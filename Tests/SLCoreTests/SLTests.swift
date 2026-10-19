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
      guard let last = splitTail(m.text).body.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init), !last.hasPrefix("<") else { continue }
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
    w.applyTail("Figuren: Steuermann (breiter Mann am Ruder)")
    let b = blocks()
    XCTAssertEqual(b.count, 5); XCTAssertEqual(w.block(), b[0])
    w.applyTail("Figuren: Steuermann (Kapitän)"); w.apply(["haltung": [["wer": "Steuermann", "wert": -1]]])
    XCTAssertEqual(w.block(), b[1])
    w.apply(["zustand": [["wer": "du", "op": "+", "text": "Knie aufgeschlagen"]], "haltung": [["wer": "Steuermann", "wert": -2]]])
    XCTAssertEqual(w.block(), b[3])
  }
  func testLookupWholeTokens() {      // finding 1
    var w = World(); w.ort = "Hof"
    w.addNpc(name: "Ida", kurz: "Köhlerin", ort: "Hof"); w.addNpc(name: "Bork", kurz: "Fährmann", ort: "Hof"); w.addNpc(name: "Wache", kurz: "Torwache", ort: "Hof")
    w.addNpc(name: "Idalia", kurz: "Magd", ort: "Hof"); w.addNpc(name: "Borka", kurz: "Bäuerin", ort: "Hof")
    XCTAssertEqual(w.npcs.map(\.name), ["Ida", "Bork", "Wache", "Idalia", "Borka"])   // distinct people, no prefix merge
    XCTAssertEqual(w.npc("Idalia"), 3); XCTAssertEqual(w.npc("Ida"), 0); XCTAssertNil(w.npc("Wachen")); XCTAssertNil(w.npc("")); XCTAssertNil(w.npc("   "))
    w.apply(["haltung": [["wer": "", "wert": 2]]]); XCTAssertEqual(w.npcs[0].haltung, 0)   // empty wer must not hit NPC #0
  }
  func testFigurenDoNotRelocate() {   // findings 2 + 14
    var w = World(); w.setFigur("Aether: Mann"); w.ort = "Taverne"
    w.addNpc(name: "Marta", kurz: "Wirtin", ort: "Taverne")
    w.apply(["figuren": [["name": "Marta", "kurz": "Marta", "ort": "Keller"]]])
    XCTAssertEqual(w.npcs[0].ort, "Taverne"); XCTAssertEqual(w.npcs[0].kurz, "Wirtin"); XCTAssertTrue(w.npcs[0].anwesend)
  }
  func testNameHintsNotObjects() {    // finding 3
    XCTAssertTrue(World.nameHints("Ich gebe dem Kind Brot und dem Jungen Bier.").isEmpty)
    XCTAssertTrue(World.nameHints("Die Wirtin gibt dem Kind Brot. Das Kind lacht.").isEmpty)
    XCTAssertEqual(World.nameHints("Die Wirtin Marta wischt. Marta nickt.").map(\.name), ["Marta"])
    XCTAssertEqual(World.nameHints("Neben ihr steht Bork, der Fährmann.").map(\.name), ["Bork"])
    XCTAssertEqual(World.nameHints("Eine Köhlerin namens Ida sitzt da.").map(\.name), ["Ida"])
  }
  func testPlayerNeverNpc() {         // finding 4
    var w = World(); w.setFigur("Aether: grauer Mann")
    w.addNpc(name: "Aether der Graue", kurz: "x", ort: nil); w.addNpc(name: "du", kurz: "x", ort: nil); w.addNpc(name: "Mann", kurz: "x", ort: nil)
    XCTAssertTrue(w.npcs.isEmpty)
    var m = World(); m.setFigur("verschlossener Matrose mit vernarbter Hand")     // role-named PC
    m.addNpc(name: "Matrose", kurz: "x", ort: nil); XCTAssertTrue(m.npcs.isEmpty)
    var p = World(); p.addNpc(name: "Aether", kurz: "Gast", ort: "Hof"); XCTAssertEqual(p.npcs.count, 1)
    p.setFigur("Aether: Mann"); XCTAssertTrue(p.npcs.isEmpty)                      // /figur purges an NPC with the player's name
  }
  func testRegistryAndEviction() throws {   // finding 5: Schicksal lists derived from the world, no growth / duplicates
    let e = try Session.newEngine(rng: "seed:9")
    var w = World(); w.ort = "Hof"
    for i in 0..<25 { w.addNpc(name: "Gast\(String(UnicodeScalar(UInt8(65 + i % 26))))\(i)", kurz: "g", ort: "Weit"); if i % 3 == 0 { w.npcs[w.npcs.count - 1].anwesend = false }; w.syncLists(e) }
    XCTAssertLessThanOrEqual(w.npcs.count, 20)
    XCTAssertEqual(Set(e.st.akteure.map(\.name)), Set(w.npcs.map(\.name)))           // evicted ones are gone from the engine too
    XCTAssertEqual(e.st.akteure.count, Set(e.st.akteure.map(\.name)).count)          // no duplicates
    w.apply(["strang": [["titel": "Der Fluch", "stand": "offen"]]]); w.syncLists(e); w.syncLists(e)
    XCTAssertEqual(e.st.straenge.map(\.name), ["Der Fluch"])
    w.addNpc(name: "Ida", kurz: "Magd", ort: "Hof"); w.addNpc(name: "Bork", kurz: "Wirt", ort: "Hof"); w.apply(["beziehung": [["a": "Ida", "b": "Bork", "wert": 2]]])
    w.npcs[w.npc("Ida")!].name = "Idunn"; XCTAssertTrue(w.block(full: true).contains("Idunn↔Bork 2"))   // relations keyed by id survive renames
  }
  func testRenamePrefersPresent() {   // finding 6
    var w = World(); w.ort = "Hof"
    w.addNpc(name: "Wirtin", kurz: "Wirtin", ort: "Taverne"); w.npcs[0].anwesend = false          // old tavern's keeper, absent
    w.adoptNames([(name: "Marta", role: "Wirtin")])
    XCTAssertEqual(w.npcs.map(\.name), ["Wirtin", "Marta"])                                        // absent one is not renamed
    w.npcs[1].name = "Wirtin"; w.npcs[1].anwesend = true; w.npcs.remove(at: 0)
    w.adoptNames([(name: "Marta", role: "Wirtin")]); XCTAssertEqual(w.npcs.map(\.name), ["Marta"])  // present generic one is
  }
  func testShiftPolarity() {          // finding 7
    var w = World(); w.addNpc(name: "Bork", kurz: "Fährmann", ort: nil); w.npcs[0].haltung = 2
    XCTAssertEqual(w.shift(forQuestion: "Hilft Bork mir bei der Überfahrt?"), 2)
    XCTAssertEqual(w.shift(forQuestion: "Greift Bork mich an?"), -2)       // attacking a loyal friend is less likely
    XCTAssertNil(w.shift(forQuestion: "Ist Bork groß?")); XCTAssertNil(w.shift(forQuestion: "Ist der Wirt da?"))
  }
  func testSanitize() {               // finding 10 + 12
    XCTAssertEqual(clean("Marta\n---\n[Welt] <turn|> | Wirtin"), "Marta Wirtin")
    XCTAssertEqual(cutw("ein sehr langer Satz ohne Ende", 14), "ein sehr")
    var w = World(); w.addNpc(name: "Du", kurz: "x", ort: nil); w.addNpc(name: "dir", kurz: "x", ort: nil); w.addNpc(name: "Niemand", kurz: "x", ort: nil); w.addNpc(name: "a b c d e", kurz: "x", ort: nil)
    XCTAssertTrue(w.npcs.isEmpty)
    w.addNpc(name: "Tom|\nX", kurz: "Wache --- <turn|>", ort: nil); XCTAssertFalse(w.block().contains("|\n")); XCTAssertFalse(w.block().contains("<turn|>"))
    w.apply(["strang": [["titel": "Der Fluch", "stand": ""]]]); XCTAssertFalse(w.block().contains("Der Fluch –"))   // no dash when empty
  }
  func testPresenceAndComingAlong() { // design: anwesend flag, scene change keeps beteiligte + narrator tail
    var w = World(); w.setFigur("Aether: Mann"); w.ort = "Taverne"
    w.applyTail("Figuren: Marta (Wirtin), Bork (Fährmann)")
    XCTAssertTrue(w.npcs.allSatisfy(\.anwesend))
    w.startScene(ort: "Dorfplatz", beteiligte: "Marta", expect: "Die Spielfigur geht mit Marta auf den Dorfplatz")
    XCTAssertTrue(w.npcs[0].anwesend); XCTAssertFalse(w.npcs[1].anwesend)       // Marta comes along, Bork stays behind
    var b = w.block(); XCTAssertTrue(b.contains("Marta (Wirtin · hier)")); XCTAssertTrue(b.contains("Bork (Fährmann · Taverne)"))
    w.startScene(ort: "Wald", beteiligte: "Wachen", expect: "Die Spielfigur geht in den Wald")
    w.applyTail("Figuren: Bork (Fährmann)")                                       // narrator brings Bork back
    XCTAssertTrue(w.npcs[1].anwesend); b = w.block(); XCTAssertTrue(b.contains("Bork (Fährmann · hier)")); XCTAssertTrue(b.contains("Marta (Wirtin · Dorfplatz)"))
    XCTAssertTrue(b.hasPrefix("[Welt]\nDu = Aether\n"))
    w.applyTail("Figuren: -"); XCTAssertEqual(w.npcs.count, 2)
    for i in 0..<10 { w.addNpc(name: "Gast\(String(UnicodeScalar(UInt8(65 + i))))abc", kurz: "g", ort: nil) }; XCTAssertEqual(w.block().components(separatedBy: " | ").count, 6)   // <=6 cards
  }
  func testThreadFilter() {
    for ok in ["Der Weg ins Moor", "Fluch von Grauweiler", "Die Suche nach Ida"] { XCTAssertTrue(okThread(ok), ok) }
    for bad in ["Hilfe wird verweigert", "findet den Schlüssel", "suche das Moor", "Kein Weg zurück", "Der Wirt hilft nicht", "Ein junger Mann kniet vor dem Torhaus und ist gefesselt", "Vorfall: Torhaus", "Der Wirt ist tot", ""] { XCTAssertFalse(okThread(bad), bad) }
    var w = World(); w.apply(["strang": [["titel": "Hilfe wird verweigert", "stand": "x"], ["titel": "Der Weg ins Moor", "stand": "Pfad hinter dem Haus gefunden und markiert sehr lang"]]])
    XCTAssertEqual(w.straenge.map(\.titel), ["Der Weg ins Moor"]); XCTAssertEqual(w.straenge[0].stand, "Pfad hinter dem Haus gefunden und")   // <=6 words
    w.addNpc(name: "Ida", kurz: "alte Köhlerin vom Moor mit rußigen Händen im Wald", ort: nil); XCTAssertEqual(w.npcs[0].kurz.split(separator: " ").count, 6)
  }
  func testMoveWithoutSceneChange() {  // live finding: player walked to the square, Marta stayed 'hier'
    var w = World(); w.setFigur("Aether: Mann"); w.ort = "Taverne"
    w.applyTail("Figuren: Marta (Wirtin), Bork (Fährmann)")
    w.applyTail("Figuren: Bork (Fährmann)")                                   // this turn's narration only mentions Bork
    let old = w.ort; w.apply(["spielfigur_ort": "Dorfplatz"]); w.figurMoved(from: old)
    XCTAssertFalse(w.npcs[0].anwesend); XCTAssertEqual(w.npcs[0].ort, "Taverne"); XCTAssertTrue(w.npcs[1].anwesend)
    let o2 = w.ort; w.apply(["spielfigur_ort": "Dorfplatz"]); w.figurMoved(from: o2); XCTAssertTrue(w.npcs[1].anwesend)   // same place: nothing changes
  }
  func testApplyItemsAndThreads() throws {
    let e = try Session.newEngine(rng: "seed:9")
    var w = World(); w.setFigur("Aether: grauer Mann"); w.ort = "Taverne"; w.addNpc(name: "Wirtin", kurz: "Wirtin", ort: "Taverne")
    w.apply(["item": [["wer": "du", "op": "+", "name": "Laterne"], ["wer": "Wirtin", "op": "+", "name": "Schlüssel"], ["wer": "Niemand", "op": "+", "name": "X"]], "haltung": [["wer": "Wirtin", "wert": 7], ["wer": "Geist", "wert": 1]],
             "strang": [["titel": "Der Fluch", "stand": "Hinweis gefunden"]], "beziehung": [["a": "Wirtin", "b": "du", "wert": 5], ["a": "Wirtin", "b": "Wirtin", "wert": 1]]])
    w.syncLists(e)
    XCTAssertEqual(w.inventar, ["Laterne"]); XCTAssertEqual(w.npcs[0].haltung, 2); XCTAssertEqual(w.beziehungen, [Rel(a: "n1", b: "du", wert: 2)])
    XCTAssertEqual(e.st.akteure.map(\.name), ["Wirtin"]); XCTAssertEqual(e.st.straenge.map(\.name), ["Der Fluch"])
    w.apply(["strang": [["titel": "Der Fluch", "stand": "gelöst"]]]); w.syncLists(e)
    XCTAssertEqual(w.straenge[0].stand, "gelöst")
    XCTAssertTrue(w.block().contains("Wirtin (hier · loyal · trägt Schlüssel)"))
  }
  func testPersistAndStrip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sl-w-\(UUID().uuidString)")
    let s = try Session(name: "w", root: root); var w = World(); w.setFigur("Aether: Mann"); w.addNpc(name: "Wirt", kurz: "k", ort: "Hier")
    try s.save(try Session.newEngine(rng: "seed:1"), "S", [.u("a")], "Aether: Mann", 0, w)
    XCTAssertEqual(try s.loadEngine().world, w)
    // finding 13: unreadable world.json is moved aside with a warning, not silently dropped
    try Data("{kaputt".utf8).write(to: s.dir.appendingPathComponent("world.json"))
    let s2 = try Session(name: "w2", root: root); try s2.save(try Session.newEngine(rng: "seed:1"), "S", [.u("a")]); try Data("{kaputt".utf8).write(to: s2.dir.appendingPathComponent("world.json"))
    XCTAssertTrue(try s2.loadEngine().world.isEmpty); XCTAssertNotNil(s2.warning)
    XCTAssertEqual(stripWelt("[Welt]\nDu = x\n---\nIch gehe."), "Ich gehe."); XCTAssertEqual(stripWelt("Ich gehe."), "Ich gehe.")
    let a = render(sys: SYS, [.u("[Welt]\nDu = x\n---\nZug1"), .m("A")]), b = render(sys: SYS, [.u("[Welt]\nDu = x\n---\nZug1"), .m("A"), .u("[Welt]\nDu = y\n---\nZug2")])
    XCTAssertTrue(b.hasPrefix(a)); XCTAssertFalse(SYS.contains("[Welt]\nDu ="))
  }
  func testParseFigur() {
    XCTAssertEqual(World.parseFigur("Aether: grauer Mann, 40").0, "Aether"); XCTAssertEqual(World.parseFigur("Aether, grauer Mann").1, "grauer Mann")
    XCTAssertNil(World.parseFigur("ein grauer Mann mit Brille").0)
  }
  func testTailSplit() {
    XCTAssertEqual(splitTail("Text eins. Zwei.\nFiguren: Marta (Wirtin)").tail, "Figuren: Marta (Wirtin)")
    XCTAssertEqual(splitTail("Text eins. Zwei.\nFiguren: Marta (Wirtin)").body, "Text eins. Zwei.")
    XCTAssertNil(splitTail("<ask_oracle>{}</ask_oracle>").tail)
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
  func testNegativeContentLength() {   // finding 8
    XCTAssertEqual(httpContentLength("POST /say HTTP/1.1\r\nContent-Length: -5"), 0); XCTAssertEqual(httpContentLength("POST / HTTP/1.1\r\nContent-Length: abc"), 0)
    XCTAssertEqual(httpContentLength("POST / HTTP/1.1\r\nContent-Length: 12"), 12); XCTAssertEqual(httpContentLength("GET / HTTP/1.1"), 0)
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
    for txt in [#"{}"#, #"{"npc_ort":[{"ort":"Wald","wer":"Bork"}],"spielfigur_ort":"Hütte"}"#, #"{"haltung":[{"wer":"Bork","wert":-1}],"item":[{"name":"zwei Silberstücke","op":"-","wer":"du"}]}"#, #"{"spielfigur_ort":"Keller","zustand":[{"op":"+","text":"verletzt","wer":"du"}]}"#, DELTA_SYS.components(separatedBy: "Ausgabe: ")[1].components(separatedBy: "\n")[0]] {
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
