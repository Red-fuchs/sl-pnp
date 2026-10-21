# Gegenstandsgenerator (Kapitel 11 des Handouts)

Spec und Regeln: `notes/RULES-gegenstaende.md`. Einzige Datenquelle: `data/*.json` (nichts doppelt, auch Fate-Chart und Wortpaare kommen aus `handout/tables.py`, also aus den Orakel-Daten).

```
handout/items/
  data/
    preise.json       Münzen, Preisregel, Seltenheit (d100, Orakel-Chancen, Deckel), Prägung (d20), Alltag
    kategorien.json   9 Kategorien (d20), je 50 Posten mit d100-Bändern, Preise in Heller, genus/kern
    merkmale.json     Material (5 Gruppen à d20), Machart, Zustand, Herkunft, Besonderheit (je d100)
    wirkungen.json    Magische Wirkung d100 (Fenster, kp, takt, typ)
    segen.json        Segen d100
    flueche.json      Fluch d100, nur Spielleitung (stufe 1-4, haken)
    wendungen.json    Wendung d100, nur Spielleitung (stufe 1-4, enthuellung)
    namen.json        Namensgenerator: epitheton x bezug (je d100)
    haendler.json     Händlerstufen (Orakel-Schritt, Seltenheitswürfe, Plunder), Kontext
    orakel.json       Wortpaar-Pools, Orakelfragen für Gegenstände und Spielleitung, Schrittregel
  roll.py             CLI: item, haendler, hat, frage, stats, lint
  pages.py            HTML für Handout-Kapitel 11 (build.py importiert items.pages)
```

Eintragsschema der d100-Tabellen: `{von, bis, text, kp|stufe, takt?, typ?, haken?, enthuellung?}`; `fenster` je Seltenheit (Breite 50, Wurf unter dem Fenster +50, darüber −50), `doppelt: [legendaer]` würfelt zwei Einträge verschiedener `typ`.

```
python3 handout/items/roll.py lint
python3 handout/items/roll.py item -n 5 --selt selten
python3 handout/items/roll.py hat 4 selten --spez trank --sp 1
python3 handout/items/roll.py stats -n 2000
```
