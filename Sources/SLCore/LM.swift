import Foundation
import MLX
import MLXLLM
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

public struct GenStats { public var prefillTok = 0, prefillS = 0.0, genTok = 0, ttft = 0.0, decS = 0.0, maskS = 0.0, compileS = 0.0
  public var maskUs: Int { genTok > 0 ? Int(maskS * 1e6 / Double(genTok)) : 0 }
  public var line: String { String(format: "prefill %d tok %.2fs · gen %d tok %.2fs (%.1f tok/s) · grammar mask %d µs/tok · compile %.2fs", prefillTok, prefillS, genTok, decS, tps, maskUs, compileS) }
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
    let c = try await LLMModelFactory.shared.load(from: dir, using: TokLoader())   // text-only factory: no vision/audio tower in RAM
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

  /// GrammarConstraint has no Fork in this xgrammar: reuse one matcher per grammar and roll it back after use.
  func take(_ g: Grammar) throws -> (GrammarConstraint, String, Double) {
    let key = g.tag
    if let c = gcache.removeValue(forKey: key) { return (c, key, 0) }
    let t = Date()
    let c = try GrammarConstraint(tokenizer: gtok, structuralTag: key)
    return (c, key, Date().timeIntervalSince(t))
  }
  func giveBack(_ c: GrammarConstraint, _ key: String, committed n: Int) {
    do { if n > 0 { try c.rollback(Int32(n)) }; gcache[key] = c } catch { /* drop: recompiled next time */ }
  }

  public func compile(_ g: Grammar) throws -> Double { let (c, k, t) = try take(g); giveBack(c, k, committed: 0); return t }

  /// Feed pending + model-turn prompt, sample under grammar until end of turn. Cache then holds prompt+output; pending = end-of-turn.
  public func generate(_ g: Grammar, temp: Float = 0.7, maxTok: Int = 500, onDelta: (String) -> Void) throws -> (String, GenStats) {
    if dirty { throw SLError("cache dirty, reset needed") }
    dirty = true
    let r = try core(cache: cache, text: pending + tmpl.gen, g, temp: temp, maxTok: maxTok, onDelta: onDelta)
    pending = tmpl.end
    cached += r.added
    dirty = false
    last = r.st
    return (r.out, r.st)
  }

  /// Side generation with a throwaway cache (world-delta step): never touches the main cache or history.
  public func aux(system: String, user: String, _ g: Grammar, temp: Float = 0.2, maxTok: Int = 400) throws -> (String, GenStats) {
    let c = try ctx.model.newCache(parameters: nil)
    let text = tmpl.bos + tmpl.open("system") + system + tmpl.end + tmpl.open("user") + user + tmpl.end + tmpl.gen
    let r = try core(cache: c, text: text, g, temp: temp, maxTok: maxTok, onDelta: { _ in })
    auxLast = r.st
    return (r.out, r.st)
  }
  public var auxLast = GenStats()

  func core(cache: [KVCache], text: String, _ g: Grammar, temp: Float, maxTok: Int, onDelta: (String) -> Void) throws -> (out: String, st: GenStats, added: Int) {
    var st = GenStats()
    let (con, gkey, ct) = try take(g)
    st.compileS = ct
    var committed = 0
    defer { giveBack(con, gkey, committed: committed) }
    let t0 = Date()
    let ids = ctx.tokenizer.encode(text: text, addSpecialTokens: false)
    st.prefillTok = ids.count
    var logits = try prefill(ids, cache)
    eval(logits)
    st.prefillS = Date().timeIntervalSince(t0)
    var added = ids.count
    var det = NaiveStreamingDetokenizer(tokenizer: ctx.tokenizer)
    var out = "", gen: [Int] = []
    let t1 = Date()
    let dim = logits.shape[logits.ndim - 1]
    var n = 0
    while n < maxTok {
      let tm = Date()
      let m = try con.computeMask()
      var l = logits[0..., -1, 0...]
      if m.needsApply { l = l + maskArr(m, vocab: gtok.vocabSize, dim: dim) }
      st.maskS += Date().timeIntervalSince(tm)
      let tok = temp <= 0 ? Int(argMax(l, axis: -1).item(UInt32.self)) : Int(categorical(l * (1 / temp)).item(UInt32.self))
      if st.ttft == 0 { st.ttft = Date().timeIntervalSince(t1) }
      if stop.contains(tok) { break }
      let tc = Date()
      let r = try con.commitToken(Int32(tok))
      st.maskS += Date().timeIntervalSince(tc)
      committed += 1 + r.tokens.count
      gen.append(tok)
      det.append(token: tok)
      if let s = det.next() { out += s; onDelta(s) }
      n += 1
      // every sampled token goes through the model (also the terminating one) so the cache == rendered history
      let o = ctx.model(LMInput.Text(tokens: MLXArray([Int32(tok)]))[text: .newAxis], cache: cache, state: nil)
      added += 1
      logits = o.logits
      if r.isTerminated { eval(logits); break }
      asyncEval(logits)
    }
    let full = ctx.tokenizer.decode(tokenIds: gen)
    if full.count > out.count, full.hasPrefix(out) { let rest = String(full.dropFirst(out.count)); onDelta(rest); out = full }
    st.genTok = n; st.decS = Date().timeIntervalSince(t1)
    if n >= maxTok { throw SLError("maxTok reached") }
    return (out, st, added)
  }

  func prefill(_ ids: [Int], _ cache: [KVCache]) throws -> MLXArray {
    let inp = LMInput(tokens: MLXArray(ids.map { Int32($0) }))
    switch try ctx.model.prepare(inp, cache: cache, state: nil, prefill: .init(stepSize: 512)) {
    case .tokens(let t): return ctx.model(t[text: .newAxis], cache: cache, state: nil).logits
    case .logits(let o): return o.logits
    }
  }

  var maskBuf: [Float] = []
  func maskArr(_ m: MaskResult, vocab: Int, dim: Int) -> MLXArray {
    if maskBuf.count != dim { maskBuf = [Float](repeating: -Float.infinity, count: dim) }
    var touched: [Int] = []
    m.mask.withUnsafeBufferPointer { b in
      let p = UnsafeRawPointer(b.baseAddress!).assumingMemoryBound(to: UInt32.self)
      for w in 0..<((min(vocab, dim) + 31) / 32) where p[w] != 0 { touched.append(w) }
      maskBuf.withUnsafeMutableBufferPointer { f in
        for i in 0..<dim { f[i] = -Float.infinity }
        for w in touched { let x = p[w]; for bit in 0..<32 where (x >> UInt32(bit)) & 1 == 1 { let i = w * 32 + bit; if i < dim { f[i] = 0 } } }
      }
    }
    return MLXArray(maskBuf)
  }

  public func unload() { cache = []; gcache = [:]; MLX.GPU.clearCache() }
}

public struct SLError: Error, CustomStringConvertible { public let description: String; public init(_ s: String) { description = s } }
