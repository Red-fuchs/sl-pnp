#!/usr/bin/env python3
"""Gegenstandsgenerator-Roller (stdlib). Liest data/items.json.
  items_roll.py item [-n 5] [--selt ID] [--kat ID]
  items_roll.py haendler STUFE [--spez KAT] [--kontext grossstadt|wildnis]
  items_roll.py hat STUFE SELTENHEIT [--spez KAT --kat KAT] [--kontext ..]
  items_roll.py stats [-n 1000]      Verteilungen + Paladin-Check
"""
import json, os, random, sys, argparse, collections
H = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(H, 'data', 'items.json')))
SEL = D['seltenheit']; SID = [s['id'] for s in SEL]; SBY = {s['id']: s for s in SEL}
PR = {p['id']: p for p in D['praegung']}; KAT = {k['id']: k for k in D['kategorien']}
HM = D['haendler']; PPT = D['muenzen']['heller_pro_punkt']
def d(n, r): return r.randint(1, n)
def inr(x, b): return b[0] <= x <= b[1]

def fmt(h):
    t, rest = divmod(h, 4); s, hh = divmod(rest, 2)
    return ' '.join(x for x in (f'{t} T' if t else '', f'{s} S' if s else '', f'{hh} H' if hh else '') if x) or '0 H'
def punkte(h): return 0 if h < PPT else -(-h // PPT)
def preis(basis, sel, pr):
    if pr in ('magisch', 'gesegnet', 'verflucht'):
        p = SBY[sel]['magie_h'] + basis
        if pr == 'verflucht': p //= 2
    elif pr == 'wendung': p = basis * SBY[sel]['mult']
    else: p = basis * PR[pr]['mult']
    return max(1, int(round(p)) if p < 40 else (int(p) + 10) // 20 * 20)

def roll_sel(r): x = d(100, r); return next(s['id'] for s in SEL if inr(x, s['d100']))
def roll_kat(r): x = d(20, r); return next(k['id'] for k in D['kategorien'] if inr(x, k['d20']))
def roll_praegung(sel, r):
    x = d(20, r); acc = 0
    for pid, n in zip(D['praegung_d20']['reihenfolge'], D['praegung_d20']['anzahl'][sel]):
        acc += n
        if x <= acc: return pid
def look(tab, x): return next(t for t in tab if ('bis' in t and t['von'] <= x <= t['bis']) or t.get('wurf') == x)['text']

def roll_item(r, sel=None, kat=None, pr=None):
    if sel and sel not in SBY or kat and kat not in KAT: sys.exit(f'unbekannt: {sel} {kat}; gültig: {SID} {list(KAT)}')
    sel = sel or roll_sel(r); kat = kat or roll_kat(r); k = KAT[kat]
    it = dict(r.choice(k['items'])); mn = it.get('min')
    if mn and SID.index(sel) < SID.index(mn): sel = mn
    pr = pr or roll_praegung(sel, r)
    if k['verbrauch'] and pr == 'wendung': pr = 'gut'
    out = {'kat': kat, 'name': it['name'], 'seltenheit': sel, 'praegung': pr, 'basis_h': it['preis_h'],
           'schaden': it.get('schaden'), 'ruestung': it.get('ruestung'), 'effekt': it.get('effekt'), 'gm': []}
    out['preis_h'] = preis(it['preis_h'], sel, pr); out['punkte'] = punkte(out['preis_h'])
    wd = SBY[sel]['wirkung_plus']; W = D['wirkung']
    if pr in ('magisch', 'gesegnet', 'verflucht'):
        if k['verbrauch']: out['wirkung'] = 'Wirkung doppelt' if pr != 'verflucht' else 'Wirkung + Nebenwirkung (Fluch) bis zur Nachtruhe'
        else: out['wirkung'] = look(W['gesegnet' if pr == 'gesegnet' else 'magisch'], d(6, r) + wd)
        if pr == 'verflucht':
            out['gm'].append('Fluch: ' + look(W['fluch']['tabelle'], d(W['fluch']['wuerfel'][sel], r)))
    if pr == 'wendung': out['gm'].append('Wendung: ' + look(W['wendung']['tabelle'], d(8, r)))
    if pr in ('magisch', 'gesegnet', 'verflucht') and not k['verbrauch'] and pr != 'gesegnet' and False: pass
    return out

def show(i):
    s = f"{i['name']} [{SBY[i['seltenheit']]['name']}, {PR[i['praegung']]['name']}] {fmt(i['preis_h'])} ({i['punkte']} P)"
    if i['schaden']: s += f" Schaden {i['schaden']}"
    if i['ruestung'] is not None: s += f" Rüstung {i['ruestung']}"
    if i['effekt']: s += f" | {i['effekt']}"
    if i.get('wirkung'): s += f" | WIRKUNG: {i['wirkung']}"
    for g in i['gm']: s += f" | SL: {g}"
    return s

def stufe_eff(stufe, kontext, spez_hit):
    sh = next((c['shift'] for c in HM['kontext'] if c['id'] == kontext), 0)
    return max(1, min(5, stufe + sh + (HM['spezial_stufe'] if spez_hit else 0)))
def roll_sel_haendler(st, r):
    x = d(100, r); acc = 0
    for key, n in HM['stufen'][st - 1]['inventar'].items():
        acc += n
        if x <= acc: return ('gewoehnlich', 'plunder') if key == 'plunder' else (key, None)

def haendler(r, stufe, spez=(), kontext='normal'):
    out = []
    for _ in range(d(6, r) + stufe):
        hit = bool(spez) and d(6, r) <= HM['spezial_d6'][1]
        kat = r.choice(list(spez)) if hit else roll_kat(r)
        st = stufe_eff(stufe, kontext, kat in spez)
        sel, pr = roll_sel_haendler(st, r)
        out.append(roll_item(r, sel, kat, pr))
    return out

def hat(r, stufe, sel, spez=(), kat=None, kontext='normal'):
    st = stufe_eff(stufe, kontext, kat in spez)
    if sel not in SBY: sys.exit(f'unbekannte Seltenheit {sel}; gültig: {SID}')
    return d(100, r) <= HM['stufen'][st - 1]['verfuegbar'][sel]

def stats(n, r):
    for stufe in range(1, 6):
        c = collections.Counter(); pr = collections.Counter(); tot = 0; cnt = 0; hp = 0; mx = 0; cur = 0
        for _ in range(n):
            for i in haendler(r, stufe):
                c['plunder' if i['praegung'] == 'plunder' else i['seltenheit']] += 1; pr[i['praegung']] += 1
                tot += i['preis_h']; cnt += 1; mx = max(mx, i['preis_h'])
        pc = lambda k, m: f"{100 * m[k] / cnt:5.1f}"
        print(f"Stufe {stufe}: {cnt/n:.1f} Posten, Ø Preis {fmt(round(tot/cnt))}, max {fmt(mx)}")
        print('  Seltenheit %: ' + ' '.join(f"{k[:5]} {pc(k,c)}" for k in ['plunder'] + SID))
        print('  Prägung %:    ' + ' '.join(f"{k[:5]} {pc(k,pr)}" for k in PR))
    print('Per Seltenheit (zufällig, 20000 Stück): Prägung % und Ø Preis')
    for s in SID:
        pr = collections.Counter(); tot = 0
        for _ in range(20000):
            i = roll_item(r, s); pr[i['praegung']] += 1; tot += i['preis_h']
        print(f"  {s:14} Ø {fmt(round(tot/20000)):>12}  " + ' '.join(f"{k[:5]} {100*pr[k]/20000:4.1f}" for k in PR))
    # Magie im Startbudget: günstigste magische Stücke
    mn = min(preis(it['preis_h'], 'ungewoehnlich', 'magisch') for k in D['kategorien'] for it in k['items'])
    mv = min(preis(it['preis_h'], 'ungewoehnlich', 'verflucht') for k in D['kategorien'] for it in k['items'])
    print(f"Günstigstes magisches Stück: {fmt(mn)} ({punkte(mn)} P), verflucht {fmt(mv)} ({punkte(mv)} P); Budget 20 P = {fmt(20*PPT)}")
    pal = [i['preis_h'] for k in KAT.values() for i in k['items'] if i['name'] in ('Plattenpanzer', 'Schwert', 'Holzschild')]
    print(f"Paladin Platte+Schwert+Schild: {fmt(sum(pal))} = {punkte(sum(pal))} P (Platte+Schwert 10 P)")
    print('Gefragter Gegenstand, Chance in % (Stufe x Seltenheit, ohne Spezial / mit Spezial):')
    for st in range(1, 6): print('  ', st, [f"{HM['stufen'][st-1]['verfuegbar'][s]}/{HM['stufen'][min(5,st+1)-1]['verfuegbar'][s]}" for s in SID])

if __name__ == '__main__':
    a = argparse.ArgumentParser(); a.add_argument('cmd'); a.add_argument('args', nargs='*')
    a.add_argument('-n', type=int, default=None); a.add_argument('--selt'); a.add_argument('--kat')
    a.add_argument('--spez', action='append', default=[]); a.add_argument('--kontext', default='normal'); a.add_argument('--seed', type=int)
    a.add_argument('--json', action='store_true'); o = a.parse_args(); r = random.Random(o.seed)
    if o.cmd == 'item':
        for _ in range(o.n or 1):
            i = roll_item(r, o.selt, o.kat); print(json.dumps(i, ensure_ascii=False) if o.json else show(i))
    elif o.cmd == 'haendler':
        inv = haendler(r, int(o.args[0]), o.spez, o.kontext)
        print(json.dumps(inv, ensure_ascii=False) if o.json else '\n'.join(show(i) for i in inv))
    elif o.cmd == 'hat':
        print('ja' if hat(r, int(o.args[0]), o.args[1], o.spez, o.kat, o.kontext) else 'nein')
    elif o.cmd == 'stats': stats(o.n or 1000, r)
