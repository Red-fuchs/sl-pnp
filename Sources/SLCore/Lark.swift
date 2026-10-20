import Foundation

/// Printable ASCII + Latin-1 letters (no ×÷) + typographic punctuation. Positive base for every negated class: a `[^\n<]` also admitted
/// Tibetan/Devanagari tokens on ~95% of the steps.
let latinRanges: [ClosedRange<UInt32>] = [0x20...0x7E, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0xFF, 0x2013...0x2014, 0x2018...0x201E, 0x2026...0x2026, 0x00AB...0x00AB, 0x00BB...0x00BB]

private func classBody(_ rs: [ClosedRange<UInt32>]) -> String {
  func e(_ v: UInt32) -> String { let s = String(UnicodeScalar(v)!); return "\\^-]['".contains(s) || s == "\\" ? "\\" + s : s }
  return rs.map { $0.lowerBound == $0.upperBound ? e($0.lowerBound) : e($0.lowerBound) + "-" + e($0.upperBound) }.joined()
}
/// `[^abc]` -> positive class over `latinRanges` minus the excluded scalars. Only simple bodies (chars + \n \t \\ escapes); anything else stays.
func positiveClass(_ body: String) -> String? {
  var ex = Set<UInt32>(), it = Array(body.unicodeScalars)[...]
  while let c = it.popFirst() {
    if c == "\\" {
      guard let n = it.popFirst() else { return nil }
      switch n { case "n": ex.insert(10); case "t": ex.insert(9); case "r": ex.insert(13); case "\\", "]", "[", "-", "^", ".", "/", "(", ")", "*", "+", "?", "{", "}", "|", "$": ex.insert(n.value); default: return nil }
    } else if c == "-" || c == "[" { return nil } else { ex.insert(c.value) }
  }
  var rs = latinRanges
  for x in ex {
    rs = rs.flatMap { r -> [ClosedRange<UInt32>] in
      guard r.contains(x) else { return [r] }
      return (r.lowerBound < x ? [r.lowerBound...(x - 1)] : []) + (x < r.upperBound ? [(x + 1)...r.upperBound] : [])
    }
  }
  return "[" + classBody(rs) + "]"
}
/// Rewrites every simple negated class `[^...]` in a regex to its positive Latin equivalent.
func positivize(_ re: String) -> String {
  var out = "", i = re.startIndex
  while i < re.endIndex {
    let c = re[i]
    if c == "\\" { let n = re.index(after: i); out += re[i..<min(re.index(after: n), re.endIndex)]; i = min(re.index(after: n), re.endIndex); continue }
    if c == "[", re[re.index(after: i)...].hasPrefix("^"), let close = re[re.index(i, offsetBy: 2)...].firstIndex(of: "]"),
       let p = positiveClass(String(re[re.index(i, offsetBy: 2)..<close])) { out += p; i = re.index(after: close); continue }
    if c == "[" { // copy a positive class verbatim (its `]` / escapes must not confuse the scan)
      var j = re.index(after: i); out.append(c)
      while j < re.endIndex { let d = re[j]; out.append(d); j = re.index(after: j); if d == "\\", j < re.endIndex { out.append(re[j]); j = re.index(after: j) } else if d == "]" { break } }
      i = j; continue
    }
    out.append(c); i = re.index(after: i)
  }
  return out
}

/// Surface forms of a secret term as one regex alternation (substring match, so inflections are covered by the stem):
/// first letter either case, trailing -e/-n/-en/-er/-s/-es dropped, ä/ö/ü/ß also as ae/oe/ue/ss.
public func llgBanRegex(_ terms: [String]) -> String? {
  var alts = Set<String>()
  for t in terms.prefix(24) {
    var w = t.lowercased().filter { $0.isLetter }
    guard w.count >= 4 else { continue }
    for suf in ["ern", "en", "er", "es", "e", "n", "s"] where w.hasSuffix(suf) && w.count - suf.count >= 4 { w = String(w.dropLast(suf.count)); break }
    for v in [w, w.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe").replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")] {
      guard let f = v.first else { continue }
      let rest = regexEscape(String(v.dropFirst()))
      alts.insert(f.uppercased() == String(f) ? regexEscape(String(f)) + rest : "[\(f)\(f.uppercased())]" + rest)
    }
  }
  return alts.isEmpty ? nil : "(" + alts.sorted().joined(separator: "|") + ")"
}

/// G (xgrammar structural-tag builder) -> llguidance Lark, 1:1. Free-text regexes (unbounded tail) become named terminals with the ban attached.
struct LarkBuilder {
  var terms: [(name: String, def: String)] = []
  let banRe: String?
  init(ban: [String]) { banRe = llgBanRegex(ban) }
  static func lit(_ v: String) -> String {
    "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
  }
  static func re(_ v: String) -> String { "/" + positivize(v).replacingOccurrences(of: "/", with: "\\/") + "/" }
  /// unbounded repetition anywhere (`]*`, `]+`, `{n,}`): the terminal can carry free text, so the ban applies
  static func isFree(_ v: String) -> Bool { v.contains("]*") || v.contains("]+") || v.range(of: #"\{\d+,\}"#, options: .regularExpression) != nil }
  mutating func emit(_ g: G) -> String {
    switch g {
    case .s(let v): return Self.lit(v)
    case .re(let v):
      guard let b = banRe, Self.isFree(v) else { return Self.re(v) }
      let def = Self.re(v) + " & ~/(?s:.*)" + b.replacingOccurrences(of: "/", with: "\\/") + "(?s:.*)/"
      if let t = terms.first(where: { $0.def == def }) { return t.name }
      let n = "FREE\(terms.count)"; terms.append((n, def)); return n
    case .js(let v): return "%json " + v
    case .seq(let e):
      let p = e.filter { if case .s(let v) = $0, v.isEmpty { return false }; return true }.map { emit($0) }
      return p.isEmpty ? "\"\"" : "(" + p.joined(separator: " ") + ")"
    case .or(let e): return e.count == 1 ? emit(e[0]) : "(" + e.map { emit($0) }.joined(separator: " | ") + ")"
    }
  }
}
extension Grammar {
  /// Lark text; `ban` = secret terms that no free-text terminal may contain (across token boundaries)
  public func lark(ban: [String] = []) -> String {
    var b = LarkBuilder(ban: ban); let body = b.emit(g)
    return "start: " + body + "\n" + b.terms.map { "\($0.name): \($0.def)\n" }.joined()
  }
  public var lark: String { lark() }
}
