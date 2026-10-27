import Foundation
import Network
import SLCore
import Schicksal

final class Hub {
  var conns: [NWConnection] = []
  let q = DispatchQueue(label: "hub")
  var recent: [Data] = []        // info/progress/world/tool events replayed to late joiners (a page reload used to lose them)
  func add(_ c: NWConnection) { q.async { self.recent.forEach { c.send(content: $0, completion: .contentProcessed { _ in }) }; self.conns.append(c) } }
  func send(_ o: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
    let b = Data("data: \(s)\n\n".utf8)
    q.async {
      if let t = o["t"] as? String, ["info", "world", "progress", "tool", "event"].contains(t) { self.recent.append(b); if self.recent.count > 30 { self.recent.removeFirst() } }
      for c in self.conns { c.send(content: b, completion: .contentProcessed { e in if e != nil { self.q.async { self.conns.removeAll { $0 === c } } } }) }
    }
  }
}

/// CORS: Foundry on localhost:30000 and its LAN host (private ranges, port 30000)
func allowedOrigin(_ o: String?) -> String? {
  guard let o, let u = URL(string: o), let host = u.host, u.port == 30000 || u.port == nil && false else { return nil }
  if host == "localhost" || host == "127.0.0.1" { return o }
  let p = host.split(separator: ".").compactMap { Int($0) }
  if p.count == 4, p[0] == 192 && p[1] == 168 || p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) { return o }
  return nil
}
func jsonOuts(_ o: Out) -> [[String: Any]] {
  switch o {
  case .delta(let d): return [["t": "delta", "d": d], ["t": "narr", "d": d]]
  case .end: return [["t": "end"], ["t": "narr_end"]]
  case .retract: return [["t": "retract"]]
  case .tool(let n, let a, let r):
    var m: [String: Any] = ["t": "tool", "name": n, "text": describe(n, a, r)]
    var extra: [[String: Any]] = []
    if n == "ask_oracle" || n == "start_scene" {
      let card: [String: Any] = ["tool": n, "q": a["q"].str ?? a["expect"].str ?? "", "answer": r["answer"].str ?? r["outcome"].str ?? "", "roll": r["roll"].int ?? -1,
                   "p": r["p"].int ?? -1, "s": r["s"].int ?? -1, "rng": r["rng"].str ?? "", "odds": a["odds"].int == nil ? "" : oddsLabel(a)]
      m["card"] = card
      if n == "ask_oracle" { extra.append(["t": "oracle", "q": card["q"]!, "answer": card["answer"]!, "odds": card["odds"]!, "p": card["p"]!, "roll": card["roll"]!]) }
    }
    return [m] + extra
  case .event(let e): return [["t": "event", "text": e]]
  case .info(let s): return [["t": "info", "text": s]]
  case .world(let w): return [["t": "world", "text": w]]
  case .progress(let t, let d, let n): return [["t": "progress", "text": t, "done": d ?? 0, "total": n ?? 0]]
  case .roll(let c): var j = c.json; j["t"] = "roll"; return [j]
  case .sheet: return [["t": "sheet"]]
  case .probe(let r): var j = r.json; j["t"] = "probe_request"; return [j]
  case .probeDone(let id, let how): return [["t": "probe_done", "id": id, "how": how]]
  case .gate: return []
  }
}

func state(_ r: Runner, busy: Bool) -> [String: Any] {
  guard let (s, _, rl) = r.snapshot() else { return ["t": "state", "busy": busy, "name": "-"] }
  let rolls: [[String: Any]] = rl.suffix(8).map { ["answer": $0["answer"].str ?? $0["outcome"].str ?? "", "roll": $0["roll"].int ?? -1, "p": $0["p"].int ?? -1, "s": $0["s"].int ?? -1, "rng": $0["rng"].str ?? ""] }
  return ["t": "state", "s": s.s, "scene": s.scene, "open": s.open, "q": s.q, "rng": s.rng, "akteure": s.akteure, "straenge": s.straenge, "journal": s.journal,
          "rolls": rolls, "figur": s.figur ?? "-", "welt": s.welt, "hier": s.hier, "busy": busy, "name": s.name]
}

func runWeb(runner: Runner, resuming: Bool, opt: [String: String]) async throws {
  let port = UInt16(opt["port"] ?? "8787") ?? 8787
  let idle = Double(opt["idle"] ?? (opt["lease"] != nil ? "300" : "600")) ?? 600
  let hub = Hub()
  if let t = opt["probe-timeout"].flatMap({ Double($0) }) { Game.probeDefault = max(0, t) }
  let work = DispatchQueue(label: "work")
  let lock = NSLock()
  var busy = false, last = Date()
  runner.sink = { o in for var j in jsonOuts(o) { if j["t"] as? String == "sheet" { j["party"] = runner.game?.partyJSON ?? [] }; hub.send(j) } }
  func snap() -> (Double, Bool) { lock.lock(); defer { lock.unlock() }; return (Date().timeIntervalSince(last), busy) }
  func touch() { lock.lock(); last = Date(); lock.unlock() }
  func job(_ f: @escaping () throws -> Bool) {
    lock.lock(); if busy { lock.unlock(); hub.send(["t": "info", "text": "SL denkt noch …"]); return }; busy = true; lock.unlock()
    hub.send(["t": "state", "busy": true])
    work.async {
      var cont = true
      do { cont = try f() } catch { hub.send(["t": "info", "text": "Fehler: \(error)"]) }
      lock.lock(); busy = false; lock.unlock(); touch()
      hub.send(state(runner, busy: false))
      if !cont { hub.send(["t": "bye"]); runner.lm.unload(); exit(0) }
    }
  }

  if resuming { try runner.resume() } else { try runner.startNew(setting: opt["setting"]) }

  let params = NWParameters.tcp
  params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
  let l = try NWListener(using: params)
  l.newConnectionHandler = { c in
    c.start(queue: .global())
    var buf = Data()
    func recv() {
      c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, done, e in
        if let d { buf.append(d) }
        if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
          let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
          let len = httpContentLength(head)   // negative / garbage -> 0 (a negative range crashed the slice)
          if len > 65536 { c.send(content: Data("HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in c.cancel() }); return }
          if buf.count - r.upperBound < len { if !done && e == nil { recv() }; return }
          handle(c, head, Data(buf[r.upperBound..<(r.upperBound + len)]))
        } else if !done && e == nil { recv() } else { c.cancel() }
      }
    }
    recv()
  }
  func reply(_ c: NWConnection, _ code: String, _ type: String, _ body: Data, origin: String? = nil) {
    var h = "HTTP/1.1 \(code)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n"
    if let o = origin { h += "Access-Control-Allow-Origin: \(o)\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: content-type, x-sl\r\n" }
    h += "\r\n"
    c.send(content: Data(h.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
  }
  func handle(_ c: NWConnection, _ head: String, _ body: Data) {
    touch()
    let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
    guard parts.count >= 2 else { return c.cancel() }
    let method = String(parts[0]), path = String(parts[1])
    let org = allowedOrigin(httpHeader(head, "origin"))
    func rep(_ code: String, _ type: String, _ body: Data) { reply(c, code, type, body, origin: org) }
    func json(_ code: String, _ o: Any) { rep(code, "application/json", (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)) }
    func bodyJSON() -> [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }
    // reject cross-origin browser posts (DNS-rebinding / CSRF guard): Host must be loopback
    func hdr(_ k: String) -> String? { httpHeader(head, k) }
    let hostName = (hdr("host") ?? "").replacingOccurrences(of: ":\(port)", with: "")
    guard ["127.0.0.1", "localhost", "[::1]"].contains(hostName) else { return rep("403 Forbidden", "text/plain", Data("host".utf8)) }
    // CSRF guard via custom header instead of Origin (browser extensions rewrite Origin): cross-site pages can't set x-sl without a CORS preflight, which we never answer
    if method == "POST", hdr("x-sl") != "1" {
      FileHandle.standardError.write(Data("403 x-sl fehlt (origin=\(hdr("origin") ?? "-"))\n".utf8))
      return rep("403 Forbidden", "text/plain", Data("x-sl".utf8))
    }
    if method == "OPTIONS" { return rep("204 No Content", "text/plain", Data()) }
    switch (method, path) {
    case ("POST", "/roll"):
      guard let j = bodyJSON(), let sp = j["speaker"] as? String, !sp.isEmpty else { return json("400 Bad Request", ["error": "speaker fehlt"]) }
      let pillar = (j["pillar"] as? String ?? "kampf").lowercased()
      guard ["kampf", "sozial", "wissen"].contains(pillar) else { return json("400 Bad Request", ["error": "pillar: kampf|sozial|wissen"]) }
      guard let g = runner.game else { return json("503 Service Unavailable", ["error": "kein Spiel"]) }
      let pid = j["id"] as? String
      if let pid, let bad = g.probeProblem(pid, speaker: sp) { return json("409 Conflict", bad) }
      let ch = g.doCheck(speaker: sp, pillar: pillar, traits: j["traits"] as? [String] ?? [], difficulty: j["difficulty"] as? Int ?? 0, sp: j["sp"] as? Int ?? 0, reason: j["reason"] as? String ?? "", ergeben: j["ergeben"] as? Bool ?? false)
      if let e = ch.error { return json(ch.errCode == 409 ? "409 Conflict" : "400 Bad Request", ["error": e]) }
      if let pid, !g.probes.resolve(pid, ch) { g.queueFact(ch.fact) }
      json("200 OK", ch.json)
    case ("POST", "/rollresult"):
      guard let j = bodyJSON(), let sp = j["speaker"] as? String, let t = j["target"] as? Int, let r = j["roll"] as? Int, let g = runner.game else { return json("400 Bad Request", ["error": "speaker, label, target, roll"]) }
      let erg = j["ergeben"] as? Bool ?? false
      if erg, (j["sp"] as? Int ?? 0) > 0 { return json("400 Bad Request", ["error": "Schicksalsergeben ist nicht kombinierbar mit Schicksalspunkten."]) }
      let pid = j["id"] as? String
      if let pid, let bad = g.probeProblem(pid, speaker: sp) { return json("409 Conflict", bad) }
      let ch = g.foundryRoll(speaker: sp, label: j["label"] as? String ?? "Probe", target: t, roll: r, ergeben: erg, difficulty: j["difficulty"] as? Int ?? 0, probe: pid)
      if let e = ch.error { return json(ch.errCode == 409 ? "409 Conflict" : ch.errCode == 404 ? "404 Not Found" : "400 Bad Request", ["error": e]) }
      json("200 OK", ["success": ch.success, "dos": ch.dos, "dof": ch.dof, "crit": ch.crit as Any? ?? NSNull(), "label": ch.reason, "ergeben": ch.ergeben, "sp_gained": ch.spGained, "sp_left": ch.spLeft, "probe": pid as Any? ?? NSNull()])
    case ("POST", "/probe/auto"):      // GM: "sl würfeln lassen"
      guard let j = bodyJSON(), let id = j["id"] as? String, let g = runner.game else { return json("400 Bad Request", ["error": "id fehlt"]) }
      if g.probes.forceAuto(id) { json("200 OK", ["ok": true]) } else { json("409 Conflict", ["error": "Probe nicht mehr offen", "stale": true]) }
    case ("POST", "/regie"):
      guard let j = bodyJSON(), let t = j["text"] as? String, !t.isEmpty, let g = runner.game else { return json("400 Bad Request", ["error": "text fehlt"]) }
      g.partyStore.lock.lock(); g.pendingRegie.append(clean(t, 300)); g.partyStore.lock.unlock()
      json("202 Accepted", ["ok": true])
    case ("POST", "/spannung"):      // GM: {"set": N} | {"delta": ±N} | {"text": "+2"}; every change goes to the narrator as a hidden cue
      guard let j = bodyJSON(), let g = runner.game else { return json("400 Bad Request", ["error": "set|delta|text"]) }
      let arg = (j["set"] as? Int).map(String.init) ?? (j["delta"] as? Int).map { $0 >= 0 ? "+\($0)" : "\($0)" } ?? (j["text"] as? String) ?? ""
      g.partyStore.lock.lock(); let r = try? runner.spannung(arg); g.partyStore.lock.unlock()
      guard let r, r.ok else { return json("400 Bad Request", ["error": "set N | delta ±N | text '+N'|'-N'|'N' (1-9)"]) }
      hub.send(state(runner, busy: snap().1)); json("200 OK", ["ok": true, "s_before": r.before, "s": r.now])
    case ("POST", "/wunden"), ("POST", "/lp"):
      guard let j = bodyJSON(), let sp = j["speaker"] as? String, j["delta"] is Int || j["set"] is Int, let g = runner.game else { return json("400 Bad Request", ["error": "speaker und delta|set"]) }
      guard let res = g.partyStore.wunden(speaker: sp, delta: j["delta"] as? Int, set: j["set"] as? Int) else { return json("404 Not Found", ["error": "unbekannter speaker"]) }
      g.announceSheet(); json("200 OK", res)
    case ("POST", "/taler"), ("POST", "/gegenstand"), ("POST", "/kauf"):      // GM bookkeeping; every success emits `sheet`
      guard let j = bodyJSON(), let sp = j["speaker"] as? String, let g = runner.game else { return json("400 Bad Request", ["error": "speaker fehlt"]) }
      guard g.isSchicksal else { return json("409 Conflict", ["error": "nur unter --rules schicksal"]) }
      guard let i = g.pcIndex(sp, create: false) else { return json("404 Not Found", ["error": "unbekannter speaker"]) }
      func amount(_ k: String) -> Int? { if let h = j[k + "_h"] as? Int { return h }; if let s = j[k] as? String { return Geld.parse(s) }; return (j[k] as? Int).map { $0 * 4 } }
      let r: (ok: Bool, msg: String)
      switch path {
      case "/taler":
        if let d = j["delta_h"] as? Int { r = g.applyTaler(i, delta: d) }
        else if let s = (j["betrag"] as? String)?.trimmingCharacters(in: .whitespaces), let f = s.first, f == "+" || f == "-", let h = Geld.parse(String(s.dropFirst())) { r = g.applyTaler(i, delta: f == "-" ? -h : h) }
        else { return json("400 Bad Request", ["error": SR.taler_usage]) }
      case "/gegenstand":
        let add = j["add"] as? String, rem = j["remove"] as? String
        guard (add == nil) != (rem == nil) else { return json("400 Bad Request", ["error": SR.gegenstand_usage]) }
        r = g.applyGegenstand(i, add: add, remove: rem)
      default:
        guard let ware = j["ware"] as? String, let h = amount("preis") else { return json("400 Bad Request", ["error": SR.kauf_usage]) }
        r = g.applyKauf(i, ware: ware, preis: h)
      }
      runner.sink(.info(r.msg))
      let pc = g.partyStore.all[i]
      json(r.ok ? "200 OK" : "409 Conflict", ["ok": r.ok, "message": r.msg, "name": pc.name, "heller": pc.heller, "taler": pc.taler, "geld": pc.geld, "inventar": pc.inventar] as [String: Any])
    case ("POST", "/sp"):
      guard let j = bodyJSON(), let sp = j["speaker"] as? String, let d = j["delta"] as? Int, let g = runner.game else { return json("400 Bad Request", ["error": "speaker, delta"]) }
      guard let res = g.applySP(speaker: sp, delta: d, target: j["target"] as? String, mode: j["mode"] as? String) else { return json("404 Not Found", ["error": "unbekannter speaker"]) }
      json((res["error"] != nil) ? "409 Conflict" : "200 OK", res)
    case ("GET", "/"): rep("200 OK", "text/html; charset=utf-8", Data(pageHTML.utf8))
    case ("GET", "/favicon.ico"): rep("204 No Content", "image/x-icon", Data())
    case ("GET", "/state"):
      lock.lock(); let b = busy; lock.unlock()
      var st = state(runner, busy: b)
      st["story"] = runner.snapshot()?.1 ?? []
      st["party"] = runner.game?.partyJSON ?? []
      rep("200 OK", "application/json", (try? JSONSerialization.data(withJSONObject: st)) ?? Data())
    case ("GET", "/events"):
      let cors = org.map { "Access-Control-Allow-Origin: \($0)\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: content-type, x-sl\r\n" } ?? ""
      let h = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\(cors)\r\n: ok\n\n"
      c.send(content: Data(h.utf8), completion: .contentProcessed { _ in }); hub.add(c)
    case ("POST", "/say"):
      let sayJ = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
      let text = String((sayJ?["text"] as? String ?? "").prefix(2000)), spk = (sayJ?["speaker"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      rep("202 Accepted", "text/plain", Data("ok".utf8))
      runner.game?.probeWait = (sayJ?["probe_timeout"] as? NSNumber)?.doubleValue      // bridge setting; absent = sl flag
      if !text.trimmingCharacters(in: .whitespaces).isEmpty {
        if !text.hasPrefix("/regie"), !text.hasPrefix("/spannung"), !text.hasPrefix("/item") { hub.send(["t": "user", "text": text, "speaker": spk ?? ""]) }     // GM notes are never echoed
        if Cmd.parse(text) == .quit { hub.send(["t": "info", "text": "/quit beendet nur die CLI – den Web-Server beendest du im Terminal (Ctrl-C)."]) }   // never kill the server over HTTP
        else { job { try runner.handle(text, speaker: spk) } }
      }
    default: rep("404 Not Found", "text/plain", Data("nope".utf8))
    }
  }
  l.start(queue: .global())
  FileHandle.standardError.write(Data("sl web: http://127.0.0.1:\(port)/  (Leerlauf \(Int(idle)) s -> Modell entladen\(opt["lease"] != nil ? ", GPU-Slot frei, nächster Zug lädt neu" : ", Prozess endet"))\n".utf8))
  while true {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    let (idleFor, b) = snap()
    if opt["lease"] != nil {   // leased: unload the model + release the gpu-run slot when idle, keep serving; the next turn re-queues
      if !b && idleFor > idle && runner.lm.loaded {
        lock.lock(); let go = !busy; if go { busy = true }; lock.unlock()
        if go { work.async { runner.idleUnload(); lock.lock(); busy = false; last = Date(); lock.unlock(); hub.send(["t": "state", "busy": false]) } }
      }
      continue
    }
    if !b && idleFor > idle {
      hub.send(["t": "bye"]); FileHandle.standardError.write(Data("Leerlauf: Modell entladen, Ende\n".utf8))
      runner.lm.unload(); try? await Task.sleep(nanoseconds: 300_000_000); return
    }
  }
}

let pageHTML = #"""
<!doctype html><html lang="de" data-theme="dark"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>sl</title>
<style>
:root{--bg:#111318;--fg:#d9d6cf;--mut:#8a8780;--card:#1b1e25;--bd:#2c303a;--ac:#c0553a;--ok:#6aa56a;--no:#c0553a}
:root[data-theme=light]{--bg:#f4f1ea;--fg:#23201b;--mut:#6f6a60;--card:#fffdf8;--bd:#d8d2c4;--ac:#9c3b24;--ok:#3d7a3d;--no:#9c3b24}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 Georgia,serif;height:100vh;display:flex;flex-direction:column}
header{display:flex;justify-content:space-between;align-items:center;padding:8px 16px;border-bottom:1px solid var(--bd)}
header b{letter-spacing:.2em}button{background:var(--card);color:var(--fg);border:1px solid var(--bd);border-radius:6px;padding:6px 12px;font:inherit;cursor:pointer}
main{flex:1;display:grid;grid-template-columns:1fr 300px;min-height:0}
#col{display:flex;flex-direction:column;min-height:0;border-right:1px solid var(--bd)}
#story{flex:1;overflow:auto;padding:16px 16px 8px}
.sl{margin:0 0 1em;max-width:46em}.me{margin:0 0 1em;color:var(--ac);font-style:italic;max-width:46em}.me:before{content:"› "}
.tool,.ev,.inf{font:12px/1.4 ui-monospace,monospace;color:var(--mut);margin:-.4em 0 .8em}.ev{color:var(--ac)}
form{display:flex;gap:8px;padding:12px 16px;border-top:1px solid var(--bd)}input{flex:1;background:var(--card);color:var(--fg);border:1px solid var(--bd);border-radius:6px;padding:8px 10px;font:inherit}
aside{overflow:auto;padding:12px 16px;font-size:14px}aside h3{margin:14px 0 6px;font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--mut)}
.big{font-size:34px;line-height:1}.bar{height:6px;background:var(--bd);border-radius:3px;margin-top:6px}.bar i{display:block;height:100%;background:var(--ac);border-radius:3px}
.c{background:var(--card);border:1px solid var(--bd);border-radius:6px;padding:6px 8px;margin-bottom:6px;font-size:13px}.c b.ja{color:var(--ok)}.c b.nein{color:var(--no)}.c small{color:var(--mut);display:block}
li{margin-bottom:4px}ul{padding-left:16px;margin:0}.busy{opacity:.6}
@media(max-width:760px){main{grid-template-columns:1fr}aside{display:none}}
</style></head><body>
<header><b>SL</b><span id="nm" style="color:var(--mut);font-size:13px"></span><button id="th" type="button">hell/dunkel</button></header>
<main><div id="col"><div id="story"></div>
<form id="f"><input id="in" autocomplete="off" placeholder="Was tust du?  (/ende  /frage+1 …  /figur …  /status  /neu)" autofocus><button>Senden</button></form></div>
<aside><h3>Spannung</h3><div class="big" id="s">–</div><div class="bar"><i id="sb" style="width:0"></i></div>
<h3>Spielfigur</h3><div id="fg">–</div><h3>Hier</h3><div id="hier"></div><h3>Welt</h3><pre id="wt" style="white-space:pre-wrap;font:12px/1.4 ui-monospace,monospace;margin:0">–</pre><h3>Szene</h3><div id="sc">–</div><h3>Zufallsquelle</h3><div id="rng">–</div>
<h3>Würfe</h3><div id="rolls"></div><h3>Journal</h3><ul id="jr"></ul></aside></main>
<script>
const $=i=>document.getElementById(i),story=$('story');let cur=null;
function setTheme(t){document.documentElement.dataset.theme=t;try{localStorage.setItem('sl-theme',t)}catch(e){}}
try{const t=localStorage.getItem('sl-theme');if(t)setTheme(t)}catch(e){}
$('th').onclick=()=>setTheme(document.documentElement.dataset.theme=='dark'?'light':'dark');
function add(c,t){const p=document.createElement('p');p.className=c;p.textContent=t;story.appendChild(p);story.scrollTop=story.scrollHeight;return p}
function cls(a){return /^JA/.test(a)||a=='erwartet'?'ja':'nein'}
function render(s){if(s.s!==undefined){$('s').textContent=s.s;$('sb').style.width=(s.s*100/9)+'%'}
 if(s.scene!==undefined){$('sc').textContent='Szene '+s.scene+(s.open?' (offen)':'')+' · Fragen '+s.q+'/6'}
 if(s.hier){const h=$('hier');h.innerHTML='';s.hier.forEach(n=>{const b=document.createElement('button');b.type='button';b.textContent='💬 '+n;b.style.margin='0 6px 6px 0';b.onclick=()=>fetch('/say',{method:'POST',headers:{'x-sl':'1'},body:JSON.stringify({text:'/gespraech '+n})});h.appendChild(b)})}
 if(s.figur!==undefined)$('fg').textContent=s.figur; if(s.welt!==undefined)$('wt').textContent=s.welt||'noch leer'; if(s.rng)$('rng').textContent=s.rng; if(s.name)$('nm').textContent=s.name;
 if(s.rolls){$('rolls').innerHTML='';s.rolls.slice().reverse().forEach(r=>$('rolls').appendChild(card(r)))}
 if(s.journal){$('jr').innerHTML='';s.journal.forEach(j=>{const l=document.createElement('li');l.textContent=j;$('jr').appendChild(l)})}
 if(s.busy!==undefined){document.body.classList.toggle('busy',s.busy)}}
function card(r){const d=document.createElement('div');d.className='c';const b=document.createElement('b');b.className=cls(r.answer);b.textContent=r.answer;d.append(b);
 const sm=document.createElement('small');sm.textContent=(r.q?r.q+' · ':'')+(r.odds?r.odds+' · ':'')+(r.roll>=0?'W100 '+r.roll+(r.p>=0?' / '+r.p:''):'')+' · '+r.rng;d.append(sm);return d}
fetch('/state').then(r=>r.json()).then(s=>{(s.story||[]).forEach(m=>add(m.who,m.text));render(s);if(!(s.story||[]).length&&(s.figur===undefined||s.figur==='-'))add('inf','Wer bist du? /figur Name: Beschreibung – oder einfach losspielen, dann erfinde ich dich.')});
const es=new EventSource('/events');
es.onmessage=e=>{const m=JSON.parse(e.data);
 if(m.t=='delta'){if(!cur)cur=add('sl','');cur.textContent+=m.d;story.scrollTop=story.scrollHeight}
 else if(m.t=='end'){cur=null}
 else if(m.t=='retract'){if(cur){cur.remove();cur=null}}
 else if(m.t=='tool'){cur=null;add('tool',m.text);if(m.card){const r=document.createElement('div');}}
 else if(m.t=='event')add('ev','⚡ '+m.text);
 else if(m.t=='world')add('ev','🌍 '+m.text);
 else if(m.t=='progress'){if(!window.pg){window.pg=add('inf','')}window.pg.textContent='['+m.done+'/'+m.total+'] '+m.text;if(m.done>=m.total&&m.total>0)window.pg=null}
 else if(m.t=='info')add('inf',m.text);
 else if(m.t=='user'){cur=null;add('me',m.text)}
 else if(m.t=='state'){if(m.s===undefined)render(m);else render(m)}
 else if(m.t=='bye')add('inf','Leerlauf – Modell entladen, Server beendet. Mit --resume neu starten.')};
$('f').onsubmit=e=>{e.preventDefault();const t=$('in').value.trim();if(!t)return;$('in').value='';fetch('/say',{method:'POST',headers:{'x-sl':'1'},body:JSON.stringify({text:t})})};
</script></body></html>
"""#
