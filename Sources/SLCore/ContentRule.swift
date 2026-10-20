import Foundation

/// Hard content rule (not configurable, ignores player wishes): minors are never victims of violence and never part of sexual content.
/// Children may exist as ordinary NPCs. Deterministic check on generated world data and on narration; a hit is rejected and regenerated.
public let minorTopic = "minderjaehrige"
private let minorRe = try! NSRegularExpression(pattern: #"\b(kind|kinder\w*|kinde[sn]?|kindlein|kindern|knabe\w*|mädchen\w*|säugling\w*|baby\w*|babies|kleinkind\w*|waisenkind\w*|schulkind\w*|straßenkind\w*|jugendliche[nrms]?|halbwüchsig\w*|teenager\w*|neugeboren\w*|bübchen|göre\w*|bengel\w*)\b|\b(der|ein|dem|den|kleine[rnms]?|junge[nrms]?) junge[n]?\b|\b(der|ein|dem|den|kleine[nrms]?) (junge|jungen)\b"#, options: .caseInsensitive)
private let harmRe = try! NSRegularExpression(pattern: #"\b(tot|tote[nrms]?|tod|todes\w*|töt\w*|sterb\w*|stirb\w*|starb|gestorben|leiche\w*|mord\w*|ermord\w*|erschl\w*|erstech\w*|erstach|erdolch\w*|erwürg\w*|erschie\w*|erschoss|ertränk\w*|ertrunk\w*|verbrenn\w*|verbrann\w*|schlag\w*|schlug|prügel\w*|quäl\w*|folter\w*|misshandel\w*|missbrauch\w*|vergewalt\w*|schänd\w*|entführ\w*|verstümmel\w*|blut\w*|verletz\w*|opfer\w*|geopfert|würg\w*|erstick\w*|hinricht\w*|abschlacht\w*|verhungert|gewalt\w*|ohrfeig\w*|züchtig\w*|verschleppt\w*|versklav\w*|sex\w*|nackt\w*|entkleid\w*|ausgezogen|erotik\w*|erotisch\w*|lüstern\w*|begehr\w*|verführ\w*|intim\w*|küss\w*|geil\w*|brüste\w*|busen|lust|stich\w*|stoß\w*|geschlag\w*|geprügelt|getreten|gequält|gefoltert|gestochen|erdrosselt|gefesselt|geknebelt)\b"#, options: .caseInsensitive)
private func hit(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
public func hasMinor(_ s: String) -> Bool { hit(minorRe, s) }
func hasHarm(_ s: String) -> Bool { hit(harmRe, s) }
private func pronounStart(_ s: String) -> Bool {
  let w = s.trimmingCharacters(in: .whitespaces).lowercased()
  return ["es ", "sie ", "er ", "das kleine", "der kleine", "die kleine", "das arme", "die arme", "der arme"].contains { w.hasPrefix($0) }
}
/// one sentence; `prevMinor` = the previous sentence was about a minor ("Ein Kind liegt am Boden. Es ist tot.")
public func minorHarm(sentence s: String, prevMinor: Bool = false) -> Bool { hasHarm(s) && (hasMinor(s) || (prevMinor && pronounStart(s))) }
public func minorHarm(_ text: String) -> Bool {
  var prev = false
  for s in sentences(of: text) { if minorHarm(sentence: s, prevMinor: prev) { return true }; prev = hasMinor(s) }
  return false
}
/// narration/tool text minus the offending sentences
public func dropMinorSentences(_ text: String) -> String {
  var prev = false, out: [String] = []
  for s in sentences(of: text) { let bad = minorHarm(sentence: s, prevMinor: prev); prev = hasMinor(s); if !bad { out.append(s) } }
  return out.joined().trimmingCharacters(in: .whitespaces)
}
/// text appended to the system prompts (narrator, world generation, director)
public let MINOR_RULE = "HARTE REGEL, unabhängig von jedem Spielerwunsch: Kinder und Jugendliche (Kind, Knabe, Mädchen, Säugling …) kommen nie als Opfer von Gewalt vor und nie in sexuellen Zusammenhängen. Sie dürfen als normale Figuren auftreten, bleiben aber unverletzt und unbedroht; lenke jede solche Richtung sofort um."
