#!/usr/bin/env python3
"""Baut Schicksalsschlag-Handout.pdf (weasyprint). Tabellen kommen aus tables.py (Engine-JSON)."""
import sys, os, subprocess
H = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, H)
import tables as T
from tables import e, table, D, POOLS

# ---- Regelrechner (Beispiele werden gegen die Formel geprüft) ----
def dos(target, roll):
    if roll <= 5 or (roll <= target and roll < 96): return min(10, 1 + max(0, (target - roll)) // 10), 'E'
    return min(10, 1 + max(0, (roll - target)) // 10), 'F'
def res(target, roll):
    v, k = dos(target, roll)
    if roll <= 5: k = 'E'
    if roll >= 96: k = 'F'
    if roll > target and roll > 5: k = 'F'
    dbl = roll % 11 == 0 and roll >= 11 or roll == 100
    return v, k, dbl
assert res(40, 47) == (1, 'F', False) and res(50, 47) == (1, 'E', False)  # Beispiel 2
assert res(40, 17) == (3, 'E', False) and res(40, 31) == (1, 'E', False)   # Beispiel 3
assert res(60, 33) == (3, 'E', True)                                       # Beispiel 4 (Kritisch)
assert res(60, 41)[:2] == (2, 'E') and res(40, 52)[:2] == (2, 'F')          # Kampf
assert res(40, 19)[:2] == (3, 'E') and res(40, 38)[:2] == (1, 'E')
assert res(20, 19)[:2] == (1, 'E') and res(40, 28)[:2] == (2, 'E') and res(40, 35)[:2] == (1, 'E')

W = D('improv_world'); N = D('improv_names'); TR = D('traits')
A, B, C = T.thr(0, 5), T.thr(1, 5), T.thr(-1, 5)

def wl(key): return T.wordlist(POOLS[key], key.capitalize())
def d10t(items, col, cols=2):
    li = ''.join(f'<li><b>{i+1}</b> {e(x)}</li>' for i, x in enumerate(items[:10]))
    return f'<div class="wl rl"><ul style="column-count:{cols}">{li}</ul></div>'
def d20t(items, col, cls='small', cols=2):
    n = len(items); w = 100 // n
    li = ''.join(f'<li><b>{T.d100_label(i*w+1,(i+1)*w)}</b> {e(x)}</li>' for i, x in enumerate(items))
    return f'<div class="wl rl"><ul style="column-count:{cols}">{li}</ul></div>'
def two(items, col):
    h = T.ranges(items); half = len(h) // 2
    f = lambda rows: table(['d100', col], [[a, e(b)] for a, b in rows], 'small" style="width:100%')
    return f'<div class="grid"><div>{f(h[:half])}</div><div>{f(h[half:])}</div></div>'

def traits_table(key, sign, pts):
    ab = {'Kampf': 'K', 'Sozial': 'S', 'Wissen': 'W', 'Alle': 'alle'}
    li = ''.join(f'<li><b>{ab.get(x["saeule"], x["saeule"])}</b> <u>{e(x["wort"])}</u> – {e(x["hinweis"])}</li>' for x in TR[key])
    return f'<div class="wl rl"><div class="cap">{"Vorteile" if sign == "" else "Nachteile"} {"klein" if pts == 2 else "groß"} ({"−" if sign == "" else "+"}{pts}) · K Kampf, S Sozial, W Wissen</div><ul style="column-count:1">{li}</ul></div>'

P = []  # Seiten/Abschnitte
add = P.append

# ================= 1 QUICKSTART =================
add(f'''<h1 class="first">Schicksalsschlag</h1>
<div class="sub">Spieler- und Spielleiter-Handout für das Fernrollenspiel. Dunkle Fantasy, d100, ein Orakel für alles, was nicht in deiner Hand liegt. Dieses Heft ist auch der <b>Notfallplan</b>, falls der KI-Spielleiter (sl) oder die Technik ausfällt: Alle Tabellen sind mit zwei Würfeln (d100 = zwei d10) oder einem Online-Würfler spielbar.</div>
<div class="toc"><div>1 Schnellstart</div><div>2 Figur erschaffen</div><div>3 Die Probe (d100)</div><div>4 Kampf</div><div>5 Schicksalspunkte</div><div>6 Das Orakel ohne KI</div><div>7 Einfalls-Werkzeugkasten</div><div>8 Notfall: Spielleitung von Hand</div><div>9 Charakterbogen</div><div>10 Spickzettel aller Modifikatoren</div><div>11 Gegenstände und Händler</div></div>
<h2>1 Schnellstart</h2>
<p><b>Würfeln:</b> Alles läuft über einen <b>d100</b>: zwei d10 (erst Zehner, dann Einer; 0 und 0 zählt als 100). Du willst <b>niedrig</b> würfeln: Ergebnis <b>kleiner oder gleich deiner Zielzahl</b> heißt Erfolg.</p>
<h3>So läuft ein Zug</h3>
<ol>
<li><b>Die Spielleitung beschreibt</b> die Lage (kurz, 2–4 Sätze).</li>
<li><b>Du sagst, was dein Charakter tut.</b> Ein Satz reicht („Ich schleiche an der Wache vorbei“).</li>
<li><b>Ist der Ausgang unsicher und hängt er vom Können deiner Figur ab?</b> Dann gibt es eine <b>Probe</b> (Kap. 3): Zielzahl = Säule + Eigenschaften + Schwierigkeit, d100 würfeln, Erfolgsgrade ablesen.</li>
<li><b>Ist der Ausgang unsicher und hängt er von der Welt ab</b> („Ist die Tür verschlossen?“, „Ist der Wirt freundlich?“)? Dann fragst du das <b>Orakel</b> (Kap. 6): Ja/Nein-Frage, Chancen schätzen, d100 würfeln.</li>
<li><b>Ist alles klar oder ohne Risiko?</b> Dann wird einfach erzählt. Nicht würfeln, wenn nichts auf dem Spiel steht.</li>
<li><b>Schicksalspunkte (SP)</b> darfst du vor oder direkt nach dem Wurf ausgeben, bevor das Ergebnis erzählt wird (Kap. 5).</li>
</ol>
<div class="box"><b class="t">Die drei Regeln, die du dir merken musst</b><ol>
<li><b>Zielzahl = Säule (30/40/50) + Eigenschaften (±10/±20) + Schwierigkeit (+20 … −30) + Zustände.</b></li>
<li><b>Würfel ≤ Zielzahl = Erfolg.</b> Erfolgsgrade (DoS) = 1 + abgerundet((Zielzahl − Wurf) ÷ 10). Pasch (11, 22 … 99, 100) = <b>kritisch</b>.</li>
<li><b>Ob die Welt mitspielt, entscheidet das Orakel:</b> Chancen × Spannung → JA+ / JA / NEIN / NEIN+.</li></ol></div>
<h3>Wann Probe, wann Orakel?</h3>
{table(['Situation','Werkzeug'],[
['„Kann meine Figur das?“ (klettern, überreden, Schloss öffnen, Rune lesen, kämpfen)','<b>Probe</b> (Kap. 3/4)'],
['„Ist es so?“ (Ist der Torwächter bestechlich? Ist jemand im Raum?)','<b>Orakel</b> (Kap. 6)'],
['Szene beginnt: läuft sie wie erwartet?','<b>Szenentest</b> (Kap. 6)'],
['Es passiert etwas Unerwartetes (Pasch ≤ Spannung)','<b>Zufallsereignis</b> (Kap. 6)'],
['Ein Name, Ort, Gerücht, Beutestück wird gebraucht','<b>Einfallskasten</b> (Kap. 7)']])}
<p class="note">Inhaltsregel: Minderjährige werden nie Opfer von Gewalt oder sexuellen Inhalten. Dunkle Themen unter Erwachsenen sind in Ordnung. Wer sich unwohl fühlt, sagt „Pause“; die Szene wird umgelenkt, ohne Diskussion.</p>''')

# ================= 2 FIGUR =================
sample = D('traits')
add(f'''<h1>2 Figur erschaffen</h1>
<p>Deine Figur entsteht aus einer <b>Hintergrundgeschichte</b>. Aus ihr ziehst du <b>Eigenschaften als Wörter</b>. Jedes Wort kostet oder bringt Punkte aus einem Budget von <b>20 Punkten</b>. Was übrig bleibt, wird zu Geld, Ausrüstung oder zusätzlichen Schicksalspunkten.</p>
<h3>Schritt 1: Hintergrundgeschichte (3–8 Sätze)</h3>
<p>Wer bist du? Woher kommst du? Was kannst du? Was holt dich ein? Gute Geschichten nennen <b>Können</b> (Vorteile) <b>und Last</b> (Nachteile). Jeder Satz kann ein Wort liefern. Bei sl zieht die KI die Wörter für dich heraus, am Tisch macht es die Spielleitung oder du selbst.</p>
<h3>Schritt 2: Eigenschaften als Wörter, Budget 20</h3>
{table(['Art','Klein (minor)','Groß (major)','Wirkung bei passender Probe'],[
['<b>Vorteil</b> (Können, Eigenschaft, Kontakt)','kostet <b>2</b>','kostet <b>4</b>','+10 / +20 auf die Zielzahl'],
['<b>Nachteil</b> (Makel, Schuld, Feind, Angst)','gibt <b>+2</b> zurück','gibt <b>+4</b> zurück','−10 / −20 auf die Zielzahl, wenn er ins Spiel kommt']])}
<p><b>Beispiele:</b> „trinkfest“ (klein, 2), „geübter Bogenschütze“ (groß, 4), „Angst vor Feuer“ (Nachteil klein, +2), „Todfeind: der Vogt“ (Nachteil groß, +4). Ein Wort gilt nur, wenn die Spielleitung findet, dass es zur Probe passt. Empfehlung: höchstens zwei große Nachteile, und jedes Wort muss in der Geschichte vorkommen.</p>
<div class="two">
{traits_table('positiv_klein','',2)}
{traits_table('positiv_gross','',4)}
{traits_table('negativ_klein','+',2)}
{traits_table('negativ_gross','+',4)}
</div>
<p class="note">Die Listen sind nur Anregungen, du kannst jedes eigene Wort vorschlagen.</p>''')

add(f'''<h3>Schritt 3: Was übrig bleibt</h3>
<p>Budget = 20 + Rückgaben der Nachteile − Kosten der Vorteile. Den Rest tauschst du:</p>
{table(['Rest','Tausch'],[['<b>1 Punkt</b>','10 Taler Startgeld'],['<b>2, 4 oder 6 Punkte</b>','Startgegenstand nach Preisstufe (Vorschlag, siehe Tabelle)'],['<b>3 Punkte</b>','+1 maximaler Schicksalspunkt (Start 5, Maximum 5, mit diesem Tausch 6 usw.)']],'small')}
<p>Mischen ist erlaubt. Die Spielleitung entscheidet, ob ein Wort klein oder groß ist, und sieht sich vor Spielbeginn die Liste an. Alltagskleidung, Beutel und Proviant hat jede Figur gratis; Waffen und Rüstung kosten Punkte oder Taler. Der Rest darf 0 sein, das Budget aber nicht ins Minus gehen. Preise für Gegenstände: siehe Spickzettel (Richtwerte).</p>
{table(['Preisstufe (Vorschlag)','Gegenstände','Taler-Gegenwert'],[['<b>2 Punkte</b>','normale Ausrüstung, Messer/Dolch oder Knüppel, Lederrüstung (Rüstung 1)','20 Taler'],['<b>4 Punkte</b>','Schwert, Axt oder Bogen (auch Speer, Armbrust), Kettenhemd (Rüstung 2), Schild','40 Taler'],['<b>6 Punkte</b>','Plattenpanzer (Rüstung 3) oder Feuerwaffe','60 Taler']],'small')}
<p class="note">Unbekannte Gegenstände zählen als normal (2 Punkte). 1 Punkt = 10 Taler. Magie gibt es nicht als Startgegenstand.</p>
<h3>Story-Items ★</h3>
<p>Jeder Gegenstand kostet seine Preisstufe. Kauft deine Figur über <code>/budget</code> einen Gegenstand, der zu ihrer Hintergrundgeschichte passt, wird er als <b>★ Story-Item</b> markiert (gleicher Preis). Manche Story-Items wachsen mit gelösten Handlungssträngen (höchstens +3), manche verbergen eine Wendung, die sich erst im Spiel offenbart. Du siehst nur den Stern; alles andere bleibt Überraschung. Gegenstände ohne Stern ändern sich nicht.</p>
<h3>Schritt 4: Drei Säulen verteilen</h3>
<p>Verteile die Werte <b>30, 40 und 50</b> beliebig auf <b>Kampf</b>, <b>Sozial</b> und <b>Wissen</b>. Sie sind deine Grundzielzahlen für den d100.</p>
{table(['Säule','Umfasst'],[['<b>Kampf</b>','Nahkampf, Fernkampf, Ausweichen, Schleichen und Klettern, alles Körperliche und Handfeste, Initiative'],['<b>Sozial</b>','Überreden, Einschüchtern, Handeln, Lügen, Gespür für Menschen, Auftreten'],['<b>Wissen</b>','Heilen, Lesen, Handwerk, Magie- und Religionskunde, Spuren deuten, Wahrnehmung']],'')}
<h3>Schritt 5: Notieren</h3>
<p>Auf den Charakterbogen (Kap. 9): Name, Geschichte (Kurzform), Wörter mit +/− Werten, Säulen, LP 10, Schicksalspunkte (Start = Maximum), Taler, Ausrüstung.</p>
<div class="box ex"><b class="t">Beispielfigur: Mirne Aschenbach</b>
<p><i>Geschichte:</i> Mirne wuchs als Tochter eines Salzsieders im Moor auf und lernte früh, mit der Armbrust Raben von den Salzpfannen zu verscheuchen. Mit neunzehn ging sie als Botin zum Zollhaus, sah dort Schmugglergold und schwieg. Seitdem schuldet ihr der Zöllner Ottokar einen Gefallen, und die Schmuggler wollen sie tot sehen. Sie kann lesen und schreiben, kennt die Heilkräuter des Moores und findet jeden Pfad dort im Nebel. Seit die Siederei brannte, erstarrt sie vor Feuer.</p>
{table(['Wort','Art','Punkte','Passt zu (Beispiele)'],[
['geübte Armbrustschützin','Vorteil groß','−4','Kampf (+20, nur Armbrust)'],
['kann lesen und schreiben','Vorteil klein','−2','Wissen (+10)'],
['kennt Moorkräuter','Vorteil klein','−2','Wissen (+10, Kräuter/Heilen)'],
['findet jeden Pfad im Moor','Vorteil klein','−2','Kampf (+10, Schleichen und Fortbewegen im Moor)'],
['Ottokar schuldet ihr einen Gefallen','Vorteil klein','−2','Sozial (+10 bei Zoll und Wache)'],
['zäh wie Moorholz','Vorteil klein','−2','Kampf (+10, Ausdauer, Gift, Kälte)'],
['Todfeind: Schmugglerbande','Nachteil groß','+4','Sozial (−20 bei Gesindel am Hafen)'],
['Angst vor Feuer','Nachteil klein','+2','alle (−10 in der Nähe von Feuer)']],'')}
<p><b>Rechnung:</b> 20 + 4 + 2 = <b>26</b>; Vorteile 4 + 2 + 2 + 2 + 2 + 2 = 14; <b>Rest 12</b>: 3 Punkte → +1 max. SP (also 6), 4 Punkte → Armbrust, 2 Punkte → Lederwams, 3 Punkte → 30 Taler (3 + 4 + 2 + 3 = 12). <b>Säulen:</b> Kampf 40, Sozial 30, Wissen 50. <b>LP</b> 10, <b>SP</b> 6 von 6.</p></div>
<div class="box ex"><b class="t">Beispiel Paladin (Vorschlag): starke Ausrüstung muss durch Nachteile bezahlt werden.</b>
<p><i>Geschichte:</i> geschworener Ritter eines Tempelordens, vom Kult gejagt, mittellos.</p>
{table(['Wort','Art','Punkte'],[['Geweihter Streiter','Vorteil groß','−4'],['Handauflegen','Vorteil groß','−4'],['Heiliger Schwur (darf nicht lügen/fliehen)','Nachteil groß','+4'],['Fanatischer Feind: Kult X','Nachteil klein','+2'],['Arm wie eine Kirchenmaus','Nachteil klein','+2']],'small')}
<p><b>Rechnung:</b> Vorteile 4 + 4 = 8; Nachteile 4 + 2 + 2 = 8; Budget 20 − 8 + 8 = <b>20</b>. Verteilt mit <code>/budget taler=3 item=Plattenpanzer,Schwert,Schild sp=1</code>: Plattenpanzer 6 + Schwert 4 + Schild 4 = 14 Punkte (140 Taler Gegenwert), +1 max. SP = 3 Punkte, Taler 3 Punkte (= 30 Taler). 14 + 3 + 3 = <b>20</b>, nichts bleibt übrig. Ohne die drei Nachteile (Budget 12) blieben nach Plattenpanzer und Schwert (10) nur 2 Punkte: kein Schild, kein SP. Die Rüstung der Figur (Leder 1, Kette 2, Platte 3) senkt den Schaden eines Gegenschlags um ihren Wert, aber nie unter 1 LP.</p></div>''')

# ================= 3 PROBE =================
add(f'''<h1>3 Die Probe (d100)</h1>
<div class="box"><b class="t">Zielzahl = Säule + Eigenschaften + Schwierigkeit (± Zustände)</b><br>Würfle d100. <b>Wurf ≤ Zielzahl</b> = Erfolg. Sonst Misserfolg.</div>
<h3>Zielzahl bilden</h3>
<ul><li><b>Säule:</b> Kampf, Sozial oder Wissen (30/40/50).</li>
<li><b>Passende Eigenschaft:</b> Vorteil klein +10, groß +20. Nachteil klein −10, groß −20. Pro Probe zählen alle Wörter, die die Spielleitung für passend hält.</li>
<li><b>Schwierigkeit:</b> siehe Tabelle.</li>
<li><b>Zustände:</b> LP ≤ 3: −10. Schicksalsmüde: SP 1 = −10, SP 0 = −20 (nicht addieren, es gilt der größere Abzug; Auslegung der Regel). Ausgegebene SP: ±10 je Punkt.</li></ul>
{table(['Schwierigkeit','Modifikator','Beispiel'],[['leicht','+20','Ein unbewachtes Fass aufstemmen'],['normal','±0','Einen müden Wirt überreden'],['schwer','−20','Ein Gift am Geruch erkennen'],['sehr schwer','−30','Im Regen eine Mauer ohne Seil erklimmen']],'small')}
<h3>Erfolgsgrade (DoS) und Misserfolgsgrade (DoF)</h3>
<div class="box"><b>Erfolg:</b> DoS = 1 + abgerundet((Zielzahl − Wurf) ÷ 10) &nbsp;&nbsp; <b>Misserfolg:</b> DoF = 1 + abgerundet((Wurf − Zielzahl) ÷ 10)<br><span class="note">Abrunden. Höchstens 10 (Auslegung). Wurf 01–05 ist immer ein Erfolg (mindestens 1 DoS), Wurf 96–100 immer ein Misserfolg (mindestens 1 DoF), auch wenn die Zielzahl etwas anderes sagt.</span></div>
{table(['Grad','Erfolg (DoS): Ergebnis','Misserfolg (DoF): Folge'],[
['1','Gerade so geschafft, mit einem kleinen Haken','Knapp daneben, nichts Schlimmes, Versuch kostet Zeit'],
['2','Solide gelungen','Daneben, ein kleiner Preis (Zeit, Lärm, Kratzer)'],
['3','Gut gemacht, ein Bonus fällt ab','Klar misslungen, ein Problem entsteht'],
['4','Sehr gut, mühelos','Deutlicher Fehlschlag, die Lage verschlechtert sich'],
['5','Meisterlich, Eindruck hinterlassen','Schwerer Fehlschlag, Ausrüstung oder Ruf leidet'],
['6','Ausgezeichnet, mehr als verlangt','Peinlich oder gefährlich, jemand wird aufmerksam'],
['7','Brillant, ein Vorteil bleibt bestehen','Fatal, ein Gegner bekommt einen Vorteil'],
['8','Herausragend, andere staunen','Katastrophal, ein Gegenstand geht verloren oder kaputt'],
['9','Legendär, wird erzählt','Verheerend, die Gruppe leidet mit'],
['10','Perfekt, kaum zu übertreffen','Unglaubliches Unglück, die Szene kippt']],'long')}
<p><b>Verwendung:</b> DoS sind Wirkungsstärke (Wie gut?) und im Kampf Schaden (Kap. 4). Die Spielleitung darf pro DoS eine kleine Zusatzwirkung erzählen.</p>
<h3>Kritisch: Pasch</h3>
<p>Ein Wurf, bei dem beide Ziffern gleich sind (<b>11, 22, 33, 44, 55, 66, 77, 88, 99, 100</b>), ist <b>kritisch</b>. Als Erfolg: <b>kritischer Erfolg</b>, die Spielleitung fügt eine Wendung zu deinen Gunsten hinzu. Als Misserfolg: <b>kritischer Misserfolg</b>, eine Komplikation tritt ein (Tabelle Kap. 7). Die DoS/DoF zählen trotzdem. Würfe unter 11 sind nie kritisch. Die 100 ist immer ein kritischer Misserfolg.</p>
<h3>Vergleichende Probe (Gegen jemanden)</h3>
<p>Beide würfeln gegen ihre eigene Zielzahl. Ein Erfolg schlägt einen Misserfolg. Haben beide Erfolg, gewinnt, wer <b>mehr DoS</b> hat; bei Gleichstand die <b>höhere Zielzahl</b>. Scheitern beide, ist es ein Patt (Auslegung): Nichts Entscheidendes geschieht, kritische Misserfolge gelten trotzdem.</p>
<h3>Proben in Foundry</h3>
<p>Ist eine Aktion riskant, zeigt sl die Karte <b>„Probe gefordert“</b>. <b>Du</b> würfelst selbst (Knopf <b>Probe würfeln</b>, vorbelegter Dialog); sl erzählt danach das Ergebnis. Würfle nicht zusätzlich von Hand. Würfelt niemand binnen etwa 90 Sekunden oder drückt die Spielleitung „sl würfeln lassen“, würfelt sl selbst. Ein Schicksalsergeben-Bonus (+1 SP) oder Schicksalsschlag zählt erst, wenn sl den Wurf bestätigt hat. Der Spielleiter-Befehl <code>/szene</code> setzt „einmal pro Szene“ für alle Figuren zurück.</p>''')

add(f'''<h3>Drei Beispiele (Mirne)</h3>
<div class="box ex"><b class="t">Beispiel 1: Armbrustschuss.</b> Mirne schießt auf eine Brieftaube. Kampf 40 + geübte Armbrustschützin 20 = <b>60</b>, normal. Wurf <b>34</b>: Erfolg, DoS = 1 + abgerundet((60 − 34) ÷ 10) = 1 + 2 = <b>3</b>. Die Taube fällt, der Brief ist unversehrt (ein Bonus von DoS 3).</div>
<div class="box ex"><b class="t">Beispiel 2: Verschmierter Brief, mit Schicksalspunkt.</b> Wissen 50 + lesen 10 − schwer 20 = <b>40</b>. Wurf <b>47</b>: Misserfolg, DoF = 1 + abgerundet(7 ÷ 10) = 1. Mirne gibt <b>1 SP</b> aus: +10 auf die Zielzahl (50). 47 ≤ 50, Erfolg mit DoS = 1 + abgerundet(3 ÷ 10) = <b>1</b>. Sie entziffert nur das Wesentliche.</div>
<div class="box ex"><b class="t">Beispiel 3: Vergleichende Probe.</b> Mirne will an einem Zollwächter vorbei (Ottokars Gefallen). Sozial 30 + 10 = <b>40</b>, Wurf <b>17</b> → DoS 1 + abgerundet(23 ÷ 10) = 3. Der Wächter (Sozial 40, kein Modifikator) würfelt <b>31</b> → DoS 1 + abgerundet(9 ÷ 10) = 1. 3 gegen 1: Mirne gewinnt und wird durchgewunken.</div>
<div class="box ex"><b class="t">Beispiel 4: Kritisch.</b> Wie Beispiel 1, Wurf <b>33</b>: Pasch und ≤ 60, also <b>kritischer Erfolg</b> mit DoS 3. Die Taube fällt, und die Spielleitung fügt eine Wendung hinzu (z. B. am Bein hängt ein zweites Papier).</div>''')

# ================= 4 KAMPF =================
add(f'''<h1>4 Kampf</h1>
<p>Kampf ist Probenspiel auf der Säule <b>Kampf</b>. Es gibt keine Rundenzahl-Pflicht: Wenn eine Seite flieht oder aufgibt, ist er vorbei.</p>
<h3>Ablauf einer Runde</h3>
<ol><li><b>Initiative:</b> Alle würfeln d100 gegen ihren Kampfwert (Zielzahl wie oben). Mehr DoS handelt zuerst; Misserfolge handeln zuletzt (Auslegung: weniger DoF zuerst). <i>Einfacher:</i> Spieler zuerst, dann Gegner.</li>
<li><b>Angriff:</b> Der Handelnde würfelt eine Kampf-Probe. Gegen einen wehrlosen oder ahnungslosen Gegner reicht <b>mindestens 1 DoS</b>.</li>
<li><b>Verteidigung:</b> Wer sich wehren kann, würfelt eine vergleichende Kampf-Probe (parieren/ausweichen). Gewinnt der Angreifer, trifft er. Gewinnt der Verteidiger, wehrt er ab (Auslegung: bei kritischem Erfolg ist ein Gegenangriff möglich). Verteidigen kostet keine Handlung. Scheitert der Angreifer, trifft er nicht.</li>
<li><b>Schaden:</b> Waffe + DoS des Angreifers − Rüstung. Ein Treffer auf eine Spielerfigur kostet mindestens 1 LP (Auslegung); Gegner können ihn ganz wegstecken. Der Verteidiger streicht diese Zahl von seinen <b>LP</b> ab.</li></ol>
<div class="box"><b class="t">Schaden = Waffe + DoS (Angreifer) − Rüstung</b> (Treffer auf Spielerfigur: min. 1 LP)</div>
<div class="grid"><div>{table(['Waffe','Schaden'],[['Faust, Ringen','1'],['Messer, Knüppel','2'],['Schwert, Axt','3'],['Bogen, Armbrust','3'],['Feuerwaffe','4']],'')}</div>
<div>{table(['Rüstung','Abzug'],[['Stoff, Lumpen','0'],['Leder','1'],['Kettenhemd','2'],['Plattenpanzer','3']],'')}</div></div>
<h3>LP (Lebenspunkte)</h3>
<ul><li>Jede Figur der Spieler hat <b>10 LP</b> (Lebenspunkte: verbleibende Gesundheit, sie zählen herunter). Schaden wird abgezogen.</li>
<li><b>Bei 3 oder weniger LP:</b> −10 auf alle Proben.</li>
<li><b>Bei 0 oder weniger:</b> Die Figur geht zu Boden. Mit <b>1 SP</b> bleibt sie am Leben (bewusstlos oder kampfunfähig). Ohne SP droht der Tod, die Spielleitung entscheidet im Sinn der Szene.</li>
<li><i>Vorschlag (nicht im Kernwerk):</i> LP heilen: Nachtruhe +2, Kräuterprobe (Wissen) mit DoS ≥ 2 zusätzlich +DoS.</li></ul>
<h3>Gegner (Vorschläge, wenn die KI ausfällt)</h3>
{table(['Typ','Kampf','LP','Waffe / Rüstung'],[['Handlanger, Räuber','30','4','Knüppel 2 / Stoff 0'],['Söldner, Wache','40','8','Schwert 3 / Leder 1'],['Veteran, Meuchler','50','10','Schwert 3 / Kette 2'],['Elite, Ritter, Ungeheuer','60','12','Schwert 3 oder Klauen 4 / Platte 3']],'')}
<div class="box ex"><b class="t">Beispielrunde: Mirne gegen einen Schmuggler</b><br>
Mirne: Kampf 40, Armbrust +20 (nur beim Schießen), LP 10, Lederwams (1). Schmuggler: Kampf 40, Schwert (3), LP 8, Leder (1).<br>
<b>Initiative:</b> Mirne würfelt 28 (Ziel 40): DoS 2. Der Schmuggler würfelt 35: DoS 1. Mirne zuerst.<br>
<b>Mirne schießt:</b> Ziel 60, Wurf 41: DoS 2. <b>Schmuggler weicht aus:</b> Ziel 40, Wurf 52: Misserfolg (DoF 2). Mirne trifft. Schaden 3 (Armbrust) + 2 − 1 (Leder) = <b>4</b>. Schmuggler: 8 → 4 LP.<br>
<b>Schmuggler greift an:</b> Ziel 40, Wurf 19: DoS 3. <b>Mirne pariert</b> mit Kampf 40 (kein Armbrustbonus im Nahkampf), Wurf 38: DoS 1. 3 gegen 1: der Schmuggler trifft. Schaden 3 + 3 − 1 (Leder) = <b>5</b>. Mirne: 10 → 5 LP.<br>
Mirne hat noch 5 LP, also über der 3er-Schwelle (kein Abzug). Nächste Runde: Initiative neu oder „Spieler zuerst“.</div>''')

# ================= 5 SP =================
add(f'''<h1>5 Schicksalspunkte (SP)</h1>
<p>SP sind eine Art Mana des Schicksals: Du <b>verbiegst</b> damit den Zufall, deinen eigenen und den der anderen. Du beginnst mit <b>5</b> (Maximum 5, mehr nur über das Budget bei der Figurenerschaffung). Du gibst SP aus <b>vor dem Wurf oder direkt danach, bevor das Ergebnis erzählt wird</b>.</p>
<h3>Ausgeben</h3>
{table(['Kosten','Wirkung'],[
['<b>1 SP</b>','<b>±10</b> auf die Zielzahl einer Probe, deiner oder der eines anderen (Gegner, NSC). Höchstens <b>3 SP</b> pro Probe.'],
['<b>1 SP</b>','Chancen des Orakels um <b>eine Stufe</b> verschieben (z. B. offen → wahrscheinlich; bei Gegnern gegen sie).'],
['<b>2 SP</b>','<b>Neu würfeln.</b> Das zweite Ergebnis zählt.'],
['<b>1 SP</b>','Bei 0 LP <b>überleben</b> (du bleibst am Boden, aber lebst).']])}
<div class="box"><b class="t">Schicksalsergeben.</b> Vor dem Wurf, bei einer Probe mit echtem Einsatz (die Spielleitung entscheidet; nie bei leichten Proben, Initiative oder reinen Übungen), kannst du dich dem Schicksal ergeben: <b>−10</b> auf die Probe. Gelingt sie trotzdem mit mindestens <b>2 Erfolgsgraden</b>, erhältst du <b>1 SP</b> zurück (nicht über dein Maximum). Scheitert sie, ist es ein <b>Schicksalsschlag</b>: der Misserfolg zählt <b>einen Fehlergrad mehr</b> und wird härter erzählt.<br>
<b>Einmal pro Szene und Figur.</b> Nicht kombinierbar mit SP auf derselben Probe, weder eigenen noch fremden. Ein Neuwurf (2 SP) bleibt erlaubt, das zweite Ergebnis zählt.</div>
<p class="note">±10 auf die Zielzahl entspricht ∓10 auf den Wurf: Erfolgsgrade ändern sich nach der Formel, der Pasch bleibt Pasch.</p>
<h3>Schwellen (Schicksalsmüdigkeit)</h3>
{table(['SP','Folge'],[['5 bis 2','keine'],['1','„schicksalsmüde“: <b>−10</b> auf alle Proben'],['0','<b>−20</b> auf alle Proben (statt −10), und Orakelfragen zu deinen Gunsten gehen eine Stufe schlechter aus']],'small')}
<h3>Erholung</h3>
{table(['Anlass','SP'],[['Kurze Rast (etwa eine Stunde)','+1'],['Nachtruhe oder sicherer Ort','+3'],['Du spielst einen deiner <b>Nachteile</b> so aus, dass es dich etwas kostet (Entscheidung der Spielleitung)','+1'],['Fest, Feier, Tempel','+2'],['Einen Handlungsstrang abschließen','+2']],'small')}
<p>Das Maximum bleibt die Obergrenze.</p>
<div class="box ex"><b class="t">Beispiel A: Einen NSC-Wurf verbiegen.</b> Der Schmuggler greift Mirne mit Ziel 40 an und würfelt 19 (DoS 3). Mirne gibt <b>2 SP</b> aus: −20 auf die Zielzahl des Schmugglers (Ziel 20). 19 ≤ 20 ist noch ein Treffer, aber nur DoS 1 + abgerundet(1 ÷ 10) = <b>1</b>. Statt 5 bekommt Mirne nur 3 + 1 − 1 = <b>3</b> Schaden. Mit einem dritten SP (Ziel 10) wäre 19 ein Misserfolg gewesen. Mirne hat jetzt 4 von 6 SP.</div>
<div class="box ex"><b class="t">Beispiel B: Orakel-Chancen verschieben.</b> Frage: „Ist die Hintertür unverschlossen?“ Spannung 5, Chancen <b>offen</b>: JA+ ≤ {A[0]}, JA ≤ {A[1]}, NEIN ≤ {A[2]}, darüber NEIN+. Mirne gibt <b>1 SP</b> aus und verschiebt auf <b>wahrscheinlich</b>: JA+ ≤ {B[0]}, JA ≤ {B[1]}, NEIN ≤ {B[2]}. Die Chance auf JA oder JA+ steigt von {A[1]} % auf {B[1]} %. Würde ein Gegner das Orakel verbiegen, verschiebt er die Chancen entsprechend in die andere Richtung.</div>
<div class="box ex"><b class="t">Beispiel C: Rettung und Neuwurf.</b> Mirne hat 4 SP (Stand nach Beispiel A) und sinkt auf 0 LP. Sie gibt 1 SP aus und bleibt am Leben (3 SP). Beim Entkommen wirft sie 88 gegen Ziel 60 (DoF 3). Sie zahlt <b>2 SP</b> für einen Neuwurf: 41, Erfolg mit DoS 2. Das zweite Ergebnis zählt. Jetzt hat sie nur noch 1 SP und ist schicksalsmüde (−10 auf alle Proben).</div>
<div class="box ex"><b class="t">Beispiel D: Schicksalsergeben.</b> Kampf 50, Ziel mit Ergeben <b>40</b>. Wurf <b>30</b>: DoS 2, <b>+1 SP</b> (Wurf 35: DoS 1, kein SP). Wurf <b>45</b>: DoF 1 + 1 = <b>2</b>, Schicksalsschlag. Gewinn gibt es bei Wurf ≤ Ziel − 20; jeder Misserfolg bekommt +1 DoF.</div>''')

# ================= 6 ORAKEL =================
add(f'''<h1>6 Das Orakel ohne KI</h1>
<p>Das Orakel beantwortet Fragen, die nicht von deinem Können abhängen. Es ist dasselbe Verfahren, das der KI-Spielleiter benutzt (das Programm <code>schicksal</code>), hier zum Nachwürfeln.</p>
<h3>Spannung</h3>
<p>Die <b>Spannung</b> (1–9) misst, wie angespannt die Geschichte ist. Start: <b>5</b>. Sie macht Zufallsereignisse wahrscheinlicher und verschiebt die Orakelantworten. <b>Notiere sie auf dem Spielstandzettel (Kap. 8).</b> Am <b>Szenenende</b> bewegt sie sich <b>immer</b> (auch weg von 5): Hatten die Spieler die Szene unter Kontrolle: <b>−1</b>. Sonst: <b>+1</b>. Bei einer <b>klar gekippten</b> Szene sind es <b>±2</b>: <b>+2</b>, wenn mindestens drei Orakelantworten NEIN/NEIN+ und keine JA/JA+ waren, oder wenn ein Zufallsereignis zusammen mit einer misslungenen Probe auftrat; <b>−2</b>, wenn mindestens drei Antworten JA/JA+ und keine NEIN/NEIN+ waren, ohne Zufallsereignis und ohne misslungene Probe. Grenzen 1 und 9. Die Spielleitung kann die Spannung jederzeit mit <code>/spannung +N</code>, <code>/spannung -N</code> oder <code>/spannung N</code> verschieben oder setzen (nur GM, im Chat oder mit dem GM-Knopf „Spannung“); die KI erzählt danach dichter (steigt) oder ruhiger (sinkt), die Spieler sehen den Wert nicht.</p>
<h3>Eine Ja/Nein-Frage stellen</h3>
<ol><li>Formuliere die Frage so, dass „Ja“ eine klare Aussage ist („Ist die Tür verschlossen?“). Höchstens <b>6 Fragen pro Szene</b>.</li>
<li>Schätze die <b>Chancen</b> (7 Stufen): fast unmöglich · sehr unwahrscheinlich · unwahrscheinlich · <b>offen</b> (Vorgabe, wenn du unsicher bist) · wahrscheinlich · sehr wahrscheinlich · fast sicher. Schicksalspunkte verschieben um eine Stufe.</li>
<li>Suche in der Schicksalstabelle die Zeile (Chancen) und Spalte (Spannung). Du findest drei Zahlen <b>a / b / c</b> (obere / mittlere / untere).</li>
<li>Würfle d100: <b>Wurf ≤ a = JA+</b> (Ja, und sogar mehr) · <b>≤ b = JA</b> · <b>≤ c = NEIN</b> · <b>&gt; c = NEIN+</b> (Nein, und es kommt schlimmer). „–“ heißt: Diese Antwort gibt es in dieser Zelle nicht.</li>
<li><b>Pasch prüfen:</b> Ist der Wurf ein Pasch (11, 22 … 99) und die Ziffer <b>≤ Spannung</b> (z. B. 33 bei Spannung ≥ 3), tritt zusätzlich ein <b>Zufallsereignis</b> ein (nächste Seiten). Die Antwort gilt trotzdem.</li></ol>
<h3>Schicksalstabelle</h3>
{T.fate_chart()}
<p class="note">Jede Zelle: <b>a</b> (JA+ bis) / <b>b</b> (JA bis) / <b>c</b> (NEIN bis, darüber NEIN+). Beispiel: offen, Spannung 5 → {A[0]} / {A[1]} / {A[2]}: Wurf 1–{A[0]} JA+, {A[0]+1}–{A[1]} JA, {A[1]+1}–{A[2]} NEIN, {A[2]+1}–100 NEIN+. Erzeugt aus den Formeln des Programms.</p>''')

fo = T.event_focus(); mt = T.mut_table(); sc = T.scene_table()
rel = P_rel = POOLS and T.P['relationen']
add(f'''<h1>6 Das Orakel ohne KI (Fortsetzung)</h1>
<h3>Zufallsereignis</h3>
<p>Tritt auf, wenn ein Orakelwurf ein <b>Pasch mit Ziffer ≤ Spannung</b> ist (bei Spannung 5 also 11, 22, 33, 44, 55). Du kannst auch jederzeit eines erzwingen („Was passiert jetzt?“). Ablauf: (1) <b>Fokus würfeln</b> (d100), (2) <b>Wortpaar würfeln</b> (zwei Wörter, Tabellen unten), (3) beides auf die Lage deuten.</p>
<p class="note">Die Pasch-Regel ergibt am Tisch etwa „Spannung Prozent“ pro Orakelwurf. Das Programm würfelt Ereignisse im Standard deutlich öfter (bis etwa 10 × Spannung Prozent, je nach Fragen pro Szene). Wollt ihr mehr Ereignisse: Ereignis bei Wurf ≤ 2 × Spannung statt nur bei Pasch.</p>
{fo}
<p><b>Akteur-Fokus</b> (Akteur handelt/leidet/gewinnt): Wähle per Zufall aus deiner <b>Akteursliste</b> (wichtige NSC, Gruppen, bis etwa 20 Einträge). <b>Strang-Fokus</b>: aus deiner Liste offener Handlungsstränge. Mit wachsender Liste steigt die Chance auf einen <b>neuen, noch nicht gelisteten</b> Akteur oder Strang weniger: Würfle d100 ≤ (1 − Einträge ÷ 20)² × 100 (mindestens 5), dann ist es ein Neuer. Ist die Liste leer, wird der Fokus <b>Umgebung (Kontext)</b>. Auf <b>Figur</b>-Fokus trifft es eine Figur der Spieler (auslosen).</p>
<h3>Szenenbeginn: Erwartung prüfen</h3>
<p>Beschreibe, was du <b>erwartest</b>. Würfle d100: Wurf ≤ 5 × Spannung = die Szene <b>verändert sich</b>. Dann würfle noch einmal d100: im Bereich „Unterbrechung“ gibt es ein <b>Zufallsereignis</b> (Fokus würfeln), sonst eine <b>Abwandlung</b>. Die erste Szene des Abends wird nicht getestet.</p>
{sc}
<h3>Szene abwandeln</h3>
<p>Würfle d100 für die Art der Änderung, dann d5 für das Element: 1 Tätigkeit · 2 Beteiligte · 3 Ort · 4 Gegenstand · 5 Stimmung. Das Element sollte in deiner Erwartung vorkommen (außer bei „hinzufügen“: dann eines, das fehlt), sonst neu würfeln. Selten (15 %) wiederhole das Ganze einmal für ein zweites, anderes Element. Ziehe dann ein Wortpaar: bei Ort aus <i>Eigenschaft + Ort</i>, bei Gegenstand aus <i>Eigenschaft + Ding</i>, sonst aus <i>Handlung + Thema</i>.</p>
{mt}''')

add(f'''<h1>6 Das Orakel ohne KI: Wortpaare</h1>
<p>Zwei Wörter ergeben einen Anstoß, den du auf die Lage deutest („verraten“ + „Schlüssel“: jemand hat einen Schlüssel verraten). Würfle <b>d100 je Wort</b>; liegt der Wurf über der Anzahl der Einträge, würfle neu. Den Pool bestimmt die Lage:</p>
{table(['Pool','Wörter','Zusammen mit'],[['Handlung + Thema','Standard für fast alle Ereignisse (Fokus-Tabelle)','Handlung = Verb, Thema = Nomen'],['Eigenschaft + Rolle','neue Figur tritt auf','Eigenschaft passt zum Beruf'],['Eigenschaft + Thema','Zeichen, Vorzeichen',''],['Eigenschaft + Ort / Ding','Szene abwandeln: Ort / Gegenstand',''],['Antrieb + Ziel','NSC-Motiv','Ziel: Gruppe (d8), Eintrag (d8)']],'')}
{wl('tun').replace('Tun','Handlung (Verb)')}
{wl('thema').replace('Thema','Thema (Nomen)')}
{wl('art').replace('Art','Eigenschaft')}
{wl('rolle')}''')

reaktion = ['feindselig, greift an oder ruft die Wache','abweisend, will nichts hören','misstrauisch, antwortet knapp','reserviert, wartet ab','neutral, geschäftsmäßig','freundlich, aber vorsichtig','interessiert, fragt nach','hilfsbereit, bietet etwas an','begeistert, nimmt dich in Schutz','ergeben, würde viel für dich riskieren']
add(f'''<h1>6 Das Orakel ohne KI: Figuren</h1>
<h3>NSC-Reaktion (Vorschlag, nicht Teil des Kernwerks)</h3>
<p>Würfle <b>d10</b> und lies die Haltung ab. Modifikator: gelungene Sozial-Probe zuvor <b>+1</b> (kritisch +2), misslungene <b>−1</b> (kritisch −2); gute Gründe oder Geschenke +1, Beleidigung −1 bis −3. Ergebnis auf <b>1–10</b> begrenzen.</p>
{d10t(reaktion,'Haltung des NSC')}
<p>Dazu <b>Wesenszug</b> (d100, 70 Einträge) und, wenn du magst, <b>Motiv</b> (Antrieb d100, 40 Einträge, plus Ziel aus der Tabelle unten). Ob der NSC jetzt etwas Bestimmtes tut, fragst du das Orakel (z. B. „Verrät er uns?“, Chancen nach Haltung: 1–2 sehr unwahrscheinlich · 5 offen · 9–10 sehr wahrscheinlich).</p>
{wl('wesen')}
<h3>Motiv: Antrieb und Ziel</h3>
{wl('antrieb')}
<p>Ziel: würfle <b>d8 für die Gruppe</b> (Spalte) und <b>d8 für den Eintrag</b> (Zeile).</p>
{T.ziel_table()}
<h3>Beziehung (d6): „Wie hängen A und B zusammen?“ (A … B)</h3>
{d10t(T.P['relationen'],'',3).replace('d10','d6')}''')

add(f'''<h1>6 Das Orakel ohne KI: Orte, Dinge, Gespräche</h1>
{wl('ort')}
{wl('ding')}
{T.wordlist([x['w'] for x in POOLS['gespraech']],'Gesprächsthema (worüber ein NSC spricht)',2)}
{wl('spur')}
<p class="note">Die Einträge „spur“ sind Fundstücke und Hinweise: zieh eines, wenn die Figuren etwas untersuchen und die Probe gelingt (mehr DoS = deutlicher).</p>''')

# ================= 7 IMPROV =================
vor, bein = N['vornamen'], N['beinamen']
add(f'''<h1>7 Einfalls-Werkzeugkasten</h1>
<h3>Namen</h3>
<p>Würfle d100 für den Vornamen und d100 für den Beinamen (Beruf, Aussehen, Herkunft). Also zum Beispiel „{e(vor[0])} {e(bein[0])}“ oder „{e(vor[41])} {e(bein[29])}“.</p>
{T.wordlist(vor,'Vornamen',5)}
{T.wordlist(bein,'Beinamen',4)}
<div class="grid"><div><h3>Herkunft (d100)</h3>{d20t(N['herkunft'],'Herkunft','',1)}</div>
<div><h3>Auffälligkeit (d100)</h3>{d20t(N['auffaelligkeit'],'Auffälligkeit','',1)}</div></div>''')

add(f'''<h1>7 Einfalls-Werkzeugkasten: Orte und Schänken</h1>
<h3>Siedlung oder Ort (d100)</h3>{d20t(W['orte'],'Ort','')}
<h3>Schänke: Name (d100)</h3>{d20t(W['schaenken_name'],'Name','')}
<h3>Schänke: Besonderheit (d100)</h3>{d20t(W['schaenken_besonderheit'],'Besonderheit','')}
<div class="grid"><div><h3>Wirt (d10)</h3>{d10t(W['schaenken_wirt'],'Wirt',1)}</div><div><h3>Gerücht (d10)</h3>{d10t(W['geruechte'],'Gerücht',1)}</div></div>''')

add(f'''<h1>7 Einfalls-Werkzeugkasten: Komplikationen, Beute, Stimmung</h1>
<h3>Komplikation (d100). Kritischer Misserfolg oder Szene verkompliziert</h3>{d20t(W['komplikationen'],'Komplikation','')}
<div class="grid"><div><h3>Beute: Kleinkram (d100), 1–10 Taler</h3>{d20t(W['beute_kleinkram'],'Fund','',1)}</div>
<div><h3>Beute: wertvoll (d100)</h3>{d20t(W['beute_wertvoll'],'Fund','',1)}</div></div>
<div class="grid"><div><h3>Wetter (d10)</h3>{d10t(W['wetter'],'Wetter',1)}</div>
<div><h3>Stimmung der Szene (d10)</h3>{d10t(W['tageszeit_stimmung'],'Sinn',1)}</div></div>''')

# ================= 8 FALLBACK =================
add(f'''<h1 class="pb">8 Notfall: Spielleitung von Hand</h1>
<p>Wenn sl hängt (keine Antwort, Absturz, kaputte Verbindung) oder die Technik ausfällt: <b>nicht abbrechen.</b> Das Spiel läuft mit diesem Heft weiter.</p>
<h3>Ablauf</h3>
<ol>
<li><b>Pause ausrufen</b> („Pause, wir spielen von Hand weiter“). Kurz sagen, warum, damit alle Bescheid wissen.</li>
<li><b>Spielleiter bestimmen:</b> Eine Person erzählt, würfelt für alle NSC und führt den Spielstandzettel (unten). Ist keine da, wechselt ihr reihum pro Szene.</li>
<li><b>Stand sichern.</b> Notiere: aktuelle Szene (ein Satz), Ort, anwesende NSC, Spannung, SP und LP jeder Figur, offene Akteure und Stränge. Wenn sl noch erreichbar ist: <code>/status</code> und <code>/welt</code> zeigen den Zustand.</li>
<li><b>Weiterspielen:</b> Szene beschreiben → Spieler handeln → Probe (Kap. 3) oder Orakel (Kap. 6) oder erzählen. Szenenbeginn: Erwartung prüfen. Bei Pasch ≤ Spannung: Ereignis. Namen, Orte, Beute aus Kap. 7. Notfalls: Komplikation würfeln.</li>
<li><b>NSC</b> bekommen Haltung (d10), ein Wesenswort und ein Motiv. Kampfwerte aus Kap. 4.</li>
<li><b>Szenenende:</b> Spannung anpassen, Stränge und Akteure notieren, SP-Erholung nach Tabelle.</li>
<li><b>Rückkehr zu sl:</b> Schreibe eine Kurzfassung (5–10 Sätze: was geschah, wer lebt, wer will was, wo seid ihr) und gib sie als Regieanweisung mit <code>/regie</code> an sl. Setze Spannung, SP und LP wie notiert. Erst dann normal weiterspielen. Beim ersten Zug danach: Szenenbeginn neu prüfen.</li></ol>
<div class="box"><b class="t">Faustregel für schnelles Improvisieren:</b> Erst fragen „Was ist am wahrscheinlichsten?“ → Orakel mit passenden Chancen. Bei Unsicherheit: <b>offen</b>. Wenn die Antwort langweilig ist, erlaube ein Ereignis. Wenn es zu viel wird, senke die Spannung.</div>
<h3>Spielstandzettel</h3>
{table(['Feld','Eintrag'],[['Szene Nr. / Ort',''],['Spannung (1–9)','&nbsp;'],['Fragen in dieser Szene (max. 6)','☐ ☐ ☐ ☐ ☐ ☐'],['Akteure (NSC, Gruppen)','&nbsp;<br>&nbsp;'],['Offene Stränge','&nbsp;<br>&nbsp;'],['LP / SP je Figur','&nbsp;<br>&nbsp;']],'blank')}''')

# ================= 9 SHEET =================
fld = lambda w='30mm': f'<span class="fld" style="min-width:{w}"></span>'
add(f'''<div class="sheet"><h1>9 Charakterbogen</h1>
<p>Name: {fld('55mm')} Spieler: {fld('35mm')} Herkunft/Beruf: {fld('45mm')}</p>
<div class="grid">
<div style="width:50%"><h3>Hintergrund (3–8 Sätze)</h3>{'<div class="line"></div>'*7}</div>
<div style="width:50%"><h3>Budget</h3><p>Start 20 + Nachteile {fld('9mm')} − Vorteile {fld('9mm')} = Rest {fld('9mm')}<br>Taler {fld('9mm')} · Gegenst. {fld('9mm')} · SP-Max {fld('9mm')}</p>
<table class="blank"><thead><tr><th>Säule</th><th>Basis (30/40/50)</th></tr></thead><tbody><tr><td><b>Kampf</b></td><td></td></tr><tr><td><b>Sozial</b></td><td></td></tr><tr><td><b>Wissen</b></td><td></td></tr></tbody></table></div></div>
<h3>Eigenschaften (Wörter)</h3>
<table class="blank"><thead><tr><th style="width:42%">Wort</th><th>Klein/Groß</th><th>Punkte (−2/−4 · +2/+4)</th><th>Säule</th><th>Wirkung</th></tr></thead><tbody>{'<tr><td></td><td></td><td></td><td></td><td></td></tr>'*9}</tbody></table>
<div class="grid">
<div><h3>LP (10)</h3><p>{''.join('<span class="cb"></span>' for _ in range(10))}<br><span class="note">Bei ≤ 3: −10 auf alles. Bei 0: nur mit 1 SP am Leben.</span></p>
<h3>Schicksalspunkte (Max ____)</h3><p>{''.join('<span class="cb"></span>' for _ in range(8))}<br><span class="note">SP 1: −10. SP 0: −20 und Orakel schlechter.</span></p></div>
<div><h3>Waffen und Rüstung</h3><table class="blank"><thead><tr><th>Name</th><th>Schaden / Abzug</th></tr></thead><tbody><tr><td></td><td></td></tr><tr><td></td><td></td></tr><tr><td></td><td></td></tr></tbody></table></div></div>
<div class="grid"><div style="width:50%"><h3>Ausrüstung</h3>{'<div class="line"></div>'*5}</div><div><h3>Taler</h3><div class="line"></div><h3>Notizen (Kontakte, Schulden, Feinde)</h3>{'<div class="line"></div>'*3}</div></div>
</div>''')

# ================= 10 SPICK =================
add(f'''<div class="sheet"><h1>10 Spickzettel: alle Modifikatoren</h1>
<div class="box"><b class="t">Zielzahl = Säule + Eigenschaften + Schwierigkeit + Zustände.</b> &nbsp; Würfle d100, <b>Wurf ≤ Zielzahl = Erfolg</b>. Wurf 01–05 immer Erfolg, 96–100 immer Misserfolg.<br>
<b>DoS</b> = 1 + abgerundet((Ziel − Wurf) ÷ 10) &nbsp;·&nbsp; <b>DoF</b> = 1 + abgerundet((Wurf − Ziel) ÷ 10) &nbsp;·&nbsp; max 10 &nbsp;·&nbsp; <b>Pasch</b> (11 … 99, 100) = kritisch.</div>
<div class="grid"><div>
{table(['Quelle','Mod.'],[['Vorteil klein / groß','+10 / +20'],['Nachteil klein / groß','−10 / −20'],['Schwierigkeit leicht','+20'],['normal','±0'],['schwer','−20'],['sehr schwer','−30'],['LP ≤ 3','−10'],['SP = 1','−10'],['SP = 0','−20 (nicht addiert)'],['1 SP ausgegeben (max. 3 je Probe)','±10 pro SP, auch bei anderen'],['Schicksalsergeben (1× je Szene)','−10, ohne SP']],'')}</div>
<div>
{table(['Säule','Grundwert'],[['Kampf, Sozial, Wissen','30 / 40 / 50 (frei verteilt)']],'')}
{table(['Waffe','Sch.'],[['Faust','1'],['Messer, Knüppel','2'],['Schwert, Axt, Bogen, Armbrust','3'],['Feuerwaffe','4']],'')}
{table(['Rüstung','Abzug'],[['Stoff','0'],['Leder','1'],['Kette','2'],['Platte','3']],'')}</div>
<div>
{table(['SP-Kosten','Wirkung'],[['1','±10 auf eine Probe'],['1','Orakel um 1 Stufe'],['2','Neuwurf'],['1','Überleben bei 0 LP'],['+1','Ergeben: ≥ 2 DoS, Wurf ≤ Ziel − 20']],'')}
{table(['SP-Erholung','+'],[['Rast 1 h','1'],['Nacht / sicher','3'],['Nachteil ausgespielt','1'],['Fest / Tempel','2'],['Strang abgeschlossen','2']],'')}</div></div>
<div class="grid"><div>
<b>Schaden</b> = Waffe + DoS − Rüstung (Treffer auf Spielerfigur min. 1 LP). LP 10.<br><b>Vergleichende Probe:</b> Erfolg schlägt Misserfolg; sonst mehr DoS, Gleichstand: höhere Zielzahl; beide scheitern: Patt.<br><b>Initiative:</b> d100 ≤ Kampf, mehr DoS zuerst (oder Spieler zuerst).<br><b>Kritisch:</b> Pasch bei Erfolg = Wendung für dich, bei Misserfolg = Komplikation.<br><b>Schicksalsergeben:</b> vor dem Wurf −10; ≥ 2 DoS = +1 SP; Misserfolg = +1 DoF (Schicksalsschlag). Nie leicht, nicht mit SP, 1× je Szene und Figur.</div>
<div><b>Startbudget</b> 20 Punkte. Vorteil −2 / −4, Nachteil +2 / +4. Rest: 1 Punkt = 10 Taler · 2/4/6 Punkte = Gegenstand (Vorschlag, Stufen in Kap. 2) · 3 Punkte = +1 SP-Max.<br><b>Orakel:</b> Chancen × Spannung → a/b/c; d100 ≤ a JA+ · ≤ b JA · ≤ c NEIN · darüber NEIN+. Pasch mit Ziffer ≤ Spannung = Ereignis.<br><b>Szenentest:</b> d100 ≤ 5 × Spannung → Szene verändert.</div></div>
<h3>Preise (Vorschlag, Kap. 11)</h3>
<p style="margin-bottom:0">1 Taler = 2 Schilling = 4 Heller. Messer, Knüppel, Lederrüstung 20 T · Schwert, Axt, Bogen, Kette, Schild 40 T · Platte, Feuerwaffe 60 T. Mahlzeit 2 H, Tagelohn 1 T. 10 Taler = 1 Budgetpunkt.</p></div>''')

# ================= 11 GEGENSTAENDE =================
from items.pages import pages as item_pages
for x in item_pages(): add(x)

# ================= BUILD =================
doc = '<!doctype html><html lang="de"><head><meta charset="utf-8"><title>Schicksalsschlag – Handout</title><link rel="stylesheet" href="style.css"></head><body>' + '\n'.join(P) + '</body></html>'
open(os.path.join(H, 'handout.html'), 'w').write(doc)
out = os.path.join(H, 'Schicksalsschlag-Handout.pdf')
os.environ.setdefault('DYLD_FALLBACK_LIBRARY_PATH', '/opt/homebrew/lib')
subprocess.run(['/opt/miniconda3/bin/weasyprint', os.path.join(H, 'handout.html'), out], check=True)
print('ok', out)
