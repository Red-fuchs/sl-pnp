import Foundation
import MLX
import MLXLLM
import MLXVLM
import MLXLMCommon
import MLXGuidedGeneration
import Tokenizers

struct TokBridge: MLXLMCommon.Tokenizer {
  let u: any Tokenizers.Tokenizer
  func encode(text: String, addSpecialTokens: Bool) -> [Int] { u.encode(text: text, addSpecialTokens: addSpecialTokens) }
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { u.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
  func convertTokenToId(_ t: String) -> Int? { u.convertTokenToId(t) }
  func convertIdToToken(_ i: Int) -> String? { u.convertIdToToken(i) }
  var bosToken: String? { u.bosToken }
  var eosToken: String? { u.eosToken }
  var unknownToken: String? { u.unknownToken }
  func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
    throw MLXLMCommon.TokenizerError.missingChatTemplate
  }
}
struct TokLoader: TokenizerLoader {
  func load(from d: URL) async throws -> any MLXLMCommon.Tokenizer { TokBridge(u: try await AutoTokenizer.from(modelFolder: d)) }
}

public struct GenStats { public var prefillTok = 0, prefillS = 0.0, genTok = 0, ttft = 0.0, decS = 0.0
  public var tps: Double { decS > 0 ? Double(genTok) / decS : 0 } }


/// Model + KV cache that persists across turns. `pending` = text not yet in the cache.
public final class LM {
  let ctx: ModelContext
  let gtok: GrammarTokenizer
  public let tmpl: Tmpl
  let stop: Set<Int>
  var cache: [KVCache]
  public private(set) var cached = 0
  var pending = ""
  public var dirty = false
  var gcache: [String: GrammarConstraint] = [:]
  public var loadS = 0.0
  public var last = GenStats()

  public static func load(dir: URL) async throws -> LM {
    let t = Date()
    let c = try await loadModel(from: dir, using: TokLoader())
    let lm = try LM(c, tmpl: Tmpl.detect(dir: dir))
    lm.loadS = Date().timeIntervalSince(t)
    return lm
  }
  init(_ c: ModelContext, tmpl: Tmpl) throws {
    ctx = c; self.tmpl = tmpl
    let end = c.tokenizer.convertTokenToId(tmpl.endTok) ?? 106   // gemma <turn|>=106, lfm <|im_end|>=124900; never the plain <eos>
    stop = Set([end] + (tmpl == .gemma ? [1, 50] : []))
    let v = TokenizerVocabExtractor.extractForGrammar(from: c.tokenizer)
    gtok = try GrammarTokenizer(vocab: v.vocab, vocabType: v.vocabType, eosTokenId: Int32(end))
    cache = try c.model.newCache(parameters: nil)
  }

  /// Start a fresh cache; `text` = full rendered history (no trailing generation prompt).
  public func reset(_ text: String) throws {
    cache = try ctx.model.newCache(parameters: nil); cached = 0; dirty = false; pending = text
  }
  public func append(_ t: String) { pending += t }

  func constraint(_ g: Grammar) throws -> (GrammarConstraint, Double) {
    let key = g.tag
    let t = Date()
    if let m = gcache[key] { return (try m.clone(), 0) }
    let m = try GrammarConstraint(tokenizer: gtok, structuralTag: key)
    gcache[key] = m
    return (try m.clone(), Date().timeIntervalSince(t))
  }

  public func compile(_ g: Grammar) throws -> Double { try constraint(g).1 }

  /// Feed pending + model-turn prompt, sample under grammar until end of turn. Cache then holds prompt+output; pending = tmpl.end.
  public func generate(_ g: Grammar, temp: Float = 0.7, maxTok: Int = 500, onDelta: (String) -> Void) throws -> (String, GenStats) {
    if dirty { throw SLError("cache dirty, reset needed") }
    dirty = true
    var st = GenStats()
    let (con, _) = try constraint(g)
    let t0 = Date()
    let ids = ctx.tokenizer.encode(text: pending + tmpl.gen, addSpecialTokens: false)
    pending = ""
    st.prefillTok = ids.count
    var logits = try prefill(ids)
    eval(logits)
    st.prefillS = Date().timeIntervalSince(t0)
    cached += ids.count
    var det = NaiveStreamingDetokenizer(tokenizer: ctx.tokenizer)
    var out = ""
    let t1 = Date()
    let dim = logits.shape[logits.ndim - 1]
    var n = 0
    while n < maxTok {
      let m = try con.computeMask()
      var l = logits[0..., -1, 0...]
      if m.needsApply { l = l + Self.maskArr(m, vocab: gtok.vocabSize, dim: dim) }
      let tok = Int(categorical(l * (1 / temp)).item(UInt32.self))
      if st.ttft == 0 { st.ttft = Date().timeIntervalSince(t1) }
      if stop.contains(tok) { break }
      let r = try con.commitToken(Int32(tok))
      det.append(token: tok)
      if let s = det.next() { out += s; onDelta(s) }
      n += 1
      if r.isTerminated { break }
      let o = ctx.model(LMInput.Text(tokens: MLXArray([Int32(tok)]))[text: .newAxis], cache: cache, state: nil)
      cached += 1
      logits = o.logits
      asyncEval(logits)
    }
    // final partial char
    st.genTok = n; st.decS = Date().timeIntervalSince(t1)
    if n >= maxTok { throw SLError("maxTok reached") }
    pending = tmpl.end
    dirty = false
    last = st
    return (out, st)
  }

  func prefill(_ ids: [Int]) throws -> MLXArray {
    let inp = LMInput(tokens: MLXArray(ids.map { Int32($0) }))
    switch try ctx.model.prepare(inp, cache: cache, state: nil, prefill: .init(stepSize: 512)) {
    case .tokens(let t): return ctx.model(t[text: .newAxis], cache: cache, state: nil).logits
    case .logits(let o): return o.logits
    }
  }

  static func maskArr(_ m: MaskResult, vocab: Int, dim: Int) -> MLXArray {
    var f = [Float](repeating: -Float.infinity, count: dim)
    m.mask.withUnsafeBufferPointer { b in
      let p = UnsafeRawPointer(b.baseAddress!).assumingMemoryBound(to: UInt32.self)
      for w in 0..<((min(vocab, dim) + 31) / 32) where p[w] != 0 {
        for bit in 0..<32 where (p[w] >> UInt32(bit)) & 1 == 1 { let i = w * 32 + bit; if i < dim { f[i] = 0 } }
      }
    }
    return MLXArray(f)
  }

  public func unload() { cache = []; gcache = [:]; MLX.GPU.clearCache() }
}

public struct SLError: Error, CustomStringConvertible { public let description: String; public init(_ s: String) { description = s } }
