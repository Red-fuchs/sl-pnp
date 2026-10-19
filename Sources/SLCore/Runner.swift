import Foundation
import Schicksal

let oddsName = ["fast unmöglich", "sehr unwahrscheinlich", "unwahrscheinlich", "offen", "wahrscheinlich", "sehr wahrscheinlich", "fast sicher"]
public func oddsText(_ o: Int) -> String { oddsName[max(0, min(6, o + 3))] }

public func describe(_ name: String, _ a: J, _ r: J) -> String {
  if let e = r["error"].str { return "⚀ \(name): Fehler: \(e)" }
  switch name {
  case "ask_oracle": return "⚀ ask_oracle: \(a["q"].str ?? "") (\(oddsText(a["odds"].int ?? 0))) → \(r["answer"].str ?? "?") [\(r["rng"].str ?? "")]"
  case "start_scene": return "⚀ start_scene: \(a["expect"].str ?? "") → \(r["outcome"].str ?? "?")"
  case "end_scene": return "⚀ end_scene: \(a["summary"].str ?? "") (Spannung \(r["s_before"].int ?? 0)→\(r["s"].int ?? 0))"
  case "random_event": return "⚀ random_event: \(r["dir"].str ?? "")"
  case "meaning": return "⚀ meaning: \(wordsText(r["pairs"]))"
  default: return "⚀ \(name)"
  }
}

public struct Status { public var figur: String?
  public var s: Int, scene: Int, open: Bool, q: Int, rng: String, source: String, akteure: Int, straenge: Int, journal: [String]
  public var text: String {
    "Spielfigur: \(figur ?? "-")\nSpannung \(s) · Szene \(scene)\(open ? " (offen)" : "") · Fragen \(q)/6 · Quelle \(rng) · Akteure \(akteure) · Stränge \(straenge)" } }

/// Session + game + persistence; shared by CLI and web.
public final class Runner {
  public let lm: LM
  public var session: Session
  public var game: Game!
  public var sink: (Out) -> Void = { _ in }
  let rng: String
  public var setting = defaultSetting
  var narr = ""
  public var debug = false
  public var temp: Float = 0.7
  public var lastRng = "?"
  public var rolls: [J] = []   // recent oracle results, newest last

  public init(lm: LM, session: Session, rng: String = "mic") { self.lm = lm; self.session = session; self.rng = rng }

  func wire() {
    game.debug = debug; game.temp = temp
    game.out = { [unowned self] o in
      switch o {
      case .delta(let d): narr += d
      case .end: session.log("\n**SL:** \(narr)\n"); narr = ""
      case .tool(let n, let a, let r):
        session.log("- `\(n)` \(a.json) → \(r.json)\n"); lastRng = r["rng"].str ?? lastRng
        if n == "ask_oracle" || n == "start_scene" || n == "random_event" { rolls.append(r); if rolls.count > 12 { rolls.removeFirst() } }
      case .event(let e): session.log("- ⚡ \(e)\n")
      default: break
      }
      if case .tool = o { refresh() } else if case .end = o { refresh() }
      sink(o)
    }
    game.onMsg = { [unowned self] _ in try? session.save(game) }
  }

  public func startNew(setting: String?) throws {
    self.setting = setting ?? defaultSetting
    let e = try Session.newEngine(rng: rng)
    game = Game(eng: e, lm: lm, setting: self.setting); wire()
    session.log("# \(session.name)\n\nSetting: \(self.setting)\n")
    try game.syncCache()
    try session.save(game); refresh()
  }
  public func resume() throws {
    let (e, s, m, f, q) = try session.loadEngine()
    setting = s
    game = Game(eng: e, lm: lm, setting: s, msgs: m, figur: f, quiet: q); wire()
    try game.syncCache(); refresh()
  }
  func run(_ f: () throws -> Void) throws {
    let n0 = game.msgs.count
    do { try f() } catch {
      if game.msgs.count > n0 { game.msgs.removeLast(game.msgs.count - n0) }   // no dangling user turn
      try? game.syncCache(); try? session.save(game); refresh(); throw error
    }
    try session.save(game); refresh()
  }
  // thread-safe snapshot for the web UI (generation runs on another thread)
  let snapLock = NSLock()
  var snapData: (Status, [[String: String]], [J])?
  public func snapshot() -> (Status, [[String: String]], [J])? { snapLock.lock(); defer { snapLock.unlock() }; return snapData }
  func refresh() { guard game != nil else { return }; let d = (status(), story(), rolls); snapLock.lock(); snapData = d; snapLock.unlock() }

  public func player(_ t: String) throws { session.log("\n**Spieler:** \(t)\n"); try run { try game.turn(t) } }
  public func ende() throws {
    guard game.eng.st.open else { sink(.info("keine offene Szene")); return }
    session.log("\n**Spieler:** /ende\n"); try run { try game.turn("Die Szene ist hier zu Ende.", forceEnd: true) } }
  public func frage(_ q: String, odds: Int) throws {
    let r = game.eng.call("ask_oracle", ["q": .str(q), "odds": .int(odds)])
    if r["error"].isNull == false { sink(.info("Fehler: \(r["error"].str ?? "")")); return }
    sink(.tool("ask_oracle", ["q": .str(q), "odds": .int(odds)], r)); rolls.append(r); lastRng = r["rng"].str ?? lastRng
    if let e = evInfo("ask_oracle", r) { sink(.event(evShow(e))) }
    session.log("\n**Spieler:** /frage \(q) → \(r.json)\n")
    var fb = fmtResult("ask_oracle", r)   // short German text only; rng/roll/step stay in the UI
    if evInfo("ask_oracle", r) != nil, !(game.eng.st.akteure.isEmpty && game.eng.st.straenge.isEmpty) { fb += "\n" + fmtKnown(game.eng.st.akteure.map(\.name), game.eng.st.straenge.map(\.name)) }
    try run { try game.turn("Ich frage das Schicksal: \(q)\n" + fb, pre: r) }
  }
  public func status() -> Status {
    let r = game.eng.call("session", ["op": "get"]), st = game.eng.st
    let j = st.journal.filter { $0["tool"].str == "end_scene" }.suffix(8).compactMap { $0["in"]["summary"].str }
    return Status(figur: game.figur, s: st.s, scene: st.scene, open: st.open, q: st.q, rng: game.eng.rngName, source: r["source"].str ?? "", akteure: st.akteure.count, straenge: st.straenge.count, journal: j)
  }

  /// Shared command handling (CLI + web). Returns false on quit.
  public func handle(_ line: String) throws -> Bool {
    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return true }
    if t == "/quit" || t == "/q" { return false }
    if t == "/ende" { try ende() }
    else if t == "/status" { let s = status(); sink(.info(([s.text] + s.journal.map { "· " + $0 }).joined(separator: "\n"))) }
    else if t.hasPrefix("/frage") {
      var rest = String(t.dropFirst(6)), odds = 0
      if let m = rest.range(of: #"^[+-]\d"#, options: .regularExpression) { odds = Int(rest[m]) ?? 0; rest = String(rest[m.upperBound...]) }
      rest = rest.trimmingCharacters(in: .whitespaces)
      if rest.isEmpty { sink(.info("/frage[+N|-N] <text>")) } else { try frage(rest, odds: odds) }
    } else if t.hasPrefix("/neu") {
      let st = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)
      let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
      session = try Session(name: "sl-" + f.string(from: Date()))
      rolls = []
      try startNew(setting: st.isEmpty ? nil : st)
    } else if t.hasPrefix("/") { sink(.info("unbekannt: \(t)")) }
    else { try player(t) }
    return true
  }

  /// Story for UI reload: player lines and final narrations.
  public func story() -> [[String: String]] {
    var r: [[String: String]] = []
    for m in game.msgs {
      if m.role == "user" {
        guard !m.text.hasPrefix("[Orakel]") else { continue }
        var t = m.text; if t.hasPrefix("Setting: "), let d = t.range(of: ". ") { t = String(t[d.upperBound...]) }
        r.append(["who": "me", "text": t])
      }
      else if let l = m.text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init), !l.hasPrefix("<"), !l.hasPrefix("Erwartung") { r.append(["who": "sl", "text": l]) }
    }
    return r
  }
}
