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
  var ctx: ModelContext!                 // nil while unloaded (idle): weights are only in RAM while the gpu-run slot is held
  let tok: any MLXLMCommon.Tokenizer
  let dir: URL
  let gtok: GrammarTokenizer
  public let tmpl: Tmpl
  let stop: Set<Int>
  var cache: [KVCache] = []
  public private(set) var cached = 0
  var pending = ""
  public var dirty = false
  public var stale = false               // model was unloaded: the KV cache must be rebuilt from the history
  var gcache: [String: GrammarConstraint] = [:]
  public var loadS = 0.0
  public var last = GenStats()
  public var loaded: Bool { ctx != nil }
  /// hooks: acquire a GPU slot before loading (blocking, reports progress), release after unloading, user-visible notices
  public var onAcquire: ((@escaping (String) -> Void) throws -> Void)?
  public var onRelease: (() -> Void)?
  public var notify: (String) -> Void = { _ in }

  /// Light: tokenizer + grammar vocab only (no weights). Call ensureLoaded() before generating.
  public static func make(dir: URL) async throws -> LM {
    let tok = try await TokLoader().load(from: dir)
    return try LM(tok, dir: dir, tmpl: Tmpl.detect(dir: dir))
  }
  init(_ t: any MLXLMCommon.Tokenizer, dir: URL, tmpl: Tmpl) throws {
    tok = t; self.dir = dir; self.tmpl = tmpl
    let end = t.convertTokenToId(tmpl.endTok) ?? 106   // gemma <turn|>=106, lfm <|im_end|>=124900; never the plain <eos>
    stop = Set([end] + (tmpl == .gemma ? [1, 50] : []))
    let v = TokenizerVocabExtractor.extractForGrammar(from: t)
    gtok = try GrammarTokenizer(vocab: v.vocab, vocabType: v.vocabType, eosTokenId: Int32(end))
  }

  /// Loads the weights (after acquiring a GPU slot if a lease hook is set). Blocking.
  public func ensureLoaded() throws {
    if ctx != nil { return }
    try onAcquire?(notify)
    notify("Lade Modell …")
    let t = Date(), d = dir
    nonisolated(unsafe) var res: Result<ModelContext, Error> = .failure(SLError("load"))
    let sem = DispatchSemaphore(value: 0)
    Task { do { res = .success(try await LLMModelFactory.shared.load(from: d, using: TokLoader())) } catch { res = .failure(error) }; sem.signal() }   // text-only factory: no vision/audio tower
    sem.wait()
    do { ctx = try res.get() } catch { onRelease?(); throw error }
    loadS = Date().timeIntervalSince(t)
    notify(String(format: "Modell geladen (%.1f s)", loadS))
  }

  /// Frees the weights and the KV cache and gives the GPU slot back.
  public func unloadModel() {
    let was = ctx != nil
    cache = []; gcache = [:]; ctx = nil; cached = 0; stale = true; dirty = false; contentIds = [:]
    MLX.GPU.clearCache()
    if was { onRelease?() }
  }
  public func unload() { unloadModel() }

  /// Start a fresh cache (created lazily); `text` = full rendered history (no trailing generation prompt).
  public func reset(_ text: String) throws {
    cache = []; cached = 0; dirty = false; pending = text; recent = []; stale = false
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
    try ensureLoaded()
    dirty = true
    if cache.isEmpty { cache = try ctx.model.newCache(parameters: nil) }
    let r = try core(cache: cache, text: pending + tmpl.gen, g, temp: temp, maxTok: maxTok, onDelta: onDelta)
    pending = tmpl.end
    cached += r.added
    dirty = false
    last = r.st
    return (r.out, r.st)
  }

  /// Side generation with a throwaway cache (world-delta step): never touches the main cache or history.
  public func aux(system: String, user: String, _ g: Grammar, temp: Float = 0.2, maxTok: Int = 400) throws -> (String, GenStats) {
    try ensureLoaded()
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
    let ids = tok.encode(text: text, addSpecialTokens: false)
    st.prefillTok = ids.count
    var logits = try prefill(ids, cache)
    eval(logits)
    st.prefillS = Date().timeIntervalSince(t0)
    var added = ids.count
    var det = NaiveStreamingDetokenizer(tokenizer: tok)
    var out = "", gen: [Int] = []
    let t1 = Date()
    let dim = logits.shape[logits.ndim - 1]
    var n = 0
    while n < maxTok {
      let tm = Date()
      let m = try con.computeMask()
      var l = logits[0..., -1, 0...]
      if m.needsApply {
        // repetition penalty on content words, only while the grammar leaves free text (narration), also against the previous turn ("Die Treppe" x3)
        let free = m.mask.reduce(0) { $0 + UInt32(bitPattern: $1).nonzeroBitCount } > 3000
        l = l + maskArr(m, vocab: gtok.vocabSize, dim: dim, pen: free ? Set(recent.filter(isContent)) : [])
      }
      st.maskS += Date().timeIntervalSince(tm)
      let tok = temp <= 0 ? Int(argMax(l, axis: -1).item(UInt32.self)) : Int(categorical(l * (1 / temp)).item(UInt32.self))
      if st.ttft == 0 { st.ttft = Date().timeIntervalSince(t1) }
      if stop.contains(tok) { break }
      let tc = Date()
      let r = try con.commitToken(Int32(tok))
      st.maskS += Date().timeIntervalSince(tc)
      committed += 1 + r.tokens.count
      gen.append(tok)
      recent.append(tok); if recent.count > 160 { recent.removeFirst(recent.count - 160) }
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
    let full = tok.decode(tokenIds: gen)
    if full.count > out.count, full.hasPrefix(out) { let rest = String(full.dropFirst(out.count)); onDelta(rest); out = full }
    st.genTok = n; st.decS = Date().timeIntervalSince(t1)
    if n >= maxTok { throw TruncatedError(partial: out) }
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
  var recent: [Int] = []                // last generated tokens (cross-turn), for the repetition penalty on free text
  var contentIds: [Int: Bool] = [:]
  func isContent(_ id: Int) -> Bool {
    if let b = contentIds[id] { return b }
    let t = tok.convertIdToToken(id) ?? ""
    let b = t.filter(\.isLetter).count >= 5; contentIds[id] = b; return b
  }
  func maskArr(_ m: MaskResult, vocab: Int, dim: Int, pen: Set<Int> = []) -> MLXArray {
    if maskBuf.count != dim { maskBuf = [Float](repeating: -Float.infinity, count: dim) }
    var touched: [Int] = []
    m.mask.withUnsafeBufferPointer { b in
      let p = UnsafeRawPointer(b.baseAddress!).assumingMemoryBound(to: UInt32.self)
      for w in 0..<((min(vocab, dim) + 31) / 32) where p[w] != 0 { touched.append(w) }
      maskBuf.withUnsafeMutableBufferPointer { f in
        for i in 0..<dim { f[i] = -Float.infinity }
        for w in touched { let x = p[w]; for bit in 0..<32 where (x >> UInt32(bit)) & 1 == 1 { let i = w * 32 + bit; if i < dim { f[i] = pen.contains(i) ? -1.5 : 0 } } }
      }
    }
    return MLXArray(maskBuf)
  }

}

/// Generation hit maxTok: the partial text is kept so a finished narration can be salvaged (cut the tail, not the story).
public struct TruncatedError: Error, CustomStringConvertible { public let partial: String; public var description: String { "maxTok reached" } }

public struct SLError: Error, CustomStringConvertible { public let description: String; public init(_ s: String) { description = s } }
