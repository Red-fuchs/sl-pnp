import Foundation

/// xgrammar structural-tag builder: whole output = one strict grammar.
func regexEscape(_ v: String) -> String { v.map { "\\.*+?()[]{}|^$/".contains($0) ? "\\\($0)" : String($0) }.joined() }

public indirect enum G {
  case s(String), re(String), js(String), seq([G]), or([G])
  var o: Any {
    switch self {
    case .s(let v):
      // xgrammar 0.1.30 compiles 2-byte UTF-8 (ä ö ü ß) in const_string to the wrong bytes (after "tr" only <0xE0> was allowed -> Tibetan glyphs).
      // Non-ASCII literals therefore go through the regex path, which handles UTF-8 correctly.
      if v.unicodeScalars.contains(where: { $0.value > 127 }) { return ["type": "regex", "pattern": regexEscape(v)] }
      return ["type": "const_string", "value": v]
    case .re(let v): return ["type": "regex", "pattern": v]
    case .js(let v): return ["type": "json_schema", "json_schema": try! JSONSerialization.jsonObject(with: Data(v.utf8))]
    case .seq(let e): return ["type": "sequence", "elements": e.filter { if case .s(let v) = $0, v.isEmpty { return false }; return true }.map(\.o)]
    case .or(let e): return e.count == 1 ? e[0].o : ["type": "or", "elements": e.map(\.o)]
    }
  }
}
public struct Grammar {
  public let g: G
  public init(_ g: G) { self.g = g }
  public var tag: String {
    let d = try! JSONSerialization.data(withJSONObject: ["type": "structural_tag", "format": g.o], options: [.sortedKeys, .withoutEscapingSlashes])
    return String(decoding: d, as: UTF8.self)
  }
}

/// Everything the grammar depends on for one decoding step (states of prompt.py v3).
public struct Gate {
  public var head = false          // first step of a player turn (Erwartung/Frage/Werkzeug)
  public var open = false          // scene open; false = head_scene (after "ja" ONLY start_scene)
  public var asks = 0              // oracle questions in this scene
  public var calls = 0             // tool calls in this player turn
  public var ans: String? = nil    // BIND: oracle answer JA+|JA|NEIN+|NEIN, fixed string in the grammar
  public var deut = false          // event/mutation shown by harness -> "Deutung:" line (or verwerfen)
  public var forceEnd = false      // /ende: head must call end_scene
  public var figurLine = false     // first turn of a session: head starts with "Spielfigur: <text>|-"
  public var mustAsk = false       // >=1 quiet turn in this scene: no narration-only head, ask the oracle (or end the scene)
  public var figurNames: [String] = []   // name candidates for the player character (from the name generator); the model picks one
  public var noAsk = false         // W-question via /frage: the oracle only answers yes/no -> no ask_oracle this turn
  public var needFigur = false     // no player character yet: the narration must end with a "Du: Name (Rolle, Merkmal)" slot
  public var selfQ = false         // self-question (wer bin ich ...): short narration, no oracle, no scene change
  public var endNarr = false       // /ende turn: narration allowed after end_scene (else start_scene only)
  public init() {}
}

// Unbounded repeats on purpose: xgrammar compile time explodes with {8,220} (80 s -> 0.3 s). Minimum lengths kept as short fixed prefixes.
public enum Gr {
  static let sent = #"[ ]?[^<.!?\n:]{6}[^<.!?\n:]*[.!?]["“”»«]?"#
  public static let narrPattern = "(\(sent)){3}(\(sent)){0,2}"   // 3-5 sentences
  public static let narrBody = G.re(narrPattern)
  static let shortPattern = "(\(sent))(\(sent)){0,2}"   // 1-3 sentences (self-questions)
  static func duSlot(_ names: [String]) -> G {   // the NAME is an enum of generated candidates (the 4B model kept evading with "dein Name ist dir unbekannt")
    .seq([names.isEmpty ? G.re(#"[A-ZÄÖÜ][a-zäöüß]{2,}"#) : GenGr.en(names), .s(" ("), .re(#"[^\n<)\[\]]{3}[^\n<)\[\]]*"#), .s(")")])
  }
  /// narration + mandatory tails: [Du: Name (Rolle, Merkmal) while no character exists] + "Figuren: Name (Rolle), …" | "-" (both stripped from display)
  public static func narrG(_ t: Gate) -> G {
    var p: [G] = [t.selfQ ? G.re(shortPattern) : narrBody]
    if t.needFigur { p += [.s("\nDu: "), duSlot(t.figurNames)] }
    p += [.s("\nFiguren: "), .or([.s("-"), .re(#"[^\n<]{2}[^\n<]*"#)])]
    return .seq(p)
  }
  public static let narr = narrG(Gate())
  static let line = #"[^\n<]{8}[^\n<]*"#
  public static let maxAsks = 6
  static let str = #"{"type":"string"}"#   // xgrammar sorts schema keys alphabetically -> key order is built by hand

  // `first:true` is injected by the harness (parseCall) for the very first scene; the model never writes it.
  static let startScene = G.seq([.s(#"<start_scene>{"expect":"#), .js(str), .s(#","el":{"ort":"#), .js(str), .s(#","beteiligte":"#), .js(str), .s("}}</start_scene>")])
  static let endScene = G.seq([.s(#"<end_scene>{"summary":"#), .js(str), .s(#","why":"#), .js(str), .s(#","control":"#), .re("true|false"),
    // optional list upkeep (akteure/straenge add) so [Bekannt] and targeted events come alive; prompt v3 does not teach it yet -> model rarely uses it
    .or([.s("}"), .seq([.s(#","akteure":[{"op":"add","name":"#), .js(str), .s("}]}")]), .seq([.s(#","straenge":[{"op":"add","name":"#), .js(str), .s("}]}")])]),
    .s("</end_scene>")])
  /// q is written by the model per the prompt but the harness overwrites it with the "Frage:" line.
  static let askCall = G.seq([.s(#"<ask_oracle>{"q":"#), .js(str), .s(#","odds":"#), .re("-[1-3]|[0-3]"), .s("}</ask_oracle>")])
  static let q = G.re(#"[^\-\n<][^\n<]{4}[^\n<]*"#)

  /// world-delta step: free-form JSON constrained to the delta schema (may be {})
  /// /gespraech: 1-2 lines of NPC speech + attitude delta (-1|0|+1)
  public static var talk: Grammar {
    let line = G.re(#"[^\n<]{8}[^\n<]*"#)
    let h = G.seq([.s("\nHaltung: "), .re(#"-1|0|\+1"#)])
    return Grammar(.seq([.s("Rede: "), line, .or([h, .seq([.s("\nRede: "), line, h])])]))
  }
  public static var delta: Grammar { Grammar(.js(DELTA_SCHEMA)) }

  static func canAsk(_ t: Gate) -> Bool { t.open && t.asks < maxAsks && !t.noAsk }

  public static func grammar(_ t: Gate) -> Grammar {
    if t.head {
      var hd: [G] = []
      if t.figurLine { hd += [.s("Spielfigur: "), .or([.re(#"[^\n<]{6}[^\n<]*"#), .s("-")]), .s("\n")] }
      hd += [.s("Erwartung: "), .re(#"[^\n<]{10}[^\n<]*"#), .s("\n")]
      let ja = G.s("Ortswechsel/Zeitsprung: ja\nFrage: -\nWerkzeug: ja\n")
      if !t.open { return Grammar(.seq(hd + [ja, startScene])) }                                   // head_scene: a new scene is a place/time change by definition
      if t.forceEnd { return Grammar(.seq(hd + [ja, endScene])) }
      // end_scene ONLY after "Ortswechsel/Zeitsprung: ja"; otherwise ask the oracle or narrate
      var br: [G] = [.seq([ja, endScene])]
      if t.selfQ { return Grammar(.seq(hd + [.s("Ortswechsel/Zeitsprung: nein\nFrage: -\nWerkzeug: nein\n"), narrG(t)])) }   // self-question: narration only
      if !t.mustAsk || !canAsk(t) { br.append(.seq([.s("Ortswechsel/Zeitsprung: nein\nFrage: -\nWerkzeug: nein\n"), narrG(t)])) }
      if canAsk(t) { br.append(.seq([.s("Ortswechsel/Zeitsprung: nein\nFrage: "), q, .s("\nWerkzeug: ja\n"), askCall])) }
      return Grammar(.seq(hd + [.or(br)]))
    }
    var parts: [G] = []
    if let a = t.ans { parts += [.s("Antwort: \(a) → "), .re(line), .s("\n")] }
    if t.deut { parts += [.s("Deutung: "), .or([.re(line), .s("verwerfen")]), .s("\n")] }
    if t.ans != nil || t.deut || t.open || t.calls >= 8 { parts.append(narrG(t)) }       // after ask / event / start_scene: narration
    else { parts.append(t.endNarr ? .or([narrG(t), startScene]) : startScene) }          // after end_scene: next step is start_scene
    return Grammar(.seq(parts))
  }
}
