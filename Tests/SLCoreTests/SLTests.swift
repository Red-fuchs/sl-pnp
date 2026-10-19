import XCTest
import Tokenizers
import MLXLMCommon
import MLXGuidedGeneration
import Schicksal
@testable import SLCore

let modelDir: URL? = {
  let b = NSHomeDirectory() + "/.cache/huggingface/hub/models--zecanard--gemma-4-E4B-it-ultra-uncensored-heretic-MLX-4bit-mixed_4_6/snapshots"
  guard let s = (try? FileManager.default.contentsOfDirectory(atPath: b))?.sorted().first else { return nil }
  return URL(fileURLWithPath: b + "/" + s)
}()

final class PromptTests: XCTestCase {
  func testRender() {
    XCTAssertEqual(render(sys: " S ", [.u("a"), .m("b ")]), "<bos><|turn>system\nS<turn|>\n<|turn>user\na<turn|>\n<|turn>model\nb<turn|>\n")
  }
  func testChatML() {
    XCTAssertEqual(Tmpl.chatml.render(sys: "S", [.u("a"), .m("b")]), "<|startoftext|><|im_start|>system\nS<|im_end|>\n<|im_start|>user\na<|im_end|>\n<|im_start|>assistant\n<think></think>b<|im_end|>\n")
    XCTAssertEqual(Tmpl.chatml.gen, "<|im_start|>assistant\n<think></think>")
    XCTAssertEqual(Tmpl.gemma.gen, "<|turn>model\n")
  }
  func testFewShotShape() throws {
    // narration lines of the few-shot must satisfy the same regex the grammar enforces
    let re = try NSRegularExpression(pattern: "^" + Gr.narrPattern + "$")
    var n = 0
    for m in FEW where m.role == "model" {
      guard let last = m.text.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init), !last.hasPrefix("<") else { continue }
      n += 1
      XCTAssertNotNil(re.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)), "narr mismatch: \(last)")
    }
    XCTAssertGreaterThan(n, 3)
  }
  func testParseCall() {
    let (n, a) = parseCall("Erwartung: x\nFrage: Ist er da?\nWerkzeug: ja\n<ask_oracle>{\"odds\":1}</ask_oracle>")!
    XCTAssertEqual(n, "ask_oracle"); XCTAssertEqual(a["q"].str, "Ist er da?"); XCTAssertEqual(a["odds"].int, 1)
    XCTAssertNil(parseCall("Nur Erzählung."))
  }
  func testEvInfo() {
    let r: J = ["answer": "JA", "event": ["dir": "akteur_handelt", "target": ["name": "Vogt"], "words": [["erpressen", "Siegel"]]]]
    XCTAssertEqual(evInfo("ask_oracle", r), EvInfo(head: "akteur_handelt (Vogt)", words: "erpressen + Siegel"))
    XCTAssertNil(evInfo("ask_oracle", ["answer": "NEIN", "event": nil]))
    let v: J = ["outcome": "variiert", "mut": [["op": "ersetzen", "el": "ort", "words": ["a", "b"]]]]
    XCTAssertEqual(evInfo("start_scene", v)?.words, "a + b")
  }
}

final class DispatchTests: XCTestCase {
  func testStateMachine() throws {
    let e = try Session.newEngine(rng: "seed:3")
    XCTAssertFalse(e.st.open)
    // head_scene: no open scene -> only start_scene after "ja", never ask/nein
    let g0 = Gr.grammar({ var g = Gate(); g.head = true; return g }()).tag
    XCTAssertTrue(g0.contains("start_scene")); XCTAssertFalse(g0.contains("ask_oracle")); XCTAssertFalse(g0.contains("Werkzeug: nein")); XCTAssertFalse(g0.contains("end_scene")); XCTAssertFalse(g0.contains("Spielfigur"))
    // first:true is injected by the harness, not by the model
    var (n, a) = parseCall("<start_scene>{\"expect\":\"x\",\"el\":{\"ort\":\"o\",\"beteiligte\":\"b\"}}</start_scene>", firstScene: true)!
    XCTAssertEqual(a["first"].bool, true)
    var r = e.call(n, a); XCTAssertEqual(r["outcome"].str, "erwartet", "\(r)"); XCTAssertTrue(e.st.open)
    XCTAssertEqual(parseCall("<start_scene>{\"expect\":\"x\"}</start_scene>")!.1["first"], .null)
    (n, a) = parseCall("Frage: Ist jemand da?\n<ask_oracle>{\"q\":\"andere\",\"odds\":1}</ask_oracle>")!
    XCTAssertEqual(a["q"].str, "Ist jemand da?")  // q := Frage line
    r = e.call(n, a); XCTAssertNotNil(r["answer"].str, "\(r)"); XCTAssertEqual(e.st.q, 1)
    XCTAssertTrue(fmtResult(n, r).hasPrefix("[Orakel] Antwort: "))
    XCTAssertFalse(fmtResult(n, r).contains("roll")); XCTAssertFalse(fmtResult(n, r).contains("step"))
    var g = Gate(); g.open = true; g.head = true
    let g1 = Gr.grammar(g).tag
    XCTAssertTrue(g1.contains("ask_oracle")); XCTAssertTrue(g1.contains("end_scene")); XCTAssertFalse(g1.contains("<start_scene>"))
    // end_scene is only reachable behind "Ortswechsel/Zeitsprung: ja"; mustAsk drops the narration-only branch
    XCTAssertTrue(g1.contains("Ortswechsel/Zeitsprung: ja")); XCTAssertTrue(g1.contains("Werkzeug: nein"))
    g.mustAsk = true; XCTAssertFalse(Gr.grammar(g).tag.contains("Werkzeug: nein")); g.mustAsk = false
    g.figurLine = true; XCTAssertTrue(Gr.grammar(g).tag.contains("Spielfigur: ")); g.figurLine = false
    (n, a) = parseCall("<end_scene>{\"summary\":\"s\",\"why\":\"w\",\"control\":true}</end_scene>")!
    r = e.call(n, a); XCTAssertNil(r["error"].str); XCTAssertFalse(e.st.open)
    XCTAssertTrue(fmtResult(n, r).hasPrefix("[Orakel] Szene beendet. Die Lage wird "))
    // after end_scene: narr or start_scene only (no ask)
    g.open = false; g.head = false
    let g2 = Gr.grammar(g).tag
    XCTAssertTrue(g2.contains("<start_scene>")); XCTAssertFalse(g2.contains("ask_oracle"))
    // BIND: actual answer is a fixed string; event adds Deutung (verwerfen allowed) then narration
    g.open = true; g.ans = "NEIN+"; g.deut = true
    let g3 = Gr.grammar(g).tag
    XCTAssertTrue(g3.contains("Antwort: NEIN+ → ")); XCTAssertFalse(g3.contains("Antwort: JA")); XCTAssertTrue(g3.contains("Deutung: ")); XCTAssertTrue(g3.contains("verwerfen")); XCTAssertFalse(g3.contains("<start_scene>"))
    // question budget
    g = Gate(); g.open = true; g.asks = 6; g.head = true
    XCTAssertFalse(Gr.grammar(g).tag.contains("ask_oracle"))
  }
  func testFormats() {
    XCTAssertEqual(fmtResult("start_scene", ["outcome": "variiert", "scene": 2, "mut": [["op": "hinzufuegen", "el": "beteiligte", "words": ["trauern", "Glocke"]]]]),
                   "[Orakel] Szene 2 beginnt anders als erwartet.\n[Orakel] Änderung: beteiligte hinzufuegen – Wörter: trauern + Glocke")
    XCTAssertEqual(fmtResult("ask_oracle", ["answer": "JA+", "event": ["dir": "akteur_handelt", "target": ["name": "Hauptmann Rejk"], "words": [["verbergen", "Siegel"]]]]),
                   "[Orakel] Antwort: JA+\n[Orakel] Ereignis: akteur_handelt (Hauptmann Rejk) – eine Figur handelt. Wörter: verbergen + Siegel")
    XCTAssertEqual(fmtResult("end_scene", ["s": 4, "s_before": 5]), "[Orakel] Szene beendet. Die Lage wird ruhiger.")
    XCTAssertEqual(fmtKnown(["Wirt"], []), "[Bekannt] Figuren: Wirt. Stränge: -.")
  }
  func testBadArgsRejected() throws {
    let e = try Session.newEngine(rng: "seed:3")
    XCTAssertNotNil(e.call("ask_oracle", ["q": "x", "odds": 9])["error"].str)
  }
}

final class WorldTests: XCTestCase {
  func blocks() -> [String] {
    FEW.filter { $0.role == "user" && $0.text.hasPrefix("[Welt]") }.map { String($0.text[..<$0.text.range(of: "\n---\n")!.lowerBound]) }
  }
  func testBlockMatchesFewShot() {
    var w = World(); w.setFigur("verschlossener Matrose mit vernarbter Hand"); w.ort = "Deck"
    w.apply(["npc_neu": [["name": "Steuermann", "kurz": "breiter Mann am Ruder", "ort": "Deck"]]])
    let b = blocks()
    XCTAssertEqual(b.count, 5); XCTAssertEqual(w.block(), b[0])
    w.apply(["npc_neu": [["name": "Steuermann", "kurz": "Kapitän, breiter Mann am Ruder", "ort": "Deck"]], "haltung": [["wer": "Steuermann", "wert": -1]]])
    XCTAssertEqual(w.block(), b[1])
    w.apply(["zustand": [["wer": "du", "op": "+", "text": "Knie aufgeschlagen"]], "haltung": [["wer": "Steuermann", "wert": -2]]])
    XCTAssertEqual(w.block(), b[3])
  }
  func testApply() throws {
    let e = try Session.newEngine(rng: "seed:9")
    var w = World(); w.setFigur("Aether: grauer Mann"); w.ort = "Taverne"
    XCTAssertEqual(w.name, "Aether"); XCTAssertEqual(w.kurz, "grauer Mann")
    let log = w.apply(["npc_neu": [["name": "Aether", "kurz": "x", "ort": "Taverne"], ["name": "du", "kurz": "x", "ort": "Taverne"], ["name": "Wirtin", "kurz": "stämmig", "ort": "Taverne"], ["name": "Bote", "kurz": "Läufer", "ort": "Markt"]],
                       "npc_ort": [["wer": "Niemand", "ort": "Keller"]], "haltung": [["wer": "Wirtin", "wert": 7], ["wer": "Geist", "wert": 1]],
                       "item": [["wer": "du", "op": "+", "name": "Laterne"], ["wer": "Wirtin", "op": "+", "name": "Schlüssel"]],
                       "strang": [["titel": "Der Fluch", "stand": "Hinweis gefunden"]], "beziehung": [["a": "Wirtin", "b": "du", "wert": 5], ["a": "Wirtin", "b": "Wirtin", "wert": 1]]], eng: e)
    XCTAssertEqual(w.npcs.map(\.name), ["Wirtin", "Bote"])            // player character never an NPC, unknown refs ignored
    XCTAssertEqual(w.npcs[0].haltung, 2); XCTAssertEqual(w.inventar, ["Laterne"]); XCTAssertEqual(w.beziehungen, [Rel(a: "Wirtin", b: "du", wert: 2)])
    XCTAssertEqual(e.st.akteure.map(\.name), ["Wirtin", "Bote"]); XCTAssertEqual(e.st.straenge.map(\.name), ["Der Fluch"])   // Schicksal lists synced
    XCTAssertFalse(log.isEmpty)
    let b = w.block()
    XCTAssertTrue(b.contains("Hier: Wirtin – stämmig (trägt Schlüssel; Haltung zu dir: loyal)")); XCTAssertTrue(b.contains("Anderswo: Bote (Markt)")); XCTAssertTrue(b.contains("Du: Aether, grauer Mann. Ort: Taverne. Inventar: Laterne."))
    XCTAssertEqual(w.haltung(in: "Hilft die Wirtin mir?"), 2); XCTAssertNil(w.haltung(in: "Ist der Bote da?"))
    w.apply(["strang": [["titel": "Der Fluch", "stand": "gelöst"]]], eng: e)                                  // existing thread: update + bump
    XCTAssertEqual(w.straenge.count, 1); XCTAssertEqual(w.straenge[0].stand, "gelöst")
    for i in 0..<30 { w.apply(["npc_neu": [["name": .str("N\(i)"), "kurz": "k", "ort": "Weit"]]]) }
    XCTAssertLessThanOrEqual(w.npcs.count, 20)
  }
  func testPersistAndStrip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sl-w-\(UUID().uuidString)")
    let s = try Session(name: "w", root: root); var w = World(); w.setFigur("Aether: Mann"); w.apply(["npc_neu": [["name": "Wirt", "kurz": "k", "ort": "Hier"]]])
    try s.save(try Session.newEngine(rng: "seed:1"), "S", [.u("a")], "Aether: Mann", 0, w)
    XCTAssertEqual(try s.loadEngine().world, w)
    XCTAssertEqual(stripWelt("[Welt]\nDu: x.\n---\nIch gehe."), "Ich gehe."); XCTAssertEqual(stripWelt("Ich gehe."), "Ich gehe.")
    // cache stability: the system prompt does not depend on the world, history only appends
    let a = render(sys: SYS, [.u("[Welt]\nDu: x.\n---\nZug1"), .m("A")]), b = render(sys: SYS, [.u("[Welt]\nDu: x.\n---\nZug1"), .m("A"), .u("[Welt]\nDu: y.\n---\nZug2")])
    XCTAssertTrue(b.hasPrefix(a)); XCTAssertFalse(SYS.contains("[Welt]\nDu:"))
  }
  func testParseFigur() {
    XCTAssertEqual(World.parseFigur("Aether: grauer Mann, 40").0, "Aether"); XCTAssertEqual(World.parseFigur("Aether, grauer Mann").1, "grauer Mann")
    XCTAssertNil(World.parseFigur("ein grauer Mann mit Brille").0)
  }
}

final class CmdTests: XCTestCase {
  func testDispatcher() {   // one parser for CLI and web
    XCTAssertEqual(Cmd.parse("/figur Aether: grauer Mann"), .figur("Aether: grauer Mann"))
    XCTAssertEqual(Cmd.parse("/figur"), .figur("")); XCTAssertEqual(Cmd.parse("/welt"), .welt); XCTAssertEqual(Cmd.parse("/ende"), .ende)
    XCTAssertEqual(Cmd.parse("/frage+2 Ist er da?"), .frage("Ist er da?", 2)); XCTAssertEqual(Cmd.parse("/frage-1 x"), .frage("x", -1))
    XCTAssertEqual(Cmd.parse("/neu Piraten"), .neu("Piraten")); XCTAssertEqual(Cmd.parse("/foo"), .unknown("/foo")); XCTAssertEqual(Cmd.parse("ich gehe"), .say("ich gehe"))
    XCTAssertNil(groundedFigur("Matrose", "ich betrete die Taverne in Grauweiler und setze mich an einen Tisch"))
  }
}

final class NameHintTests: XCTestCase {
  func testHints() throws {
    let h = World.nameHints("Ich betrete die Taverne. Die Wirtin Marta wischt die Theke. Neben ihr steht Bork, der Fährmann, und die Wache Tom lacht. ")
    XCTAssertEqual(Set(h.map(\.name)), ["Marta", "Tom", "Bork"])
    XCTAssertTrue(h.contains { $0.name == "Marta" && $0.role == "Wirtin" }); XCTAssertTrue(h.contains { $0.name == "Bork" && $0.role == "Fährmann" })
    XCTAssertTrue(World.nameHints("Die Wirtin wischt. Sie nickt. Der Wirt schweigt.").isEmpty)
    let e = try Session.newEngine(rng: "seed:2")
    var w = World(); w.setFigur("Aether: Mann"); w.ort = "Taverne"
    w.apply(["figuren": [["name": "Wirtin", "kurz": "Wirtin", "ort": "Taverne"]]], eng: e)       // role-named NPC from the delta step
    w.adoptNames(World.nameHints("Die Wirtin Marta wischt."), eng: e)
    XCTAssertEqual(w.npcs.map(\.name), ["Marta"]); XCTAssertEqual(e.st.akteure.map(\.name), ["Marta"])
    XCTAssertTrue(w.block().contains("Hier: Marta – Wirtin"))
    w.adoptNames(World.nameHints("Aether sieht die Wirtin Aether."), eng: e); XCTAssertEqual(w.npcs.count, 1)   // the player character never becomes an NPC
  }
}

final class MiscTests: XCTestCase {
  func testClip() {
    let long = String(repeating: "x", count: 500)
    let a = clip(["q": .str(long), "el": ["ort": .str(long)], "odds": 1])
    XCTAssertEqual(a["q"].str?.count, 200); XCTAssertEqual(a["el"]["ort"].str?.count, 80); XCTAssertEqual(a["odds"].int, 1)
  }
  func testGroundedFigur() {
    XCTAssertEqual(groundedFigur("grauer Mann mit Brille", "Ein grauer Mann ende 40 mit lila Brille betritt die Taverne"), "grauer Mann mit Brille")
    XCTAssertTrue(groundedFigur("Matrose", "Ein grauer Mann ende 40 mit lila Brille betritt die Taverne")!.hasPrefix("Ein grauer Mann"))
  }
  func testWQuestion() {
    for q in ["wo bin ich?", "Wer ist das?", "welcher Weg führt hinaus", "wie viele Gäste sind da?"] { XCTAssertTrue(isWQuestion(q), q) }
    for q in ["Ist die Tür offen?", "Bin ich noch in Grauweiler?", "Wirt kennt mich?"] { XCTAssertFalse(isWQuestion(q), q) }
  }
  func testGatePrefix() {
    XCTAssertTrue(isGatePrefix("Ortswechsel/Zeit")); XCTAssertTrue(isGatePrefix("Ortswechsel/Zeitsprung: nein")); XCTAssertTrue(isGatePrefix("Er"))
    XCTAssertFalse(isGatePrefix("Der Regen peitscht")); XCTAssertFalse(isGatePrefix("Das Deck"))
  }
  func testHttpHeader() {
    let h = "POST /say HTTP/1.1\r\nHost: 127.0.0.1:8791\r\nContent-Length: 12\r\nOrigin: http://x"
    XCTAssertEqual(httpHeader(h, "host"), "127.0.0.1:8791"); XCTAssertEqual(httpHeader(h, "content-length"), "12")
    XCTAssertEqual(httpHeader(h, "origin"), "http://x"); XCTAssertNil(httpHeader(h, "x-none"))
  }
  func testEndSceneLists() throws {
    let e = try Session.newEngine(rng: "seed:4")
    _ = e.call("start_scene", ["expect": "x", "first": true])
    let (n, a) = parseCall("<end_scene>{\"summary\":\"s\",\"why\":\"w\",\"control\":true,\"akteure\":[{\"op\":\"add\",\"name\":\"Der Wirt\"}]}</end_scene>")!
    XCTAssertNil(e.call(n, a)["error"].str); XCTAssertEqual(e.st.akteure.first?.name, "Der Wirt")
    XCTAssertEqual(fmtKnown(e.st.akteure.map(\.name), []), "[Bekannt] Figuren: Der Wirt. Stränge: -.")
  }
  func testSessionLock() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sl-lock-\(UUID().uuidString)")
    let s1 = try Session(name: "x", root: root)
    XCTAssertThrowsError(try Session(name: "x", root: root))   // second holder refused
    XCTAssertThrowsError(try Session(name: "nope", root: root, mustExist: true))
    _ = s1
  }
}

final class SessionTests: XCTestCase {
  func testSaveResume() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sl-test-\(UUID().uuidString)")
    let s = try Session(name: "t", root: root)
    XCTAssertFalse(s.exists)
    let e = try Session.newEngine(rng: "seed:5")
    _ = e.call("start_scene", ["expect": "x", "first": true])
    let msgs: [Msg] = [.u("hi"), .m("Erwartung: …")]
    try s.save(e, "Setting X", msgs)
    XCTAssertTrue(s.exists)
    let (e2, set, m2, _, _, _) = try s.loadEngine()
    XCTAssertEqual(set, "Setting X"); XCTAssertEqual(m2, msgs)
    XCTAssertTrue(e2.st.open); XCTAssertEqual(e2.st.scene, 1); XCTAssertEqual(e2.st.step, e.st.step)
    // seed engine continues deterministically after reload
    XCTAssertEqual(e.call("ask_oracle", ["q": "q", "odds": 0])["roll"], e2.call("ask_oracle", ["q": "q", "odds": 0])["roll"])
    XCTAssertEqual(Session.latest(root: root), "t")
  }
}

final class GrammarTests: XCTestCase {
  func tok() async throws -> (any MLXLMCommon.Tokenizer, GrammarTokenizer) {
    guard let d = modelDir else { throw XCTSkip("no model dir") }
    let t = TokBridge(u: try await AutoTokenizer.from(modelFolder: d))
    let v = TokenizerVocabExtractor.extractForGrammar(from: t)
    return (t, try GrammarTokenizer(vocab: v.vocab, vocabType: v.vocabType, eosTokenId: 106))
  }
  func testSpecialTokens() async throws {
    let (t, _) = try await tok()
    XCTAssertEqual(t.encode(text: "<|turn>model\n", addSpecialTokens: false).first, t.convertTokenToId("<|turn>"))
    XCTAssertEqual(t.convertTokenToId("<turn|>"), 106)
    XCTAssertEqual(t.encode(text: "<bos>x", addSpecialTokens: false).first, 2)
  }
  func testDeltaGrammar() async throws {
    let (t, gt) = try await tok()
    let t0 = Date()
    for txt in [#"{"figuren":[]}"#, #"{"figuren":[{"kurz":"Köhlerin","name":"Ida","ort":"Hütte"}],"spielfigur_ort":"Hütte"}"#, #"{"figuren":[{"kurz":"Fährmann","name":"Bork","ort":"Flussufer"}],"haltung":[{"wer":"Bork","wert":-1}],"item":[{"name":"zwei Silberstücke","op":"-","wer":"du"}]}"#, #"{"figuren":[],"spielfigur_ort":"Keller","zustand":[{"op":"+","text":"verletzt","wer":"du"}]}"#, DELTA_SYS.components(separatedBy: "Ausgabe: ")[1].components(separatedBy: "\n")[0]] {
      let c = try GrammarConstraint(tokenizer: gt, structuralTag: Gr.delta.tag)
      for id in t.encode(text: txt, addSpecialTokens: false) {
        let r = try c.computeMask()
        XCTAssertTrue(!r.needsApply || (r.mask[id / 32] >> Int32(id % 32)) & 1 == 1, "delta rejected: \(txt)")
        _ = try c.commitToken(Int32(id))
      }
      let r = try c.computeMask(); XCTAssertTrue(!r.needsApply || (r.mask[106 / 32] >> Int32(106 % 32)) & 1 == 1, "no end: \(txt)")
    }
    print(String(format: "delta grammar compile+check %.2fs", Date().timeIntervalSince(t0)))
  }
  /// no Fork in xgrammar 0.1.30: a used matcher must be reusable after rollback
  func testRollbackReuse() async throws {
    let (t, gt) = try await tok()
    let c = try GrammarConstraint(tokenizer: gt, structuralTag: Gr.grammar({ var g = Gate(); g.head = true; g.figurLine = true; return g }()).tag)
    let ids = t.encode(text: FEW[1].text, addSpecialTokens: false)
    for round in 0..<2 {
      for id in ids { let r = try c.computeMask(); XCTAssertTrue(!r.needsApply || (r.mask[id / 32] >> Int32(id % 32)) & 1 == 1, "round \(round)"); _ = try c.commitToken(Int32(id)) }
      try c.rollback(Int32(ids.count))
    }
  }
  /// every few-shot model message must be accepted by the grammar of its state and be able to terminate
  func testFewShotAcceptedByGrammar() async throws {
    let (t, gt) = try await tok()
    func G(_ f: (inout Gate) -> Void) -> Gate { var g = Gate(); f(&g); return g }
    let gates: [Gate] = [
      G { $0.head = true; $0.figurLine = true },                        // start_scene (head_scene, first turn)
      G { $0.open = true; $0.calls = 1 },                               // narr
      G { $0.head = true; $0.open = true },                             // ask
      G { $0.open = true; $0.asks = 1; $0.ans = "JA"; $0.calls = 1 },
      G { $0.head = true; $0.open = true; $0.asks = 1 },                // nein + narr (no scene change)
      G { $0.head = true; $0.open = true; $0.asks = 1 },                // ask
      G { $0.open = true; $0.asks = 2; $0.ans = "NEIN+"; $0.deut = true; $0.calls = 1 },
      G { $0.head = true; $0.open = true; $0.asks = 2 },                // ask
      G { $0.open = true; $0.asks = 3; $0.ans = "NEIN"; $0.deut = true; $0.calls = 1 },   // verwerfen
      G { $0.head = true; $0.open = true; $0.asks = 3 },                // end_scene
      G { $0.open = false; $0.calls = 1 },                              // start_scene w/o head
      G { $0.open = true; $0.deut = true; $0.calls = 1 },
    ]
    let ms = FEW.filter { $0.role == "model" }
    XCTAssertEqual(ms.count, gates.count)
    for (m, g) in zip(ms, gates) {
      let t0 = Date()
      let c = try GrammarConstraint(tokenizer: gt, structuralTag: Gr.grammar(g).tag)
      let ct = Date().timeIntervalSince(t0)
      let ids = t.encode(text: m.text, addSpecialTokens: false)
      func allowed(_ r: MaskResult, _ id: Int) -> Bool { !r.needsApply || (r.mask[id / 32] >> Int32(id % 32)) & 1 == 1 }
      for (i, id) in ids.enumerated() {
        let r = try c.computeMask()
        XCTAssertTrue(allowed(r, id), "token \(i) '\(t.convertIdToToken(id) ?? "")' rejected in: \(m.text.prefix(80))… after '\(t.decode(tokenIds: Array(ids[..<i])).suffix(40))'")
        if !allowed(r, id) { break }
        _ = try c.commitToken(Int32(id))
      }
      XCTAssertTrue(allowed(try c.computeMask(), 106), "cannot terminate: \(m.text.prefix(60))")
      print(String(format: "compile %.2fs  %d tok  %@", ct, ids.count, String(m.text.prefix(30))))
    }
  }
}
