import Foundation

// Port of gm-loop/prompt.py (single source of truth). VERSION must match.

public struct Msg: Codable, Equatable { public var role: String; public var text: String
  public init(_ r: String, _ t: String) { role = r; text = t }
  public static func u(_ t: String) -> Msg { Msg("user", t) }
  public static func m(_ t: String) -> Msg { Msg("model", t) } }

/// Chat formats rendered by hand (gemma: the shipped template of the Heretic build hardcodes thinking + a date prefix;
/// lfm: always-reasoning ChatML -> every assistant turn, history and generation prompt, carries an empty <think></think>).
public enum Tmpl {
  case gemma, chatml
  public static func detect(dir: URL) -> Tmpl {
    let c = (try? String(contentsOf: dir.appendingPathComponent("config.json"), encoding: .utf8)) ?? ""
    return c.contains("\"lfm2") ? .chatml : .gemma
  }
  func role(_ r: String) -> String { self == .chatml && r == "model" ? "assistant" : r }
  func open(_ r: String) -> String { self == .gemma ? "<|turn>\(r)\n" : "<|im_start|>\(role(r))\n" }
  public var end: String { self == .gemma ? "<turn|>\n" : "<|im_end|>\n" }
  public var endTok: String { self == .gemma ? "<turn|>" : "<|im_end|>" }
  public var bos: String { self == .gemma ? "<bos>" : "<|startoftext|>" }
  /// generation prompt (model turn opener)
  public var gen: String { open("model") + (self == .chatml ? "<think></think>" : "") }
  public func turn(_ m: Msg) -> String {
    open(m.role) + (self == .chatml && m.role == "model" ? "<think></think>" : "") + m.text.trimmingCharacters(in: .whitespacesAndNewlines) + end
  }
  public func render(sys: String, _ msgs: [Msg]) -> String {
    bos + open("system") + sys.trimmingCharacters(in: .whitespacesAndNewlines) + end + msgs.map(turn).joined()
  }
}
public func render(sys: String, _ msgs: [Msg]) -> String { Tmpl.gemma.render(sys: sys, msgs) }
public func turnText(_ m: Msg) -> String { Tmpl.gemma.turn(m) }

public let defaultSetting = "dunkle Fantasy, verfluchtes Dorf Grauweiler"
public func setupMsg(_ setting: String) -> String { "Neues Abenteuer. Setting: \(setting). Beginne mit der ersten Szene: die Spielfigur erreicht den Ort des Geschehens." }

