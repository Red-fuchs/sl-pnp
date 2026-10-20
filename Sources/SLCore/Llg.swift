import Foundation
import CLlguidance

public struct LlgError: Error, CustomStringConvertible { public let description: String }

/// tokenize_fn target: bytes -> ids with the host tokenizer (swift-transformers). llg_tokenize_bytes' greedy fallback does NOT match BPE ids.
final class TokenizeBox {
  let f: ([UInt8]) -> [UInt32]; let lock = NSLock()
  init(_ f: @escaping ([UInt8]) -> [UInt32]) { self.f = f }
}
private let tokenizeCB: LlgTokenizeFn = { ud, bytes, n, out, outLen in
  let box = Unmanaged<TokenizeBox>.fromOpaque(ud!).takeUnretainedValue()
  box.lock.lock(); defer { box.lock.unlock() }
  let ids = box.f(n == 0 ? [] : Array(UnsafeBufferPointer(start: bytes, count: n)))
  if let out { for (i, id) in ids.prefix(outLen).enumerated() { out[i] = id } }
  return ids.count
}

/// Owns the LlgTokenizer (vocab trie + slicer). One per model, ~0.7 s to build. The vocab comes from tokenizer.json (ordered; never build it
/// from a [String: Int]: a Swift Dictionary collapses canonically equivalent keys and loses tokens).
public final class LlgTok {
  let p: OpaquePointer
  public let vocab: Int
  let eosSet: Set<UInt32>
  let box: TokenizeBox
  /// `encode`: host tokenizer on text without special-token insertion (bytes that are not valid UTF-8 arrive lossy, `tokenize_assumes_string`)
  public init(tokenizerJSON path: String, vocab: Int, eos: UInt32, extraEos: [UInt32], encode: @escaping (String) -> [Int]) throws {
    guard let js = try? String(contentsOfFile: path, encoding: .utf8) else { throw LlgError(description: "cannot read \(path)") }
    let box = TokenizeBox { b in encode(String(decoding: b, as: UTF8.self)).map { UInt32($0) } }
    self.box = box
    var err = [CChar](repeating: 0, count: 1024)
    var extra = extraEos
    let ud = Unmanaged.passUnretained(box).toOpaque()
    let p: OpaquePointer? = js.withCString { jp in extra.withUnsafeMutableBufferPointer { eb in
      var i = LlgTokenizerInitV2()
      i.struct_size = MemoryLayout<LlgTokenizerInitV2>.size
      i.vocab_size = UInt32(vocab); i.tok_eos = eos; i.tokenizer_json = jp
      i.tokenize_fn = tokenizeCB; i.tokenize_user_data = UnsafeRawPointer(ud); i.tokenize_assumes_string = true
      i.tok_eos_extra = UnsafePointer(eb.baseAddress); i.tok_eos_extra_count = UInt32(eb.count)
      return llg_new_tokenizer_v2(&i, &err, err.count)
    } }
    guard let p else { throw LlgError(description: String(cString: err)) }
    self.p = p; self.vocab = vocab; eosSet = Set([eos] + extraEos)
  }
  /// ids via llg's own entry point (goes through the host callback)
  public func tokenize(_ s: String) -> [UInt32] {
    let b = Array(s.utf8); var out = [UInt32](repeating: 0, count: b.count + 8)
    let n = b.withUnsafeBufferPointer { llg_tokenize_bytes(p, $0.baseAddress, $0.count, &out, out.count) }
    return Array(out.prefix(min(n, out.count)))
  }
  deinit { llg_free_tokenizer(p) }
}

/// llguidance matcher behind `Constraint`. Rollback and clone are native.
public final class LlgConstraint: Constraint, @unchecked Sendable {
  var m: OpaquePointer
  let tok: LlgTok
  let words: Int
  public init(tok: LlgTok, lark: String) throws {
    self.tok = tok; words = (tok.vocab + 31) / 32
    var ci = LlgConstraintInit()
    llg_constraint_init_set_defaults(&ci, tok.p)
    ci.backtrack_ok = false; ci.ff_tokens_ok = false
    m = llg_new_matcher(&ci, "lark", lark)
    if llg_matcher_is_error(m) { let e = String(cString: llg_matcher_get_error(m)); llg_free_matcher(m); throw LlgError(description: e) }
  }
  init(_ m: OpaquePointer, _ tok: LlgTok) { self.m = m; self.tok = tok; words = (tok.vocab + 31) / 32 }
  deinit { llg_free_matcher(m) }
  func err() -> LlgError { LlgError(description: String(cString: llg_matcher_get_error(m))) }

  public func computeMask() throws -> CMask {
    guard llg_matcher_compute_mask(m) == 0, let p = llg_matcher_get_mask(m) else { throw err() }
    let mask = [Int32](unsafeUninitializedCapacity: words) { b, n in
      p.withMemoryRebound(to: Int32.self, capacity: words) { b.baseAddress!.update(from: $0, count: words) }; n = words }
    return CMask(mask: mask, isTerminated: llg_matcher_is_stopped(m), needsApply: true)
  }
  public func commit(_ id: Int32) throws -> CCommit {
    // grammar complete -> llguidance auto-stops; the EOS that the mask then offers is a no-op (xgrammar needs it committed)
    if llg_matcher_is_stopped(m) && tok.eosSet.contains(UInt32(bitPattern: id)) { return CCommit(tokens: [], isTerminated: true) }
    guard llg_matcher_consume_token(m, UInt32(bitPattern: id)) == 0 else { throw err() }
    return CCommit(tokens: [], isTerminated: llg_matcher_is_stopped(m))
  }
  public func rollback(_ n: Int) throws { if n > 0, llg_matcher_rollback(m, n) != 0 { throw err() } }
  public func clone() throws -> Constraint { LlgConstraint(llg_clone_matcher(m), tok) }
  public func ffTokens(max: Int) -> [Int32] {
    var out = [UInt32](repeating: 0, count: max)
    let n = llg_matcher_compute_ff_tokens(m, &out, max)
    return n > 0 ? out.prefix(Int(n)).map { Int32(bitPattern: $0) } : []
  }
}
