import Foundation
import Schicksal

public struct Npc: Codable, Equatable {
  public var id: String, name: String, kurz: String
  public var ort: String?
  public var anwesend = true          // in the current scene (presence flag, not a place-string match)
  public var zustand: [String] = [], inventar: [String] = []
  public var haltung = 0              // -2 feindlich .. 2 loyal (towards the player character)
  public var notiz = ""
  public init(id: String, name: String, kurz: String, ort: String?, anwesend: Bool = true) { self.id = id; self.name = name; self.kurz = kurz; self.ort = ort; self.anwesend = anwesend }
  enum K: String, CodingKey { case id, name, kurz, ort, anwesend, zustand, inventar, haltung, notiz }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); kurz = try c.decodeIfPresent(String.self, forKey: .kurz) ?? ""
    ort = try c.decodeIfPresent(String.self, forKey: .ort); anwesend = try c.decodeIfPresent(Bool.self, forKey: .anwesend) ?? true
    zustand = try c.decodeIfPresent([String].self, forKey: .zustand) ?? []; inventar = try c.decodeIfPresent([String].self, forKey: .inventar) ?? []
    haltung = try c.decodeIfPresent(Int.self, forKey: .haltung) ?? 0; notiz = try c.decodeIfPresent(String.self, forKey: .notiz) ?? ""
  }
}
public struct Rel: Codable, Equatable { public var a: String, b: String, wert: Int }   // a/b = NPC id or "du"
public struct Strang: Codable, Equatable { public var titel: String, stand: String }

let haltungWort = [-2: "feindlich", -1: "misstrauisch", 0: "", 1: "freundlich", 2: "loyal"]
func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
func tokens(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 } }
/// cut at a word boundary
func cutw(_ s: String, _ n: Int) -> String {
  if s.count <= n { return s }
  let p = String(s.prefix(n))
  if let i = p.lastIndex(of: " "), p.distance(from: p.startIndex, to: i) > n / 2 { return String(p[..<i]) }
  return p
}
/// Sanitize any model-produced string before it reaches the prompt (newlines, separators, control tokens).
public func clean(_ s: String, _ n: Int = 60) -> String {
  var t = s
  for bad in ["<turn|>", "<|turn>", "<|im_start|>", "<|im_end|>", "<bos>", "[Welt]", "---", "|", "<", ">", "\n", "\r", "\t"] { t = t.replacingOccurrences(of: bad, with: " ") }
  t = t.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,;:–-"))
  return cutw(t, n)
}
let rejectNames: Set<String> = ["du", "dir", "dich", "dein", "mich", "ich", "mir", "mein", "wir", "ihr", "er", "sie", "es", "man", "niemand", "jemand", "spielfigur", "figur", "spieler", "-", "unbekannt", "umgebung", "alle"]
func okName(_ n: String) -> Bool { !n.isEmpty && n.split(separator: " ").count <= 4 && !rejectNames.contains(norm(n)) }

/// Bounded world state: the player character, NPCs, places, relations, threads. Persisted as world.json.
public struct World: Codable, Equatable {
  public var name: String?, kurz: String?, ort: String?
  public var zustand: [String] = [], inventar: [String] = []
  public var npcs: [Npc] = []
  public var orte: [String: String] = [:]
  public var beziehungen: [Rel] = []
  public var straenge: [Strang] = []
  var nextId = 1
  public init() {}
  public var isEmpty: Bool { name == nil && kurz == nil && ort == nil && npcs.isEmpty && straenge.isEmpty && zustand.isEmpty && inventar.isEmpty }

  // MARK: player character
  /// "Aether: grauer Mann, 40" | "Aether, grauer Mann" | free text -> name?, kurz
  public static func parseFigur(_ t: String) -> (String?, String) {
    let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
    if let i = s.firstIndex(of: ":"), s[..<i].split(separator: " ").count <= 3 { return (clean(String(s[..<i]), 40), clean(String(s[s.index(after: i)...]), 140)) }
    if let i = s.firstIndex(of: ","), s[..<i].split(separator: " ").count == 1, s.first?.isUppercase == true { return (clean(String(s[..<i]), 40), clean(String(s[s.index(after: i)...]), 140)) }
    return (nil, clean(s, 140))
  }
  /// Sets the character and purges NPCs that are really the player character.
  public mutating func setFigur(_ t: String) { let (n, k) = Self.parseFigur(t); name = n; kurz = k; let me = self; npcs = npcs.filter { !me.isFigur($0.name) } }
  var pcTokens: Set<String> {
    var s = Set(tokens(name ?? ""))
    if let k = kurz, let h = k.split(whereSeparator: { !$0.isLetter }).map(String.init).first(where: { $0.first?.isUppercase == true && $0.count >= 4 }) { s.insert(h.lowercased()) }   // head noun ("Matrose")
    return s
  }
  func isFigur(_ w: String) -> Bool {
    let x = norm(w)
    if ["du", "ich", "spielfigur", "figur", "dir", "dich", "mich"].contains(x) { return true }
    let t = tokens(x); return !t.isEmpty && t.contains { pcTokens.contains($0) }
  }

  // MARK: lookup (whole tokens only: Idalia != Ida, Borka != Bork, Wachen != Wache; empty never matches)
  func npc(_ w: String) -> Int? {
    let x = norm(clean(w)); guard !x.isEmpty else { return nil }
    if let i = npcs.firstIndex(where: { norm($0.id) == x || norm($0.name) == x }) { return i }
    let q = Set(tokens(x)); guard !q.isEmpty else { return nil }
    let c = npcs.indices.filter { q.isSubset(of: Set(tokens(npcs[$0].name))) }
    return c.count == 1 ? c[0] : nil
  }
  func here(_ n: Npc) -> Bool { n.anwesend }

  // MARK: [Welt] block
  /// Compact [Welt] block with slot cards (fixed slot order, <=6 figures): `Name (Rolle · hier|Ort · Haltung · trägt X)`.
  public func block(full: Bool = false) -> String {
    if isEmpty { return "" }
    var l = ["[Welt]"]
    let head = name ?? (kurz?.isEmpty == false ? kurz! : "Spielfigur")
    l.append("Du = \(head)")
    var p: [String] = []
    if name != nil, let k = kurz, !k.isEmpty { p.append(k) }
    if let o = ort, !o.isEmpty { p.append("Ort: \(o)") }
    if !zustand.isEmpty { p.append("Zustand: \(zustand.joined(separator: ", "))") }
    if !inventar.isEmpty { p.append("Inventar: \(inventar.joined(separator: ", "))") }
    if !p.isEmpty { l.append(p.joined(separator: ". ") + ".") }
    let ordered = npcs.filter(\.anwesend) + npcs.filter { !$0.anwesend }
    let cards = ordered.prefix(full ? 20 : 6).map(card)
    if !cards.isEmpty { l.append("Figuren: " + cards.joined(separator: " | ")) }
    if !straenge.isEmpty { l.append("Stränge: " + straenge.suffix(full ? 8 : 3).map { $0.stand.isEmpty ? $0.titel : "\($0.titel) – \($0.stand)" }.joined(separator: " | ")) }
    if full {
      if !orte.isEmpty { l.append("Orte: " + orte.sorted { $0.key < $1.key }.map { $0.value.isEmpty ? $0.key : "\($0.key) – \($0.value)" }.joined(separator: " | ")) }
      if !beziehungen.isEmpty { l.append("Beziehungen: " + beziehungen.map { "\(label($0.a))↔\(label($0.b)) \($0.wert)" }.joined(separator: ", ")) }
    }
    return l.joined(separator: "\n")
  }
  func label(_ id: String) -> String { id == "du" ? "du" : (npcs.first { $0.id == id }?.name ?? id) }
  func card(_ n: Npc) -> String {
    var x: [String] = []
    if !n.kurz.isEmpty && norm(n.kurz) != norm(n.name) { x.append(cutw(n.kurz, 50)) }
    x.append(n.anwesend ? "hier" : (n.ort.map { clean($0, 30) } ?? "anderswo"))
    if let h = haltungWort[n.haltung], !h.isEmpty { x.append(h) }
    x += n.zustand.prefix(2); x += n.inventar.prefix(2).map { "trägt \($0)" }
    return "\(n.name) (\(x.joined(separator: " · ")))"
  }

  // MARK: oracle shift from attitude (only for social questions, with polarity)
  static let posVerbs = ["hilft", "helfen", "hilfst", "vertraut", "vertrauen", "verrät", "verraten", "gibt", "geben", "lässt", "erlaubt", "glaubt", "antwortet", "redet", "spricht", "erzählt", "zeigt", "folgt", "begleitet", "teilt", "schenkt", "bietet", "gewährt", "empfängt", "kooperiert", "stimmt zu", "hört zu"]
  static let negVerbs = ["greift", "angreift", "bedroht", "verfolgt", "betrügt", "belügt", "lügt", "verrät mich", "verweigert", "verjagt", "wirft raus", "schlägt", "tötet", "meldet", "verhaftet", "stiehlt", "misstraut"]
  public func shift(forQuestion q: String) -> Int? {
    let t = norm(q)
    let pos = Self.posVerbs.contains { t.contains($0) }, neg = Self.negVerbs.contains { t.contains($0) }
    guard pos != neg else { return nil }
    let qt = Set(tokens(t))
    for n in npcs where n.anwesend && n.haltung != 0 {
      if !Set(tokens(n.name)).isDisjoint(with: qt) { return pos ? n.haltung : -n.haltung }
    }
    return nil
  }

  // MARK: scene / presence
  /// New scene: nobody is present unless named in beteiligte/expect.
  public mutating func startScene(ort o: String?, beteiligte: String, expect: String) {
    if let o, !o.isEmpty { ort = clean(o); if orte[clean(o)] == nil, orte.count < 30 { orte[clean(o)] = "" } }
    let txt = Set(tokens(beteiligte + " " + expect))
    for i in npcs.indices {
      let present = !Set(tokens(npcs[i].name)).isDisjoint(with: txt)
      npcs[i].anwesend = present
      if present { npcs[i].ort = ort } else if npcs[i].ort == nil || samePlace(npcs[i].ort, ort) { npcs[i].ort = npcs[i].ort ?? ort }
    }
  }
  func samePlace(_ a: String?, _ b: String?) -> Bool { guard let a = a.map(norm), let b = b.map(norm), !a.isEmpty, !b.isEmpty else { return false }; return a == b }

  /// Narrator tail `Figuren: Marta (Wirtin), Bork` -> presence + new characters. "-" changes nothing.
  @discardableResult
  public mutating func applyTail(_ line: String) -> [String] {
    var s = line.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("Figuren:") { s = String(s.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
    if s.isEmpty || s == "-" { return [] }
    var log: [String] = []
    for part in s.split(separator: ",") {
      var n = String(part), r = ""
      if let o = n.firstIndex(of: "("), let c = n.lastIndex(of: ")"), o < c { r = clean(String(n[n.index(after: o)..<c]), 40); n = String(n[..<o]) }
      n = clean(n, 40)
      guard okName(n), !isFigur(n) else { continue }
      if let i = npc(n) ?? npcs.firstIndex(where: { norm($0.kurz) == norm(n) }) {      // known by name, or by its role ("Wirtin")
        if !r.isEmpty, !norm(npcs[i].kurz).contains(norm(r)), npcs[i].kurz.count < 40 { npcs[i].kurz = npcs[i].kurz.isEmpty ? r : "\(r), \(npcs[i].kurz)" }   // refine the role ("Kapitän, breiter Mann …")
        if !npcs[i].anwesend { npcs[i].anwesend = true; npcs[i].ort = ort; log.append("\(npcs[i].name) anwesend") }
      } else if !r.isEmpty, let i = npcs.firstIndex(where: { $0.anwesend && norm($0.name) == norm(r) }) {   // role-named NPC gets its proper name
        log.append("\(npcs[i].name) heißt \(n)"); npcs[i].name = n
      } else if let (i, new) = addNpc(name: n, kurz: r, ort: ort), new { log.append("neu \(npcs[i].name)") }
    }
    return log
  }

  /// New NPC (present, at the current place). Existing NPC: only the role word may be refined; never moved.
  @discardableResult
  mutating func addNpc(name n0: String, kurz k0: String, ort o: String?) -> (Int, Bool)? {
    let n = clean(n0, 40), k = clean(k0, 60)
    guard okName(n), !isFigur(n) else { return nil }
    if let i = npc(n) {
      if !k.isEmpty, norm(npcs[i].kurz).isEmpty || norm(npcs[i].kurz) == norm(npcs[i].name), norm(k) != norm(npcs[i].name) { npcs[i].kurz = k }
      return (i, false)
    }
    if npcs.count >= 20 {   // evict an absent NPC (never one that is here)
      guard let e = npcs.firstIndex(where: { !$0.anwesend }) else { return nil }
      let id = npcs[e].id; npcs.remove(at: e); beziehungen.removeAll { $0.a == id || $0.b == id }
    }
    npcs.append(Npc(id: "n\(nextId)", name: n, kurz: k, ort: o ?? ort)); nextId += 1
    return (npcs.count - 1, true)
  }

  // MARK: delta
  /// Apply a delta (JSON from the world step: items, attitude, threads, movement). Unknown references are ignored.
  @discardableResult
  public mutating func apply(_ d: J) -> [String] {
    var log: [String] = []
    func edit(_ arr: inout [String], _ op: String, _ t0: String, _ cap: Int) {
      let t = clean(t0, 40); guard !t.isEmpty, tokens(t).count >= 1 else { return }
      if op == "+" { if !arr.contains(where: { norm($0) == norm(t) }) { arr.append(t); if arr.count > cap { arr.removeFirst() } } }
      else { arr.removeAll { norm($0) == norm(t) || norm($0).contains(norm(t)) } }
    }
    if let o = d["spielfigur_ort"].str.map({ clean($0) }), !o.isEmpty { ort = o; log.append("du → \(o)") }
    for e in d["ort_neu"].arr ?? [] { if let n = e["name"].str.map({ clean($0) }), !n.isEmpty, orte.count < 30 { orte[n] = clean(e["kurz"].str ?? "", 80); log.append("ort \(n)") } }
    for e in (d["figuren"].arr ?? []) + (d["npc_neu"].arr ?? []) {   // legacy / manual
      if let (i, new) = addNpc(name: e["name"].str ?? "", kurz: e["kurz"].str ?? "", ort: e["ort"].str.map { clean($0) }) { if new { log.append("neu \(npcs[i].name)") } }
    }
    for e in d["npc_ort"].arr ?? [] {
      if let w = e["wer"].str, let o = e["ort"].str.map({ clean($0) }), !o.isEmpty, let i = npc(w) {
        npcs[i].ort = o; npcs[i].anwesend = samePlace(o, ort); log.append("\(npcs[i].name) → \(o)")
      }
    }
    for e in d["zustand"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["text"].str else { continue }
      if isFigur(w) { edit(&zustand, op, t, 4); log.append("du \(op)\(clean(t, 40))") } else if let i = npc(w) { edit(&npcs[i].zustand, op, t, 3); log.append("\(npcs[i].name) \(op)\(clean(t, 40))") }
    }
    for e in d["item"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["name"].str else { continue }
      if isFigur(w) { edit(&inventar, op, t, 8); log.append("du \(op)\(clean(t, 40))") } else if let i = npc(w) { edit(&npcs[i].inventar, op, t, 4); log.append("\(npcs[i].name) \(op)\(clean(t, 40))") }
    }
    func rid(_ w: String) -> String? { isFigur(w) ? "du" : npc(w).map { npcs[$0].id } }
    for e in d["beziehung"].arr ?? [] {
      guard let a = e["a"].str, let b = e["b"].str, let v = e["wert"].int, let a2 = rid(a), let b2 = rid(b), a2 != b2 else { continue }
      let w = max(-2, min(2, v))
      if let i = beziehungen.firstIndex(where: { ($0.a == a2 && $0.b == b2) || ($0.a == b2 && $0.b == a2) }) { beziehungen[i].wert = w }
      else { beziehungen.append(Rel(a: a2, b: b2, wert: w)); if beziehungen.count > 20 { beziehungen.removeFirst() } }
      log.append("\(label(a2))↔\(label(b2)) \(w)")
    }
    for e in d["haltung"].arr ?? [] { if let w = e["wer"].str, let v = e["wert"].int, let i = npc(w) { npcs[i].haltung = max(-2, min(2, v)); log.append("\(npcs[i].name) Haltung \(npcs[i].haltung)") } }
    for e in d["strang"].arr ?? [] {
      guard let t = e["titel"].str.map({ clean($0) }), okName(t) || t.split(separator: " ").count <= 8, !t.isEmpty else { continue }
      let s = clean(e["stand"].str ?? "", 80)
      if let i = straenge.firstIndex(where: { norm($0.titel) == norm(t) }) { straenge[i].stand = s.isEmpty ? straenge[i].stand : s; _touched.insert(t) }
      else { straenge.append(Strang(titel: t, stand: s)); if straenge.count > 8 { straenge.removeFirst() } }
      log.append("strang \(t)")
    }
    return log
  }
  var _touched: Set<String> = []   // strands updated this turn (-> Schicksal bump); transient, not persisted
  private enum CodingKeys: String, CodingKey { case name, kurz, ort, zustand, inventar, npcs, orte, beziehungen, straenge, nextId }

  // MARK: one registry: Schicksal akteure/straenge are derived from the world
  public mutating func syncLists(_ eng: Engine?) {
    guard let eng else { return }
    func sync(_ list: String, _ want: [String]) {
      let have = { list == "akteure" ? eng.st.akteure : eng.st.straenge }
      var seen = Set<String>()
      for e in have() { if !want.contains(e.name) || !seen.insert(e.name).inserted { _ = eng.call("lists", ["list": .str(list), "op": "remove", "id": .str(e.id)]) } }   // stale or duplicate
      for n in want where !seen.contains(n) { _ = eng.call("lists", ["list": .str(list), "op": "add", "name": .str(n)]) }
    }
    sync("akteure", npcs.map(\.name))
    sync("straenge", straenge.map(\.titel))
    for t in _touched { if let id = eng.st.straenge.first(where: { norm($0.name) == norm(t) })?.id { _ = eng.call("lists", ["list": "straenge", "op": "bump", "id": .str(id)]) } }
    _touched = []
  }

  // MARK: fallback name hints ("die Wirtin Marta", "Marta, die Wirtin", "Köhlerin namens Ida") - strict: nominative article, or namens/comma form, or >=2 mentions
  static let roleWords = ["Wirtin", "Wirt", "Köhlerin", "Köhler", "Fährmann", "Händlerin", "Händler", "Wache", "Hauptmann", "Priesterin", "Priester", "Pfarrer", "Schmiedin", "Schmied", "Botin", "Bote", "Bürgermeister", "Vogt", "Mönch", "Nonne", "Knecht", "Magd", "Kapitän", "Steuermann", "Heilerin", "Heiler", "Bäuerin", "Bauer", "Jägerin", "Jäger", "Dame", "Herr", "Frau", "Kind", "Junge", "Mädchen"]
  static let stop: Set<String> = ["Sie", "Der", "Die", "Das", "Ein", "Eine", "Dann", "Doch", "Und", "Als", "Wie", "Wer", "Was", "Hier", "Dort", "Nur", "Noch", "Auch", "Mit", "Von", "Aber", "Seine", "Ihre", "Dein", "Deine", "Kommt", "Wischt", "Stand", "Steht", "Sitzt", "Blickt", "Hebt", "Tritt", "Sagt", "Antwortet", "Nickt", "Schüttelt", "Hat", "Ist", "War", "Wird", "Ihr", "Ihm", "Ihn", "Dir", "Dich", "Mich", "Mir", "Hinter", "Neben", "Vor", "Zu", "Bei", "Nach", "Aus", "Auf", "Fremder", "Fremde", "Brot", "Bier", "Wein", "Wasser", "Geld", "Münzen", "Silber", "Hand", "Kopf"]
  public static func nameHints(_ text: String) -> [(name: String, role: String)] {
    let roles = roleWords.joined(separator: "|"), cap = "[A-ZÄÖÜ][a-zäöüß]{2,}"
    var out: [(String, String)] = []
    let ns = text as NSString
    func scan(_ pat: String, name: Int, role: Int, strict: Bool, art: Int? = nil) {
      guard let re = try? NSRegularExpression(pattern: pat) else { return }
      for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let n = ns.substring(with: m.range(at: name)), r = ns.substring(with: m.range(at: role))
        if let a = art, m.range(at: a).location != NSNotFound, ["dem", "den", "einem", "einen", "des", "einer", "deinem", "seinem", "ihrem"].contains(ns.substring(with: m.range(at: a)).lowercased()) { continue }   // dative/accusative object, not a name
        guard !stop.contains(n), !roleWords.contains(n), !out.contains(where: { $0.0 == n }) else { continue }
        let mentions = text.components(separatedBy: n).count - 1
        if strict || mentions >= 2 { out.append((n, r)) }
      }
    }
    scan("\\b(\(roles))\\s+(?:namens|genannt)\\s+(\(cap))\\b", name: 2, role: 1, strict: true)
    scan("(\(cap)),\\s+(?:die|der|eine|ein)\\s+(\(roles))\\b", name: 1, role: 2, strict: true)
    scan("(?:\\b(\\w+)\\s+)?\\b(\(roles))\\s+(\(cap))\\b", name: 3, role: 2, strict: false, art: 1)
    return out
  }
  @discardableResult
  public mutating func adoptNames(_ hints: [(name: String, role: String)]) -> [String] {
    var log: [String] = []
    for h in hints where !isFigur(h.name) && npc(h.name) == nil {
      if let i = npcs.firstIndex(where: { $0.anwesend && norm($0.name) == norm(h.role) }) {   // generic present "Wirtin" -> "Marta" (never an absent one)
        log.append("\(npcs[i].name) heißt \(h.name)"); npcs[i].name = h.name
      } else if let (i, new) = addNpc(name: h.name, kurz: h.role, ort: ort), new { log.append("neu \(npcs[i].name) (\(h.role))") }
    }
    return log
  }
}
