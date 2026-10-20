import Foundation
import Schicksal

public enum Out {
  case gate(String)                 // head/gate line (debug)
  case delta(String)                // streamed narration
  case tool(String, J, J)           // name, args, result
  case event(String)                // ⚡ line
  case end                          // narration finished
  case info(String)
  case retract                      // drop the narration streamed so far (a retry restarts it)
  case world(String)                // 🌍 world-state change
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
  public var world = World()
  public var quiet = 0                 // consecutive turns without an oracle question in an open scene
  var recap = ""
  public var sys: String { SYS + figurBlock(figur) + recap }
  public var out: (Out) -> Void = { _ in }
  public var debug = false
  public var temp: Float = 0.7
  public var lastRolls: [(String, J)] = []
  public var maxCtx = 14000
  public var onMsg: (Msg) -> Void = { _ in }

  public init(eng: Engine, lm: LM, setting: String, msgs: [Msg] = [], figur: String? = nil, quiet: Int = 0, world: World = World()) {
    self.world = world; self.eng = eng; self.lm = lm; self.setting = setting; self.msgs = msgs; self.figur = figur; self.quiet = quiet
  }

  public func syncCache() throws { try lm.reset(lm.tmpl.render(sys: sys, FEW + msgs)) }

  func compact() throws {
    let rc = eng.st.journal.filter { $0["tool"].str == "end_scene" }.suffix(12).compactMap { $0["in"]["summary"].str }.joined(separator: " ")
    var keep = Array(msgs.suffix(24)); while let f = keep.first, f.role == "model" || f.text.hasPrefix("[Orakel]") { keep.removeFirst() }
    msgs = keep.enumerated().map { (i, m) in i < keep.count - 6 ? Msg(m.role, stripWelt(m.text)) : m }   // old [Welt] blocks are stale -> drop (cache is rebuilt anyway)
    recap = rc.isEmpty ? "" : "\n\nBisheriger Verlauf (Journal): " + rc
    out(.info("Kontext verdichtet"))
    try syncCache()
  }

  /// After the narration: (1) the narrator's own "Figuren:" tail sets presence / new characters, (2) one constrained delta step
  /// (items, attitude, threads, movement) on a throwaway cache, (3) Schicksal lists are re-derived from the world.
  func worldStep(player: String, narr: String, tail: String?, oracle: [String]) {
    var log: [String] = []
    if let t = tail { log += world.applyTail(t) } else { log += world.adoptNames(World.nameHints(player + " " + narr)) }
    let block = world.block()   // current state (after start_scene and the tail), not the one shown to the narrator
    let user = (block.isEmpty ? "" : block + "\n---\n") + "Aktion: \(clean(player, 300))\nErzählung: \(clean(narr, 900))\nOrakel: \(oracle.isEmpty ? "-" : oracle.joined(separator: "; "))\nAusgabe:"
    do {
      let (txt, st) = try lm.aux(system: DELTA_SYS, user: user, Gr.delta)
      if debug { out(.info("· Welt: \(st.line) · \(txt)")) }
      if let d = try? J.parse(txt) { let old = world.ort; log += world.apply(d); world.figurMoved(from: old) }
    } catch { out(.info("Weltänderung fehlgeschlagen: \(error)")) }
    world.syncLists(eng)
    if !log.isEmpty { out(.world(log.joined(separator: " · "))) }
  }

  func push(_ m: Msg) { msgs.append(m); onMsg(m); lm.append(lm.tmpl.turn(m)) }

  /// One player turn. `pre`: already-rolled oracle result (from /frage) -> skips the gate head.
  public func turn(_ player: String, pre: J? = nil, forceEnd: Bool = false) throws {
    if lm.stale { try syncCache() }        // model was unloaded while idle: rebuild the history (the weights are re-loaded lazily on generate)
    if lm.cached > maxCtx { try compact() }
    let firstTurn = msgs.isEmpty
    let wb = world.block()
    // [Welt] goes in front of the player text of THIS turn (the system prefix stays cacheable); scene 1 starts with the first player turn
    push(.u((wb.isEmpty ? "" : wb + "\n---\n") + (msgs.isEmpty ? "Setting: \(setting). \(player)" : player)))
    var gate = Gate(); gate.figurLine = firstTurn && figur == nil; gate.selfQ = isSelfQuestion(player); gate.mustAsk = quiet >= 1 && !isWQuestion(player) && !gate.selfQ; gate.head = pre == nil; gate.forceEnd = forceEnd; gate.endNarr = forceEnd
    if let p = pre { gate.ans = p["answer"].str; gate.deut = evInfo("ask_oracle", p) != nil }
    var calls = 0, asked = false, figurChanged = false, finalNarr = "", finalTail: String? = nil, finalDu: String? = nil, oracle: [String] = []
    var done = false
    for _ in 0..<14 {
      gate.open = eng.st.open; gate.asks = eng.st.q; gate.calls = calls; gate.needFigur = figur == nil && world.name == nil && world.kurz == nil
      var ns = NarrStream(out: out)
      let gm = Gr.grammar(gate)
      var txt = "", truncated = false
      for attempt in 0..<3 {
        ns = NarrStream(out: out)
        do {
          (txt, _) = try lm.generate(gm, temp: attempt == 0 ? temp : 0.4, maxTok: 600) { d in ns.feed(d) }
          break
        } catch let e as TruncatedError {
          if let sv = salvageNarration(e.partial) {   // narration finished, only the tail overran: keep the story, drop the tail
            ns.finish(); txt = sv; out(.info("Figuren-Zeile abgeschnitten")); truncated = true; break
          }
          ns.discard()
          guard attempt < 2 else { throw e }
          out(.retract); out(.info("Ausgabe zu lang – neuer Versuch"))   // nothing usable: restart, and the UI drops the partial text
          try syncCache()   // drop the half-generated tokens from the cache
        }
      }
      if debug { out(.info("· " + lm.last.line)) }
      ns.finish()
      if gate.figurLine, let l = txt.split(separator: "\n").first(where: { $0.hasPrefix("Spielfigur: ") }) {
        let f = String(l.dropFirst(12)).trimmingCharacters(in: .whitespaces)
        if f != "-" && !f.isEmpty, let g = groundedFigur(f, player) { figur = g; world.setFigur(g); world.syncLists(eng); figurChanged = true }
      }
      gate.figurLine = false
      msgs.append(.m(txt)); onMsg(.m(txt))
      if truncated { try syncCache() }   // the cache still holds the cut tail tokens
      if let g = txt.split(separator: "\n").first(where: { $0.hasPrefix("Ereignis: ") }), debug { out(.info(String(g))) }
      let (body, tail, du) = splitTail(txt)
      guard var (name, args) = parseCall(body, firstScene: eng.st.scene == 0) else { done = true; finalNarr = body.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""; finalTail = tail; finalDu = du; break }
      if name == "ask_oracle", args["shift"].isNull, let h = world.shift(forQuestion: args["q"].str ?? ""), var o = args.obj { o["shift"] = .int(h); args = .obj(o) }   // NPC attitude -> social oracle shift (polarity-aware)
      let res = eng.call(name, args)
      calls += 1
      if name == "ask_oracle" { asked = true }
      if name == "start_scene" || name == "end_scene" { quiet = 0 }
      out(.tool(name, args, res))
      if let e = evInfo(name, res) { out(.event(evShow(e))) }
      if name == "start_scene", res["error"].isNull { world.startScene(ort: args["el"]["ort"].str, beteiligte: args["el"]["beteiligte"].str ?? "", expect: args["expect"].str ?? "") }
      var fb = fmtResult(name, res)
      oracle.append(fmtResult(name, res).replacingOccurrences(of: "[Orakel] ", with: ""))
      if evInfo(name, res) != nil, !(eng.st.akteure.isEmpty && eng.st.straenge.isEmpty) { fb += "\n" + fmtKnown(eng.st.akteure.map(\.name), eng.st.straenge.map(\.name)) }
      gate.head = false; gate.forceEnd = false
      let ok = res["error"].isNull
      gate.ans = ok && name == "ask_oracle" ? res["answer"].str : nil
      gate.deut = ok && evInfo(name, res) != nil
      if !ok { gate.head = true }
      push(.u(fb))
    }
    if !done { out(.info("Aufruflimit")) }
    if done, figur == nil, let d = finalDu {   // narrator invented the player character: register it (system prompt changes -> cache rebuild)
      let t = String(d.dropFirst(4)).trimmingCharacters(in: .whitespaces)
      if let o = t.firstIndex(of: "("), let c = t.lastIndex(of: ")"), o < c {
        let n = clean(String(t[..<o]), 40), k = clean(String(t[t.index(after: o)..<c]), 80)
        if okName(n) { figur = "\(n): \(k)"; world.setFigur(figur!); figurChanged = true; out(.world("Spielfigur: \(figur!)")) }
      }
    }
    if done { worldStep(player: player, narr: finalNarr, tail: finalTail, oracle: oracle) }
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

let gatePrefixes = ["Du: ", "Figuren: ", "Spielfigur: ", "Erwartung: ", "Ortswechsel/Zeitsprung: ", "Frage: ", "Werkzeug: ", "Antwort: ", "Deutung: "]
/// true while a partial line could still become a gate line (narration never contains ":" and never starts like a gate label)
public func isGatePrefix(_ l: String) -> Bool { gatePrefixes.contains { $0.hasPrefix(l) || l.hasPrefix($0) } }

/// The model's "Spielfigur:" line is only trusted if it is grounded in the player's own words (few-shot bleed: it once answered "Matrose").
/// Otherwise fall back to the player's text itself (cut at ~140 chars, word boundary).
func groundedFigur(_ f: String, _ player: String) -> String? {
  let p = player.lowercased()
  let ok = f.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 4 }.contains { p.contains($0.prefix(5)) }
  if ok { return f }
  var t = player.trimmingCharacters(in: .whitespacesAndNewlines)
  // fallback only for something that reads like a description ("ein älterer Mann …"), not an action ("ich betrete …")
  let w = t.lowercased().split(separator: " ")
  if w.count < 8 || ["ich", "wir", "ich,"].contains(String(w.first ?? "")) { return nil }
  if t.count > 140 { t = String(t.prefix(140)); if let i = t.lastIndex(of: " ") { t = String(t[..<i]) } }
  return t
}

/// Remove the "[Welt]…\n---\n" prefix from a user message.
public func stripWelt(_ t: String) -> String {
  guard t.hasPrefix("[Welt]"), let r = t.range(of: "\n---\n") else { return t }
  return String(t[r.upperBound...])
}

/// Split the narrator tails ("Du: Name (Rolle, Merkmal)" and "Figuren: …") off a step text.
public func splitTail(_ txt: String) -> (body: String, tail: String?, du: String?) {
  var lines = txt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard let l = lines.last, l.hasPrefix("Figuren: ") else { return (txt, nil, nil) }
  lines.removeLast()
  var du: String? = nil
  if let d = lines.last, d.hasPrefix("Du: ") { du = d; lines.removeLast() }
  return (lines.joined(separator: "\n"), l, du)
}

/// Line-wise splitter of the generated text: narration lines stream as deltas and ALWAYS close with `.end` at their line break
/// (a missing .end once glued paragraphs together and dropped the SL lines from transcript.md); gate/tail lines go to .gate.
public final class NarrStream {
  var line = "", narr = false
  let out: (Out) -> Void
  public init(out: @escaping (Out) -> Void) { self.out = out }
  public func feed(_ d: String) {
    for ch in d {
      if ch == "\n" { endLine(); continue }
      line.append(ch)
      if narr { out(.delta(String(ch))) }
      else if !isGatePrefix(line) && !line.hasPrefix("<") { narr = true; out(.delta(line)) }
    }
  }
  func endLine() { if narr { out(.end) } else if !line.isEmpty { out(.gate(line)) }; line = ""; narr = false }
  public func finish() { endLine() }
  public func discard() { line = ""; narr = false }
}

/// Self-questions are answered from [Welt] in 1-3 sentences: no oracle, no scene change.
public func isSelfQuestion(_ t: String) -> Bool {
  t.lowercased().range(of: #"\b(bin ich|heiße ich|heisse ich|mein name|lautet mein|habe ich dabei|habe ich bei mir|trage ich|besitze ich|geht es mir|fühle ich mich|sehe ich aus|mein zustand|meine ausrüstung)\b"#, options: .regularExpression) != nil
}

/// A truncated generation is usable if its narration line is complete (ends in a sentence terminator, 3+ sentences): returns head+narration without the cut tail.
public func salvageNarration(_ partial: String) -> String? {
  var lines = partial.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard lines.count >= 2 else { return nil }
  lines.removeLast()                                   // the last line is the incomplete one (the tail that overran)
  while let l = lines.last, l.hasPrefix("Du: ") || l.hasPrefix("Figuren:") { lines.removeLast() }
  guard let narr = lines.last, narr.range(of: "^" + Gr.narrPattern + "$", options: .regularExpression) != nil else { return nil }
  return lines.joined(separator: "\n")
}
