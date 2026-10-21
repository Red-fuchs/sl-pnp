"""Kapitel 11 Gegenstände & Händler: HTML aus items/data/*.json (nur Darstellung, keine eigenen Regeln)."""
import json, os, sys, glob
H = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.dirname(H))
from tables import e, table
import tables as T
import items.roll as R
D = R.D; SEL = D['seltenheit']; PR = R.PR; KAT = D['kategorien']; HM = D['haendler']; ODDS = R.ODDS

def fmt(h):
    t, r = divmod(h, 4); s, hh = divmod(r, 2)
    return ' '.join(x for x in (f'{t}&nbsp;T' if t else '', f'{s}&nbsp;S' if s else '', f'{hh}&nbsp;H' if hh else '') if x) or '0&nbsp;H'
def rng(lo, hi): return f'{lo:02d}' if lo == hi else f'{lo:02d}–{hi:02d}'.replace('–100', '–00')
def d20r(lo, hi): return str(lo) if lo == hi else f'{lo}–{hi}'
def pc(o, sp=5): return T.thr(max(-3, min(3, o)), sp)[1]
GM = '<span class="gm">Nur Spielleitung</span>'

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

def entry(t, fields=()):
    txt = t['text']; head, sep, rest = txt.partition(': ')
    s = (f'<u>{e(head)}</u>{e(sep)}{e(rest)}' if sep and len(head) < 32 else e(txt))
    for f, lab in fields: s += f' <i>{lab}: {e(t[f])}</i>' if t.get(f) else ''
    return s
def wl(cap, li, cols=1, size=None, big=False):
    st = f'column-count:{cols}' + (f';font-size:{size}pt' if size else '')
    return f'<div class="wl rl{" big" if big else ""}"><div class="cap">{cap}</div><ul style="{st}">{li}</ul></div>'
def band_li(tab, fields=()):
    return ''.join(f'<li><b>{rng(t["von"], t["bis"])}</b> {entry(t, fields)}</li>' for t in tab)
def str_li(lst, start=1): return ''.join(f'<li><b>{i + start:02d}</b> {e(x)}</li>' for i, x in enumerate(lst))

def cat_list(k):
    li = ''
    for it in k['items']:
        v = f'Sch. {it["schaden"]}' if 'schaden' in it else (f'Rü. {it["ruestung"]}' if 'ruestung' in it else '')
        extra = ' · '.join(y for y in [v, e(it.get('effekt', ''))] if y)
        li += f'<li><b>{rng(it["von"], it["bis"])}</b> {e(it["name"])} <i>{fmt(it["preis_h"])}</i>{" · " + extra if extra else ""}</li>'
    return wl(f'{e(k["name"])} (d20 {d20r(*k["d20"])}), Gegenstand d100', li, 2, 6.6)

def stufe_table():
    return table(['Stufe', 'Beispiel', 'Chancen-Schritt', 'Seltenheit je Posten', 'Plunder'],
                 [[str(s['stufe']), e(s['beispiel'].split(',')[0]), f'{s["orakel"]:+d}'.replace('+0', '±0'),
                   'zwei Würfe, der gewöhnlichere zählt' if s['wuerfe'] == -2 else 'ein Wurf' if s['wuerfe'] == 1 else f'{s["wuerfe"]} Würfe, der seltenere zählt',
                   f'gewöhnlich: d6 ≤ {s["plunder_d6"]}' if s['plunder_d6'] else '–'] for s in HM['stufen']], 'small nw')

def example_orakel():
    """Straßenbrauer vs. Meisteralchemist, gerechnet gegen die Fate-Chart."""
    sel = R.SBY['selten']; assert ODDS[sel['orakel'] + 3] == 'unwahrscheinlich'
    s1 = R.hat_schritte(1, True); s4 = R.hat_schritte(4, True); assert (s1, s4) == (0, 2)
    o1, o4 = sel['orakel'] + s1, sel['orakel'] + s4; a1 = T.thr(o1, 5); a4 = T.thr(o4, 5)
    assert ODDS[o1 + 3] == 'unwahrscheinlich' and ODDS[o4 + 3] == 'wahrscheinlich'
    kat = next(k for k in D['kategorien'] if k['id'] == 'trank'); it = next(i for i in kat['items'] if i['name'] == 'Stärkungstrank'); assert it['von'] <= 24 <= it['bis'], it
    assert R.preis(it['preis_h'], 'selten', 'magisch', True) == 600 and R.preis(it['preis_h'], 'gewoehnlich', 'plunder') == 30
    assert T.thr(0, 5)[1] < 63 <= T.thr(0, 5)[2] and a1[1] < 63 <= a1[2] and a4[0] < 41 <= a4[1], (a1, a4)
    return f'''<div class="box ex"><b class="t">Beispiel 1: ein seltener Trank, zwei Händler.</b> Die Gruppe sucht einen <b>seltenen Trank</b>. Frage ans Orakel: „Hat der Händler einen seltenen Trank?“ Start-Chancen für selten: <b>unwahrscheinlich</b>. Spannung 5.<br>
<b>Straßenbrauer</b> (Stufe 1: −1, Spezialgebiet Tränke: +1, zusammen ±0 → <b>unwahrscheinlich</b>): JA+ ≤ {a1[0]}, JA ≤ {a1[1]}, NEIN ≤ {a1[2]}. d100 = <b>63</b>: <b>NEIN</b>. Die Gruppe gibt 1 SP und verschiebt auf offen ({T.thr(0, 5)[1]} %): 63 reicht trotzdem nicht. „Hab nur Gebräu für Mutige.“ Er hat dann etwas anderes: Art-Wurf Trank, d100 = 24 Stärkungstrank (30 T), Seltenheit gewöhnlich, Prägung d20 = 2 <b>Plunder</b>: {fmt(30)} (30 T × ¼), wirkt nur halb.<br>
<b>Meisteralchemist</b> (Stufe 4: +1, Spezialgebiet: +1 → +2 Schritte von unwahrscheinlich = <b>wahrscheinlich</b>): JA+ ≤ {a4[0]}, JA ≤ {a4[1]}, NEIN ≤ {a4[2]}. d100 = <b>41</b>: <b>JA</b>. Prägung d20 in der Spalte selten = 11 → <b>magisch</b>. Trank: Wirkung doppelt, also <b>+20 auf Kampf eine Szene</b>. Preis: Trank, also Basis × 5 = <b>150 T</b> (15 Budgetpunkte: nur als Beute oder Belohnung). Ein dauerhafter seltener Gegenstand kostet dagegen Stufenpreis 500 T + Basis. Wäre der Wurf 08 gewesen (≤ {a4[0]}, JA+), kennt der Händler außerdem die Herkunft des Tranks (ein Wortpaar und eine Frage gratis).</div>'''

def example_magie():
    w = D['wirkungen']['tabelle']; ent = w[28]; assert ent['text'].startswith('Zunftkrug'), ent['text']
    assert R.fold(79, D['wirkungen']['fenster']['selten']) == 29 and 'verraten' in T.POOLS['tun'] and 'Lüge' in T.POOLS['thema']
    Nn = D['namen']; ep, bz = Nn['epitheton'][4], Nn['bezug'][40]; NM = f"{ep}{'' if ep.endswith('e') else 'e'} Siegelring {bz}"
    a_, b_ = T.thr(0, 5), T.thr(-1, 5); assert a_[0] < 37 <= a_[1] and b_[1] < 71 <= b_[2]
    return f'''<div class="box ex"><b class="t">Beispiel 2: ein seltener Siegelring in drei Schritten.</b> Siegelring (60 T), Seltenheit selten, Prägung magisch.<br>
<b>1 Rahmen:</b> d100 = 79 liegt über dem Fenster selten (26–75): −50 = <b>29</b>. <i>{e(ent['text'])}</i><br>
<b>2 Wortpaar</b> (aus den Orakel-Wortlisten tun + thema): <b>verraten · Lüge</b>. Gemma oder die Spielleitung deutet es: Der Ring wird warm, wenn jemand im Raum lügt; er wurde einst von einem Verräter getragen.<br>
<b>3 Fragen</b> (höchstens zwei, nur wenn sie reizen): „Kennt jemand den Ring?“ (offen, Spannung 5): d100 = 37: <b>JA</b>, der Wirt der nächsten Schenke erkennt ihn und weiß, wem er gehörte. „Will jemand ihn zurückhaben?“ (unwahrscheinlich): d100 = 71: <b>NEIN</b>.<br>
Name (optional, zwei d100): <i>Der {e(NM)}</i>.</div>'''

def pages():
    ids = [s['id'] for s in SEL]
    arts = table(['d20', 'Art'], [[d20r(*k['d20']), f'<b>{e(k["name"])}</b>'] for k in KAT], 'small nw')
    selt = table(['d100', 'Seltenheit', 'Magie ab', 'Fenster'], [[rng(*s['d100']), f'<b>{e(s["name"])}</b>', f'{s["magie_h"]//4} T' if s.get('magie_h') else '–',
                 rng(*D['wirkungen']['fenster'][s['id']]) if s['id'] in D['wirkungen']['fenster'] else '–'] for s in SEL], 'small nw')
    pr = table(['Prägung (Preis ×)'] + [e(s['name']) for s in SEL], praegung_rows(), '')
    css = '<style>.it .wl.rl ul{font-size:7.2pt;line-height:1.12} .it table{font-size:8pt;margin-bottom:1.5mm} .it h3{margin:1.5mm 0 .6mm} .it td{padding:.4mm 1.4mm} .it .nw td:first-child{white-space:nowrap} .it .wl.big{break-inside:auto;page-break-inside:auto} .it .gm{border:1pt solid #000;padding:0 2mm;font:bold 8pt Georgia,serif;margin-left:3mm;background:#fff;color:#000;letter-spacing:.4pt} .it h1 .gm{font-size:9pt;vertical-align:middle}</style>'
    p1 = f'''{css}<h1 class="pb">11 Gegenstände und Händler <span class="note">(Vorschlag)</span></h1>
<div class="grid"><div style="width:44%"><div class="box"><b class="t">Münzen</b><br>1 Taler (T) = 2 Schilling (S) = 4 Heller (H). „3 T 1 S 1 H“ = 3¾ Taler.<br><b>10 Taler = 1 Budgetpunkt</b> (Figurenerschaffung). Posten unter 10 T zahlst du in Taler.</div></div>
<div><b>Würfe für einen Gegenstand:</b><ol style="margin-bottom:0"><li><b>Art:</b> d20 → Kategorie, dann d100 → Gegenstand (Listen am Ende dieses Kapitels; 01–60 gängig, 61–80 spezialisiert, 81–00 exotisch).</li>
<li><b>Seltenheit:</b> d100 (oder von der Spielleitung gesetzt).</li>
<li><b>Prägung:</b> d20 in der Spalte der Seltenheit.</li>
<li><b>Eigenschaften:</b> ohne Magie 1–2 Merkmale (Seite Merkmale); mit Magie ein Rahmen aus der Wirkungstabelle, ab selten dazu ein Wortpaar und bis zu zwei Orakelfragen.</li></ol></div></div>
<p><b>Preis:</b> gewöhnlich, gut, Plunder = <b>Basis × Prägung</b> (Plunder ×¼, normal ×1, gut ×1½); die Seltenheit macht sie nur schwerer zu finden. <b>Magisch/gesegnet = Basis + Stufenpreis</b> (ungewöhnlich 250 T · selten 500 T · sehr selten 1000 T · legendär 2000 T), verflucht die Hälfte davon. Wendung: Basis × Seltenheit. Tränke und andere Verbrauchsgüter: magisch/gesegnet Basis × 5, verflucht Basis × 2. Ab 10 T auf 5 T runden. <b>Budgetpunkte</b> = Preis ÷ 10 T, aufgerundet. Mit 200 T (20 Punkte) ist Magie nie zu bezahlen. Startausrüstung: höchstens Tarif 60 T (6 Punkte) je Stück; exotische Waffen und Rüstungen der Liste darüber sind Beute oder Kauf im Spiel.</p>
<div class="grid"><div style="width:36%"><h3>Art (d20)</h3>{arts}</div><div style="width:40%"><h3>Seltenheit (d100)</h3>{selt}<p class="note">Fenster: Welcher Teil der Wirkungstabellen gilt (Seite Magie). Normale Ausrüstung bleibt auf den Tarifen 20 T (2 P) · 40 T (4 P) · 60 T (6 P).</p></div>
<div><h3>Wirkung begrenzt</h3><p class="note">Je seltener, desto weiter hinten in der d100-Tabelle: Seltenheit schiebt ein Fenster. Grenzen: Schaden 5, Rüstung 3 (auch mit Magie); +1 Schaden/Rüstung nur bei Waffe und Rüstung.</p></div></div>
<h3>Prägung (d20, Spalte = Seltenheit)</h3>{pr}
<div style="column-count:2;column-gap:5mm;font-size:8pt;line-height:1.2">{"".join(f'<p style="margin-bottom:.6mm"><b>{e(p["name"])}:</b> {e(p["text"])}</p>' for p in D["praegung"] if p["id"] not in ("normal",))}<p style="margin-bottom:.6mm"><b>Tränke:</b> magisch/gesegnet = Wirkung doppelt (Heilung durch Tränke wird nie verdoppelt; der Heiltrank heilt nach Seltenheit 1/2/3/4 LP, vier nur ab sehr selten); verflucht = Nebenwirkung bis zur Nachtruhe. <b>Vergiftet:</b> −10 auf alles, 1 LP Verlust je Szene bis Gegengift oder Nachtruhe.</p></div>'''
    p2 = f'''<h1 class="pb">11 Händler: Orakel statt Matrix</h1>
<p><b>Hat der Händler genau das?</b> ist eine <b>Orakelfrage</b> auf der Fate-Chart (Kap. 6), keine eigene Regel. Start-Chancen nach Seltenheit, dann Schritte auf der Chancenleiter, Spannung wie in der Szene (Standard 5).</p>
<div class="grid"><div style="width:44%"><h3>Start-Chancen</h3>{table(['Seltenheit', 'Chancen', 'JA / JA+'], [[f'<b>{e(s["name"])}</b>', e(ODDS[s["orakel"] + 3]), f'{pc(s["orakel"])} %'] for s in SEL], 'small nw')}
<h3>Schritte (zusammenzählen)</h3><ul style="font-size:8.2pt;margin:0"><li>Händlerstufe: 1 → −1 · 2, 3 → ±0 · 4 → +1 · 5 → +2</li><li>Spezialgebiet (gefragte Kategorie): +1</li><li>Großstadt, Hafen, Markttag, Messe: +1</li><li>Wildnis, Krieg, Belagerung, Seuche: −1</li><li>1 SP: ein Schritt, wie immer</li><li><b>Deckel</b> (alle Schritte und SP zusammen): selten höchstens wahrscheinlich, sehr selten höchstens offen, legendär höchstens unwahrscheinlich</li><li>Jede Frage gilt einmal je Händler und Stück; ein NEIN bleibt bis zum nächsten Markttag</li></ul></div>
<div><h3>Antworten lesen</h3><ul style="font-size:8.4pt;margin:0"><li><b>JA+</b> (außergewöhnlich): er hat es, in besserer Prägung (Plunder → normal → gut, Preis folgt); bei Magie kennt der Händler die Herkunft: ein Wortpaar und eine Frage gratis.</li><li><b>JA</b>: er hat es.</li><li><b>NEIN</b>: er hat es nicht; würfle den Posten wie unten.</li><li><b>NEIN+</b>: er hat es nicht, aber bietet Ähnliches an, das nicht stimmt: Fälschung oder Falle (Wendung, die Spielleitung würfelt).</li></ul>
<h3>Händlerstufen</h3>{stufe_table()}</div></div>
<div class="grid"><div style="width:50%"><h3>Was hat er da? (Ablauf)</h3><ol style="font-size:8.4pt"><li>Posten: <b>d6 + Stufe</b>.</li><li>Je Posten: d6 1–4 → aus seinem <b>Spezialgebiet</b>, sonst Art würfeln (d20). Ohne Spezialgebiet immer Art würfeln.</li><li><b>Seltenheit</b>: ein d100 auf die Seltenheitstabelle, bei Stufe 4 und 5 mehrfach (der seltenere zählt), bei Stufe 1 zwei Würfe (der gewöhnlichere zählt).</li><li>Prägung (d20), Merkmale oder Wirkung. Fluch und Wendung würfelt die Spielleitung.</li><li>Preis ausrechnen, Namen und eine Zeile Beschreibung erfinden.</li></ol></div>
<div><h3>Weitere Orakelfragen (Spielleitung)</h3><ul style="font-size:8.2pt;margin:0">{"".join(f'<li><b>{e(f["text"])}</b> {e(f["chancen"])}</li>' for f in D["orakel"]["fragen_gm"][1:])}</ul></div></div>
{example_orakel()}
<p class="note">Handeln: Sozial-Probe, jeder Erfolgsgrad −10 % Preis (Vorschlag). Alltagsware (Tabelle Seite Magie) hat feste Preise und braucht keine Frage.</p>'''
    ft = D['wirkungen']['fenster']
    fenster = table(['Seltenheit', 'Fenster (d100)', 'Würfe', 'Kraft'],
                    [['ungewöhnlich', rng(*ft['ungewoehnlich']), '1', 'ein Effekt, meist +10 oder ein Trick'], ['selten', rng(*ft['selten']), '1', 'ein bis zwei kleine Effekte'],
                     ['sehr selten', rng(*ft['sehr_selten']), '1', 'zwei bis drei, auch +1 Schaden oder Rüstung'], ['legendär', rng(*ft['legendaer']), '2 (verschiedene Art)', 'zwei starke Effekte']], 'small nw')
    p3 = f'''<h1 class="pb">11 Magische Gegenstände: Rahmen, Wortpaar, Fragen</h1>
<p><b>Ungewöhnliche und gewöhnliche Stücke</b> bekommen nur Merkmale (Seite danach). <b>Magische, gesegnete und verfluchte Gegenstände</b> (und Wendungen) haben einen <b>Rahmen</b> aus den Wirkungstabellen. Ab <b>selten</b> kommen dazu ein <b>Wortpaar</b> und bis zu zwei <b>Orakelfragen</b>, damit jedes Stück eine eigene Geschichte hat.</p>
<div class="grid"><div style="width:50%"><h3>Fenster: wie Seltenheit die Tabelle schiebt</h3>{fenster}<p class="note">Ein d100. Liegt der Wurf <b>unter</b> dem Fenster, +50; <b>darüber</b>, −50. So zählen vorne die kleinen, hinten die starken Einträge. Gleiches Fenster für Wirkung, Segen, Fluch und Wendung.</p></div>
<div><h3>Die drei Schritte (ab selten)</h3><ol style="font-size:8.4pt"><li><b>Rahmen:</b> ein d100 in der Tabelle Wirkung oder Segen (legendär zweimal). Er legt die Mechanik fest und liegt innerhalb der Grenzen.</li><li><b>Wortpaar:</b> je ein Wort aus den Wortlisten <i>tun</i> und <i>thema</i> des Orakels. Art, Herkunft und Haken des Stücks.</li><li><b>Fragen:</b> höchstens zwei Ja/Nein-Fragen, nur wenn sie reizen: <i>Hat es einen Preis? Kennt jemand es? Will jemand es zurück? Ist sein Ursprung bekannt? Zieht es Ärger an?</i> (Start meist offen, Fate-Chart wie immer.)</li></ol></div></div>
<div class="box"><b class="t">Grenzen für alle magischen Gegenstände</b> (damit nichts durchbricht):<ul style="font-size:8.2pt;margin:.5mm 0 0">
<li><b>Pro Probe</b> zählen alle Gegenstände zusammen höchstens <b>+20</b> (mit 3 SP bis +50). Schaden insgesamt 5, Rüstung 3; Überschuss wird <b>ein</b> +10 auf die Verteidigung.</li>
<li><b>Aktive Fähigkeiten</b> (Neuwurf, Orakel verschieben, Schutz, Trick) zählen wie SP: bei einer Probe mit <b>Schicksalsergeben</b> gelten nur passive Boni. Einmal pro Szene oder Sitzung gilt je Gegenstand.</li>
<li><b>SP:</b> höchstens ein Segen mit „+1 SP“ je Figur, einmal pro Sitzung, nie über das Maximum. Kein Gegenstand erhöht das SP-Maximum.</li>
<li><b>Heilung durch Gegenstände:</b> höchstens 2 LP je Anwendung, einmal pro Sitzung und Ziel, zusammen höchstens 6 LP je Sitzung und Figur (Tränke ausgenommen). Ausnahme <b>Heiltrank</b>: 1 LP gewöhnlich, 2 ungewöhnlich, 3 selten, 4 nur ab sehr selten.</li></ul></div>
{example_magie()}
<h3>Alltag (feste Preise)</h3>{table(['Ware', 'Preis'], [[e(a['name']), fmt(a['preis_h'])] for a in D['alltag']], 'small nw')}'''
    wk = D['wirkungen']['tabelle']; sg = D['segen']['tabelle']
    p4 = f'''<h1 class="pb">11 Magische Wirkung (d100)</h1><p class="note">Fenster nach Seltenheit anwenden (Seite davor). Schaden-/Rüstungs-Einträge gelten nur für Waffe bzw. Rüstung, sonst neu würfeln. Einträge vorne sind schwächer.</p>
{wl("Wirkung magisch", band_li(wk), 2, 6.2, True)}'''
    p5 = f'''<h1 class="pb">11 Segen (d100)</h1><p class="note">Für gesegnete Gegenstände, gleiches Fenster. Die fünf Einträge mit „+1 SP“ stehen ganz hinten.</p>
{wl("Wirkung gesegnet", band_li(sg), 2, 6.4, True)}'''
    fl = D['flueche']['tabelle']; wd = D['wendungen']['tabelle']
    p6 = f'''<h1 class="pb">11 Fluch (d100) {GM}</h1>
<div class="box" style="font-size:8pt"><b class="t">Regeln des Fluchs.</b> Wirkung aus der Tabelle magisch (immer ein Vorteil), dazu ein Fluch aus dieser Tabelle (Fenster nach Seltenheit; Stufe 1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden). <b>Klebt:</b> jeder verfluchte Gegenstand lässt sich nicht ablegen oder verkaufen, bis der Fluch gelöst ist. <b>Hunger:</b> zu Beginn der Sitzung zahlt der Träger die genannten SP; sonst ruht die Wirkung und es gilt −10 auf alle Proben mit ihm; zwei Sitzungen hintereinander ungezahlt: der Fluch rückt eine Stufe vor (neu würfeln im nächsten Fenster). <b>Lösen:</b> Weihe kostet den halben Stufenpreis (der andere Teil des Preises) plus Wissen-Probe schwer eines Priesters; sehr selten und legendär verlangen zusätzlich einen abgeschlossenen Handlungsstrang. <b>Erkennen:</b> Wissen-Probe schwer, beim Zuschlagen, oder Orakelfrage „Erkennt jemand den Fluch?“.</div>
{wl("Fluch (Haken = Aufhänger für die Spielleitung)", band_li(fl, [("haken", "Haken")]), 2, 6.5, True)}'''
    p7 = f'''<h1 class="pb">11 Wendung (d100) {GM}</h1><p class="note">Für Gegenstände mit Prägung Wendung (und NEIN+ beim Händler). Fenster nach Seltenheit; Stücke deutet die Spielleitung passend zum Gegenstand. Die Enthüllung steht kursiv; sie gibt es nur, wenn die Gruppe das Geheimnis aufdeckt. Fragen dazu: <i>Ist es echt?</i> (unwahrscheinlich), <i>Weiß der Verkäufer es?</i> (offen).</p>
{wl("Wendung (verborgene Wahrheit)", band_li(wd, [("enthuellung", "Enthüllung")]), 2, 6.5, True)}'''
    M = D['merkmale']; g = {'hart': 'hart: Waffe, Rüstung, Werkzeug', 'stoff': 'Stoff: Kleidung', 'zier': 'Zier: Schmuck, Kuriosum', 'papier': 'Papier: Schrift', 'tier': 'Tier und Gefährt: Transport'}
    mats = ''.join(wl(f'Material ({g[k]}), d20', str_li(M['material'][k]), 1, 7) for k in g)
    p8 = f'''<h1 class="pb">11 Merkmale gewöhnlicher Gegenstände</h1>
<p><b>Wie viele?</b> Plunder: <i>Zustand</i> (d100, 01–30). Gut gearbeitet: <i>Machart</i>. Gewöhnlich: Material und ein Merkmal nach Wahl (Herkunft, Besonderheit oder Zustand). Ungewöhnlich und Wendung: Material, Machart und Besonderheit. Alle fünf nur für Gegenstände mit Geschichte. Merkmale ändern den Preis nicht; die kleinen Boni (+10 einmal pro Szene, −10 in einer Lage) sind Besonderheiten. Material, Machart und Zustand deutet die Spielleitung passend zum Gegenstand (sonst neu würfeln: „Klinge“ bei einem Mantel wird zur Schnittkante).</p>
<div class="two" style="column-count:5;column-gap:3mm">{mats}</div>
{wl("Machart (d100)", str_li(M['machart']), 3, 6.9)}{wl("Zustand (d100; 01–15 schlecht, 86–00 makellos)", str_li(M['zustand']), 3, 6.9)}'''
    N = D['namen']
    p9 = f'''<h1 class="pb">11 Herkunft, Besonderheit, Namen</h1>
{wl("Herkunft (d100)", str_li(M['herkunft']), 3, 6.9)}{wl("Besonderheit (d100; mit „;“ steht eine kleine Regel dabei)", str_li(M['besonderheit']), 2, 6.9)}
<h3>Namensgenerator für besondere Gegenstände (zwei d100)</h3><p class="note">Name = <b>Der/Die/Das</b> + Epitheton (+e) + Gegenstand + Bezug. Beispiel: Epitheton 05 + Schwert (n) + Bezug 41. Oder nur Gegenstand + Bezug („Klinge der stillen Witwe“). Ab selten, bei magischen Stücken und Wendungen.</p>
<div class="grid"><div>{wl("Epitheton (d100, Endung -e anhängen)", str_li(N['epitheton']), 4, 6.9)}</div><div>{wl("Bezug (d100)", str_li(N['bezug']), 2, 6.9)}</div></div>'''
    cats = ''.join(cat_list(k) for k in KAT)
    p10 = '<h1 class="pb">11 Gegenstandslisten (Art d20, Gegenstand d100)</h1><p class="note">Preise in Taler (T), Schilling (S) und Heller (H). Sch. = Schaden, Rü. = Rüstung. 01–60 gängig, 61–80 spezialisiert, 81–00 exotisch.</p>' + cats
    return [f'<div class="it">{x}</div>' for x in (p1, p2, p3, p4, p5, p6, p7, p8, p9, p10)]
