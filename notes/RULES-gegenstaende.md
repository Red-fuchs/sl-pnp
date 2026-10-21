# Schicksalsschlag: Gegenstände und Händler (Vorschlag v0.2, 2026-10-22)

Gegenstandsgenerator mit d100-Tabellen im Stil der NPC-Tabellen, Wahrscheinlichkeiten als **Orakelfragen** (keine Zusatzregeln). Alle Zahlen sind **Vorschlag**, bis der Spielleiter sie freigibt. Einzige Datenquelle: `handout/items/data/*.json` (Übersicht: `handout/items/README.md`). PDF: Handout-Kapitel 11 (Seiten 19–36), erzeugt von `handout/items/pages.py`. Roller: `handout/items/roll.py`. Fate-Chart und Wortpaare kommen aus `handout/tables.py` (Orakel-Daten), nichts ist kopiert.

## Währung
- 1 **Taler (T)** = 2 **Schilling (S)** = 4 **Heller (H)**. Engine und JSON rechnen nur in Heller (`preis_h`, ganze Zahl).
- **10 Taler = 40 Heller = 1 Budgetpunkt**; Posten unter 10 T zählen 0 Punkte. Startausrüstung: höchstens Tarif 60 T (6 P) je Stück; exotische Waffen/Rüstungen der Listen (bis 100 T) sind Beute oder Kauf im Spiel. Tarife normal: 20 / 40 / 60 T; Paladin Platte + Schwert + Schild = 140 T = 14 P bleibt.

## Ablauf eines Gegenstands
1. **Art:** d20 → Kategorie (Waffe 1–3, Rüstung 4–5, Werkzeug 6–8, Trank 9–12, Kleidung 13, Schmuck 14–15, Schrift 16, Kuriosum 17–18, Transport 19–20), dann **d100 → Gegenstand** (je Kategorie 50 Posten; 01–60 gängig, 61–80 spezialisiert, 81–00 exotisch).
2. **Seltenheit** d100: 01–60 gewöhnlich · 61–85 ungewöhnlich · 86–95 selten · 96–99 sehr selten · 100 legendär.
3. **Prägung** d20 (Spalte = Seltenheit): Plunder (×¼), normal (×1), gut gearbeitet (×1½), magisch, gesegnet, verflucht, Wendung (`praegung_d20` in preise.json).
4. **Eigenschaften:**
   - ohne Magie: **Merkmale**: Material, Machart, Zustand, Besonderheit (je d100, mit Gruppen-Tags), Herkunft (d100). **Jeder Posten trägt seine Materialgruppen** (`mat`: metall, holz, leder, textil, stein_glas, organisch, papier, tier, zutat); gewürfelt wird nur in diesen Gruppen, Tränke immer in Zutat; Machart/Zustand/Besonderheit mit Tag gelten nur für diese Gruppen (`lint` prüft, dass jede Gruppe existiert und keine Pools dünn sind). Plunder Zustand (01–30), gut Machart, gewöhnlich Material + eines nach Wahl, ungewöhnlich/Wendung Material + Machart + Besonderheit. Merkmale ändern den Preis nicht. Besonderheiten tragen manchmal eine kleine Regel (+10 einmal pro Szene / −10 in einer Lage).
   - mit Magie (magisch, gesegnet, verflucht, Wendung): **Rahmen** aus der Tabelle Wirkung bzw. Segen (d100 mit Fenster). **Ab selten** zusätzlich **ein Wortpaar** (tun + thema aus den Orakel-Wortlisten: Natur, Herkunft, Haken) und **höchstens zwei Orakelfragen** (nur wenn sie reizen; Liste `orakel.fragen_item`: Hat es einen Preis? Kennt jemand es? …). Name optional (Epitheton × Bezug, zwei d100).

## Fenster (Seltenheit schiebt die Tabelle)
Alle d100-Wirkungstabellen sind nach Stärke bzw. Schwere aufsteigend sortiert. Ein d100, Fenster der Breite 50: ungewöhnlich 01–50 · selten 26–75 · sehr selten und legendär 51–00. **Liegt der Wurf unter dem Fenster, +50; darüber, −50.** Legendär würfelt **zweimal** (zwei Einträge verschiedener Art, `typ`). Gleiches Fenster für Wirkung, Segen, Fluch, Wendung (gewöhnliche Wendung: 01–50).

## Preise (steigen mit der Seltenheit)
- Nichtmagisch (Plunder ×¼, normal ×1, gut ×1½, Wendung wie normal): **Basis × Prägung × Seltenheitsfaktor**, Faktor gewöhnlich 1 · ungewöhnlich 1,5 · selten 2 · sehr selten 3 · legendär 4 (`seltenheit[].preis_mult`).
- Magisch/gesegnet: **Basis × Faktor + Stufenpreis** (ungewöhnlich 250 T · selten 500 T · sehr selten 1000 T · legendär 2000 T); verflucht die Hälfte davon, nie teurer als magisch.
- **Magische Tränke/Verbrauchsgüter:** Basis × 3 / 5 / 8 / 12 (ungewöhnlich bis legendär, `trank_mult`), verflucht die Hälfte. Der Heiltrank folgt seiner eigenen Staffel (Basis × LP/2, Faktor entfällt). **Gifte und Reizstoffe** (`schaedlich`) sind nie magisch/gesegnet/verflucht (sie zählen als gut gearbeitet); so kostet z. B. eine Nachtschattenpaste nie mehr als ein magisches Heilmittel gleicher Seltenheit.
- Ab 10 T auf 5 T gerundet. Magie ist mit dem Startbudget (200 T) nie zu bezahlen. `lint` prüft: Preis je Gegenstand und Prägung steigt (nie fallend) mit der Seltenheit, verflucht ≤ magisch, magisch ≥ normal. Ø Preis in Taler je Kategorie × Seltenheit (normal | magisch):

```
Ø Preis (T) je Kategorie x Seltenheit; Prägung normal | magisch (Heiltrank/Verbrauch eingerechnet)
  waffe         44.2|      0    66.3|    316    88.4|    588   132.6|   1133   176.8|   2177
  ruestung      34.7|      0    52.3|    302    69.4|    569   104.1|   1104   138.8|   2139
  werkzeug      17.4|      0    26.1|    276    34.9|    535    52.0|   1052    69.3|   2069
  trank         11.5|      0    17.1|     28    22.8|     49    34.2|     80    45.0|    120
  kleidung      24.1|      0    36.1|    286    47.6|    548    71.9|   1072    95.4|   2095
  schmuck       63.3|      0    94.9|    345   125.8|    626   189.0|   1189   251.4|   2252
  schrift       31.0|      0    46.3|    296    61.0|    561    92.0|   1092   122.0|   2122
  kuriosum      20.5|      0    31.1|    281    41.2|    541    61.2|   1061    81.7|   2082
  transport     85.8|      0   129.1|    379   171.5|    672   257.3|   1257   343.0|   2343
```

## Kraft: KP und Grenzen
- Jeder Eintrag in Wirkung/Segen hat `kp` 1–3 und `takt` (passiv · Szene · Sitzung): kp 1 = +10 situativ, Trick, einmal pro Sitzung Neuwurf / 2 LP / Schutz; kp 2 = +1 Schaden oder Rüstung, +20 eng umrissen, Orakel-Schub, Treffer auf 1; kp 3 = Kombination, +1 SP (nur Segen). Budget je Seltenheit: ungewöhnlich 1, selten 1–2, sehr selten 2–3, legendär zwei Effekte (bis 6 KP).
- **Harte Grenzen:** Schaden 5, Rüstung 3 (Überschuss = ein +10 auf die Verteidigung). Gegenstände geben auf eine Probe zusammen höchstens **+20**. Schaden-/Rüstungseinträge gelten nur für Waffe bzw. Rüstung (Roller würfelt sonst neu). **SP:** höchstens ein Segen mit „+1 SP“ je Figur, einmal pro Sitzung, nie über das Maximum; kein Gegenstand erhöht das SP-Maximum; Wendungs-Enthüllungen geben keine SP. **Heilung** durch Gegenstände höchstens 2 LP je Anwendung, einmal pro Sitzung und Ziel, zusammen höchstens 6 LP je Sitzung und Figur (Tränke ausgenommen). **Ausnahme Heiltrank (Entscheidung des Spielleiters):** er heilt nach Seltenheit 1 LP (gewöhnlich), 2 (ungewöhnlich, der normale Deckel), 3 (selten), 4 (sehr selten, legendär); die 4 LP gibt es nur bei hoher Seltenheit. Preis = Basis (120 H) × LP/2 (gewöhnlich ×½ bis sehr selten ×2), ohne zusätzlichen Seltenheitsfaktor, als magisch/gesegnet × trank_mult. Kräuterumschlag (1 LP) und Wundsalbe (2 LP) bleiben fest.
- **Schicksalsergeben:** aktive Fähigkeiten (Neuwurf, Orakel-Schub, Schutz, Trick) zählen wie SP-Einsatz: auf einer Probe mit Schicksalsergeben gelten nur passive Boni (sonst wäre ergeben mit Gratis-Neuwurf eine fast risikolose SP-Quelle).
- Prägung ist exklusiv: „gut gearbeitet“ und Magie stapeln nicht.

## Fluch (nur Spielleitung)
- Wirkung (Tabelle magisch, immer ein Vorteil) plus ein Fluch aus der Tabelle (Fenster nach Seltenheit). Stufen: 1 Makel · 2 Zehrend · 3 Bösartig · 4 Gebunden (Pakt, Erwachter Wille, Hunger 2 SP, verlangt Blut, Besitzanspruch). Jeder Eintrag hat Nachteil **und** Haken (Aufhänger oder verborgener Vorteil). Flüche sind objektneutral formuliert.
- **Klebt:** jeder verfluchte Gegenstand lässt sich nicht ablegen oder verkaufen, bis der Fluch gelöst ist.
- **Hunger:** zu Sitzungsbeginn zahlt der Träger die genannten SP (nie unter 1 SP); sonst ruht die Wirkung und es gilt −10 auf alle Proben mit ihm; zwei Sitzungen hintereinander ungezahlt: der Fluch rückt eine Stufe vor.
- **Lösen:** Weihe kostet den halben Stufenpreis (verflucht + Weihe = Preis des magischen Stücks, keine Arbitrage) plus Wissen-Probe schwer eines Priesters; sehr selten/legendär zusätzlich ein abgeschlossener Handlungsstrang. **Erkennen:** Wissen-Probe schwer, beim Zuschlagen oder Orakelfrage „Erkennt jemand den Fluch?“ (unwahrscheinlich).

## Wendung (nur Spielleitung)
d100 mit Fenster; Stufe 1–4 nach Gewicht; jeder Eintrag hat eine Enthüllung (Hinweis, +10 einmalig, Verbündeter/Feind, Schatzort, Preisänderung), nie SP, nie Schaden/Rüstung. Fragen: „Ist es echt?“ (unwahrscheinlich bei Wendung), „Weiß der Verkäufer es?“ (offen).

## Händler: Orakel statt Matrix
- **Hat der Händler genau das?** ist eine Orakelfrage auf der Fate-Chart (Spannung wie in der Szene, Standard 5). Start-Chancen: gewöhnlich **sehr wahrscheinlich** · ungewöhnlich **wahrscheinlich** · selten **unwahrscheinlich** · sehr selten **sehr unwahrscheinlich** · legendär **fast unmöglich**.
- Schritte auf der Leiter: Händlerstufe 1 −1 · 2 und 3 ±0 · 4 +1 · 5 +2; Spezialgebiet +1; Großstadt/Hafen/Markttag +1; Wildnis/Krieg/Belagerung −1; 1 SP = 1 Schritt. **Deckel** (Summe inkl. SP): selten höchstens wahrscheinlich, sehr selten höchstens offen, legendär höchstens unwahrscheinlich. Jede Frage einmal je Händler und Stück; NEIN gilt bis zum nächsten Markttag.
- **JA+** (außergewöhnlich): bessere Prägung (Plunder → normal → gut, Preis folgt); bei Magie kennt der Händler die Herkunft (Wortpaar und eine Frage gratis). **NEIN+**: er bietet Ähnliches an, das nicht stimmt (Fälschung oder Falle, Wendung).
- **Was hat er da?** d6 + Stufe Posten. Je Posten d6 1–4 aus dem Spezialgebiet, sonst Art d20. Seltenheit: d100 auf die Seltenheitstabelle, Stufe 1 zwei Würfe (der gewöhnlichere zählt), Stufe 4 zwei und Stufe 5 drei Würfe (der seltenere zählt). Plunder: gewöhnlicher Posten bei Stufe 1 d6 ≤ 2, Stufe 2 d6 ≤ 1.
- Weitere Orakelfragen für die Spielleitung (`orakel.fragen_gm`): Ist es verflucht? (sehr unwahrscheinlich, bei dunkler Herkunft unwahrscheinlich), Ist es echt? (wahrscheinlich), Ist der Verkäufer ehrlich? (wahrscheinlich).
- Handeln: Sozial-Probe, jeder Erfolgsgrad −10 % Preis (Vorschlag, nicht im JSON).

## Gemma-Nutzung
Die Engine liefert Rahmen (Tabelleneintrag), Wortpaar und vorgeschlagene Fragen; das Modell deutet das Paar und erfindet Namen und eine Zeile Beschreibung, es ändert nie Werte, Preis oder Mechanik. Spielerseitig sichtbar: Name, Seltenheit (soweit offensichtlich), sichtbare Merkmale; Fluch und Wendung bleiben in `hidden`.

## Tabellenumfang
| Tabelle | Einträge |
|---|---|
| Gegenstandslisten (9 Kategorien × 50, d100-Bänder) | 450 |
| Material (9 Gruppen, 124 Einträge, davon 24 Zutaten) | 124 |
| Machart (130), Zustand (125), Besonderheit (115), Herkunft (100); je mit Gruppen-Tags, Tränke- und Tierzusatz | 470 |
| Magische Wirkung (d100) | 100 |
| Segen (d100) | 100 |
| Fluch (d100, GM) | 100 |
| Wendung (d100, GM) | 100 |
| Namen: Epitheton × Bezug (je d100, 10 000 Paare) | 200 |
| Orakelfragen für Gegenstände / Spielleitung | 12 / 5 |

## Roller und Verteilungen
`python3 handout/items/roll.py item -n 5 --selt selten`, `haendler 4 --spez trank --kontext grossstadt`, `hat 3 selten --spez trank --sp 1`, `frage offen`, `stats -n 2000`, `lint`. Ergebnis `stats -n 2000` (2000 Stücke je Seltenheit ohne Tränke; Händler 20000 Posten je Stufe):

```
ungewoehnlich  Prägung % plund  0.0 norma 45.0 gut 29.9 magis  9.7 geseg  5.2 verfl  5.0 wendu  5.2
               magische Stücke 399: KP-Summe {1: 342, 2: 57}, stark (KP>=3) 0 %, Typen {'bonus': 162, 'nutz': 96, 'neuwurf': 54, 'heilung': 34, 'schutz': 25, 'orakel': 22}
               Fluchstufen {1: 49, 2: 52} (1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden)
               Wendungsstufen {1: 54, 2: 49}
selten         Prägung % plund  0.0 norma 19.9 gut 16.1 magis 30.8 geseg 14.6 verfl 13.8 wendu  4.8
               magische Stücke 1185: KP-Summe {1: 427, 2: 758}, stark (KP>=3) 0 %, Typen {'nutz': 422, 'bonus': 318, 'orakel': 173, 'neuwurf': 93, 'schutz': 90, 'heilung': 44}
               Fluchstufen {2: 147, 3: 130} (1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden)
               Wendungsstufen {2: 49, 3: 47}
sehr_selten    Prägung % plund  0.0 norma  8.3 gut  5.2 magis 28.4 geseg 19.2 verfl 20.3 wendu 18.6
               magische Stücke 1357: KP-Summe {2: 625, 3: 732}, stark (KP>=3) 54 %, Typen {'nutz': 577, 'bonus': 242, 'orakel': 233, 'neuwurf': 86, 'schutz': 85, 'heilung': 70}
               Fluchstufen {3: 173, 4: 233} (1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden)
               Wendungsstufen {3: 192, 4: 181}
legendaer      Prägung % plund  0.0 norma  0.0 gut  0.0 magis 28.1 geseg 24.6 verfl 24.1 wendu 23.1
               magische Stücke 1537: KP-Summe {4: 251, 5: 849, 6: 437}, stark (KP>=3) 100 %, Typen {'nutz': 1132, 'orakel': 532, 'bonus': 516, 'schutz': 237, 'neuwurf': 226, 'heilung': 203}
               Fluchstufen {3: 222, 4: 261} (1 Makel, 2 Zehrend, 3 Bösartig, 4 Gebunden)
               Wendungsstufen {3: 228, 4: 235}
Haendler: Seltenheit je Posten in % (20000 Posten je Stufe)
  Stufe 1: plund 27.9 gewoe 55.8 ungew 13.9 selte  2.1 sehr_  0.2 legen  0.0
  Stufe 2: plund 10.2 gewoe 50.3 ungew 24.8 selte  9.9 sehr_  3.7 legen  1.1
  Stufe 3: plund  0.0 gewoe 60.1 ungew 24.8 selte 10.1 sehr_  3.9 legen  1.2
  Stufe 4: plund  0.0 gewoe 35.9 ungew 36.3 selte 17.9 sehr_  7.7 legen  2.2
  Stufe 5: plund  0.0 gewoe 21.4 ungew 40.1 selte 24.5 sehr_ 10.9 legen  3.0
Orakel: Chance auf JA/JA+ (Spannung 5) bei "hat er das?", Stufe x Seltenheit (ohne / mit Spezialgebiet)
   1 ['71/86', '50/71', '14/29', '6/14', '6/6']
   2 ['86/94', '71/86', '29/50', '14/29', '6/14']
   3 ['86/94', '71/86', '29/50', '14/29', '6/14']
   4 ['94/94', '86/94', '50/71', '29/50', '14/29']
   5 ['94/94', '94/94', '71/71', '50/50', '29/29']
Günstigstes magisches Stück: 250 T (25 P), verflucht 125 T (13 P); Budget 20 P = 200 T
Paladin Platte+Schwert+Schild: 140 T = 14 P (Platte+Schwert 10 P)
Waffe/Rüstung Preisstufen (Anteil an d100): {'ruestung 5 T': 10, 'ruestung 10 T': 11, 'ruestung 15 T': 9, 'ruestung 20 T': 25, 'ruestung 40 T': 14, 'ruestung 50 T': 6, 'ruestung 60 T': 13, 'ruestung 70 T': 2, 'ruestung 80 T': 6, 'ruestung 90 T': 2, 'ruestung 100 T': 2, 'waffe 10 T': 21, 'waffe 20 T': 21, 'waffe 40 T': 26, 'waffe 60 T': 22, 'waffe 80 T': 4, 'waffe 100 T': 6}
```

Lesart: Ungewöhnlich: 20 % magisch, nie stark (KP ≤ 2). Selten: nie KP 3. Sehr selten: 56 % der magischen Stücke stark. Legendär: immer zwei Effekte (4–6 KP). Fluchstufen steigen mit der Seltenheit (ungewöhnlich 1–2, selten 2–3, sehr selten und legendär 3–4). Paladin-Check und Startbudget bleiben intakt.

## Fable-Beratung (2026-10-22)
- **Vorab:** Fenster-Tabellen statt je Seltenheit eine Tabelle (ein d100, eine Addition), KP-Budget je Seltenheit, mundane Merkmale nie als Spalten-Kombination, Fluch mit Stufen und Haken, Hunger/Weihe ohne Arbitrage, kein SP-Farming (ein SP-Segen je Figur), Schicksalsergeben nur mit passiven Boni.
- **Review der Entwürfe, umgesetzt:** Gewöhnlich-Wendung-Fenster (Crash), Zweitwurf der legendären Stücke muss andere Art haben, Tränke eigene Preisregel und kein Fluchwurf, Neuwurf/Krit-Schutz-Einträge entschärft („mit dieser Waffe“, Rätsel nur Hinweis), Schwertzahn ohne Gratis-Entwaffnen, mundane Rüstungen mit Magie-Effekt auf +10 zurückgestuft, Fluch 41–58 verstärkt (Zehrend/Bösartig), Pakt mit Verweigerungs-Mechanik statt Tod, Flüche objektneutral, Wendungs-SP gestrichen, Chancen-Deckel für sehr selten/legendär, Fragen einmal je Händler, JA+ definiert.
- **Nicht übernommen:** mehr Seltenheitswürfe auf Stufe 3 bis 5 (hätte die seltenen Posten auf Stufe 3 verdreifacht); Material je Posten statt je Kategoriegruppe (Spielleitung deutet passend, das Handout sagt es).
- **Verdikt:** Struktur und Ablauf schlüssig und schlank; Balance nach den Fixes tragbar (legendär bewusst stark, 1 % der Zufallsstücke, ab 2000 T).

## Offen
- RULES-schicksalsschlag.md (andere Lead): levelbare Story-Waffen (+3 Schaden) brechen die Grenze 5; die Zeile „+1 SP bei jedem Reveal“ kollidiert mit „Wendungen geben keine SP“ (der Strang-Abschluss mit +2 SP reicht).
- Machart-Einträge sind teils waffenlastig („Klinge“); die Spielleitung deutet.
- Handeln (−10 % je Erfolgsgrad) ist nicht im JSON.

## Engine-Port (`/item`, `/haendler`) braucht
- Daten: `handout/items/data/*.json` laden (Top-Level-Schlüssel mergen); `handout/data/items.json` gibt es nicht mehr.
- Roller-Logik portieren: Fenster-Falte (`fold`), Zweitwurf mit anderem `typ`, `passt()` (Schaden/Rüstung nur Waffe/Rüstung), Preisformel (`preis()` mit `preis_mult`, `trank_mult`, Heiltrank-Staffel, `schaedlich`), Materialgruppen (`mat`, `pool()`), Plunder bei Händlern, Seltenheitswürfe je Stufe.
- **Orakel statt Matrix:** `hat_er_das` = bestehender Orakelaufruf mit Start-Chancen `seltenheit[].orakel`, Schritten `haendler.stufen[].orakel` + Spezialgebiet + Kontext, Deckel `seltenheit[].deckel`, SP-Schritt; JA+/NEIN+ mappen auf bessere Prägung bzw. Wendung. Keine eigene Prozenttabelle.
- Item-Ausgabe um `merkmale[]`, `paar[2]`, `fragen[]`, `titel`, `mech[]` (typ, takt, kp), `gm[]` erweitern; Wortpaar und Fragen an Gemma geben (sie deutet, ändert nichts).
- Regeln in den Probenrechner: Item-Boni höchstens +20 je Probe, aktive Item-Fähigkeiten gelten nicht bei Schicksalsergeben, ein SP-Segen je Figur, Hunger (SP zu Sitzungsbeginn) und Klebt als Zustand am Inventar-Eintrag, Weihe-Preis = halber Stufenpreis.
- Preisquelle für `/budget` bleibt `kategorien.json` (`preis_h`); Startgut höchstens 60 T je Stück.
