import Foundation
import Schicksal

/// Scene-end tension step (no d6 brake): ±1 always, ±2 for a clearly tipped scene.
/// control == false (see tensionControl) -> +1, +2 if NEIN >= 3 and no JA, or a random event together with a failed check.
/// control == true -> -1, -2 if JA >= 3 and no NEIN, no event, no failed check.
public func tensionStep(control: Bool, nein: Int, ja: Int, events: Int, fails: Int) -> Int {
  if !control { return (nein >= 3 && ja == 0) || (events >= 1 && fails >= 1) ? 2 : 1 }
  return ja >= 3 && nein == 0 && events == 0 && fails == 0 ? -2 : -1
}

/// end_scene without the engine's d6 brake (policy "elastisch": a move away from 5 only on a roll of 1-4) and with the +-2 step applied on top
public func endSceneTension(_ eng: Engine, _ args: J, step: Int) -> J {
  if eng.st.policy == "elastisch" { _ = eng.call("session", ["op": "policy", "policy": "kontrolle"]) }
  var res = eng.call("end_scene", args)
  if abs(step) == 2, res["error"].isNull, let b = res["s_before"].int, let s0 = res["s"].int, (s0 - b) * step > 0, !["fest", "zufall", "gegen"].contains(eng.st.policy) {
    let ns = clampTension(s0 + step / 2)
    if ns != s0 { _ = eng.call("session", ["op": "set_tension", "s": .int(ns)]); if case .obj(var o) = res { o["s"] = .int(ns); res = .obj(o) } }
  }
  return res
}

public func clampTension(_ s: Int) -> Int { max(1, min(9, s)) }

/// "/spannung" argument: "+N" / "-N" shift, "N" absolute; nil = unparsable
public func parseTension(_ a: String, cur: Int) -> Int? {
  let t = a.trimmingCharacters(in: .whitespaces)
  guard let f = t.first, let n = Int(t.hasPrefix("+") ? String(t.dropFirst()) : t), t.count <= 4 else { return nil }
  return clampTension(f == "+" || f == "-" ? cur + n : n)
}

/// hidden narrator cue for a tension change (no number, so the narrator cannot recite it)
public func tensionCue(from a: Int, to b: Int) -> String? {
  if b > a { return "Die Spannung steigt: erzähle dichter, bedrohlicher und mit mehr Druck, kleine Vorzeichen von Gefahr. Nenne die Spannung nie ausdrücklich." }
  if b < a { return "Die Spannung sinkt: erzähle ruhiger und gelassener, lass Raum zum Durchatmen. Nenne die Spannung nie ausdrücklich." }
  return nil
}

extension Game {
  /// GM override at any time; clamped to 1...9, queues the narrator cue on change
  @discardableResult
  public func setTension(_ arg: String) -> (ok: Bool, before: Int, now: Int) {
    let before = eng.st.s
    guard let n = parseTension(arg, cur: before) else { return (false, before, before) }
    if n != before { _ = eng.call("session", ["op": "set_tension", "s": .int(n)]); if let c = tensionCue(from: before, to: n) { pendingRegie.append(c) } }
    return (true, before, n)
  }
}
