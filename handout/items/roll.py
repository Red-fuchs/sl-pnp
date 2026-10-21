#!/usr/bin/env python3
"""Gegenstandsgenerator-Roller (stdlib). Liest items/data/*.json, Orakel + Wortpaare aus handout/tables.py.
  roll.py item [-n 5] [--selt ID] [--kat ID] [--name] [--json]
  roll.py haendler STUFE [--spez KAT] [--kontext grossstadt|wildnis]
  roll.py hat STUFE SELTENHEIT [--spez KAT] [--kontext ..] [--spannung 5] [--sp N]
  roll.py frage CHANCEN [--spannung 5]      Orakelwurf (CHANCEN -3..3 oder Name)
  roll.py stats [-n 2000]                    Verteilungen + Paladin-Check
  roll.py lint                               Tabellen prüfen
"""
import json, os, random, sys, argparse, collections, glob
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(H))
import tables as T  # Fate-Chart (thr, ODDS) + Wortpaar-Pools der Engine, nicht dupliziert
D = {}
for f in sorted(glob.glob(os.path.join(H, 'data', '*.json'))): D.update(json.load(open(f)))
SEL = D['seltenheit']; SID = [s['id'] for s in SEL]; SBY = {s['id']: s for s in SEL}
PR = {p['id']: p for p in D['praegung']}; KAT = {k['id']: k for k in D['kategorien']}
HM = D['haendler']; PPT = D['muenzen']['heller_pro_punkt']; ODDS = T.ODDS
MAGIC = ('magisch', 'gesegnet', 'verflucht')
def d(n, r): return r.randint(1, n)
def inr(x, b): return b[0] <= x <= b[1]
def odds_idx(x):
    if isinstance(x, int): return x
    try: return int(x)
    except ValueError: return ODDS.index(x) - 3

def fmt(h):
    t, rest = divmod(h, 4); s, hh = divmod(rest, 2)
    return ' '.join(x for x in (f'{t} T' if t else '', f'{s} S' if s else '', f'{hh} H' if hh else '') if x) or '0 H'
def punkte(h): return 0 if h < PPT else -(-h // PPT)
def preis(basis, sel, pr, verbrauch=False, skaliert=False):
    """Preis steigt mit der Seltenheit: Nichtmagisches Basis x Praegung x preis_mult, Magie Stufenpreis + Basis x preis_mult,
    magische Verbrauchsgueter Basis x trank_mult (verflucht die Haelfte). skaliert: Preis folgt schon einer eigenen Staffel (Heiltrank)."""
    S = SBY[sel]; R = 1 if skaliert else S['preis_mult']
    if verbrauch and pr in MAGIC: p = basis * S['trank_mult'] / (2 if pr == 'verflucht' else 1)
    elif pr in MAGIC:
        p = S['magie_h'] + basis * R
        if pr == 'verflucht': p //= 2
    else: p = basis * PR[pr]['mult'] * R
    return max(1, int(round(p)) if p < 40 else (int(p) + 10) // 20 * 20)

# ---- Orakel: dieselbe Fate-Chart wie Handout und sl ----
def orakel(r, chancen, spannung=5, schritte=0):
    o = max(-3, min(3, odds_idx(chancen) + schritte)); a, b, c = T.thr(o, spannung); x = d(100, r)
    return {'chancen': ODDS[o + 3], 'wurf': x, 'antwort': 'JA+' if x <= a else 'JA' if x <= b else 'NEIN' if x <= c else 'NEIN+'}
def hat_schritte(stufe, spez=False, kontext='normal'):
    return HM['stufen'][stufe - 1]['orakel'] + (HM['spezial_schritt'] if spez else 0) + next((c['shift'] for c in HM['kontext'] if c['id'] == kontext), 0)
def hat(r, stufe, sel, spez=False, kontext='normal', spannung=5, sp=0):
    if sel not in SBY: sys.exit(f'unbekannte Seltenheit {sel}; gültig: {SID}')
    o = SBY[sel]['orakel'] + hat_schritte(stufe, spez, kontext) + sp
    return orakel(r, min(o, SBY[sel]['deckel']), spannung)

# ---- d100-Tabellen mit Fenster ----
def look(tab, x): return next(t for t in tab if t['von'] <= x <= t['bis'])
def fold(x, win):
    return x + 50 if x < win[0] else x - 50 if x > win[1] else x
def passt(e, kat):
    return not ((e.get('typ') == 'schaden' and kat != 'waffe') or (e.get('typ') == 'ruestung' and kat != 'ruestung'))
def roll_fenster(tabname, sel, r, kat=None):
    t = D[tabname]; win = t['fenster'][sel]; n = 2 if sel in t.get('doppelt', []) else 1; out = []
    while len(out) < n:
        e = look(t['tabelle'], fold(d(100, r), win))
        if e not in out and (kat is None or passt(e, kat)) and e.get('typ') not in {x.get('typ') for x in out}: out.append(e)
    return out

def roll_sel(r): x = d(100, r); return next(s['id'] for s in SEL if inr(x, s['d100']))
def roll_kat(r): x = d(20, r); return next(k['id'] for k in D['kategorien'] if inr(x, k['d20']))
def roll_praegung(sel, r):
    x = d(20, r); acc = 0
    for pid, n in zip(D['praegung_d20']['reihenfolge'], D['praegung_d20']['anzahl'][sel]):
        acc += n
        if x <= acc: return pid
def roll_posten(k, r):
    x = d(100, r); return next(i for i in k['items'] if i['von'] <= x <= i['bis'])

def pool(lst, gr):
    """Eintraege, die zu mindestens einer erlaubten Materialgruppe passen (leere gruppen = universell)."""
    return [x for x in lst if not x['gruppen'] or set(x['gruppen']) & set(gr)]
def roll_merkmale(it, sel, pr, r):
    M = D['merkmale']; gr = it['mat']; out = []
    mats = [m for g in gr for m in M['material'][g]]
    out.append(('Material' if gr != ['zutat'] else 'Zutat', r.choice(mats)))
    z = pool(M['zustand'], gr); ma = pool(M['machart'], gr); be = pool(M['besonderheit'], gr)
    if pr == 'plunder': out.append(('Zustand', r.choice(z[:max(3, len(z) * 3 // 10)])['text']))
    elif pr == 'gut': out.append(('Machart', r.choice(ma)['text']))
    elif sel == 'gewoehnlich':
        c = r.choice(['herkunft', 'besonderheit', 'zustand']); out.append((c.capitalize(), r.choice(M['herkunft']) if c == 'herkunft' else r.choice(be if c == 'besonderheit' else z)['text']))
    else: out += [('Machart', r.choice(ma)['text']), ('Besonderheit', r.choice(be)['text'])]
    return out

def artikel(g): return {'m': 'Der', 'f': 'Die', 'n': 'Das'}[g]
def roll_name(it, r):
    N = D['namen']; ep = N['epitheton'][d(100, r) - 1]; bz = N['bezug'][d(100, r) - 1]
    kern = it.get('kern') or it['name'].split(' / ')[0].split(' (')[0]; g = it.get('genus', 'n')
    return f"{artikel(g)} {ep}{'' if ep.endswith('e') else 'e'} {kern} {bz}"
def roll_paar(r):
    a, b = D['orakel']['paar']; return r.choice(T.POOLS[a]), r.choice(T.POOLS[b])

def roll_item(r, sel=None, kat=None, pr=None, name=False):
    if sel and sel not in SBY or kat and kat not in KAT: sys.exit(f'unbekannt: {sel} {kat}; gültig: {SID} {list(KAT)}')
    sel = sel or roll_sel(r); kat = kat or roll_kat(r); k = KAT[kat]; it = roll_posten(k, r)
    mn = it.get('min')
    if mn and SID.index(sel) < SID.index(mn): sel = mn
    pr = pr or roll_praegung(sel, r)
    if 'heilung_lp' in it:  # Heiltrank: Heilung (und Preis) folgen der Seltenheit; 4 LP nur ab sehr selten
        lp = it['heilung_lp'][SID.index(sel)]; it['effekt'] = f'heilt {lp} LP sofort, auch im Kampf'; it['preis_h'] = it['preis_h'] * lp // 2
    if k['verbrauch'] and pr == 'wendung': pr = 'gut'
    if it.get('schaedlich') and pr in MAGIC: pr = 'gut'  # Gifte und Reizstoffe sind nie magisch/gesegnet/verflucht
    out = {'kat': kat, 'name': it['name'], 'seltenheit': sel, 'praegung': pr, 'basis_h': it['preis_h'],
           'schaden': it.get('schaden'), 'ruestung': it.get('ruestung'), 'effekt': it.get('effekt'), 'gm': [], 'merkmale': [], 'kp': 0}
    out['preis_h'] = preis(it['preis_h'], sel, pr, k['verbrauch'], 'heilung_lp' in it); out['punkte'] = punkte(out['preis_h'])
    if pr in ('normal', 'gut', 'plunder') or (pr == 'wendung'): out['merkmale'] = roll_merkmale(it, sel, pr, r)
    if pr in MAGIC:
        tab = 'segen' if pr == 'gesegnet' else 'wirkungen'
        if k['verbrauch']: out['wirkung'] = 'Wirkung doppelt' if pr != 'verflucht' else 'Wirkung + Nebenwirkung (Fluch) bis zur Nachtruhe'
        else:
            es = roll_fenster(tab, sel, r, kat); out['wirkung'] = ' + '.join(e['text'] for e in es); out['kp'] = sum(e['kp'] for e in es)
            out['mech'] = [(e['typ'], e['takt'], e['kp']) for e in es]
        out['merkmale'] = roll_merkmale(it, sel, 'normal', r)[:1]
        if pr == 'verflucht' and k['verbrauch']: out['gm'].append('Nebenwirkung: vergiftet bis zur Nachtruhe (kein Fluchwurf)')
        elif pr == 'verflucht':
            f = roll_fenster('flueche', sel, r)[0]; out['gm'].append(f"Fluch (Stufe {f['stufe']}): {f['text']} | Haken: {f['haken']}"); out['fluch_stufe'] = f['stufe']
    if pr == 'wendung':
        w = roll_fenster('wendungen', sel, r)[0]; out['gm'].append(f"Wendung (Stufe {w['stufe']}): {w['text']} | Enthüllung: {w['enthuellung']}"); out['wendung_stufe'] = w['stufe']
    if SID.index(sel) >= SID.index('selten') and pr in MAGIC + ('wendung',):
        a, b = roll_paar(r); out['paar'] = [a, b]
        out['fragen'] = [f"{f['text']} ({f['chancen']})" for f in r.sample(D['orakel']['fragen_item'], 2)]
        name = True
    if name: out['titel'] = roll_name(it, r)
    return out

def show(i):
    s = f"{i.get('titel') or i['name']}{' (' + i['name'] + ')' if i.get('titel') else ''} [{SBY[i['seltenheit']]['name']}, {PR[i['praegung']]['name']}] {fmt(i['preis_h'])} ({i['punkte']} P)"
    if i['schaden']: s += f" Schaden {i['schaden']}"
    if i['ruestung'] is not None: s += f" Rüstung {i['ruestung']}"
    if i['effekt']: s += f" | {i['effekt']}"
    if i['merkmale']: s += ' | ' + ', '.join(f'{a}: {b}' for a, b in i['merkmale'])
    if i.get('wirkung'): s += f" | WIRKUNG (Rahmen): {i['wirkung']}"
    if i.get('paar'): s += f" | WORTPAAR: {i['paar'][0]} · {i['paar'][1]} | FRAGEN: " + ' / '.join(i['fragen'])
    for g in i['gm']: s += f" | SL: {g}"
    return s

def stufe_eff(stufe, kontext, spez_hit):
    sh = next((c['shift'] for c in HM['kontext'] if c['id'] == kontext), 0)
    return max(1, min(5, stufe + sh + (1 if spez_hit else 0)))
def roll_sel_haendler(st, r):
    w = HM['stufen'][st - 1]['wuerfe']; xs = [roll_sel(r) for _ in range(abs(w))]
    sel = (min if w < 0 else max)(xs, key=SID.index)
    if sel == 'gewoehnlich' and d(6, r) <= HM['stufen'][st - 1]['plunder_d6']: return sel, 'plunder'
    return sel, None
def haendler(r, stufe, spez=(), kontext='normal'):
    out = []
    for _ in range(d(6, r) + stufe):
        hit = bool(spez) and d(6, r) <= HM['spezial_d6'][1]
        kat = r.choice(list(spez)) if hit else roll_kat(r)
        sel, pr = roll_sel_haendler(stufe_eff(stufe, kontext, kat in spez), r)
        out.append(roll_item(r, sel, kat, pr))
    return out

def lint():
    bad = []
    for tn in ('wirkungen', 'segen', 'flueche', 'wendungen'):
        t = D[tn]['tabelle']; acc = 0
        for e in t:
            if e['von'] != acc + 1 or e['bis'] < e['von']: bad.append(f'{tn}: Lücke bei {e["von"]}')
            acc = e['bis']
        if acc != 100: bad.append(f'{tn}: endet bei {acc}')
        key = 'stufe' if tn in ('flueche', 'wendungen') else 'kp'
        v = [e[key] for e in t]
        if v != sorted(v): bad.append(f'{tn}: {key} nicht monoton')
        if tn == 'flueche' and any(not e.get('haken') for e in t): bad.append('flueche: Haken fehlt')
        if tn == 'wendungen' and any(not e.get('enthuellung') for e in t): bad.append('wendungen: Enthüllung fehlt')
        for e in t:
            if 'Wunden' in json.dumps(e, ensure_ascii=False): bad.append(f'{tn}: "Wunden" bei {e["von"]}')
    sp = [e for e in D['wirkungen']['tabelle'] if e.get('typ') == 'sp']
    if sp: bad.append('wirkungen: SP-Typ nur im Segen erlaubt')
    for e in D['segen']['tabelle']:
        if e.get('typ') == 'sp' and (e['takt'] != 'sitzung' or e['kp'] != 3): bad.append(f'segen {e["von"]}: SP nur sitzung/kp3')
    for k in D['kategorien']:
        acc = 0
        for i in k['items']:
            if i['von'] != acc + 1: bad.append(f'{k["id"]}: Lücke bei {i["von"]}')
            acc = i['bis']
            if i.get('schaden', 0) > 5 or i.get('ruestung', 0) > 3 and k['id'] != 'x': bad.append(f'{k["id"]} {i["name"]}: Deckel')
            if not i.get('genus'): bad.append(f'{k["id"]} {i["name"]}: genus fehlt')
        if acc != 100: bad.append(f'{k["id"]} endet bei {acc}')
    M = D['merkmale']; GR = list(M['material'])
    seen = {}
    for g, l in M['material'].items():
        if len(l) < 6: bad.append(f'material {g}: nur {len(l)}')
        for m in l:
            if m in seen: bad.append(f'Material {m!r} in {seen[m]} und {g}')
            seen[m] = g
    for c in ('machart', 'zustand', 'besonderheit'):
        for x in M[c]:
            if set(x['gruppen']) - set(GR): bad.append(f'{c}: unbekannte Gruppe {x}')
    if len(M['herkunft']) != 100: bad.append('herkunft != 100')
    # kein Gegenstand kann ein unmögliches Material oder Merkmal würfeln: jede Gruppe existiert, Pools sind nicht dünn
    for k in D['kategorien']:
        for i in k['items']:
            gr = i.get('mat')
            if not gr or set(gr) - set(GR): bad.append(f'{k["id"]} {i["name"]}: mat {gr}'); continue
            if k['verbrauch'] and gr != ['zutat']: bad.append(f'{i["name"]}: Trank braucht mat [zutat]')
            if not k['verbrauch'] and 'zutat' in gr and k['id'] not in ('kuriosum', 'schmuck'): bad.append(f'{i["name"]}: zutat nur bei Tränken')
            if 'tier' in gr and k['id'] not in ('transport', 'kuriosum'): bad.append(f'{i["name"]}: tier nur bei Transport/Kuriosum')
            for c in ('machart', 'zustand', 'besonderheit'):
                if len(pool(M[c], gr)) < 8: bad.append(f'{i["name"]}: zu wenige {c} für {gr}')
    for c in ('epitheton', 'bezug'):
        if len(D['namen'][c]) != 100: bad.append(f'namen {c}')
    for k in D['kategorien']:
        for i in k['items']:
            ver = k['verbrauch']; sk = 'heilung_lp' in i
            for pr in ('plunder', 'normal', 'gut', 'wendung', 'magisch', 'gesegnet', 'verflucht'):
                if i.get('schaedlich') and pr in MAGIC: continue
                ids = SID[1:] if pr in MAGIC else SID
                ps = [preis(i['preis_h'] * ((i['heilung_lp'][SID.index(x)] // 1) / 2 if sk else 1), x, pr, ver, sk) for x in ids]
                if ps != sorted(ps): bad.append(f'Preis nicht monoton: {k["id"]} {i["name"]} {pr} {ps}')
            for x in SID[1:]:
                b0 = i['preis_h'] * ((i['heilung_lp'][SID.index(x)]) / 2 if sk else 1)
                if not i.get('schaedlich') and preis(b0, x, 'verflucht', ver, sk) > preis(b0, x, 'magisch', ver, sk): bad.append(f'verflucht teurer als magisch: {i["name"]} {x}')
                if preis(b0, x, 'magisch', ver, sk) < preis(b0, x, 'normal', ver, sk): bad.append(f'magisch billiger als normal: {i["name"]} {x}')
            if i.get('schaedlich') and any(preis(i['preis_h'], x, 'gut', ver) > preis(i['preis_h'], x, 'gut', ver) for x in SID): pass
    print('\n'.join(bad) or 'lint ok'); return not bad

def preise_stats():
    print('Ø Preis (T) je Kategorie x Seltenheit; Prägung normal | magisch (Heiltrank/Verbrauch eingerechnet)')
    for k in D['kategorien']:
        row = []
        for x in SID:
            ns = [preis(i['preis_h'] * (i['heilung_lp'][SID.index(x)] / 2 if 'heilung_lp' in i else 1), x, 'normal', k['verbrauch'], 'heilung_lp' in i) for i in k['items']]
            ms = [preis(i['preis_h'] * (i['heilung_lp'][SID.index(x)] / 2 if 'heilung_lp' in i else 1), x, 'magisch', k['verbrauch'], 'heilung_lp' in i) for i in k['items'] if not i.get('schaedlich')] if x != 'gewoehnlich' else []
            row.append(f"{sum(ns)/len(ns)/4:7.1f}|{(sum(ms)/len(ms)/4 if ms else 0):7.0f}")
        print(f"  {k['id']:10}", ' '.join(row))

def stats(n, r):
    for sel in SID[1:]:
        c = collections.Counter(); kp = collections.Counter(); fl = collections.Counter(); strong = tot = 0; tp = collections.Counter(); wd = collections.Counter()
        for _ in range(n):
            while True:
                i = roll_item(r, sel)
                if i['kat'] != 'trank': break
            c[i['praegung']] += 1
            if i['praegung'] in MAGIC:
                tot += 1; kp[i['kp']] += 1; strong += i['kp'] >= 3
                for t_, _, k_ in i.get('mech', []): tp[t_] += 1
                if 'fluch_stufe' in i: fl[i['fluch_stufe']] += 1
            if 'wendung_stufe' in i: wd[i['wendung_stufe']] += 1
        print(f"{sel:14} Prägung % " + ' '.join(f'{k[:5]} {100*c[k]/n:4.1f}' for k in PR))
        if tot: print(f"{'':14} magische Stücke {tot}: KP-Summe {dict(sorted(kp.items()))}, stark (KP>=3) {100*strong/tot:.0f} %, Typen {dict(tp.most_common(6))}")
        if fl: print(f"{'':14} Fluchstufen {dict(sorted(fl.items()))} (1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden)")
        if wd: print(f"{'':14} Wendungsstufen {dict(sorted(wd.items()))}")
    print('Haendler: Seltenheit je Posten in % (20000 Posten je Stufe)')
    for st in range(1, 6):
        c = collections.Counter()
        for _ in range(20000): s_, p_ = roll_sel_haendler(st, r); c['plunder' if p_ else s_] += 1
        print(f"  Stufe {st}: " + ' '.join(f"{k[:5]} {100*c[k]/20000:4.1f}" for k in ['plunder'] + SID))
    print('Orakel: Chance auf JA/JA+ (Spannung 5) bei "hat er das?", Stufe x Seltenheit (ohne / mit Spezialgebiet)')
    for st in range(1, 6):
        print('  ', st, [f"{T.thr(max(-3, min(SBY[s]['deckel'], SBY[s]['orakel'] + hat_schritte(st))), 5)[1]}/{T.thr(max(-3, min(SBY[s]['deckel'], SBY[s]['orakel'] + hat_schritte(st, True))), 5)[1]}" for s in SID])
    mn = min(preis(i['preis_h'], 'ungewoehnlich', 'magisch') for k in D['kategorien'] if not k['verbrauch'] for i in k['items'])
    mv = min(preis(i['preis_h'], 'ungewoehnlich', 'verflucht') for k in D['kategorien'] if not k['verbrauch'] for i in k['items'])
    print(f"Günstigstes magisches Stück: {fmt(mn)} ({punkte(mn)} P), verflucht {fmt(mv)} ({punkte(mv)} P); Budget 20 P = {fmt(20*PPT)}")
    pal = [i['preis_h'] for k in KAT.values() for i in k['items'] if i['name'] in ('Plattenpanzer', 'Schwert', 'Holzschild')]
    print(f"Paladin Platte+Schwert+Schild: {fmt(sum(pal))} = {punkte(sum(pal))} P (Platte+Schwert 10 P)")
    tiers = collections.Counter()
    for k in KAT.values():
        for i in k['items']:
            if k['id'] in ('waffe', 'ruestung'): tiers[(k['id'], i['preis_h'])] += i['bis'] - i['von'] + 1
    print('Waffe/Rüstung Preisstufen (Anteil an d100):', {f'{a} {fmt(b)}': v for (a, b), v in sorted(tiers.items())})

if __name__ == '__main__':
    a = argparse.ArgumentParser(); a.add_argument('cmd'); a.add_argument('args', nargs='*')
    a.add_argument('-n', type=int, default=None); a.add_argument('--selt'); a.add_argument('--kat'); a.add_argument('--name', action='store_true')
    a.add_argument('--spez', action='append', default=[]); a.add_argument('--kontext', default='normal'); a.add_argument('--seed', type=int)
    a.add_argument('--spannung', type=int, default=5); a.add_argument('--sp', type=int, default=0); a.add_argument('--json', action='store_true')
    o = a.parse_args(); r = random.Random(o.seed)
    if o.cmd == 'item':
        for _ in range(o.n or 1):
            i = roll_item(r, o.selt, o.kat, name=o.name); print(json.dumps(i, ensure_ascii=False) if o.json else show(i))
    elif o.cmd == 'haendler':
        inv = haendler(r, int(o.args[0]), o.spez, o.kontext)
        print(json.dumps(inv, ensure_ascii=False) if o.json else '\n'.join(show(i) for i in inv))
    elif o.cmd == 'hat':
        res = hat(r, int(o.args[0]), o.args[1], bool(o.spez), o.kontext, o.spannung, o.sp); print(json.dumps(res, ensure_ascii=False))
    elif o.cmd == 'frage': print(json.dumps(orakel(r, o.args[0], o.spannung, o.sp), ensure_ascii=False))
    elif o.cmd == 'preise': preise_stats()
    elif o.cmd == 'stats': stats(o.n or 2000, r)
    elif o.cmd == 'lint': sys.exit(0 if lint() else 1)
