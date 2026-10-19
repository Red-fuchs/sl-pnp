import Foundation
import SLCore
import Schicksal

setvbuf(stdout, nil, _IOLBF, 0)
func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func die(_ s: String) -> Never { err(s); exit(2) }

var args = Array(CommandLine.arguments.dropFirst())
var web = false
if args.first == "web" { web = true; args.removeFirst() }
var opt: [String: String] = [:]
let flags: Set<String> = ["resume", "debug", "help", "no-gpu-check"]
var i = 0
while i < args.count {
  let a = args[i]; i += 1
  guard a.hasPrefix("--") else { die("unerwartet: \(a)") }
  let k = String(a.dropFirst(2))
  if k == "resume" { if i < args.count, !args[i].hasPrefix("--") { opt[k] = args[i]; i += 1 } else { opt[k] = "" } }
  else if flags.contains(k) { opt[k] = "1" }
  else { guard i < args.count else { die("--\(k) braucht einen Wert") }; opt[k] = args[i]; i += 1 }
}
if opt["help"] != nil {
  print("""
  sl [--resume [name]] [--name n] [--setting text] [--model dir|lfm] [--rng mic|jitter|seed:N] [--temp 0.7] [--idle 600] [--debug] [--input FILE|/dev/tty]
  sl web [--port 8787] [--idle 600] [same options]
  Befehle: /ende /figur <Beschreibung> /status /frage[+N|-N] <text> /neu [setting] /quit   (Ctrl-D beendet)
  Modell läuft über die GPU-Queue: ./play.sh [args] (gpu-run -n sl --ram 10 ...)
  """); exit(0)
}

func findModel() -> URL {
  if let m = opt["model"] {
    if m == "lfm" {
      let d = NSHomeDirectory() + "/AI-Model/models/LiquidAI/LFM2.5-2.6B-MLX-bf16"
      guard FileManager.default.fileExists(atPath: d) else { die("LFM2.5-2.6B-MLX-bf16 fehlt (\(d)); --model <dir> angeben") }
      return URL(fileURLWithPath: d)
    }
    return URL(fileURLWithPath: (m as NSString).expandingTildeInPath)
  }
  let base = NSHomeDirectory() + "/.cache/huggingface/hub/models--zecanard--gemma-4-E4B-it-ultra-uncensored-heretic-MLX-4bit-mixed_4_6/snapshots"
  guard let s = (try? FileManager.default.contentsOfDirectory(atPath: base))?.sorted().first else { die("Modell nicht gefunden (\(base)); --model <dir>") }
  return URL(fileURLWithPath: base + "/" + s)
}

// stdin: with gpu-run the child's stdin is /dev/null -> play.sh passes --input
if let p = opt["input"], let f = freopen(p, "r", stdin) { _ = f } else if opt["input"] != nil { die("--input nicht lesbar") }

let dim = "\u{1B}[2m", off = "\u{1B}[0m", bold = "\u{1B}[1m"
let rng = opt["rng"] ?? "mic"
let name = opt["name"] ?? (opt["resume"].flatMap { $0.isEmpty ? nil : $0 }) ?? (opt["resume"] != nil ? Session.latest() : nil) ?? { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return "sl-" + f.string(from: Date()) }()
let resuming = opt["resume"] != nil
let session: Session
do { session = try Session(name: name, mustExist: resuming) } catch { die("\(error)") }

err("Modell laden: \(findModel().lastPathComponent) …")
var lm: LM? = try await LM.load(dir: findModel())
err(String(format: "geladen in %.1fs", lm!.loadS))
let runner = Runner(lm: lm!, session: session, rng: rng)

func show(_ o: Out) {
  switch o {
  case .delta(let d): print(d, terminator: "")
  case .end: print("\n")
  case .tool(let n, let a, let r): print("\(dim)\(describe(n, a, r))\(off)")
  case .event(let e): print("\(dim)⚡ \(e)\(off)")
  case .gate(let l): if opt["debug"] != nil { print("\(dim)· \(l)\(off)") }
  case .info(let s): print("\(dim)\(s)\(off)")
  }
}
runner.sink = show
runner.debug = opt["debug"] != nil
if let t = opt["temp"], let v = Float(t) { runner.temp = v }

if web {
  try await runWeb(runner: runner, resuming: resuming, opt: opt)
  exit(0)
}

let t0 = Date()
if resuming { try runner.resume(); print("\(dim)Sitzung \(name) fortgesetzt (\(runner.game.msgs.count) Nachrichten)\(off)") }
else { try runner.startNew(setting: opt["setting"]); print("\(dim)Sitzung \(name) · Setting: \(runner.setting)\nBeschreibe deinen Auftakt (Szene 1 beginnt mit deinem ersten Zug).\(off)") }
if opt["debug"] != nil { err(String(format: "start %.1fs", Date().timeIntervalSince(t0))) }

func prompt() { print("\(bold)Du> \(off)", terminator: ""); fflush(stdout) }
/// stdin line reader with idle timeout (the GPU lock held by gpu-run must not be held by an idle prompt)
var inbuf = [UInt8]()
func readLineIdle(_ secs: Double) -> String? {
  while true {
    if let i = inbuf.firstIndex(of: 10) { let l = String(decoding: inbuf[..<i], as: UTF8.self); inbuf.removeSubrange(...i); return l }
    var p = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
    if poll(&p, 1, Int32(secs * 1000)) == 0 { print("\(dim)Leerlauf – Modell entladen. Weiter mit --resume \(name)\(off)"); return nil }
    var b = [UInt8](repeating: 0, count: 4096)
    let n = read(0, &b, 4096)
    if n <= 0 { if inbuf.isEmpty { return nil }; let l = String(decoding: inbuf, as: UTF8.self); inbuf = []; return l }
    inbuf += b[..<n]
  }
}
let idleSecs = Double(opt["idle"] ?? "600") ?? 600
prompt()
while let l = readLineIdle(idleSecs) {
  let t = l.trimmingCharacters(in: .whitespaces)
  if t.isEmpty { prompt(); continue }
  print()
  do { if !(try runner.handle(t)) { break } } catch { print("\(dim)Fehler: \(error)\(off)") }
    prompt()
}
print()
lm?.unload(); lm = nil
