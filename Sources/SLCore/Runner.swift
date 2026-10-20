import Foundation
import Schicksal

let oddsName = ["fast unmöglich", "sehr unwahrscheinlich", "unwahrscheinlich", "offen", "wahrscheinlich", "sehr wahrscheinlich", "fast sicher"]
public func oddsText(_ o: Int) -> String { oddsName[max(0, min(6, o + 3))] }
/// odds label incl. the applied shift ("offen · Säule +1 → wahrscheinlich")
public func oddsLabel(_ a: J) -> String {
  let o = a["odds"].int ?? 0, sh = a["shift"].int ?? 0
  return sh == 0 ? oddsText(o) : "\(oddsText(o)) \(sh > 0 ? "+" : "")\(sh) → \(oddsText(o + sh))"
}

public func describe(_ name: String, _ a: J, _ r: J) -> String {
  if let e = r["error"].str { return "⚀ \(name): Fehler: \(e)" }
  switch name {
  case "ask_oracle": return "⚀ ask_oracle: \(a["q"].str ?? "") (\(oddsLabel(a))) → \(r["answer"].str ?? "?") [\(r["rng"].str ?? "")]"
  case "start_scene": return "⚀ start_scene: \(a["expect"].str ?? "") → \(r["outcome"].str ?? "?")"
  case "end_scene": return "⚀ end_scene: \(a["summary"].str ?? "") (Spannung \(r["s_before"].int ?? 0)→\(r["s"].int ?? 0))"
  case "random_event": return "⚀ random_event: \(r["dir"].str ?? "")"
  case "meaning": return "⚀ meaning: \(wordsText(r["pairs"]))"
  default: return "⚀ \(name)"
  }
}

public struct Status { public var figur: String?, welt = "", name = ""
  public var hier: [String] = []
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
  public var neglect: Int?             // --neglect N: quiet turns before an attitude decays
  public var temp: Float = 0.7
  public var lastRng = "?"
  public var rolls: [J] = []   // recent oracle results, newest last

  public init(lm: LM, session: Session, rng: String = "mic") { self.lm = lm; self.session = session; self.rng = rng; lm.notify = { [unowned self] s in self.sink(.info(s)) } }

  /// Idle: free weights + KV cache and give the GPU slot back; the next turn re-queues and reloads.
  public func idleUnload() { guard lm.loaded else { return }; lm.unloadModel(); sink(.info("Modell entladen (Leerlauf) – der nächste Zug wartet auf die GPU und lädt neu.")) }

  func wire() {
    game.debug = debug; game.temp = temp
    game.out = { [unowned self] o in
      switch o {
      case .delta(let d): narr += d
      case .retract: narr = ""
      case .end: session.log("\n**SL:** \(narr)\n"); narr = ""
      case .tool(let n, let a, let r):
        session.log("- `\(n)` \(a.json) → \(r.json)\n"); lastRng = r["rng"].str ?? lastRng
        if n == "ask_oracle" || n == "start_scene" || n == "random_event" { rolls.append(r); if rolls.count > 12 { rolls.removeFirst() } }
      case .event(let e): session.log("- ⚡ \(e)\n")
      case .world(let w): session.log("- 🌍 \(w)\n")
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
    if let n = neglect { game.world.neglectN = n }
    session.log("# \(session.name)\n\nSetting: \(self.setting)\n")
    try game.syncCache()
    try session.save(game); refresh()
  }
  public func resume() throws {
    let (e, s, m, f, q, w) = try session.loadEngine()
    setting = s
    game = Game(eng: e, lm: lm, setting: s, msgs: m, figur: f, quiet: q, world: w, hidden: session.hidden); wire()
    if let n = neglect { game.world.neglectN = n }
    if let w = session.warning { sink(.info(w)) }
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
  /// /frage is a yes/no oracle question. W-questions ("wo bin ich?") would be answered by NEIN and overwrite established facts ->
  /// they go in as a normal player turn instead (the gate then decides whether/how to ask a yes/no question).
  public func frage(_ q: String, odds: Int) throws {
    guard game.eng.st.open else { sink(.info("Keine offene Szene – beschreibe zuerst deinen Auftakt (Szene 1 beginnt mit deinem ersten Zug).")); return }
    if isWQuestion(q) { sink(.info("W-Frage: wird als normaler Zug gespielt (das Orakel beantwortet nur Ja/Nein-Fragen).")); session.log("\n**Spieler:** \(q)\n"); try run { try game.turn(q, noOracle: true) }; return }
    var args: J = ["q": .str(q), "odds": .int(odds)]
    if var o = args.obj, let sh = combinedShift(haltung: game.world.shift(forQuestion: q), regel: game.regel.oddsShift(art: classifyArt(q), pc: game.world.pc, input: q)) { o["shift"] = .int(sh); args = .obj(o) }   // N4: NPC attitude + Säulen, same as the auto-oracle
    let r = game.eng.call("ask_oracle", args)
    if r["error"].isNull == false { sink(.info("Fehler: \(r["error"].str ?? "")")); return }
    sink(.tool("ask_oracle", args, r)); rolls.append(r); lastRng = r["rng"].str ?? lastRng
    if let e = evInfo("ask_oracle", r) { sink(.event(evShow(e))) }
    session.log("\n**Spieler:** /frage \(q) → \(r.json)\n")
    var fb = fmtResult("ask_oracle", r)   // short German text only; rng/roll/step stay in the UI
    if evInfo("ask_oracle", r) != nil, !(game.eng.st.akteure.isEmpty && game.eng.st.straenge.isEmpty) { fb += "\n" + fmtKnown(game.eng.st.akteure.map(\.name), game.eng.st.straenge.map(\.name)) }
    game.lastOracleQ = q
    try run { try game.turn("Ich frage das Schicksal: \(q)\n" + fb, pre: r) }
  }
  /// `rest` = "<Name> [Thema]"; the NPC name is matched longest-first against the known figures.
  public func gespraech(_ rest: String) throws {
    let r = rest.trimmingCharacters(in: .whitespaces)
    guard !r.isEmpty else { sink(.info("/gespraech <Figur> [Thema]")); return }
    var who = String(r.split(separator: " ").first ?? ""), topic = String(r.dropFirst(who.count)).trimmingCharacters(in: .whitespaces)
    for n in game.world.npcs.sorted(by: { $0.name.count > $1.name.count }) where norm(r).hasPrefix(norm(n.name)) { who = n.name; topic = String(r.dropFirst(n.name.count)).trimmingCharacters(in: .whitespaces); break }
    session.log("\n**Spieler:** /gespraech \(r)\n")
    try run { try game.talk(who, topic: topic) }
  }
  /// /welt orakel | "text" | mix "text" | slots | slot k=v | start
  public func weltgen(_ a0: String) throws {
    let a = a0.trimmingCharacters(in: .whitespaces)
    func table() { sink(.info("Welt-Vorgaben (\(game.world.gen.mode)):\n\(game.world.gen.slots.table)\nÄndern: /welt slot ton=düster · Start: /welt start")) }
    func unq(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”„")) }
    do {
      switch a.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "" {
      case "orakel": try game.genPrepare(mode: "orakel", text: ""); table()
      case "mix": try run { try game.genPrepare(mode: "mix", text: unq(String(a.dropFirst(3)))) }; table()
      case "regeln": let v = String(a.dropFirst(6)).trimmingCharacters(in: .whitespaces); if ["frei", "saeulen"].contains(v) { game.world.regeln = v; sink(.info("Regeln: \(regelwerk(v).titel)")) } else { sink(.info("/welt regeln frei|saeulen")) }
      case "slots": table()
      case "debug": sink(.info(debug ? game.hidden.debugTable() : "/welt debug nur mit --debug (zeigt Hinweisorte)"))   // tiers / Spur: not part of the player view
      case "slot":
        let kv = String(a.dropFirst(4)).trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { sink(.info("/welt slot ton=düster")); return }
        try game.genSetSlot(kv[0].trimmingCharacters(in: .whitespaces), unq(kv[1])); table()
      case "start":
        let t0 = Date()
        try run { try game.genRun() }
        game.setting = game.world.gen.praemisse.isEmpty ? game.setting : game.world.gen.praemisse
        session.log("\n**Welt (\(game.world.gen.mode)):** \(game.world.gen.praemisse) – \(String(format: "%.0f", Date().timeIntervalSince(t0))) s\n")
        try session.save(game); refresh()
      default: try run { try game.genPrepare(mode: "text", text: unq(a)) }; table()
      }
    } catch let e as GenError { sink(.info("\(e)")) }
  }
  public func status() -> Status {
    let r = game.eng.call("session", ["op": "get"]), st = game.eng.st
    let j = st.journal.filter { $0["tool"].str == "end_scene" }.suffix(8).compactMap { $0["in"]["summary"].str }
    return Status(figur: game.figur, welt: game.world.panel(), name: session.name, hier: game.world.npcs.filter(\.anwesend).map(\.name), s: st.s, scene: st.scene, open: st.open, q: st.q, rng: game.eng.rngName, source: r["source"].str ?? "", akteure: st.akteure.count, straenge: st.straenge.count, journal: j)
  }

  /// Shared command handling (CLI + web): ONE dispatcher. Returns false on quit.
  public func handle(_ line: String) throws -> Bool {
    switch Cmd.parse(line) {
    case .empty: break
    case .quit: return false
    case .ende: try ende()
    case .status: let s = status(); sink(.info(([s.text] + s.journal.map { "· " + $0 }).joined(separator: "\n")))
    case .welt: sink(.info(game.world.panel()))
    case .frage(let q, let odds): if q.isEmpty { sink(.info("/frage[+N|-N] <text>")) } else { try frage(q, odds: odds) }
    case .figur(let f0):
      var f = f0
      if let bad = figurProblem(f0) { sink(.info(bad)); return true }
      if let r = f.range(of: #"\s*regeln=(frei|saeulen)\s*$"#, options: .regularExpression) { game.world.regeln = String(f[r]).contains("saeulen") ? "saeulen" : "frei"; f.removeSubrange(r) }   // /figur Name: Text regeln=saeulen
      game.figur = f.isEmpty ? nil : f
      if f.isEmpty { game.world.name = nil; game.world.kurz = nil } else { game.world.setFigur(f); game.world.syncLists(game.eng) }
      try game.syncCache(); try session.save(game); refresh()
      sink(.info("Spielfigur: \(f.isEmpty ? "-" : f)"))
    case .neu(let st):
      session = try Session(name: nextSessionName(base: session.name), root: session.dir.deletingLastPathComponent())   // keeps the --name the user chose
      rolls = []
      try startNew(setting: st.isEmpty ? nil : st)
    case .lebt(let a):
      if let i = game.world.npc(a), game.world.revive(i) { try session.save(game); refresh(); sink(.world("\(game.world.npcs[i].name) lebt")) } else { sink(.info("/lebt <Figur>: keine tote Figur '\(a)'")) }
    case .regeln(let a):
      if a.isEmpty { sink(.info("Regeln: \(regelwerk(game.world.regeln).titel)  (/regeln frei | saeulen)")) }
      else if ["frei", "saeulen"].contains(a) { game.world.regeln = a; try session.save(game); refresh(); sink(.info("Regeln: \(regelwerk(a).titel)")) } else { sink(.info("/regeln frei | saeulen")) }
    case .saeulen(let a):
      let (pc, msgs) = applySaeulen(a, game.world.pc); game.world.pc = pc
      msgs.forEach { sink(.info($0)) }
      try session.save(game); refresh(); sink(.info("Säulen: \(game.world.pc.line)"))
    case .talent(let a):
      let (pc, msg) = applyTalent(a, game.world.pc); game.world.pc = pc
      try session.save(game); refresh(); sink(.info(msg))
    case .weltgen(let a): try weltgen(a)
    case .gespraech(let rest): try gespraech(rest)
    case .geloest(let f):
      if let ti = game.world.straenge.firstIndex(where: { norm($0.titel).contains(norm(f)) && $0.stufe != "antwort" }) {      // P6: all core clues of the thread must be found
        if let m = missingClues(game.world.straenge[ti].titel, game.hidden.clues) { sink(.info(m)); return true }
      }
      if let t = game.world.solve(f) { game.world.pc = game.regel.progress(onThreadSolved: game.world.pc, art: nil); sink(.world("gelöst: \(t)")); try session.save(game); refresh() } else { sink(.info(game.world.straenge.contains { norm($0.titel).contains(norm(f)) && $0.stufe != "antwort" && $0.hinweise.isEmpty } ? "Der Faden hat noch keinen Hinweis – erst ermitteln." : "kein offener Faden mit '\(f)'")) }
    case .unknown(let t): sink(.info("unbekannt: \(t)"))
    case .say(let t): try player(t)
    }
    return true
  }

  /// Story for UI reload: player lines and narrations only (display text is derived from the prompt text, never the other way round).
  public func story() -> [[String: String]] { displayStory(game.msgs) }
}

public func isWQuestion(_ q: String) -> Bool {
  let w = q.lowercased().trimmingCharacters(in: .whitespaces)
  return w.range(of: #"^(wo|wer|wen|wem|wessen|was|wie|warum|wieso|weshalb|weswegen|wann|woher|wohin|welche[nmrs]?|wieviel\w*|wie viel\w*|womit|wodurch|wozu|worauf|woran)\b"#, options: .regularExpression) != nil
}

public enum Cmd: Equatable {
  case lebt(String), regeln(String), saeulen(String), talent(String), weltgen(String), gespraech(String), geloest(String), empty, quit, ende, status, welt, frage(String, Int), figur(String), neu(String), unknown(String), say(String)
  public static func parse(_ line: String) -> Cmd {
    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
    func arg(_ n: Int) -> String { String(t.dropFirst(n)).trimmingCharacters(in: .whitespaces) }
    if t.isEmpty { return .empty }
    if t == "/quit" || t == "/q" { return .quit }
    if t == "/ende" { return .ende }
    if t == "/status" { return .status }
    if t == "/welt" { return .welt }
    if t.hasPrefix("/welt ") { return .weltgen(arg(6)) }
    if t == "/frage" || t.hasPrefix("/frage ") || t.range(of: #"^/frage[+-]\d(\s|$)"#, options: .regularExpression) != nil {
      var rest = String(t.dropFirst(6)), odds = 0
      if let m = rest.range(of: #"^[+-]\d"#, options: .regularExpression) { odds = Int(rest[m]) ?? 0; rest = String(rest[m.upperBound...]) }
      return .frage(rest.trimmingCharacters(in: .whitespaces), odds)
    }
    if t == "/gespraech" || t.hasPrefix("/gespraech ") { return .gespraech(arg(10)) }
    if t == "/geloest" || t.hasPrefix("/geloest ") { return .geloest(arg(8)) }
    if t == "/lebt" || t.hasPrefix("/lebt ") { return .lebt(arg(5)) }
    if t == "/regeln" || t.hasPrefix("/regeln ") { return .regeln(arg(7)) }
    if t == "/saeulen" || t.hasPrefix("/saeulen ") { return .saeulen(arg(8)) }
    if t == "/talent" || t.hasPrefix("/talent ") { return .talent(arg(7)) }
    if t == "/figur" || t.hasPrefix("/figur ") { return .figur(arg(6)) }
    if t == "/neu" || t.hasPrefix("/neu ") { return .neu(arg(4)) }
    return t.hasPrefix("/") ? .unknown(t) : .say(t)
  }
}

/// Harness tags that exist for the model only; they must never reach the UI (hidden clue text!) or /state.
let harnessTag = try! NSRegularExpression(pattern: #"^\[(Gespräch|Hinweis verdeckt|Regie verdeckt|Orakel|Welt|Auftakt|Bekannt|System)\]"#)
func isHarnessLine(_ l: String) -> Bool { harnessTag.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil }

/// Display story from the chat history: user lines minus harness tags, narration = last prose line of each model message
/// (gate lines, calls and the Du:/Figuren: tails are skipped, so a message whose last line is a tail still shows its narration).
public func displayStory(_ msgs: [Msg]) -> [[String: String]] {
  var r: [[String: String]] = []
  for m in msgs {
    if m.role == "user" {
      var t = stripWelt(m.text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !isHarnessLine($0) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      if t.hasPrefix("Setting: "), let d = t.range(of: ". ") { t = String(t[d.upperBound...]) }
      if !t.isEmpty { r.append(["who": "me", "text": t]) }
    } else {
      let prose = m.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { l in !l.isEmpty && !l.hasPrefix("<") && !gatePrefixes.contains { l.hasPrefix($0) } && !isHarnessLine(l) }
      if let l = prose.last { r.append(["who": "sl", "text": l]) }
    }
  }
  return r
}

/// /neu: "<name>-2", "<name>-3", ... (next free) instead of a timestamp outside the chosen --name.
public func nextSessionName(base: String, root: URL = sessionsRoot) -> String {
  var b = base
  if let r = b.range(of: #"-\d+$"#, options: .regularExpression) { b = String(b[..<r.lowerBound]) }
  var n = 2
  while FileManager.default.fileExists(atPath: root.appendingPathComponent("\(b)-\(n)").path) { n += 1 }
  return "\(b)-\(n)"
}

/// P6: `/geloest` needs every core clue of the thread; nil = allowed
public func missingClues(_ titel: String, _ clues: [Clue]) -> String? {
  let cl = clues.filter { $0.thread == titel }
  return cl.contains { !$0.found } ? "Es fehlen noch Hinweise (\(cl.filter(\.found).count)/\(cl.count)) – erst ermitteln." : nil
}

/// /saeulen kampf=2 sozial=1: reports every token it could not use
public func applySaeulen(_ a: String, _ pc: PCSheet) -> (PCSheet, [String]) {
  var pc = pc, msgs: [String] = []
  let toks = a.split(separator: " ").map(String.init)
  if toks.isEmpty { return (pc, ["/saeulen kampf=2 sozial=1 wissen=0 (Werte -1 bis 2)"]) }
  for kv in toks {
    let p = kv.split(separator: "=").map(String.init)
    guard p.count == 2, let art = Art(rawValue: p[0].lowercased()), art != .sonst else { msgs.append("'\(kv)' ignoriert – erwartet kampf|sozial|wissen=Zahl"); continue }
    guard let v = Int(p[1]) else { msgs.append("'\(kv)' ignoriert – '\(p[1])' ist keine Zahl"); continue }
    if v < -1 || v > 2 { msgs.append("\(p[0]) auf \(max(-1, min(2, v))) begrenzt (erlaubt -1 bis 2)") }
    pc.setWert(art, v)
  }
  return (pc, msgs)
}
/// /talent <text> adds, /talent -<text> removes one, /talent - alone clears all (said out loud)
public func applyTalent(_ a: String, _ pc: PCSheet) -> (PCSheet, String) {
  var pc = pc
  if a == "-" { let n = pc.talente.count; pc.talente = []; return (pc, n == 0 ? "Keine Talente vorhanden." : "Alle \(n) Talente gelöscht. Neu: /talent <Text>") }
  if a.hasPrefix("-") { let t = String(a.dropFirst()).trimmingCharacters(in: .whitespaces); let n = pc.talente.count; pc.talente.removeAll { norm($0).contains(norm(t)) }; return (pc, n == pc.talente.count ? "Kein Talent '\(t)'." : "Talent '\(t)' entfernt. Talente: \(pc.talente.isEmpty ? "-" : pc.talente.joined(separator: ", "))") }
  if a.isEmpty { return (pc, "Talente: \(pc.talente.isEmpty ? "-" : pc.talente.joined(separator: ", ")) · /talent <Text> | /talent -<Text> | /talent -") }
  pc.talente.append(clean(a, 40)); pc.talente = Array(pc.talente.suffix(3))
  return (pc, "Talente: \(pc.talente.joined(separator: ", "))")
}
/// /figur needs a name before ':' - ": x" or "regeln=…" alone is stored nowhere
public func figurProblem(_ f: String) -> String? {
  let t = f.trimmingCharacters(in: .whitespaces)
  if t.isEmpty { return nil }                       // empty clears the figure
  if let c = t.firstIndex(of: ":"), t[..<c].trimmingCharacters(in: .whitespaces).isEmpty { return "/figur: Name fehlt vor dem ':' – /figur Name: Beschreibung" }
  if t.hasPrefix("regeln=") { return "/figur: Name fehlt – /figur Name: Beschreibung regeln=saeulen" }
  return nil
}
