import Foundation
import Schicksal

public struct Npc: Codable, Equatable {
  public var id: String, name: String, kurz: String
  public var ort: String?
  public var anwesend = true          // in the current scene (presence flag, not a place-string match)
  public var zustand: [String] = [], inventar: [String] = []
  public var haltung = 0              // -2 feindlich .. 2 loyal (towards the player character)
  public var notiz = ""
  public var fest = false             // generated / clue-holding: never evicted (its clues must stay reachable)
  public var tot = false              // dead: never present again, shown as "tot"
  public var bekannt: [String] = []   // facts the player has learned (revealed secrets); the only hidden-derived text that reaches [Welt]
  public var basis = 0                // base attitude: neglect never decays below it
  public var kontakt = 0              // world turn of the last contact
  public var gekraenkt = false        // attitude decayed through neglect
  public var geruecht = 0.0           // fractional gossip residue (half-strength spreading)
  public init(id: String, name: String, kurz: String, ort: String?, anwesend: Bool = true) { self.id = id; self.name = name; self.kurz = kurz; self.ort = ort; self.anwesend = anwesend }
  enum K: String, CodingKey { case id, name, kurz, ort, anwesend, zustand, inventar, haltung, notiz, bekannt, tot, fest, basis, kontakt, gekraenkt, geruecht }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); kurz = try c.decodeIfPresent(String.self, forKey: .kurz) ?? ""
    ort = try c.decodeIfPresent(String.self, forKey: .ort); anwesend = try c.decodeIfPresent(Bool.self, forKey: .anwesend) ?? true
    zustand = try c.decodeIfPresent([String].self, forKey: .zustand) ?? []; inventar = try c.decodeIfPresent([String].self, forKey: .inventar) ?? []
    haltung = try c.decodeIfPresent(Int.self, forKey: .haltung) ?? 0; notiz = try c.decodeIfPresent(String.self, forKey: .notiz) ?? ""
    bekannt = try c.decodeIfPresent([String].self, forKey: .bekannt) ?? []; tot = try c.decodeIfPresent(Bool.self, forKey: .tot) ?? false; fest = try c.decodeIfPresent(Bool.self, forKey: .fest) ?? false
    basis = try c.decodeIfPresent(Int.self, forKey: .basis) ?? 0; kontakt = try c.decodeIfPresent(Int.self, forKey: .kontakt) ?? 0
    gekraenkt = try c.decodeIfPresent(Bool.self, forKey: .gekraenkt) ?? false; geruecht = try c.decodeIfPresent(Double.self, forKey: .geruecht) ?? 0
  }
}
public struct Rel: Codable, Equatable { public var a: String, b: String, wert: Int }   // a/b = NPC id or "du"
/// A thread. Question/answer arc: stufe frage -> hinweise (>=1 hint) -> antwort (only via oracle JA/JA+ with >=2 hints, or the player solves it).
/// `extra` is free for later features (world generation, deadlines, secrets).
public struct Strang: Codable, Equatable {
  public var titel: String, stand: String
  public var stufe = "frage"
  public var hinweise: [String] = []
  public var antwort: String?
  public var extra: [String: String] = [:]
  public init(titel: String, stand: String) { self.titel = titel; self.stand = stand }
  enum K: String, CodingKey { case titel, stand, stufe, hinweise, antwort, extra }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    titel = try c.decode(String.self, forKey: .titel); stand = try c.decodeIfPresent(String.self, forKey: .stand) ?? ""
    stufe = try c.decodeIfPresent(String.self, forKey: .stufe) ?? "frage"; hinweise = try c.decodeIfPresent([String].self, forKey: .hinweise) ?? []
    antwort = try c.decodeIfPresent(String.self, forKey: .antwort); extra = try c.decodeIfPresent([String: String].self, forKey: .extra) ?? [:]
  }
  public var isQuestion: Bool { let w = titel.split(separator: " ").first.map { String($0).lowercased() } ?? ""; return ["wer", "wo", "was", "wie", "warum", "wieso", "weshalb", "wohin", "woher", "wann", "welche", "welcher", "welches", "wem", "wen"].contains(w) }
}

let haltungWort = [-2: "feindlich", -1: "misstrauisch", 0: "", 1: "freundlich", 2: "loyal"]
/// One identity key for place names (hidden refs, clue locations, world, visits): case, umlauts/ß, whitespace and a leading article do not matter.
func key(_ s: String) -> String {
  var t = s.lowercased().folding(options: [.diacriticInsensitive], locale: nil).replacingOccurrences(of: "ß", with: "ss")
  t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  for a in ["der ", "die ", "das ", "dem ", "den ", "des ", "zum ", "zur ", "am ", "im ", "ins ", "in der ", "in die ", "im "] where t.hasPrefix(a) && t.count > a.count + 2 { t.removeFirst(a.count); break }
  return t
}
func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
func tokens(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 } }
/// cut at a word boundary
func cutw(_ s: String, _ n: Int) -> String {
  if s.count <= n { return s }
  let p = String(s.prefix(n))
  if let i = p.lastIndex(of: " "), p.distance(from: p.startIndex, to: i) > n / 2 { return String(p[..<i]) }
  return p
}
/// Characters that may appear in generated data: Latin + German umlauts, digits, punctuation, arrows/check marks. Everything else
/// (Tibetan, Devanagari, CJK, Cyrillic, ...) is the signature of a decoding fault and is dropped / triggers a regeneration.
func isCleanScalar(_ u: Unicode.Scalar) -> Bool {
  switch u.value {
  case 0x20...0x7E, 0xA0...0x17F, 0x2010...0x2027, 0x2030...0x205E, 0x2190...0x21FF, 0x2713, 0x2717, 0xB7: return true
  default: return u.value == 0x0A || u.value == 0x09
  }
}
public func isCleanText(_ s: String) -> Bool { s.unicodeScalars.allSatisfy(isCleanScalar) }
public func stripForeign(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.filter(isCleanScalar))) }

/// Sanitize any model-produced string before it reaches the prompt (newlines, separators, control tokens).
public func clean(_ s: String, _ n: Int = 60) -> String {
  var t = stripForeign(s)
  for bad in ["<turn|>", "<|turn>", "<|im_start|>", "<|im_end|>", "<bos>", "[Welt]", "---", "|", "<", ">", "\n", "\r", "\t"] { t = t.replacingOccurrences(of: bad, with: " ") }
  t = t.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,;:–-"))
  return cutw(t, n)
}
let rejectNames: Set<String> = ["du", "dir", "dich", "dein", "mich", "ich", "mir", "mein", "wir", "ihr", "er", "sie", "es", "man", "niemand", "jemand", "spielfigur", "figur", "spieler", "-", "unbekannt", "umgebung", "alle"]
/// Status/item entries must be short noun phrases: no sentence punctuation, no finite verb, no "Name" statement, not the player's own name.
func okEntry(_ t: String, pc: Set<String>, allowComma: Bool = false) -> Bool {
  let w = t.split(separator: " ").map { $0.lowercased() }
  guard !w.isEmpty, w.count <= 6, !t.contains(where: { (allowComma ? ".!?:;" : ".!?:;,").contains($0) }) else { return false }
  if w.contains("name") || w.contains("namen") { return false }
  if w.contains(where: { ["ist", "sind", "war", "waren", "wird", "wurde", "hat", "haben", "hast", "bist", "bin", "dein", "deine", "deinen", "dir", "dich", "du", "ich", "mein", "meine"].contains($0) }) { return false }
  if !pc.isDisjoint(with: Set(w)) { return false }
  return true
}
/// F5: a place must be a plain name - no parentheses, hedges or placeholders ("Hafenschenke (oder ein ähnlicher Ort, abhängig von der")
func okPlace(_ p: String) -> Bool {
  let t = p.trimmingCharacters(in: .whitespaces)
  return !t.isEmpty && t.count <= 50 && t.split(separator: " ").count <= 6 && !t.contains(where: { "()[]{}<>…".contains($0) }) && !["oder", "abhängig", "etwa", "ähnlich", "vielleicht", "unbekannt", "platzhalter"].contains { norm(t).contains($0) }
}
/// at most n words, cut at a word boundary
func cutWords(_ s: String, _ n: Int) -> String { s.split(separator: " ").prefix(n).joined(separator: " ") }
let negations: Set<String> = ["nicht", "kein", "keine", "keiner", "keinen", "niemand", "nie", "nichts", "ohne", "verweigert", "verweigerte", "unmöglich"]
/// Thread titles: a short noun phrase (<=5 words), no sentence, no leading verb, no negation. "Der Weg ins Moor" ok; "Hilfe wird verweigert", "findet den Schlüssel" rejected.
func okThread(_ t: String) -> Bool {
  let w = t.split(separator: " ").map(String.init)
  if let f = w.first?.lowercased(), ["wer", "wo", "was", "wie", "warum", "wieso", "weshalb", "wohin", "woher", "wann", "welche", "welcher", "welches", "wem", "wen"].contains(f) {   // open question as thread title
    return w.count >= 3 && w.count <= 8 && !t.contains(where: { ".!?:;,".contains($0) }) && !w.contains(where: { negations.contains($0.lowercased()) })
  }
  guard !w.isEmpty, w.count <= 5, !t.contains(where: { ".!?:;,".contains($0) }) else { return false }
  guard let f = w.first, f.first?.isUppercase == true || ["der", "die", "das", "ein", "eine"].contains(f.lowercased()) else { return false }   // German nouns are capitalised; a lowercase start is a verb/sentence
  if w.contains(where: { negations.contains($0.lowercased()) }) { return false }
  if w.count > 1, ["wird", "werden", "wurde", "ist", "sind", "war", "hat", "haben"].contains(where: { w.map { $0.lowercased() }.contains($0) }) { return false }   // finite verb = sentence
  return !["finde", "suche", "hole", "töte", "rette", "gehe"].contains(f.lowercased())   // imperatives
}
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
  public var turn = 0
  public var festeStraenge: Set<String> = []   // threads that own unfound clues: never evicted by the thread cap
  public var regeln = "frei"          // rules module: frei | saeulen (core stays universal)
  public var pc = PCSheet()
  public var gen = GenState()          // generated-world state (visible parts only; secrets live in hidden.json)
  public var neglectN = 8             // turns without contact before an attitude decays one step
  public init() {}
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: CodingKeys.self)
    name = try c.decodeIfPresent(String.self, forKey: .name); kurz = try c.decodeIfPresent(String.self, forKey: .kurz); ort = try c.decodeIfPresent(String.self, forKey: .ort)
    zustand = try c.decodeIfPresent([String].self, forKey: .zustand) ?? []; inventar = try c.decodeIfPresent([String].self, forKey: .inventar) ?? []
    npcs = try c.decodeIfPresent([Npc].self, forKey: .npcs) ?? []; orte = try c.decodeIfPresent([String: String].self, forKey: .orte) ?? [:]
    beziehungen = try c.decodeIfPresent([Rel].self, forKey: .beziehungen) ?? []; straenge = try c.decodeIfPresent([Strang].self, forKey: .straenge) ?? []
    nextId = try c.decodeIfPresent(Int.self, forKey: .nextId) ?? 1; turn = try c.decodeIfPresent(Int.self, forKey: .turn) ?? 0; neglectN = try c.decodeIfPresent(Int.self, forKey: .neglectN) ?? 8
    gen = try c.decodeIfPresent(GenState.self, forKey: .gen) ?? GenState()
    festeStraenge = try c.decodeIfPresent(Set<String>.self, forKey: .festeStraenge) ?? []
    regeln = try c.decodeIfPresent(String.self, forKey: .regeln) ?? "frei"; pc = try c.decodeIfPresent(PCSheet.self, forKey: .pc) ?? PCSheet()
  }
  public var isEmpty: Bool { name == nil && kurz == nil && ort == nil && npcs.isEmpty && straenge.isEmpty && zustand.isEmpty && inventar.isEmpty }

  // MARK: player character
  /// "Aether: grauer Mann, 40" | "Aether, grauer Mann" | free text -> name?, kurz
  public static func parseFigur(_ t: String) -> (String?, String) {
    let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
    if let i = s.firstIndex(of: ":"), s[..<i].split(separator: " ").count <= 3 {
      let n = clean(String(s[..<i]), 40), k = clean(String(s[s.index(after: i)...]), 140)
      return (n.isEmpty ? nil : n, k)          // "/figur : nur Beschreibung" has no name; "Hans: " has a name and no description
    }
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
    if !straenge.isEmpty { l.append("Stränge: " + straenge.suffix(full ? 8 : 3).map(threadText).joined(separator: " | ")) }
    if full {
      if !orte.isEmpty { l.append("Orte: " + orte.sorted { $0.key < $1.key }.map { $0.value.isEmpty ? $0.key : "\($0.key) – \($0.value)" }.joined(separator: " | ")) }
      if !beziehungen.isEmpty { l.append("Beziehungen: " + beziehungen.map { "\(label($0.a))↔\(label($0.b)) \($0.wert)" }.joined(separator: ", ")) }
    }
    return l.joined(separator: "\n")
  }
  /// Display text for /welt and the web panel: no "[Welt]" header, no "Spielfigur" placeholder.
  public func panel() -> String {
    var l = block(full: true).split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { $0 != "[Welt]" }
    let noFigur = name == nil && (kurz ?? "").isEmpty
    if noFigur { if l.first?.hasPrefix("Du = ") == true { l.removeFirst() }; l.insert("Du = –  (noch keine Figur: /figur Name: Beschreibung)", at: 0) }
    if regeln == "saeulen" { l.insert("Regeln: Drei Säulen — " + pc.line, at: min(2, l.count)) }   // char sheet only while the module is active
    return l.joined(separator: "\n")
  }
  /// "? Wer hat den Brunnen vergiftet (2 Hinweise)" | "✓ Wer … : Antwort" | "Titel – stand"
  func threadText(_ t: Strang) -> String {
    if t.stufe == "antwort" { return "✓ \(t.titel)" + (t.antwort.map { " – \($0)" } ?? "") }
    if t.isQuestion || !t.hinweise.isEmpty {
      let n = t.hinweise.count
      return "? \(t.titel)" + (n > 0 ? " (\(n) Hinweis\(n == 1 ? "" : "e"))" : "")
    }
    return t.stand.isEmpty ? t.titel : "\(t.titel) – \(t.stand)"
  }
  func label(_ id: String) -> String { id == "du" ? "du" : (npcs.first { $0.id == id }?.name ?? id) }
  func card(_ n: Npc) -> String {
    var x: [String] = []
    if !n.kurz.isEmpty && norm(n.kurz) != norm(n.name) { x.append(cutw(n.kurz, 50)) }
    x.append(n.tot ? "tot" : (n.anwesend ? "hier" : (n.ort.map { clean($0, 30) } ?? "anderswo")))
    if n.gekraenkt { x.append("gekränkt") } else if let h = haltungWort[n.haltung], !h.isEmpty { x.append(h) }
    x += n.zustand.filter { !(n.tot && $0 == "tot") }.prefix(2); x += n.inventar.prefix(2).map { "trägt \($0)" }; x += n.bekannt.suffix(2).map { "bekannt: \($0)" }
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
    for n in npcs where n.anwesend && !n.tot && n.haltung != 0 {
      if !Set(tokens(n.name)).isDisjoint(with: qt) { return pos ? n.haltung : -n.haltung }
    }
    return nil
  }

  // MARK: scene / presence
  /// New scene: nobody is present unless named in beteiligte/expect.
  public mutating func startScene(ort o: String?, beteiligte: String, expect: String) {
    if let o, okPlace(clean(o)) { ort = clean(o); if orte[clean(o)] == nil, orte.count < 30 { orte[clean(o)] = "" } }
    let txt = Set(tokens(beteiligte + " " + expect))
    for i in npcs.indices {
      let present = !Set(tokens(npcs[i].name)).isDisjoint(with: txt)
      npcs[i].anwesend = present
      if present { npcs[i].ort = ort } else if npcs[i].ort == nil || samePlace(npcs[i].ort, ort) { npcs[i].ort = npcs[i].ort ?? ort }
    }
  }
  func samePlace(_ a: String?, _ b: String?) -> Bool { guard let a = a.map(key), let b = b.map(key), !a.isEmpty, !b.isEmpty else { return false }; return a == b }

  /// Narrator tail `Figuren: Marta (Wirtin), Bork` -> presence + new characters. "-" changes nothing.
  @discardableResult
  public mutating func applyTail(_ line: String) -> [String] {
    var s = line.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("Figuren:") { s = String(s.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
    _tailIds = []
    if s.isEmpty || s == "-" { return [] }
    var log: [String] = []
    for part in s.split(separator: ",") {
      var n = String(part), r = ""
      if let o = n.firstIndex(of: "("), let c = n.lastIndex(of: ")"), o < c { r = clean(String(n[n.index(after: o)..<c]), 40); n = String(n[..<o]) }
      n = clean(n, 40)
      guard okName(n), !isFigur(n) else { continue }
      if let i = npc(n) ?? npcs.firstIndex(where: { norm($0.kurz) == norm(n) }) {      // known by name, or by its role ("Wirtin")
        if npcs[i].tot { continue }
        if !r.isEmpty, !norm(npcs[i].kurz).contains(norm(r)), npcs[i].kurz.count < 40 { npcs[i].kurz = npcs[i].kurz.isEmpty ? r : "\(r), \(npcs[i].kurz)" }   // refine the role ("Kapitän, breiter Mann …")
        if !npcs[i].anwesend { npcs[i].anwesend = true; log.append("\(npcs[i].name) anwesend") }
        npcs[i].ort = ort          // present NPCs are where the player is (stale ort made [Welt] say "Kielboden" for 20 turns)
        _tailIds.insert(npcs[i].id)
      } else if !r.isEmpty, let i = npcs.firstIndex(where: { $0.anwesend && norm($0.name) == norm(r) }) {   // role-named NPC gets its proper name
        log.append("\(npcs[i].name) heißt \(n)"); npcs[i].name = n; _tailIds.insert(npcs[i].id)
      } else if let (i, new) = addNpc(name: n, kurz: r, ort: ort) { _tailIds.insert(npcs[i].id); if new { log.append("neu \(npcs[i].name)") } }
    }
    return log
  }

  /// New NPC (present, at the current place). Existing NPC: only the role word may be refined; never moved.
  @discardableResult
  mutating func addNpc(name n0: String, kurz k0: String, ort o: String?) -> (Int, Bool)? {
    let n = clean(n0, 40), k = cutWords(clean(k0, 60), 6)
    guard okName(n), !isFigur(n) else { return nil }
    if let i = npc(n) {
      if !k.isEmpty, norm(npcs[i].kurz).isEmpty || norm(npcs[i].kurz) == norm(npcs[i].name), norm(k) != norm(npcs[i].name) { npcs[i].kurz = k }
      return (i, false)
    }
    if npcs.count >= 20 {   // evict an absent, non-protected NPC (never one that is here, generated or holds a clue)
      guard let e = npcs.firstIndex(where: { !$0.anwesend && !$0.fest }) else { return nil }
      let id = npcs[e].id; npcs.remove(at: e); beziehungen.removeAll { $0.a == id || $0.b == id }
    }
    npcs.append(Npc(id: "n\(nextId)", name: n, kurz: k, ort: o ?? ort)); nextId += 1
    return (npcs.count - 1, true)
  }

  /// The player moved to another place without a scene change: everybody not named in this turn's narrator tail stays behind.
  public mutating func figurMoved(from old: String?) {
    guard !samePlace(old, ort) else { return }
    for i in npcs.indices where !npcs[i].tot { if _tailIds.contains(npcs[i].id) { npcs[i].anwesend = true; npcs[i].ort = ort } else if npcs[i].anwesend { npcs[i].anwesend = false; npcs[i].ort = old } }
  }

  // MARK: delta
  /// Apply a delta (JSON from the world step: items, attitude, threads, movement). Unknown references are ignored.
  @discardableResult
  public mutating func apply(_ d: J) -> [String] {
    var log: [String] = []
    let pcSnap = pcTokens
    @discardableResult
    func edit(_ arr: inout [String], _ op: String, _ t0: String, _ cap: Int, comma: Bool = false) -> Bool {
      let t = cutWords(clean(t0, 40), 6); guard !t.isEmpty, tokens(t).count >= 1, op == "-" || okEntry(t, pc: pcSnap, allowComma: comma) else { return false }
      if op == "+" { if arr.contains(where: { norm($0) == norm(t) }) { return false }; arr.append(t); if arr.count > cap { arr.removeFirst() }; return true }
      let n = arr.count; arr.removeAll { norm($0) == norm(t) || norm($0).contains(norm(t)) }; return arr.count != n
    }
    if let o = d["spielfigur_ort"].str.map({ clean($0) }), okPlace(o) { ort = o; log.append("du → \(o)") }
    for e in d["ort_neu"].arr ?? [] { if let n = e["name"].str.map({ clean($0) }), okPlace(n), orte.count < 30 { orte[n] = clean(e["kurz"].str ?? "", 80); log.append("ort \(n)") } }
    for e in (d["figuren"].arr ?? []) + (d["npc_neu"].arr ?? []) {   // legacy / manual
      if let (i, new) = addNpc(name: e["name"].str ?? "", kurz: e["kurz"].str ?? "", ort: e["ort"].str.map { clean($0) }) { if new { log.append("neu \(npcs[i].name)") } }
    }
    for e in d["npc_ort"].arr ?? [] {
      if let w = e["wer"].str, let o = e["ort"].str.map({ clean($0) }), okPlace(o), let i = npc(w), !npcs[i].tot {
        npcs[i].ort = o; npcs[i].anwesend = samePlace(o, ort); log.append("\(npcs[i].name) → \(o)")
      }
    }
    for e in d["zustand"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["text"].str else { continue }
      if isFigur(w) { if edit(&zustand, op, t, 4) { log.append("du \(op)\(clean(t, 40))") } } else if let i = npc(w) { if edit(&npcs[i].zustand, op, t, 3) { log.append("\(npcs[i].name) \(op)\(clean(t, 40))") } }
    }
    for e in d["item"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["name"].str else { continue }
      if isFigur(w) { if edit(&inventar, op, t, 8, comma: true) { log.append("du \(op)\(clean(t, 40))") } } else if let i = npc(w) { if edit(&npcs[i].inventar, op, t, 4, comma: true) { log.append("\(npcs[i].name) \(op)\(clean(t, 40))") } }
    }
    func rid(_ w: String) -> String? { isFigur(w) ? "du" : npc(w).map { npcs[$0].id } }
    for e in d["beziehung"].arr ?? [] {
      guard let a = e["a"].str, let b = e["b"].str, let v = e["wert"].int, let a2 = rid(a), let b2 = rid(b), a2 != b2 else { continue }
      let w = max(-2, min(2, v))
      if let i = beziehungen.firstIndex(where: { ($0.a == a2 && $0.b == b2) || ($0.a == b2 && $0.b == a2) }) { beziehungen[i].wert = w }
      else { beziehungen.append(Rel(a: a2, b: b2, wert: w)); if beziehungen.count > 20 { beziehungen.removeFirst() } }
      log.append("\(label(a2))↔\(label(b2)) \(w)")
    }
    for e in d["tot"].arr ?? [] { if let w = e["wer"].str, let i = npc(w) { log += kill(i) } }
    for e in d["haltung"].arr ?? [] { if let w = e["wer"].str, let v = e["wert"].int, let i = npc(w) { log += setHaltung(i, v) } }
    for e in d["strang"].arr ?? [] {   // the delta step may only ADD HINTS (or open a thread); it can never mark one answered
      guard var t = e["titel"].str.map({ clean($0, 70) }) else { continue }
      while t.hasSuffix("?") { t.removeLast() }
      guard okThread(t) else { continue }
      let hint = cutWords(clean(e["hinweis"].str ?? "", 70), 8), legacy = cutWords(clean(e["stand"].str ?? "", 80), 6)
      if let i = straenge.firstIndex(where: { norm($0.titel) == norm(t) }) {
        if !hint.isEmpty, straenge[i].stufe != "antwort", !straenge[i].hinweise.contains(where: { norm($0) == norm(hint) }) {
          straenge[i].hinweise.append(hint); if straenge[i].hinweise.count > 3 { straenge[i].hinweise.removeFirst() }
          straenge[i].stufe = "hinweise"; straenge[i].stand = cutWords(hint, 6)
        } else if !legacy.isEmpty { straenge[i].stand = legacy }
        _touched.insert(t)
      } else {
        var n = Strang(titel: t, stand: legacy)
        if !hint.isEmpty { n.hinweise = [hint]; n.stufe = "hinweise"; n.stand = cutWords(hint, 6) }
        straenge.append(n)
        if straenge.count > 8, let e = straenge.firstIndex(where: { !festeStraenge.contains($0.titel) }) { straenge.remove(at: e) }   // oldest thread WITHOUT unfound clues
      }
      log.append("strang \(t)")
    }
    return log
  }
  var _touched: Set<String> = []
  public var talkedThisTurn: Set<String> = []   // transient: /gespraech counts as contact for the next tick
  public internal(set) var _tailIds: Set<String> = []   // NPC ids named in this turn's narrator tail (transient)   // strands updated this turn (-> Schicksal bump); transient, not persisted
  enum CodingKeys: String, CodingKey { case name, kurz, ort, zustand, inventar, npcs, orte, beziehungen, straenge, nextId, turn, neglectN, gen, regeln, pc, festeStraenge }

  // MARK: death + presence sync (F5)
  @discardableResult
  public mutating func kill(_ i: Int) -> [String] {
    guard !npcs[i].tot else { return [] }
    npcs[i].tot = true; npcs[i].anwesend = false; npcs[i].haltung = 0
    if !npcs[i].zustand.contains("tot") { npcs[i].zustand.insert("tot", at: 0) }
    return ["\(npcs[i].name) ist tot"]
  }
  static let intransitive = ["stirbt", "starb", "gestorben", "ist tot", "war tot", "fällt tot", "stürzt tot", "tot zu boden", "verendet", "verblutet", "röchelt sein letztes", "haucht sein leben", "haucht ihr leben"]
  static let transitive = ["erschlägt", "ersticht", "tötet", "erdolcht", "erwürgt", "erschießt", "richtet hin", "ermordet", "erschlagen", "erstochen", "getötet", "hingerichtet", "erschossen"]
  static let hedges = ["nicht", "kaum", "beinahe", "fast ", "wäre", "könnte", "würde", "angeblich", "gerüchte", "wenn ", "falls", "kein ", "niemand", "sagt", "sagte", "erzählt", "berichtet", "dass", "meint", "glaubt", "behauptet", "erinnert", "vor jahren", "damals"]   // reported speech / past events (observers are handled by "name right before the verb")
  /// Narration says a named NPC dies -> mark dead (the delta step often misses it: "Ithror stirbt" left him alive in [Welt]).
  /// "X stirbt" / "X wurde erschlagen": X is before the verb; "Kara erschlägt X": X is after the verb.
  @discardableResult
  public mutating func markDeaths(narr: String) -> [String] {
    var log: [String] = []
    let sentences = narr.components(separatedBy: CharacterSet(charactersIn: ".!?")).map { $0.lowercased() }
    var last: Int?                               // the single NPC named in the previous sentence ("Ithror sinkt zusammen. Er stirbt …")
    for sn in sentences {
      defer { let named = npcs.indices.filter { !tokens(npcs[$0].name).allSatisfy { !sn.contains($0) } }; if named.count == 1 { last = named[0] } }
      guard !Self.hedges.contains(where: { sn.contains($0) }) else { continue }
      let passive = ["wurde", "wird", "wurden", "worden", "ist ", "war "].contains { sn.contains($0) }
      let iv = Self.intransitive.compactMap { sn.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
      let tv = Self.transitive.compactMap { sn.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
      var hit = false
      // candidates in order of appearance
      let named = npcs.indices.compactMap { i -> (Int, String.Index)? in
        guard !npcs[i].tot, let p = tokens(npcs[i].name).compactMap({ sn.range(of: $0)?.lowerBound }).min() else { return nil }
        return (i, p) }.sorted { $0.1 < $1.1 }
      if !named.isEmpty { hit = true }
      if let d = iv, let victim = named.last(where: { $0.1 < d.lowerBound }) { log += kill(victim.0) }       // "X stirbt": the name right before the verb (an observer named earlier is not the victim)
      else if let d = tv {
        if passive { if let victim = named.last(where: { $0.1 < d.lowerBound }) { log += kill(victim.0) } }   // "X wurde erschlagen": LAST name before the verb
        else if let victim = named.first(where: { $0.1 > d.upperBound }) { log += kill(victim.0) }           // "Kara erschlägt X": first name after the verb
      }
      if !hit, let l = last, !npcs[l].tot, iv != nil, sn.trimmingCharacters(in: .whitespaces).hasPrefix("er ") || sn.trimmingCharacters(in: .whitespaces).hasPrefix("sie ") { log += kill(l) }   // pronoun subject
    }
    return log
  }
  /// Undo a wrongly detected death (`/lebt <Figur>`).
  @discardableResult
  public mutating func revive(_ i: Int) -> Bool {
    guard npcs[i].tot else { return false }
    npcs[i].tot = false; npcs[i].zustand.removeAll { $0 == "tot" }; npcs[i].anwesend = samePlace(npcs[i].ort, ort); return true
  }
  /// An NPC named in the narration, last seen at the player's current place, is present (the tail/delta steps often forget this).
  public mutating func syncPresence(narr: String) {
    let nt = Set(tokens(narr))
    for i in npcs.indices where !npcs[i].tot && !npcs[i].anwesend && samePlace(npcs[i].ort, ort) && !Set(tokens(npcs[i].name)).isDisjoint(with: nt) { npcs[i].anwesend = true }
  }

  // MARK: neglect + gossip
  /// Sets an attitude; a notable change (>=1 step) spreads at half strength along relations, one hop only.
  @discardableResult
  public mutating func setHaltung(_ i: Int, _ v: Int, gossip: Bool = true) -> [String] {
    let old = npcs[i].haltung, nv = max(-2, min(2, v)), d = nv - old
    guard d != 0 else { return [] }
    npcs[i].haltung = nv; npcs[i].gekraenkt = false
    var log = ["\(npcs[i].name) Haltung \(nv)"]
    guard gossip else { return log }
    let id = npcs[i].id
    for r in beziehungen where r.wert != 0 && (r.a == id || r.b == id) {
      let other = r.a == id ? r.b : r.a
      guard other != "du", let j = npcs.firstIndex(where: { $0.id == other }) else { continue }
      // friends share the opinion, enemies take the opposite; half strength via a fractional residue
      npcs[j].geruecht += Double(d) * 0.5 * (r.wert > 0 ? 1 : -1)
      let step = Int(npcs[j].geruecht.rounded(.towardZero))
      if step != 0 {
        npcs[j].geruecht -= Double(step)
        let before = npcs[j].haltung; npcs[j].haltung = max(-2, min(2, before + step))
        if npcs[j].haltung != before { log.append("Gerücht: \(npcs[j].name) Haltung \(npcs[j].haltung)") }
      }
    }
    return log
  }
  /// One player turn passed. `contacts` = NPC ids met this turn. Attitudes decay one step towards their base after `neglectN` quiet turns.
  @discardableResult
  public mutating func tick(contacts: Set<String>) -> [String] {
    turn += 1
    var log: [String] = []
    defer { talkedThisTurn = [] }
    for i in npcs.indices where !npcs[i].tot {
      if contacts.contains(npcs[i].id) { npcs[i].kontakt = turn; continue }
      guard turn - npcs[i].kontakt >= neglectN else { continue }
      npcs[i].kontakt = turn                                  // the timer restarts: one step per N quiet turns
      if npcs[i].haltung > npcs[i].basis { npcs[i].haltung -= 1; npcs[i].gekraenkt = true; log.append("\(npcs[i].name) vernachlässigt → Haltung \(npcs[i].haltung)") }
    }
    return log
  }
  /// ids of NPCs named in a text (player line) - counts as contact
  /// NPCs spoken to via /gespraech since the last tick (tick clears the set - read it BEFORE ticking)
  public func talkedNames() -> [String] { npcs.filter { talkedThisTurn.contains($0.id) }.map(\.name) }
  public func mentioned(in text: String) -> Set<String> {
    let t = Set(tokens(text)); return Set(npcs.filter { !Set(tokens($0.name)).isDisjoint(with: t) }.map(\.id))
  }

  // MARK: question/answer threads
  /// "antwort" is reachable only with >=2 hints AND an oracle JA/JA+ about the thread (or the player solves it explicitly).
  @discardableResult
  public mutating func oracleSolved(question q: String, answer: String) -> [String] {
    guard answer == "JA" || answer == "JA+" else { return [] }
    let qt = Set(tokens(q).filter { $0.count >= 4 }); var log: [String] = []
    for i in straenge.indices where straenge[i].stufe != "antwort" && straenge[i].hinweise.count >= 2 {
      if Set(tokens(straenge[i].titel).filter { $0.count >= 4 }).intersection(qt).count >= 2 { straenge[i].stufe = "antwort"; straenge[i].antwort = cutWords(straenge[i].hinweise.last ?? "", 8); log.append("Antwort: \(straenge[i].titel)") }
    }
    return log
  }
  /// The player solves a thread by hand (`/geloest <Teil des Titels>`).
  public mutating func solve(_ fragment: String) -> String? {
    let f = norm(fragment); guard !f.isEmpty, let i = straenge.firstIndex(where: { norm($0.titel).contains(f) && $0.stufe != "antwort" }) else { return nil }
    straenge[i].stufe = "antwort"; straenge[i].antwort = straenge[i].hinweise.last.map { cutWords($0, 8) }; return straenge[i].titel
  }

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

/// Repairs glyph-corrupted values in an existing world (older sessions): a value with foreign characters is matched against the known
/// word lists (slot enums, roles) with the foreign run as a wildcard; otherwise the foreign characters are dropped.
public func repairGlyphs(_ s: String, vocab: [String] = []) -> String {
  if isCleanText(s) { return s }
  let words = Set(vocab + GenSlots.enums.values.flatMap { $0 } + GenGr.roles)
  // "tr࿋" / "Glཬkner": a run of foreign scalars becomes `.{1,3}`; the (shortest) vocabulary word that fits is the repair
  var pat = ""; var inRun = false
  for u in s.unicodeScalars { if isCleanScalar(u) { pat += NSRegularExpression.escapedPattern(for: String(u)); inRun = false } else if !inRun { pat += ".{1,3}"; inRun = true } }
  var out = s
  if !s.contains(" "), let re = try? NSRegularExpression(pattern: "^" + pat + "$", options: [.caseInsensitive]) {
    let hits = words.filter { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }.sorted { $0.count < $1.count }
    if let h = hits.first { return h }
  }
  out = stripForeign(s)
  return out
}
extension World {
  /// Repair all stored strings of a loaded world (F4: sessions written before the const_string fix).
  public mutating func repairText() {
    func fix(_ s: String) -> String { repairGlyphs(s) }
    name = name.map(fix); kurz = kurz.map(fix); ort = ort.map(fix)
    zustand = zustand.map(fix); inventar = inventar.map(fix)
    for i in npcs.indices { npcs[i].name = fix(npcs[i].name); npcs[i].kurz = fix(npcs[i].kurz); npcs[i].ort = npcs[i].ort.map(fix); npcs[i].zustand = npcs[i].zustand.map(fix); npcs[i].inventar = npcs[i].inventar.map(fix); npcs[i].bekannt = npcs[i].bekannt.map(fix) }
    orte = Dictionary(orte.map { (fix($0.key), fix($0.value)) }, uniquingKeysWith: { a, _ in a })
    for i in straenge.indices { straenge[i].titel = fix(straenge[i].titel); straenge[i].stand = fix(straenge[i].stand); straenge[i].hinweise = straenge[i].hinweise.map(fix) }
    for k in GenSlots.keys { gen.slots[k] = fix(gen.slots[k]) }
    gen.praemisse = fix(gen.praemisse); gen.alltag = fix(gen.alltag); gen.start = fix(gen.start); gen.szene = fix(gen.szene)
    gen.orte = Dictionary(gen.orte.map { (fix($0.key), fix($0.value)) }, uniquingKeysWith: { a, _ in a })
  }
}
