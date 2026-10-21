import Foundation

public struct ProbeReq {
  public let id: String, speaker: String, pillar: String, difficulty: Int, reason: String, timeout: Double
  public var json: [String: Any] { ["speaker": speaker, "pillar": pillar, "difficulty": difficulty, "reason": reason, "id": id, "timeout": timeout] }
}

/// "Players roll in Foundry": a risky action of a Foundry player opens a pending probe; the turn blocks until the player's roll arrives
/// (/rollresult or /roll with the id), the GM hands it to sl, or the timeout passes. Late rolls with a closed id are refused (stale).
public final class ProbeBroker: @unchecked Sendable {
  public enum Outcome { case player(Check), auto, timeout }
  final class Slot { let req: ProbeReq; let sem = DispatchSemaphore(value: 0); var check: Check?; var auto = false; init(_ r: ProbeReq) { req = r } }
  let lock = NSLock()
  var slots: [String: Slot] = [:]
  var closed: [String: String] = [:]      // id -> how it ended (player | sl | timeout)
  var n = 0
  public init() {}
  public func open(speaker: String, pillar: String, difficulty: Int, reason: String, timeout: Double) -> ProbeReq {
    lock.lock(); defer { lock.unlock() }
    n += 1; let r = ProbeReq(id: "p\(n)-\(Int.random(in: 1000...9999))", speaker: speaker, pillar: pillar, difficulty: difficulty, reason: reason, timeout: timeout)
    slots[r.id] = Slot(r); return r
  }
  public func request(_ id: String) -> ProbeReq? { lock.lock(); defer { lock.unlock() }; return slots[id]?.req }
  public var pendingIDs: [String] { lock.lock(); defer { lock.unlock() }; return slots.keys.sorted() }
  public func closedHow(_ id: String) -> String? { lock.lock(); defer { lock.unlock() }; return closed[id] }
  /// delivers the player's roll; false when the probe is not pending any more (timed out / taken over by sl)
  @discardableResult public func resolve(_ id: String, _ c: Check) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let s = slots[id], s.check == nil, !s.auto else { return false }
    s.check = c; s.sem.signal(); return true
  }
  /// GM button "sl würfeln lassen"
  @discardableResult public func forceAuto(_ id: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let s = slots[id], s.check == nil, !s.auto else { return false }
    s.auto = true; s.sem.signal(); return true
  }
  public func wait(_ id: String, timeout: Double) -> Outcome {
    lock.lock(); let s = slots[id]; lock.unlock()
    guard let s else { return .timeout }
    let got = s.sem.wait(timeout: .now() + max(0, timeout)) == .success
    lock.lock(); defer { lock.unlock() }
    slots[id] = nil
    if let c = s.check { closed[id] = "player"; return .player(c) }
    if s.auto { closed[id] = "sl"; return .auto }
    closed[id] = "timeout"; _ = got; return .timeout
  }
}
