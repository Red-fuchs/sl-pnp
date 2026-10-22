#!/usr/bin/env python3
"""Builds handout/oneshot/Schicksalsschlag-OneShot-SL.pdf (GM sheet) and handout/oneshot/foundry/*.html (journal texts for a later import)."""
import os, subprocess, sys
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, H)
import content as C
import seed

SECT = {}

def esc(s): return s.replace('&', '&amp;').replace('<', '&lt;')

NPC_ROWS = [
 ("Die Weberin", "Auftraggeberin, gesichtslose Frau aus Garn. Kreis. Haltung +1", "Will die Nadel. Gibt Auftrag und Leihe, verschweigt den Rest.", "Sie IST der abgetrennte Teil des Schicksals und will sich mit der Nadel als Herrin über alle Fäden wieder einweben. Frei wird niemand."),
 ("Der Kater", "Begleiter, GM-Figur. Kreis. Haltung +2", "Heim, Namen zurück.", "Letzter Gerufener, von der Weberin zum Kater geknotet; sie verwahrt seinen Namen. Weiß das selbst nicht."),
 ("Der Kettler", "Schicksalsbote, Nadelfinger. Fadenbruch. Haltung −2", "Fremde ausnähen, Gewirk flicken.", "Sieht Fremde nicht, nur ihre Wirkung. Kein Freund: er stutzt jede Abweichung. Nicht tötbar."),
 ("Ambros Fehling", "Spindelmeister, Laienbruder und Klostervogt am Webstuhl, müde, pedantisch. Kloster. −1", "Nadel schützen, Ruhe.", "Setzt Fäden nach Bestellung der Vogtin, der Abt deckt es. Gehorsam statt Lebenslauf. Das Fadenbuch im Skriptorium enthüllt es."),
 ("Agnet Rauhsohl", "Vogtin, kühl, geschäftstüchtig. Krähenfurt. 0", "Macht behalten, Fremde als Hebel.", "Hat frühere Gerufene an Fehling verkauft. Will für den Passierschein „eine Probe“: eine Nacht im Kloster als Gast schlafen."),
 ("Wenke Sparr", "Garnhändlerin, einst Dienerin der Weberin. Krähenfurt. +2", "Weberin aufhalten, ohne selbst zu sterben.", "Weiß, dass die Weberin sich als Herrin wieder einweben will. Redet nur, wenn die Figuren ehrlich sagen, wer sie schickt (Sozial; 2 Erfolgsgrade für das Geheimnis)."),
 ("Jorrit Keil", "Schmuggler auf den Moorwegen. Krähenfurt. −1", "Taler, Loyalität dem Höchstbietenden.", "Kennt den Weg durch die Krypta unter der Kapelle von Grams ins Kloster und sah dort die Gruft früherer Gerufener. Verkauft es ab 20 Taler."),
 ("Brand Quast", "Gemischtwarenhändler, geschäftig, neugierig. Grams am Moor. 0", "Profit, Laden behalten.", "Meldet jeden Neuankömmling dem Abt Odilo und verkauft Knochengarn unterm Ladentisch."),
 ("Abt Odilo Wendt", "Abt der blinden Spinner, sanft, unbeugsam. Kloster. −1", "Webstuhl bewahren, Fremde ausliefern.", "Steht im Bund mit dem Kettler und reicht ihm jeden fremden Faden, den er findet. Fehling dient ihm nur. Zur Vesper singt er."),
]
CLOCK = [("1", "Mond steigt (Start)"), ("2", "über dem Moor"), ("3", "über Krähenfurt und Grams: Tore und Zollhaus schließen, Keil wird teurer"), ("4", "über dem Kloster: Vesper, die Mönche singen in der Kapelle, nur die Schreinwächter bleiben; Fehling setzt Nachtfäden"), ("5", "über der Klostermauer: der Kettler findet den Kreis"), ("6", "Mond sinkt: die Leihe endet")]
SCENES = [
 ("0 Der Zug", "Aschekreis. Alle erwachen mit dem, was sie hielten, Garn am Handgelenk, der Kater wartet. Figuren treffen sich. Eine Fremdkraft-Demo ist erlaubt (zeigt die Regel)."),
 ("1 Die Weberin", "Auftrag: Nadel aus dem Kloster der Spinner in den Kreis vor Monduntergang, danach löst sie die Leihe. Warnung: „Das Schicksal darf euch nicht sehen.“ Erstes Ritual (Garn knoten) erklärt."),
 ("2 Moorsaum nach Krähenfurt", "Tor, Wache, erste Blick-Probe (Kleidung, Technik, Fremdkraft)."),
 ("3 Krähenfurt", "Wenke (Ermittlung, S1b), Rauhsohl (Sozial, S3b), Keil (Handel, S2b, S3c). Passierschein gegen die „Probe“."),
 ("4 Grams am Moor", "Zollhaus (Passierschein), Taverne (Gerüchte), Quast (meldet Fremde, Knochengarn), Kapelle mit Krypta-Treppe (Keil führt)."),
 ("5 Fadenbruch (optional)", "Nebelbild (S1c), Kettler-Begegnung (S2a), Webstelle: Ritual senkt den Blick um 2."),
 ("6 Kloster der Spinner", "Beste Zeit: Vesper (Uhr 4), alle singen. Weg: Krypta, Gruft (S2b), Tunnel; oder Pforte. Fadenbuch (S1a, S3a), Fehling, Schrein mit der Nadel, Odilo. Optional Kampf."),
 ("7 Der Kettler", "Auf dem Rückweg. Verhandeln oder fliehen; er nimmt Fremdkraft, nicht Leben."),
 ("8 Der Kreis", "Entscheidung, Ende, Epilog je Figur."),
]
ENDS = [
 ("Rückkehr (Weberin)", "Nadel im Kreis abgegeben, Uhr unter 6: Leihe gelöst, Erwachen daheim im Moment des Zugriffs (Narben, LP-Verlust, Erinnerung bleiben). Die Mark bekommt eine Herrin. Der Kater bleibt Kater, außer die Gruppe verhandelt ihn mit (Sozial sehr schwer, oder eine Fremdkraft als Pfand). Sind S1 und S2 gelöst, können die Figuren vorher verhandeln: Sozial sehr schwer, dann löst die Weberin die Leihe, bevor sie die Nadel nimmt."),
 ("Der Schnitt (Kettler)", "Nadel an den Kettler: er flickt das Gewirk und schneidet die Fremden sauber heraus. Rückkehr, aber jede Fremdkraft erlischt dauerhaft; die Weberin bleibt hungrig im Moor. Voraussetzung: Kettler gefunden und S2 gelöst, sonst näht er auch die Figuren aus. Der Kater kehrt als Mensch heim, ohne Erinnerung."),
 ("Bleiben (Bruch)", "Nadel zerbrochen oder behalten, oder Uhr 6 ohne Entscheidung: kein Rückweg, das Gewirk löst sich, die Mark wird fadenlos (frei und chaotisch). Jede Figur sagt, wo sie ihren Faden verankert. Der Kater bleibt Kater, ist frei und erinnert sich an alles."),
]

def table(head, rows, widths=None):
    h = ''.join(f'<th>{x}</th>' for x in head)
    return '<table><tr>' + h + '</tr>' + ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows) + '</table>'

def blick_html():
    return """<table><tr><th>Blick</th><th>Stufe</th><th>Was geschieht</th></tr>
<tr><td>1–3</td><td><b>Unbemerkt</b></td><td>Nichts. Zufallsereignisse selten (Pasch ≤ Spannung).</td></tr>
<tr><td>4–6</td><td><b>Fäden zittern</b></td><td>Münzen fallen falsch, Hunde heulen, Fremde werden angestarrt. Kleine Unstimmigkeiten.</td></tr>
<tr><td>7–8</td><td><b>Boten suchen</b></td><td>Genähte (zugenähte Lippen) fragen nach Fremden; NPC-Haltung effektiv −1; der Kettler ist eine Szene entfernt. Bei Fremdkraft-Einsatz sagt sl vorher, dass der Faden zieht.</td></tr>
<tr><td>9</td><td><b>Eingriff</b></td><td>Set-Piece, danach Reset auf 5 (sl macht das automatisch).</td></tr></table>
<div class="cols"><div><h3>Hebt (GM: <code>/spannung +1</code>, außer Fremdkraft)</h3><ul><li><b>Fremdkraft-Einsatz +1</b>, automatisch in sl (auch bei Fehlschlag)</li><li>Spektakulär/öffentlich (Kampf auf dem Markt, Feuer, Technik vor Zeugen) +1</li><li>SP auf <b>fremde</b> Würfe +1 je Probe</li><li>Szenenende: ±1/±2 wie gehabt</li></ul></div>
<div><h3>Senkt</h3><ul><li>Ruhige Szene: Szenenende −1/−2</li><li><b>Untertauchen</b> eine ganze Szene: −1 zusätzlich</li><li><b>Ritual der Weberin</b> an einer Webstelle (Kreis, Fadenbruch, Garnbude): 1 SP ins Garn, −2, einmal je Ort</li><li><b>Schicksalsergeben</b>: −1 am Szenenende</li></ul></div></div>
<p><b>Eingriff bei 9</b> (GM wählt oder w6): <b>1–2 Der Kettler kommt</b>: betritt die Szene, nicht tötbar, sticht eine Fremdkraft an (weg bis zum nächsten Ritual). <b>3–4 Ein Faden reißt</b>: ein helfender NPC stirbt oder vergisst die Figuren (Haltung 0, bekannt bleibt). <b>5–6 Paradox</b>: eine Figur trifft ihre Entsprechung aus der Mark; −10 auf alles, bis sie beruhigt, getäuscht oder getötet ist. <b>Nachher:</b> sl setzt auf 5; die <b>Uhr rückt eine Stufe vor</b>, die Figur erhält ein <b>Fadenmal</b> (0-Punkte-Makel, z. B. „ein Auge sieht Fäden“). Kein Death-Spiral: 9 ist ein Ereignis, kein Zustand. Start des One-Shots: Blick 3.</p>"""

def fremd_html():
    return """<p><b>Eine pro Figur, 4 Punkte</b> (große Stärke, +20 auf passende Proben). Wirkung immer als Probe, eine Szene oder ein Ziel, kein Sofort-Sieg, nichts wird ungeschehen gemacht, Schaden max. 3 + Erfolgsgrade, Heilung max. halbe LP. <b>Jeder Einsatz Blick +1, auch bei Fehlschlag.</b> Eintrag: <code>/sl /merkmal +Fremdkraft: Name</code>; sl erkennt den Einsatz, wenn die Probe das Merkmal betrifft, hebt die Spannung selbst und gibt dir eine Infozeile. Beispiele: Netzgeist (Schlösser als Code), Letzter Atem (Sterbende über der Schwelle), Hexenblick (Lüge sehen), Schildeid (Treffer für andere abfangen), Schattenschritt (Gruppe ungesehen ab), Totenflüstern (3 Ja/Nein-Fragen an einen Toten).</p>"""

def kater_html():
    return """<p><b>Rolle:</b> Bote der Weberin, roter Garnfaden am Hals, dehnt sich bis Krähenfurt und droht im Kloster zu reißen (dort alle Kosten +1). Fremd und mit altem Leihknoten: das Schicksal riecht ihn zuerst. Erklärt Welt und Regeln in der Fiktion („Garn“, „Knoten“, „der Blick“), moderiert den Tisch, löst nichts (kein Schloss, kein Kampf), gibt nur Richtungen. 4 LP; sein Tod kappt den Rückweg nicht, aber die Weberin schweigt danach. <b>Du spielst ihn, sl nicht.</b></p>
<table><tr><th>Handlung</th><th>Blick</th></tr><tr><td>Zur Gruppe flüstern, auf der Schulter mitreisen</td><td>0</td></tr><tr><td>Hörbar sprechen, wo NPCs lauschen</td><td>+1 (<code>/vertrauter laut</code>)</td></tr><tr><td>Körperlich eingreifen oder eigene Kraft „Garnsicht“ (sieht Fäden/Lügen, eine Antwort)</td><td>+2 (<code>/vertrauter eingriff</code>)</td></tr><tr><td>Alles im Kloster</td><td>zusätzlich +1 (<code>/spannung +1</code>)</td></tr><tr><td>Allein im Kreis sitzen, eine Szene</td><td>−1</td></tr></table>
<p><b>Wahrnehmung:</b> Er nimmt <b>nur wahr, was die Figuren wahrnehmen</b>; allein ist er blind und taub und leiht sich die Sinne der Figur, die er berührt oder auf der er sitzt (immer nur eine, Wechsel frei). Er kann nicht auskundschaften, nicht vorauslaufen, keine Räume prüfen. Sein Wissen: was die Figuren erfahren haben, plus sein Teilwissen von vor der Berufung. <b>Weiß:</b> Mark, Weg, Uhr; die Weberin will die Nadel und braucht Fremde, weil Einheimische daran ihren Faden verlieren; der Kettler näht Fremde aus; Wenke diente der Weberin. <b>Weiß nicht:</b> dass die Weberin das abgetrennte Schicksal ist, dass die Asche aus Fäden früherer Gerufener besteht, seinen eigenen Namen. Er lügt nie; der Twist trägt, weil <i>sie</i> ihn belog.</p>
<p><b>Twist-Haken:</b> Er war der letzte Gerufene. Die Weberin löste die Leihe nicht, sondern knotete ihn zum Kater und verwahrt Name und Erinnerung („Wenn die Nadel kommt, bekommst du beides“). Sie kann ihn nur mit der Nadel lösen und wird es nicht freiwillig tun. Hinweiskette: Grab in der Gruft (Krallenspuren, ein Name, den er nicht lesen will) → Nebelbild im Fadenbruch (ein Mann mit seinem Blick) → nahe der Nadel erinnert er sich (Namens-Slot: die Spieler dürfen ihn benennen, wenn nichts vorbereitet ist).</p>
<div class="box key"><span class="lab">Spielleiter-Disziplin</span>Als Kater sagst du <b>nur, was die Figuren wissen können</b>. sl erzählt die Welt, also verrät der Kater nie Ungesehenes und „bemerkt“ nichts Verborgenes. Nichts aus diesem Blatt in seinen Mund legen, was die Figuren nicht erfahren haben. sl darf den Kater nie sprechen oder wahrnehmen lassen (steht im Erzähler-Prompt).</div>
<p><b>Spielen ohne Railroading:</b> (1) Fragen statt Antworten („Was riecht ihr?“). (2) Eine Richtung je Stupser, nie die beste. (3) Er irrt sich über Menschen, nicht über Orte. (4) Jede Hilfe hat einen Blick-Preis, die Gruppe entscheidet. (5) Bei Entscheidungen der Gruppe schweigt er, ausdrücklich. (6) Sein Ziel offen spielen: er will heim, das darf der Gruppe im Weg stehen. Stupser, wenn die Gruppe über 10 Minuten kreist. <i>Sätze:</i> „Flüstert. Hier hören die Wände, und die Wände haben einen Herrn.“ · „Ich kenne den Weg, nicht die Tür.“ · „Das kostet. Nicht Taler. Aufmerksamkeit.“ · „Fragt mich nicht, was sie will. Fragt mich, was sie mir versprochen hat.“ · „Ich hatte einmal einen Namen. Er fing mit einem Konsonanten an.“</p>"""

def commands_html():
    return """<table><tr><th>Befehl</th><th>Zweck</th></tr>
<tr><td><code>sl web --welt weberin</code> oder <code>/welt vorlage weberin</code></td><td>Welt laden (vor dem ersten Zug)</td></tr>
<tr><td><code>/sl /figur Name: Geschichte</code>, <code>/merkmal +Fremdkraft: X</code>, <code>/budget …</code></td><td>Figuren bauen</td></tr>
<tr><td><code>/spannung +1</code> · <code>-2</code> · <code>7</code></td><td>Blick des Schicksals setzen; bei Eintritt in eine neue Stufe erhält der Erzähler einen verdeckten Hinweis; bei 9 der Eingriff (danach 5)</td></tr>
<tr><td><code>/vertrauter laut</code> · <code>eingriff</code></td><td>Kater: Blick +1 / +2 mit verdecktem Hinweis</td></tr>
<tr><td><code>/regie Text</code></td><td>Verdeckte Notiz für die nächste Erzählung, z. B. „Uhr 4: Genähte patrouillieren“ oder der gewählte Eingriff</td></tr>
<tr><td><code>/szene</code></td><td>Szenenwechsel (Schicksalsergeben wieder frei)</td></tr>
<tr><td><code>/kauf Name Ware Preis</code>, <code>/taler</code>, <code>/gegenstand</code></td><td>Einkäufe in Krähenfurt und Grams buchen (Garn, Passierschein, Knochengarn bei Quast, Keils Auskunft ab 20 Taler)</td></tr>
<tr><td><code>/rast kurz|lang|fest</code></td><td>SP/LP; jede Rast rückt die Uhr vor</td></tr></table>"""

def gm_html():
    nrows = [(f'<b>{a}</b><br><span class="small">{b}</span>', c, d) for a, b, c, d in NPC_ROWS]
    clues = ''.join(f'<tr><td><b>{t}?</b></td><td>' + '<br>'.join(f'{i+1}. {tx} <span class="mute">({at})</span>' for i, (tx, at) in enumerate(cl)) + '</td></tr>' for t, cl in C.STRAENGE)
    return f"""<section class="pg dense"><p class="kick">Spielleiter-Blatt · Streng geheim</p><h1>Fadenleihe: Die Weberin</h1>
<p class="lead">One-Shot für 3–5 Figuren, 3–4 Stunden, dunkle Fantasy. sl erzählt, du lenkst über /spannung, /regie, /szene, /kauf und spielst den Kater.</p>
<h2>Auftrag und Lage</h2>
<p><b>Die Gramsmark</b>: Moor, Flussauen, eine Stadt. Schicksal ist Handwerk: im <b>Kloster der Spinner</b> auf dem Hügel über Grams am Moor spinnen blinde Mönche jedem Bewohner den Faden am Riesenwebstuhl, der Spindelmeister setzt ihn mit der <b>Nadel</b>; Abt Odilo Wendt steht im Bund mit dem Kettler. Das Gewirk ist wund, der <b>Kettler</b> näht jede Abweichung fest. Die <b>Weberin</b> zieht Fremde im Moment ihrer eigenen Krise in einen Aschekreis. <b>Auftrag:</b> „Holt die Nadel aus dem Kloster der Spinner über Grams am Moor und bringt sie in den Kreis, bevor der Mond hinter den Klosterberg sinkt. Danach löse ich die Leihe.“ Leihe = ein Mondlauf (eine Nacht und ein Tag). Gelöst: Erwachen daheim im Moment des Zugriffs. Nicht gelöst: der Faden wächst fest, die Figur bleibt. Tod ist Tod.</p>
<div class="box key"><span class="lab">Der Twist</span>Die Weberin arbeitet nicht gegen das Schicksal, sie <b>ist</b> es: die abgetrennte Hälfte, die vor 300 Jahren frei sein wollte und sich die Nadel (ein Knochen, kein Eisen, verwahrt im Reliquienschrein) aus dem Leib brach. Mit der Nadel webt sie sich nicht los, sondern <b>als die, die webt wieder ein</b>. Fehling und Rauhsohl würden nur ersetzt. Frühere Gerufene holten die Nadel, die Leihe wurde nie gelöst: ihre Fäden sind der Aschekreis. Grau bleibt es, weil der Kettler kein Freund ist: er stutzt auch die Figuren. Der Kater ist der letzte Gerufene.</div>
<h2>Orte</h2>
{table(['Ort', 'Beschreibung', 'Herrscht'], [(f'<b>{k}</b>', v[0], v[1]) for k, v in C.ORTE.items()])}
<h2>Uhr „Mondlauf“</h2>
<p class="small">{' · '.join(f'<b>{a}</b> {b}' for a, b in CLOCK)}. Die Uhr rückt am Szenenende bei verbrauchter Zeit vor (nicht jede Szene), bei Rast und bei jedem Eingriff. Notiere sie selbst und gib sie sl per <code>/regie</code>.</p>
<h2>Szenen (ca. 9)</h2>
{table(['Szene', 'Inhalt'], [(f'<b>{a}</b>', b) for a, b in SCENES])}
<section class="pg dense"><h1 style="margin-top:0">Figuren und Fäden</h1>
<h2>NPCs und ihre Geheimnisse</h2>
{table(['Figur', 'Ziel', 'Geheimnis / Enthüllung'], nrows)}
<h2>Drei Fäden, je drei Hinweise (in hidden.json, sl gibt sie frei, wenn die Figuren am Ort sind oder die Figur ansprechen)</h2>
<table><tr><th>Frage</th><th>Hinweise (Fundort)</th></tr>{clues}</table>
<p><b>Optionaler Kampf</b> an der Klosterpforte und am Schrein: zwei <b>Schreinwächter</b>/<b>Genähte</b> (Kampf 45, Leder 1, Knüppel 2) und Fehlings <b>Fadenhund</b> (Kampf 55, Biss 3). Umgehen über Krypta und Tunnel (Keil) oder Schattenschritt; während der Vesper sind nur die Schreinwächter da. <b>Soziale Szene:</b> Krähenfurt, Garnbude der Wenke Sparr; sie redet nur, wenn die Figuren ehrlich sagen, wer sie schickt. Parallel die Audienz bei Rauhsohl.</p>
<h2>sl-Befehle für diesen One-Shot</h2>
{commands_html()}
<p class="small">Start: <code>SL_IDLE=1800 ./play.sh web --port 8787 --rules schicksal --rng jitter --welt weberin --name pnp-2026-10-22</code> (die Vorlage setzt Regeln „schicksal“, Blick 3, Auftakt im Aschekreis). Namens-Slot des Katers: in <code>worlds/weberin/world.json</code> „Der Kater“ ersetzen (auch in hidden.json).</p>
<h2>Ablauf-Checkliste</h2><ol><li>Figuren bauen (/figur, /merkmal +Fremdkraft, /budget), der Kater tritt als Mitspieler mit eigenem Namen auf.</li><li>Szene 0: Auftakt, alle treffen sich im Kreis; erste Szene mit <code>/szene</code> abschließen.</li><li>Pro Szene: Blick prüfen, Uhr nachführen, Hinweise nicht verschenken: sl gibt sie frei.</li><li>Bei Eingriff: sl meldet es per Infozeile; spiele das Set-Piece, setze die Uhr eine Stufe weiter und vergib das Fadenmal.</li><li>Ende nach den Bedingungen oben, Epilog je Figur.</li></ol></section>
</section>
<section class="pg dense"><p class="kick">Spielleiter-Blatt</p><h1>Blick des Schicksals und Fremdkraft</h1>
<p class="lead">Der Blick ist die Spannung (1–9). Die Spieler kennen den Wert nicht, nur die Zeichen.</p>
{blick_html()}
<h2>Fremdkraft</h2>{fremd_html()}
<h2>Heimatwelt-Ausrüstung</h2><p>Alles, was die Figur hielt, kommt mit (Preis nach Stufe 2/4/6, Unbekanntes 2). Alltagsdinge werden örtliche Entsprechungen (Smartphone: glattes schwarzes Täfelchen, nur Uhrzeit); Waffen bleiben, Munition endlich; seltsame Technik funktioniert unzuverlässig, vor Zeugen hebt sie den Blick (+1); Großes (Auto, Pferd) bleibt daheim.</p></section>
<section class="pg dense"><p class="kick">Spielleiter-Blatt</p><h1>Der Kater und die Enden</h1>
{kater_html()}
<h2>Enden</h2>{table(['Ende', 'Bedingung und Folge'], [(f'<b>{a}</b>', b) for a, b in ENDS])}</section>
"""

def build_pdf():
    html = ('<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Fadenleihe – Spielleiter-Blatt</title><link rel="stylesheet" href="../spieler/style.css"><style>@page :first{margin:15mm 15mm 17mm 15mm;@bottom-left{content:"Fadenleihe · Spielleiter-Blatt · geheim";font:7.5pt Georgia,serif;color:#8a7f86}@bottom-right{content:"Seite " counter(page);font:7.5pt Georgia,serif;color:#8a7f86}} @page{@bottom-left{content:"Fadenleihe · Spielleiter-Blatt · geheim"}} .dense{font-size:8.7pt} .dense table{font-size:8.2pt} .mute{color:#6b6068} .cols>div{padding:0} code{white-space:normal} .dense td{padding:.8mm 1.4mm} .dense h2{margin:3mm 0 1.4mm} h3{font-size:9.6pt}</style></head><body>' + gm_html() + '</body></html>')
    open(os.path.join(H, 'oneshot.html'), 'w', encoding='utf-8').write(html)
    out = os.path.join(H, 'Schicksalsschlag-OneShot-SL.pdf')
    os.environ.setdefault('DYLD_FALLBACK_LIBRARY_PATH', '/opt/homebrew/lib')
    subprocess.run(['/opt/miniconda3/bin/weasyprint', os.path.join(H, 'oneshot.html'), out], check=True)
    print('ok', out)

def foundry():
    d = os.path.join(H, 'foundry'); os.makedirs(d, exist_ok=True)
    spieler = f"""<h2>Die Berufung</h2>
<p>Im schlimmsten Moment deines Lebens (ein Sturz, ein Speer, ein Systemabsturz, ein Strick) greift etwas nach dir. Du erwachst in einem Kreis aus Asche am Rand eines Moores. In der Hand hältst du, was du im Augenblick des Zugriffs gehalten hast, um die Handgelenke liegt ein feines Garn. Neben dir erwachen andere: Fremde aus anderen Welten, so verloren wie du.</p>
<p>Eine uralte Macht hat euch einberufen, <b>die Weberin</b>. Sie wirkt gegen das Schicksal selbst und braucht Menschen, die nicht in dessen Fäden eingewoben sind. Sie gibt euch einen Auftrag, der in einer Nacht zu schaffen ist. Löst ihr ihn, werdet ihr zurückgebracht.</p>
<h3>Der Blick des Schicksals</h3>
<p>Für das Schicksal seid ihr Störungen im Gewebe. Je mehr ihr auffallt, desto genauer sieht es hin. Jeder Einsatz einer <b>Fremdkraft</b> (eure eine übernatürliche Fähigkeit, 4 Punkte), Spektakuläres vor Zeugen und fremde Würfe mit SP heben den Blick; Untertauchen, ruhige Szenen und ein Ritual der Weberin an einer Webstelle senken ihn. Ihr kennt die Zahl nicht, nur die Zeichen: Fäden zittern, Boten suchen, bis das Schicksal eingreift.</p>
<h3>Euer Begleiter</h3>
<p>Im Kreis wartet <b>der Kater</b>, ein sprechendes Tier (die Spielleitung spricht für ihn). <b>Er sieht nur, was ihr seht.</b> Er kennt die Gegend, aber nicht alles, und löst nichts für euch. Was er laut vor Fremden sagt oder tut, hebt auch euren Blick.</p>
<h3>Deine Figur</h3><p>Woher kommst du? Was kannst du? Was hattest du in der Hand? Gib deiner Figur eine Fremdkraft: <code>/sl /merkmal +Fremdkraft: Hexenblick</code>. Alltagsdinge aus deiner Welt werden zu örtlichen Entsprechungen, Munition ist endlich, seltsame Technik funktioniert unzuverlässig.</p>"""
    gmj = f"""<h2>Weberin – SL (nur Spielleitung)</h2>
<p><b>Twist:</b> Die Weberin ist der abgetrennte Teil des Schicksals. Mit der Nadel (ein Knochen) webt sie sich als Herrin wieder ein. Frei wird niemand. Der Kater ist der letzte Gerufene.</p>
<p><b>Blick (Spannung):</b> 1–3 unbemerkt · 4–6 Fäden zittern · 7–8 Boten suchen · 9 Eingriff (Kettler / Faden reißt / Paradox), danach 5, Uhr +1, Fadenmal. Fremdkraft +1 je Einsatz.</p>
<p><b>Uhr:</b> {' · '.join(f'{a} {b}' for a, b in CLOCK)}.</p>
<h3>NPCs</h3><ul>{''.join(f'<li><b>{a}</b> ({b}): {c} <i>{dd}</i></li>' for a, b, c, dd in NPC_ROWS)}</ul>
<h3>Fäden</h3><ul>{''.join(f'<li><b>{t}?</b> ' + '; '.join(f'{tx} ({at})' for tx, at in cl) + '</li>' for t, cl in C.STRAENGE)}</ul>
<h3>Enden</h3><ul>{''.join(f'<li><b>{a}:</b> {b}</li>' for a, b in ENDS)}</ul>"""
    kater = "<h2>Der Kater (Vertrauter, GM-Figur)</h2>" + kater_html()
    for n, t in (('Die-Berufung_Spieler.html', spieler), ('Weberin-SL_nur-GM.html', gmj), ('Der-Kater_GM-Actor.html', kater)):
        open(os.path.join(d, n), 'w', encoding='utf-8').write('<!-- Foundry journal page; import later. ' + n + ' -->\n' + t + '\n')
    print('ok foundry', os.listdir(d))

if __name__ == '__main__':
    seed.build(); build_pdf(); foundry()
