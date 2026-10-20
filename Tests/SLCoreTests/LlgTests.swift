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
