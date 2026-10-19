import Foundation
import Schicksal

// Port of prompt.py fmt_*: oracle results reach the model as short German text, never JSON/rng/step/roll numbers.
func firstWords(_ w: J) -> String {
  guard let a = w.arr, let f = a.first else { return "" }
  if f.str != nil { return a.compactMap(\.str).joined(separator: " + ") }  // flat pair
  return (f.arr ?? []).compactMap(\.str).joined(separator: " + ")
}
public func fmtEvent(_ ev: J) -> String {
  guard let d = ev["dir"].str else { return "" }
  let t = ev["target"]["name"].str.map { " (\($0))" } ?? ""
  return "Ereignis: \(d)\(t) – \(DIRS[d] ?? d). Wörter: \(firstWords(ev["words"]))"
}
public func fmtResult(_ tool: String, _ r: J) -> String {
  if let e = r["error"].str { return "[Orakel] Fehler: \(e)" }
  switch tool {
  case "ask_oracle":
    var s = "[Orakel] Antwort: \(r["answer"].str ?? "?")"
    if !r["event"].isNull { s += "\n[Orakel] " + fmtEvent(r["event"]) }
    return s
  case "start_scene":
    let o = ["erwartet": "wie erwartet", "variiert": "anders als erwartet", "bruch": "kippt"][r["outcome"].str ?? ""] ?? "wie erwartet"
    var s = "[Orakel] Szene \(r["scene"].int ?? 0) beginnt \(o)."
    for m in r["mut"].arr ?? [] { s += "\n[Orakel] Änderung: \(m["el"].str ?? "") \(m["op"].str ?? "") – Wörter: \(firstWords(m["words"]))" }
    if !r["event"].isNull { s += "\n[Orakel] " + fmtEvent(r["event"]) }
    return s
  case "end_scene":
    let d = (r["s"].int ?? 0) - (r["s_before"].int ?? r["s"].int ?? 0)
    return "[Orakel] Szene beendet. Die Lage wird \(d > 0 ? "unruhiger" : d < 0 ? "ruhiger" : "nicht anders")."
  case "random_event": return "[Orakel] " + fmtEvent(r)
  default: return "[Orakel] " + r.json
  }
}
public func fmtKnown(_ ak: [String], _ st: [String]) -> String {
  "[Bekannt] Figuren: \(ak.isEmpty ? "-" : ak.joined(separator: ", ")). Stränge: \(st.isEmpty ? "-" : st.joined(separator: ", "))."
}
