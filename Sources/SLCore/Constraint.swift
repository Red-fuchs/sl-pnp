import Foundation
import MLXGuidedGeneration

/// LSB-first uint32 bitmask over the vocab (bit i of word w = token w*32+i); same layout for both engines.
public struct CMask { public let mask: [Int32]; public let isTerminated: Bool; public let needsApply: Bool }
public struct CCommit { public let tokens: [Int32]; public let isTerminated: Bool }

/// Grammar engine behind the decode loop: xgrammar (`XgConstraint`) or llguidance (`LlgConstraint`).
public protocol Constraint: AnyObject {
  func computeMask() throws -> CMask
  /// advance by one sampled token; `tokens` = extra tokens the engine consumed itself (xgrammar fast-forward), they count for rollback
  func commit(_ id: Int32) throws -> CCommit
  /// undo the last n committed tokens (incl. FF tokens)
  func rollback(_ n: Int) throws
  func clone() throws -> Constraint
  /// forced tokens at the current state, NOT consumed (llguidance); the caller may feed them without sampling, then `commit` each
  func ffTokens(max: Int) -> [Int32]
}

public enum GrammarEngine: String { case xg, llg }

/// xgrammar behind `Constraint`. No fork in 0.1.30 -> `clone` unsupported (LM keeps the take/giveBack rollback cache for it).
public final class XgConstraint: Constraint {
  let c: GrammarConstraint
  public init(tokenizer: GrammarTokenizer, structuralTag: String) throws { c = try GrammarConstraint(tokenizer: tokenizer, structuralTag: structuralTag) }
  public func computeMask() throws -> CMask { let r = try c.computeMask(); return CMask(mask: r.mask, isTerminated: r.isTerminated, needsApply: r.needsApply) }
  public func commit(_ id: Int32) throws -> CCommit { let r = try c.commitToken(id); return CCommit(tokens: r.tokens, isTerminated: r.isTerminated) }
  public func rollback(_ n: Int) throws { if n > 0 { try c.rollback(Int32(n)) } }
  public func clone() throws -> Constraint { throw SLError("xgrammar 0.1.30 has no fork") }
  public func ffTokens(max: Int) -> [Int32] { [] }
}
