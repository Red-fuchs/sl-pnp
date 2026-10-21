# Schicksalsschlag: Gegenstände und Händler (Vorschlag v0.1, 2026-10-22)

Gegenstandsgenerator in vier Würfen plus Händler-Verfügbarkeit. Alle Zahlen sind **Vorschlag**, bis der Spielleiter sie freigibt. Einzige Datenquelle: `handout/data/items.json` (PDF, `handout/items_roll.py`, später Engine `/item`, `/haendler`). Handout-Kapitel 11 druckt dieselben Tabellen.

## Währung
- 1 **Taler (T)** = 2 **Schilling (S)** = 4 **Heller (H)**. 1 S = 2 H. Kurzschrift „3 T 1 S 1 H“ = 3¾ Taler.
- Engine und JSON rechnen **nur in Heller** (ganze Zahl, Feld `preis_h`), Anzeige als T/S/H (`fmt()` in items_roll.py).
- **10 Taler = 40 Heller = 1 Budgetpunkt** (Figurenerschaffung). Posten unter 10 T zählen 0 Punkte und werden in Taler bezahlt.
- Alltag (Vorschlag): Laib Brot / Krug Bier 1 H, Mahlzeit / Schlafsaal 2 H, Einzelzimmer 4 H (1 T), Tagelohn Handlanger 1 T, Geselle/Söldner 2 T. Schwert 40 T = 40 Tagelöhne.

## Der Gegenstand in 4 Würfen
1. **Art** (d20 → Kategorie, dann d10 → Gegenstand, mit Basispreis und Werten). Kategorien: Waffe 1–3, Rüstung/Schild 4–5, Werkzeug 6–8, Trank/Tinktur 9–12, Kleidung 13, Schmuck 14–15, Schriftstück 16, Kuriosum 17–18, Reittier/Transport 19–20. Proviant und Alltagsware haben keine Würfe, sie stehen als feste Preisliste (`alltag`).
2. **Seltenheit** (d100; nur bei Zufallsgegenständen, sonst gesetzt): 01–60 gewöhnlich ×1 · 61–85 ungewöhnlich ×2 · 86–95 selten ×5 · 96–99 sehr selten ×10 · 100 legendär ×20.
3. **Prägung** (d20, Spalte = Seltenheit, je seltener, desto besonderer):

| Prägung (Preis ×) | gewöhnlich | ungewöhnlich | selten | sehr selten | legendär |
|---|---|---|---|---|---|
| Plunder (¼) | 1–2 | – | – | – | – |
| normal (1) | 3–15 | 1–9 | 1–4 | 1–2 | – |
| gut gearbeitet (1½) | 16–19 | 10–15 | 5–7 | 3 | – |
| magisch (+Stufenpreis) | – | 16–17 | 8–13 | 4–8 | 1–5 |
| gesegnet (+Stufenpreis) | – | 18 | 14–16 | 9–12 | 6–10 |
| verflucht (½ Stufenpreis) | – | 19 | 17–19 | 13–16 | 11–15 |
| Wendung (Basis × Seltenheit) | 20 | 20 | 20 | 17–20 | 16–20 |

4. **Wirkung** (nur magisch / gesegnet / verflucht): **W6 + Bonus der Seltenheit**: ungewöhnlich W6 (1–6), selten W6+2 (3–8), sehr selten W6+4 (5–10), legendär W6+6 (7–12). Je seltener, desto stärker und desto höher der Mindestwurf (legendär ist mindestens „Kraft“). Tabellen *magisch* und *gesegnet* in items.json / Handout. Ein Würfel, eine Addition.
   - **verflucht** = Wirkung aus Tabelle *magisch* (immer ein Vorteil) **plus** verborgener Fluch (W6 bei ungewöhnlich/selten, W8 darüber). Jeder verfluchte Gegenstand **klebt**: er lässt sich nicht ablegen oder verkaufen, bis der Fluch gelöst ist (Weihe, Segen, Handlungsstrang abschließen). Der Fluch ist nur für die Spielleitung; Entdeckung: Wissen-Probe schwer oder beim Zuschlagen.
   - **Wendung**: W8 Geheimnis (Fälschung = in Wahrheit Plunder, gestohlen, berühmter Vorbesitzer, Geheimfach, erwacht, Schnäppchen = zusätzlich Wirkung W6, Erbstück, Beweisstück). Nur Spielleitung, Preis wie angeboten (Basis × Seltenheit).
   - **Plunder**: Schaden/Rüstung −1, Werkzeug/Tränke wirken halb, zerbricht bei kritischem Misserfolg.
   - **gut gearbeitet**: je Kategorie eine kleine Regel (Spalte `gut`), z. B. Waffe: kritischer Erfolg +1 Schaden; Werkzeug +10.
   - Tränke sind Verbrauchsgüter: magisch/gesegnet = Wirkung doppelt (Heilung höchstens 6 LP); verflucht = Wirkung plus Nebenwirkung bis zur Nachtruhe; Wendung zählt als gut.
   - Kampf-Ergebnisse (+1 Schaden / +1 Rüstung) gelten nur für Waffe und Rüstung/Schild, sonst +20 in der passenden Situation. **Grenzen: Schaden 5, Rüstung 3** (darüber stattdessen +10 auf die Verteidigung).
   - **Vergiftet:** −10 auf alle Proben und 1 LP Verlust je Szene, bis Gegengift oder Nachtruhe.

## Preis und Budget
- **Gewöhnlich, gut, Plunder: Preis = Basis × Prägung** (¼ / 1 / 1½). Die Seltenheit macht diese Stücke nur schwerer zu finden (Händler-Matrix), nicht teurer. **Wendung:** Basis × Seltenheit (so wird es angeboten).
- **Magisch oder gesegnet: Preis = Stufenpreis + Basis**; verflucht die Hälfte davon. Stufenpreis: ungewöhnlich 250 T · selten 500 T · sehr selten 1000 T · legendär 2000 T. Ab 10 T auf 5 T gerundet. Magie ist damit nie mit den 200 T (20 Punkte) der Figurenerschaffung zu bezahlen; ein verfluchtes ungewöhnliches Stück (≈125 T, 13 P) geht nur mit schweren Nachteilen.
- **Budgetpunkte:** Preis ÷ 10 T, aufgerundet (ein Stück für 15 T zählt 2 Punkte). Posten unter 10 T zählen 0 Punkte und werden in Taler bezahlt. items.json ist damit die Preisquelle für `/budget`; die Stichwort-Tarife 2/4/6 gelten weiter als Obergrenze für Startausrüstung.
- Normale Ausrüstung bleibt auf den Vorschlag-Tarifen: Messer/Knüppel/Leder 20 T (2 P) · Schwert/Axt/Bogen/Kette/Schild 40 T (4 P) · Platte/Feuerwaffe 60 T (6 P). **Paladin:** Platte 60 + Schwert 40 + Schild 40 = 140 T = 14 P (Platte + Schwert = 10 P) passt zum Beispiel aus RULES-schicksalsschlag.md.

## Händler
- **Stufe 1–5:** 1 Straßenbrauer/Hausierer · 2 Dorfkrämer · 3 Stadthändler · 4 Meister (Alchemist, Schmied) · 5 Hofmagier/Schatzkammer.
- **Effektive Stufe** = Stufe + Spezialgebiet (+1 für Posten der eigenen Kategorie) + Kontext (Großstadt/Hafen/Markttag +1, Wildnis/Krieg/Belagerung −1), begrenzt auf 1–5.
- **Hat er genau das?** (Spieler fragt nach einem Stück) d100 ≤ Wert in der Matrix (Stufe × Seltenheit):

| Stufe | gewöhnlich | ungewöhnlich | selten | sehr selten | legendär |
|---|---|---|---|---|---|
| 1 | 70 | 10 | 1 | 0 | 0 |
| 2 | 90 | 30 | 5 | 0 | 0 |
| 3 | 95 | 55 | 15 | 2 | 0 |
| 4 | 95 | 75 | 35 | 10 | 1 |
| 5 | 95 | 90 | 60 | 30 | 10 |

- **Was hat er da?** d6 + Stufe Posten. Je Posten: Kategorie (d6 1–4: aus dem Spezialgebiet, sonst Art-Wurf d20), Seltenheit aus der Inventar-Tabelle (d100) der effektiven Stufe, dann Prägung/Wirkung wie oben. „Plunder“ = gewöhnlich mit Prägung Plunder.

| Stufe | Plunder | gewöhnlich | ungewöhnlich | selten | sehr selten | legendär |
|---|---|---|---|---|---|---|
| 1 | 25 | 65 | 9 | 1 | – | – |
| 2 | 10 | 70 | 17 | 3 | – | – |
| 3 | 3 | 62 | 27 | 7 | 1 | – |
| 4 | – | 45 | 33 | 16 | 5 | 1 |
| 5 | – | 25 | 35 | 25 | 12 | 3 |

- Preis beim Händler = Preis wie oben. Handeln: Sozial-Probe, jeder Erfolgsgrad (DoS) −10 % (Vorschlag, noch nicht im JSON).

## Gemma-Nutzung
Alle Tabellen sind kurz und enum-basiert; die Zahlen kommen aus der Engine (`roll_item`), das Modell erfindet nur **Namen und eine Zeile Beschreibung** und darf Werte, Preis und Wirkung nicht ändern. Spielerseitig nur sichtbar: Name, Seltenheit (soweit offensichtlich), sichtbare Prägung; Fluch/Wendung bleiben in `hidden`.

## Schema `handout/data/items.json`
- `muenzen` (heller_pro_taler/schilling/punkt), `preis_regel`, `alltag[] {name, preis_h}`.
- `seltenheit[] {id, name, d100[von,bis], mult, wirkungswuerfel, magie_min_h}`.
- `praegung[] {id, name, mult, text}`; `praegung_d20 {reihenfolge[], anzahl{seltenheit: [n je Prägung]}}` (Anzahl von 20, in Reihenfolge zu Bereichen kumulieren).
- `kategorien[] {id, name, d20[von,bis], verbrauch, gut, items[10] {name, preis_h, schaden?, ruestung?, effekt?, min?}}` (`min` = Mindestseltenheit des Postens).
- `wirkung {magisch[], gesegnet[] {von,bis,text}, fluch {wuerfel{seltenheit:n}, tabelle[]}, wendung {tabelle[]}}`.
- `haendler {anzahl, spezial_stufe, spezial_d6, stufen[] {stufe, beispiel, verfuegbar{seltenheit:%}, inventar{plunder|seltenheit:%}}, kontext[] {id, name, shift}}`.
- Gegenstand zur Laufzeit (Roller-Ausgabe): `{kat, name, seltenheit, praegung, basis_h, preis_h, punkte, schaden, ruestung, effekt, wirkung, gm[]}`; `gm` ist verborgen.

## Roller und Verteilungen
`python3 handout/items_roll.py item -n 5 [--selt selten --kat trank]`, `haendler 4 --spez trank --kontext grossstadt`, `hat 3 selten --spez trank --kat trank`, `stats -n 1000`. Ergebnis `stats -n 2000` (Anteile in % je Posten, Heller → T S H):

```
Stufe 1: 4.5 Posten, Ø Preis 33 T 1 S 1 H, max 620 T
  Seltenheit %: plund  31.6 gewoe  57.3 ungew   9.9 selte   1.2 sehr_   0.0 legen   0.0
  Prägung %:    plund  31.6 norma  45.7 gut  17.2 magis   1.3 geseg   0.7 verfl   0.7 wendu   2.8
Stufe 2: 5.5 Posten, Ø Preis 46 T 1 S, max 700 T
  Seltenheit %: plund  16.8 gewoe  62.6 ungew  17.4 selte   3.1 sehr_   0.0 legen   0.0
  Prägung %:    plund  16.8 norma  53.2 gut  20.8 magis   2.8 geseg   1.3 verfl   1.4 wendu   3.7
Stufe 3: 6.5 Posten, Ø Preis 72 T, max 1080 T
  Seltenheit %: plund   9.2 gewoe  54.2 ungew  28.3 selte   7.3 sehr_   1.0 legen   0.0
  Prägung %:    plund   9.2 norma  53.7 gut  22.1 magis   5.6 geseg   2.7 verfl   2.6 wendu   4.1
Stufe 4: 7.5 Posten, Ø Preis 135 T 1 H, max 2200 T
  Seltenheit %: plund   4.3 gewoe  39.7 ungew  33.6 selte  16.3 sehr_   5.0 legen   1.1
  Prägung %:    plund   4.3 norma  47.5 gut  23.3 magis   9.7 geseg   5.3 verfl   5.3 wendu   4.6
Stufe 5: 8.6 Posten, Ø Preis 230 T, max 4000 T
  Seltenheit %: plund   2.5 gewoe  22.1 ungew  35.1 selte  24.9 sehr_  12.4 legen   3.0
  Prägung %:    plund   2.5 norma  38.2 gut  21.2 magis  14.9 geseg   8.7 verfl   8.5 wendu   6.1
Per Seltenheit (zufällig, 20000 Stück): Prägung % und Ø Preis
  gewoehnlich    Ø 32 T 1 S 1 H  plund  9.8 norma 64.7 gut 21.0 magis  0.2 geseg  0.1 verfl  0.1 wendu  4.0
  ungewoehnlich  Ø         80 T  plund  0.0 norma 45.4 gut 30.9 magis  9.9 geseg  5.0 verfl  4.9 wendu  3.9
  selten         Ø        296 T  plund  0.0 norma 20.6 gut 15.9 magis 29.6 geseg 14.8 verfl 15.1 wendu  4.0
  sehr_selten    Ø    625 T 1 S  plund  0.0 norma  9.7 gut  9.4 magis 24.7 geseg 19.7 verfl 20.6 wendu 15.9
  legendaer      Ø   1399 T 1 H  plund  0.0 norma  0.0 gut  5.0 magis 25.0 geseg 24.4 verfl 25.0 wendu 20.5
Günstigstes magisches Stück: 250 T (25 P), verflucht 125 T (13 P); Budget 20 P = 200 T
Paladin Platte+Schwert+Schild: 140 T = 14 P (Platte+Schwert 10 P)
Gefragter Gegenstand, Chance in % (Stufe x Seltenheit, ohne Spezial / mit Spezial):
   1 ['70/90', '10/30', '1/5', '0/0', '0/0']
   2 ['90/95', '30/55', '5/15', '0/2', '0/0']
   3 ['95/95', '55/75', '15/35', '2/10', '0/1']
   4 ['95/95', '75/90', '35/60', '10/30', '1/10']
   5 ['95/95', '90/90', '60/60', '30/30', '10/10']
```

## Fable-Review (2026-10-22), Ergebnis und Umsetzung
Verdikt: Rechnung und Tarife (20/40/60 T, Paladin 14 P) stimmen; Hauptkritik war Preislogik und Balance. Übernommen:
- Seltenheit verteuert nur Magie (Stufenpreis + Basis statt Basis × Seltenheit × 3); normale Stücke kosten Basis × Prägung. Rundungsfehler im Roller (Banker's rounding) behoben.
- Wirkung W6 + Bonus statt festem W6/W8/W10/W12 (legendär ist mindestens „Kraft“). Gefahrensinn/Warnung nur einmal pro Sitzung; Ruhe und Segen zusammengelegt.
- Verflucht nicht mehr reiner Gewinn: Fluch „Klebt“ gilt immer, neuer Fluch „Hunger“ (1 SP je Sitzung).
- Proviant ist eine feste Preisliste (kein Würfelwurf, kein Budget-SP-Gewinn); Tränke ohne Wendung; Grenzen Schaden 5, Rüstung 3; Vergiftung definiert; Doppelungen (Schilde, Branntwein/Schnaps, Schlagring) bereinigt; Wendung 1/6 repariert; Magie bei ungewöhnlich nur 20 %.
- Roller prüft Eingaben.
## Offen
- RULES-schicksalsschlag.md: levelbare Story-Waffen (+3 Schaden) brechen die Schadensgrenze 5 (Grenze dort ergänzen); Budget-Zeile (Stichwort-Tarife 2/4/6) auf items.json als Preisquelle abstimmen.
- Handeln (Sozial-Probe, −10 % je Erfolgsgrad) ist nur Vorschlag und nicht im JSON.
- Engine: `/item`, `/haendler`, `world.json`-Inventar, Foundry-Händlerkarten (siehe Übergabe im Bericht).
