import Foundation
import Schicksal

/// Gegenstandsgenerator, port of handout/items/roll.py (data: handout/items/data/*.json, oracle: the Fate chart in Core.thr).
/// lint/stats stay in Python; this is the table part the GM needs at the table: /item.
public struct Item {
  public var kat = "", name = "", sel = "", pr = "", effekt: String?, titel: String?, wirkung: String?
  public var basis = 0, preis = 0, punkte = 0, kp = 0, schaden: Int?, ruestung: Int?
  public var merkmale: [(String, String)] = [], gm: [String] = [], paar: [String] = [], fragen: [String] = []
}

public struct ItemGen {
  static let magic: Set = ["magisch", "gesegnet", "verflucht"]
  public let D: [String: J]
  var d: (Int) -> Int                       // d(n) = 1...n
  public var pair: () -> [String] = { [] }  // Wortpaar tun/thema from the engine (none in tests)

  public init(data: [String: J], d: @escaping (Int) -> Int = { Int.random(in: 1...$0) }) { D = data; self.d = d }
  /// SL_ITEMS, then handout/items/data next to the package, then ~/Projects/sl-pnp
  public static func load(dir: URL? = nil) -> ItemGen? {
    let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let dirs = [dir, ProcessInfo.processInfo.environment["SL_ITEMS"].map { URL(fileURLWithPath: $0) }, pkg.appendingPathComponent("handout/items/data"),
                URL(fileURLWithPath: NSHomeDirectory() + "/Projects/sl-pnp/handout/items/data")].compactMap { $0 }
    guard let dd = dirs.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("preise.json").path) }),
          let fs = try? FileManager.default.contentsOfDirectory(at: dd, includingPropertiesForKeys: nil) else { return nil }
    var data: [String: J] = [:]
    for f in fs.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
      guard let s = try? String(contentsOf: f, encoding: .utf8), let o = (try? J.parse(s))?.obj else { return nil }
      data.merge(o) { $1 }
    }
    return ItemGen(data: data)
  }

  // ---- data accessors ----
  var SEL: [J] { D["seltenheit"]?.arr ?? [] }
  public var SID: [String] { SEL.compactMap { $0["id"].str } }
  func sby(_ id: String) -> J { SEL.first { $0["id"].str == id } ?? .null }
  func praeg(_ id: String) -> J { D["praegung"]?.arr?.first { $0["id"].str == id } ?? .null }
  public var KAT: [J] { D["kategorien"]?.arr ?? [] }
  func kat(_ id: String) -> J? { KAT.first { $0["id"].str == id } }
  var HM: J { D["haendler"] ?? .null }
  var ppt: Int { D["muenzen"]?["heller_pro_punkt"].int ?? 40 }
  func idx(_ s: String) -> Int { SID.firstIndex(of: s) ?? 0 }
  func strs(_ j: J) -> [String] { j.arr?.compactMap(\.str) ?? [] }
  func inr(_ x: Int, _ b: J) -> Bool { (b.arr?.first?.int ?? 0) <= x && x <= (b.arr?.last?.int ?? 0) }
  func choice<T>(_ a: [T]) -> T { a[d(a.count) - 1] }

  // ---- price ----
  public func punkte(_ h: Int) -> Int { h < ppt ? 0 : (h + ppt - 1) / ppt }
  /// rarity raises the price: mundane basis x Prägung x preis_mult, magic Stufenpreis + basis x preis_mult,
  /// magic consumables basis x trank_mult (cursed half). skaliert: price already follows its own scale (Heiltrank).
  public func preis(_ basis: Double, _ sel: String, _ pr: String, verbrauch: Bool = false, skaliert: Bool = false) -> Int {
    let S = sby(sel), R = skaliert ? 1 : S["preis_mult"].dbl ?? 1
    var p: Double
    if verbrauch && Self.magic.contains(pr) { p = basis * (S["trank_mult"].dbl ?? 1) / (pr == "verflucht" ? 2 : 1) }
    else if Self.magic.contains(pr) { p = (S["magie_h"].dbl ?? 0) + basis * R; if pr == "verflucht" { p = (p / 2).rounded(.down) } }
    else { p = basis * (praeg(pr)["mult"].dbl ?? 1) * R }
    return max(1, p < 40 ? Core.rnd(p) : (Int(p) + 10) / 20 * 20)
  }

  // ---- oracle: same Fate chart as handout and engine ----
  public func orakel(_ o0: Int, spannung: Int = 5) -> (chancen: String, wurf: Int, antwort: String) {
    let o = max(-3, min(3, o0)), x = d(100)
    return (Core.odds[o + 3], x, Core.answer(x, Core.thr(o, spannung)))
  }
  func kontextShift(_ k: String) -> Int { HM["kontext"].arr?.first { $0["id"].str == k }?["shift"].int ?? 0 }
  func hatSchritte(_ stufe: Int, spez: Bool, kontext: String) -> Int {
    (HM["stufen"].arr?[stufe - 1]["orakel"].int ?? 0) + (spez ? HM["spezial_schritt"].int ?? 1 : 0) + kontextShift(kontext)
  }
  /// "Hat der Händler genau das?": rarity steps + merchant tier + specialty + context, capped per rarity
  public func hat(_ stufe: Int, _ sel: String, spez: Bool = false, kontext: String = "normal", spannung: Int = 5, sp: Int = 0) -> (chancen: String, wurf: Int, antwort: String) {
    let S = sby(sel)
    return orakel(min((S["orakel"].int ?? 0) + hatSchritte(stufe, spez: spez, kontext: kontext) + sp, S["deckel"].int ?? 3), spannung: spannung)
  }

  // ---- d100 tables with a rarity window ----
  func look(_ tab: [J], _ x: Int) -> J { tab.first { ($0["von"].int ?? 0) <= x && x <= ($0["bis"].int ?? 0) } ?? .null }
  func fold(_ x: Int, _ w: J) -> Int { let a = w.arr?.first?.int ?? 1, b = w.arr?.last?.int ?? 100; return x < a ? x + 50 : x > b ? x - 50 : x }
  func passt(_ e: J, _ kat: String?) -> Bool {
    guard let kat else { return true }
    return !((e["typ"].str == "schaden" && kat != "waffe") || (e["typ"].str == "ruestung" && kat != "ruestung"))
  }
  func fenster(_ tab: String, _ sel: String, kat: String? = nil) -> [J] {
    let t = D[tab] ?? .null, rows = t["tabelle"].arr ?? [], n = strs(t["doppelt"]).contains(sel) ? 2 : 1
    var out: [J] = []
    while out.count < n {
      let e = look(rows, fold(d(100), t["fenster"][sel]))
      if !out.contains(e), passt(e, kat), !out.contains(where: { $0["typ"].str != nil && $0["typ"].str == e["typ"].str }) { out.append(e) }
    }
    return out
  }

  func rollSel() -> String { let x = d(100); return SEL.first { inr(x, $0["d100"]) }?["id"].str ?? "gewoehnlich" }
  func rollKat() -> String { let x = d(20); return KAT.first { inr(x, $0["d20"]) }?["id"].str ?? "waffe" }
  func rollPraegung(_ sel: String) -> String {
    let p = D["praegung_d20"] ?? .null, x = d(20); var acc = 0
    for (id, n) in zip(strs(p["reihenfolge"]), p["anzahl"][sel].arr?.compactMap(\.int) ?? []) { acc += n; if x <= acc { return id } }
    return "normal"
  }
  func rollPosten(_ k: J) -> J { let x = d(100); return look(k["items"].arr ?? [], x) }

  /// entries matching at least one allowed material group (empty gruppen = universal)
  func pool(_ l: J, _ gr: [String]) -> [String] {
    (l.arr ?? []).filter { strs($0["gruppen"]).isEmpty || !Set(strs($0["gruppen"])).isDisjoint(with: gr) }.compactMap { $0["text"].str }
  }
  func merkmale(_ it: J, _ sel: String, _ pr: String) -> [(String, String)] {
    let M = D["merkmale"] ?? .null, gr = strs(it["mat"])
    var out = [(gr == ["zutat"] ? "Zutat" : "Material", choice(gr.flatMap { strs(M["material"][$0]) }))]
    let z = pool(M["zustand"], gr), ma = pool(M["machart"], gr), be = pool(M["besonderheit"], gr)
    if pr == "plunder" { out.append(("Zustand", choice(Array(z.prefix(max(3, z.count * 3 / 10)))))) }
    else if pr == "gut" { out.append(("Machart", choice(ma))) }
    else if sel == "gewoehnlich" {
      let c = choice(["Herkunft", "Besonderheit", "Zustand"])
      out.append((c, c == "Herkunft" ? choice(strs(M["herkunft"])) : choice(c == "Besonderheit" ? be : z)))
    } else { out += [("Machart", choice(ma)), ("Besonderheit", choice(be))] }
    return out
  }
  func titel(_ it: J) -> String {
    let N = D["namen"] ?? .null, ep = strs(N["epitheton"])[d(100) - 1], bz = strs(N["bezug"])[d(100) - 1]
    let kern = it["kern"].str ?? String((it["name"].str ?? "").components(separatedBy: " / ")[0].components(separatedBy: " (")[0])
    let art = ["m": "Der", "f": "Die"][it["genus"].str ?? "n"] ?? "Das"
    return "\(art) \(ep)\(ep.hasSuffix("e") ? "" : "e") \(kern) \(bz)"
  }

  public func roll(sel s0: String? = nil, kat k0: String? = nil, pr p0: String? = nil, name: Bool = false) throws -> Item {
    if let s0, !SID.contains(s0) { throw SLError("unbekannte Seltenheit \(s0); gültig: \(SID.joined(separator: ", "))") }
    if let k0, kat(k0) == nil { throw SLError("unbekannte Kategorie \(k0); gültig: \(KAT.compactMap { $0["id"].str }.joined(separator: ", "))") }
    var sel = s0 ?? rollSel()
    let kid = k0 ?? rollKat(), k = kat(kid)!, it = rollPosten(k), verbrauch = k["verbrauch"].bool ?? false
    if let mn = it["min"].str, idx(sel) < idx(mn) { sel = mn }
    var pr = p0 ?? rollPraegung(sel)
    var i = Item(kat: kid, name: it["name"].str ?? "?", sel: sel, effekt: it["effekt"].str, basis: it["preis_h"].int ?? 0, schaden: it["schaden"].int, ruestung: it["ruestung"].int)
    let lps = it["heilung_lp"].arr?.compactMap(\.int)
    if let lps {  // Heiltrank: healing (and price) follow the rarity; 4 LP only from sehr selten. Local, roll.py mutates its table here.
      let lp = lps[idx(sel)]; i.effekt = "heilt \(lp) LP sofort, auch im Kampf"; i.basis = i.basis * lp / 2
    }
    if verbrauch && pr == "wendung" { pr = "gut" }
    if it["schaedlich"].bool == true && Self.magic.contains(pr) { pr = "gut" }  // poisons and irritants are never magic
    i.pr = pr; i.preis = preis(Double(i.basis), sel, pr, verbrauch: verbrauch, skaliert: lps != nil); i.punkte = punkte(i.preis)
    if ["normal", "gut", "plunder", "wendung"].contains(pr) { i.merkmale = merkmale(it, sel, pr) }
    if Self.magic.contains(pr) {
      if verbrauch { i.wirkung = pr != "verflucht" ? "Wirkung doppelt" : "Wirkung + Nebenwirkung (Fluch) bis zur Nachtruhe" }
      else { let es = fenster(pr == "gesegnet" ? "segen" : "wirkungen", sel, kat: kid); i.wirkung = es.compactMap { $0["text"].str }.joined(separator: " + "); i.kp = es.compactMap { $0["kp"].int }.reduce(0, +) }
      i.merkmale = Array(merkmale(it, sel, "normal").prefix(1))
      if pr == "verflucht" && verbrauch { i.gm.append("Nebenwirkung: vergiftet bis zur Nachtruhe (kein Fluchwurf)") }
      else if pr == "verflucht" { let f = fenster("flueche", sel)[0]; i.gm.append("Fluch (Stufe \(f["stufe"].int ?? 0)): \(f["text"].str ?? "") | Haken: \(f["haken"].str ?? "")") }
    }
    if pr == "wendung" { let w = fenster("wendungen", sel)[0]; i.gm.append("Wendung (Stufe \(w["stufe"].int ?? 0)): \(w["text"].str ?? "") | Enthüllung: \(w["enthuellung"].str ?? "")") }
    var name = name
    if idx(sel) >= idx("selten") && (Self.magic.contains(pr) || pr == "wendung") {
      i.paar = pair()
      var fr = D["orakel"]?["fragen_item"].arr ?? []
      for _ in 0..<min(2, fr.count) { let f = fr.remove(at: d(fr.count) - 1); i.fragen.append("\(f["text"].str ?? "") (\(f["chancen"].str ?? ""))") }
      name = true
    }
    if name { i.titel = titel(it) }
    return i
  }

  public func show(_ i: Item) -> String {
    var s = "\(i.titel.map { "\($0) (\(i.name))" } ?? i.name) [\(sby(i.sel)["name"].str ?? i.sel), \(praeg(i.pr)["name"].str ?? i.pr)] \(Geld.fmt(i.preis)) (\(i.punkte) P)"
    if let x = i.schaden { s += " Schaden \(x)" }
    if let x = i.ruestung { s += " Rüstung \(x)" }
    if let x = i.effekt { s += " | \(x)" }
    if !i.merkmale.isEmpty { s += " | " + i.merkmale.map { "\($0.0): \($0.1)" }.joined(separator: ", ") }
    if let x = i.wirkung { s += " | WIRKUNG (Rahmen): \(x)" }
    if i.paar.count == 2 { s += " | WORTPAAR: \(i.paar[0]) · \(i.paar[1])" }
    if !i.fragen.isEmpty { s += " | FRAGEN: " + i.fragen.joined(separator: " / ") }
    return s + i.gm.map { " | SL: \($0)" }.joined()
  }

  // ---- merchant ----
  func stufeEff(_ st: Int, _ kontext: String, _ hit: Bool) -> Int { max(1, min(5, st + kontextShift(kontext) + (hit ? 1 : 0))) }
  func rollSelHaendler(_ st: Int) -> (String, String?) {
    let S = HM["stufen"].arr?[st - 1] ?? .null, w = S["wuerfe"].int ?? 1, xs = (0..<max(1, abs(w))).map { _ in rollSel() }
    let sel = (w < 0 ? xs.min { idx($0) < idx($1) } : xs.max { idx($0) < idx($1) })!
    return sel == "gewoehnlich" && d(6) <= (S["plunder_d6"].int ?? 0) ? (sel, "plunder") : (sel, nil)
  }
  public func haendler(_ stufe: Int, spez: [String] = [], kontext: String = "normal") throws -> [Item] {
    try (0..<(d(6) + stufe)).map { _ in
      let hit = !spez.isEmpty && d(6) <= (HM["spezial_d6"].arr?.last?.int ?? 4), k = hit ? choice(spez) : rollKat()
      let (sel, pr) = rollSelHaendler(stufeEff(stufe, kontext, spez.contains(k)))
      return try roll(sel: sel, kat: k, pr: pr)
    }
  }

  // ---- /item ----
  public static let usage = """
  /item [N] [Seltenheit] [Kategorie] [name]   Gegenstand würfeln (N bis 10)
  /item haendler STUFE(1-5) [Kategorie…] [grossstadt|wildnis]   Händlerware
  /item hat STUFE SELTENHEIT [spez] [grossstadt|wildnis] [Ware]   Orakel: Hat der Händler das?
  """
  /// `spannung` = current tension (oracle column). Output lines with "SL:" are for the GM only.
  public func command(_ a: String, spannung: Int = 5) -> String {
    var w = a.split(separator: " ").map { String($0) }
    let kats = Set(KAT.compactMap { $0["id"].str }), kontexte = Set(HM["kontext"].arr?.compactMap { $0["id"].str } ?? [])
    func selId(_ t: String) -> String? { SID.first { $0 == t.lowercased() || norm(sby($0)["name"].str ?? "") == norm(t) } }
    do {
      switch w.first?.lowercased() {
      case "haendler", "händler":
        guard w.count > 1, let st = Int(w[1]), (1...5).contains(st) else { return Self.usage }
        let rest = w.dropFirst(2).map { $0.lowercased() }
        if let bad = rest.first(where: { !kats.contains($0) && !kontexte.contains($0) }) { return "unbekannt: \(bad)\n" + Self.usage }
        let inv = try haendler(st, spez: rest.filter(kats.contains), kontext: rest.first(where: kontexte.contains) ?? "normal")
        return "Händler Stufe \(st): \(inv.count) Posten\n" + inv.map(show).joined(separator: "\n")
      case "hat":
        guard w.count > 2, let st = Int(w[1]), (1...5).contains(st), let sel = selId(w[2]) else { return Self.usage }
        w.removeFirst(3)
        let spez = w.first?.lowercased() == "spez"; if spez { w.removeFirst() }
        let kx = w.first.map { $0.lowercased() }.flatMap { kontexte.contains($0) ? $0 : nil } ?? "normal"; if kx != "normal" || w.first?.lowercased() == "normal" { w.removeFirst() }
        let r = hat(st, sel, spez: spez, kontext: kx, spannung: spannung), ware = w.joined(separator: " ")
        return "Hat der Händler \(ware.isEmpty ? "das" : ware)? (Stufe \(st), \(sby(sel)["name"].str ?? sel)\(spez ? ", Spezialgebiet" : "")\(kx == "normal" ? "" : ", \(kx)"); Chancen \(r.chancen), Spannung \(spannung)) → d100 \(r.wurf): \(r.antwort)"
      default:
        var n = 1, sel: String?, k: String?, name = false
        for t in w {
          if let x = Int(t) { n = max(1, min(10, x)) } else if let s = selId(t) { sel = s } else if kats.contains(t.lowercased()) { k = t.lowercased() }
          else if t.lowercased() == "name" { name = true } else { return "unbekannt: \(t)\n" + Self.usage }
        }
        return try (0..<n).map { _ in show(try roll(sel: sel, kat: k, name: name)) }.joined(separator: "\n")
      }
    } catch { return "Fehler: \(error)" }
  }
}
