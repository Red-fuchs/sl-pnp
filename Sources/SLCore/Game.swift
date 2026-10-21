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
  case progress(String, Int?, Int?) // world generation progress (text, done, total)
  case world(String)                // 🌍 world-state change
  case roll(Check)                  // d100 check result
  case sheet                        // party sheets changed
  case probe(ProbeReq)              // a Foundry player has to roll (probe_request)
  case probeDone(String, String)    // id, how it ended: player | sl | timeout
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
  public var hidden = HiddenWorld()     // secrets of a generated world: never rendered into [Welt]
  var lastArt: Art?
  var regel: Regelwerk { regelwerk(world.regeln) }
  var figurCandidates: [String] = []
  var banCache: (key: String, ban: BanSet)?
  /// decode-time ban for the unrevealed secret terms (cached per term set)
  func banFor(_ secrets: [(topic: String, text: String)], _ known: String) -> BanSet? {
    let terms = banTerms(secrets: secrets, known: known); guard !terms.isEmpty else { return nil }
    let key = terms.joined(separator: "|"); if let c = banCache, c.key == key { return c.ban }
    let b = buildBan(terms: terms, encode: { self.lm.tok.encode(text: $0, addSpecialTokens: false) }); banCache = (key, b); return b
  }
  /// tier 1 (Andeutung): soft penalty set
  var softCache: (key: String, ban: BanSet)?
  func softBanFor(_ known: String) -> BanSet? {
    let terms = banTerms(secrets: hidden.softList(), known: known); guard !terms.isEmpty else { return nil }
    let key = terms.joined(separator: "|"); if let c = softCache, c.key == key { return c.ban }          // 64 tokenizer encodes per term: build once per term set
    let b = buildBan(terms: terms, encode: { self.lm.tok.encode(text: $0, addSpecialTokens: false) }); softCache = (key, b); return b
  }
  var pendingHint: String?              // one-shot "[Hinweis verdeckt]" for the next narrator turn (harness reveal)
  var turnQA: [(q: String, a: String)] = []
  var lastOracleQ = ""
  var lastTargetId: String?
  var turnNo = 0
  var sceneQs: [String] = []
  var metaVetoes = 0
  var sceneNein = 0, sceneJa = 0, sceneEvents = 0     // N9: what went wrong in this scene (drives the tension, not the model's "control" guess)
  public var quiet = 0                 // consecutive turns without an oracle question in an open scene
  var recap = ""
  public var sys: String { SYS + "\n\n" + MINOR_RULE + figurBlock(figur) + recap }
  public var out: (Out) -> Void = { _ in }
  public var debug = false
  public var temp: Float = 0.7
  public var lastRolls: [(String, J)] = []
  public var maxCtx = Int(ProcessInfo.processInfo.environment["SL_MAXCTX"] ?? "") ?? 14000   // SL_MAXCTX: test aid to force compaction
  public var pendingNote: String?      // /gespraech result, handed to the narrator with the next player line
  public var onMsg: (Msg) -> Void = { _ in }
  public let partyStore = PartyStore()
  public let probes = ProbeBroker()
  /// default wait for a Foundry player's own roll (seconds, 0 = sl always rolls); `probeWait` = per-message override from the bridge setting
  nonisolated(unsafe) public static var probeDefault: Double = 90
  public var probeWait: Double?
  var pendingFacts: [String] = []
  public var chargen = "a"              // --chargen a|b|c|bc (notes/CHARGEN-v2.md)
  public var cg: [String: CgState] = [:]
  public var pendingRegie: [String] = []
  var npcMods: [String: Int] = [:]
  public var speaker: String?
  public var storyLog: [[String: String]] = []
  public var onStory: ([String: String]) -> Void = { _ in }
  func logStory(_ e: [String: String]) { storyLog.append(e); onStory(e) }

  public init(eng: Engine, lm: LM, setting: String, msgs: [Msg] = [], figur: String? = nil, quiet: Int = 0, world: World = World(), hidden: HiddenWorld = HiddenWorld()) {
    self.hidden = hidden; self.world = world; self.eng = eng; self.lm = lm; self.setting = setting; self.msgs = msgs; self.figur = figur; self.quiet = quiet
    partyStore.with { $0 = world.party }
  }

  /// after a failed attempt: the LM already rolled its cache back (dirty == false) unless it could not
  static let forceAbort = ProcessInfo.processInfo.environment["SL_FORCE_ABORT"] != nil   // test aid: first attempt of every call aborts
  func recoverCache() throws { if lm.dirty { try syncCache() } }
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
  func worldStep(player: String, narr: String, tail: String?, oracle: [String], harness: Bool = false, harnessNein: Bool = false) {
    var log: [String] = []
    if let t = tail { log += world.applyTail(t) } else { log += world.adoptNames(World.nameHints(player + " " + narr)) }
    world.updateMinors(player + " " + narr); world.syncPresence(narr: narr); if !harnessNein { log += world.markDeaths(narr: narr) }; if !harness { log += world.markKillIntent(player: player, narr: narr, oracleNein: oracle.contains { $0.contains("NEIN") }) }   // the harness oracle decides lethal actions; NEIN never kills
    defer { world.enforceDead(); world.shieldMinors() }
    let block = world.block()   // current state (after start_scene and the tail), not the one shown to the narrator
    let user = (block.isEmpty ? "" : block + "\n---\n") + "Aktion: \(clean(player, 300))\nErzählung: \(clean(narr, 900))\nOrakel: \(oracle.isEmpty ? "-" : oracle.joined(separator: "; "))\nAusgabe:"
    do {
      let (txt, st) = try lm.aux(system: DELTA_SYS, user: user, Gr.delta)
      if debug { out(.info("· Welt: \(st.line) · \(txt)")) }
      if let d = try? J.parse(txt) {
        let old = world.ort, threads = world.straenge, injected = isInjection(player) || player.trimmingCharacters(in: .whitespaces).hasSuffix("?")   // injection and plain question turns never grow threads/hints (clues come from the reveal pipeline)
        log += world.apply(d); world.figurMoved(from: old)
        if injected { world.straenge = threads }      // N6: an injected frame never writes threads / hints
      }
    } catch { out(.info("Weltänderung fehlgeschlagen: \(error)")) }
    let talkedNames = world.talkedNames()      // read BEFORE tick(): tick clears talkedThisTurn (the Spur event "asking the bearer" was lost for /gespraech)
    var met = world._tailIds.union(world.mentioned(in: player)); met.formUnion(world.npcs.filter { $0.anwesend && world.talkedThisTurn.contains($0.id) }.map(\.id))
    log += world.tick(contacts: met)
    genLazy()
    let itemsBefore = Set(hidden.npcs.filter { $0.key.hasPrefix("★") && $0.value.revealed }.keys)
    let sp = hidden.updateSpur(&world, bonus: { [regel, pc = world.pc, art = lastArt ?? classifyArt(player)] tier in regel.spurBonus(art: art, pc: pc, tier: tier) }, player: player, oracle: turnQA, talked: namedBy(player) + talkedNames)
    if debug { sp.filter { $0.hasPrefix("[debug]") }.forEach { out(.info($0)) } }
    itemPayoffs(revealed: hidden.npcs.filter { $0.key.hasPrefix("★") && $0.value.revealed && !itemsBefore.contains($0.key) }.map(\.key)).forEach { out(.info($0)) }
    let rv = genReveals(oracle: turnQA, talked: namedBy(player) + talkedNames) + sp.filter { !$0.hasPrefix("[debug]") }
    if !rv.isEmpty { pendingHint = rv.joined(separator: " "); if debug { out(.info("[debug] enthüllt (nächste Szene): " + rv.joined(separator: " · "))) }  }
    world.syncLists(eng)
    if !log.isEmpty { out(.world(log.joined(separator: " · "))) }
  }

  /// /gespraech: 1-2 lines of dialogue from a present NPC (side generation: no scene change, no oracle, history untouched), attitude -1..+1.
  public func talk(_ who: String, topic: String) throws {
    guard let i = world.npc(who) else { out(.info("Unbekannte Figur: \(who)")); return }
    guard !world.npcs[i].tot else { out(.info("\(world.npcs[i].name) ist tot.")); return }
    guard world.npcs[i].anwesend else { out(.info("\(world.npcs[i].name) ist nicht hier.")); return }
    try lm.ensureLoaded()
    let n = world.npcs[i]
    let h = haltungWort[n.haltung].flatMap { $0.isEmpty ? nil : $0 } ?? "neutral"
    let sys = "Du bist \(n.name) (\(n.kurz)) in einem düsteren Fantasy-Rollenspiel und sprichst mit der Spielfigur. Sprich Deutsch, in der Ich-Form, 1 bis 2 kurze Sätze wörtliche Rede, in deinem Ton. Deine Haltung zur Spielfigur: \(h). Nutze nur, was in [Welt] steht; erfinde keine neuen Namen. Zeilenformat: \"Rede: <Satz>\" (optional eine zweite Rede-Zeile), dann \"Haltung: -1|0|+1\" (ändert sich deine Haltung durch das Gespräch? -1 kühler, +1 wärmer)." + " " + MINOR_RULE
    let user = world.block() + "\n---\nDie Spielfigur spricht dich an" + (topic.isEmpty ? "." : " und fragt nach: \(clean(topic, 80)).") + "\nAusgabe:"
    let (txt, st) = try lm.aux(system: sys, user: user, Gr.talk, temp: 0.7, maxTok: 200)
    if debug { out(.info("· Gespräch: \(st.line)")) }
    let lines = txt.split(separator: "\n").map(String.init)
    let speech = lines.filter { $0.hasPrefix("Rede: ") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
    let d = Int((lines.first { $0.hasPrefix("Haltung: ") }.map { String($0.dropFirst(9)) } ?? "0").replacingOccurrences(of: "+", with: "")) ?? 0
    let said = speech.map { "„\(clean($0, 220))“" }.joined(separator: " ")
    out(.delta("\(n.name): \(said)")); out(.end)
    world.talkedThisTurn.insert(n.id)
    var log: [String] = []
    if d != 0 { log += world.setHaltung(i, world.npcs[i].haltung + regel.haltungDelta(max(-1, min(1, d)), art: .sozial, pc: world.pc)) }
    world.npcs[i].kontakt = world.turn
    if !log.isEmpty { out(.world(log.joined(separator: " · "))) }
    pendingNote = "\(n.name) sagte: \(said)"
    let rv = genReveals(oracle: [], talked: [n.name])
    if !rv.isEmpty { pendingHint = (pendingHint.map { $0 + " " } ?? "") + rv.joined(separator: " "); if debug { out(.info("[debug] enthüllt (nächste Szene): " + rv.joined(separator: " · "))) }  }
    world.syncLists(eng)
  }

  func push(_ m: Msg) { msgs.append(m); onMsg(m); lm.append(lm.tmpl.turn(m)) }

  /// Gate state at the start of a turn (a pure function so a test can assert every field; a trailing `//` once swallowed all of them).
  static func initialGate(player: String, pre: J?, forceEnd: Bool, noOracle: Bool, firstTurn: Bool, figurKnown: Bool, quiet: Int, saeulen: Bool, open: Bool = true, isDialogue: Bool = false) -> Gate {
    var gate = Gate()
    gate.figurLine = firstTurn && !figurKnown
    gate.selfQ = isSelfQuestion(player)
    gate.noAsk = noOracle || pre != nil || !(askOpener(player) || quiet >= 3)   // free asks only when the player opens something (ob/weiß/kennt/?...) or after a long quiet stretch; the harness vetoes irrelevant ones
    gate.art = saeulen
    gate.mustAsk = quiet >= 3 && !isWQuestion(player) && !gate.selfQ
    gate.quote = isDialogue
    gate.head = pre == nil || open     // pre turns keep the head (Erwartung) with `Frage: -`
    gate.forceEnd = forceEnd; gate.endNarr = forceEnd
    return gate
  }
  /// One player turn. `pre`: already-rolled oracle result (from /frage) -> skips the gate head.
  public func turn(_ player: String, pre: J? = nil, forceEnd: Bool = false, noOracle: Bool = false, speaker spk: String? = nil) throws {
    if spk != nil { speaker = spk }
    let speaker = self.speaker
    if lm.stale { try syncCache() }        // model was unloaded while idle: rebuild the history (the weights are re-loaded lazily on generate)
    if lm.cached > maxCtx { try compact() }
    let firstTurn = msgs.isEmpty
    world.updateMinors(player)
    let playerOrig = player
    if isSchicksal { pcIndex(speaker) }
    var player = player
    turnQA = []; lastArt = nil; turnNo += 1
    var cls: ActionClass? = (pre == nil && !noOracle && !firstTurn && !isWQuestion(player) && !isSelfQuestion(player)) ? classifyAction(player) : nil
    var minorTarget = false
    if let c = cls, c == .kill || c == .risky(.kampf), case .npc(let i) = world.resolveTarget(player, last: lastTargetId), world.npcs[i].minor { minorTarget = true }
    if minorHarm(player, names: world.minorNames) || minorTarget {      // P1: the act never happens - deflected in the fiction, the player is told
      out(.info("Hinweis: Gewalt oder Sexuelles gegen Kinder wird nicht gespielt – die Handlung kommt in der Geschichte nicht zustande."))
      player = "Ich will etwas Unüberlegtes tun, aber ein Geräusch lenkt mich im letzten Moment ab, und niemand kommt zu Schaden. (Kinder bleiben unverletzt und unbedroht.)"
    }
    var pre = pre
    var actionRes = false
    var actionNein = false
    if pre == nil, !noOracle, !firstTurn, !minorTarget, cls == nil, let (fact, res) = resolveNameAsk(player) { player += "\n" + fact; pre = res; actionRes = true }
    if pre == nil, !noOracle, !firstTurn, !minorTarget, let (fact, res, cancel) = resolveClaim(player) {      // M2: claimed item not in the inventory
      player += "\n" + fact
      if cancel, let r = res { cls = nil; pre = r; actionRes = true; actionNein = true }
    }
    if let c = cls, pre == nil, !minorTarget, let (fb, res) = resolveAction(player, c) {
      player += "\n" + fb
      if let r = res { pre = r; actionRes = true; actionNein = r["answer"].str?.hasPrefix("NEIN") ?? false }
    }
    if !pendingFacts.isEmpty { player += "\n" + pendingFacts.joined(separator: "\n"); pendingFacts = [] }
    let wb = world.block() + (partyBlock.isEmpty ? "" : (world.block().isEmpty ? "[Welt]\n" : "\n") + partyBlock)
    // [Welt] goes in front of the player text of THIS turn (the system prefix stays cacheable); scene 1 starts with the first player turn
    let regie = directorPass(player: player)   // behaviour cue from the secrets (side cache); [Regie verdeckt] never reaches the UI
    if let r = regie, debug { out(.info("[debug] Regie: \(r)")) }
    let note = (pendingNote.map { "[Gespräch] \($0)\n" } ?? "") + (pendingHint.map { "[Hinweis verdeckt] \($0)\n" } ?? "") + ((regie ?? motifNote()).map { "[Regie verdeckt] \($0)\n" } ?? ""); pendingNote = nil; pendingHint = nil; let regieHidden = pendingRegie.map { "[Regie verdeckt] \($0)\n" }.joined(); pendingRegie = []
    let who: String = { guard isSchicksal || speaker != nil, let i = pcIndex(speaker, create: false) else { return "" }; return "[Spieler] \(partyStore.all[i].name)\n" }()
    push(.u((wb.isEmpty ? "" : wb + "\n---\n") + note + regieHidden + who + (msgs.isEmpty ? "Setting: \(setting). \(player)" : player)))
    if let e = displayStory([Msg.u(playerOrig)]).first { logStory(e) }      // the story log keeps what the player typed (the model may have seen a deflection)
    var gate = Game.initialGate(player: player, pre: pre, forceEnd: forceEnd, noOracle: noOracle, firstTurn: firstTurn, figurKnown: figur != nil, quiet: quiet, saeulen: world.regeln == "saeulen", open: eng.st.open, isDialogue: isDialogueTurn(playerOrig, world))
    if let p = pre { gate.ans = p["answer"].str; gate.deut = evInfo("ask_oracle", p) != nil }
    var calls = 0, asked = actionRes || pre != nil, figurChanged = false, finalNarr = "", finalTail: String? = nil, finalDu: String? = nil, oracle: [String] = pre.map { [fmtResult("ask_oracle", $0).replacingOccurrences(of: "[Orakel] ", with: "")] } ?? []
    var done = false, callLeakRetries = 0
    for _ in 0..<14 {
      gate.open = eng.st.open; gate.asks = eng.st.q; gate.calls = calls; gate.needFigur = figur == nil && world.name == nil && world.kurz == nil
      if gate.needFigur { if figurCandidates.isEmpty { var ng = NameGen(used: Set(world.gen.used), rand: rnd); let c = NameGen.culture(for: world.gen.slots.line); figurCandidates = (0..<4).map { _ in ng.next(culture: c, avoid: Set(world.npcs.map { norm($0.name) })) }; world.gen.used = ng.used.sorted() }; gate.figurNames = figurCandidates }
      let secrets = hidden.guardList(), known = knownText(), hold = hidden.holdNarration   // held back whenever any tier-0/1 secret exists (also when its bearer is absent): a leak must never be shown and then retracted   // narration is held back for the leak check while a secret-bearing NPC is present
      let minors = world.minorNames
      let ansQ = actionRes ? nil : gate.ans.map { a in (a, turnQA.last?.q ?? lastOracleQ) }
      let oracleFlag = Box<String?>(nil)
      let mkStream = { (attempt: Int) in NarrStream(hold: hold, minors: minors, check: secrets.isEmpty && ansQ == nil ? nil : { line in
        if !secrets.isEmpty, let l = leakCheck(line, secrets: secrets, known: known) { return l }
        if attempt == 0, let (a, q) = ansQ, !q.isEmpty, oracleContradicted(answer: a, question: q, narration: line) { oracleFlag.value = line }   // M1: flagged now, confirmed by a second opinion after the generation
        return nil }, out: self.out) }
      let ban = banFor(hidden.secretList(), known)          // hard ban: tier 0 only; the check above also covers tier 1
      var ns = mkStream(0)
      let gm = Gr.grammar(gate)
      var txt = "", truncated = false, metaRetry = false
      for attempt in 0..<3 {
        ns = mkStream(attempt)
        do {
          (txt, _) = try lm.generate(gm, temp: attempt == 0 ? temp : (metaRetry ? 0.9 : 0.4), maxTok: 600, abort: { attempt < 2 && (ns.bad || ns.leak != nil || (attempt == 0 && Game.forceAbort && ns.n > 8)) }, ban: ban, soft: softBanFor(known)) { d in ns.feed(d) }
          if attempt == 0, let sent = oracleFlag.value, let (a, q) = ansQ, secondOpinionContradicts(answer: a, question: q, narration: sent) { ns.markOracle(sent); throw AbortedError() }
          break
        } catch is AbortedError {
          // planner scaffold / foreign glyphs in the narration: drop it (UI retracts) and sample again
          if let l = ns.leak, !msgs.isEmpty {   // leak guard: regenerate once with a "do not reveal" note (kept in the prompt text, stripped from the UI)
            // neutral note only (naming the forbidden term primes the model to use it); the decode-time ban is active for the retry
            msgs[msgs.count - 1].text += l.topic == "orakel" ? "\n[Regie] Das Orakel hat entschieden: \(gate.ans ?? ""). Erzähle dieses Ergebnis ausdrücklich und sichtbar." : l.topic == minorTopic ? "\n[Regie] Kinder bleiben unverletzt und unbedroht; nichts Sexuelles. Erzähle etwas anderes." : "\n[Regie verdeckt] Bleib bei Verhalten, nenne keine neuen Fakten."
            out(.info(leakNotice(dropped: false))); if debug { out(.info("[debug] Leck: \(l.topic)")) }
          } else { out(.info("Erzählung verworfen (Meta-Text oder fremde Zeichen) – neuer Versuch")) }
          metaRetry = ns.leak == nil; ns.discard()
          out(.retract)
          if ns.leak != nil { try syncCache() } else { try recoverCache() }
        } catch let e as TruncatedError {
          if let sv = salvageNarration(e.partial) {   // narration finished, only the tail overran: keep the story, drop the tail
            ns.finish(); txt = sv; out(.info("Figuren-Zeile abgeschnitten")); truncated = true; break
          }
          ns.discard()
          guard attempt < 2 else { throw e }
          out(.retract); out(.info("Ausgabe zu lang – neuer Versuch"))   // nothing usable: restart, and the UI drops the partial text
          try recoverCache()   // drop the half-generated tokens from the cache
        }
      }
      if debug { out(.info("· " + lm.last.line)) }
      ns.finish()
      if ns.bad, ns.leak == nil {   // meta text / foreign glyphs on the LAST attempt: never show or store it
        var lines = txt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let k = lines.lastIndex(where: { !$0.isEmpty && !$0.hasPrefix("<") && !gatePrefixes.contains(where: $0.hasPrefix) }), isMetaNarration(lines[k]) || !isCleanText(lines[k]) {
          if !hold { out(.retract) }
          let kept = stripMeta(lines[k]) ?? "Die Szene verharrt für einen Augenblick."   // best attempt minus the meta sentences; the stock line only when nothing is left
          out(.delta(kept)); out(.end)
          lines[k] = kept; txt = lines.joined(separator: "\n"); truncated = true
        }
      }
      if let l = ns.leak, l.topic == "orakel" { ns.discardLeakFlag() }
      if let l = ns.leak {   // still leaking after the regeneration: drop the offending sentences, show the rest
        var lines = txt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let k = lines.lastIndex(where: { !$0.isEmpty && !$0.hasPrefix("<") && !gatePrefixes.contains(where: $0.hasPrefix) }) {
          let safe = l.topic == minorTopic ? dropMinorSentences(lines[k], names: minors) : dropLeakingSentences(lines[k], secrets: secrets, known: known)
          out(.info(leakNotice(dropped: true))); if debug { out(.info("[debug] Leck: \(l.topic)")) }
          if !hold { out(.retract) }
          if !safe.isEmpty { out(.delta(safe)); out(.end) }
          lines[k] = safe.isEmpty ? "Die Szene verharrt für einen Augenblick." : safe; txt = lines.joined(separator: "\n"); truncated = true
        }
      }
      if gate.figurLine, let l = txt.split(separator: "\n").first(where: { $0.hasPrefix("Spielfigur: ") }) {
        let f = String(l.dropFirst(12)).trimmingCharacters(in: .whitespaces)
        if f != "-" && !f.isEmpty, let g = groundedFigur(f, player) { figur = g; world.setFigur(g); world.syncLists(eng); figurChanged = true }
      }
      let hadFigurLine = gate.figurLine
      gate.figurLine = false
      msgs.append(.m(txt)); onMsg(.m(txt)); if let e = displayStory([Msg.m(txt)]).first { logStory(e) }
      if truncated { try syncCache() }   // the cache still holds the cut tail tokens
      if let g = txt.split(separator: "\n").first(where: { $0.hasPrefix("Ereignis: ") }), debug { out(.info(String(g))) }
      let (body, tail, du) = splitTail(txt)
      guard var (name, args) = parseCall(body, firstScene: eng.st.scene == 0) else { done = true; finalNarr = body.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""; finalTail = tail; finalDu = du; break }
      // verdict design: the model may propose a scene/identity/NPC-reaction question in the head; the harness vetoes irrelevant or repeated ones and regenerates the head without asking
      if name == "ask_oracle", pre == nil, let q = args["q"].str, !askAllowed(q: q, player: playerOrig) {
        msgs.removeLast(); if !lm.undoLast() { try syncCache() }
        gate.noAsk = true; gate.figurLine = hadFigurLine; metaVetoes += 1
        if debug { out(.info("[debug] Orakelfrage verworfen: \(q)")) }
        continue
      }
      // leak guard for tool-call text that reaches the UI / journal / recap (oracle q, scene expect, summary, why): regenerate once or twice, then sanitise
      if let l = argLeak(args, secrets: secrets, known: known, minors: minors) {
        if callLeakRetries < 2, !msgs.isEmpty {
          callLeakRetries += 1; msgs.removeLast()
          msgs[msgs.count - 1].text += "\n[Regie verdeckt] Bleib bei Verhalten, nenne keine neuen Fakten."
          out(.info(leakNotice(dropped: false))); if debug { out(.info("[debug] Leck im Aufruf: \(l.topic)")) }
          gate.figurLine = hadFigurLine; try syncCache(); continue
        }
        args = sanitizeArgs(args, secrets: secrets, known: known, minors: minors)
      }
      // oracle shift = NPC attitude (polarity-aware) + rules module (Säulen/talent by the classified art); both combined, clamped to -2...2
      let art = Art(rawValue: txt.split(separator: "\n").first(where: { $0.hasPrefix("Art: ") }).map { String($0.dropFirst(5)) } ?? "") ?? .sonst
      if name == "ask_oracle", args["shift"].isNull, var o = args.obj {
        let rs = regel.oddsShift(art: art, pc: world.pc, input: player) + spOracleShift(speaker)
        if let sh = combinedShift(haltung: world.shift(forQuestion: args["q"].str ?? ""), regel: rs) { o["shift"] = .int(sh); args = .obj(o) }
        if world.regeln == "saeulen" { lastArt = art }
      }
      if name == "end_scene", var o = args.obj {
        let c = tensionControl(model: o["control"]?.bool ?? true, nein: sceneNein, ja: sceneJa, events: sceneEvents)
        if o["control"]?.bool != c { o["control"] = .bool(c); args = .obj(o); if debug { out(.info("[debug] Spannung: control → \(c) (NEIN \(sceneNein), JA \(sceneJa), Ereignisse \(sceneEvents))")) } }
      }
      let res = eng.call(name, args)
      if name == "ask_oracle", let a = res["answer"].str { if a.hasPrefix("NEIN") { sceneNein += 1 } else { sceneJa += 1 }; if !res["event"].isNull { sceneEvents += 1 } }
      if name == "end_scene" || name == "start_scene" { sceneQs = []; sceneNein = 0; sceneJa = 0; sceneEvents = 0; partyStore.with { SR.resetScene(&$0) } }
      calls += 1
      if name == "ask_oracle" { asked = true; sceneQs.append(args["q"].str ?? "") }
      if name == "start_scene" || name == "end_scene" { quiet = 0 }
      out(.tool(name, args, res))
      if let e = evInfo(name, res) { out(.event(evShow(e))) }
      if name == "start_scene", res["error"].isNull { world.startScene(ort: args["el"]["ort"].str, beteiligte: args["el"]["beteiligte"].str ?? "", expect: args["expect"].str ?? "") }
      if name == "ask_oracle", let a = res["answer"].str { turnQA.append((args["q"].str ?? "", a)); let l = world.oracleSolved(question: args["q"].str ?? "", answer: a); if !l.isEmpty { world.pc = regel.progress(onThreadSolved: world.pc, art: lastArt); if isSchicksal { partyGain(sp: 2) }; out(.world(l.joined(separator: " · "))) } }
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
        if okFigurName(n, k) { figur = "\(n): \(k)"; world.setFigur(figur!); figurChanged = true; out(.world("Spielfigur: \(figur!)")) }
      }
    }
    if done { worldStep(player: player, narr: finalNarr, tail: finalTail, oracle: oracle, harness: actionRes, harnessNein: actionNein) }
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
    // the call's own q wins (the model sometimes pre-writes the ANSWER into its "Frage:" line: "Nein (Der Tod ist unmittelbar)"); the Frage line is the fallback
    let own = o["q"]?.str?.trimmingCharacters(in: .whitespaces) ?? ""
    o["q"] = .str(own.count >= 5 ? own : (lines.last { $0.hasPrefix("Frage: ") }.map { String($0.dropFirst(7)) } ?? "?")); args = .obj(o)
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

let gatePrefixes = ["Art: ", "Du: ", "Figuren: ", "Spielfigur: ", "Erwartung: ", "Ortswechsel/Zeitsprung: ", "Frage: ", "Werkzeug: ", "Antwort: ", "Deutung: "]
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
  var t = t
  if t.hasPrefix("[Welt]"), let r = t.range(of: "\n---\n") { t = String(t[r.upperBound...]) }
  let keep = t.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("[Regie") && !$0.hasPrefix("[Hinweis verdeckt]") && !$0.hasPrefix("[Gespräch]") }   // stale director / hint notes do not belong in old history
  return keep.joined(separator: "\n")
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
  var line = "", narr = false, held = ""
  public private(set) var bad = false          // narration must be regenerated (foreign glyph / planner scaffold, see F2)
  public private(set) var leak: Leak?          // narration gives away a secret (leak guard)
  let out: (Out) -> Void
  let hold: Bool, check: ((String) -> Leak?)?, minors: [String]
  /// hold: narration deltas are buffered until the line is complete and checked (only on turns with secret-bearing NPCs present)
  public init(hold: Bool = false, minors: [String] = [], check: ((String) -> Leak?)? = nil, out: @escaping (Out) -> Void) { self.hold = hold; self.minors = minors; self.check = check; self.out = out }
  public private(set) var n = 0
  var sent = "", prevMinor = false
  public func feed(_ d: String) {
    n += 1
    for ch in d {
      if ch == "\n" { endLine(); continue }
      line.append(ch)
      if narr { emit(ch) }
      else if !isGatePrefix(line) && !line.hasPrefix("<") { narr = true; for c in line { emit(c) } }
      if narr, !bad, isMetaNarration(line) || !isCleanText(String(ch)) { bad = true }
    }
  }
  /// narration goes out sentence by sentence (or at the end of the line when held): minors-rule violations never reach the UI
  func emit(_ ch: Character) {
    if hold { held.append(ch); return }
    sent.append(ch)
    if ".!?".contains(ch) { flush() }
  }
  func flush() {
    guard !sent.isEmpty else { return }
    if leak == nil, minorHarm(sentence: sent, prevMinor: prevMinor, names: minors) { leak = Leak(topic: minorTopic, words: [], sentence: sent) }
    prevMinor = hasMinor(sent, names: minors)
    if leak == nil { out(.delta(sent)) }
    sent = ""
  }
  func endLine() {
    if narr {
      flush()
      if leak == nil, let c = check?(line) ?? (minorHarm(line, names: minors) ? Leak(topic: minorTopic, words: [], sentence: line) : nil) { leak = c; held = "" }   // never shown (hold) / retracted by the caller
      if leak == nil { if hold { out(.delta(held)); held = "" }; out(.end) }
    } else if !line.isEmpty { out(.gate(line)) }
    line = ""; narr = false; held = ""; prevMinor = false
  }
  public func finish() { endLine() }
  func discardLeakFlag() { leak = nil }
  func markOracle(_ s: String) { leak = Leak(topic: "orakel", words: [], sentence: s) }
  public func discard() { line = ""; narr = false; bad = false; leak = nil; held = ""; sent = ""; prevMinor = false }
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

/// The narrator must give the player character a real name: reject articles, "Spielfigur", "Dein Name", "unbekannt" evasions.
public func okFigurName(_ n: String, _ role: String) -> Bool {
  guard okName(n), let f = n.split(separator: " ").first?.lowercased() else { return false }
  if ["die", "der", "das", "dein", "deine", "mein", "meine", "ein", "eine", "name", "ihr", "sie", "er", "spielfigur", "figur"].contains(f) { return false }
  if norm(n).contains("spielfigur") || norm(n).contains("name") { return false }
  return !norm(role).contains("unbekannt") && !norm(role).contains("name") && !role.contains("[")
}

/// F2: the 4B model sometimes puts the planner scaffold into the narration slot ("Erwartung eines Kindes …", "Deutunglichst plausibel ist, dass …").
public func isMetaNarration(_ line: String) -> Bool {
  let t = line.trimmingCharacters(in: .whitespaces)
  let w = String(t.prefix { $0.isLetter })
  if ["Erwartung", "Werkzeug", "Ortswechsel", "Antwort", "Frage", "Hinweis"].contains(w) || w.hasPrefix("Deutung") { return true }
  if t.contains("zugänglich geworden") || t.contains("nun für dich zugänglich") || t.contains("Regeln ignor") { return true }   // N6: plays along with an injected frame
  return t.contains("plausibel ist, dass") || t.contains("plausibel ist dass")
}

/// M1: does the narration contradict (or ignore) the oracle answer to the question? Sentences sharing a content word with the question
/// must not deny a JA, and must deny a NEIN. Cue lists by class (not bare negation words): a first, cheap flag - the caller confirms with a second opinion.
let denyCues = ["nicht ", "kein", "nie ", "niemand", "nichts", "vergeblich", "leer", "misslingt", "scheitert", "fehl", "unmöglich", "verschlossen", "verwehr", "ohne ", "verweiger", "lehnt ab", "abgelehnt", "weigert", "bleibt aus", "misstraut"]
public func oracleContradicted(answer: String, question: String, narration: String) -> Bool {
  let qw = Set(contentWords(question).map(lemma)); guard !qw.isEmpty else { return false }
  let rel = sentences(of: narration).filter { !Set(contentWords($0).map(lemma)).isDisjoint(with: qw) }
  guard !rel.isEmpty else { return false }       // unrelated narration is not provably contradictory (the BIND line already carries the answer)
  let denies = rel.contains { s in denyCues.contains { s.lowercased().contains($0) } }
  let affirms = rel.contains { s in !denyCues.contains { s.lowercased().contains($0) } }
  return answer.hasPrefix("JA") ? (denies && !affirms) : (!denies && affirms)
}

/// N9: tension must rise when the scene went badly (NEIN majority, random event) - the model nearly always claims "control".
public func tensionControl(model: Bool, nein: Int, ja: Int, events: Int) -> Bool {
  if events >= 1 || nein > ja { return false }
  return model
}

/// N6: player text that tries to rewrite the rules / role ("Ignoriere deine Regeln", "SYSTEM:") - it must never write into threads or the world
public func isInjection(_ t: String) -> Bool {
  t.range(of: #"(ignorier\w*|vergiss|missachte)\s+(alle[ns]?|deine[ns]?|die|vorherige\w*)?\s*(regeln|anweisung\w*|instruktion\w*|prompt)|ignore\s+(all|your|previous)|(^|\n|\s)system\s*:|\[system|neue anweisung|du bist (jetzt|ab sofort)|spielleiter-modus|hidden\.json|systemprompt|system prompt|developer mode"#, options: [.regularExpression, .caseInsensitive]) != nil
}

/// Narration line minus planner/meta sentences and foreign glyphs; nil when nothing readable is left.
public func stripMeta(_ line: String) -> String? {
  let r = sentences(of: line).filter { !isMetaNarration($0) }.map { stripForeign($0).trimmingCharacters(in: .whitespaces) }.filter { $0.count > 3 }.joined(separator: " ")
  return r.count >= 20 ? r : nil
}

/// UI/SSE text for a guarded narration: never names the bearer or the topic (the info line is replayed to late joiners and shown to the player).
public func leakNotice(dropped: Bool) -> String { dropped ? "Ein Satz wurde entfernt." : "Erzählung verworfen – neuer Versuch" }

/// Free-text fields of a tool call that the player (UI, journal, recap) can read.
let callTextKeys = ["q", "expect", "summary", "why"]
public func argLeak(_ args: J, secrets: [(topic: String, text: String)], known: String, minors: [String] = []) -> Leak? {
  for k in callTextKeys { if let t = args[k].str, minorHarm(t, names: minors) { return Leak(topic: minorTopic, words: [], sentence: t) } }
  guard !secrets.isEmpty else { return nil }
  for k in callTextKeys { if let t = args[k].str, let l = leakCheck(t, secrets: secrets, known: known) { return l } }
  if let el = args["el"].obj { for (_, v) in el { if let t = v.str, let l = leakCheck(t, secrets: secrets, known: known) { return l } } }
  return nil
}
/// Last resort when the regeneration still leaks: drop the leaking sentences (q falls back to a neutral question).
public func sanitizeArgs(_ args: J, secrets: [(topic: String, text: String)], known: String, minors: [String] = []) -> J {
  guard var o = args.obj else { return args }
  for k in callTextKeys { if let t = o[k]?.str, minorHarm(t, names: minors) { let safe = dropMinorSentences(t, names: minors); o[k] = .str(safe.isEmpty ? (k == "q" ? "Ist hier etwas im Gange?" : "-") : safe) } }
  for k in callTextKeys { if let t = o[k]?.str, leakCheck(t, secrets: secrets, known: known) != nil {
    let safe = dropLeakingSentences(t, secrets: secrets, known: known)
    o[k] = .str(safe.isEmpty ? (k == "q" ? "Ist hier etwas im Gange?" : "-") : safe) } }
  if var el = o["el"]?.obj { for (k, v) in el { if let t = v.str, leakCheck(t, secrets: secrets, known: known) != nil { el[k] = .str("-") } }; o["el"] = .obj(el) }
  return .obj(o)
}

let openerRe = try! NSRegularExpression(pattern: #"\?|\b(ob|weiß|weiss|kennt|kenne ich|hilft|helfen|gibt es|ist hier|finde ich|lügt|lüge|wer ist|ist das|sind das|versteht|erkennt|erkenne)\b"#, options: .caseInsensitive)
public func askOpener(_ player: String) -> Bool { openerRe.firstMatch(in: player, range: NSRange(player.startIndex..., in: player)) != nil }

/// harness veto for model-proposed oracle questions: yes/no, relevant (shares a content lemma with the player line, a present NPC or an open thread), not a repeat
public func askRelevant(q: String, player: String, world: World, earlier: [String]) -> Bool {
  if isWQuestion(q) { return false }
  let ql = Set(contentWords(q).map(lemma)); guard !ql.isEmpty else { return false }
  var ctx = Set(contentWords(player).map(lemma))
  for n in world.npcs where n.anwesend && !n.tot { ctx.formUnion(tokens(n.name).map(lemma)); ctx.formUnion(contentWords(n.kurz).map(lemma)) }
  for t in world.straenge where t.stufe != "antwort" { ctx.formUnion(contentWords(t.titel).map(lemma)) }
  if ql.isDisjoint(with: ctx) { return false }
  for old in earlier { let o = Set(contentWords(old).map(lemma)); if !o.isEmpty, Double(o.intersection(ql).count) / Double(max(o.count, ql.count)) >= 0.7 { return false } }
  return true
}
extension Game { func askAllowed(q: String, player: String) -> Bool { askRelevant(q: q, player: player, world: world, earlier: sceneQs + turnQA.map(\.q)) } }

final class Box<T> { var value: T; init(_ v: T) { value = v } }
extension Game {
  /// aux yes/no: only called for flagged narrations (+1.5 s), saves the 5-10 s regeneration on false alarms
  func secondOpinionContradicts(answer: String, question: String, narration: String) -> Bool {
    let user = "Frage ans Orakel: \(question)\nOrakel-Antwort: \(answer)\nErzählung: \(clean(narration, 600))\nWiderspricht die Erzählung der Orakel-Antwort? Antworte ja oder nein.\nAusgabe:"
    guard let (txt, _) = try? lm.aux(system: "Du prüfst, ob eine Erzählung einem Orakelergebnis widerspricht. JA/JA+ = die Sache trifft zu oder gelingt, NEIN/NEIN+ = sie trifft nicht zu oder misslingt. Antworte nur mit ja oder nein.", user: user, Grammar(.or([.s("ja"), .s("nein")])), temp: 0.0, maxTok: 4) else { return true }
    if debug { out(.info("[debug] Zweitmeinung Orakel: \(txt)")) }
    return txt.hasPrefix("ja")
  }
}
