import Foundation
import Schicksal

public struct Npc: Codable, Equatable {
  public var id: String, name: String, kurz: String
  public var ort: String?
  public var zustand: [String] = [], inventar: [String] = []
  public var haltung = 0            // -2 feindlich .. 2 loyal (towards the player character)
  public var notiz = ""
}
public struct Rel: Codable, Equatable { public var a: String, b: String, wert: Int }
public struct Strang: Codable, Equatable { public var titel: String, stand: String }

let haltungWort = [-2: "feindlich", -1: "misstrauisch", 0: "", 1: "freundlich", 2: "loyal"]
func cut(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n)) }
func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
func samePlace(_ a: String?, _ b: String?) -> Bool {
  guard let a = a.map(norm), let b = b.map(norm), !a.isEmpty, !b.isEmpty else { return false }
  return a == b || a.contains(b) || b.contains(a)
}

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

  /// "Aether: grauer Mann, 40" | "Aether, grauer Mann" | free text -> name?, kurz
  public static func parseFigur(_ t: String) -> (String?, String) {
    let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
    if let i = s.firstIndex(of: ":"), s[..<i].split(separator: " ").count <= 3 { return (String(s[..<i]).trimmingCharacters(in: .whitespaces), String(s[s.index(after: i)...]).trimmingCharacters(in: .whitespaces)) }
    if let i = s.firstIndex(of: ","), s[..<i].split(separator: " ").count == 1, s.first?.isUppercase == true { return (String(s[..<i]), String(s[s.index(after: i)...]).trimmingCharacters(in: .whitespaces)) }
    return (nil, cut(s, 140))
  }
  public mutating func setFigur(_ t: String) { let (n, k) = Self.parseFigur(t); name = n; kurz = k }
  func isFigur(_ w: String) -> Bool {
    let x = norm(w)
    return ["du", "ich", "spielfigur", "figur"].contains(x) || (name.map { norm($0) == x } ?? false)
  }
  func npc(_ w: String) -> Int? {
    let x = norm(w)
    return npcs.firstIndex { norm($0.id) == x || norm($0.name) == x } ?? npcs.firstIndex { norm($0.name).hasPrefix(x) || x.hasPrefix(norm($0.name)) && !x.isEmpty }
  }

  func here(_ n: Npc) -> Bool { samePlace(n.ort, ort) }

  /// Compact [Welt] block, relevant entries only (figure, current place, NPCs here, a few elsewhere, open threads).
  public func block(full: Bool = false) -> String {
    if isEmpty { return "" }
    var l = ["[Welt]"]
    var du = (name ?? "") + ((name != nil && kurz?.isEmpty == false) ? ", " : "") + (kurz ?? "")
    if du.isEmpty { du = "Spielfigur" }
    var d = "Du: \(du)."
    if let o = ort, !o.isEmpty { d += " Ort: \(o)." }
    if !zustand.isEmpty { d += " Zustand: \(zustand.joined(separator: ", "))." }
    if !inventar.isEmpty { d += " Inventar: \(inventar.joined(separator: ", "))." }
    l.append(d)
    let hs = npcs.filter(here)
    if !hs.isEmpty { l.append("Hier: " + hs.map(desc).joined(separator: " | ")) }
    let els = npcs.filter { !here($0) }.suffix(full ? 20 : 4)
    if !els.isEmpty { l.append("Anderswo: " + els.map { "\($0.name) (\($0.ort ?? "?"))" }.joined(separator: ", ")) }
    if !straenge.isEmpty { l.append("Stränge: " + straenge.suffix(full ? 8 : 3).map { "\($0.titel) – \($0.stand)" }.joined(separator: " | ")) }
    if full {
      if !orte.isEmpty { l.append("Orte: " + orte.sorted { $0.key < $1.key }.map { $0.value.isEmpty ? $0.key : "\($0.key) – \($0.value)" }.joined(separator: " | ")) }
      if !beziehungen.isEmpty { l.append("Beziehungen: " + beziehungen.map { "\($0.a)↔\($0.b) \($0.wert)" }.joined(separator: ", ")) }
    }
    return l.joined(separator: "\n")
  }
  func desc(_ n: Npc) -> String {
    var s = "\(n.name) – \(cut(n.kurz, 60))"
    var x = n.zustand + n.inventar.map { "trägt \($0)" }
    if let h = haltungWort[n.haltung], !h.isEmpty { x.append("Haltung zu dir: \(h)") }
    if !x.isEmpty { s += " (\(x.joined(separator: "; ")))" }
    return s
  }

  /// Haltung of an NPC at the current place named in `text` (for the oracle `shift` of social questions).
  public func haltung(in text: String) -> Int? {
    let t = norm(text)
    for n in npcs where here(n) && n.haltung != 0 {
      let w = norm(n.name)
      if t.contains(w) || w.split(separator: " ").contains(where: { $0.count >= 4 && t.contains($0) }) { return n.haltung }
    }
    return nil
  }

  /// Apply a delta (JSON from the world step). Unknown references are ignored, the player character is never an NPC.
  /// Returns human-readable log lines. `eng` syncs Schicksal lists (akteure/straenge).
  @discardableResult
  public mutating func apply(_ d: J, eng: Engine? = nil) -> [String] {
    var log: [String] = []
    func edit(_ arr: inout [String], _ op: String, _ t: String, _ cap: Int) {
      let t = cut(t.trimmingCharacters(in: .whitespaces), 40); guard !t.isEmpty else { return }
      if op == "+" { if !arr.contains(where: { norm($0) == norm(t) }) { arr.append(t); if arr.count > cap { arr.removeFirst() } } }
      else { arr.removeAll { norm($0) == norm(t) || norm($0).contains(norm(t)) } }
    }
    if let o = d["spielfigur_ort"].str, !o.trimmingCharacters(in: .whitespaces).isEmpty { ort = cut(o, 60); log.append("du → \(cut(o, 60))") }
    for e in d["ort_neu"].arr ?? [] { if let n = e["name"].str, !n.isEmpty, orte.count < 30 { orte[cut(n, 60)] = cut(e["kurz"].str ?? "", 80); log.append("ort \(n)") } }
    for e in (d["figuren"].arr ?? []) + (d["npc_neu"].arr ?? []) {
      guard let n = e["name"].str.map({ cut($0.trimmingCharacters(in: .whitespaces), 40) }), !n.isEmpty, !isFigur(n) else { continue }
      let k = cut(e["kurz"].str ?? "", 80), o = e["ort"].str.map { cut($0, 60) }
      if let i = npc(n) { if !k.isEmpty && norm(k) != norm(npcs[i].name) { npcs[i].kurz = k }; if let o { npcs[i].ort = o }; continue }
      if npcs.count >= 20 { if let i = npcs.firstIndex(where: { !here($0) }) { npcs.remove(at: i) } else { continue } }
      npcs.append(Npc(id: "n\(nextId)", name: n, kurz: k, ort: o ?? ort)); nextId += 1
      log.append("neu \(n)\(o.map { " (\($0))" } ?? "")")
      _ = eng?.call("lists", ["list": "akteure", "op": "add", "name": .str(n)])
    }
    for e in d["npc_ort"].arr ?? [] { if let w = e["wer"].str, let o = e["ort"].str, let i = npc(w) { npcs[i].ort = cut(o, 60); log.append("\(npcs[i].name) → \(cut(o, 60))") } }
    for e in d["zustand"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["text"].str else { continue }
      if isFigur(w) { edit(&zustand, op, t, 4); log.append("du \(op)\(t)") } else if let i = npc(w) { edit(&npcs[i].zustand, op, t, 3); log.append("\(npcs[i].name) \(op)\(t)") }
    }
    for e in d["item"].arr ?? [] {
      guard let w = e["wer"].str, let op = e["op"].str, let t = e["name"].str else { continue }
      if isFigur(w) { edit(&inventar, op, t, 8); log.append("du \(op)\(t)") } else if let i = npc(w) { edit(&npcs[i].inventar, op, t, 4); log.append("\(npcs[i].name) \(op)\(t)") }
    }
    for e in d["beziehung"].arr ?? [] {
      guard let a = e["a"].str, let b = e["b"].str, let v = e["wert"].int else { continue }
      let a2 = isFigur(a) ? "du" : (npc(a).map { npcs[$0].name } ?? ""), b2 = isFigur(b) ? "du" : (npc(b).map { npcs[$0].name } ?? "")
      guard !a2.isEmpty, !b2.isEmpty, a2 != b2 else { continue }
      let w = max(-2, min(2, v))
      if let i = beziehungen.firstIndex(where: { ($0.a == a2 && $0.b == b2) || ($0.a == b2 && $0.b == a2) }) { beziehungen[i].wert = w }
      else { beziehungen.append(Rel(a: a2, b: b2, wert: w)); if beziehungen.count > 20 { beziehungen.removeFirst() } }
      log.append("\(a2)↔\(b2) \(w)")
    }
    for e in d["haltung"].arr ?? [] { if let w = e["wer"].str, let v = e["wert"].int, let i = npc(w) { npcs[i].haltung = max(-2, min(2, v)); log.append("\(npcs[i].name) Haltung \(npcs[i].haltung)") } }
    for e in d["strang"].arr ?? [] {
      guard let t = e["titel"].str.map({ cut($0, 60) }), !t.isEmpty else { continue }
      let s = cut(e["stand"].str ?? "", 80)
      if let i = straenge.firstIndex(where: { norm($0.titel) == norm(t) }) {
        straenge[i].stand = s
        if let id = eng?.st.straenge.first(where: { norm($0.name) == norm(t) })?.id { _ = eng?.call("lists", ["list": "straenge", "op": "bump", "id": .str(id)]) }
      } else {
        straenge.append(Strang(titel: t, stand: s)); if straenge.count > 8 { straenge.removeFirst() }
        _ = eng?.call("lists", ["list": "straenge", "op": "add", "name": .str(t)])
      }
      log.append("strang \(t)")
    }
    return log
  }

  // MARK: deterministic name hints ("die Wirtin Marta", "Marta, die Wirtin", "Köhlerin namens Ida") - the 4B delta step often skips proper names
  static let roleWords = ["Wirtin", "Wirt", "Köhlerin", "Köhler", "Fährmann", "Händlerin", "Händler", "Wache", "Hauptmann", "Priesterin", "Priester", "Pfarrer", "Schmiedin", "Schmied", "Botin", "Bote", "Bürgermeister", "Vogt", "Mönch", "Nonne", "Knecht", "Magd", "Kapitän", "Steuermann", "Heilerin", "Heiler", "Bäuerin", "Bauer", "Jägerin", "Jäger", "Wirtsleute", "Dame", "Herr", "Frau", "Kind", "Junge", "Mädchen"]
  static let stop: Set<String> = ["Sie", "Der", "Die", "Das", "Ein", "Eine", "Dann", "Doch", "Und", "Als", "Wie", "Wer", "Was", "Hier", "Dort", "Nur", "Noch", "Auch", "Mit", "Von", "Aber", "Seine", "Ihre", "Dein", "Deine", "Kommt", "Wischt", "Stand", "Steht", "Sitzt", "Blickt", "Hebt", "Tritt", "Sagt", "Antwortet", "Nickt", "Schüttelt", "Hat", "Ist", "War", "Wird", "Ihr", "Ihm", "Ihn", "Dir", "Dich", "Mich", "Mir", "Hinter", "Neben", "Vor", "Zu", "Bei", "Nach", "Aus", "Auf", "Fremder", "Fremde"]
  public static func nameHints(_ text: String) -> [(name: String, role: String)] {
    let roles = roleWords.joined(separator: "|"), cap = "[A-ZÄÖÜ][a-zäöüß]{2,}"
    var out: [(String, String)] = []
    func scan(_ pat: String, name: Int, role: Int) {
      guard let re = try? NSRegularExpression(pattern: pat) else { return }
      let ns = text as NSString
      for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let n = ns.substring(with: m.range(at: name)), r = ns.substring(with: m.range(at: role))
        if !stop.contains(n) && !roleWords.contains(n) && !out.contains(where: { $0.0 == n }) { out.append((n, r)) }
      }
    }
    scan("\\b(\(roles))\\s+(?:namens\\s+|genannt\\s+)?(\(cap))\\b", name: 2, role: 1)
    scan("(\(cap)),\\s+(?:die|der|eine|ein)\\s+(\(roles))\\b", name: 1, role: 2)
    return out
  }
  /// Register or rename NPCs from name hints; returns log lines.
  @discardableResult
  public mutating func adoptNames(_ hints: [(name: String, role: String)], eng: Engine? = nil) -> [String] {
    var log: [String] = []
    for h in hints where !isFigur(h.name) && npc(h.name) == nil {
      if let i = npcs.firstIndex(where: { norm($0.name) == norm(h.role) }) {   // generic "Wirtin" -> "Marta"
        let old = npcs[i].name; npcs[i].name = h.name
        if let id = eng?.st.akteure.first(where: { $0.name == old })?.id { _ = eng?.call("lists", ["list": "akteure", "op": "remove", "id": .str(id)]) }
        _ = eng?.call("lists", ["list": "akteure", "op": "add", "name": .str(h.name)])
        log.append("\(old) heißt \(h.name)")
      } else if npcs.count < 20 {
        npcs.append(Npc(id: "n\(nextId)", name: h.name, kurz: h.role, ort: ort)); nextId += 1
        _ = eng?.call("lists", ["list": "akteure", "op": "add", "name": .str(h.name)])
        log.append("neu \(h.name) (\(h.role))")
      }
    }
    return log
  }
}
