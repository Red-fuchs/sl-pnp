"""Kapitel 11 Gegenstände & Händler: HTML aus data/items.json."""
import json, os
from tables import e, table
H = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(H, 'data', 'items.json')))
SEL = D['seltenheit']; PR = {p['id']: p for p in D['praegung']}; KAT = D['kategorien']; HM = D['haendler']
SN = {s['id']: s['name'] for s in SEL}
def fmt(h):
    t, r = divmod(h, 4); s, hh = divmod(r, 2)
    return ' '.join(x for x in (f'{t}&nbsp;T' if t else '', f'{s}&nbsp;S' if s else '', f'{hh}&nbsp;H' if hh else '') if x) or '0&nbsp;H'
def rng(lo, hi): return f'{lo:02d}' if lo == hi else f'{lo:02d}–{hi:02d}'.replace('–100', '–00')
def d20r(lo, hi): return str(lo) if lo == hi else f'{lo}–{hi}'

def praegung_rows():
    ids = D['praegung_d20']['reihenfolge']; rows = []
    for i, pid in enumerate(ids):
        lab = {'magisch': '+ Stufenpreis', 'gesegnet': '+ Stufenpreis', 'verflucht': '+ ½ Stufenpreis', 'wendung': '× Seltenheit'}.get(pid) or f'×{PR[pid]["mult"]:g}'.replace('.', ',')
        row = [f'<b>{e(PR[pid]["name"])}</b> ({lab})']
        for s in SEL:
            acc = sum(D['praegung_d20']['anzahl'][s['id']][:i]); n = D['praegung_d20']['anzahl'][s['id']][i]
            row.append(d20r(acc + 1, acc + n) if n else '–')
        rows.append(row)
    return rows

def wirk_li(tab):
    return ''.join(f'<li><b>{t["von"]}{"–" + str(t["bis"]) if t["bis"] != t["von"] else ""}</b> {e(t["text"])}</li>' for t in tab)
def num_li(tab): return ''.join(f'<li><b>{t["wurf"]}</b> {e(t["text"])}</li>' for t in tab)
def wl(cap, li, cols=1): return f'<div class="wl rl"><div class="cap">{cap}</div><ul style="column-count:{cols}">{li}</ul></div>'

def stufe_rows():
    ids = [s['id'] for s in SEL]
    return ([[str(s['stufe']), e(s['beispiel'].split(' (')[0].split(',')[0] + ('' if s['stufe'] != 4 else ' (Alchemist)'))] + [f'{s["verfuegbar"][i]} %' for i in ids] for s in HM['stufen']],
            [[str(s['stufe'])] + [f'{s["inventar"][k]}' if s['inventar'][k] else '–' for k in ['plunder'] + ids] for s in HM['stufen']])

def cat_list(k):
    li = ''
    for i, it in enumerate(k['items']):
        v = f'Sch. {it["schaden"]}' if 'schaden' in it else (f'Rü. {it["ruestung"]}' if 'ruestung' in it else '')
        x = it.get('effekt', '')
        extra = ' · '.join(y for y in [v, e(x)] if y)
        li += f'<li><b>{i + 1}</b> {e(it["name"])} <i>{fmt(it["preis_h"])}</i>{" · " + extra if extra else ""}</li>'
    return wl(f'{e(k["name"])}  (d20 {d20r(*k["d20"])}), Gegenstand d10', li)

def pages(example_html):
    vm = HM['stufen']; ids = [s['id'] for s in SEL]
    arts = table(['d20', 'Art'], [[d20r(*k['d20']), f'<b>{e(k["name"])}</b>'] for k in KAT], 'small nw')
    selt = table(['d100', 'Seltenheit', 'Magie ab', 'Wirkung'], [[rng(*s['d100']), f'<b>{e(s["name"])}</b>', f'{s["magie_h"]//4} T' if s.get('magie_h') else '–', ('W6' + (f'+{s["wirkung_plus"]}' if s['wirkung_plus'] else '')) if s['wirkungswuerfel'] else 'keine'] for s in SEL], 'small nw')
    pr = table(['Prägung (Preis ×)'] + [e(s['name']) for s in SEL], praegung_rows(), '')
    pa = f'''<style>.it .wl.rl ul{{font-size:7.4pt;line-height:1.12}} .it table{{font-size:8pt;margin-bottom:1.5mm}} .it h3{{margin:1.5mm 0 .6mm}} .it td{{padding:.4mm 1.4mm}} .it .nw td:first-child{{white-space:nowrap}}</style><h1 class="pb">11 Gegenstände und Händler <span class="note">(Vorschlag)</span></h1>
<div class="grid"><div style="width:44%"><div class="box"><b class="t">Münzen</b><br>1 Taler (T) = 2 Schilling (S) = 4 Heller (H). „3 T 1 S 1 H“ = 3¾ Taler.<br><b>10 Taler = 1 Budgetpunkt</b> (Figurenerschaffung). Posten unter 10 T zahlst du in Taler.</div></div>
<div><b>Vier Würfe für einen Gegenstand:</b><ol style="margin-bottom:0"><li><b>Art:</b> d20 → Kategorie, dann d10 → Gegenstand (Basispreis und Werte stehen dabei).</li>
<li><b>Seltenheit:</b> d100 (oder von der Spielleitung gesetzt).</li>
<li><b>Prägung:</b> d20 in der Spalte der Seltenheit.</li>
<li><b>Wirkung:</b> nur bei magisch, gesegnet, verflucht: Würfel der Seltenheit (W6 bis W12).</li></ol></div></div>
<p><b>Preis:</b> gewöhnlich, gut, Plunder = <b>Basis × Prägung</b> (Plunder ×¼, normal ×1, gut ×1½); die Seltenheit macht sie nur schwerer zu finden. <b>Magisch/gesegnet = Basis + Stufenpreis</b> (ungewöhnlich 250 T · selten 500 T · sehr selten 1000 T · legendär 2000 T), verflucht die Hälfte davon. Wendung: Basis × Seltenheit. Ab 10 T auf 5 T runden. <b>Budgetpunkte</b> = Preis ÷ 10 T, aufgerundet (Posten unter 10 T: Taler). Mit 200 T (20 Punkte) ist Magie nie zu bezahlen.</p>
<div class="grid"><div style="width:36%"><h3>Art (d20)</h3>{arts}</div><div style="width:34%"><h3>Seltenheit (d100)</h3>{selt}<p class="note">Normale Ausrüstung bleibt auf den Tarifen 20 T (2 P) · 40 T (4 P) · 60 T (6 P).</p></div><div><h3>Wirkung begrenzt</h3><p class="note">Wurf = W6 plus Bonus: je seltener, desto stärker (legendär mindestens 7). +1 Schaden/Rüstung nur bei Waffe und Rüstung, sonst +20. Grenzen: Schaden 5, Rüstung 3.</p></div></div>
<h3>Prägung (d20, Spalte = Seltenheit)</h3>{pr}
<div style="column-count:2;column-gap:5mm;font-size:8pt;line-height:1.2">{"".join(f'<p style="margin-bottom:.6mm"><b>{e(p["name"])}:</b> {e(p["text"])}</p>' for p in D["praegung"] if p["id"] not in ("normal", "magisch", "gesegnet"))}<p style="margin-bottom:.6mm"><b>Tränke:</b> magisch/gesegnet = Wirkung doppelt (Heilung höchstens 6); verflucht = Nebenwirkung bis zur Nachtruhe. <b>Vergiftet:</b> −10 auf alles, 1 LP Verlust je Szene bis Gegengift oder Nachtruhe.</p></div>
<div class="two">{wl("Wirkung magisch (W6 + Bonus der Seltenheit)", wirk_li(D["wirkung"]["magisch"]))}{wl("Wirkung gesegnet", wirk_li(D["wirkung"]["gesegnet"]))}</div>
'''
    m, inv = stufe_rows()
    mat = table(['Stufe', 'Beispiel'] + [e(s['name']) for s in SEL], m, '')
    ivt = table(['Stufe', 'Plunder'] + [e(s['name']) for s in SEL], inv, 'small')
    kont = table(['Kontext', 'Stufe'], [[e(c['name']), f'{c["shift"]:+d}' if c['shift'] else '±0'] for c in HM['kontext']] + [['Spezialgebiet (eigene Kategorie)', '+1']], 'small" style="width:100%')
    alltag = table(['Ware', 'Preis'], [[e(a['name']), fmt(a['preis_h'])] for a in D['alltag']], 'small" style="width:100%')
    pb = f'''<h1 class="pb">11 Händler: hat er das?</h1>
<p><b>Händlerstufe 1–5</b> (1 Straßenbrauer · 2 Dorfkrämer · 3 Stadthändler · 4 Meister · 5 Hofmagier). Verschiebe die Stufe nach Kontext und Spezialgebiet, aber nie unter 1 oder über 5.</p>
<div class="grid"><div style="width:60%"><h3>Gefragter Gegenstand: hat er ihn? (d100 ≤ Wert)</h3>{mat}<h3>Stufe verschieben</h3>{kont}</div><div><h3>Alltag (feste Preise)</h3>{alltag}</div></div>
<div class="grid"><div style="width:48%"><h3>Was hat er da? (Ablauf)</h3><ol><li>Posten: <b>d6 + Stufe</b>.</li><li>Je Posten: d6 1–4 → aus seinem <b>Spezialgebiet</b>, sonst Art würfeln (d20). Ohne Spezialgebiet immer Art würfeln.</li><li><b>Seltenheit</b> in der Tabelle rechts (d100, Spalten in Prozent). „Plunder“ = gewöhnlich, Prägung Plunder.</li><li>Prägung (d20) und, falls nötig, Wirkung. Fluch und Wendung würfelt nur die Spielleitung.</li><li>Preis ausrechnen, Namen und eine Zeile Beschreibung erfinden.</li></ol></div>
<div><h3>Seltenheit je Posten (d100, Prozent)</h3>{ivt}</div></div>
{example_html}
<div class="grid"><div>{wl("Fluch (nur Spielleitung): Vorteil aus Tabelle magisch, Fluch W6 (ungewöhnlich, selten) oder W8 (sehr selten, legendär)", num_li(D["wirkung"]["fluch"]["tabelle"]))}</div>
<div>{wl("Wendung (nur Spielleitung, W8)", num_li(D["wirkung"]["wendung"]["tabelle"]))}</div>
</div>'''
    pc = '<h1 class="pb">11 Gegenstandslisten (Art d20, Gegenstand d10)</h1><p class="note">Preise in Taler (T), Schilling (S) und Heller (H). Sch. = Schaden, Rü. = Rüstung.</p><div class="two">' + ''.join(cat_list(k) for k in KAT) + '</div>'
    return [f'<div class="it">{x}</div>' for x in (pa, pb, pc)]

def example():
    import items_roll as R
    kat = next(k for k in R.D['kategorien'] if k['id'] == 'trank'); it = kat['items'][7]
    assert it['name'] == 'Stärkungstrank' and R.HM['stufen'][1]['verfuegbar']['selten'] == 5 and R.HM['stufen'][4]['verfuegbar']['selten'] == 60
    ph = R.preis(it['preis_h'], 'selten', 'magisch'); assert ph == 2120, ph
    pl = R.preis(it['preis_h'], 'gewoehnlich', 'plunder'); assert pl == 30, pl
    return f'''<div class="box ex"><b class="t">Beispiel: ein seltener Trank, zwei Händler.</b> Die Gruppe sucht einen <b>seltenen Trank</b>.<br>
<b>Straßenbrauer</b> (Stufe 1, Spezialgebiet Tränke → für Tränke Stufe 2): Matrix Stufe 2 × selten = <b>5 %</b>. d100 = <b>63</b>, also nein. „Hab nur Gebräu für Mutige.“ Er hat dann etwas anderes: Art-Wurf Trank, d10 = 8 Stärkungstrank (30 T), Seltenheit aus der Stufe-2-Spalte „gewöhnlich“, Prägung d20 = 2 <b>Plunder</b>: {fmt(pl)} (30 T × ¼ = 7 T 1 S), wirkt nur halb.<br>
<b>Meisteralchemist</b> (Stufe 4, Spezialgebiet Tränke → Stufe 5): Matrix Stufe 5 × selten = <b>60 %</b>. d100 = <b>41</b>, ja. Gegenstand: d10 = 8 Stärkungstrank, Prägung d20 in Spalte selten = 11 → <b>magisch</b>. Wirkung: Trank, also doppelt: <b>+20 auf Kampf eine Szene</b>. Preis: Stufenpreis selten 500 T + Basis 30 T = <b>530 T</b> (53 Budgetpunkte, also nur als Beute oder Belohnung, nie als Startgut). Gemma erfindet nur Namen („Tropfen des Falkenblutes“) und eine Zeile Beschreibung.</div>'''
