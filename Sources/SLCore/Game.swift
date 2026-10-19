import Foundation
import Schicksal

public enum Out {
  case gate(String)                 // head/gate line (debug)
  case delta(String)                // streamed narration
  case tool(String, J, J)           // name, args, result
  case event(String)                // ⚡ line
  case end                          // narration finished
  case info(String)
}

public func wordsText(_ w: J) -> String {
  (w.arr ?? []).map { ($0.arr ?? []).compactMap(\.str).joined(separator: " + ") }.filter { !$0.isEmpty }.joined(separator: " | ")
}
public func evInfo(_ tool: String, _ r: J) -> EvInfo? {
  func from(_ e: J) -> EvInfo? {
    guard let d = e["dir"].str else { return nil }
    let w = wordsText(e["words"]); if w.isEmpty { return nil }
    return EvInfo(head: d + (e["target"]["name"].str.map { " (\($0))" } ?? ""), words: w)
  }
  switch tool {
  case "ask_oracle": return from(r["event"])
  case "random_event": return from(r)
  case "start_scene":
    if r["outcome"].str == "bruch" { return from(r["event"]) }
    if r["outcome"].str == "variiert", let ms = r["mut"].arr, !ms.isEmpty {
      let h = ms.map { "\($0["op"].str ?? "") \($0["el"].str ?? "")" }.joined(separator: ", ")
      let w = ms.map { ($0["words"].arr ?? []).compactMap(\.str).joined(separator: " + ") }.joined(separator: " | ")
      return EvInfo(head: "szene_variiert (\(h))", words: w)
    }
    return nil
  default: return nil
  }
}
func evShow(_ e: EvInfo) -> String { "\(e.head): \(e.words)" }

public final class Game {
  public let eng: Engine
  public let lm: LM
  public var msgs: [Msg]
  public var setting: String
  public var figur: String?
  public var quiet = 0                 // consecutive turns without an oracle question in an open scene
  var recap = ""
  public var sys: String { SYS + figurBlock(figur) + recap }
  public var out: (Out) -> Void = { _ in }
  public var debug = false
  public var temp: Float = 0.7
  public var lastRolls: [(String, J)] = []
  public var maxCtx = 14000
  public var onMsg: (Msg) -> Void = { _ in }

  public init(eng: Engine, lm: LM, setting: String, msgs: [Msg] = [], figur: String? = nil, quiet: Int = 0) {
    self.eng = eng; self.lm = lm; self.setting = setting; self.msgs = msgs; self.figur = figur; self.quiet = quiet
  }

  public func syncCache() throws { try lm.reset(lm.tmpl.render(sys: sys, FEW + msgs)) }

  func compact() throws {
    let rc = eng.st.journal.filter { $0["tool"].str == "end_scene" }.suffix(12).compactMap { $0["in"]["summary"].str }.joined(separator: " ")
    var keep = Array(msgs.suffix(24)); while let f = keep.first, f.role == "model" || f.text.hasPrefix("[Orakel]") { keep.removeFirst() }
    msgs = keep
    recap = rc.isEmpty ? "" : "\n\nBisheriger Verlauf (Journal): " + rc
    out(.info("Kontext verdichtet"))
    try syncCache()
  }

  func push(_ m: Msg) { msgs.append(m); onMsg(m); lm.append(lm.tmpl.turn(m)) }

  /// One player turn. `pre`: already-rolled oracle result (from /frage) -> skips the gate head.
  public func turn(_ player: String, pre: J? = nil, forceEnd: Bool = false) throws {
    if lm.cached > maxCtx { try compact() }
    let firstTurn = msgs.isEmpty
    push(.u(msgs.isEmpty ? "Setting: \(setting). \(player)" : player))   // scene 1 starts with the first player turn (head_scene -> start_scene first:true)
    var gate = Gate(); gate.figurLine = firstTurn && figur == nil; gate.mustAsk = quiet >= 1; gate.head = pre == nil; gate.forceEnd = forceEnd; gate.endNarr = forceEnd
    if let p = pre { gate.ans = p["answer"].str; gate.deut = evInfo("ask_oracle", p) != nil }
    var calls = 0, asked = false, figurChanged = false
    var done = false
    for _ in 0..<14 {
      gate.open = eng.st.open; gate.asks = eng.st.q; gate.calls = calls
      var line = "", narr = false
      let flush = { (final: Bool) in
        if !narr { self.out(.gate(line)) }
        line = ""; narr = false
      }
      let gm = Gr.grammar(gate)
      var txt = ""
      for attempt in 0..<3 {
        line = ""; narr = false
        do {
          (txt, _) = try lm.generate(gm, temp: attempt == 0 ? temp : 0.4, maxTok: 600) { d in
            for ch in d {
              if ch == "\n" { flush(false); continue }
              line.append(ch)
              if narr { self.out(.delta(String(ch))) }
              else if !isGatePrefix(line) && !line.hasPrefix("<") { narr = true; self.out(.delta(line)) }
            }
          }
          break
        } catch let e as SLError where e.description.contains("maxTok") && attempt < 2 {
          out(.info("Ausgabe zu lang – neuer Versuch")); if narr { out(.end) }
          try syncCache()   // drop the half-generated tokens from the cache
        }
      }
      if debug { out(.info("· " + lm.last.line)) }
      if narr { out(.end) } else if !line.isEmpty { out(.gate(line)) }
      if gate.figurLine, let l = txt.split(separator: "\n").first(where: { $0.hasPrefix("Spielfigur: ") }) {
        let f = String(l.dropFirst(12)).trimmingCharacters(in: .whitespaces)
        if f != "-" && !f.isEmpty { figur = groundedFigur(f, player); figurChanged = true }
      }
      gate.figurLine = false
      msgs.append(.m(txt)); onMsg(.m(txt))
      if let g = txt.split(separator: "\n").first(where: { $0.hasPrefix("Ereignis: ") }), debug { out(.info(String(g))) }
      guard let (name, args) = parseCall(txt, firstScene: eng.st.scene == 0) else { done = true; break }
      let res = eng.call(name, args)
      calls += 1
      if name == "ask_oracle" { asked = true }
      if name == "start_scene" || name == "end_scene" { quiet = 0 }
      out(.tool(name, args, res))
      if let e = evInfo(name, res) { out(.event(evShow(e))) }
      var fb = fmtResult(name, res)
      if evInfo(name, res) != nil, !(eng.st.akteure.isEmpty && eng.st.straenge.isEmpty) { fb += "\n" + fmtKnown(eng.st.akteure.map(\.name), eng.st.straenge.map(\.name)) }
      gate.head = false; gate.forceEnd = false
      let ok = res["error"].isNull
      gate.ans = ok && name == "ask_oracle" ? res["answer"].str : nil
      gate.deut = ok && evInfo(name, res) != nil
      if !ok { gate.head = true }
      push(.u(fb))
    }
    if !done { out(.info("Aufruflimit")) }
    if eng.st.open { quiet = asked ? 0 : quiet + 1 } else { quiet = 0 }
    if figurChanged { try syncCache() }   // pinned character changes the system prompt -> rebuild the cache once
  }
}

/// Parse a step's text: last line `<tool>{json}</tool>` -> (name, args); for ask_oracle q is copied from the preceding "Frage:" line.
public func parseCall(_ txt: String, firstScene: Bool = false) -> (String, J)? {
  let lines = txt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard let last = lines.last, last.hasPrefix("<"), let m = last.range(of: #"^<(\w+)>(.*)</\1>$"#, options: .regularExpression) else { return nil }
  let s = String(last[m])
  let name = String(s.dropFirst().prefix { $0 != ">" })
  let js = String(s.dropFirst(name.count + 2).dropLast(name.count + 3))
  var args = (try? J.parse(js)) ?? .obj([:])
  if name == "start_scene", firstScene, var o = args.obj { o["first"] = true; args = .obj(o) }
  if name == "ask_oracle", var o = args.obj {
    o["q"] = .str(lines.last { $0.hasPrefix("Frage: ") }.map { String($0.dropFirst(7)) } ?? "?"); args = .obj(o)
  }
  return (name, clip(args))
}

public struct EvInfo: Equatable { public var head: String, words: String
  public init(head: String, words: String) { self.head = head; self.words = words } }

/// Engine maxLength limits (tools.json) enforced by clipping instead of grammar (bounded repeats blow up xgrammar compile time).
func clip(_ a: J, _ limits: [String: Int] = ["q": 200, "expect": 300, "summary": 400, "why": 120, "aktivitaet": 80, "beteiligte": 80, "objekt": 80, "ort": 80, "stimmung": 40, "name": 60]) -> J {
  guard let o = a.obj else { return a }
  return .obj(o.reduce(into: [:]) { r, kv in
    if let s = kv.value.str, let m = limits[kv.key] { r[kv.key] = .str(String(s.prefix(m))) } else { r[kv.key] = clip(kv.value, limits) }
  })
}

let gatePrefixes = ["Spielfigur: ", "Erwartung: ", "Ortswechsel/Zeitsprung: ", "Frage: ", "Werkzeug: ", "Antwort: ", "Deutung: "]
/// true while a partial line could still become a gate line (narration never contains ":" and never starts like a gate label)
public func isGatePrefix(_ l: String) -> Bool { gatePrefixes.contains { $0.hasPrefix(l) || l.hasPrefix($0) } }

/// The model's "Spielfigur:" line is only trusted if it is grounded in the player's own words (few-shot bleed: it once answered "Matrose").
/// Otherwise fall back to the player's text itself (cut at ~140 chars, word boundary).
func groundedFigur(_ f: String, _ player: String) -> String {
  let p = player.lowercased()
  let ok = f.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 4 }.contains { p.contains($0.prefix(5)) }
  if ok { return f }
  var t = player.trimmingCharacters(in: .whitespacesAndNewlines)
  if t.count > 140 { t = String(t.prefix(140)); if let i = t.lastIndex(of: " ") { t = String(t[..<i]) } }
  return t
}
