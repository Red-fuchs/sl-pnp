import Foundation

/// Schicksalsschlag rules v0.1 (notes/RULES-schicksalsschlag.md): d100 roll-under with degrees, word-budget characters, Schicksalspunkte, Wunden.
public struct Trait: Codable, Equatable {
  public var text: String, major: Bool, pos: Bool
  public init(text: String, major: Bool, pos: Bool) { self.text = text; self.major = major; self.pos = pos }
  public var cost: Int { major ? 4 : 2 }
  /// check modifier when it fits the action
  public var bonus: Int { (major ? 20 : 10) * (pos ? 1 : -1) }
  public var json: [String: Any] { ["text": text, "kind": major ? "major" : "minor", "pos": pos] }
}

public struct Check: Codable, Equatable {
  public var speaker = "", pillar = "", reason = ""
  public var target = 0, roll = 0
  public var success = false, dos = 0, dof = 0
  public var crit: String?
  public var spLeft = 0
  public var source = "sl"
  public init() {}
  public var json: [String: Any] { ["speaker": speaker, "pillar": pillar, "reason": reason, "target": target, "roll": roll, "success": success, "dos": dos, "dof": dof, "crit": crit as Any? ?? NSNull(), "sp_left": spLeft, "source": source] }
  /// hard fact for the narrator
  public var fact: String {
    let what = pillar.isEmpty ? reason : (reason.isEmpty ? "Probe \(pillar.capitalized)" : "Probe \(pillar.capitalized) (\(reason))")
    var s = "[Fakt] \(speaker.isEmpty ? "" : speaker + ": ")\(what): Ziel \(target), Wurf \(roll) – "
    s += success ? "Erfolg, \(dos) Grad\(dos == 1 ? "" : "e")" : "Misserfolg, \(dof) Grad\(dof == 1 ? "" : "e")"
    if crit == "success" { s += ", KRITISCHER ERFOLG: eine Wendung zu Gunsten der Figur" }
    if crit == "failure" { s += ", KRITISCHER MISSERFOLG: eine Komplikation" }
    return s + ". Erzähle genau dieses Ergebnis" + (success ? (dos >= 3 ? " (glänzend)." : " (knapp bis solide).") : (dof >= 3 ? " (deutlich gescheitert)." : " (knapp gescheitert)."))
  }
}

public struct Pc: Codable, Equatable {
  public var speaker = "", name = "", hintergrund = ""
  public var pillars: [String: Int] = ["kampf": 40, "sozial": 40, "wissen": 40]
  public var traits: [Trait] = []
  public var sp = 5, spMax = 5
  public var wunden = 10, wundenMax = 10
  public var inventar: [String] = []
  public var taler = 0
  public var pendingSp = 0          // pre-spent: +10 each on the next check (max 3)
  public var pendingOracle = 0      // steps for the next oracle odds
  public var mod = 0                // +-10 steps put on this character by others (applies to the next check)
  public var lastCheck: Check?
  public init(speaker: String, name: String? = nil) { self.speaker = speaker; self.name = name ?? speaker }
  public var json: [String: Any] { ["name": name, "speaker": speaker, "pillars": pillars, "traits": traits.map(\.json), "sp": sp, "spMax": spMax, "wunden": wunden, "inventar": inventar, "taler": taler] }
  public var line: String { "\(name) (Kampf \(pillars["kampf"] ?? 0) · Sozial \(pillars["sozial"] ?? 0) · Wissen \(pillars["wissen"] ?? 0); SP \(sp)/\(spMax); Wunden \(wunden)/\(wundenMax)\(traits.isEmpty ? "" : "; " + traits.map { ($0.pos ? "+" : "−") + $0.text }.joined(separator: ", ")))" }
}

public enum SR {
  /// DoS/DoF + crits from target and roll (01-05 always success, 96-100 always failure, doubles crit)
  public static func degrees(target: Int, roll: Int) -> (success: Bool, dos: Int, dof: Int, crit: String?) {
    let success = roll <= 5 ? true : (roll >= 96 ? false : roll <= target)
    let dos = success ? 1 + max(0, target - roll) / 10 : 0
    let dof = success ? 0 : 1 + max(0, roll - target) / 10
    let double = roll == 100 || (roll >= 11 && roll <= 99 && roll % 11 == 0)
    return (success, dos, dof, double ? (success ? "success" : "failure") : nil)
  }
  /// SP <= 1: -10, SP 0: -20; Wunden <= 3: -10
  public static func penalty(_ pc: Pc) -> Int { (pc.sp == 0 ? -20 : (pc.sp <= 1 ? -10 : 0)) + (pc.wunden <= 3 ? -10 : 0) }
  public static func fitting(_ text: String, _ traits: [Trait]) -> [Trait] {
    let w = Set(contentWords(text).map(lemma))
    return traits.filter { t in !Set(contentWords(t.text).map(lemma)).isDisjoint(with: w) }
  }
  public static func target(_ pc: Pc, pillar: String, fit: [Trait], difficulty: Int, spBonus: Int = 0) -> Int {
    (pc.pillars[pillar] ?? 40) + fit.reduce(0) { $0 + $1.bonus } + difficulty + penalty(pc) + spBonus + pc.mod
  }
  /// d: 1...100
  public static func check(_ pc: inout Pc, pillar: String, traits: [Trait], difficulty: Int, spUse: Int, reason: String, d100: Int, source: String = "sl") -> Check {
    let use = max(0, min(3, spUse + pc.pendingSp, pc.sp)) , mod = pc.mod
    _ = mod
    pc.sp -= use; pc.pendingSp = 0
    let t = target(pc, pillar: pillar, fit: traits, difficulty: difficulty, spBonus: 10 * use)
    pc.mod = 0
    var c = Check(); c.speaker = pc.name; c.pillar = pillar; c.reason = reason; c.target = t; c.roll = d100; c.source = source
    (c.success, c.dos, c.dof, c.crit) = degrees(target: t, roll: d100)
    c.spLeft = pc.sp; pc.lastCheck = c
    return c
  }
  // MARK: character creation
  public static func budgetLeft(_ traits: [Trait]) -> Int { 20 - traits.filter(\.pos).reduce(0) { $0 + $1.cost } + traits.filter { !$0.pos }.reduce(0) { $0 + $1.cost } }
  /// drop the last positive traits until the budget is not overdrawn
  public static func fit(_ traits: [Trait]) -> [Trait] {
    var t = traits
    while budgetLeft(t) < 0, let i = t.lastIndex(where: \.pos) { t.remove(at: i) }
    return t
  }
  /// leftover budget -> Taler (1 pt = 10), items (2 pts each), +1 max SP (3 pts each); unspent points become Taler. nil = overdrawn.
  public static func allocate(left: Int, talerPts: Int, items: [String], sp: Int) -> (taler: Int, items: [String], sp: Int)? {
    guard left >= 0, talerPts >= 0, sp >= 0 else { return nil }
    let used = talerPts + 2 * items.count + 3 * sp
    if used > left { return nil }
    return ((talerPts + left - used) * 10, items, sp)
  }
  /// "Merkmal: text | major" / "Schwäche: text | minor" lines -> traits (harmful words dropped, "-" = none)
  public static func parseTraits(_ txt: String, pos: Bool) -> [Trait] {
    txt.split(separator: "\n").compactMap { l -> Trait? in
      guard let c = l.firstIndex(of: ":") else { return nil }
      let f = l[l.index(after: c)...].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
      guard f.count == 2, !f[0].isEmpty, f[0] != "-" else { return nil }
      let t = clean(f[0], 40); if minorHarm(t) { return nil }
      return Trait(text: t, major: f[1] == "major", pos: pos)
    }
  }
  /// the extraction sometimes lists a flaw as a skill or twice ("Schulden bei X" / "Schuld bei X"): a trait that shares a content word with an earlier one or with any flaw is dropped (flaws win)
  public static func dedupe(_ traits: [Trait]) -> [Trait] {
    func words(_ t: Trait) -> Set<String> { Set(contentWords(t.text).map(lemma)) }
    var out: [Trait] = []
    for t in traits.filter({ !$0.pos }) + traits.filter(\.pos) {
      let w = words(t)
      if w.isEmpty || !out.contains(where: { !words($0).isDisjoint(with: w) }) { out.append(t) }
    }
    return traits.filter { out.contains($0) }
  }
  /// check reason for cards: cut at a word boundary, never mid-word
  public static func shortReason(_ s: String, _ n: Int = 60) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines); if t.count <= n { return t }
    var c = String(t.prefix(n)); if let sp = c.lastIndex(of: " ") { c = String(c[..<sp]) }
    return c.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-")) + " …"
  }
  /// traits fitted to the budget, pillars, leftover as Taler; returns the dropped traits
  public static func build(_ pc: inout Pc, name: String, story: String, traits: [Trait]) -> [Trait] {
    let fit = SR.fit(traits)
    if !name.isEmpty { pc.name = name }
    pc.hintergrund = clean(story, 400); pc.traits = fit; pc.pillars = defaultPillars(story, fit)
    pc.taler = max(0, budgetLeft(fit)) * 10
    return traits.filter { !fit.contains($0) }
  }
  /// /budget taler=N item=A,B sp=N (only before the first check)
  public static func budget(_ pc: inout Pc, args: String) -> String {
    var tal = 0, items: [String] = [], sp = 0
    for kv in args.split(separator: " ") {
      let x = kv.split(separator: "=", maxSplits: 1).map(String.init)
      guard x.count == 2 else { return "/budget taler=N item=Name,Name sp=N  (Taler: 1 Punkt = 10, Gegenstand 2, +1 SP-Max 3)" }
      switch x[0].lowercased() {
      case "taler": tal = Int(x[1]) ?? -1
      case "item", "gegenstand": items += x[1].split(separator: ",").map { clean(String($0), 30) }.filter { !$0.isEmpty }
      case "sp": sp = Int(x[1]) ?? -1
      default: return "/budget: unbekannt '\(x[0])'"
      }
    }
    if pc.lastCheck != nil { return "/budget geht nur vor der ersten Probe." }
    let left = budgetLeft(pc.traits)
    guard let r = allocate(left: left, talerPts: tal, items: items, sp: sp) else { return "/budget: nur \(left) Punkte übrig (Taler 1, Gegenstand 2, +1 SP-Max 3)" }
    pc.taler = r.taler; pc.inventar = r.items; pc.spMax = 5 + r.sp; pc.sp = pc.spMax
    return "Budget: \(r.taler) Taler · \(r.items.isEmpty ? "keine Gegenstände" : r.items.joined(separator: ", ")) · SP-Max \(pc.spMax) (übrige Punkte als Taler)"
  }
  static let kw: [String: [String]] = [
    "kampf": ["kämpf", "krieg", "soldat", "söldner", "schwert", "bogen", "schütze", "jäger", "stark", "dolch", "wache", "ringer", "narbe", "gewalt", "schläger", "messer", "axt"],
    "sozial": ["charme", "händler", "redner", "überred", "lügner", "freund", "diplomat", "adel", "schauspiel", "trinkfest", "spielmann", "verführ", "bettler", "wirt", "kontakt", "zunge"],
    "wissen": ["gelehrt", "heiler", "kräuter", "schreiber", "mönch", "bibliothek", "alchemist", "student", "belesen", "magie", "forscher", "navigat", "archiv", "kenntnis", "klug"]]
  /// 30/40/50 by the story (keyword score), ties keep kampf, sozial, wissen order
  public static func defaultPillars(_ story: String, _ traits: [Trait]) -> [String: Int] {
    let t = (story + " " + traits.filter(\.pos).map(\.text).joined(separator: " ")).lowercased()
    var score: [(String, Int)] = ["kampf", "sozial", "wissen"].map { k in (k, kw[k]!.filter { t.contains($0) }.count) }
    score.sort { $0.1 > $1.1 }
    return [score[0].0: 50, score[1].0: 40, score[2].0: 30]
  }
  public static func validPillars(_ p: [String: Int]) -> Bool { Set(p.keys) == ["kampf", "sozial", "wissen"] && p.values.sorted() == [30, 40, 50] }
  // MARK: combat
  public static func weaponDamage(_ text: String) -> Int {
    let t = text.lowercased()
    if ["pistole", "gewehr", "arkebuse", "büchse"].contains(where: t.contains) { return 4 }
    if ["schwert", "axt", "bogen", "armbrust", "säbel", "speer", "beil"].contains(where: t.contains) { return 3 }
    if ["messer", "dolch", "knüppel", "keule", "stock"].contains(where: t.contains) { return 2 }
    if ["faust", "fäuste", "tritt", "ohrfeige"].contains(where: t.contains) { return 1 }
    return 2
  }
  public static func armour(role: String) -> Int {
    let r = role.lowercased()
    if ["ritter", "plattenpanzer"].contains(where: r.contains) { return 3 }
    if ["hauptmann", "söldner", "wache", "krieger", "soldat", "waffenmeister"].contains(where: r.contains) { return 2 }
    if ["jäger", "räuber", "schmuggler", "leder"].contains(where: r.contains) { return 1 }
    return 0
  }
}
