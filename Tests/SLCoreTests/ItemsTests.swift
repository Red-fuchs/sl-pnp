import XCTest
import Schicksal
@testable import SLCore

final class ItemsTests: XCTestCase {
  func gen(_ seed: UInt64 = 7) throws -> ItemGen {
    var g = try XCTUnwrap(ItemGen.load())
    var x = seed
    g.d = { n in x = x &* 6364136223846793005 &+ 1442695040888963407; return Int((x >> 33) % UInt64(n)) + 1 }
    g.pair = { ["suchen", "Schuld"] }
    return g
  }

  func testPriceMatchesRollPy() throws {
    let g = try gen()
    // python3 -c 'from handout.items.roll import preis; ...' reference values
    XCTAssertEqual(g.preis(80, "gewoehnlich", "normal"), 80)
    XCTAssertEqual(g.preis(80, "ungewoehnlich", "normal"), 120)
    XCTAssertEqual(g.preis(80, "ungewoehnlich", "magisch"), 1120)
    XCTAssertEqual(g.preis(80, "ungewoehnlich", "verflucht"), 560)
    XCTAssertEqual(g.preis(10, "gewoehnlich", "plunder"), 2)
    XCTAssertEqual(g.punkte(39), 0); XCTAssertEqual(g.punkte(41), 2)
  }

  func testRollsAreValid() throws {
    let g = try gen()
    for _ in 0..<500 {
      let i = try g.roll()
      XCTAssertTrue(g.SID.contains(i.sel)); XCTAssertGreaterThan(i.preis, 0)
      if ["magisch", "gesegnet", "verflucht"].contains(i.pr) { XCTAssertNotNil(i.wirkung); XCTAssertEqual(i.merkmale.count, 1) }
      if i.pr == "verflucht" || i.pr == "wendung" { XCTAssertFalse(i.gm.isEmpty) }
      if g.SID.firstIndex(of: i.sel)! >= 2 && i.pr != "normal" && i.pr != "gut" && i.pr != "plunder" { XCTAssertNotNil(i.titel); XCTAssertEqual(i.paar.count, 2); XCTAssertEqual(i.fragen.count, 2) }
    }
  }

  func testHeiltrankPriceDoesNotCompound() throws {
    let g = try gen()
    let ps = try (0..<200).map { _ in try g.roll(sel: "selten", kat: "trank", pr: "normal") }.filter { $0.name.hasPrefix("Heiltrank") }.map(\.basis)
    XCTAssertEqual(Set(ps).count, min(1, ps.count))
  }

  func testCommand() throws {
    let g = try gen()
    XCTAssertEqual(g.command("3 selten waffe").split(separator: "\n").count, 3)
    XCTAssertTrue(g.command("haendler 3 waffe grossstadt").hasPrefix("Händler Stufe 3:"))
    let h = g.command("hat 2 selten spez wildnis Silberdolch", spannung: 6)
    XCTAssertTrue(h.hasPrefix("Hat der Händler Silberdolch? (Stufe 2, selten, Spezialgebiet, wildnis; Chancen "), h)
    XCTAssertTrue(h.contains(" → d100 "))
    XCTAssertTrue(g.command("quatsch").hasPrefix("unbekannt: quatsch"))
    XCTAssertEqual(g.command("hat 9 selten"), ItemGen.usage)
    XCTAssertEqual(Cmd.parse("/item 2 selten"), .item("2 selten"))
  }

  func testHatOdds() throws {
    let g = try gen()
    // Stufe 1 (-1) wildnis (-1) for selten: steps from data, capped by deckel; Chancen always on the ladder
    for st in 1...5 { for s in g.SID { XCTAssertTrue(Core.odds.contains(g.hat(st, s, kontext: "wildnis").chancen)) } }
  }
}
