import Foundation

// MARK: leak guard (deterministic, no extra model)

let germanStop: Set<String> = ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "und", "oder", "aber", "doch", "mit", "von", "vor", "für", "auf", "aus", "bei", "nach", "über", "unter", "durch", "gegen", "ohne", "zum", "zur", "im", "am", "ist", "sind", "war", "waren", "wird", "werden", "wurde", "hat", "haben", "hatte", "kann", "will", "soll", "muss", "nicht", "kein", "keine", "sich", "sie", "ihr", "ihre", "ihm", "ihn", "er", "es", "wir", "du", "dein", "dich", "dir", "als", "wie", "was", "wer", "wo", "wenn", "dass", "damit", "dann", "noch", "nur", "auch", "sehr", "mehr", "schon", "immer", "hier", "dort", "diese", "dieser", "dieses", "jede", "jeder", "alle", "alles", "etwas", "nichts", "man", "um", "zu", "an", "in", "so", "da", "bis", "seit", "weil"]
/// domain-generic nouns: sharing them with a secret is no leak
let commonNouns: Set<String> = ["wasser", "haus", "stadt", "dorf", "mann", "frau", "kind", "tür", "nacht", "tag", "hand", "auge", "licht", "schatten", "stein", "holz", "feuer", "luft", "herz", "blut", "tod", "angst", "weg", "wand", "raum", "keller", "brunnen", "markt", "platz", "straße", "gasse", "tor", "turm", "mauer", "boden", "himmel", "wind", "regen", "nebel", "stimme", "blick", "name", "ding", "zeit", "leben", "welt", "land", "hafen", "schiff", "boot", "meer", "fluss", "wald", "berg", "tal", "kirche", "kloster", "halle", "saal", "tisch", "stuhl", "bett", "fenster", "dach", "treppe", "gold", "geld", "silber", "brot", "bier", "wein", "messer", "schwert", "waffe", "brief", "buch", "schlüssel", "geheimnis", "plan", "ziel", "grund", "sache", "arbeit", "ordnung", "macht", "recht", "gesetz", "schuld", "lüge", "wahrheit", "gruppe", "zunft", "rat", "volk", "leute", "bürger", "wache", "händler"]

func stem(_ w: String) -> String { String(w.lowercased().prefix(5)) }
/// German word key: lower case, common inflection suffixes stripped (Kranken/Kranke/Krankes -> krank), but a COMPOUND stays a different word
/// (Brunnentor != Brunnen - 5-letter stems made them collide and caused false regens).
func lemma(_ w: String) -> String {
  var x = w.lowercased()
  for suf in ["ern", "en", "er", "es", "e", "n", "s"] where x.hasSuffix(suf) && x.count - suf.count >= 4 { x = String(x.dropLast(suf.count)); break }
  return x
}
func contentWords(_ t: String) -> [String] { t.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !germanStop.contains($0.lowercased()) } }

public struct Leak: Equatable { public var topic: String, words: [String]; public var sentence = "" }

func sentences(of t: String) -> [String] {
  var parts: [String] = [], cur = ""
  for ch in t { cur.append(ch); if ".!?".contains(ch) { parts.append(cur); cur = "" } }
  if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }
  return parts
}

/// Does `text` give away an unrevealed secret? Evaluated PER SENTENCE with full-word (lemma) matching, stopwords and visible words removed.
/// Leak = >=2 distinct rare secret words in one sentence, or ONE name-like word (capitalised, >=6 letters) when the secret has at most two rare words.
public func leakCheck(_ text: String, secrets: [(topic: String, text: String)], known: String) -> Leak? {
  let seen = Set(contentWords(known).map(lemma))
  for sn in sentences(of: text) {
    let tw = Set(contentWords(sn).map(lemma))
    for s in secrets {
      var rare: [String: String] = [:]            // lemma -> original word of the secret
      for w in contentWords(s.text) where !seen.contains(lemma(w)) && !commonNouns.contains(w.lowercased()) { rare[lemma(w)] = w }
      let hits = rare.keys.filter { tw.contains($0) }
      let nameLike = rare.count <= 2 && hits.contains { k in let w = rare[k]!; return w.count >= 6 && w.first!.isUppercase }
      if hits.count >= 2 || nameLike { return Leak(topic: s.topic, words: hits.map { rare[$0]! }, sentence: sn) }
    }
  }
  return nil
}

/// Removes the sentences that carry a leak (second line of defence when a regeneration still leaks).
public func dropLeakingSentences(_ narr: String, secrets: [(topic: String, text: String)], known: String) -> String {
  let parts = sentences(of: narr)
  let kept = parts.filter { leakCheck($0, secrets: secrets, known: known) == nil }
  return kept.joined().trimmingCharacters(in: .whitespaces)
}

// MARK: director pass (Regie)

extension HiddenWorld {
  /// What the leak guard and the hard ban look at: the geheimnis of NPCs in tier 0 (verdeckt). NEVER clue texts (clues must stay reachable),
  /// never revealed/tier>=1 secrets, never the hidden goals (the director only steers behaviour for those).
  public func secretList() -> [(topic: String, text: String)] {
    npcs.sorted(by: { $0.key < $1.key }).compactMap { (n, h) in h.tier(schwellen) == 0 && !h.geheimnis.isEmpty ? ("Geheimnis von \(n)", h.geheimnis) : nil }
  }
  /// tier 1 (Andeutung): soft penalty instead of a ban
  public func softList() -> [(topic: String, text: String)] {
    npcs.sorted(by: { $0.key < $1.key }).compactMap { (n, h) in h.tier(schwellen) == 1 && !h.geheimnis.isEmpty ? ("Geheimnis von \(n)", h.geheimnis) : nil }
  }
  /// present, living NPCs that carry an unrevealed secret or a hidden goal (the director runs for them)
  public func bearers(in world: World) -> [String] {
    world.npcs.filter { $0.anwesend && !$0.tot && npcs[$0.name].map { (!$0.revealed && !$0.geheimnis.isEmpty) || !$0.ziel.isEmpty } == true }.map(\.name)
  }

  /// One player turn: raise the Spur of every secret the player is on the track of. Returns hint lines (tier 2: one keyword) / debug lines.
  /// +1 asking/naming the bearer, +1 entering the ref place, +1 matching item, +2 oracle yes about the bearer/topic, +1 per turn on the topic.
  /// Anti-stuck: `stuckN` engaged turns without a tier change lower this secret's thresholds by 1. Tier 3 = revealed (moves to bekannt).
  public mutating func updateSpur(_ w: inout World, player: String, oracle: [(q: String, a: String)], talked: [String]) -> [String] {
    var lines: [String] = []
    let ptoks = Set(tokens(player)), pwords = Set(contentWords(player).map(lemma))
    for name in npcs.keys.sorted() {
      guard var h = npcs[name], !h.revealed else { continue }
      let before = h.tier(schwellen)
      var gain = 0, engaged = false
      if !Set(tokens(name)).isDisjoint(with: ptoks) || talked.contains(where: { norm($0) == norm(name) }) { gain += 1; engaged = true }
      if h.typ == "ort_betreten", !h.besucht, w.samePlace(w.ort, h.ref) { h.besucht = true; gain += 1; engaged = true }
      if h.typ == "gegenstand", !h.gegenstand, w.inventar.contains(where: { norm($0).contains(norm(h.ref)) }) { h.gegenstand = true; gain += 1; engaged = true }
      let topic = Set(contentWords(h.geheimnis + " " + h.ziel).map(lemma)).subtracting(Set(contentWords(w.knownText()).map(lemma)))
      for (q, a) in oracle where (a == "JA" || a == "JA+") && (!Set(tokens(name)).isDisjoint(with: Set(tokens(q))) || !topic.isDisjoint(with: Set(contentWords(q).map(lemma)))) { gain += 2; engaged = true }
      if !topic.isDisjoint(with: pwords) { gain += 1; engaged = true }
      h.spur += gain
      let after = h.tier(schwellen)
      if after > before {
        h.stuck = 0
        if after == 3 {
          h.revealed = true
          if let i = w.npcs.firstIndex(where: { $0.name == name }) { w.npcs[i].bekannt.append(cutWords(h.geheimnis, 10)); if w.npcs[i].bekannt.count > 3 { w.npcs[i].bekannt.removeFirst() } }
          lines.append("\(name): \(h.geheimnis)")                       // free to say now
        } else if after == 2, let k = contentWords(h.geheimnis).first(where: { commonNouns.contains($0.lowercased()) == false }) {
          lines.append("\(name): Stichwort „\(k)“")                      // Hinweis: one keyword unlocked
        }
      } else if engaged {
        h.stuck += 1
        if h.stuck >= stuckN { h.stuck = 0; h.senkung += 1; lines.append("[debug] Spur \(name): Schwellen -1 (festgefahren)") }
      }
      npcs[name] = h
    }
    return lines
  }
  /// every thread needs >= 3 reachable clue paths (a clue is reachable when its location is a generated place or a living NPC)
  public func threadWarnings(_ w: World, places: Set<String>) -> [String] {
    var out: [String] = []
    for t in w.straenge where t.stufe != "antwort" {
      let cl = clues.filter { $0.thread == t.titel }
      let ok = cl.filter { c in places.contains(where: { w.samePlace($0, c.at) }) || w.npcs.contains(where: { $0.name == c.at && !$0.tot }) }.count
      if cl.isEmpty { continue }                                   // delta-made threads without clues are fine
      if ok < 3 { out.append("Faden '\(t.titel)': nur \(ok) von \(cl.count) Hinweiswegen erreichbar (Soll: 3)") }
    }
    return out
  }
  /// /welt debug (not part of the player view)
  public func debugTable() -> String {
    npcs.sorted(by: { $0.key < $1.key }).map { (n, h) in "\(n): Stufe \(h.tier(schwellen)) · Spur \(h.spur) · Schwellen \(schwellen.map { max(1, $0 - h.senkung) }) · festgefahren \(h.stuck)/\(stuckN)\(h.revealed ? " · enthüllt" : "")" }.joined(separator: "\n")
      + "\nHinweise: " + clues.map { ($0.found ? "✓" : "·") + " " + $0.at }.joined(separator: ", ")
  }
}
extension World {
  /// everything the player may already know (rare-word filter of the leak guard)
  public func knownText() -> String {
    block(full: true) + " " + gen.praemisse + " " + gen.szene + " " + gen.pcZiel + " " + straenge.map { $0.titel + " " + $0.hinweise.joined(separator: " ") }.joined(separator: " ") + " " + npcs.map { $0.bekannt.joined(separator: " ") }.joined(separator: " ")
  }
}

extension Game {
  func softList() -> [(topic: String, text: String)] { hidden.softList() }
  func secretList() -> [(topic: String, text: String)] { hidden.secretList() }
  func knownText() -> String { world.knownText() }
  func secretBearersHere() -> [String] { hidden.bearers(in: world) }

  /// "Regie": the model may use the secrets fully, the output is behaviour only (<= 2 short lines). Side cache, like the world-delta step.
  func directorPass(player: String) -> String? {
    let who = secretBearersHere(); guard !who.isEmpty else { return nil }
    let facts = who.map { n -> String in let h = hidden.npcs[n]!; return "\(n): Geheimnis: \(h.revealed ? "(bekannt)" : h.geheimnis). Ziel: \(h.ziel). Gruppe: \(h.gruppe). \(h.tier(hidden.schwellen) >= 1 ? "Das Thema darf angedeutet werden (nicht der Kern)." : "Nichts andeuten.")" }.joined(separator: "\n")
    let sys = "Du bist Regisseur eines düsteren Rollenspiels. Du kennst die Geheimnisse der anwesenden Figuren. Beschreibe in höchstens zwei kurzen Zeilen, wie sich die betroffenen Figuren jetzt VERHALTEN (Körpersprache, Ausweichen, Blicke, Tonfall, Handgriffe). Nenne niemals das Geheimnis, das Ziel oder Fakten daraus – nur sichtbares Verhalten. Zeilenformat: \"Regie: <Name> <Verhalten>\"."
    var note = ""
    for attempt in 0..<2 {
      let user = world.block() + "\n---\nGeheim (nur für dich):\n\(facts)\nAktion der Spielfigur: \(clean(player, 200))\(note)\nAusgabe:"
      guard let (txt, _) = try? lm.aux(system: sys, user: user, Gr.regie, temp: 0.7, maxTok: 120, ban: banFor(secretList(), knownText())) else { return nil }
      let lines = txt.split(separator: "\n").map { String($0).replacingOccurrences(of: "Regie: ", with: "") }
      let joined = lines.joined(separator: " ")
      if let l = leakCheck(joined, secrets: secretList(), known: knownText()) {
        if attempt == 0 { note = "\nBeschreibe nur sichtbares Verhalten, keine Fakten."; _ = l; continue }
        let kept = lines.filter { leakCheck($0, secrets: secretList(), known: knownText()) == nil }   // drop the leaking line(s)
        return kept.isEmpty ? nil : kept.joined(separator: " ")
      }
      return joined
    }
    return nil
  }
}

extension Gr {
  /// Regie: 1-2 behaviour lines
  public static var regie: Grammar {
    let line = G.re("[A-ZÄÖÜ]" + Cls.rep(Cls.line, 12))
    return Grammar(.or([.seq([.s("Regie: "), line]), .seq([.s("Regie: "), line, .s("\nRegie: "), line])]))
  }
}

// MARK: decode-time ban (first line of defence)

/// Token sequences that must not be completed while generating. Only the LAST token of a banned sequence is masked, and only once the
/// preceding tokens of that sequence have just been generated (prefix-trie style); exact token sequences only, hence the variant generator.
public struct BanSet {
  var single: Set<Int> = []                    // one-token terms: always banned
  var byPrev: [Int: [(prefix: [Int], last: Int)]] = [:]   // key = token before the last one
  public private(set) var count = 0
  public init(_ seqs: [[Int]] = []) {
    for q in seqs where !q.isEmpty {
      count += 1
      if q.count == 1 { single.insert(q[0]) } else { byPrev[q[q.count - 2], default: []].append((Array(q.dropLast()), q[q.count - 1])) }
    }
  }
  public var isEmpty: Bool { count == 0 }
  /// tokens that would complete a banned sequence as the next token
  public func blocked(after gen: [Int]) -> Set<Int> {
    var r = single
    if let l = gen.last, let c = byPrev[l] { for (pre, last) in c where gen.count >= pre.count && gen.suffix(pre.count).elementsEqual(pre) { r.insert(last) } }
    return r
  }
}

/// Rare secret words (same filter as the leak check): not visible in [Welt], not stopwords, not generic nouns.
public func banTerms(secrets: [(topic: String, text: String)], known: String) -> [String] {
  let seen = Set(contentWords(known).map(stem))
  var out: [String] = [], have = Set<String>()
  for s in secrets { for w in contentWords(s.text) where !seen.contains(stem(w)) && !commonNouns.contains(w.lowercased()) && have.insert(w.lowercased()).inserted { out.append(w) } }
  return out
}
/// HF-style bans match exact token sequences only -> generate the surface variants: lower / Capitalised, with and without leading space,
/// common German inflections (plural, genitive, dropped -e).
public func banVariants(_ w: String) -> [String] {
  let low = w.lowercased(), cap = low.prefix(1).uppercased() + low.dropFirst()
  var stems = [low, cap]
  for b in [low, cap] { if b.hasSuffix("e") { stems.append(String(b.dropLast())) } }
  var v: [String] = []
  for b in stems { for suf in ["", "n", "e", "en", "s", "es", "er", "ern"] { v.append(b + suf) } }
  return Array(Set(v)).flatMap { [$0, " " + $0] }
}
public func buildBan(terms: [String], encode: (String) -> [Int], cap: Int = 600) -> BanSet {
  var seqs: [[Int]] = [], seen = Set<[Int]>()
  for t in terms { for v in banVariants(t) { let ids = encode(v); if !ids.isEmpty, seen.insert(ids).inserted { seqs.append(ids) }; if seqs.count >= cap { return BanSet(seqs) } } }
  return BanSet(seqs)
}
