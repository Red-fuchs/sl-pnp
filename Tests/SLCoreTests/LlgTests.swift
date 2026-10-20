import XCTest
import Tokenizers
import MLXLMCommon
import MLXGuidedGeneration
@testable import SLCore

/// One LlgTok per test run (0.7 s); skipped when the Gemma-4 tokenizer is not in the HF cache.
enum Llg {
  static let ctx: (tok: any MLXLMCommon.Tokenizer, llg: LlgTok)? = {
    guard let d = modelDir else { return nil }
    let sem = DispatchSemaphore(value: 0); nonisolated(unsafe) var t: (any Tokenizers.Tokenizer)?
    Task { t = try? await AutoTokenizer.from(modelFolder: d); sem.signal() }; sem.wait()
    guard let u = t else { return nil }
    let b = TokBridge(u: u)
    guard let l = try? LlgTok(tokenizerJSON: d.path + "/tokenizer.json", vocab: 262144, eos: 106, extraEos: [1, 50], encode: { b.encode(text: $0, addSpecialTokens: false) }) else { return nil }
    return (b, l)
  }()
}
private func ok(_ m: CMask, _ id: Int) -> Bool { (m.mask[id / 32] >> Int32(id % 32)) & 1 == 1 }

final class LlgTests: XCTestCase {
  func need() throws -> (tok: any MLXLMCommon.Tokenizer, llg: LlgTok) { guard let c = Llg.ctx else { throw XCTSkip("no model dir") }; return c }
  /// index of the first token the grammar rejects (nil = all accepted)
  func firstReject(_ c: Constraint, _ ids: [Int]) throws -> Int? {
    for (i, id) in ids.enumerated() { let m = try c.computeMask(); if !ok(m, id) { return i }; _ = try c.commit(Int32(id)) }
    return nil
  }
  let narr3 = "Die Wasserträger rasten am Tor. Der Wind trägt Staub herbei. Niemand spricht ein Wort"

  func testTokenizeFnMatchesHostBPE() throws {
    let (t, l) = try need()
    for s in ["trüb Glöckner <turn|>", " Salzlake glitzert", "Straße und Größe", "Ortswechsel/Zeitsprung: ja"] {
      XCTAssertEqual(l.tokenize(s).map { Int($0) }, t.encode(text: s, addSpecialTokens: false), s)
    }
  }
  func testUmlautRoundTrip() throws {
    let (t, l) = try need()
    let g = Grammar(.seq([.s("X: "), .or([.s("trüb"), .s("Glöckner"), .s("Straße"), .s("zzz")])]))
    for w in ["trüb", "Glöckner", "Straße"] {
      let c = try LlgConstraint(tok: l, lark: g.lark)
      XCTAssertNil(try firstReject(c, t.encode(text: "X: " + w, addSpecialTokens: false)), w)
      let m = try c.computeMask(); XCTAssertTrue(m.isTerminated && ok(m, 106), "EOS after accept")
      XCTAssertTrue(try c.commit(106).isTerminated)      // EOS after accept = no-op, no throw
    }
    let c = try LlgConstraint(tok: l, lark: g.lark)
    XCTAssertNotNil(try firstReject(c, t.encode(text: "X: trüc", addSpecialTokens: false)))
  }
  func testBanAcrossTokenBoundaries() throws {
    let (t, l) = try need()
    let g = Grammar(Gr.narr), tail = "\nFiguren: -"
    let ban = ["Salzlake", "Glöcknerin"]
    func run(_ s: String, ban: [String]) throws -> Int? { try firstReject(try LlgConstraint(tok: l, lark: g.lark(ban: ban)), t.encode(text: s, addSpecialTokens: false)) }
    let bad = narr3 + ". Die Salzlake glitzert." + tail
    XCTAssertNotNil(try run(bad, ban: ban)); XCTAssertNil(try run(bad, ban: []))       // blocked only with the ban
    XCTAssertNotNil(try run(narr3 + ". Die Glöcknerin schweigt." + tail, ban: ban))     // umlaut term
    XCTAssertNotNil(try run(narr3 + ". Die salzlaken stinken." + tail, ban: ban))      // lower case + inflection (stem)
    XCTAssertNil(try run(narr3 + ". Die Salzlage glitzert." + tail, ban: ban))         // near miss is fine
    XCTAssertNil(try run(narr3 + "." + tail, ban: ban))
  }
  func testRollbackAndClone() throws {
    let (t, l) = try need()
    let ids = t.encode(text: narr3 + ".\nFiguren: -", addSpecialTokens: false)
    let c = try LlgConstraint(tok: l, lark: Grammar(Gr.narr).lark)
    let m0 = try c.computeMask().mask
    var snap: [Int32] = [], cl: Constraint?
    for (i, id) in ids.enumerated() {
      if i == 10 { snap = try c.computeMask().mask; cl = try c.clone() }
      _ = try c.computeMask(); _ = try c.commit(Int32(id))
    }
    try c.rollback(ids.count); XCTAssertEqual(try c.computeMask().mask, m0)             // back to the start
    try c.rollback(0)
    XCTAssertEqual(try cl!.computeMask().mask, snap)                                  // clone independent of the original's progress
    for id in ids.dropFirst(10) { _ = try cl!.computeMask(); _ = try cl!.commit(Int32(id)) }
    let c2 = try LlgConstraint(tok: l, lark: Grammar(Gr.narr).lark)
    for id in ids { _ = try c2.computeMask(); _ = try c2.commit(Int32(id)) }
    XCTAssertEqual(try cl!.computeMask().mask, try c2.computeMask().mask)
    try c.rollback(0); for id in ids.prefix(5) { _ = try c.computeMask(); _ = try c.commit(Int32(id)) }   // reusable after rollback
  }
  func testNoForeignScriptsInFreeText() throws {
    let (t, l) = try need()
    let c = try LlgConstraint(tok: l, lark: Grammar(Gr.narr).lark(ban: ["Salzlake"]))
    for id in t.encode(text: "Die Wasserträger", addSpecialTokens: false) { _ = try c.computeMask(); _ = try c.commit(Int32(id)) }
    let m = try c.computeMask(); var n = 0, bad: [String] = []
    for id in 0..<262144 where ok(m, id) { n += 1; let s = t.convertIdToToken(id) ?? ""; if s.unicodeScalars.contains(where: { $0.value >= 0x0370 && $0.value < 0x2000 || $0.value >= 0x3000 }) { bad.append(s) } }
    XCTAssertGreaterThan(n, 3000); XCTAssertEqual(bad, [], "foreign-script tokens allowed")
  }
  func testPositivizeNegatedClasses() {
    let p = positivize(#"[^\n<]{6}[^\n<]*"#)
    XCTAssertFalse(p.contains("^")); XCTAssertTrue(p.contains("ä".unicodeScalars.first! == "ä" ? "\u{C0}" : ""))
    XCTAssertEqual(positivize("[A-Z]x[a-z]+"), "[A-Z]x[a-z]+")
  }
  /// every sl grammar (all Gate combinations, talk, delta, regie, world-gen) compiles as Lark, with and without a ban
  func testAllSlGrammarsCompile() throws {
    let (_, l) = try need()
    var gs: [(String, Grammar)] = [("talk", Gr.talk), ("delta", Gr.delta), ("regie", Gr.regie), ("slots", GenGr.slots), ("premise", GenGr.premise), ("premiseA", GenGr.premise(alltag: "Bergdorf im Alpental")),
      ("place", GenGr.place()), ("placeN", GenGr.place(name: "Brunnentor")), ("npc", GenGr.npc(name: "Zubeir", places: ["Brunnentor", "Basar"], npcs: ["Zubeir", "Kira"])),
      ("npcR", GenGr.npc(name: "Kira", places: ["Basar"], npcs: ["Kira"], role: "Wirt", place: "Basar", roles: GenGr.roles)), ("thread", GenGr.thread(refs: ["Brunnentor", "Zubeir"])), ("start", GenGr.start(places: ["Brunnentor", "Basar"]))]
    for bits in 0..<(1 << 9) {
      var g = Gate(); g.head = bits & 1 != 0; g.open = bits & 2 != 0; g.deut = bits & 4 != 0; g.forceEnd = bits & 8 != 0; g.figurLine = bits & 16 != 0; g.mustAsk = bits & 32 != 0
      g.noAsk = bits & 64 != 0; g.needFigur = bits & 128 != 0; g.selfQ = bits & 256 != 0
      for (a, ans) in [(0, String?.none), (2, "JA+"), (6, "NEIN")] { g.asks = a; g.ans = ans; g.figurNames = g.needFigur ? ["Kira", "Jaro Böhm", "Åse"] : []; gs.append(("gate\(bits)/\(a)", Gr.grammar(g))) }
    }
    var worst = 0.0
    for (n, g) in gs { for ban in [[], ["Salzlake", "Glöcknerin"]] {
      let t0 = Date()
      do { _ = try LlgConstraint(tok: l, lark: g.lark(ban: ban)) } catch { XCTFail("\(n) ban=\(ban.count): \(error)\n\(g.lark(ban: ban).prefix(600))"); return }
      worst = max(worst, Date().timeIntervalSince(t0))
    } }
    print("[llg] \(gs.count) grammars x2 compiled, worst \(Int(worst * 1000)) ms")
  }
}

/// ban coverage: every free-text (unbounded) regex of every sl grammar must carry the Lark ban; only %json strings rely on the token trie
final class LlgBanCoverageTests: XCTestCase {
  func res(_ g: G) -> [String] { switch g { case .re(let v): return LarkBuilder.isFree(v) ? [v] : []; case .seq(let e), .or(let e): return e.flatMap(res); default: return [] } }
  func testEveryFreeTerminalCarriesTheBan() {
    var gs: [Grammar] = [Gr.talk, Gr.regie, GenGr.slots, GenGr.premise, GenGr.place(), GenGr.npc(name: "Z", places: ["A", "B"], npcs: ["Z"]), GenGr.thread(refs: ["A", "B"]), GenGr.start(places: ["A", "B"])]
    for bits in 0..<(1 << 9) {
      var g = Gate(); g.head = bits & 1 != 0; g.open = bits & 2 != 0; g.deut = bits & 4 != 0; g.forceEnd = bits & 8 != 0; g.figurLine = bits & 16 != 0; g.mustAsk = bits & 32 != 0
      g.noAsk = bits & 64 != 0; g.needFigur = bits & 128 != 0; g.selfQ = bits & 256 != 0; g.ans = bits % 3 == 0 ? "JA+" : nil; g.art = bits % 5 == 0
      gs.append(Gr.grammar(g))
    }
    for g in gs {
      let free = Set(res(g.g)); guard !free.isEmpty else { continue }
      let l = g.lark(ban: ["Salzlake"]); let banned = l.components(separatedBy: "\n").filter { $0.hasPrefix("FREE") && $0.contains("& ~") }.count
      XCTAssertEqual(banned, free.count, "free terminals without ban in \(l.prefix(300))")
      XCTAssertEqual(l.components(separatedBy: "& ~").count - 1, banned)
    }
  }
}

final class LlgFuelProbe: XCTestCase {
  func testProbe() throws {
    guard let c = Llg.ctx else { throw XCTSkip("no model") }
    let all = ["Bittermandelöl", "panscht", "Brunnenwasser", "Schlüssel", "Zisterne", "Schmuggler", "heimlich", "Zeughaus", "Stadtgeheimnisse", "Kontamination", "akzeptiert", "Wachsspuren"]
    for n in [2, 4, 6, 8, 12] {
      let t0 = Date()
      do {
        let k = try LlgConstraint(tok: c.llg, lark: Grammar(Gr.narr).lark(ban: Array(all.prefix(n))))
        var worst = 0.0
        for id in c.tok.encode(text: "Die Wasserträger rasten am Tor. Der Wind trägt Staub herbei. Niemand spricht ein Wort. Im Hof liegt ein Eimer neben dem Brunnen, und die Wache starrt ins Leere.", addSpecialTokens: false) { let t1 = Date(); _ = try k.computeMask(); worst = max(worst, Date().timeIntervalSince(t1)); _ = try k.commit(Int32(id)) }
        print("[probe] \(n) terms ok \(Int(Date().timeIntervalSince(t0) * 1000)) ms, worst mask \(Int(worst * 1000)) ms") }
      catch { print("[probe] \(n) terms FAIL \(error) \(Int(Date().timeIntervalSince(t0) * 1000)) ms") }
    }
  }
}

final class LlgWorldGenTests: XCTestCase {
  func need() throws -> (tok: any MLXLMCommon.Tokenizer, llg: LlgTok) { guard let c = Llg.ctx else { throw XCTSkip("no model dir") }; return c }
  func fire(_ c: Constraint, _ ids: [Int]) throws -> Int? {
    for (i, id) in ids.enumerated() { let m = try c.computeMask(); if !ok(m, id) { return i }; _ = try c.commit(Int32(id)) }
    return nil
  }
  /// every world-gen stage must accept its own few-shot example, end exactly there (EOS only) and show no path-dependent surprises
  func testAllStagesAcceptExample() throws {
    let (t, l) = try need()
    let refs = ["Brunnentor", "Zubeir", "Basar"]
    let stages: [(String, Grammar, String)] = [
      ("slots", GenGr.slots, GenPromptEx.slots),
      ("premise", GenGr.premise, GenPromptEx.premise),
      ("place", GenGr.place(), GenPromptEx.place),
      ("thread", GenGr.thread(refs: refs), GenPromptEx.thread),
      ("npc", GenGr.npc(name: "Zubeir", places: ["Brunnentor", "Basar"], npcs: ["Zubeir"]), GenPromptEx.npc),
      ("start", GenGr.start(places: ["Brunnentor", "Basar"]), GenPromptEx.start.replacingOccurrences(of: "Start: Brunnentor", with: "Start: Brunnentor")),
    ]
    for (n, g, ex) in stages {
      let c = try LlgConstraint(tok: l, lark: g.lark)
      let ids = t.encode(text: ex, addSpecialTokens: false)
      let r = try fire(c, ids)
      XCTAssertNil(r, "\(n): rejected at token \(r ?? -1) of \(ids.count): \(r.map { t.decode(tokenIds: Array(ids[max(0, $0 - 3)...$0])) } ?? "")")
      if r == nil { XCTAssertTrue(try c.computeMask().isTerminated || ok(try c.computeMask(), 106), "\(n): EOS not allowed after example") }
    }
  }
}

final class SaeulenGateTests: XCTestCase {   // N4
  func testRiskyActionMustAskOracle() throws {
    guard let (t, l) = Llg.ctx else { throw XCTSkip("no model dir") }
    var g = Gate(); g.head = true; g.open = true; g.art = true
    let head = "Erwartung: Der Wächter zieht blank und greift an.\nOrtswechsel/Zeitsprung: nein\nFrage: -\nArt: "
    func rejectAt(_ art: String) throws -> Int? {
      let c = try LlgConstraint(tok: l, lark: Gr.grammar(g).lark)
      var ids = t.encode(text: head + art + "\nWerkzeug: nein\n", addSpecialTokens: false)
      for (i, id) in ids.enumerated() { let m = try c.computeMask(); if (m.mask[id / 32] >> Int32(id % 32)) & 1 == 0 { return i }; _ = try c.commit(Int32(id)) }
      ids.removeAll(); return nil
    }
    XCTAssertNil(try rejectAt("sonst"))
    for a in ["kampf", "sozial", "wissen"] { XCTAssertNotNil(try rejectAt(a), a) }
    g.asks = 99          // no oracle budget left: the model may narrate
    XCTAssertNil(try rejectAt("kampf"))
  }
  func testOddsLabel() {
    XCTAssertEqual(oddsLabel(["odds": .int(0)]), oddsText(0))
    XCTAssertTrue(oddsLabel(["odds": .int(0), "shift": .int(1)]).contains("+1"))
  }
}

private func firstRejectIn(_ c: Constraint, _ ids: [Int]) throws -> Int? {
  for (i, id) in ids.enumerated() { let m = try c.computeMask(); if (m.mask[id / 32] >> Int32(id % 32)) & 1 == 0 { return i }; _ = try c.commit(Int32(id)) }
  return nil
}
final class RiskGateTests: XCTestCase {   // P4
  func testRiskArt() {
    let risky = ["Ich schleiche an der Wache vorbei.", "Ich springe über die Schlucht.", "Ich breche die Eisentür auf.", "Ich klettere die Mauer hoch.", "Ich schwimme durch den Fluss.", "Ich greife den Wächter an.", "Ich überrede den Zöllner, mich durchzulassen.", "Ich belüge den Wirt über meine Herkunft.", "Ich stehle dem Händler den Beutel.", "Ich trete die Tür ein."]
    let trivial = ["Ich trinke etwas Wasser.", "Ich schaue aus dem Fenster.", "Ich nicke der Wache zu.", "Ich gehe zur Tür.", "Ich sehe mich um.", "Ich frage den Wirt nach dem Weg.", "Ich nehme den Schlüssel vom Tisch.", "Ich öffne die Tür.", "Ich setze mich ans Feuer.", "Ich erkenne die Geste."]
    XCTAssertEqual(risky.filter { classifyAction($0) != nil }.count, 10, "\(risky.filter { classifyAction($0) == nil })")
    XCTAssertEqual(trivial.filter { classifyAction($0) != nil }.count, 0, "\(trivial.filter { classifyAction($0) != nil })")
    XCTAssertEqual(classifyAction("Ich erschieße Oruiel mit der Armbrust, direkt ins Herz."), .kill)
    XCTAssertEqual(classifyAction("Ich steche dem Waffenmeister den Dolch mitten in die Brust."), .kill)
    XCTAssertEqual(classifyAction("Ich überrede den Zöllner."), .risky(.sozial))
    XCTAssertEqual(classifyAction("Ich klettere die Mauer hoch."), .risky(.sonst))
  }
  func testRiskyForcesOracleAndArt() throws {
    guard let (t, l) = Llg.ctx else { throw XCTSkip("no model dir") }
    var g = Gate(); g.head = true; g.open = true; g.art = true; g.risky = .kampf
    let head = "Erwartung: Der Wächter zieht blank.\nOrtswechsel/Zeitsprung: nein\nFrage: "
    func rej(_ rest: String) throws -> Bool {
      let c = try LlgConstraint(tok: l, lark: Gr.grammar(g).lark)
      for id in t.encode(text: head + rest, addSpecialTokens: false) { let m = try c.computeMask(); if (m.mask[id / 32] >> Int32(id % 32)) & 1 == 0 { return true }; _ = try c.commit(Int32(id)) }
      return false
    }
    XCTAssertTrue(try rej("-\nArt: sonst\nWerkzeug: nein\n"))             // no narration-only head
    let c0 = try LlgConstraint(tok: l, lark: Gr.grammar(g).lark)
    XCTAssertNotNil(try firstRejectIn(c0, t.encode(text: "Erwartung: Der Wächter zieht blank.\nOrtswechsel/Zeitsprung: ja\n", addSpecialTokens: false)))   // no scene change either
    XCTAssertTrue(try rej("Trifft der Hieb?\nArt: sozial\nWerkzeug: ja\n"))   // wrong Art
    XCTAssertFalse(try rej("Trifft der Hieb?\nArt: kampf\nWerkzeug: ja\n"))
  }
}
