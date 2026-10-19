import Foundation
import Network
import SLCore
import Schicksal

final class Hub {
  var conns: [NWConnection] = []
  let q = DispatchQueue(label: "hub")
  func add(_ c: NWConnection) { q.async { self.conns.append(c) } }
  func send(_ o: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
    let b = Data("data: \(s)\n\n".utf8)
    q.async {
      for c in self.conns { c.send(content: b, completion: .contentProcessed { e in if e != nil { self.q.async { self.conns.removeAll { $0 === c } } } }) }
    }
  }
}

func jsonOut(_ o: Out) -> [String: Any]? {
  switch o {
  case .delta(let d): return ["t": "delta", "d": d]
  case .end: return ["t": "end"]
  case .tool(let n, let a, let r):
    var m: [String: Any] = ["t": "tool", "name": n, "text": describe(n, a, r)]
    if n == "ask_oracle" || n == "start_scene" {
      m["card"] = ["tool": n, "q": a["q"].str ?? a["expect"].str ?? "", "answer": r["answer"].str ?? r["outcome"].str ?? "", "roll": r["roll"].int ?? -1,
                   "p": r["p"].int ?? -1, "s": r["s"].int ?? -1, "rng": r["rng"].str ?? "", "odds": a["odds"].int.map { oddsText($0) } ?? ""] as [String: Any]
    }
    return m
  case .event(let e): return ["t": "event", "text": e]
  case .info(let s): return ["t": "info", "text": s]
  case .gate: return nil
  }
}

func state(_ r: Runner, busy: Bool) -> [String: Any] {
  guard let (s, _, rl) = r.snapshot() else { return ["t": "state", "busy": busy, "name": r.session.name] }
  let rolls: [[String: Any]] = rl.suffix(8).map { ["answer": $0["answer"].str ?? $0["outcome"].str ?? "", "roll": $0["roll"].int ?? -1, "p": $0["p"].int ?? -1, "s": $0["s"].int ?? -1, "rng": $0["rng"].str ?? ""] }
  return ["t": "state", "s": s.s, "scene": s.scene, "open": s.open, "q": s.q, "rng": s.rng, "akteure": s.akteure, "straenge": s.straenge, "journal": s.journal,
          "rolls": rolls, "figur": s.figur ?? "-", "busy": busy, "name": r.session.name]
}

func runWeb(runner: Runner, resuming: Bool, opt: [String: String]) async throws {
  let port = UInt16(opt["port"] ?? "8787") ?? 8787
  let idle = Double(opt["idle"] ?? "600") ?? 600
  let hub = Hub()
  let work = DispatchQueue(label: "work")
  let lock = NSLock()
  var busy = false, last = Date()
  runner.sink = { o in if let j = jsonOut(o) { hub.send(j) } }
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
          let len = httpHeader(head, "content-length").flatMap { Int($0) } ?? 0
          if buf.count - r.upperBound < len { if !done && e == nil { recv() }; return }
          handle(c, head, Data(buf[r.upperBound..<(r.upperBound + len)]))
        } else if !done && e == nil { recv() } else { c.cancel() }
      }
    }
    recv()
  }
  func reply(_ c: NWConnection, _ code: String, _ type: String, _ body: Data) {
    let h = "HTTP/1.1 \(code)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
    c.send(content: Data(h.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
  }
  func handle(_ c: NWConnection, _ head: String, _ body: Data) {
    touch()
    let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
    guard parts.count >= 2 else { return c.cancel() }
    let method = String(parts[0]), path = String(parts[1])
    // reject cross-origin browser posts (DNS-rebinding / CSRF guard): Host must be loopback
    func hdr(_ k: String) -> String? { httpHeader(head, k) }
    let hostName = (hdr("host") ?? "").replacingOccurrences(of: ":\(port)", with: "")
    guard ["127.0.0.1", "localhost", "[::1]"].contains(hostName) else { return reply(c, "403 Forbidden", "text/plain", Data("host".utf8)) }
    if let o = hdr("origin"), !["http://127.0.0.1:\(port)", "http://localhost:\(port)"].contains(o) { return reply(c, "403 Forbidden", "text/plain", Data("origin".utf8)) }
    switch (method, path) {
    case ("GET", "/"): reply(c, "200 OK", "text/html; charset=utf-8", Data(pageHTML.utf8))
    case ("GET", "/state"):
      lock.lock(); let b = busy; lock.unlock()
      var st = state(runner, busy: b)
      st["story"] = runner.snapshot()?.1 ?? []
      reply(c, "200 OK", "application/json", (try? JSONSerialization.data(withJSONObject: st)) ?? Data())
    case ("GET", "/events"):
      let h = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n: ok\n\n"
      c.send(content: Data(h.utf8), completion: .contentProcessed { _ in }); hub.add(c)
    case ("POST", "/say"):
      let text = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["text"] as? String ?? ""
      reply(c, "202 Accepted", "text/plain", Data("ok".utf8))
      if !text.trimmingCharacters(in: .whitespaces).isEmpty {
        hub.send(["t": "user", "text": text])
        job { try runner.handle(text) }
      }
    default: reply(c, "404 Not Found", "text/plain", Data("nope".utf8))
    }
  }
  l.start(queue: .global())
  FileHandle.standardError.write(Data("sl web: http://127.0.0.1:\(port)/  (Leerlauf \(Int(idle)) s -> Modell entladen, Prozess endet)\n".utf8))
  while true {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    let (idleFor, b) = snap()
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
<h3>Spielfigur</h3><div id="fg">–</div><h3>Szene</h3><div id="sc">–</div><h3>Zufallsquelle</h3><div id="rng">–</div>
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
 if(s.figur!==undefined)$('fg').textContent=s.figur; if(s.rng)$('rng').textContent=s.rng; if(s.name)$('nm').textContent=s.name;
 if(s.rolls){$('rolls').innerHTML='';s.rolls.slice().reverse().forEach(r=>$('rolls').appendChild(card(r)))}
 if(s.journal){$('jr').innerHTML='';s.journal.forEach(j=>{const l=document.createElement('li');l.textContent=j;$('jr').appendChild(l)})}
 if(s.busy!==undefined){document.body.classList.toggle('busy',s.busy)}}
function card(r){const d=document.createElement('div');d.className='c';const b=document.createElement('b');b.className=cls(r.answer);b.textContent=r.answer;d.append(b);
 const sm=document.createElement('small');sm.textContent=(r.q?r.q+' · ':'')+(r.odds?r.odds+' · ':'')+(r.roll>=0?'W100 '+r.roll+(r.p>=0?' / '+r.p:''):'')+' · '+r.rng;d.append(sm);return d}
fetch('/state').then(r=>r.json()).then(s=>{(s.story||[]).forEach(m=>add(m.who,m.text));render(s)});
const es=new EventSource('/events');
es.onmessage=e=>{const m=JSON.parse(e.data);
 if(m.t=='delta'){if(!cur)cur=add('sl','');cur.textContent+=m.d;story.scrollTop=story.scrollHeight}
 else if(m.t=='end'){cur=null}
 else if(m.t=='tool'){add('tool',m.text);if(m.card){const r=document.createElement('div');}}
 else if(m.t=='event')add('ev','⚡ '+m.text);
 else if(m.t=='info')add('inf',m.text);
 else if(m.t=='user')add('me',m.text);
 else if(m.t=='state'){if(m.s===undefined)render(m);else render(m)}
 else if(m.t=='bye')add('inf','Leerlauf – Modell entladen, Server beendet. Mit --resume neu starten.')};
$('f').onsubmit=e=>{e.preventDefault();const t=$('in').value.trim();if(!t)return;$('in').value='';fetch('/say',{method:'POST',body:JSON.stringify({text:t})})};
</script></body></html>
"""#
