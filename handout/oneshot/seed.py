#!/usr/bin/env python3
"""Writes worlds/weberin/{vorlage,world,hidden}.json from content.py."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import content as C
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'worlds', 'weberin')

def build():
    os.makedirs(OUT, exist_ok=True)
    npcs = []
    for (i, name, kurz, ort, h, w, an, gm) in C.NPCS:
        npcs.append({"id": i, "name": name, "kurz": kurz, "ort": ort, "anwesend": an, "haltung": h, "basis": h, "fest": True, "wunden": w, "gmFigur": gm, "zustand": [], "inventar": [], "bekannt": []})
    gen = {"mode": "vorlage", "slots": {"ton": "düster", "epoche": "mittelalterlich", "ort": "Sumpf", "bedrohung": "Verschwörung", "licht": "neblig", "muss": [], "nicht": []},
           "praemisse": C.SETTING, "alltag": "Aschekreis", "start": "Aschekreis", "szene": C.START_SZENE, "pcZiel": C.PC_ZIEL,
           "orte": {k: f"{v[0]} · herrscht: {v[1]}" for k, v in C.ORTE.items()}, "used": [n[1].lower() for n in C.NPCS], "wuerze": [], "motive": C.MOTIVE, "ready": True, "secs": {}}
    world = {"ort": "Aschekreis", "zustand": [], "inventar": [], "npcs": npcs, "orte": {k: v[0].split('.')[0] for k, v in C.ORTE.items()}, "beziehungen": [],
             "straenge": [{"titel": t, "stand": "", "stufe": "frage", "hinweise": []} for t, _ in C.STRAENGE], "nextId": 20, "turn": 0,
             "festeStraenge": [t for t, _ in C.STRAENGE], "regeln": "schicksal", "gen": gen, "neglectN": 8, "vorlage": "weberin", "eingriffe": 0}
    hidden = {"npcs": {n: {"geheimnis": g, "ziel": z, "gruppe": gr, "typ": t, "ref": r} for n, (g, z, gr, t, r) in C.HIDDEN.items()},
              "clues": [{"thread": t, "text": tx, "at": at, "found": False} for t, cl in C.STRAENGE for tx, at in cl],
              "pcGeheim": "Die Weberin hat über die Leihe nie ganz die Wahrheit gesagt.", "schwellen": [2, 4, 6], "stuckN": 8}
    vor = {"id": "weberin", "titel": "Fadenleihe (Die Weberin)", "setting": C.SETTING, "prompt": C.PROMPT, "stufen": C.STUFEN, "eingriff": C.EINGRIFF,
           "eingriffReset": 5, "start": 3, "auftakt": C.AUFTAKT, "fremdCue": C.FREMD_CUE}
    for n, d in (('world', world), ('hidden', hidden), ('vorlage', vor)):
        json.dump(d, open(os.path.join(OUT, n + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=2, sort_keys=True)
    print('ok', OUT)

if __name__ == '__main__':
    build()
