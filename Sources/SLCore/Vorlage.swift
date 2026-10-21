import Foundation
import Schicksal

/// Prepared one-shot world: worlds/<id>/{vorlage.json, world.json, hidden.json}. world.json / hidden.json use the same schema as a session dir.
/// vorlage.json carries the narrator block, the "Blick des Schicksals" tier cues (index 0...2) and the "Eingriff" cue for tension 9.
public struct Vorlage: Codable, Equatable {
  public var id: String, titel: String, setting: String
  public var prompt: String                 // appended to the narrator system prompt
  public var stufen: [String]               // hidden cues when the tension enters tier 0 (1-3), 1 (4-6), 2 (7-8)
  public var eingriff: String               // hidden cue at tension 9
  public var eingriffReset = 5              // tension after the intervention
  public var start = 3                      // tension at the start
  public var auftakt: String                // hidden opening for the narrator
  public var fremdCue: String               // hidden cue after a Fremdkraft use
  enum K: String, CodingKey { case id, titel, setting, prompt, stufen, eingriff, eingriffReset, start, auftakt, fremdCue }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    id = try c.decode(String.self, forKey: .id); titel = try c.decode(String.self, forKey: .titel); setting = try c.decode(String.self, forKey: .setting)
    prompt = try c.decode(String.self, forKey: .prompt); stufen = try c.decode([String].self, forKey: .stufen); eingriff = try c.decode(String.self, forKey: .eingriff)
    eingriffReset = try c.decodeIfPresent(Int.self, forKey: .eingriffReset) ?? 5; start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 3
    auftakt = try c.decodeIfPresent(String.self, forKey: .auftakt) ?? ""
    fremdCue = try c.decodeIfPresent(String.self, forKey: .fremdCue) ?? "Die Fäden zittern: eine Fremdkraft wurde benutzt. Lass es spürbar werden (ein Zufall, ein Blick, ein Geräusch), ohne den Begriff zu nennen."
  }

  /// search order: $SL_WORLDS, ./worlds, <repo>/worlds (next to Package.swift, via this source file), ~/Projects/sl-pnp/worlds
  public static func roots() -> [URL] {
    var r: [URL] = []
    if let e = ProcessInfo.processInfo.environment["SL_WORLDS"] { r.append(URL(fileURLWithPath: (e as NSString).expandingTildeInPath)) }
    r.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("worlds"))
    r.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("worlds"))
    r.append(URL(fileURLWithPath: NSHomeDirectory() + "/Projects/sl-pnp/worlds"))
    return r
  }
  public static func dir(_ id: String, roots: [URL] = roots()) -> URL? {
    guard id.range(of: #"^[a-z0-9_-]{1,30}$"#, options: .regularExpression) != nil else { return nil }
    return roots.map { $0.appendingPathComponent(id) }.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("vorlage.json").path) }
  }
  public static func load(_ id: String, roots: [URL] = roots()) -> Vorlage? {
    guard let d = dir(id, roots: roots), let data = try? Data(contentsOf: d.appendingPathComponent("vorlage.json")) else { return nil }
    return try? JSONDecoder().decode(Vorlage.self, from: data)
  }
  /// world.json + hidden.json of the template (rules schicksal, vorlage id set, generated-world flag so [Welt] shows the premise)
  public static func worldData(_ id: String, roots: [URL] = roots()) throws -> (World, HiddenWorld) {
    guard let d = dir(id, roots: roots) else { throw SLError("Vorlage '\(id)' nicht gefunden (worlds/\(id)/vorlage.json; Suchpfade: SL_WORLDS, ./worlds)") }
    var w = try JSONDecoder().decode(World.self, from: Data(contentsOf: d.appendingPathComponent("world.json")))
    var h = (try? JSONDecoder().decode(HiddenWorld.self, from: Data(contentsOf: d.appendingPathComponent("hidden.json")))) ?? HiddenWorld()
    w.repairText(); h.repairText(); w.regeln = "schicksal"; w.vorlage = id; w.eingriffe = 0
    w.gen.ready = true
    h.canonPlaces(Array(w.orte.keys) + Array(w.gen.orte.keys))
    return (w, h)
  }
}

/// "Blick des Schicksals" = the tension (1-9) in a world with a Vorlage. Pure helpers (testable without a model).
public enum Blick {
  /// 0: unbemerkt (1-3), 1: Fäden zittern (4-6), 2: Schicksalsboten (7-8), 3: Eingriff (9)
  public static func stufe(_ s: Int) -> Int { s <= 3 ? 0 : (s <= 6 ? 1 : (s <= 8 ? 2 : 3)) }
  public static let namen = ["unbemerkt", "Fäden zittern", "Schicksalsboten", "Eingriff"]
  /// hidden narrator cue for a tension move; nil = nothing to say. `eingriff` = the 9 was reached (the caller then resets the tension).
  public static func note(_ v: Vorlage, from a: Int, to b: Int) -> (cue: String?, eingriff: Bool) {
    if b >= 9 { return (v.eingriff, true) }
    if stufe(a) == stufe(b) { return (nil, false) }
    let i = stufe(b)
    return (i < v.stufen.count ? v.stufen[i] : nil, false)
  }
  /// +n on the engine's tension (clamped); returns before/now
  @discardableResult
  public static func raise(_ eng: Engine, by n: Int) -> (before: Int, now: Int) {
    let b = eng.st.s, ns = clampTension(b + n)
    if ns != b { _ = eng.call("session", ["op": "set_tension", "s": .int(ns)]) }
    return (b, ns)
  }
  /// tension after the intervention
  public static func reset(_ eng: Engine, to s: Int) { _ = eng.call("session", ["op": "set_tension", "s": .int(clampTension(s))]) }
}

extension Game {
  public var vorlageInfo: Vorlage? { world.vorlage.flatMap { Vorlage.load($0) } }
  /// narrator system block of the prepared world
  var vorlageBlock: String { vorlageInfo.map { "\n\n" + $0.prompt } ?? "" }

  /// after any tension move: tier change -> hidden cue; 9 -> the Eingriff cue, count it and drop the tension to the reset value
  func blickAfter(from before: Int) {
    guard let v = vorlageInfo else { return }
    let now = eng.st.s
    let n = Blick.note(v, from: before, to: now)
    if let c = n.cue { pendingRegie.append(c) }
    if n.eingriff {
      world.eingriffe += 1
      Blick.reset(eng, to: v.eingriffReset)
      out(.info("Eingriff des Schicksals: Blick des Schicksals \(now) → \(v.eingriffReset). Der Erzähler spielt das Set-Piece aus dem One-Shot."))
    }
  }
  /// a Fremdkraft was used in a check: +1 tension, GM info line, hidden cue ("the threads tremble")
  func fremdkraftUsed(_ who: String, _ t: Trait) {
    let r = Blick.raise(eng, by: 1)
    out(.info("Fremdkraft: \(who) nutzt \(t.text). Blick des Schicksals \(r.before) → \(r.now)"))
    pendingRegie.append(vorlageInfo?.fremdCue ?? "Die Fäden zittern: eine Fremdkraft wurde benutzt. Lass es spürbar werden, ohne den Begriff zu nennen.")
    blickAfter(from: r.before)
  }
  /// start a session from a prepared world: world + hidden, setting, start tension, opening cue
  public func applyVorlage(_ id: String) throws {
    guard let v = Vorlage.load(id) else { throw SLError("Vorlage '\(id)' nicht gefunden (worlds/\(id)/vorlage.json)") }
    let (w, h) = try Vorlage.worldData(id)
    let party = world.party, neglect = world.neglectN
    world = w; hidden = h; world.party = party; world.neglectN = neglect
    setting = v.setting
    world.syncLists(eng)
    _ = eng.call("session", ["op": "set_tension", "s": .int(clampTension(v.start))])
    if !v.auftakt.isEmpty { pendingNote = "Auftakt (verdeckt vorgegeben): \(v.auftakt)" }
  }
}

extension Game {
  /// GM convenience for the familiar: "laut" (heard by NPCs, +1) or "eingriff" (physical / own power, +2); a hidden cue goes to the narrator
  func vertrauterBlick(_ a: String) -> (what: String, before: Int, now: Int)? {
    let k = a.trimmingCharacters(in: .whitespaces).lowercased()
    let (n, what, cue): (Int, String, String)
    switch k {
    case "laut": (n, what, cue) = (1, "laut", "Der Kater hat hörbar vor NPCs gesprochen: die Umstehenden haben es gehört und reagieren darauf. Erfinde keine Worte des Katers, die Spielleitung spricht für ihn.")
    case "eingriff": (n, what, cue) = (2, "eingriff", "Der Kater hat körperlich eingegriffen oder seine eigene Kraft benutzt: es fällt auf, die Fäden zittern. Beschreibe nur die sichtbare Wirkung, nicht seine Wahrnehmung.")
    default: return nil
    }
    let r = Blick.raise(eng, by: n)
    pendingRegie.append(cue)
    blickAfter(from: r.before)
    return (what, r.before, eng.st.s)
  }
}
