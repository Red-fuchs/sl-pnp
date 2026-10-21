import Foundation

/// Schicksalsschlag rules v0.1 (notes/RULES-schicksalsschlag.md): d100 roll-under with degrees, word-budget characters, Schicksalspunkte, LP (Lebenspunkte; code name wunden).
public struct Trait: Codable, Equatable {
  public var text: String, major: Bool, pos: Bool
  /// kampf|sozial|wissen; nil = fits every pillar. Optional so older saves still decode.
  public var pillar: String?
  public init(text: String, major: Bool, pos: Bool, pillar: String? = nil) { self.text = text; self.major = major; self.pos = pos; self.pillar = pillar }
  public static let pillarWords: [(String, [String])] = [
    ("kampf", ["armbrust", "bogen", "schwert", "klinge", "dolch", "messer", "axt", "speer", "lanze", "schleuder", "schütz", "kämpf", "krieg", "söldner", "soldat", "ritter", "faust", "fäuste", "ringen", "ringer", "zäh", "wache", "wächter", "waffe", "schild", "rüstung", "athlet", "jäger", "jagd", "streiter", "gewalt", "verwundet"]),
    ("sozial", ["überred", "lüg", "lügen", "handel", "händler", "feilsch", "charme", "charism", "gefallen", "kontakt", "freund", "redegewandt", "diplomat", "verführ", "schmeich", "einschücht", "tratsch", "ansehen", "gastfreund", "schüchtern", "misstrau", "schulden", "schuld bei"]),
    ("wissen", ["lesen", "schreib", "kräuter", "heilk", "heiler", "heilung", "heilen", "pfad", "spur", "fährte", "gelehrt", "karte", " wissen", "gebildet", "bibliothek", "alchem", "magie", "arzt", "medizin", "sprache", "navigat", "orient", "schrift", "forsch", "studier", "sternen", "geschichte", "aberglaub"]),
  ]
  /// deterministic keyword classifier: most keyword hits win, a tie or no hit = nil
  public static func classify(_ text: String) -> String? {
    let t = " " + text.lowercased() + " "
    let sc = pillarWords.map { ($0.0, $0.1.filter { t.contains($0) }.count) }
    guard let top = sc.map(\.1).max(), top > 0, sc.filter({ $0.1 == top }).count == 1 else { return nil }
    return sc.first { $0.1 == top }?.0
  }
  public var cost: Int { major ? 4 : 2 }
  /// check modifier when it fits the action
  public var bonus: Int { (major ? 20 : 10) * (pos ? 1 : -1) }
  /// Fremdkraft (setting "Die Weberin"): one supernatural home-world ability, written as "Fremdkraft: Feuerhand". Always a positive major trait; every check that uses it raises the tension by 1.
  public var fremd: Bool { pos && text.lowercased().hasPrefix("fremdkraft") }
  public var json: [String: Any] { ["text": text, "kind": major ? "major" : "minor", "pos": pos, "fremd": fremd, "pillar": pillar as Any? ?? NSNull()] }
}

public struct Check: Codable, Equatable {
  public var speaker = "", pillar = "", reason = ""
  public var target = 0, roll = 0
  public var success = false, dos = 0, dof = 0
  public var crit: String?
  public var spLeft = 0
  public var source = "sl"
  /// Schicksalsergeben: -10 before the roll; >= 2 DoS gives 1 SP back, a failure gets 1 DoF more (Schicksalsschlag). Stored optional so older saves still decode.
  var _ergeben: Bool?, _spGained: Int?
  public var ergeben: Bool { get { _ergeben ?? false } set { _ergeben = newValue } }
  public var spGained: Int { get { _spGained ?? 0 } set { _spGained = newValue } }
  /// set when the check was refused (nothing rolled, nothing changed); errCode = HTTP status (400/409)
  public var error: String?
  public var errCode = 0
  public init() {}
  public var json: [String: Any] { ["speaker": speaker, "pillar": pillar, "reason": reason, "target": target, "roll": roll, "success": success, "dos": dos, "dof": dof, "crit": crit as Any? ?? NSNull(), "sp_left": spLeft, "source": source, "ergeben": ergeben, "sp_gained": spGained] }
  /// hard fact for the narrator
  public var fact: String {
    let what = pillar.isEmpty ? reason : (reason.isEmpty ? "Probe \(pillar.capitalized)" : "Probe \(pillar.capitalized) (\(reason))")
    var s = "[Fakt] \(speaker.isEmpty ? "" : speaker + ": ")\(what): Ziel \(target), Wurf \(roll) – "
    s += success ? "Erfolg, \(dos) Grad\(dos == 1 ? "" : "e")" : "Misserfolg, \(dof) Grad\(dof == 1 ? "" : "e")"
    if ergeben { s += success ? " [schicksalsergeben (−10)\(spGained > 0 ? ", 1 SP zurück" : "")]" : " [schicksalsergeben (−10): Schicksalsschlag, der Misserfolg wiegt einen Grad schwerer und wird härter erzählt]" }
    if crit == "success" { s += ", KRITISCHER ERFOLG: eine Wendung zu Gunsten der Figur" }
    if crit == "failure" { s += ", KRITISCHER MISSERFOLG: eine Komplikation" }
    return s + ". Erzähle genau dieses Ergebnis" + (success ? (dos >= 3 ? " (glänzend)." : " (knapp bis solide).") : (dof >= 3 ? " (deutlich gescheitert)." : " (knapp gescheitert)."))
  }
}

/// A bought item that matches the character's background story (★). The hidden "Gegenstandsgeheimnis" is rolled on purchase:
/// `levelbar` grows +1 per solved thread (max 3); a Wendung lives in hidden.json (key "★<name>") and is revealed through the Spur system.
public struct StoryItem: Codable, Equatable {
  public var name: String, kind: String = "werkzeug"   // "waffe" | "werkzeug" | "ruestung"
  public var level = 0, levelbar = false, rolled = false
  public var truth: String?                           // set once the Wendung is revealed
  public init(name: String, kind: String = "werkzeug") { self.name = name; self.kind = kind }
  public var json: [String: Any] { ["name": name, "level": level] }
}

public struct Pc: Codable, Equatable {
  public var speaker = "", name = "", hintergrund = ""
  public var pillars: [String: Int] = ["kampf": 40, "sozial": 40, "wissen": 40]
  public var traits: [Trait] = []
  public var sp = 5, spMax = 5
  public var wunden = 10, wundenMax = 10
  public var inventar: [String] = []
  public var taler = 0 { didSet { _heller = nil } }   // whole Taler; any direct write resets the finer Heller balance
  var _heller: Int?                                     // purse in Heller (optional: older saves only have `taler`)
  /// purse in Heller (1 Taler = 2 Schilling = 4 Heller); older saves derive it from `taler`
  public var heller: Int { get { _heller ?? taler * 4 } set { let h = max(0, newValue); taler = h / 4; _heller = h } }
  public var geld: String { Geld.fmt(heller) }
  public var pendingSp = 0          // pre-spent: +10 each on the next check (max 3)
  public var pendingOracle = 0      // steps for the next oracle odds
  public var mod = 0                // +-10 steps put on this character by others (applies to the next check)
  var _ergebenUsed: Bool?           // Schicksalsergeben already used in this scene (optional: older saves)
  public var ergebenUsed: Bool { get { _ergebenUsed ?? false } set { _ergebenUsed = newValue } }
  var _items: [StoryItem]?
  public var items: [StoryItem] { get { _items ?? [] } set { _items = newValue.isEmpty ? nil : newValue } }
  public var lastCheck: Check?
  public init(speaker: String, name: String? = nil) { self.speaker = speaker; self.name = name ?? speaker }
  public var json: [String: Any] { ["name": name, "speaker": speaker, "pillars": pillars, "traits": traits.map(\.json), "sp": sp, "spMax": spMax, "wunden": wunden, "lp": wunden, "lpMax": wundenMax, "inventar": inventar, "taler": taler, "heller": heller, "geld": geld, "items": items.map(\.json)] }
  public var line: String { "\(name) (Kampf \(pillars["kampf"] ?? 0) · Sozial \(pillars["sozial"] ?? 0) · Wissen \(pillars["wissen"] ?? 0); SP \(sp)/\(spMax); LP \(wunden)/\(wundenMax)\(traits.isEmpty ? "" : "; " + traits.map { ($0.pos ? "+" : "−") + $0.text }.joined(separator: ", ")))" }
}

/// Currency: 1 Taler (T) = 2 Schilling (S) = 4 Heller (H); the engine counts in Heller.
public enum Geld {
  public static func fmt(_ h: Int) -> String {
    let h = max(0, h), t = h / 4, s = (h % 4) / 2, r = h % 2
    let parts = [(t, "T"), (s, "S"), (r, "H")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
    return parts.isEmpty ? "0 H" : parts.joined(separator: " ")
  }
  /// "40" (Taler), "1S", "2H", "1T 1S", "3T1S1H"; no sign. nil = not an amount.
  public static func parse(_ s: String) -> Int? {
    let t = s.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return nil }
    guard t.range(of: #"^(\d+\s*[tTsShH]?\s*)+$"#, options: .regularExpression) != nil else { return nil }
    var sum = 0
    let re = try! NSRegularExpression(pattern: #"(\d+)\s*([tTsShH]?)"#)
    for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
      guard let n = Int((t as NSString).substring(with: m.range(at: 1))), n < 1_000_000 else { return nil }
      switch (t as NSString).substring(with: m.range(at: 2)).lowercased() { case "s": sum += n * 2; case "h": sum += n; default: sum += n * 4 }
    }
    return sum
  }
  /// "Seil 1S" / "Eisenschwert 3 T 1 S" -> (ware, preis text); the price is the trailing amount
  public static func wareUndPreis(_ s: String) -> (ware: String, preis: String)? {
    let re = try! NSRegularExpression(pattern: #"^(.+?)\s+((?:\d+\s*[tTsShH]?\s*)+)$"#)
    guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return ((s as NSString).substring(with: m.range(at: 1)), (s as NSString).substring(with: m.range(at: 2)))
  }
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
  /// SP <= 1: -10, SP 0: -20; LP <= 3: -10
  public static func penalty(_ pc: Pc) -> Int { (pc.sp == 0 ? -20 : (pc.sp <= 1 ? -10 : 0)) + (pc.wunden <= 3 ? -10 : 0) }
  public static func fitting(_ text: String, _ traits: [Trait]) -> [Trait] {
    let w = Set(contentWords(text).map(lemma))
    return traits.filter { t in !Set(contentWords(t.text).map(lemma)).isDisjoint(with: w) }
  }
  /// the Fremdkraft among the traits that fit a check (nil = none used)
  public static func fremdUsed(_ fit: [Trait]) -> Trait? { fit.first(where: \.fremd) }
  public static func target(_ pc: Pc, pillar: String, fit: [Trait], difficulty: Int, spBonus: Int = 0) -> Int {
    (pc.pillars[pillar] ?? 40) + fit.reduce(0) { $0 + $1.bonus } + difficulty + penalty(pc) + spBonus + pc.mod
  }
  /// Schicksalsergeben refusals (nil = allowed): 400 = not combinable / leicht / used, 409 = pending SP or mod on the sheet
  public static func ergebenRefusal(_ pc: Pc, difficulty: Int, spUse: Int) -> (code: Int, msg: String)? {
    if spUse > 0 { return (400, "Schicksalsergeben ist nicht kombinierbar mit Schicksalspunkten auf derselben Probe.") }
    if pc.pendingSp > 0 { return (409, "Schicksalsergeben ist nicht kombinierbar mit vorab eingesetzten Schicksalspunkten.") }
    if pc.mod != 0 { return (409, "Schicksalsergeben ist nicht kombinierbar mit Schicksalspunkten anderer auf dieser Probe.") }
    if difficulty > 0 { return (400, "Schicksalsergeben gibt es nicht bei leichten Proben.") }
    if pc.ergebenUsed { return (400, "Schicksalsergeben ist in dieser Szene schon verbraucht (einmal pro Szene und Figur).") }
    return nil
  }
  /// after the degrees: failure +1 DoF, success with >= 2 DoS +1 SP (capped at max). Voids a gain of an earlier result (Neuwurf: the second result counts).
  public static func settleErgeben(_ pc: inout Pc, _ c: inout Check) {
    guard c.ergeben else { return }
    if c.spGained > 0 { pc.sp = max(0, pc.sp - c.spGained); c.spGained = 0 }
    if !c.success { c.dof += 1 }
    else if c.dos >= 2 { let n = max(0, min(pc.spMax, pc.sp + 1) - pc.sp); pc.sp += n; c.spGained = n }
    c.spLeft = pc.sp
  }
  /// scene change: Schicksalsergeben is available again
  public static func resetScene(_ pcs: inout [Pc]) { for i in pcs.indices { pcs[i].ergebenUsed = false } }
  public static let ergebenMod = -10
  /// backstory length that reaches the trait extraction and the story-item matcher
  public static let storyMax = 900
  /// tag-like prefixes in free player text lose their colon ("Merkmal: x" -> "Merkmal x"), so the story cannot fake extraction lines or harness tags
  public static func defuse(_ s: String) -> String {
    s.replacingOccurrences(of: #"(?i)\b(Regie|Fakt|System|Systemhinweis|Anweisung|Merkmal|Schwäche|Gegenstand|Urteil|Fairness|Tausch|Preis|Orakel|Antwort|Ausgabe|Grund|Spielleiter|Assistant|User|Welt|Spieler)\s*:"#, with: "$1 ", options: .regularExpression).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
  }
  /// d: 1...100
  public static func check(_ pc: inout Pc, pillar: String, traits: [Trait], difficulty: Int, spUse: Int, reason: String, d100: Int, source: String = "sl", ergeben: Bool = false) -> Check {
    if ergeben, let r = ergebenRefusal(pc, difficulty: difficulty, spUse: spUse) {
      var c = Check(); c.speaker = pc.name; c.pillar = pillar; c.reason = reason; c.source = source; c.ergeben = true; c.error = r.msg; c.errCode = r.code; c.spLeft = pc.sp
      return c
    }
    let use = max(0, min(3, spUse + pc.pendingSp, pc.sp)) , mod = pc.mod
    _ = mod
    pc.sp -= use; pc.pendingSp = 0
    let t = target(pc, pillar: pillar, fit: traits, difficulty: difficulty, spBonus: 10 * use) + (ergeben ? ergebenMod : 0)   // own labelled modifier, not via difficulty
    pc.mod = 0
    var c = Check(); c.speaker = pc.name; c.pillar = pillar; c.reason = reason; c.target = t; c.roll = d100; c.source = source
    (c.success, c.dos, c.dof, c.crit) = degrees(target: t, roll: d100)
    c.ergeben = ergeben
    if ergeben { pc.ergebenUsed = true; settleErgeben(&pc, &c) }
    c.spLeft = pc.sp; pc.lastCheck = c
    return c
  }
  /// Neuwurf: 2 SP rerolls the last check against the same target, the second result counts (ergeben effects re-settled). Once per check. Returns the new check or a German refusal.
  public static func reroll(_ pc: inout Pc, d100 r: Int) -> (Check?, String?) {
    guard var last = pc.lastCheck else { return (nil, "Neuwurf braucht 2 SP und eine vorherige Probe") }
    if last.reason.hasSuffix("(Neuwurf)") { return (nil, "Nur ein Neuwurf pro Probe.") }
    guard pc.sp >= 2 else { return (nil, "Neuwurf braucht 2 SP und eine vorherige Probe") }
    pc.sp -= 2; last.roll = r; (last.success, last.dos, last.dof, last.crit) = degrees(target: last.target, roll: r)
    settleErgeben(&pc, &last); last.spLeft = pc.sp; last.reason += " (Neuwurf)"; last.source = "neuwurf"; pc.lastCheck = last
    return (last, nil)
  }
  // MARK: character creation
  public static func budgetLeft(_ traits: [Trait]) -> Int { 20 - traits.filter(\.pos).reduce(0) { $0 + $1.cost } + traits.filter { !$0.pos }.reduce(0) { $0 + $1.cost } }
  /// drop the last positive traits until the budget is not overdrawn
  public static func fit(_ traits: [Trait]) -> [Trait] {
    var t = traits
    while budgetLeft(t) < 0, let i = t.lastIndex(where: \.pos) { t.remove(at: i) }
    return t
  }
  // MARK: gear prices (Vorschlag): normal 2, sword/axe/bow/chain/shield 4, plate/firearm 6
  static let tier6 = ["platten", "vollplatte", "harnisch", "pistole", "gewehr", "arkebuse", "büchse", "muskete", "revolver", "feuerwaffe"]
  static let tier2 = ["leder", "messer", "dolch", "knüppel", "keule", "stock"]
  static let tier4 = ["schwert", "axt", "beil", "bogen", "armbrust", "speer", "säbel", "degen", "morgenstern", "kriegshammer", "streitkolben", "ketten", "schuppen", "schild", "rüstung", "panzer"]
  /// 2, 4 or 6 points by keyword; unknown items count as normal
  public static func itemCost(_ item: String) -> Int {
    let t = item.lowercased()
    if tier6.contains(where: t.contains) { return 6 }
    if tier2.contains(where: t.contains) { return 2 }
    return tier4.contains(where: t.contains) ? 4 : 2
  }
  public static func tierLabel(_ item: String) -> String { ["", "", "normal", "", "stark", "", "schwer"][itemCost(item)] }
  /// armour value of a piece of gear (cloth 0, leather 1, mail 2, plate 3)
  public static func gearArmour(_ item: String) -> Int {
    let t = item.lowercased()
    if tier6.prefix(3).contains(where: t.contains) { return 3 }
    if t.contains("leder") { return 1 }
    if ["ketten", "schuppen", "rüstung", "panzer"].contains(where: t.contains) { return 2 }
    return 0
  }
  public static func armour(of pc: Pc) -> Int { pc.inventar.map(gearArmour).max() ?? 0 }
  static func itemKind(_ item: String) -> String {
    gearArmour(item) > 0 ? "ruestung" : (["schwert", "axt", "beil", "bogen", "armbrust", "speer", "säbel", "degen", "morgenstern", "hammer", "streitkolben", "messer", "dolch", "keule", "knüppel", "pistole", "gewehr"].contains(where: item.lowercased().contains) ? "waffe" : "werkzeug")
  }
  /// an item is story-consistent when it shares a content word with the background story or a positive trait (same lemma matcher as the traits)
  public static func storyMatch(_ item: String, pc: Pc) -> Bool {
    let src = Set(contentWords(pc.hintergrund + " " + pc.traits.filter(\.pos).map(\.text).joined(separator: " ")).map(lemma))
    return !Set(contentWords(item).map(lemma)).isDisjoint(with: src)
  }
  /// situational bonus of the speaker's story items that the text mentions: weapons +level damage, tools +10 per level on the check
  public static func itemBonus(_ pc: Pc, text: String) -> (dmg: Int, check: Int) {
    let w = Set(contentWords(text).map(lemma)); var d = 0, c = 0
    for it in pc.items where it.level > 0 && !Set(contentWords(it.name).map(lemma)).isDisjoint(with: w) {
      if it.kind == "waffe" { d += min(it.level, levelCap(it)) } else if it.kind == "werkzeug" { c += 10 * it.level }
    }
    return (d, c)
  }
  /// max level of a story item: +3, and base + level stays within the item caps (weapon damage 5, armour 3; RULES-gegenstaende.md)
  public static func levelCap(_ it: StoryItem) -> Int {
    switch it.kind { case "waffe": return max(0, min(3, 5 - weaponDamage(it.name))); case "ruestung": return max(0, min(3, 3 - gearArmour(it.name))); default: return 3 }
  }
  /// a thread was solved: every levelbar story item grows +1 (max 3, capped by levelCap). Returns the names that grew.
  public static func levelUp(_ pcs: inout [Pc]) -> [String] {
    var g: [String] = []
    for i in pcs.indices { var its = pcs[i].items; for k in its.indices where its[k].levelbar && its[k].level < levelCap(its[k]) { its[k].level += 1; g.append("\(its[k].name) +\(its[k].level)") }; pcs[i].items = its }
    return g
  }
  /// Gegenstandsgeheimnis from a d6: 1-2 nothing, 3-4 levelbar, 5 Wendung, 6 both. Returns the Wendung text (item name never inside: the leak guard must not ban the visible name).
  public static let wendungen = ["Das Stück ist eine plumpe Fälschung: der Glanz bröckelt, sobald jemand genau hinsieht.", "Das Stück wurde gestohlen: sein rechtmäßiger Besitzer sucht es noch.", "Auf dem Stück liegt ein Fluch, der Blut fordert, aber in höchster Not Kraft schenkt.", "Das Stück gehörte einst einem berühmten Ritter, den einige noch fürchten."]
  public static func rollSecret(_ item: inout StoryItem, d6: Int, pick: Int) -> String? {
    item.rolled = true; item.levelbar = d6 == 3 || d6 == 4 || d6 == 6
    return d6 >= 5 ? wendungen[((pick % wendungen.count) + wendungen.count) % wendungen.count] : nil
  }
  /// leftover budget -> Taler (1 pt = 10), items (2/4/6 pts by tier), +1 max SP (3 pts each); unspent points become Taler. nil = overdrawn.
  public static func allocate(left: Int, talerPts: Int, items: [String], sp: Int) -> (taler: Int, items: [String], sp: Int)? {
    guard left >= 0, talerPts >= 0, sp >= 0 else { return nil }
    let used = talerPts + items.reduce(0) { $0 + itemCost($1) } + 3 * sp
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
      return Trait(text: t, major: f[1] == "major" || (pos && t.lowercased().hasPrefix("fremdkraft")), pos: pos, pillar: Trait.classify(t))
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
  /// /merkmal +Text [major] | /merkmal -Text [major] (flaw) | /merkmal x Text (remove): fix the extraction by hand, before the first check.
  /// Re-fits the budget and resets the leftover to Taler (a /budget has to be repeated).
  public static func editTrait(_ pc: inout Pc, args: String) -> String {
    let usage = "/merkmal +Stärke [major] [kampf|sozial|wissen] | /merkmal -Schwäche [major] | /merkmal x Text (streichen)"
    if pc.lastCheck != nil { return "/merkmal geht nur vor der ersten Probe." }
    var a = args.trimmingCharacters(in: .whitespaces); guard let f = a.first else { return usage }
    if f == "x" || f == "X" {
      a = String(a.dropFirst()).trimmingCharacters(in: .whitespaces); let n = pc.traits.count
      pc.traits.removeAll { norm($0.text).contains(norm(a)) && !a.isEmpty }
      if pc.traits.count == n { return "/merkmal: kein Merkmal '\(a)'" }
    } else if f == "+" || f == "-" {
      a = String(a.dropFirst()).trimmingCharacters(in: .whitespaces)
      var major = false; if a.hasSuffix(" major") { major = true; a = String(a.dropLast(6)) }
      var pil: String?
      if let r = a.range(of: #"\s*\[(kampf|sozial|wissen)\]\s*$"#, options: [.regularExpression, .caseInsensitive]) { pil = a[r].trimmingCharacters(in: CharacterSet(charactersIn: " []")).lowercased(); a = String(a[..<r.lowerBound]) }
      if a.hasSuffix(" major") { major = true; a = String(a.dropLast(6)) }
      let txt = clean(a, 40); if txt.isEmpty || minorHarm(txt) { return usage }
      var t = Trait(text: txt, major: major, pos: f == "+", pillar: pil ?? Trait.classify(txt))
      if t.fremd { if pc.traits.contains(where: \.fremd) { return "/merkmal: nur eine Fremdkraft pro Figur (erst /merkmal x Fremdkraft)." }; t.major = true }
      pc.traits = dedupe(pc.traits + [t]); if !pc.traits.contains(t) { return "/merkmal: '\(txt)' gibt es schon (ähnliches Merkmal)." }
    } else { return usage }
    let all = pc.traits; pc.traits = fit(all)
    let dropped = all.filter { !pc.traits.contains($0) }
    pc.taler = max(0, budgetLeft(pc.traits)) * 10; pc.inventar = []; pc.items = []; pc.spMax = 5; pc.sp = 5
    return "Merkmale: " + (pc.traits.isEmpty ? "-" : pc.traits.map { ($0.pos ? "+" : "−") + $0.text + ($0.major ? " (major)" : "") }.joined(separator: ", ")) + " · Budget übrig \(budgetLeft(pc.traits)) · Taler \(pc.taler)" + (dropped.isEmpty ? "" : " · über dem Budget, gestrichen: " + dropped.map(\.text).joined(separator: ", "))
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
    pc.hintergrund = clean(story, storyMax); pc.traits = fit; pc.pillars = defaultPillars(story, fit)
    pc.taler = max(0, budgetLeft(fit)) * 10
    return traits.filter { !fit.contains($0) }
  }
  /// /budget taler=N item=A,B sp=N (only before the first check)
  public static func budget(_ pc: inout Pc, args: String) -> String {
    var tal = 0, items: [String] = [], sp = 0
    for kv in args.split(separator: " ") {
      let x = kv.split(separator: "=", maxSplits: 1).map(String.init)
      guard x.count == 2 else { return "/budget taler=N item=Name,Name sp=N  (Taler: 1 Punkt = 10, Gegenstand 2/4/6 je nach Stufe, +1 SP-Max 3)" }
      switch x[0].lowercased() {
      case "taler": tal = Int(x[1]) ?? -1
      case "item", "gegenstand": items += x[1].split(separator: ",").map { clean(String($0), 30) }.filter { !$0.isEmpty }
      case "sp": sp = Int(x[1]) ?? -1
      default: return "/budget: unbekannt '\(x[0])'"
      }
    }
    if pc.lastCheck != nil { return "/budget geht nur vor der ersten Probe." }
    let left = budgetLeft(pc.traits)
    guard let r = allocate(left: left, talerPts: tal, items: items, sp: sp) else { return "/budget: nur \(left) Punkte übrig (Taler 1, Gegenstand 2/4/6, +1 SP-Max 3)" }
    pc.taler = r.taler; pc.inventar = r.items; pc.spMax = 5 + r.sp; pc.sp = pc.spMax
    pc.items = r.items.filter { storyMatch($0, pc: pc) }.map { StoryItem(name: $0, kind: itemKind($0)) }
    let star = Set(pc.items.map(\.name))
    let itemTxt = r.items.map { "\($0) (\(itemCost($0)) Pkt = \(itemCost($0) * 10) Taler, \(tierLabel($0)))\(star.contains($0) ? " ★ Story-Item" : "")" }
    return "Budget: \(r.taler) Taler · \(r.items.isEmpty ? "keine Gegenstände" : itemTxt.joined(separator: ", ")) · SP-Max \(pc.spMax) (übrige Punkte als Taler)"
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

// MARK: GM purchase commands (/taler, /gegenstand, /kauf)
public extension SR {
  /// index of the party member named at the START of `a` (longest name first, then a space); returns the rest
  static func splitName(_ a: String, _ party: [Pc]) -> (i: Int, rest: String)? {
    let t = a.trimmingCharacters(in: .whitespaces)
    var best: (Int, Int)?
    for (i, p) in party.enumerated() { for n in [p.name, p.speaker] where !n.isEmpty {
      let l = norm(n); let tn = norm(t)
      if (tn == l || tn.hasPrefix(l + " ")), best == nil || l.count > best!.1 { best = (i, l.count) }
    } }
    guard let (i, len) = best else { return nil }
    return (i, String(t.dropFirst(len)).trimmingCharacters(in: .whitespaces))
  }
  static let taler_usage = "/taler <Name> ±N[T|S|H]  (z. B. /taler Mirne -40 · /taler Mirne +1S; ohne Einheit = Taler; 1 T = 2 S = 4 H)"
  static let gegenstand_usage = "/gegenstand <Name> +Text | -Text  (Gegenstand hinzufügen bzw. entfernen)"
  static let kauf_usage = "/kauf <Name> <Ware> <Preis>  (z. B. /kauf Mirne Seil 1S; Preis in T, S oder H)"
  /// /taler: nil error = ok. Returns (message, fact-less)
  static func taler(_ pc: inout Pc, delta: Int) -> String {
    let before = pc.heller
    if before + delta < 0 { return "Fehler: \(pc.name) hat nur \(pc.geld) und kann \(Geld.fmt(-delta)) nicht abgeben." }
    pc.heller = before + delta
    return "\(pc.name): \(delta >= 0 ? "+" : "−")\(Geld.fmt(abs(delta))) · Geld jetzt \(pc.geld)"
  }
  /// add or remove an inventory item (remove matches the exact name first, then a part of it); the ★ entry goes with it
  static func gegenstand(_ pc: inout Pc, add: String?, remove: String?) -> String {
    if let a = add {
      let t = clean(a, 60); if t.isEmpty { return "Fehler: Gegenstand fehlt. " + gegenstand_usage }
      if pc.inventar.count >= 40 { return "Fehler: \(pc.name) trägt schon 40 Gegenstände." }
      pc.inventar.append(t); return "\(pc.name) erhält: \(t)"
    }
    let r = norm(remove ?? ""); if r.isEmpty { return "Fehler: Gegenstand fehlt. " + gegenstand_usage }
    guard let i = pc.inventar.firstIndex(where: { norm($0) == r }) ?? pc.inventar.firstIndex(where: { norm($0).contains(r) }) else { return "Fehler: \(pc.name) hat keinen Gegenstand '\(remove ?? "")'." }
    let n = pc.inventar.remove(at: i); pc.items.removeAll { $0.name == n }
    return "\(pc.name) gibt ab: \(n)"
  }
  /// /kauf: pay and take in one step; refused (nothing changes) when the purse is too small
  static func kauf(_ pc: inout Pc, ware: String, preis: Int) -> (ok: Bool, msg: String) {
    let w = clean(ware, 60)
    if w.isEmpty { return (false, "Fehler: Ware fehlt. " + kauf_usage) }
    if preis <= 0 { return (false, "Fehler: Preis muss größer als 0 sein. " + kauf_usage) }
    if pc.heller < preis { return (false, "Fehler: \(pc.name) kann sich \(w) nicht leisten (Preis \(Geld.fmt(preis)), Geld \(pc.geld)). Nichts gebucht.") }
    if pc.inventar.count >= 40 { return (false, "Fehler: \(pc.name) trägt schon 40 Gegenstände. Nichts gebucht.") }
    pc.heller -= preis; pc.inventar.append(w)
    return (true, "Kauf: \(pc.name) zahlt \(Geld.fmt(preis)) für \(w) · Rest \(pc.geld)")
  }
}

public extension Game {
  /// shared by the slash commands and the HTTP endpoints; emits `sheet` (and for purchases a hard fact for the next narration)
  func applyTaler(_ i: Int, delta: Int) -> (ok: Bool, msg: String) {
    let m = partyStore.with { SR.taler(&$0[i], delta: delta) }; announceSheet(); return (!m.hasPrefix("Fehler"), m)
  }
  func applyGegenstand(_ i: Int, add: String?, remove: String?) -> (ok: Bool, msg: String) {
    let m = partyStore.with { SR.gegenstand(&$0[i], add: add, remove: remove) }; announceSheet(); return (!m.hasPrefix("Fehler"), m)
  }
  func applyKauf(_ i: Int, ware: String, preis: Int) -> (ok: Bool, msg: String) {
    let r = partyStore.with { SR.kauf(&$0[i], ware: ware, preis: preis) }
    if r.ok { let pc = partyStore.all[i]; queueFact("[Fakt] \(pc.name) kauft \(clean(ware, 60)) für \(Geld.fmt(preis)) und hat danach noch \(pc.geld). Erwähne den Kauf kurz."); announceSheet() }
    return r
  }
}
