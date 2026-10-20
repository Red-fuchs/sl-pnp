import Foundation
import Schicksal

// MARK: state

public struct GenSlots: Codable, Equatable {
  public var ton = "offen", epoche = "offen", ort = "offen", bedrohung = "offen", licht = "offen"
  public var muss: [String] = [], nicht: [String] = []
  public init() {}
  public static let keys = ["ton", "epoche", "ort", "bedrohung", "licht"]
  public static let enums: [String: [String]] = [
    "ton": ["düster", "rau", "melancholisch", "grimmig", "unheimlich", "bitter"],
    "epoche": ["mittelalterlich", "frühneuzeitlich", "antik", "barock", "zeitlos"],
    "ort": ["Dorf", "Hafenstadt", "Burg", "Wald", "Gebirge", "Sumpf", "Kloster", "Wüste", "Insel"],
    "bedrohung": ["Fluch", "Seuche", "Krieg", "Verschwörung", "Ungeheuer", "Hungersnot", "Sekte"],
    "licht": ["trüb", "hell", "blutrot", "neblig", "nächtlich"],
  ]
  public subscript(k: String) -> String {
    get { switch k { case "ton": return ton; case "epoche": return epoche; case "ort": return ort; case "bedrohung": return bedrohung; default: return licht } }
    set { switch k { case "ton": ton = newValue; case "epoche": epoche = newValue; case "ort": ort = newValue; case "bedrohung": bedrohung = newValue; default: licht = newValue } }
  }
  public var offen: [String] { Self.keys.filter { self[$0] == "offen" } }
  /// Hints that justify a player-set epoche / licht (the 4B parser kept answering "antik" / "hell" for everything).
  static let hints: [String: [String]] = [
    "antik": ["antik", "römer", "grie", "ägypt", "bronzezeit", "pharao"], "barock": ["barock", "rokoko", "absolut"],
    "frühneuzeitlich": ["frühneuzeit", "renaissance", "inquisition", "pirat", "hexenjagd", "reformation"],
    "mittelalterlich": ["mittelalter", "ritter", "burg", "kloster", "kreuzzug", "pest", "feudal", "fürst"], "zeitlos": ["zeitlos", "märchen"],
    "trüb": ["trüb", "grau", "regen", "düster", "dunst"], "hell": ["hell", "sonne", "licht", "sommer", "strahl"], "blutrot": ["blut", "rot", "glut"],
    "neblig": ["nebel", "dunst", "moor"], "nächtlich": ["nacht", "mond", "finster", "dunkel"],
  ]
  /// F3: epoche/licht only count when the player's text supports them, otherwise they stay open (and the oracle picks).
  public static func supported(_ v: String, text: String) -> Bool { let t = text.lowercased(); return (hints[v] ?? []).contains { t.contains($0) } }
  /// `ort` is free text (enum values are only hints): returns the place NAME the player asked for, if it is more than a bare type.
  public var ortName: String? { Self.enums["ort"]!.contains(ort) || ort == "offen" ? nil : ort }
  public mutating func set(_ k: String, _ v0: String) throws {
    let key = k.lowercased(), v = clean(v0, 60)
    if Self.keys.contains(key) {
      if key == "ort" { self.ort = v.isEmpty ? "offen" : v; return }
      guard Self.enums[key]!.contains(v) || v == "offen" else { throw GenError.msg("\(key): \(Self.enums[key]!.joined(separator: " | "))") }
      self[key] = v
    } else if key == "muss" { muss = v == "-" ? [] : v.split(separator: ",").map { clean(String($0), 40) } }
    else if key == "nicht" { nicht = v == "-" ? [] : v.split(separator: ",").map { clean(String($0), 40) } }
    else { throw GenError.msg("Slot unbekannt: \(k)") }
  }
  /// Slot parser output -> slots (with the epoche/licht sanity check).
  public static func parse(_ f: [String: String], text: String) -> GenSlots {
    var g = GenSlots()
    for k in keys { var v = f[k.capitalized] ?? "offen"; if k == "ort" { v = clean(v, 60); if v.isEmpty { v = "offen" } }
      if (k == "epoche" || k == "licht"), v != "offen", !supported(v, text: text) { v = "offen" }
      g[k] = v }
    let split = { (s: String?) -> [String] in (s ?? "-") == "-" ? [] : s!.split(separator: ",").map { clean(String($0), 40) }.filter { !$0.isEmpty } }
    g.muss = split(f["Muss"]); g.nicht = split(f["Nicht"])
    return g
  }
  /// every must-have (by 5-letter stem) has to appear in `text`; returns the first missing one
  public func missing(in text: String) -> String? { let t = text.lowercased(); return muss.first { !t.contains(String($0.lowercased().prefix(5))) } }
  public var table: String {
    (Self.keys.map { "\($0.capitalized): \(self[$0])" } + ["Muss vorkommen: \(muss.isEmpty ? "-" : muss.joined(separator: ", "))", "Darf nicht vorkommen: \(nicht.isEmpty ? "-" : nicht.joined(separator: ", "))"]).joined(separator: "\n")
  }
  public var line: String {
    "Ton \(ton), Epoche \(epoche), Ort \(ort), Bedrohung \(bedrohung), Licht \(licht)." + (muss.isEmpty ? "" : " Muss vorkommen: \(muss.joined(separator: ", ")).") + (nicht.isEmpty ? "" : " Darf nicht vorkommen: \(nicht.joined(separator: ", ")).")
  }
}

public struct GenState: Codable, Equatable {
  public var mode = ""                       // orakel | text | mix ("" = no generated world)
  public var slots = GenSlots()
  public var praemisse = "", alltag = "", start = "", szene = "", pcZiel = ""
  public var orte: [String: String] = [:]    // generated places: name -> "kurz · herrscht"
  public var used: [String] = []             // name generator used-set (lowercase)
  public var wuerze: [[String]] = []         // oracle word pairs ("inspiration only")
  public var ready = false                   // "spielbar"
  public var secs: [String: Double] = [:]    // timing per stage
  public init() {}
}

/// Never rendered into [Welt] or the narrator prompt except through `reveal`.
public struct HiddenNpc: Codable, Equatable {
  public var geheimnis = "", ziel = "", gruppe = "", typ = "", ref = ""
  public var revealed = false
  public var spur = 0               // "Spur" score: how far the player is on the track of this secret
  public var senkung = 0            // anti-stuck: thresholds lowered by this much
  public var stuck = 0              // engaged turns without a tier change
  public var besucht = false, gegenstand = false   // one-time spur events
  public init() {}
  enum K: String, CodingKey { case geheimnis, ziel, gruppe, typ, ref, revealed, spur, senkung, stuck, besucht, gegenstand }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    geheimnis = try c.decodeIfPresent(String.self, forKey: .geheimnis) ?? ""; ziel = try c.decodeIfPresent(String.self, forKey: .ziel) ?? ""; gruppe = try c.decodeIfPresent(String.self, forKey: .gruppe) ?? ""
    typ = try c.decodeIfPresent(String.self, forKey: .typ) ?? ""; ref = try c.decodeIfPresent(String.self, forKey: .ref) ?? ""; revealed = try c.decodeIfPresent(Bool.self, forKey: .revealed) ?? false
    spur = try c.decodeIfPresent(Int.self, forKey: .spur) ?? 0; senkung = try c.decodeIfPresent(Int.self, forKey: .senkung) ?? 0; stuck = try c.decodeIfPresent(Int.self, forKey: .stuck) ?? 0
    besucht = try c.decodeIfPresent(Bool.self, forKey: .besucht) ?? false; gegenstand = try c.decodeIfPresent(Bool.self, forKey: .gegenstand) ?? false
  }
  /// 0 verdeckt (hard ban) · 1 Andeutung (soft penalty) · 2 Hinweis (free, one keyword offered) · 3 enthüllt
  public func tier(_ thresholds: [Int]) -> Int { revealed ? 3 : thresholds.filter { spur >= max(1, $0 - senkung) }.count }
}
public struct Clue: Codable, Equatable { public var thread: String, text: String, at: String; public var found = false }
public struct HiddenWorld: Codable, Equatable {
  public var npcs: [String: HiddenNpc] = [:]   // by NPC name
  public var clues: [Clue] = []
  public var pcGeheim = ""
  public var schwellen = [2, 4, 6]             // spur thresholds for tier 1/2/3 (config)
  public var stuckN = 8                        // engaged turns without progress before the thresholds drop by 1
  public init() {}
  enum K: String, CodingKey { case npcs, clues, pcGeheim, schwellen, stuckN }
  public init(from d: Decoder) throws {
    let c = try d.container(keyedBy: K.self)
    npcs = try c.decodeIfPresent([String: HiddenNpc].self, forKey: .npcs) ?? [:]; clues = try c.decodeIfPresent([Clue].self, forKey: .clues) ?? []
    pcGeheim = try c.decodeIfPresent(String.self, forKey: .pcGeheim) ?? ""; schwellen = try c.decodeIfPresent([Int].self, forKey: .schwellen) ?? [2, 4, 6]; stuckN = try c.decodeIfPresent(Int.self, forKey: .stuckN) ?? 8
  }
}

public enum GenError: Error, CustomStringConvertible { case msg(String); public var description: String { if case .msg(let s) = self { return s }; return "" } }

// MARK: grammars (id enums: places / npcs / roles come from the current world, free text uses regex prefix + unbounded tail)

public enum GenGr {
  static func en(_ v: [String]) -> G { v.count == 1 ? .s(v[0]) : .or(v.map { .s($0) }) }
  static let line = G.re(Cls.rep(Cls.line, 6))
  static let hintLine = G.re(Cls.rep(Cls.line, 6))   // NB llg: a literal must not start with a char the preceding free-text class also accepts (" @" was rejected); the separator is "@ " and the text keeps its trailing space
  /// proper place name: optional article, capitalised words (+ small connectors) - no glued "Die"+junk
  static let placeName = G.re(#"((Der|Die|Das|Zum|Zur|Am|Im) )?[A-ZÄÖÜ][a-zäöüß]{3,}(( (von|der|des|am|zum|zur|im|zu|an))? [A-ZÄÖÜ][a-zäöüß]{3,}){0,2}"#)
  static let word = G.re(#"[A-ZÄÖÜ][a-zäöüß]{3,}( [a-zäöüß]{3,})?"#)
  static let optLine = G.or([.s("-"), .re(Cls.rep(Cls.line, 2))])
  static let roles = ["Händler", "Schmied", "Heiler", "Jäger", "Fährmann", "Priester", "Bürgermeister", "Wache", "Bauer", "Köhler", "Schreiber", "Bote", "Gerber", "Fischer", "Müller", "Bäcker", "Wirt", "Magd", "Knecht", "Söldner", "Wanderprediger", "Kräuterfrau", "Totengräber", "Zöllner", "Spielmann", "Bettler", "Schäfer", "Glöckner", "Steinmetz", "Schiffer", "Webermeister", "Waffenmeister", "Hebamme", "Archivar", "Pilger", "Schmuggler", "Hauptmann", "Mönch", "Nonne", "Alchemist"]
  public static let reveals = ["ort_betreten", "npc_befragt", "gegenstand", "zeit", "orakel"]

  public static var slots: Grammar {
    var p: [G] = []
    for k in GenSlots.keys { p += [.s("\(k.capitalized): "), k == "ort" ? .or([en(GenSlots.enums[k]! + ["offen"]), .re("[A-ZÄÖÜ]" + Cls.rep(Cls.line, 2))]) : en(GenSlots.enums[k]! + ["offen"]), .s("\n")] }
    p += [.s("Muss: "), optLine, .s("\nNicht: "), optLine]
    return Grammar(.seq(p))
  }
  /// `alltag`: the player's own place name when given (it becomes the real start place), otherwise a generated one
  public static func premise(alltag: String? = nil) -> Grammar { Grammar(.seq([.s("Prämisse: "), line, .s("\nAlltag: "), alltag.map { G.s($0) } ?? placeName])) }
  public static let premise = premise()
  public static func place(name: String? = nil) -> Grammar {
    Grammar(.seq([.s("Ort: "), name.map { G.s($0) } ?? placeName, .s("\nKurz: "), line, .s("\nHerrscht: "), line]))
  }
  static func revealG(places: [String], npcs: [String]) -> G {
    var alts: [G] = [.seq([.s("zeit "), .re("[1-9][0-9]?")]), .seq([.s("gegenstand "), word])]
    if !places.isEmpty { alts.append(.seq([.s("ort_betreten "), en(places)])) }
    if !npcs.isEmpty { alts.append(.seq([.s("npc_befragt "), en(npcs)])); alts.append(.seq([.s("orakel "), en(npcs)])) }
    return .or(alts)
  }
  /// NPC stage: the NAME is fixed by the name generator (const string), role / place / reveal from enums.
  public static func npc(name: String, places: [String], npcs: [String], role: String? = nil, place: String? = nil, roles avail: [String]? = nil) -> Grammar {
    Grammar(.seq([.s("Name: \(name)\nRolle: "), en(role.map { [$0] } ?? (avail?.isEmpty == false ? avail! : roles)), .s("\nHaltung: "), .re(#"-?[0-2]"#), .s("\nOrt: "), en(place.map { [$0] } ?? places), .s("\nGruppe: "), line,
                  .s("\nZiel: "), line, .s("\nGeheimnis: "), line, .s("\nEnthüllung: "), revealG(places: places, npcs: npcs)]))
  }
  public static func thread(refs: [String]) -> Grammar {
    let hint = { (n: Int) -> [G] in [.s("\nHinweis\(n): "), hintLine, .s("@ "), en(refs)] }
    return Grammar(.seq([.s("Frage: "), .or(["Wer ", "Wo ", "Was ", "Warum ", "Wie "].map { .s($0) }), .re(Cls.rep(Cls.lineNoQ, 8)), .s("?")] + hint(1) + hint(2) + hint(3)))
  }
  public static func start(places: [String]) -> Grammar {
    Grammar(.seq([.s("Start: "), en(places), .s("\nSzene: "), line, .s("\nZiel der Figur: "), line, .s("\nGeheimes Ziel: "), line]))
  }
}

// MARK: prompts

/// few-shot examples (also used by the grammar tests)
public enum GenPromptEx { public static var slots: String { GenPrompt.ex["slots"]!.components(separatedBy: "\n").dropFirst().joined(separator: "\n") }; public static var premise: String { GenPrompt.ex["premise"]! }; public static var place: String { GenPrompt.ex["place"]! }; public static var npc: String { GenPrompt.ex["npc"]! }; public static var thread: String { GenPrompt.ex["thread"]! }; public static var start: String { GenPrompt.ex["start"]! } }

enum GenPrompt {
  static let sys = "Du erschaffst die Welt eines düsteren Solo-Rollenspiels auf Deutsch. Konkret, ungewöhnlich, keine Klischees. Du hältst dich an die Vorgaben und erfindest keine Zusatzfelder. Antworte genau im vorgegebenen Zeilenformat."
  static let ex: [String: String] = [
    "slots": "Text: Eine Karawanenstadt stirbt langsam, der Brunnen versiegt.\nTon: bitter\nEpoche: offen\nOrt: Karawanenstadt\nBedrohung: Hungersnot\nLicht: offen\nMuss: Brunnen\nNicht: -",
    "premise": "Prämisse: Seit drei Monaten fällt kein Regen, und die Karawanenstadt verkauft ihr letztes Wasser an den Meistbietenden.\nAlltag: Der Basar am Brunnentor",
    "place": "Ort: Brunnentor\nKurz: Ein Torbogen aus rotem Stein, an dem Wasser nach Gewicht verkauft wird.\nHerrscht: Die Zunft der Wasserwäger",
    "npc": "Name: Zubeir\nRolle: Zöllner\nHaltung: -1\nOrt: Brunnentor\nGruppe: Zunft der Wasserwäger\nZiel: Die Zunft vor dem Bankrott bewahren\nGeheimnis: Er panscht das Wasser mit Salzlake\nEnthüllung: ort_betreten Brunnentor",
    "thread": "Frage: Wer hat die Zisterne unter dem Basar versiegelt?\nHinweis1: Frische Mörtelspuren am Gitter @ Brunnentor\nHinweis2: Ein Zöllner kennt den Schlüssel @ Zubeir\nHinweis3: Der Schlüssel wurde nachts verkauft @ Brunnentor",
    "start": "Start: Brunnentor\nSzene: Du reihst dich in die Schlange vor dem Brunnentor ein, als ein Streit ausbricht.\nZiel der Figur: Wasser für die Karawane kaufen\nGeheimes Ziel: Beweise für die gepanschte Lake sammeln",
  ]
}

/// Validator shared by all stages: banned words, darf_nicht, literal oracle pairs (both words verbatim -> reject).
public func genCheck(_ t: String, _ g: GenState) -> String? {
  if !isCleanText(t) { return "unzulässige Zeichen (nur lateinische Buchstaben, Umlaute und Satzzeichen)" }
  let low = t.lowercased()
  for b in NameGen.banned.union(["schatten", "uralt", "flüstern", "flüstert", "raunen"]) where low.range(of: "\\b\(b)\\b", options: .regularExpression) != nil { return "Wort '\(b)' ist verboten" }
  for n in g.slots.nicht where !n.isEmpty && low.contains(norm(n)) { return "'\(n)' darf nicht vorkommen" }
  for p in g.wuerze where p.count == 2 && low.contains(norm(p[0])) && low.contains(norm(p[1])) { return "die Wörter '\(p[0])' und '\(p[1])' stehen beide wörtlich im Text – deute sie, zitiere sie nicht" }
  return nil
}
public func genFields(_ t: String) -> [String: String] {
  var d: [String: String] = [:]
  for l in t.split(separator: "\n") { if let i = l.firstIndex(of: ":") { d[String(l[..<i])] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
  return d
}
extension GenSlots {
  /// Unfilled slots come from the oracle (true RNG); filled ones are hard constraints and never overridden.
  public mutating func fillOpen(_ rand: (Int) -> Int) {
    for k in offen {
      var a = Self.enums[k]!
      if k == "epoche" { a = a.filter { $0 != "antik" && $0 != "barock" } }   // dark-fantasy default: the oracle only picks antik/barock when the player asks for them
      self[k] = a[rand(a.count)]
    }
  }
}

// MARK: pipeline (Game extension)

extension Game {
  func rnd(_ n: Int) -> Int { eng.randomBelow(n) }
  func pick<T>(_ a: [T]) -> T { a[rnd(a.count)] }
  func prog(_ s: String, _ done: Int? = nil, _ total: Int? = nil) { out(.progress(s, done, total)) }

  /// One constrained generation with validation + targeted regeneration ("Verboten: <word>"), max 3 attempts.
  func genCall(_ stage: String, ctx: String, task: String, _ g: Grammar, validate: (String) -> String?, maxTok: Int = 320) throws -> String {
    let banned = Array(NameGen.banned.union(["schatten", "uralt", "flüstern", "flüstert", "raunen", "uralte", "uralten"])).sorted()
    var note = ""
    var last = ""
    for attempt in 0..<3 {
      let user = ctx + "\nVerbotene Wörter (niemals verwenden): \(banned.joined(separator: ", ")).\(note)\nBeispiel (andere Welt, NICHT übernehmen):\n\(GenPrompt.ex[stage] ?? "")\nAufgabe: \(task)\nAusgabe:"
      do {
        let (txt, _) = try lm.aux(system: GenPrompt.sys, user: user, g, temp: attempt == 0 ? 0.9 : 0.7, maxTok: maxTok)
        last = txt
        guard let why = validate(txt) else { return txt }
        note = "\nDein letzter Versuch war ungültig: \(why). Mach es anders."
      } catch is TruncatedError { note = "\nDein letzter Versuch war zu lang. Fasse dich kurz: eine kurze Zeile pro Feld."; last = "" }
    }
    if last.isEmpty { throw GenError.msg("Stufe \(stage) fehlgeschlagen (zu lang)") }
    return last   // accept the last attempt after 3 tries
  }

  func ctxBlock() -> String {
    let g = world.gen
    var c = "Vorgaben: \(g.slots.line)"
    if !g.wuerze.isEmpty { c += "\nAnregung (nur Inspiration, nie wörtlich zitieren): " + g.wuerze.map { $0.joined(separator: " + ") }.joined(separator: "; ") }
    if !g.praemisse.isEmpty { c += "\nPrämisse: \(g.praemisse)" }
    for (n, k) in g.orte.sorted(by: { $0.key < $1.key }) { c += "\nOrt \(n): \(k)" }
    for n in world.npcs { c += "\nFigur \(n.name) (\(n.kurz)) in \(n.ort ?? "?")" }
    return c
  }

  func check(_ t: String) -> String? { genCheck(t, world.gen) }

  static func fields(_ t: String) -> [String: String] { genFields(t) }

  // (c) slots: from player text (one grammar call) and/or the oracle ----------------------------------------------------------
  public func genPrepare(mode: String, text: String) throws {
    var g = GenState(); g.mode = mode
    if mode != "orakel" {
      guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw GenError.msg("Text fehlt: /welt \(mode == "mix" ? "mix " : "")\"deine Idee\"") }
      let user = "Text des Spielers: \(clean(text, 400))\nLege die Vorgaben fest. Was der Text nicht ausdrücklich festlegt (besonders Epoche und Licht), setzt du auf 'offen'. Ort = der genannte Ort in den Worten des Spielers (frei, z.B. 'Bergdorf im Alpental'). Muss = Dinge, die vorkommen müssen (kommagetrennt), Nicht = Dinge, die nicht vorkommen dürfen, sonst '-'.\n\nBeispiel:\n\(GenPrompt.ex["slots"]!)\nAusgabe:"
      let (txt, _) = try lm.aux(system: GenPrompt.sys, user: user, GenGr.slots, temp: 0.3, maxTok: 160)
      g.slots = GenSlots.parse(Self.fields(txt), text: text)
    }
    world.gen = g
    genFillOpen()
    // Würze: oracle word pairs as inspiration (player mode ~20% neutral pairs: tables are dark by design)
    for _ in 0..<2 {
      let neutral = mode != "orakel" && rnd(5) == 0
      let r = eng.call("meaning", neutral ? ["a": "ding", "b": "art"] : (rnd(2) == 0 ? ["a": "ort", "b": "wesen"] : ["a": "tun", "b": "thema"]))
      if let p = r["pairs"].arr?.first?.arr?.compactMap(\.str), p.count == 2 { world.gen.wuerze.append(p) }
    }
  }
  /// Unfilled slots come from the oracle (true RNG); filled ones are hard constraints and never overridden.
  func genFillOpen() { world.gen.slots.fillOpen(rnd) }
  public func genSetSlot(_ k: String, _ v: String) throws { try world.gen.slots.set(k, v); if v == "offen" { genFillOpen() } }

  // (d) up-front phase ----------------------------------------------------------------------------------------------------------
  public func genRun(nPlaces: Int = 3, nNpcs: Int = 2, nThreads: Int = 2) throws {
    guard world.gen.mode != "" else { throw GenError.msg("erst /welt orakel | \"text\" | mix \"text\"") }
    try lm.ensureLoaded()
    var names = NameGen(used: Set(world.gen.used), rand: rnd)
    let cult = NameGen.culture(for: world.gen.slots.line)
    let total = 1 + nPlaces + nNpcs + nThreads + 1
    var done = 0
    func tick(_ what: String, _ t0: Date) { done += 1; world.gen.secs[what] = Date().timeIntervalSince(t0); prog(what, done, total) }
    prog("Prämisse …", 0, total)
    var t0 = Date()
    let slots = world.gen.slots
    let musst = slots.muss.isEmpty ? "" : " Die Prämisse MUSS diese Begriffe enthalten: \(slots.muss.joined(separator: ", "))."
    let ortFix = slots.ortName.map { clean($0, 50) }       // the player's own place becomes the actual start place (F3)
    let pr = Self.fields((try? genCall("premise", ctx: ctxBlock(), task: "Schreibe die Prämisse (eine Zeile, Spannung + Alltag)\(ortFix.map { " am Ort '\($0)'" } ?? "") und nenne den Alltagsort.\(musst)", GenGr.premise(alltag: ortFix), validate: { t in self.check(t) ?? slots.missing(in: t).map { "Pflichtbegriff '\($0)' fehlt" } })) ?? "")
    world.gen.praemisse = clean(pr["Prämisse"] ?? "", 260); world.gen.alltag = clean(pr["Alltag"] ?? "Der Marktplatz", 50)
    tick("Prämisse", t0)
    // places
    var places: [String] = []
    for i in 0..<nPlaces {
      prog("Orte \(i)/\(nPlaces) …", done, total); t0 = Date()
      let taken = places.joined(separator: ", ")
      guard let t = try? genCall("place", ctx: ctxBlock(), task: i == 0 ? "Beschreibe den Alltagsort '\(world.gen.alltag)' (Name unverändert übernehmen)." : "Erfinde einen weiteren, anderen Ort (bereits vergeben: \(taken)). Wer herrscht dort?", i == 0 ? GenGr.place(name: world.gen.alltag) : GenGr.place(), validate: { t in
        let f = Self.fields(t); let n = f["Ort"] ?? ""
        if places.contains(where: { norm($0) == norm(n) }) { return "Ortsname '\(n)' ist schon vergeben" }
        return self.check(t) }) else { out(.info("Ort \(i + 1) fehlgeschlagen – weiter")); continue }
      let f = Self.fields(t); let n = clean(f["Ort"] ?? "Ort\(i + 1)", 40)
      if places.contains(where: { norm($0) == norm(n) }) { continue }
      places.append(n); world.gen.orte[n] = clean((f["Kurz"] ?? "") + " · " + (f["Herrscht"] ?? ""), 140); world.orte[n] = clean(f["Kurz"] ?? "", 80)
      tick("Orte \(places.count)/\(nPlaces)", t0)
    }
    if places.isEmpty { places = [world.gen.alltag]; world.gen.orte[world.gen.alltag] = ""; world.orte[world.gen.alltag] = "" }
    let startPlace = places[0]
    // npcs (name = const from the generator)
    for i in 0..<nNpcs {
      prog("Figuren \(i)/\(nNpcs) …", done, total); t0 = Date()
      do { try genNpc(names: &names, culture: cult, places: places, place: i == 0 ? startPlace : nil, role: nil) } catch { out(.info("Figur \(i + 1) fehlgeschlagen – weiter")) }
      tick("Figuren \(i + 1)/\(nNpcs)", t0)
    }
    // threads (question arcs; clues stay hidden)
    for i in 0..<nThreads {
      prog("Fäden \(i)/\(nThreads) …", done, total); t0 = Date()
      let refs = places + world.npcs.map(\.name)
      guard let t = try? genCall("thread", ctx: ctxBlock(), task: "Erfinde eine offene Frage der Welt (Faden \(i + 1)) mit drei Hinweisen, jeder an einem Ort oder bei einer Figur (nach @). Nicht mit '\(world.straenge.map(\.titel).joined(separator: "', '"))' doppeln.", GenGr.thread(refs: refs), validate: { t in self.check(t) ?? (i == 0 ? self.world.gen.slots.muss.first.flatMap { m in t.lowercased().contains(String(m.lowercased().prefix(5))) ? nil : "Pflichtbegriff '\(m)' muss im ersten Faden vorkommen" } : nil) }, maxTok: 380) else { out(.info("Faden \(i + 1) fehlgeschlagen – weiter")); tick("Faden \(i + 1) übersprungen", t0); continue }
      let f = Self.fields(t); var q = clean(f["Frage"] ?? "", 70); while q.hasSuffix("?") { q.removeLast() }
      let qt = Set(tokens(q)), dup = world.straenge.contains { let o = Set(tokens($0.titel)); return !o.isEmpty && Double(o.intersection(qt).count) / Double(max(o.count, qt.count)) >= 0.6 }   // near-duplicate question
      if okThread(q) && !dup {
        world.straenge.append(Strang(titel: q, stand: "")); world.festeStraenge.insert(q)
        for n in 1...3 { if let h = f["Hinweis\(n)"], let r = h.range(of: "@ ", options: .backwards) { hidden.clues.append(Clue(thread: q, text: clean(String(h[..<r.lowerBound]), 90), at: String(h[r.upperBound...]).trimmingCharacters(in: .whitespaces))) } }
      }
      tick("Fäden \(i + 1)/\(nThreads)", t0)
    }
    for c in hidden.clues { if let i = world.npcs.firstIndex(where: { $0.name == c.at }) { world.npcs[i].fest = true } }   // clue holders are protected too
    // start scene + player hook
    prog("Startszene …", done, total); t0 = Date()
    let s = Self.fields((try? genCall("start", ctx: ctxBlock(), task: "Lege den Beginn fest: Startort, erste Szene (2. Person, ein Satz), Ziel der Figur und ein geheimes Ziel.", GenGr.start(places: places), validate: check)) ?? "")
    world.gen.start = world.gen.slots.ortName != nil ? startPlace : (places.contains(s["Start"] ?? "") ? s["Start"]! : startPlace)   // the player's own place is where the story starts
    world.gen.szene = clean(s["Szene"] ?? "", 200); world.gen.pcZiel = clean(s["Ziel der Figur"] ?? "", 100); hidden.pcGeheim = clean(s["Geheimes Ziel"] ?? "", 100)
    world.ort = world.gen.start
    for i in world.npcs.indices { world.npcs[i].anwesend = world.samePlace(world.npcs[i].ort, world.gen.start) }
    for w in hidden.threadWarnings(world, places: Set(world.gen.orte.keys)) { out(.info("Warnung: \(w)")) }
    world.gen.used = names.used.sorted()
    world.gen.ready = true
    world.syncLists(eng)
    tick("Startszene", t0)
    let secs = world.gen.secs.values.reduce(0, +)
    prog(String(format: "Welt spielbar (%.0f s) – weitere Orte/Figuren entstehen beim ersten Kontakt", secs), total, total)
    pendingNote = "Auftakt (verdeckt vorgegeben): \(world.gen.szene) Ziel der Figur: \(world.gen.pcZiel)"
  }

  /// One NPC (name from the generator, hidden details into `hidden`, visible card into the world).
  func genNpc(names: inout NameGen, culture: String, places: [String], place: String?, role: String?, fixedName: String? = nil) throws {
    let name = fixedName ?? names.next(culture: culture, avoid: Set(world.npcs.map { norm($0.name) }))
    let others = world.npcs.map(\.name)
    let t = try genCall("npc", ctx: ctxBlock(), task: "Erschaffe eine Figur. Name '\(name)' ist vorgegeben. Rolle nicht doppeln (bereits: \(world.npcs.map(\.kurz).joined(separator: ", "))). Geheimnis + Ziel kurz, konkret; Enthüllung = wodurch das Geheimnis herauskommen kann.", GenGr.npc(name: name, places: places, npcs: others + [name], role: role, place: place, roles: GenGr.roles.filter { r in !world.npcs.contains { $0.kurz == r } }), validate: check, maxTok: 340)
    let f = Self.fields(t)
    let ort = places.contains(f["Ort"] ?? "") ? f["Ort"]! : (place ?? places.first ?? "")
    guard let (i, _) = world.addNpcGen(name: name, kurz: f["Rolle"] ?? "", ort: ort, haltung: Int(f["Haltung"] ?? "0") ?? 0) else { return }
    _ = i
    var h = HiddenNpc(); h.geheimnis = clean(f["Geheimnis"] ?? "", 100); h.ziel = clean(f["Ziel"] ?? "", 100); h.gruppe = clean(f["Gruppe"] ?? "", 60)
    let r = (f["Enthüllung"] ?? "zeit 6").split(separator: " ", maxSplits: 1).map(String.init)
    h.typ = r.first ?? "zeit"; h.ref = r.count > 1 ? r[1] : "6"
    hidden.npcs[name] = h
  }

  // (f) lazy generation on first contact ---------------------------------------------------------------------------------------------
  /// Called after start_scene / the narrator tail: unknown places and role-only NPCs get hidden details when first met.
  public func genLazy() {
    guard world.gen.mode != "", world.gen.ready else { return }
    do {
      var names = NameGen(used: Set(world.gen.used), rand: rnd)
      let places = Array(world.gen.orte.keys)
      if let o = world.ort, !o.isEmpty, world.gen.orte[o] == nil, world.gen.orte.count < 8 {
        prog("… \(o)")
        let t = try genCall("place", ctx: ctxBlock(), task: "Beschreibe den Ort '\(o)' (Name unverändert übernehmen). Wer herrscht dort?", GenGr.place(name: o), validate: check)
        let f = Self.fields(t); world.gen.orte[o] = clean((f["Kurz"] ?? "") + " · " + (f["Herrscht"] ?? ""), 140); world.orte[o] = clean(f["Kurz"] ?? "", 80)
      }
      for n in world.npcs where hidden.npcs[n.name] == nil && n.anwesend && world.npcs.count <= 10 {
        prog("… \(n.name)")
        let t = try genCall("npc", ctx: ctxBlock(), task: "Ergänze Geheimnis, Ziel und Gruppe der Figur '\(n.name)' (\(n.kurz)). Rolle und Ort bleiben.", GenGr.npc(name: n.name, places: places.isEmpty ? [world.ort ?? "hier"] : places, npcs: world.npcs.map(\.name), role: GenGr.roles.contains(n.kurz) ? n.kurz : nil, place: n.ort), validate: check, maxTok: 340)
        let f = Self.fields(t); var h = HiddenNpc()
        h.geheimnis = clean(f["Geheimnis"] ?? "", 100); h.ziel = clean(f["Ziel"] ?? "", 100); h.gruppe = clean(f["Gruppe"] ?? "", 60)
        let r = (f["Enthüllung"] ?? "zeit 6").split(separator: " ", maxSplits: 1).map(String.init); h.typ = r.first ?? "zeit"; h.ref = r.count > 1 ? r[1] : "6"
        hidden.npcs[n.name] = h; names.reserve(n.name)
      }
      world.gen.used = names.used.sorted()
    } catch { out(.info("Lazy-Generierung fehlgeschlagen: \(error)")) }
  }

  // (e) reveal ---------------------------------------------------------------------------------------------------------------------------
  /// The harness decides: when a hidden fact's condition is met it moves into `bekannt` / a thread's hints and is injected ONCE as
  /// "[Hinweis verdeckt] …" into the next narrator turn. Returns the lines.
  public func genReveals(oracle: [(q: String, a: String)], talked: [String]) -> [String] { hidden.reveal(&world, oracle: oracle, talked: talked) }
  /// names of NPCs the player named in this turn's line (counts as "spoken to" for clue reveals)
  func namedBy(_ text: String) -> [String] { let ids = world.mentioned(in: text); return world.npcs.filter { ids.contains($0.id) }.map(\.name) }
}

extension HiddenWorld {
  /// Older sessions: clue locations / place refs spelled differently from the world's place name ("Die Krypta" vs "Krypta") are rewritten to the world's spelling.
  public mutating func canonPlaces(_ names: [String]) {
    func canon(_ s: String) -> String { names.first(where: { key($0) == key(s) }) ?? s }
    for i in clues.indices { clues[i].at = canon(clues[i].at) }
    for k in npcs.keys where npcs[k]!.typ == "ort_betreten" { npcs[k]!.ref = canon(npcs[k]!.ref) }
  }
  /// The harness decides: when a hidden fact's condition is met it moves into `bekannt` / a thread's hints and is injected ONCE as
  /// "[Hinweis verdeckt] …" into the next narrator turn. Returns the lines.
  public mutating func reveal(_ world: inout World, oracle: [(q: String, a: String)], talked: [String]) -> [String] {
    var lines: [String] = []
    for (name, h) in npcs where !h.revealed {
      var hit = false
      switch h.typ {
      case "ort_betreten": hit = world.samePlace(world.ort, h.ref)
      case "zeit": hit = world.turn >= (Int(h.ref) ?? 99)
      case "gegenstand": hit = world.inventar.contains { norm($0).contains(norm(h.ref)) }
      case "npc_befragt": hit = talked.contains { norm($0) == norm(h.ref) }
      case "orakel": hit = oracle.contains { ($0.a == "JA" || $0.a == "JA+") && norm($0.q).contains(norm(h.ref)) }
      default: break
      }
      guard hit, let i = world.npcs.firstIndex(where: { $0.name == name }) else { continue }
      npcs[name]?.revealed = true
      world.npcs[i].bekannt.append(cutWords(h.geheimnis, 10)); if world.npcs[i].bekannt.count > 3 { world.npcs[i].bekannt.removeFirst() }
      lines.append("\(name): \(h.geheimnis)")
    }
    if lines.count >= 1 { return lines }                       // pacing: at most one reveal per turn
    for k in clues.indices where !clues[k].found {
      let c = clues[k]
      // a clue at a place needs the player there; a clue held by an NPC needs that NPC to be spoken to / named (not mere presence)
      let here = world.samePlace(world.ort, c.at) || talked.contains { norm($0) == norm(c.at) }
      guard here, let ti = world.straenge.firstIndex(where: { $0.titel == c.thread }), world.straenge[ti].stufe != "antwort" else { continue }
      clues[k].found = true
      world.straenge[ti].hinweise.append(c.text); if world.straenge[ti].hinweise.count > 3 { world.straenge[ti].hinweise.removeFirst() }
      world.straenge[ti].stufe = "hinweise"; world.straenge[ti].stand = cutWords(c.text, 6)
      lines.append("Hinweis zu '\(c.thread)': \(c.text)")
      break                                                    // one per turn
    }
    return lines
  }
}

extension World {
  @discardableResult
  mutating func addNpcGen(name: String, kurz: String, ort: String, haltung: Int) -> (Int, Bool)? {
    guard let r = addNpc(name: name, kurz: kurz, ort: ort) else { return nil }
    npcs[r.0].haltung = max(-2, min(2, haltung)); npcs[r.0].basis = npcs[r.0].haltung; npcs[r.0].anwesend = false; npcs[r.0].fest = true
    return r
  }
}

extension HiddenWorld {
  /// Mirrors `World.repairText()` for hidden.json (a repaired thread title must keep matching `clue.thread`).
  public mutating func repairText() {
    for i in clues.indices { clues[i].thread = repairGlyphs(clues[i].thread); clues[i].at = repairGlyphs(clues[i].at); clues[i].text = repairGlyphs(clues[i].text) }
    npcs = Dictionary(npcs.map { (repairGlyphs($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
    for k in npcs.keys { npcs[k]!.ref = repairGlyphs(npcs[k]!.ref); npcs[k]!.geheimnis = repairGlyphs(npcs[k]!.geheimnis); npcs[k]!.ziel = repairGlyphs(npcs[k]!.ziel) }
  }
}
