#!/usr/bin/env python3
"""Baut handout/Schicksalsschlag-Spieler.pdf (weasyprint). Preise aus handout/items/data/preise.json.
Eigener Einstieg, rührt build.py (Voll-Handout, später GM-Buch) nicht an."""
import base64, json, os, subprocess

H = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(H)
PRICES = json.load(open(os.path.join(ROOT, 'items', 'data', 'preise.json'), encoding='utf-8'))
RED, GOLD, INK, OK = '#8a1f2b', '#a9822f', '#241c20', '#2f6b4f'


def coin(h):
    """Heller -> 'T S H' (1 T = 2 S = 4 H), Nullstellen weg."""
    t, r = divmod(h, 4); s, hh = divmod(r, 2)
    return ' '.join(x for x in (f'{t} T' if t else '', f'{s} S' if s else '', f'{hh} H' if hh else '') if x) or '0'
assert coin(14) == '3 T 1 S' and coin(15) == '3 T 1 S 1 H' and coin(8) == '2 T'


def img(n):
    return 'data:image/png;base64,' + base64.b64encode(open(os.path.join(H, 'img', n), 'rb').read()).decode()


def ic(name, c=RED, s=14):
    g = {
        'quill': f'<path d="M6 28 L24 8 Q28 4 30 6 Q32 10 26 14 L10 30 Z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/><path d="M6 28 L4 33" stroke="{c}" stroke-width="2" stroke-linecap="round"/>',
        'die': f'<path d="M18 3 L32 11 V25 L18 33 L4 25 V11 Z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/><path d="M18 3 V33 M4 11 L32 25 M32 11 L4 25" stroke="{c}" stroke-width="1" opacity=".5"/>',
        'eye': f'<path d="M2 18 Q18 4 34 18 Q18 32 2 18 Z" fill="none" stroke="{c}" stroke-width="2"/><circle cx="18" cy="18" r="5" fill="{c}"/>',
        'star': f'<path d="M18 3 L22 14 L33 14 L24 21 L28 32 L18 25 L8 32 L12 21 L3 14 L14 14 Z" fill="{c}"/>',
        'coin': f'<circle cx="18" cy="18" r="13" fill="none" stroke="{c}" stroke-width="2"/><circle cx="18" cy="18" r="8" fill="none" stroke="{c}" stroke-width="1" opacity=".6"/><path d="M18 11 V25 M14 14 H20 Q22 14 22 16 T20 18 H15 M15 18 H21 Q23 18 23 20.500 T20 23 H14" fill="none" stroke="{c}" stroke-width="1.4"/>',
        'sword': f'<path d="M30 4 L12 22 M10 20 L16 26 M8 28 L4 32 M26 8 L30 4 L32 6" fill="none" stroke="{c}" stroke-width="2.400" stroke-linecap="round"/>',
        'shield': f'<path d="M18 3 L31 8 V18 Q31 28 18 33 Q5 28 5 18 V8 Z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/>',
        'heart': f'<path d="M18 31 C4 21 3 11 10 8 C14 6.500 17 9 18 12 C19 9 22 6.500 26 8 C33 11 32 21 18 31 Z" fill="{c}"/>',
        'speech': f'<path d="M4 6 H32 V24 H18 L10 31 V24 H4 Z" fill="none" stroke="{c}" stroke-width="2" stroke-linejoin="round"/>',
    }[name]
    return f'<svg width="{s*1.0}mm" height="{s*1.0}mm" viewBox="0 0 36 36">{g}</svg>'


def hearts(n=10, cls=RED):
    return '<svg width="120mm" height="9mm" viewBox="0 0 600 45">' + ''.join(
        f'<g transform="translate({i*60+6},2) scale(1.1)"><path d="M18 31 C4 21 3 11 10 8 C14 6.500 17 9 18 12 C19 9 22 6.500 26 8 C33 11 32 21 18 31 Z" fill="{cls}"/></g>' for i in range(n)) + '</svg>'


def stars(n=5, s=9):
    return f'<svg width="{n*s*1.15:.0f}mm" height="{s}mm" viewBox="0 0 {n*40} 36">' + ''.join(
        f'<g transform="translate({i*40},0)"><path d="M18 3 L22 14 L33 14 L24 21 L28 32 L18 25 L8 32 L12 21 L3 14 L14 14 Z" fill="{GOLD}"/></g>' for i in range(n)) + '</svg>'


def budget_bar():
    cw, g = 30, 4
    cells, x = [], 0
    spec = [RED] * 6 + ['#e5dcc9'] * 14 + [GOLD] * 2
    for c in spec:
        cells.append(f'<rect x="{x}" y="22" width="{cw}" height="30" rx="3" fill="{c}" stroke="{INK}" stroke-width=".8"/>'); x += cw + g
    w = x
    def br(a, b, t, col, y=60):
        xa, xb = a * (cw + g), b * (cw + g) - g
        return f'<path d="M{xa} {y} v6 H{xb} v-6" fill="none" stroke="{col}" stroke-width="1.6"/><text x="{(xa+xb)/2}" y="{y+22}" text-anchor="middle" font-size="13" font-family="Helvetica Neue,Helvetica,sans-serif" fill="{col}" font-weight="700">{t}</text>'
    top = f'<text x="0" y="14" font-size="12" font-family="Helvetica Neue,Helvetica,sans-serif" fill="{INK}">20 Punkte Startbudget</text><path d="M0 18 H{20*(cw+g)-g}" stroke="{INK}" stroke-width=".8"/><text x="{w-g}" y="14" text-anchor="end" font-size="12" font-family="Helvetica Neue,Helvetica,sans-serif" fill="{GOLD}" font-weight="700">+2 aus Schwäche</text>'
    return f'<svg width="100%" viewBox="0 0 {w} 118">{top}{"".join(cells)}{br(0,6,"−6 Stärken",RED)}{br(6,22,"= 16 Punkte übrig",INK)}</svg>'


def d100_bar():
    X0, U, Y, Ht = 10, 8.8, 40, 34
    def x(r): return X0 + (r - 1) * U
    segs = [(1, 10, '#1f5a41', '6'), (11, 20, '#2f6b4f', '5'), (21, 30, '#43835f', '4'), (31, 40, '#5f9b78', '3'), (41, 50, '#84b698', '2'), (51, 60, '#abd0bb', '1'),
            (61, 69, '#e8b4ae', '1'), (70, 79, '#d98c85', '2'), (80, 89, '#c4645e', '3'), (90, 100, '#a33a3a', '4+')]
    o = ['<text x="10" y="14" font-size="13" fill="#2f6b4f" font-weight="700" font-family="Helvetica Neue,Helvetica,sans-serif">ERFOLG: Wurf 01–60 (≤ Zielzahl)</text>',
         '<text x="890" y="14" font-size="13" fill="#8a1f2b" font-weight="700" text-anchor="end" font-family="Helvetica Neue,Helvetica,sans-serif">MISSERFOLG: Wurf 61–100</text>']
    for a, b, c, t in segs:
        w = (b - a + 1) * U
        tc = '#fff' if c in ('#1f5a41', '#2f6b4f', '#43835f', '#c4645e', '#a33a3a', '#5f9b78') else INK
        o.append(f'<rect x="{x(a)-U/2+U/2:.1f}" y="{Y}" width="{w:.1f}" height="{Ht}" fill="{c}" stroke="#fff" stroke-width="1.5"/><text x="{x(a)+w/2:.1f}" y="{Y+22}" text-anchor="middle" font-size="16" font-weight="700" font-family="Georgia,serif" fill="{tc}">{t}</text>')
        o.append(f'<text x="{x(a)+w/2:.1f}" y="{Y+Ht+12}" text-anchor="middle" font-size="11" fill="#6b6068" font-family="Helvetica Neue,Helvetica,sans-serif">{a:02d}–{b:02d}</text>')
    # 01-05 und 96-100 Sonderstreifen
    o.append(f'<rect x="{x(1):.1f}" y="{Y+Ht+18}" width="{5*U:.1f}" height="5" fill="#1f5a41"/><text x="{x(1):.1f}" y="{Y+Ht+36}" font-size="12" font-weight="700" fill="#1f5a41" font-family="Helvetica Neue,Helvetica,sans-serif">01–05: immer Erfolg</text>')
    o.append(f'<rect x="{x(96):.1f}" y="{Y+Ht+18}" width="{5*U:.1f}" height="5" fill="#a33a3a"/><text x="{x(100)+U:.1f}" y="{Y+Ht+36}" text-anchor="end" font-size="12" font-weight="700" fill="#a33a3a" font-family="Helvetica Neue,Helvetica,sans-serif">96–100: immer Misserfolg</text>')
    # Zielzahl-Marke
    xt = x(60) + U
    o.append(f'<path d="M{xt:.1f} {Y-6} v{Ht+12}" stroke="{INK}" stroke-width="2"/><path d="M{xt-5:.1f} {Y-14} h10 l-5 8 z" fill="{INK}"/><text x="{xt:.1f}" y="{Y-18}" text-anchor="middle" font-size="13" font-weight="700" font-family="Helvetica Neue,Helvetica,sans-serif" fill="{INK}">Zielzahl 60</text>')
    # Pasch
    for r in [11, 22, 33, 44, 55, 66, 77, 88, 99, 100]:
        o.append(f'<circle cx="{x(r)+U/2:.1f}" cy="{Y+Ht+58}" r="3.600" fill="{GOLD}"/><text x="{x(r)+U/2:.1f}" y="{Y+Ht+74}" text-anchor="middle" font-size="11" fill="#6b6068" font-family="Helvetica Neue,Helvetica,sans-serif">{"99 · 100" if r==99 else ("" if r==100 else r)}</text>')
    o.append(f'<text x="10" y="{Y+Ht+62}" font-size="12" font-weight="700" fill="{GOLD}" font-family="Helvetica Neue,Helvetica,sans-serif">Pasch =</text>')
    return f'<svg width="100%" viewBox="0 0 900 {Y+Ht+86}">' + ''.join(o) + '</svg>'


def oracle_ladder():
    words = ['fast unmöglich', 'sehr unwahr&shy;scheinlich', 'unwahr&shy;scheinlich', 'offen', 'wahr&shy;scheinlich', 'sehr wahr&shy;scheinlich', 'fast sicher']
    cols = ['#a33a3a', '#c4645e', '#dba09a', '#e6dcc4', '#aed0bd', '#6ea686', '#2f6b4f']
    cells = ''.join(f'<td style="background:{c};color:{"#fff" if i in (0,6) else INK};text-align:center;font-weight:700;font-size:8.2pt;padding:3mm 1mm;border:1.2mm solid #fff;border-radius:2mm;{"outline:1.4pt solid "+INK+";" if i==3 else ""}">{w}</td>' for i, (w, c) in enumerate(zip(words, cols)))
    return f'<table style="table-layout:fixed;margin:2mm 0 1mm;border-collapse:separate"><tr>{cells}</tr></table><div style="display:table;width:100%;font-size:8pt;color:#6b6068"><span style="display:table-cell">← weniger Chance auf JA</span><span style="display:table-cell;text-align:right">mehr Chance auf JA →</span></div>'


def price_rows():
    want = ['Laib Brot, Krug Bier', 'Warme Mahlzeit, Bett im Schlafsaal', 'Einzelzimmer mit Frühstück', 'Fackel, Kerze, Zunder', 'Überfahrt, Fährmann',
            'Tagelohn (Handlanger, Magd)', 'Tagelohn (Geselle, Söldner)', 'Bestechung Torwache (klein)', 'Wirtshaus-Gelage (ganze Runde)']
    by = {a['name']: a['preis_h'] for a in PRICES['alltag']}
    return ''.join(f'<tr><td>{n.replace("Warme Mahlzeit, Bett im Schlafsaal","Warme Mahlzeit / Bett im Schlafsaal")}</td><td class="n"><b>{coin(by[n])}</b></td></tr>' for n in want)


assert PRICES['muenzen']['heller_pro_taler'] == 4 and PRICES['muenzen']['heller_pro_schilling'] == 2


def cover():
    deco = f'<svg class="deco" width="64mm" height="64mm" viewBox="0 0 200 200"><g fill="none" stroke="#d6b25e" stroke-width="1.6"><path d="M100 10 L180 55 V145 L100 190 L20 145 V55 Z"/><path d="M100 10 V190 M20 55 L180 145 M180 55 L20 145" opacity=".45"/><path d="M100 10 L180 145 L20 145 Z" opacity=".7"/><circle cx="100" cy="100" r="34" opacity=".6"/></g><text x="100" y="116" text-anchor="middle" font-family="Georgia,serif" font-size="46" fill="#d6b25e" font-weight="700">100</text></svg>'
    return f'''<section class="pg cover"><div class="band">{deco}
<p class="kick">Spieler-Handout</p><h1>Schicksal&shy;schlag</h1>
<p class="lead">Dunkle Fantasy, ein Würfel, deine Geschichte. Du erzählst, was deine Figur tut. <b>sl</b>, die KI-Spielleitung, erzählt, was die Welt daraus macht.</p></div>
<div class="sixty"><h2>So funktioniert’s in 60 Sekunden</h2>
<div class="step"><div class="ic">{ic('quill', RED, 12)}</div><div><h3>1 · Erzähle, was du tust</h3><p>Ein Satz reicht: „Ich schleiche an der Wache vorbei.“ Ist nichts riskant, geht’s einfach weiter.</p></div></div>
<div class="step"><div class="ic">{ic('die', RED, 12)}</div><div><h3>2 · Würfle, wenn es riskant wird</h3><p>Ein W100, und du willst <b>niedrig</b> würfeln: gleich oder unter deiner Zielzahl ist ein Erfolg. Mehr Abstand heißt: besser gelungen.</p></div></div>
<div class="step"><div class="ic">{ic('eye', RED, 12)}</div><div><h3>3 · Frag das Orakel, wenn die Welt entscheidet</h3><p>„Ist die Tür verschlossen?“ Die Antwort lautet JA+, JA, NEIN oder NEIN+.</p></div></div>
<div class="step"><div class="ic">{ic('star', GOLD, 12)}</div><div><h3>4 · Biege das Schicksal</h3><p>Du hast 5 Schicksalspunkte (SP). Jeder gibt ±10 auf einen Wurf, oder schiebt das Orakel auf deine Seite.</p></div></div>
<div class="toc" style="margin-bottom:4mm"><b>Wörter, die oft vorkommen</b> &nbsp; <b>W100</b> zwei Zehnerwürfel, 00 zählt als 100 · <b>Zielzahl</b> würfle gleich oder darunter · <b>SP</b> Schicksalspunkte · <b>LP</b> Lebenspunkte · <b>sl</b> die KI-Spielleitung im Chat · <b>Spielleitung</b> der Mensch, der den Abend leitet und sl bei Bedarf übernimmt · <b>Foundry</b> der Spieltisch im Browser · <b>Szene</b> ein Ort, ein Zeitraum; sl sagt, wann eine neue beginnt</div>
<div class="toc" style="margin-top:0"><b>Inhalt</b> &nbsp; Das Setting: Berufung, Blick des Schicksals, Fremdkraft (S. 2–3) · Deine Figur (S. 4–5) · Proben (S. 6–7) · Schicksalspunkte (S. 8) · Kampf &amp; LP (S. 9) · Orakel, Geld &amp; Einkaufen (S. 10) · Spickzettel (S. 11)<br><b>Anhang</b> &nbsp; Leitfaden für den ersten Abend in Foundry (S. 12–14)</div></div></section>'''


def setting1():
    return f"""<section class="pg dense"><p class="kick">Das Setting · Fadenleihe</p><h1>Du wirst gerufen</h1>
<p class="lead">Ein Abend, eine Nacht in einer fremden Welt. Du gehörst nicht hierher, und genau deshalb hat man dich geholt.</p>
<h2>Die Berufung</h2>
<p>Im schlimmsten Moment deines Lebens (ein Sturz, ein Speer, ein Systemabsturz, ein Strick) greift etwas nach dir. Dann erwachst du in einem Kreis aus Asche am Rand eines Moores. In der Hand hältst du, was du auch im Augenblick des Zugriffs gehalten hast. Um die Handgelenke liegt ein feines Garn. Neben dir erwachen die anderen: Fremde aus anderen Welten, so verloren wie du.</p>
<p>Eine uralte Macht hat euch einberufen, <b>die Weberin</b>. Sie wirkt gegen das Schicksal selbst und braucht Menschen, die nicht in dessen Fäden eingewoben sind. Sie gibt euch einen Auftrag, der in <b>einer Nacht</b> zu schaffen ist. Löst ihr ihn, werdet ihr zurückgebracht. Mehr sagt sie nicht.</p>
<p class="small mute">Es gibt <b>keine Starttaverne</b>: Ihr beginnt gemeinsam im Aschekreis und lernt euch dort kennen. Eure Figuren dürfen aus jeder Welt, jeder Zeit und jedem Beruf stammen.</p>
<div class="box ex"><span class="lab">Euer Begleiter</span>Im Kreis wartet ein <b>sprechendes Tier</b>, das die Weberin an euch gebunden hat (die Spielleitung spricht für es). <b>Es sieht nur, was ihr seht</b>: Ohne euch ist es blind und taub, es leiht sich eure Sinne, kann also nichts auskundschaften. Es kennt die Gegend, aber nicht alles, und löst nichts für euch. Es stammt wie ihr nicht aus dieser Welt und fällt dem Schicksal noch eher auf: Was es laut vor Fremden sagt oder tut, hebt auch euren Blick.</div>
<h2>Der Blick des Schicksals</h2>
<p>Für das Schicksal seid ihr <b>Störungen im Gewebe</b>. Je mehr ihr auffallt, desto genauer sieht es hin. Das ist die <b>Spannung</b> dieses Abenteuers, und sie heißt hier <b>Blick des Schicksals</b>. Die Zahl (1–9) kennt nur die Spielleitung. Ihr spürt sie an den Zeichen:</p>
<table><tr><th>Blick</th><th>Was ihr merkt</th></tr>
<tr><td><b>1–3 unbemerkt</b></td><td>Niemand achtet auf euch. Ihr seid Fremde unter vielen.</td></tr>
<tr><td><b>4–6 Fäden zittern</b></td><td>Zufälle häufen sich: Münzen fallen falsch, Hunde heulen, man starrt euch nach.</td></tr>
<tr><td><b>7–8 Boten suchen</b></td><td>Das Schicksal schickt Boten. Wachen fragen nach Fremden, Einheimische werden misstrauisch.</td></tr>
<tr><td><b>9 Eingriff</b></td><td>Das Schicksal greift zu: etwas Handfestes, nicht zu übersehen. Danach beruhigt sich die Welt, aber die Zeit läuft euch davon.</td></tr></table>
<div class="cols"><div class="card"><h3>Was den Blick hebt</h3><ul class="small"><li>Jeder Einsatz einer <b>Fremdkraft</b> (+1)</li><li>Spektakuläres vor Zeugen: Feuer, Kampf auf dem Markt, Technik aus eurer Welt</li><li>Mit Schicksalspunkten (SP, S. 8) die Würfe anderer biegen (+1)</li></ul></div>
<div class="card"><h3>Was ihn senkt</h3><ul class="small"><li>Ruhige Szenen, in denen ihr nichts Auffälliges tut (am Szenenende −1)</li><li><b>Untertauchen</b>: euch eine Szene lang verbergen, nichts bewegen (−1)</li><li>Ein <b>Ritual der Weberin</b> an einer Webstelle (die Spielleitung nennt sie): Garn um die Hand knoten, 1 SP ausgeben. −2, einmal je Ort.</li><li>Sich dem Schicksal ergeben (S. 8): am Szenenende −1</li></ul></div></div>
<p class="small mute">Am Szenenende verschiebt er sich um 1–2: wilde Szenen heben ihn, ruhige senken ihn. Nach einem Eingriff fällt er auf die Mitte zurück. Sagt eure Spielleitung, dass der Faden zieht, ist das eure Warnung.</p></section>"""


def setting2():
    return f"""<section class="pg dense"><p class="kick">Das Setting · Fadenleihe, Teil 2</p><h1>Deine Figur aus einer anderen Welt</h1>
<p class="lead" style="margin-bottom:3mm">Baue sie wie auf Seite 4–5 beschrieben. Drei Fragen helfen dir beim Schreiben:</p>
<ol class="small" style="margin-bottom:1mm"><li><b>Woher kommst du?</b> Welche Welt, welcher Stand? Was hat dich in diesem Moment fast oder ganz umgebracht?</li><li><b>Was kannst du?</b> Zwei, drei Stärken und echte Schwächen. Eine Stärke darf übernatürlich sein: deine <b>Fremdkraft</b>.</li><li><b>Was hattest du in der Hand?</b> Es kommt mit dir, wenn es nicht zu groß ist (kein Auto, kein Pferd).</li></ol>
<h2 style="margin-top:3mm">Die Fremdkraft</h2>
<p>Jede Figur darf <b>eine</b> übernatürliche Fähigkeit aus ihrer Heimatwelt mitbringen: Magie, Hexenblick, Hackerinstinkt, ein Eid, der trägt. Magie ist hier also erlaubt. Sie wirkt wirklich, aber sie hat einen Preis.</p>
<table><tr><th>Regel</th><th>So funktioniert es</th></tr>
<tr><td><b>Kosten</b></td><td>Wie eine große Stärke (S. 4): <b>4 Punkte</b> aus deinen 20. Sie gibt +20 auf die Zielzahl passender Proben.</td></tr>
<tr><td><b>Preis</b></td><td>Jeder Einsatz hebt den <b>Blick des Schicksals um 1</b>, auch wenn die Probe misslingt.</td></tr>
<tr><td><b>Grenzen</b></td><td>Immer eine Probe, nie automatisch. Wirkt auf <b>ein Ziel oder eine Szene</b>. Kein Sofort-Sieg, nichts wird ungeschehen gemacht. Schaden höchstens wie ein Schwert (3) plus Erfolgsgrade (S. 7, 9).</td></tr>
<tr><td><b>Auf dem Bogen</b></td><td><span class="cmd">/sl /merkmal +Fremdkraft: Hexenblick</span> (zählt automatisch als große Stärke). Pro Figur nur eine.</td></tr></table>
<h2>Ausrüstung aus deiner Welt</h2>
<p class="small">Preise wie bei normalen Gegenständen (2, 4 oder 6 Punkte; 1 Punkt = 10 Taler, S. 5). Alltagsdinge übersetzt das Gewebe in örtliche Entsprechungen: das Smartphone wird ein glattes schwarzes Täfelchen, die Jacke ein Wams. Waffen bleiben, <b>Munition ist endlich</b>. Seltsame Technik funktioniert unzuverlässig (eine Taschenlampe flackert im Herzschlag), und sie vor Zeugen zu benutzen hebt den Blick. Was zu groß für ein Garn ist, bleibt daheim.</p>
<h2>Drei Beispiele (jede geht im 20-Punkte-Budget auf)</h2>
<div class="box ex"><span class="lab">Brida Hauk, Söldnerin aus einer Fantasywelt</span><i>„Zwölf Jahre Freikompanie Graustich. Beim Fall von Nessach schwor ich den Schildeid: Ich stelle mich vor jeden, der schwächer ist. Ich trinke, bis meine Hände ruhig werden, und schulde der Kompanie 200 Silber. Ein Speer öffnete mir den Panzer, das Schwert hatte ich in der Faust.“</i><br><span class="small"><b>Stärken:</b> geübte Schwertkämpferin (4) · <b>Fremdkraft:</b> Schildeid (4) · <b>Schwächen:</b> Trinkerin (+2), Schulden (+2), kann keinen Hilferuf ignorieren (+4) · <b>Ausrüstung:</b> Schwert 4, Kettenhemd 4, Schild 4, +1 max. SP, 50 Taler. Rechnung: 20 + 8 − 8 = 20 = 12 + 3 + 5.</span></div>
<div class="box ex"><span class="lab">Tarek Nowak, Rettungssanitäter aus unserer Welt</span><i>„Neun Jahre Nachtschicht im Rettungswagen in Dortmund. Seit dem Autobahnunfall letzten Winter habe ich Flashbacks, und ich kann keinen Verletzten liegen lassen. Gezogen wurde ich mit dem Notfallrucksack in der Hand, als ein Lkw den Wagen rammte.“</i><br><span class="small"><b>Stärken:</b> Notfallmedizin (4), Deeskalation (2) · <b>Fremdkraft:</b> Letzter Atem (4): hält Sterbende eine Szene lang über der Schwelle · <b>Schwächen:</b> Flashbacks (+2), lässt niemanden liegen (+4), kein Kämpfer (+2) · <b>Ausrüstung:</b> Notfallrucksack 2, Klappmesser 2, +1 max. SP, 110 Taler. Rechnung: 20 + 8 − 10 = 18 = 4 + 3 + 11.</span></div>
<div class="box ex"><span class="lab">Mireth Dohlenbach, Hexe aus einer Welt der Kräuterfrauen</span><i>„Ich brachte mein Dorf durch zwei Seuchen und sehe Lügen als Flackern im Auge des Gegenübers. Dafür wollte man mich verbrennen, seitdem fürchte ich Feuer und verachte Amtsträger. Gezogen wurde ich mit dem Messer in der Hand, mit dem ich den Strick durchschnitt.“</i><br><span class="small"><b>Stärken:</b> Kräuterkunde (2), Giftmischerin (2) · <b>Fremdkraft:</b> Hexenblick (4) · <b>Schwächen:</b> Feuerangst (+2), verachtet Amtsträger (+2), gesucht als Hexe (+2) · <b>Ausrüstung:</b> Messer 2, Kräuterbeutel 2, +1 max. SP, 110 Taler. Rechnung: 20 + 6 − 8 = 18 = 4 + 3 + 11.</span></div>
</section>"""


def figur1():
    return f'''<section class="pg"><p class="kick">01 · Deine Figur</p><h1>Aus einer Geschichte werden Werte</h1>
<p class="lead">Du schreibst keine Werte auf. Du schreibst, wer deine Figur ist. Aus Stärken und Schwächen wird ihr Können.</p>
<div class="cols"><div class="card"><div class="big">1</div><h3>Schreib 3–8 Sätze</h3><p class="small">Woher kommt sie? Was kann sie? Was hat sie verloren, wer ist hinter ihr her, wovor hat sie Angst?</p></div>
<div class="card"><div class="big">2</div><h3>sl sucht die Merkmale</h3><p class="small">Aus deinem Text zieht sl Worte heraus: <b>Stärken</b> („geübter Bogenschütze“) und <b>Schwächen</b> („Angst vor Feuer“).</p></div>
<div class="card"><div class="big">3</div><h3>Du gibst 20 Punkte aus</h3><p class="small">Stärken kosten Punkte. <b>Schwächen geben Punkte zurück.</b> Was übrig bleibt, wird Geld, Ausrüstung oder Schicksal.</p></div></div>
<h2>Das Budget: 20 Punkte</h2>
<table><tr><th>Merkmal (Stärke oder Schwäche)</th><th class="n">Budget</th><th>Wirkung auf passende Proben</th></tr>
<tr><td><b>Stärke klein</b> („trinkfest“)</td><td class="n"><b class="pm">−2</b></td><td>+10 auf die Zielzahl</td></tr>
<tr><td><b>Stärke groß</b> („geübter Bogenschütze“)</td><td class="n"><b class="pm">−4</b></td><td>+20 auf die Zielzahl</td></tr>
<tr><td><b>Schwäche klein</b> („Angst vor Feuer“)</td><td class="n"><b class="pm">+2</b></td><td>−10 auf die Zielzahl</td></tr>
<tr><td><b>Schwäche groß</b> („Todfeind: Schmugglerbande“)</td><td class="n"><b class="pm">+4</b></td><td>−20 auf die Zielzahl</td></tr></table>
<div class="box ex"><span class="lab">Beispiel</span>Du wählst die Stärken <b>geübter Bogenschütze</b> (kostet 4) und <b>trinkfest</b> (kostet 2): zusammen 6 Punkte. Dazu die Schwäche <b>Angst vor Feuer</b>: du bekommst 2 Punkte zurück. Rechnung: 20 − 6 + 2 = <b>16 Punkte übrig</b>.</div>
<div style="margin:2mm 0 0">{budget_bar()}</div>
<h2>Drei Säulen: Kampf, Sozial, Wissen</h2>
<p>Eine <b>Säule</b> ist ein Grundwert deiner Figur. Du verteilst <b>30, 40 und 50</b> in beliebiger Reihenfolge. Die Säule ist der Startwert jeder Probe.</p>
<div class="cols"><div class="card c">{ic('sword', RED, 10)}<h3>Kampf</h3><p class="small mute">Zuschlagen, schießen, ausweichen, schleichen, durchhalten</p></div>
<div class="card c">{ic('speech', RED, 10)}<h3>Sozial</h3><p class="small mute">Überreden, drohen, lügen, bezirzen, verhandeln</p></div>
<div class="card c">{ic('quill', RED, 10)}<h3>Wissen</h3><p class="small mute">Lesen, heilen, Rätsel lösen, Runen deuten, sich erinnern</p></div></div>
<p class="small mute" style="margin-top:2mm">Beispiel: Mirne wählt Kampf <b>40</b>, Sozial <b>30</b>, Wissen <b>50</b>. Ihre Figur ist eine Botin und Kräuterkundige, also hoch im Wissen.</p></section>'''


def figur2():
    return f'''<section class="pg"><p class="kick">01 · Deine Figur, Teil 2</p><h1>Was mit dem Rest passiert</h1>
<p class="lead">Übrige Punkte verfallen nicht. Du tauschst sie in eine von drei Währungen.</p>
<div class="cols"><div class="card c">{ic('coin', GOLD, 10)}<h3>Taler</h3><p class="small"><b>1 Punkt = 10 Taler</b> Startgeld.</p></div>
<div class="card c">{ic('shield', GOLD, 10)}<h3>Ausrüstung</h3><p class="small">Nach Stufe: <b>2, 4 oder 6 Punkte</b> je Stück (siehe unten).</p></div>
<div class="card c">{ic('star', GOLD, 10)}<h3>Schicksal</h3><p class="small"><b>3 Punkte = +1</b> maximaler Schicksalspunkt.</p></div></div>
<h2>Ausrüstung nach Stufe</h2>
<div class="cols"><div class="card"><span class="pill">2 Punkte · 20 T</span><p class="small" style="margin-top:2mm"><b>Gewöhnlich:</b> normale Ausrüstung, Messer, Dolch, Knüppel, <b>Lederwams</b> (Rüstung 1)</p></div>
<div class="card"><span class="pill red">4 Punkte · 40 T</span><p class="small" style="margin-top:2mm"><b>Kampfausrüstung:</b> Schwert, Axt, Bogen, Speer, Armbrust, <b>Kettenhemd</b> (Rüstung 2), Schild</p></div>
<div class="card"><span class="pill gold">6 Punkte · 60 T</span><p class="small" style="margin-top:2mm"><b>Schwerstes Gerät:</b> <b>Plattenpanzer</b> (Rüstung 3) oder eine Feuerwaffe</p></div></div>
<p class="small mute">Alles ist normal und nicht magisch. Kennt sl einen Gegenstand nicht, zählt er als gewöhnlich (2 Punkte). <b>Passt ein Gegenstand zu deiner Geschichte</b> (Mirnes Armbrust zu „Armbrust gegen Raben“), wird er ein <b>★ Story-Item</b>: gleicher Preis, aber er kann mit deiner Geschichte wachsen. Manchmal steckt mehr dahinter. Das erfährst du im Spiel.</p>
<h2>Beispiel: Mirne</h2>
<div class="box ex"><span class="lab">Mirne Aschenbach, Botin und Kräuterkundige</span><i>„Tochter eines Salzsieders, früh mit der Armbrust gegen Raben geübt. Als Botin sah sie Schmugglergold und schwieg. Der Zöllner schuldet ihr einen Gefallen, die Schmuggler wollen sie tot sehen. Seit die Siederei brannte, erstarrt sie vor Feuer.“</i></div>
<div class="cols"><div><table><tr><th>Merkmal</th><th class="n">Pkt.</th></tr>
<tr><td>geübte Armbrustschützin</td><td class="n"><b class="pm">−4</b></td></tr>
<tr><td>5 kleine Stärken (lesen, Moorkräuter, Pfade im Moor, Zöllner-Gefallen, zäh)</td><td class="n"><b class="pm">−10</b></td></tr>
<tr><td>Todfeind: Schmuggler</td><td class="n"><b class="pm">+4</b></td></tr>
<tr><td>Angst vor Feuer</td><td class="n"><b class="pm">+2</b></td></tr></table></div>
<div><table><tr><th>Rechnung</th><th class="n">Pkt.</th></tr>
<tr><td>20 + 4 + 2 = Budget</td><td class="n"><b>26</b></td></tr>
<tr><td>Stärken (4 + 10)</td><td class="n"><b>14</b></td></tr>
<tr><td>Rest zum Ausgeben</td><td class="n"><b>12</b></td></tr>
<tr><td>+1 max. SP (also 6)</td><td class="n">3</td></tr><tr><td>Armbrust</td><td class="n">4</td></tr><tr><td>Lederwams</td><td class="n">2</td></tr><tr><td>30 Taler</td><td class="n">3</td></tr></table></div></div>
<p class="small">Ergebnis: Kampf 40 · Sozial 30 · Wissen 50 · LP 10 · SP 6 von 6. Beim Schießen hat sie Kampf <b>60</b> (40 + 20 durch die Stärke „geübte Armbrustschützin“; die Armbrust selbst ist ein Gegenstand).</p>
<div class="box ex"><span class="lab">Kurz: Paladin (starke Ausrüstung braucht Schwächen)</span>
Die zwei großen Stärken „Geweihter Streiter“ und „Handauflegen“ kosten zusammen 8. Dafür nimmt der Paladin drei Schwächen: „Heiliger Schwur“ (groß, +4), „Fanatischer Feind: Kult“ (klein, +2) und „Arm wie eine Kirchenmaus“ (klein, +2) = +8. Budget bleibt 20: <b>Plattenpanzer (6) + Schwert (4) + Schild (4) + 1 SP (3) + 30 Taler (3) = 20.</b> Ohne die drei Schwächen blieben nur 12 Punkte: kein Schild, kein SP.</div></section>'''


def probe1():
    return f'''<section class="pg"><p class="kick">02 · Proben</p><h1>Würfle niedrig</h1>
<p class="lead">Eine Probe ist ein Wurf mit dem W100 (zwei Zehnerwürfel, Ergebnis 01–100, die Doppel-Null zählt als 100). Erst rechnest du deine Zielzahl, dann würfelst du <b>gleich oder darunter</b>.</p>
<h2>Deine Zielzahl</h2>
<div class="formula"><div><b>Säule</b><small>Kampf, Sozial oder Wissen (30/40/50)</small></div><div class="op">+</div><div><b>Merkmale</b><small>passende Stärke +10/+20, Schwäche −10/−20</small></div><div class="op">+</div><div><b>Schwierigkeit</b><small>leicht +20 … sehr schwer −30</small></div><div class="op">+</div><div><b>Zustände</b><small>LP, SP (falls es zutrifft)</small></div><div class="op">=</div><div class="res"><b>Zielzahl</b><small>Wurf ≤ Zielzahl: Erfolg</small></div></div>
<div class="cols"><div><table><tr><th>Schwierigkeit</th><th class="n">Zielzahl</th></tr><tr><td>leicht</td><td class="n"><b class="pm">+20</b></td></tr><tr><td>normal</td><td class="n"><b>±0</b></td></tr><tr><td>schwer</td><td class="n"><b class="pm">−20</b></td></tr><tr><td>sehr schwer</td><td class="n"><b class="pm">−30</b></td></tr></table></div>
<div><table><tr><th>Zustände</th><th class="n">Zielzahl</th></tr><tr><td>LP 3 oder weniger</td><td class="n"><b class="pm">−10</b></td></tr><tr><td>Nur noch 1 SP</td><td class="n"><b class="pm">−10</b></td></tr><tr><td>0 SP</td><td class="n"><b class="pm">−20</b></td></tr><tr><td>Freiwillig: Schicksalsergeben (S. 8)</td><td class="n"><b class="pm">−10</b></td></tr></table></div></div>
<p class="small mute">Alle Zahlen werden einfach addiert. „Passend“ heißt: das Merkmal hilft bei genau dieser Handlung. „Geübte Armbrustschützin“ hilft beim Schießen, nicht beim Überreden. Schwächen mit Auslöser („Angst vor Feuer“) greifen von selbst, sobald der Auslöser da ist. Du setzt die Häkchen, sl achtet darauf, dass sie stimmen.</p>
<h2>Drei Beispiele</h2>
<div class="box ex"><span class="lab">1 · Normal</span><b>Mirne schießt auf eine Brieftaube.</b> Kampf 40 + Armbrust 20 = <b>60</b>, Schwierigkeit normal. Sie würfelt <b>34</b>. 34 ist kleiner als 60: <b>Erfolg</b>. Die Taube fällt, der Brief bleibt heil.</div>
<div class="box ex"><span class="lab">2 · Schwer, mit kleiner Stärke</span><b>Kampf 40, eine passende kleine Stärke (+10), Schwierigkeit schwer (−20).</b> 40 + 10 − 20 = <b>30</b>. Würfelst du 30 oder weniger, gelingt es. Bei 31 oder mehr nicht.</div>
<div class="box ex"><span class="lab">3 · Schwächen zählen auch</span><b>Mirne soll durchs Feuer rennen.</b> Kampf 40, „Angst vor Feuer“ gilt für alle Proben nahe Flammen (−10), schwer (−20): 40 − 10 − 20 = <b>10</b>. Das ist knapp. Zeit, einen Schicksalspunkt zu überlegen.</div>
<div class="tip box"><span class="lab">Wann würfelst du?</span>Nur, wenn der Ausgang unsicher ist <b>und</b> es auf das Können deiner Figur ankommt. Sonst wird einfach erzählt. In Foundry fordert sl die Probe, du klickst und würfelst (siehe Anhang).</div></section>'''


def probe2():
    return f'''<section class="pg"><p class="kick">02 · Proben, Teil 2</p><h1>Wie gut hat es geklappt?</h1>
<p class="lead">Nicht nur „gelungen“ oder „gescheitert“. Je weiter du unter der Zielzahl bleibst, desto besser gelingt es.</p>
<h2>Der W100 für Zielzahl 60</h2>
{d100_bar()}
<p class="small mute" style="margin-top:1mm">Die große Zahl im Balken zeigt die <b>Erfolgsgrade</b> (grün) und die <b>Fehlergrade</b> (rot). Der Wurf 01 ist der beste, 100 der schlechteste.</p>
<div class="box ex"><span class="lab">So rechnest du</span><b>Erfolgsgrade = 1 + (Zielzahl − Wurf) ÷ 10</b>, abgerundet. Ziel 60, Wurf 34: Abstand 26, also 26 ÷ 10 = 2 (abgerundet), plus 1 = <b>3 Erfolgsgrade</b>. <b>Fehlergrade = 1 + (Wurf − Zielzahl) ÷ 10</b>, abgerundet. Wurf 47 gegen Ziel 40: Abstand 7, 7 ÷ 10 = 0, plus 1 = <b>1 Fehlergrad</b>. Ein Erfolg hat immer mindestens 1 Erfolgsgrad.</div>
<div class="cols"><div class="card"><h3>01–05 und 96–100</h3><p class="small"><b>01–05</b> ist immer ein Erfolg, auch bei winziger Zielzahl. <b>96–100</b> ist immer ein Misserfolg, auch bei riesiger Zielzahl.</p></div>
<div class="card"><h3>Pasch = kritisch</h3><p class="small">Zwei gleiche Ziffern (11, 22 … 99) oder 100. <b>Erfolg + Pasch:</b> sl lässt etwas zu deinen Gunsten passieren (eine Information, einen Vorteil, eine freundliche Reaktion). <b>Misserfolg + Pasch:</b> es gibt eine Komplikation.</p></div></div>
<div class="box ex"><span class="lab">Beispiel: kritischer Erfolg</span>Ziel 60, Wurf <b>33</b>: 3 Erfolgsgrade, und 33 ist ein Pasch. Du triffst nicht nur, sondern bekommst eine Wendung zu deinen Gunsten.</div>
<h2>Wenn jemand dagegenhält</h2>
<p><b>Vergleichende Probe:</b> beide würfeln. Wer mehr Erfolgsgrade hat, gewinnt. Gleichstand bei den Graden: die höhere Zielzahl gewinnt. Ein Erfolg schlägt immer einen Misserfolg. Scheitern beide, passiert erst einmal nichts.</p>
<div class="box ex"><span class="lab">Beispiel</span>Mirne (Sozial 30 + 10 für den Zöllner-Gefallen = 40) will an einer Wache vorbei. Sie würfelt <b>17</b>: Abstand 23, also <b>3 Erfolgsgrade</b>. Die Wache (Sozial 40) würfelt <b>31</b>: Abstand 9, also <b>1 Erfolgsgrad</b>. 3 gegen 1: Mirne wird durchgewunken.</div></section>'''


def sp():
    return f'''<section class="pg"><p class="kick">03 · Schicksalspunkte</p><h1>Das Schicksal ist biegsam</h1>
<p class="lead">Du startest mit <b>5 SP</b>. Dein Maximum steigt nur über das Budget (3 Punkte = +1). Gib sie vor dem Wurf aus oder direkt danach, <b>bevor</b> erzählt wird, wie es ausging.</p>
<div style="margin:0 0 3mm">{stars(5, 9)}</div>
<h2>Was SP kaufen</h2>
<table><tr><th class="n">Kosten</th><th>Wirkung</th></tr>
<tr><td class="n"><b>1 SP</b></td><td><b>±10</b> auf eine Probe: auf deine, aber auch auf die eines Gegners oder einer anderen Figur. Höchstens <b>3 SP pro Probe</b>.</td></tr>
<tr><td class="n"><b>1 SP</b></td><td>Schiebt die <b>Orakel-Chance</b> um eine Stufe (zum Beispiel von „offen“ auf „wahrscheinlich“).</td></tr>
<tr><td class="n"><b>2 SP</b></td><td><b>Neuwurf.</b> Das zweite Ergebnis zählt, auch wenn es schlechter ist.</td></tr>
<tr><td class="n"><b>1 SP</b></td><td>Bei <b>0 LP</b> am Leben bleiben. Du liegst am Boden, aber du lebst.</td></tr></table>
<div class="box ex"><span class="lab">Beispiel</span>Mirne entziffert einen verschmierten Brief: Wissen 50 + Lesen 10 − schwer 20 = <b>40</b>. Sie würfelt <b>47</b>, knapp daneben. Sie gibt <b>1 SP</b>: Zielzahl 50. Jetzt ist 47 ein Erfolg (1 Erfolgsgrad). Sie entziffert nur das Wesentliche.</div>
<div class="cols"><div><h2>Wenn die SP knapp werden</h2><table><tr><th>Stand</th><th>Folge</th></tr><tr><td>1 SP</td><td>„schicksalsmüde“: <b class="pm">−10</b> auf alle Proben</td></tr><tr><td>0 SP</td><td><b class="pm">−20</b> auf alle Proben, und Orakelfragen zu deinen Gunsten gehen eine Stufe schlechter</td></tr></table></div>
<div><h2>Wie du SP zurückbekommst</h2><table><tr><th>Anlass</th><th class="n">SP</th></tr><tr><td>Kurze Rast (eine Stunde)</td><td class="n"><b>+1</b></td></tr><tr><td>Nachtruhe, sicherer Ort</td><td class="n"><b>+3</b></td></tr><tr><td>Fest, Feier, Tempel</td><td class="n"><b>+2</b></td></tr><tr><td>Handlungsstrang (Quest) abgeschlossen</td><td class="n"><b>+2</b></td></tr><tr><td>Schwäche ausgespielt, sodass sie dich etwas kostet</td><td class="n"><b>+1</b></td></tr></table></div></div>
<p class="small mute">Mehr als dein Maximum geht nie. Ob eine Schwäche stark genug ausgespielt war, entscheidet sl.</p>
<div class="box key"><span class="lab">Schicksalsergeben</span><b>Ergib dich dem Schicksal.</b> Vor dem Wurf, bei einer Probe, bei der für deine Figur wirklich etwas auf dem Spiel steht, kannst du <b>−10</b> auf die Probe nehmen. Gelingt sie trotzdem mit <b>mindestens 2 Erfolgsgraden</b>, bekommst du <b>1 SP zurück</b>. Scheitert sie, ist es ein <b>Schicksalsschlag</b>: du bekommst einen Fehlergrad mehr als sonst, und sl erzählt die Folgen härter.
<p class="small" style="margin:2mm 0 0"><b>Regeln:</b> einmal pro Szene und Figur · nie bei leichten Proben, beim Wurf „Wer ist zuerst dran?“ oder bei reinen Übungen (sl entscheidet) · keine SP auf derselben Probe (weder deine noch fremde), nur der Neuwurf für 2 SP bleibt erlaubt.<br><b>Beispiel:</b> Mirne (Kampf 40) wagt den Sprung über die Zugbrücke. Ziel 40 − 10 = <b>30</b>. Wurf 20: 2 Erfolgsgrade, <b>+1 SP</b>. Wurf 25: nur 1 Grad, kein SP. Wurf 35: 1 Fehlergrad plus 1 durch den Schicksalsschlag = 2, die Brücke bricht weg.</p></div></section>'''


def kampf():
    return f'''<section class="pg"><p class="kick">04 · Kampf &amp; LP</p><h1>Zehn Lebenspunkte</h1>
<p class="lead">Jede Figur hat <b>10 LP</b> (Lebenspunkte). Sie zählen, wie viel Gesundheit übrig ist, nicht wie viele Wunden du hast.</p>
<div style="margin:0 0 3mm">{hearts(10)}</div>
<h2>Ein Angriff in drei Schritten</h2>
<div class="cols"><div class="card"><div class="big">1</div><h3>Angriff</h3><p class="small">Eine <b>Kampf-Probe</b>. Ein passendes Merkmal (zum Beispiel „geübte Armbrustschützin“) zählt dazu.</p></div>
<div class="card"><div class="big">2</div><h3>Abwehr</h3><p class="small">Der Gegner würfelt Kampf (parieren, ausweichen): es gilt die vergleichende Probe, mehr Erfolgsgrade treffen. Wehrt sich das Ziel nicht, reicht <b>1 Erfolgsgrad</b>.</p></div>
<div class="card"><div class="big">3</div><h3>Schaden</h3><p class="small"><b>Waffe + Erfolgsgrade des Angreifers − Rüstung.</b> So viele LP verliert das Ziel.</p></div></div>
<div class="cols"><div><table><tr><th>Waffe</th><th class="n">Schaden</th></tr><tr><td>Faust</td><td class="n"><b>1</b></td></tr><tr><td>Messer, Dolch, Knüppel</td><td class="n"><b>2</b></td></tr><tr><td>Schwert, Axt, Bogen, Armbrust</td><td class="n"><b>3</b></td></tr><tr><td>Feuerwaffe</td><td class="n"><b>4</b></td></tr></table></div>
<div><table><tr><th>Rüstung</th><th class="n">Abzug</th></tr><tr><td>Stoff</td><td class="n"><b>0</b></td></tr><tr><td>Leder</td><td class="n"><b>1</b></td></tr><tr><td>Kette</td><td class="n"><b>2</b></td></tr><tr><td>Platte</td><td class="n"><b>3</b></td></tr></table></div></div>
<div class="tip box"><span class="lab">Rüstung schützt auch dich</span>Sie zieht von jedem Treffer ab, den du einsteckst. Aber: <b>ein Treffer kostet dich mindestens 1 LP.</b></div>
<div class="box ex"><span class="lab">Beispiel: Mirne gegen einen Schmuggler</span>Mirne (Kampf 40, Armbrust +20, Lederwams 1) gegen einen Schmuggler (Kampf 40, Schwert 3, Leder 1, 8 LP; Gegner haben oft weniger LP als du). Mirne würfelt 28, der Schmuggler 35: Mirne ist zuerst dran.<br>
<b>Schuss:</b> Ziel 60, Wurf 41: 2 Erfolgsgrade. Der Schmuggler weicht aus (Ziel 40, Wurf 52): Misserfolg. Schaden: 3 + 2 − 1 = <b>4</b>. Schmuggler: 8 → 4 LP.<br>
<b>Gegenschlag:</b> Der Schmuggler würfelt 19 (3 Grade), Mirne pariert mit 38 (1 Grad). Er trifft: 3 + 3 − 1 = <b>5</b>. Mirne: 10 → <b>5 LP</b>.</div>
<div class="cols"><div class="card"><h3>3 LP oder weniger</h3><p class="small"><b>−10</b> auf alle Proben. Du bist angeschlagen.</p></div>
<div class="card"><h3>0 LP oder weniger</h3><p class="small">Du liegst am Boden. <b>1 SP</b> hält dich am Leben. Ohne SP droht der Tod; sl entscheidet im Sinn der Szene.</p></div></div>
<h2>Heilung</h2>
<p>Ein Heilkundiger versorgt eine Verletzung für <b>2 Taler</b> und heilt dabei <b>1 LP</b>. <b>Heiltränke heilen je nach Seltenheit 1–4 LP</b> (gewöhnlich 1, ungewöhnlich 2, selten 3, sehr selten oder legendär 4).</p>
<p class="small mute"><b>Wer ist zuerst dran?</b> sl sagt es an. Meist gilt: erst die Spieler, dann die Gegner. Genauer: alle würfeln W100 gegen ihren Kampfwert, mehr Erfolgsgrade handeln zuerst, bei Gleichstand die Spieler.</p></section>'''


def orakel_geld():
    return f'''<section class="pg"><p class="kick">05 · Orakel · Geld</p><h1>Wenn die Welt antwortet</h1>
<p class="lead">Dein Können würfelst du als Probe. Alles andere, was die Welt entscheidet, beantwortet das Orakel.</p>
<div class="cols"><div>
<h3>So fragst du</h3><ol><li>Stell eine <b>Ja/Nein-Frage</b>: „Ist die Hintertür unverschlossen?“</li><li>sl schätzt die Chance mit einem der Wörter unten.</li><li>sl würfelt einen W100 gegen die Chance: niedrig ist gut für JA. Antwort: <b>JA+</b> (ja, und besser), <b>JA</b>, <b>NEIN</b>, <b>NEIN+</b> (nein, und schlimmer).</li></ol></div>
<div><h3>Gut zu wissen</h3><ul><li>Fällt beim Orakelwurf ein Pasch, kann ein <b>Zufallsereignis</b> dazukommen: etwas Unerwartetes.</li><li><b>1 SP</b> schiebt die Chance eine Stufe zu dir. Mehr dazu auf S. 8.</li><li>Das Orakel antwortet auf Fragen zur <b>Welt</b>. Geht es um dein Können („Kann ich das?“), ist es immer eine Probe.</li></ul></div></div>
{oracle_ladder()}
<div class="box ex"><span class="lab">Beispiel</span>Mirne fragt: „Ist die Hintertür unverschlossen?“ sl schätzt <b>offen</b>: etwa 50 zu 50. Mirne gibt 1 SP und schiebt auf <b>wahrscheinlich</b>. Dabei steigt die Chance auf JA oder JA+ deutlich, etwa von 50 auf 70 Prozent.</div>
<h2>Geld und Einkaufen</h2>
<div class="cols"><div><div style="margin:0 0 2mm"><svg width="100%" viewBox="0 0 300 84"><g font-family="Georgia,serif" font-weight="700" text-anchor="middle"><circle cx="35" cy="35" r="30" fill="{GOLD}"/><text x="35" y="44" font-size="22" fill="#fff">T</text><text x="100" y="42" font-size="16" fill="{INK}" font-family="Helvetica Neue,sans-serif">=</text><circle cx="140" cy="35" r="22" fill="#b9b3ae"/><text x="140" y="43" font-size="18" fill="#fff">S</text><text x="190" y="42" font-size="16" fill="{INK}" font-family="Helvetica Neue,sans-serif">=</text><circle cx="235" cy="35" r="15" fill="#a2673a"/><text x="235" y="41" font-size="14" fill="#fff">H</text></g><text x="35" y="80" font-size="10" text-anchor="middle" font-family="Helvetica Neue,sans-serif" fill="{INK}">Taler</text><text x="140" y="80" font-size="10" text-anchor="middle" font-family="Helvetica Neue,sans-serif" fill="{INK}">Schilling</text><text x="235" y="80" font-size="10" text-anchor="middle" font-family="Helvetica Neue,sans-serif" fill="{INK}">Heller</text></svg></div>
<p><b>1 Taler = 2 Schilling = 4 Heller.</b> Kürzel: T, S, H.</p>
<p class="small"><b>Einkaufen:</b> Sag der Spielleitung, was du kaufst. Sie bucht es (Preis ab, Ware auf deinen Bogen). Taler und Ausrüstung änderst du nicht selbst.</p>
<p class="small"><b>Beispiel:</b> 3 T 1 S sind 3 × 4 + 1 × 2 = <b>14 Heller</b>. Und 15 Heller sind 3 T 1 S 1 H.</p>
<p class="small mute">Ausrüstung kostet Taler: Messer, Dolch, Knüppel, Leder 20 T · Schwert, Axt, Bogen, Armbrust, Speer, Kette, Schild 40 T · Platte, Feuerwaffe 60 T.</p></div>
<div><table><tr><th>Alltag</th><th class="n">Preis</th></tr>{price_rows()}</table></div></div>
<div class="cols"><div class="card"><h3>Händler fragen = Orakelfrage</h3><p class="small">Ob ein Händler etwas hat, ist keine Probe: frag das Orakel. „Hat der Schmied ein gutes Schwert?“</p></div>
<div class="card"><h3>★ Story-Items</h3><p class="small">Passt ein Gegenstand zu deiner Geschichte, ist er etwas Besonderes. Wie besonders, merkst du erst im Spiel.</p></div></div></section>'''


def spick():
    return f'''<section class="pg sheet"><p class="kick">Spickzettel</p><h1>Alles auf einer Seite</h1>
<div class="box key" style="margin:1mm 0 2mm"><b>Zielzahl = Säule + Merkmale + Schwierigkeit + Zustände.</b> W100 ≤ Zielzahl = Erfolg. 01–05 immer Erfolg, 96–100 immer Misserfolg. Pasch (11, 22 … 99, 100) = kritisch.<br><b>Erfolgsgrade = 1 + (Ziel − Wurf) ÷ 10</b>, abgerundet. Fehlergrade = 1 + (Wurf − Ziel) ÷ 10.</div>
<div class="cols"><div><h2>Modifikatoren</h2><table><tr><td>Stärke klein / groß</td><td class="n"><b class="pm">+10 / +20</b></td></tr><tr><td>Schwäche klein / groß</td><td class="n"><b class="pm">−10 / −20</b></td></tr><tr><td>leicht / schwer / sehr schwer</td><td class="n"><b class="pm">+20 / −20 / −30</b></td></tr><tr><td>LP ≤ 3</td><td class="n"><b class="pm">−10</b></td></tr><tr><td>nur noch 1 SP / 0 SP</td><td class="n"><b class="pm">−10 / −20</b></td></tr><tr><td>Schicksalsergeben</td><td class="n"><b class="pm">−10</b></td></tr><tr><td>1 SP ausgegeben (max. 3)</td><td class="n"><b class="pm">±10 je SP</b></td></tr></table>
<h2>Figur</h2><table><tr><td>Säulen</td><td class="n">30 / 40 / 50</td></tr><tr><td>Budget</td><td class="n">20 Punkte</td></tr><tr><td>Stärke klein / groß</td><td class="n">−2 / −4</td></tr><tr><td>Schwäche klein / groß</td><td class="n">+2 / +4</td></tr><tr><td>1 Punkt</td><td class="n">10 Taler</td></tr><tr><td>3 Punkte</td><td class="n">+1 max. SP</td></tr><tr><td>Gegenstand</td><td class="n">2 / 4 / 6 Pkt.</td></tr><tr><td>Fremdkraft (1 pro Figur)</td><td class="n">4 Pkt., Blick +1 je Einsatz</td></tr></table></div>
<div><h2>SP: Start 5</h2><table><tr><td>±10 auf eine Probe (max. 3 SP)</td><td class="n"><b>1 SP</b></td></tr><tr><td>Orakel eine Stufe schieben</td><td class="n"><b>1 SP</b></td></tr><tr><td>Neuwurf (zweiter Wurf zählt)</td><td class="n"><b>2 SP</b></td></tr><tr><td>Bei 0 LP am Leben bleiben</td><td class="n"><b>1 SP</b></td></tr></table>
<table><tr><th>Erholung</th><th class="n">SP</th></tr><tr><td>Rast (1 Std.) · Nacht / sicher</td><td class="n">+1 · +3</td></tr><tr><td>Fest / Tempel · Strang fertig</td><td class="n">+2 · +2</td></tr><tr><td>Schwäche ausgespielt</td><td class="n">+1</td></tr></table>
<h2>Schicksalsergeben</h2><p>Vor dem Wurf <b>−10</b>. Mind. 2 Erfolgsgrade: <b>+1 SP</b>. Misserfolg: +1 Fehlergrad. 1× pro Szene, nicht bei leichten Proben, nur Neuwurf (2 SP) erlaubt, sonst keine SP.</p></div>
<div><h2>Kampf &amp; LP</h2><table><tr><td>LP</td><td class="n">10</td></tr><tr><td>Schaden</td><td class="n">Waffe + Grade − Rüstung</td></tr><tr><td>Treffer auf dich</td><td class="n">min. 1 LP</td></tr><tr><td>Waffen</td><td class="n">1 · 2 · 3 · 4</td></tr><tr><td>Rüstung</td><td class="n">0 · 1 · 2 · 3</td></tr><tr><td>≤ 3 LP</td><td class="n">−10 auf alles</td></tr><tr><td>0 LP</td><td class="n">1 SP, sonst droht der Tod</td></tr></table>
<p class="small">Waffen: Faust, Messer/Dolch/Knüppel, Schwert/Axt/Bogen/Armbrust, Feuerwaffe. Rüstung: Stoff, Leder, Kette, Platte.</p>
<h2>Geld</h2><p><b>1 T = 2 S = 4 H.</b><br>Mahlzeit 1 S · Zimmer 1 T · Tagelohn 1 T (Geselle 2 T).<br>Heilkundiger 2 T = 1 LP.<br>Heiltränke heilen je nach Seltenheit 1–4 LP.</p></div></div>
<div class="cols"><div><h2>Orakel</h2><p>Frage → Chance: fast unmöglich · sehr unwahrscheinlich · unwahrscheinlich · <b>offen</b> · wahrscheinlich · sehr wahrscheinlich · fast sicher. Antwort: <b>JA+ · JA · NEIN · NEIN+</b>. Händler fragen = Orakelfrage.</p></div>
<div><h2>Vergleichende Probe</h2><p>Beide würfeln, mehr Erfolgsgrade gewinnt. Gleichstand bei den Graden: höhere Zielzahl. Erfolg schlägt Misserfolg.</p><h2>Kritisch</h2><p>Pasch + Erfolg: Wendung für dich. Pasch + Misserfolg: Komplikation.</p></div></div></section>'''


def shot(name, markers, cap_items, w='100%', ratio=None):
    m = ''.join(f'<span class="m" style="left:{x}%;top:{y}%">{i+1}</span>' for i, (x, y) in enumerate(markers))
    lis = ''.join(f'<li>{c}</li>' for c in cap_items)
    return f'<div class="fig" style="width:{w}"><div class="shot"><img src="{img(name)}">{m}</div><ol>{lis}</ol></div>'


def anhang1():
    return f'''<section class="pg"><p class="kick">Anhang · Leitfaden</p><h1>Dein erster Abend</h1>
<p class="lead">Sieben Schritte, dann bist du im Spiel. Du brauchst nur einen Browser. <b>Foundry</b> ist der Spieltisch im Browser.</p>
<div class="cols"><div style="width:56%">
<ol class="steps">
<li><div><h3>Link öffnen</h3><p>Die Spielleitung schickt dir einen Link zum Foundry-Spieltisch. Öffne ihn im Browser.</p></div></li>
<li><div><h3>Einloggen</h3><p>Wähle deinen Spielernamen und gib das Passwort ein, das du bekommen hast.</p></div></li>
<li><div><h3>Figur übernehmen</h3><p>Dir ist eine Figur zugewiesen. Öffne den Chat (Sprechblase rechts oben). Siehst du keine Figur, sag der Spielleitung Bescheid.</p></div></li>
<li><div><h3>Sag Hallo</h3><p>Schreib <span class="cmd">/sl Hallo</span> in den Chat. Antwortet sl, läuft alles.</p></div></li>
<li><div><h3>Figur anlegen</h3><p><span class="cmd">/sl /figur Name: Geschichte</span><br>Schreib deine Hintergrundgeschichte (3–8 Sätze). Beantworte: <b>Woher? Was kannst du? Was in der Hand?</b> sl antwortet mit den Merkmalen, deinen Säulen und deinem Budget.</p></div></li>
<li><div><h3>Merkmale prüfen</h3><p>Fehlt etwas, korrigiere es (nur vor der ersten Probe):<br><span class="cmd">/sl /merkmal +Stärke</span> &nbsp;·&nbsp; <span class="cmd">/sl /merkmal -Schwäche</span> &nbsp;·&nbsp; <span class="cmd">/sl /merkmal x Text</span> (streichen).<br>Ohne Zusatz klein. <b>Fremdkraft:</b> <span class="cmd">/sl /merkmal +Fremdkraft: Hexenblick</span>. Groß: <span class="cmd">/sl /merkmal +geübte Armbrustschützin major</span></p></div></li>
<li><div><h3>Budget ausgeben</h3><p><span class="cmd">/sl /budget taler=3 item=Armbrust,Lederwams sp=1</span><br><b>taler=3</b> sind 3 Punkte (30 Taler), <b>item=</b> die Gegenstände (2, 4 oder 6 Punkte je Stück), <b>sp=1</b> bedeutet +1 max. SP (3 Punkte). Mirne: 3 + 4 + 2 + 3 = 12.</p></div></li></ol></div>
<div><div class="chat"><div class="card2" style="border-left-color:#5b7fa6"><b>Mirne</b> · jetzt<br><span style="font-family:Menlo,monospace;font-size:7.6pt">/budget taler=3 item=Armbrust,Lederwams sp=1</span> <span class="num" style="margin:0 0 0 1mm;background:#e2a62e;color:#1a1216">1</span></div><div class="card2" style="margin-top:1.6mm"><b>Spielleiter</b> · sl<br>Budget: 30 Taler · Armbrust, Lederwams · SP-Max 6 <span class="num" style="margin:0 0 0 1mm;background:#e2a62e;color:#1a1216">2</span></div></div><p class="small mute" style="margin-top:-1.5mm">① Dein Befehl im Chat. ② sl bestätigt Taler, Gegenstände und SP-Maximum. (Skizze, so ungefähr sieht es aus.)</p>
<div class="box ex" style="margin-top:0"><span class="lab">Dann geht’s los</span>Schreib, was deine Figur tut:<br><span class="cmd">/sl Ich öffne die Tür.</span><br>Jede Aktion, die du in der Welt tust, beginnt mit <span class="cmd">/sl</span>. Ohne das Kürzel hört sl nicht zu, das ist dann Tischgespräch mit den anderen.</div>
</div></div>
<div class="box ex"><span class="lab">So sieht eine Figur-Nachricht aus</span><span class="cmd" style="white-space:normal">/sl /figur Mirne: Ich wuchs als Tochter eines Salzsieders im Moor auf und scheuchte mit der Armbrust Raben von den Salzpfannen. Als Botin im Zollhaus sah ich Schmugglergold und schwieg. Seitdem schuldet mir der Zöllner Ottokar einen Gefallen, und die Schmuggler wollen mich tot sehen. Ich kann lesen und schreiben und kenne die Heilkräuter des Moores. Seit die Siederei brannte, erstarre ich vor Feuer.</span></div></section>'''


def anhang2():
    return f'''<section class="pg"><p class="kick">Anhang · Leitfaden</p><h1>Die Probe in Foundry</h1>
<p class="lead">Ist deine Aktion riskant, fordert sl eine Probe. <b>Du</b> würfelst, nicht sl. Die Bilder zeigen die Figur Mirne.</p>
<div class="chat"><div class="card2"><b>Probe gefordert:</b> Mirne Aschenbach – Kampf, normal – Ich schleiche mich geduckt zum Lagerhaus<br><span class="btn hot">Probe würfeln</span></div></div>
<div class="cols"><div>
<ol class="steps">
<li><div><h3>Karte „Probe gefordert“</h3><p>Sie erscheint im Chat und nennt Säule, Schwierigkeit und Grund.</p></div></li>
<li><div><h3>Klick auf „Probe würfeln“</h3><p>Der Dialog öffnet sich schon ausgefüllt. Setz bei den <b>Eigenschaften</b> ein Häkchen für jedes Merkmal, das bei dieser Handlung hilft. sl achtet darauf, dass es stimmt.</p></div></li>
<li><div><h3>Würfeln</h3><p>Unten steht deine <b>Zielzahl</b>. Optional setzt du hier SP ein <b>oder</b> wählst Schicksalsergeben (beides zusammen geht nicht). Dann <b>Würfeln</b>.</p></div></li>
<li><div><h3>SP nachlegen</h3><p>Auf der Ergebniskarte kannst du kurz (ca. 8 Sekunden) mit <b>SP +10</b> oder <b>SP −10</b> nachhelfen. Danach erzählt sl das Ergebnis.</p></div></li></ol>
<div class="box key"><span class="lab">Nicht doppelt würfeln</span>Würfle nie zusätzlich von Hand. Der zweite Wurf zählt nicht, sl meldet „schon gewürfelt“.</div></div>
<div>{shot('dialog.png', [(2.5,11.3),(2.5,39.7),(2.5,61.5),(2.5,66.7),(2.5,93.4)], ['<b>Säule</b> (hier Kampf)','<b>Eigenschaften</b>: Häkchen bei passenden Merkmalen','<b>Schwierigkeit</b>','<b>SP einsetzen</b> oder Schicksalsergeben (nicht beides)','<b>Würfeln</b> (oder „sl würfeln lassen“)'], w='72%')}
{shot('karte.png', [(4,26),(4,86)], ['Dein Wurf gegen die Zielzahl, mit Erfolgs- oder Fehlergraden (Foundry: „Misserfolgsgrade“)','<b>SP +10 / SP −10</b>'], w='86%')}</div></div>
<p class="small mute">Der Knopf <b>Probe</b> im Chat öffnet denselben Dialog. Nutze ihn nur, wenn die Spielleitung dich am Tisch zum Würfeln auffordert. Sonst würfelst du nur auf die Karte „Probe gefordert“.</p></section>'''


def anhang3():
    return f'''<section class="pg"><p class="kick">Anhang · Leitfaden</p><h1>Wenn’s hakt, und wie wir spielen</h1>
<div class="cols"><div>
<h2>Warten ist normal</h2>
<p>sl braucht <b>4 bis 12 Sekunden</b> für eine Antwort. Schick pro Nachricht <b>eine Aktion</b>. Schreibst du in der Wartezeit weiter, reihen sich die Nachrichten in eine Warteschlange ein und gehen danach raus.</p>
<p>Die Lampe neben dem Probe-Knopf zeigt den Zustand: <span class="lamp" style="background:#3fa561"></span>grün: alles gut · <span class="lamp" style="background:#d6a929"></span>gelb: sl ist pausiert (die Spielleitung spielt von Hand) · <span class="lamp" style="background:#c04545"></span>rot: sl nicht erreichbar.</p>
<h2>Wenn etwas hängt</h2>
<ul><li><b>Lampe rot oder keine Antwort:</b> sag es der Spielleitung. Sie pausiert sl und übernimmt von Hand. Deine Nachrichten gehen nicht verloren.</li>
<li><b>Niemand würfelt die Probe:</b> nach etwa 90 Sekunden würfelt sl selbst, oder die Spielleitung drückt „sl würfeln lassen“.</li>
<li><b>Es fehlt etwas auf dem Bogen:</b> den Figurenbogen öffnest du über das Figuren-Symbol. SP, LP, Säulen und Merkmale stehen dort.</li></ul>
<h2>Etikette</h2>
<ul><li>Alles, was deine Figur tut oder sagt, beginnt mit <span class="cmd">/sl</span>.</li><li>Eine Aktion pro Nachricht. Kurz und klar.</li><li>Schick die nächste Aktion, wenn sl geantwortet hat.</li><li>Würfle nur, wenn sl eine Probe fordert.</li><li>Regelfragen klärst du am Tisch, nicht mit <span class="cmd">/sl</span>.</li><li>Kinder und Jugendliche sind tabu: keine Gewalt, nichts Sexuelles. Dunkle Themen unter Erwachsenen sind okay.</li><li>Fühlst du dich unwohl, sag <b>„Pause“</b>. Die Szene wird umgelenkt, ohne Diskussion.</li></ul></div>
<div><h2>Mini-FAQ</h2><dl class="faq">
<dt>Muss ich die Regeln auswendig können?</dt><dd>Nein. Zielzahl, SP und LP rechnet Foundry mit. Der Spickzettel (S. 11) reicht.</dd>
<dt>Darf meine Figur ein Superheld sein?</dt><dd>Fast. Starke Stärken und starke Ausrüstung kosten Punkte. Wer viel will, braucht Schwächen, die das bezahlen.</dd>
<dt>Ich habe 0 LP, was jetzt?</dt><dd>Du liegst am Boden. Gib <b>1 SP</b>, dann bleibst du am Leben. Ohne SP droht der Tod; sl entscheidet im Sinn der Szene.</dd>
<dt>Was kostet Schicksalsergeben, was bringt es?</dt><dd>−10 auf die Probe. Mit mindestens 2 Erfolgsgraden bekommst du 1 SP zurück. Scheitert die Probe, bekommst du einen Fehlergrad mehr.</dd>
<dt>Was, wenn ich mich beim Merkmal vertan habe?</dt><dd>Mit <span class="cmd">/sl /merkmal …</span>, aber nur vor der ersten Probe. Ändert sich dadurch dein Budget, schick danach <span class="cmd">/sl /budget …</span> noch einmal.</dd>
<dt>Wie viel kostet ein Schwert?</dt><dd>40 Taler, also 4 Budgetpunkte. Im Spiel zahlst du in Taler, Schilling und Heller.</dd>

<dt>Darf ich dem Orakel jede Frage stellen?</dt><dd>Ja-Nein-Fragen zur Welt, ja. „Schaffe ich den Sprung?“ ist eine Probe.</dd></dl>
<div class="box tip" style="margin-top:4mm"><span class="lab">Merksatz</span>Können → <b>Probe</b>. Welt → <b>Orakel</b>. Schicksal biegen → <b>SP</b>.</div></div></div></section>'''


def main():
    html = ('<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Schicksalsschlag – Spieler-Handout</title><link rel="stylesheet" href="style.css"></head><body>'
            + cover() + setting1() + setting2() + figur1() + figur2() + probe1() + probe2() + sp() + kampf() + orakel_geld() + spick() + anhang1() + anhang2() + anhang3() + '</body></html>')
    open(os.path.join(H, 'spieler.html'), 'w', encoding='utf-8').write(html)
    out = os.path.join(ROOT, 'Schicksalsschlag-Spieler.pdf')
    os.environ.setdefault('DYLD_FALLBACK_LIBRARY_PATH', '/opt/homebrew/lib')
    subprocess.run(['/opt/miniconda3/bin/weasyprint', os.path.join(H, 'spieler.html'), out], check=True)
    print('ok', out)


if __name__ == '__main__':
    main()
