#!/usr/bin/env python3
"""usage: chargen_metrics.py OUT_DIR  -> prints markdown tables (per mode summary, per persona) and writes OUT_DIR/metrics.json"""
import json, glob, os, sys, statistics as st
out = sys.argv[1]
WD = [("pistole",4),("gewehr",4),("arkebuse",4),("büchse",4),("schwert",3),("axt",3),("bogen",3),("armbrust",3),("säbel",3),("speer",3),("beil",3),("messer",2),("dolch",2),("knüppel",2),("keule",2),("stock",2)]
def wdmg(items):
    best = 1
    for it in items:
        l = it.lower()
        for k, d in WD:
            if k in l: best = max(best, d)
    return best
def arm(items):
    best = 0
    for it in items:
        l = it.lower()
        if any(k in l for k in ("platten", "vollplatte", "harnisch")): best = max(best, 3)
        elif any(k in l for k in ("ketten", "schuppen", "rüstung", "panzer")): best = max(best, 2)
        elif "leder" in l: best = max(best, 1)
    return best
rows = {}
for mode in ["a", "b", "c", "bc"]:
    for f in sorted(glob.glob(f"{out}/{mode}/p*.json")):
        d = json.load(open(f)); s = d["sheet"] or {}; P = d["persona"]
        tr = s.get("traits", []); pos = [t for t in tr if t["pos"]]; neg = [t for t in tr if not t["pos"]]
        bon = sorted([20 if t["kind"] == "major" else 10 for t in pos], reverse=True)
        clamp = mode in ("b", "bc")
        allfit = min(30, sum(bon[:2])) if clamp else sum(bon)
        pil = s.get("pillars", {}); bp = max(pil.values()) if pil else 0
        inv = s.get("inventar", [])
        r = dict(id=P["id"], type=P["type"], mode=mode, power=s.get("power"), pos=len(pos), major=sum(t["kind"] == "major" for t in pos), neg=len(neg),
                 paid=sum(1 for t in neg if not t.get("farbe")), farbe=sum(1 for t in neg if t.get("farbe")), teurer=sum(1 for t in pos if t.get("teurer")),
                 best_pillar=bp, best_single=bp + (bon[0] if bon else 0), best_all=bp + allfit, dmg=wdmg(inv), armour=arm(inv),
                 spmax=s.get("spMax"), taler=s.get("taler"), gear=inv, sec=d["total_sec"], refusals=d["budget_refusals"], steps=len(d["steps"]))
        rows[(mode, P["id"])] = r
json.dump([r for r in rows.values()], open(f"{out}/metrics.json", "w"), ensure_ascii=False, indent=1)
def grp(mode, typ): return [r for (m, _), r in rows.items() if m == mode and (typ is None or r["type"] == typ)]
print("| mode | n | mean power | power max | mean best_single | mean best_all | unerf. mean power | breaker mean power | gap breaker-unerf. | mean sec |")
print("|---|---|---|---|---|---|---|---|---|---|")
for m in ["a", "b", "c", "bc"]:
    g = grp(m, None)
    if not g: continue
    mean = lambda xs: round(st.mean(xs), 1) if xs else 0
    u = grp(m, "unerfahren"); b = grp(m, "breaker")
    print(f"| {m} | {len(g)} | {mean([r['power'] for r in g])} | {max(r['power'] for r in g)} | {mean([r['best_single'] for r in g])} | {mean([r['best_all'] for r in g])} | {mean([r['power'] for r in u])} | {mean([r['power'] for r in b])} | {round(mean([r['power'] for r in b]) - mean([r['power'] for r in u]), 1)} | {mean([r['sec'] for r in g])} |")
print("\n| persona | type | " + " | ".join(f"{m}: P / pos+/neg- / best_all / gear" for m in ["a","b","c","bc"]) + " |")
print("|---|---|" + "---|" * 4)
ids = sorted({i for (_, i) in rows})
for i in ids:
    cells = []
    for m in ["a", "b", "c", "bc"]:
        r = rows.get((m, i)); cells.append(f"{r['power']} / {r['pos']}+{r['neg']}-({r['farbe']}F) / {r['best_all']} / dmg{r['dmg']}ar{r['armour']}sp{r['spmax']} / {r['sec']}s" if r else "-")
    t = next(r["type"] for (m, j), r in rows.items() if j == i)
    print(f"| {i} | {t} | " + " | ".join(cells) + " |")
