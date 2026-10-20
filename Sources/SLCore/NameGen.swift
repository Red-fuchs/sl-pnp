import Foundation
import Schicksal

/// Deterministic name generator: syllables per culture, driven by an injected random function (production: Schicksal's true RNG,
/// `Engine.randomBelow`), with a used-set so no name is issued twice. Names are handed to grammars as const strings.
public struct NameGen {
  public struct Culture { let pre: [String], mid: [String], suf: [String] }
  public static let cultures: [String: Culture] = [
    "nord": Culture(pre: ["Hald", "Sig", "Ulf", "Bjar", "Thor", "Eir", "Gunn", "Rag", "Ing", "Skul", "Vald", "Orm"], mid: ["a", "i", "o", "ar", "un", "ve"], suf: ["rik", "mund", "veig", "dis", "gar", "hild", "bjorn", "ulf", "a", "ir"]),
    "dunkel": Culture(pre: ["Kor", "Vel", "Mor", "Dra", "Ser", "Gal", "Nar", "Tho", "Bel", "Ash", "Hel", "Ulm", "Yor", "Fen"], mid: ["a", "e", "o", "an", "el", "ur", "id"], suf: ["wen", "ric", "len", "mar", "dor", "ia", "ek", "ule", "ven", "ark"]),
    "alt": Culture(pre: ["Ae", "Ili", "Quo", "Zer", "Am", "Ere", "Oru", "Syl", "Ith", "Ura"], mid: ["n", "l", "th", "r", "v", "sh"], suf: ["a", "is", "or", "eth", "iel", "um", "ae", "on", "ys"]),
    "morgen": Culture(pre: ["Sa", "Ha", "Ka", "Ra", "Zu", "Ba", "Na", "Ta", "Fa", "Ja"], mid: ["ri", "li", "mi", "sa", "la", "dir"], suf: ["m", "d", "ra", "fa", "il", "an", "ud", "ira", "eh"]),
  ]
  public static let banned: Set<String> = ["marta", "ida", "bork", "jaro", "aether", "tom", "jaros", "grauweiler", "wirtin", "wirt", "du", "dir", "niemand"]   // names used in few-shots / UI tests
  public private(set) var used: Set<String>
  let rand: (Int) -> Int
  public init(used: Set<String> = [], rand: @escaping (Int) -> Int) { self.used = used; self.rand = rand }

  /// Culture from the world slots (ton / ortTyp / epoche keywords); default "dunkel".
  public static func culture(for slots: String) -> String {
    let s = slots.lowercased()
    if ["nord", "fjord", "insel", "hafen", "eis", "wikinger"].contains(where: s.contains) { return "nord" }
    if ["wüste", "oase", "basar", "morgen"].contains(where: s.contains) { return "morgen" }
    if ["antik", "elf", "uralt", "kloster", "alt"].contains(where: s.contains) { return "alt" }
    return "dunkel"
  }
  /// A fresh, unique name. `reserve` = names to avoid in addition to the used set.
  public mutating func next(culture: String = "dunkel", avoid: Set<String> = []) -> String {
    let c = Self.cultures[culture] ?? Self.cultures["dunkel"]!
    for _ in 0..<80 {
      var n = c.pre[rand(c.pre.count)]
      if rand(3) == 0 { n += c.mid[rand(c.mid.count)] }
      n += c.suf[rand(c.suf.count)]
      n = n.prefix(1).uppercased() + n.dropFirst().lowercased()
      let k = n.lowercased()
      if n.count >= 4, n.count <= 11, !used.contains(k), !Self.banned.contains(k), !avoid.contains(k) { used.insert(k); return n }
    }
    // exhausted combinations: disambiguate with a deterministic suffix (never a number)
    var n = c.pre[rand(c.pre.count)] + c.suf[rand(c.suf.count)] + "ar"
    n = n.prefix(1).uppercased() + n.dropFirst().lowercased()
    while used.contains(n.lowercased()) { n += "e" }
    used.insert(n.lowercased()); return n
  }
  public mutating func reserve(_ n: String) { used.insert(n.lowercased()) }
}
