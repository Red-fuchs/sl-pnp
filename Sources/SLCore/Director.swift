import Foundation

// MARK: leak guard (deterministic, no extra model)

let germanStop: Set<String> = ["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "und", "oder", "aber", "doch", "mit", "von", "vor", "für", "auf", "aus", "bei", "nach", "über", "unter", "durch", "gegen", "ohne", "zum", "zur", "im", "am", "ist", "sind", "war", "waren", "wird", "werden", "wurde", "hat", "haben", "hatte", "kann", "will", "soll", "muss", "nicht", "kein", "keine", "sich", "sie", "ihr", "ihre", "ihm", "ihn", "er", "es", "wir", "du", "dein", "dich", "dir", "als", "wie", "was", "wer", "wo", "wenn", "dass", "damit", "dann", "noch", "nur", "auch", "sehr", "mehr", "schon", "immer", "hier", "dort", "diese", "dieser", "dieses", "jede", "jeder", "alle", "alles", "etwas", "nichts", "man", "um", "zu", "an", "in", "so", "da", "bis", "seit", "weil"]
/// domain-generic nouns: sharing them with a secret is no leak
let commonNouns: Set<String> = ["wasser", "haus", "stadt", "dorf", "mann", "frau", "kind", "tür", "nacht", "tag", "hand", "auge", "licht", "schatten", "stein", "holz", "feuer", "luft", "herz", "blut", "tod", "angst", "weg", "wand", "raum", "keller", "brunnen", "markt", "platz", "straße", "gasse", "tor", "turm", "mauer", "boden", "himmel", "wind", "regen", "nebel", "stimme", "blick", "name", "ding", "zeit", "leben", "welt", "land", "hafen", "schiff", "boot", "meer", "fluss", "wald", "berg", "tal", "kirche", "kloster", "halle", "saal", "tisch", "stuhl", "bett", "fenster", "dach", "treppe", "gold", "geld", "silber", "brot", "bier", "wein", "messer", "schwert", "waffe", "brief", "buch", "schlüssel", "geheimnis", "plan", "ziel", "grund", "sache", "arbeit", "ordnung", "macht", "recht", "gesetz", "schuld", "lüge", "wahrheit", "gruppe", "zunft", "rat", "volk", "leute", "bürger", "wache", "händler"]

func stem(_ w: String) -> String { String(w.lowercased().prefix(5)) }
func contentWords(_ t: String) -> [String] { t.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !germanStop.contains($0.lowercased()) } }

public struct Leak: Equatable { public var topic: String, words: [String] }

/// F-Regie: does `text` give away an unrevealed secret? Content-word overlap with stopwords removed and 5-letter stems.
/// Leak = >=2 distinct rare secret words in the text, or ONE name-like word (capitalised, >=6 letters, not a common noun, not already visible in [Welt]).
public func leakCheck(_ text: String, secrets: [(topic: String, text: String)], known: String) -> Leak? {
  let seen = Set(contentWords(known).map(stem)), tw = Dictionary(grouping: contentWords(text), by: stem)
  for s in secrets {
    var rare: [String: String] = [:]            // stem -> original word of the secret
    for w in contentWords(s.text) where !seen.contains(stem(w)) && !commonNouns.contains(w.lowercased()) { rare[stem(w)] = w }
    let hits = rare.keys.filter { tw[$0] != nil }
    let nameLike = hits.contains { k in let w = rare[k]!; return w.count >= 6 && w.first!.isUppercase }
    if hits.count >= 2 || nameLike { return Leak(topic: s.topic, words: hits.map { rare[$0]! }) }
  }
  return nil
}

/// Removes the sentences that carry a leak (second line of defence when a regeneration still leaks).
public func dropLeakingSentences(_ narr: String, secrets: [(topic: String, text: String)], known: String) -> String {
  var parts: [String] = [], cur = ""
  for ch in narr { cur.append(ch); if ".!?".contains(ch) { parts.append(cur); cur = "" } }
  if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }
  let kept = parts.filter { leakCheck($0, secrets: secrets, known: known) == nil }
  return (kept.isEmpty ? Array(parts.prefix(1).filter { leakCheck($0, secrets: secrets, known: known) == nil }) : kept).joined().trimmingCharacters(in: .whitespaces)
}

// MARK: director pass (Regie)

extension HiddenWorld {
  /// Unrevealed secrets: NPC geheimnis + ziel, unfound clues, the player's secret goal.
  public func secretList() -> [(topic: String, text: String)] {
    var r: [(String, String)] = []
    for (n, h) in npcs.sorted(by: { $0.key < $1.key }) {
      if !h.revealed, !h.geheimnis.isEmpty { r.append(("Geheimnis von \(n)", h.geheimnis)) }
      if !h.ziel.isEmpty { r.append(("Ziel von \(n)", h.ziel)) }
    }
    for c in clues where !c.found { r.append(("Hinweis zu '\(c.thread)'", c.text)) }
    if !pcGeheim.isEmpty { r.append(("geheimes Ziel der Spielfigur", pcGeheim)) }
    return r
  }
  /// present, living NPCs that carry an unrevealed secret or a hidden goal
  public func bearers(in world: World) -> [String] {
    world.npcs.filter { $0.anwesend && !$0.tot && npcs[$0.name].map { (!$0.revealed && !$0.geheimnis.isEmpty) || !$0.ziel.isEmpty } == true }.map(\.name)
  }
}
extension World {
  /// everything the player may already know (rare-word filter of the leak guard)
  public func knownText() -> String {
    block(full: true) + " " + gen.praemisse + " " + gen.szene + " " + gen.pcZiel + " " + straenge.map { $0.titel + " " + $0.hinweise.joined(separator: " ") }.joined(separator: " ") + " " + npcs.map { $0.bekannt.joined(separator: " ") }.joined(separator: " ")
  }
}

extension Game {
  func secretList() -> [(topic: String, text: String)] { hidden.secretList() }
  func knownText() -> String { world.knownText() }
  func secretBearersHere() -> [String] { hidden.bearers(in: world) }

  /// "Regie": the model may use the secrets fully, the output is behaviour only (<= 2 short lines). Side cache, like the world-delta step.
  func directorPass(player: String) -> String? {
    let who = secretBearersHere(); guard !who.isEmpty else { return nil }
    let facts = who.map { n -> String in let h = hidden.npcs[n]!; return "\(n): Geheimnis: \(h.revealed ? "(bekannt)" : h.geheimnis). Ziel: \(h.ziel). Gruppe: \(h.gruppe)." }.joined(separator: "\n")
    let sys = "Du bist Regisseur eines düsteren Rollenspiels. Du kennst die Geheimnisse der anwesenden Figuren. Beschreibe in höchstens zwei kurzen Zeilen, wie sich die betroffenen Figuren jetzt VERHALTEN (Körpersprache, Ausweichen, Blicke, Tonfall, Handgriffe). Nenne niemals das Geheimnis, das Ziel oder Fakten daraus – nur sichtbares Verhalten. Zeilenformat: \"Regie: <Name> <Verhalten>\"."
    var note = ""
    for attempt in 0..<2 {
      let user = world.block() + "\n---\nGeheim (nur für dich):\n\(facts)\nAktion der Spielfigur: \(clean(player, 200))\(note)\nAusgabe:"
      guard let (txt, _) = try? lm.aux(system: sys, user: user, Gr.regie, temp: 0.7, maxTok: 120) else { return nil }
      let lines = txt.split(separator: "\n").map { String($0).replacingOccurrences(of: "Regie: ", with: "") }
      let joined = lines.joined(separator: " ")
      if let l = leakCheck(joined, secrets: secretList(), known: knownText()) {
        if attempt == 0 { note = "\nDein letzter Versuch verriet: \(l.topic). Verrate nichts davon, nur Verhalten."; continue }
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
    let line = G.re(#"[A-ZÄÖÜ][^\n<]{12}[^\n<]*"#)
    return Grammar(.or([.seq([.s("Regie: "), line]), .seq([.s("Regie: "), line, .s("\nRegie: "), line])]))
  }
}
