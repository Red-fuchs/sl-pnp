#!/usr/bin/env python3
"""Drives one running `sl web --rules schicksal --chargen X` through character creation for every persona JSON.
usage: chargen_run.py PORT MODE PERSONA_DIR OUT_DIR
Per persona: /figur -> wishes -> (a,b: /merkmal + /budget with fallback) | (c,bc: /wunsch + /pruefen [+ Einwand] + /annehmen alle). Writes OUT_DIR/MODE/<id>.json (transcript, timings, sheet)."""
import sys, json, time, threading, glob, os, http.client, re

port, mode, pdir, out = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
os.makedirs(f"{out}/{mode}", exist_ok=True)
ev, lock = [], threading.Lock()

def sse():
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=3600)
    c.request("GET", "/events"); r = c.getresponse(); buf = b""
    while True:
        ch = r.read(1)
        if not ch: break
        buf += ch
        if buf.endswith(b"\n\n"):
            for l in buf.decode("utf8", "replace").splitlines():
                if l.startswith("data: "):
                    try:
                        with lock: ev.append((time.time(), json.loads(l[6:])))
                    except Exception: pass
            buf = b""
threading.Thread(target=sse, daemon=True).start()

def req(method, path, body=None):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=600)
    h = {"x-sl": "1", "content-type": "application/json"}
    c.request(method, path, json.dumps(body) if body is not None else None, h)
    r = c.getresponse(); d = r.read(); return r.status, d

def say(speaker, text, timeout=900):
    """send a line, wait until the server is idle again; returns (seconds, info texts)"""
    with lock: n0 = len(ev)
    t0 = time.time(); st, _ = req("POST", "/say", {"text": text, "speaker": speaker})
    seen_busy = False
    while time.time() - t0 < timeout:
        time.sleep(0.25)
        with lock: new = ev[n0:]
        for _, e in new:
            if e.get("t") == "state" and e.get("busy") is True: seen_busy = True
            if e.get("t") == "state" and e.get("busy") is False and (seen_busy or time.time() - t0 > 3):
                infos = [e2.get("text", "") for _, e2 in new if e2.get("t") in ("info", "world", "event")]
                return time.time() - t0, infos, [e2 for _, e2 in new]
    return time.time() - t0, ["TIMEOUT"], []

def sheet(speaker):
    _, d = req("GET", "/state"); s = json.loads(d)
    for p in s.get("party", []):
        if p.get("speaker") == speaker: return p
    return None

def mk(items): return ",".join(items)

for f in sorted(glob.glob(f"{pdir}/p[0-9][0-9].json")):
    P = json.load(open(f)); pid = P["id"]; W = P["wishes"]
    if os.path.exists(f"{out}/{mode}/{pid}.json"): continue
    steps = []; T0 = time.time()
    def step(cmd):
        t, infos, raw = say(pid, cmd); steps.append({"cmd": cmd, "sec": round(t, 1), "info": infos}); return infos
    step(f"/figur {P['name']}: {P['backstory']}")
    refusals = 0
    if mode in ("a", "b"):
        for t, m in W["plus"]: step(f"/merkmal +{t}" + (" major" if m == "major" else ""))
        for t, m in W["minus"]: step(f"/merkmal -{t}" + (" major" if m == "major" else ""))
        items = list(W["gear"]); sp = int(W.get("sp_extra", 0))
        for attempt in range(8):
            args = (f"item={mk(items)} " if items else "") + (f"sp={sp}" if sp else "")
            if not args.strip(): break
            r = step("/budget " + args.strip())
            if any(re.search(r"nur \d+ (Punkte|Taler) übrig", x) for x in r):
                refusals += 1
                if sp: sp -= 1
                elif items: items.pop()
                continue
            break
    else:
        for t, m in W["plus"]: step(f"/wunsch +{t}" + (" major" if m == "major" else ""))
        for t, m in W["minus"]: step(f"/wunsch -{t}" + (" major" if m == "major" else ""))
        for g in W["gear"]: step(f"/wunsch gegenstand {g}")
        if W.get("sp_extra"): step(f"/wunsch sp {int(W['sp_extra'])}")
        card = " ".join(step("/pruefen"))
        if re.search(r"nur mit|höherem Preis|abgelehnt|nicht erhältlich", card):
            step("/pruefen " + P["insist"])
        step("/annehmen alle")
    total = time.time() - T0
    json.dump({"persona": P, "mode": mode, "steps": steps, "total_sec": round(total, 1), "budget_refusals": refusals, "sheet": sheet(pid)}, open(f"{out}/{mode}/{pid}.json", "w"), ensure_ascii=False, indent=1)
    print(mode, pid, round(total, 1), "s", flush=True)
