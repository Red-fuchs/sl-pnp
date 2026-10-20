import Foundation

/// Hard content rule (not configurable, ignores player wishes): minors are never victims of violence and never part of sexual content.
/// Children may exist as ordinary NPCs. Deterministic check on generated world data and on narration; a hit is rejected and regenerated.
public let minorTopic = "minderjaehrige"
private let minorRe = try! NSRegularExpression(pattern: #"\b(kind|kinder\w*|kinde[sn]?|kindlein|kindern|knabe\w*|mädchen\w*|säugling\w*|baby\w*|babies|kleinkind\w*|waisenkind\w*|schulkind\w*|straßenkind\w*|jugendliche[nrms]?|halbwüchsig\w*|teenager\w*|neugeboren\w*|bübchen|göre\w*|bengel\w*|waisen\w*|\w{3,}jung(e|en)|\w+jährig\w*)\b|\b(der|ein|dem|den|kleine[rnms]?|junge[nrms]?) junge[n]?\b|\b(der|ein|dem|den|kleine[nrms]?) (junge|jungen)\b"#, options: .caseInsensitive)
private let harmRe = try! NSRegularExpression(pattern: #"\b(tot|tote[nrms]?|tod|todes\w*|töt\w*|sterb\w*|stirb\w*|starb|gestorben|leiche\w*|mord\w*|ermord\w*|erschl\w*|erstech\w*|erstach|erdolch\w*|erwürg\w*|erschie\w*|erschoss|ertränk\w*|ertrunk\w*|verbrenn\w*|verbrann\w*|schlag\w*|schlug|prügel\w*|quäl\w*|folter\w*|misshandel\w*|missbrauch\w*|vergewalt\w*|schänd\w*|entführ\w*|verstümmel\w*|blut\w*|verletz\w*|opfer\w*|geopfert|würg\w*|erstick\w*|hinricht\w*|abschlacht\w*|verhungert|gewalt\w*|ohrfeig\w*|züchtig\w*|verschleppt\w*|versklav\w*|sex\w*|nackt\w*|entkleid\w*|ausgezogen|erotik\w*|erotisch\w*|lüstern\w*|begehr\w*|verführ\w*|intim\w*|küss\w*|geil\w*|brüste\w*|busen|lust|stich\w*|stoß\w*|ramm\w*|durchbohr\w*|schlitz\w*|köpf\w*|enthaupt\w*|meuchel\w*|erdrossel\w*|erhäng\w*|umbring\w*|umgebracht|stech\w*|stach|geschlag\w*|geprügelt|getreten|gequält|gefoltert|gestochen|erdrosselt|gefesselt|geknebelt)\b"#, options: .caseInsensitive)
private func hit(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
public func hasMinor(_ s: String, names: [String] = []) -> Bool {
  if hit(minorRe, s) { return true }
  let l = s.lowercased(); return names.contains { l.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0.lowercased()) + "\\w{0,2}\\b", options: .regularExpression) != nil }
}
func hasHarm(_ s: String) -> Bool { hit(harmRe, s) }
private func pronounStart(_ s: String) -> Bool {
  let w = s.trimmingCharacters(in: .whitespaces).lowercased()
  return ["es ", "sie ", "er ", "das kleine", "der kleine", "die kleine", "das arme", "die arme", "der arme"].contains { w.hasPrefix($0) }
}
/// one sentence; `prevMinor` = the previous sentence was about a minor ("Ein Kind liegt am Boden. Es ist tot.")
public func minorHarm(sentence s: String, prevMinor: Bool = false, names: [String] = []) -> Bool { hasHarm(s) && (hasMinor(s, names: names) || (prevMinor && pronounStart(s))) }
public func minorHarm(_ text: String, names: [String] = []) -> Bool {
  var prev = false
  for s in sentences(of: text) { if minorHarm(sentence: s, prevMinor: prev, names: names) { return true }; prev = hasMinor(s, names: names) }
  return false
}
/// narration/tool text minus the offending sentences
public func dropMinorSentences(_ text: String, names: [String] = []) -> String {
  var prev = false, out: [String] = []
  for s in sentences(of: text) { let bad = minorHarm(sentence: s, prevMinor: prev, names: names); prev = hasMinor(s, names: names); if !bad { out.append(s) } }
  return out.joined().trimmingCharacters(in: .whitespaces)
}
/// text appended to the system prompts (narrator, world generation, director)
public let MINOR_RULE = "HARTE REGEL, unabhängig von jedem Spielerwunsch: Kinder und Jugendliche (Kind, Knabe, Mädchen, Säugling …) kommen nie als Opfer von Gewalt vor und nie in sexuellen Zusammenhängen. Sie dürfen als normale Figuren auftreten, bleiben aber unverletzt und unbedroht; lenke jede solche Richtung sofort um."

/// age statements: "Tom (9)", "Tom, 9 Jahre", "der neunjährige Tom", "Tom ist 12"
private let wordNums = ["zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "sechzehn": 16, "siebzehn": 17]
public func statedAge(_ text: String, name: String) -> Int? {
  let n = NSRegularExpression.escapedPattern(for: name)
  for pat in ["\\b\(n)\\s*[\\(,]\\s*(\\d{1,2})\\b", "\\b\(n),?\\s+(?:ist\\s+)?(\\d{1,2})\\s*(?:jahre|jährig)", "(\\d{1,2})[- ]?jährige[rn]?\\s+(?:\\w+\\s+)?\\(n)\\b"] {
    if let r = try? NSRegularExpression(pattern: pat, options: .caseInsensitive), let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let g = Range(m.range(at: 1), in: text), let a = Int(text[g]) { return a }
  }
  let l = text.lowercased()
  for (w, a) in wordNums where l.range(of: "\\b\(w)jährige[rn]?\\s+(\\w+\\s+)?\\(NSRegularExpression.escapedPattern(for: name.lowercased()))\\b", options: .regularExpression) != nil { return a }
  return nil
}
