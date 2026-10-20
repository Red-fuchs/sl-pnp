"""Tabellen-Generator: liest die Engine-JSON (schicksal) und liefert HTML-Fragmente."""
import json, math, html, os
H = os.path.dirname(os.path.abspath(__file__))
ENG = os.path.expanduser('~/Projects/schicksal/Sources/Schicksal/Resources/tables_de_darkfantasy.json')
P = json.load(open(ENG))
POOLS = P['pools']
def D(n): return json.load(open(os.path.join(H, 'data', n + '.json')))
e = html.escape
# --- Core.swift 1:1 ---
A, B, K = 0.9, 0.16, 0.15
ODDS = ["fast unmöglich", "sehr unwahrscheinlich", "unwahrscheinlich", "offen", "wahrscheinlich", "sehr wahrscheinlich", "fast sicher"]
def pyes(o, s): return 1 / (1 + math.exp(-(A * o + B * (s - 5))))
def thr(o, s):
    p = round(100 * pyes(o, s))
    return round(p * K), p, 100 - round((100 - p) * K)
def bruch_share(s): return 0.30 + 0.05 * (s - 1)
# Engine.dirs
DIRS = [("fern", 6), ("zeichen", 7), ("neu", 8), ("akteur_handelt", 15), ("akteur_leidet", 6), ("akteur_gewinnt", 4),
        ("strang_voran", 9), ("strang_zurueck", 6), ("strang_ende", 3), ("figur_schaden", 11), ("figur_gunst", 7), ("kontext", 18)]
assert sum(w for _, w in DIRS) == 100
MUTS = [("ersetzen", 35), ("hinzufuegen", 25), ("entfernen", 15), ("steigern", 15), ("daempfen", 10)]

def table(head, rows, cls='', widths=None):
    h = ''.join(f'<th>{x}</th>' for x in head)
    r = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in row) + '</tr>' for row in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{r}</tbody></table>'

def d100_label(lo, hi): return f'{lo:02d}' if lo == hi else f'{lo:02d}–{hi:02d}'.replace('–100', '–00')

def ranges(items):
    n = len(items)
    if 100 % n: return None
    w = 100 // n
    return [(d100_label(i * w + 1, (i + 1) * w), it) for i, it in enumerate(items)]

def rolltable(items, title_col='Ergebnis', cls=''):
    r = ranges(items)
    if r: return table(['d100', title_col], [[a, e(b)] for a, b in r], cls)
    n = len(items)
    return table(['Nr.', title_col], [[i + 1, e(x)] for i, x in enumerate(items)], cls)

def wordlist(items, name, cols=4):
    n = len(items)
    li = ''.join(f'<li><b>{i+1:02d}</b> {e(x)}</li>' for i, x in enumerate(items))
    return f'<div class="wl"><div class="cap">{e(name)} ({n} Einträge): d100 würfeln{", bei Ergebnis über " + str(n) + " neu würfeln" if n < 100 else ""}. 00 = 100.</div><ul style="column-count:{cols}">{li}</ul></div>'

def fate_chart():
    head = ['Chancen \\ Spannung'] + [str(s) for s in range(1, 10)]
    rows = []
    for o in range(-3, 4):
        row = [f'<b>{e(ODDS[o+3])}</b> ({o:+d})']
        for s in range(1, 10):
            a, b, c = thr(o, s)
            row.append(f'{a if a else "–"}<br>{b}<br>{c}')
        rows.append(row)
    return table(head, rows, 'fate')

def fate_pct():
    return table(['Chancen', 'Spannung 5: JA oder JA+'], [[e(ODDS[o+3]), f'{thr(o,5)[1]} %'] for o in range(-3, 4)], 'small')

def event_focus():
    desc = {
     'fern': ('Etwas Fernes rührt sich', 'tun + thema'),
     'zeichen': ('Ein Zeichen oder Vorzeichen', 'art + thema'),
     'neu': ('Etwas oder jemand Neues tritt auf', 'art + rolle'),
     'akteur_handelt': ('Ein bekannter Akteur handelt', 'tun + thema'),
     'akteur_leidet': ('Ein bekannter Akteur leidet', 'tun + thema'),
     'akteur_gewinnt': ('Ein bekannter Akteur gewinnt', 'tun + thema'),
     'strang_voran': ('Ein offener Strang kommt voran', 'tun + thema'),
     'strang_zurueck': ('Ein offener Strang wirft zurück', 'tun + thema'),
     'strang_ende': ('Ein offener Strang geht zu Ende', 'tun + thema'),
     'figur_schaden': ('Eine Figur der Gruppe wird bedroht', 'tun + thema'),
     'figur_gunst': ('Eine Figur der Gruppe hat Glück', 'tun + thema'),
     'kontext': ('Die Umgebung verändert sich', 'tun + thema')}
    rows, lo = [], 1
    for k, w in DIRS:
        rows.append([d100_label(lo, lo + w - 1), desc[k][0], desc[k][1]]); lo += w
    return table(['d100', 'Fokus des Ereignisses', 'Wortpaar aus'], rows, '')

def mut_table():
    nm = {'ersetzen': 'ersetzen: ein Element wird ausgetauscht', 'hinzufuegen': 'hinzufügen: ein Element kommt dazu',
          'entfernen': 'entfernen: ein Element fehlt', 'steigern': 'steigern: ein Element ist stärker als erwartet',
          'daempfen': 'dämpfen: ein Element ist schwächer als erwartet'}
    rows, lo = [], 1
    for k, w in MUTS:
        rows.append([d100_label(lo, lo + w - 1), nm[k]]); lo += w
    return table(['d100', 'Abwandlung'], rows)

def scene_table():
    rows = []
    for s in range(1, 10):
        t = 5 * s; b = round(bruch_share(s) * 100)
        rows.append([s, f'01–{t:02d}', f'01–{b:02d}', f'{b+1:02d}–00'])
    return table(['Spannung', 'Szene verändert?', 'Dann: Unterbrechung', 'Sonst: Abwandlung'], rows, 'small')

def ziel_table():
    g = POOLS['ziel']
    ks = list(g.keys())
    rows = [[i + 1] + [e(g[k][i]) for k in ks] for i in range(8)]
    return table(['d8'] + [k.capitalize() for k in ks], rows, 'ziel')

def gespraech():
    items = [x['w'] for x in POOLS['gespraech']]
    return wordlist(items, 'Gesprächsthema', 2)

def d10(items, c='Ergebnis'): return table(['d10', c], [[i + 1, e(x)] for i, x in enumerate(items[:10])], 'small')
