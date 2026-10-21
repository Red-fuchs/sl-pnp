import Foundation

/// itemtest branch only: reads JSONL {id, frame}, asks Gemma (lm.aux + grammar) for "Name:/Beschreibung:", writes JSONL with timing.
public func runItemTest(lm: LM, inPath: String, outPath: String, temp: Float) throws {
  let sys = "Du bist Spielleiter eines düsteren Solo-Rollenspiels und deutest Zufallsgegenstände auf Deutsch. Du bekommst einen festen Rahmen (Art, Seltenheit, Material, Wirkung) und ein Wortpaar als Bedeutungsanstoß. Erfinde einen kurzen Namen und eine Beschreibung in 1-2 Sätzen. Die Beschreibung darf nur Aussehen, Herkunft und Stimmung zeigen: keine zusätzlichen Kräfte, keine neuen Zahlen, keine Preise. Die beiden Wörter des Wortpaars nie wörtlich nennen, sondern als Bild oder Geschichte deuten. Antworte genau im Format."
  let g = Grammar(.seq([.s("Name: "), .re(#"[A-ZÄÖÜ][a-zäöüß]{2,}( [A-Za-zÄÖÜäöüß]{2,}){0,5}"#), .s("\nBeschreibung: "), .re(Gr.shortPatternPublic)]))
  let lines = try String(contentsOfFile: inPath, encoding: .utf8).split(separator: "\n")
  var out = ""
  for l in lines {
    guard let o = try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let frame = o["frame"] as? String else { continue }
    let user = "Rahmen:\n\(frame)\nAufgabe: Name und Beschreibung des Gegenstands.\nAusgabe:"
    let t0 = Date()
    var txt = "", st = GenStats(), err = ""
    do { (txt, st) = try lm.aux(system: sys, user: user, g, temp: temp, maxTok: 220) } catch { err = "\(error)" }
    let rec: [String: Any] = ["id": o["id"] ?? "", "frame": frame, "out": txt, "err": err, "secs": Date().timeIntervalSince(t0), "genTok": st.genTok, "tps": st.tps, "prefillTok": st.prefillTok, "prefillS": st.prefillS]
    out += String(decoding: try JSONSerialization.data(withJSONObject: rec, options: [.withoutEscapingSlashes]), as: UTF8.self) + "\n"
    FileHandle.standardError.write(Data("item \(o["id"] ?? ""): \(String(format: "%.1f", Date().timeIntervalSince(t0))) s\n".utf8))
  }
  try out.write(toFile: outPath, atomically: true, encoding: .utf8)
}
