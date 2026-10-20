import Foundation

/// Optional rules module. The core stays universal: `Frei` (default) changes nothing. The model only CLASSIFIES the action (`art`), the program does all maths.
public enum Art: String, Codable, CaseIterable { case kampf, sozial, wissen, sonst }

public struct PCSheet: Codable, Equatable {
  public var kampf = 0, sozial = 0, wissen = 0          // -1 ... +2
  public var talente: [String] = []                      // 2-3 free-text talents
  public init() {}
  public func wert(_ a: Art) -> Int { switch a { case .kampf: return kampf; case .sozial: return sozial; case .wissen: return wissen; case .sonst: return 0 } }
  public mutating func setWert(_ a: Art, _ v: Int) { let c = max(-1, min(2, v)); switch a { case .kampf: kampf = c; case .sozial: sozial = c; case .wissen: wissen = c; case .sonst: break } }
  public var line: String { "Kampf \(kampf) · Sozial \(sozial) · Wissen \(wissen)" + (talente.isEmpty ? "" : " · Talente: " + talente.joined(separator: ", ")) }
}

public protocol Regelwerk {
  var id: String { get }
  var titel: String { get }
  /// added to the oracle odds shift (combined with the NPC-attitude shift, total clamped to -2...2)
  func oddsShift(art: Art, pc: PCSheet, input: String) -> Int
  /// extra Spur points while the player is on the track of a secret (`tier` = current tier of that secret)
  func spurBonus(art: Art, pc: PCSheet, tier: Int) -> Int
  /// strengthens attitude changes (/gespraech, social actions)
  func haltungDelta(_ d: Int, art: Art, pc: PCSheet) -> Int
  /// a thread was solved: returns the progressed sheet
  func progress(onThreadSolved pc: PCSheet, art: Art?) -> PCSheet
}
// Stub hook for a later "w20" module (d20 vs a difficulty class, rolled with Schicksal's Engine.randomBelow): it would add
// `func check(art:pc:input:rand:) -> (roll: Int, dc: Int, success: Bool)?` here. Deliberately not implemented.

/// default: current behaviour, zero changes
public struct Frei: Regelwerk {
  public init() {}
  public let id = "frei", titel = "frei (keine Regeln)"
  public func oddsShift(art: Art, pc: PCSheet, input: String) -> Int { 0 }
  public func spurBonus(art: Art, pc: PCSheet, tier: Int) -> Int { 0 }
  public func haltungDelta(_ d: Int, art: Art, pc: PCSheet) -> Int { d }
  public func progress(onThreadSolved pc: PCSheet, art: Art?) -> PCSheet { pc }
}

/// Kampf / Sozial / Wissen (-1...+2) plus free-text talents. A talent adds +1 when it matches the action (word overlap with the player input).
public struct DreiSaeulen: Regelwerk {
  public init() {}
  public let id = "saeulen", titel = "Drei Säulen"
  /// +1 when any talent shares a content word (lemma) with the input - deterministic, no model involved
  public static func talentBonus(_ pc: PCSheet, input: String) -> Int {
    let words = Set(contentWords(input).map(lemma))
    return pc.talente.contains { !Set(contentWords($0).map(lemma)).isDisjoint(with: words) } ? 1 : 0
  }
  public func oddsShift(art: Art, pc: PCSheet, input: String) -> Int { pc.wert(art) + Self.talentBonus(pc, input: input) }
  public func spurBonus(art: Art, pc: PCSheet, tier: Int) -> Int {
    switch art {
    case .wissen: return 1 + max(0, pc.wissen)                 // knowledge speeds up the track
    case .sozial: return tier == 0 && pc.sozial >= 1 ? 1 : 0    // social skill speeds up tier 1 (Andeutung)
    default: return 0
    }
  }
  public func haltungDelta(_ d: Int, art: Art, pc: PCSheet) -> Int {
    guard d != 0, art == .sozial, pc.sozial >= 1 else { return d }
    return max(-2, min(2, d + (d > 0 ? 1 : -1)))
  }
  public func progress(onThreadSolved pc: PCSheet, art: Art?) -> PCSheet {
    var p = pc
    let a = art.flatMap { $0 == .sonst ? nil : $0 } ?? [Art.kampf, .sozial, .wissen].min { p.wert($0) < p.wert($1) }!    // the art used, else the weakest pillar
    p.setWert(a, p.wert(a) + 1); return p
  }
}

public func regelwerk(_ id: String) -> Regelwerk { id == "saeulen" ? DreiSaeulen() : Frei() }
/// oracle shift = NPC-attitude shift + rules shift, clamped to the engine's range
public func combinedShift(haltung: Int?, regel: Int) -> Int? {
  let t = (haltung ?? 0) + regel; return haltung == nil && regel == 0 ? nil : max(-2, min(2, t))
}
/// fallback classifier for actions that did not go through the model gate (/frage): keywords only
public func classifyArt(_ t: String) -> Art {
  let s = t.lowercased()
  if ["kämpf", "angriff", "greif", "schlag", "töte", "verletz", "besiegt", "treffe", "schieß", "klinge", "ausweich"].contains(where: s.contains) { return .kampf }
  if ["überred", "überzeug", "lügt", "belüg", "verhandel", "vertraut", "hilft", "bestech", "einschücht", "freundlich", "bitte"].contains(where: s.contains) { return .sozial }
  if ["weiß", "kennt", "wissen", "erkennt", "versteht", "entziffer", "untersuch", "bedeutet", "erinner", "lesen", "recherch"].contains(where: s.contains) { return .wissen }
  return .sonst
}

