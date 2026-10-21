# -*- coding: utf-8 -*-
"""Single source for the one-shot "Fadenleihe" (Die Weberin): world seed (worlds/weberin/), GM PDF, Foundry journals."""

TITLE = "Fadenleihe"
SETTING = ("Die Gramsmark, dunkles Moor-Grenzland, in dem Schicksal ein Handwerk ist: im Spindelhaus setzt der Spindelmeister jedem Bewohner mit der Nadel seinen Faden. "
           "Fremde aus anderen Welten, von der Weberin für einen Mondlauf an Leihfäden gezogen, sollen die Nadel holen und dürfen das Schicksal nicht auf sich aufmerksam machen.")

ORTE = {
  "Aschekreis": ("Verfallene Walkmühle am Moorsaum, ein Kreis aus Asche und alten Fäden. Hier erwachen die Gerufenen.", "die Weberin"),
  "Krähenfurt": ("Einzige Stadt der Mark: Flussmarkt, Fachwerk, Tore, die nachts schließen.", "Vogtin Agnet Rauhsohl"),
  "Spindelhaus": ("Turm im Flussbogen, in dem Fäden gesetzt werden; ein Kanal führt unter das Fundament.", "Spindelmeister Ambros Fehling"),
  "Fadenbruch": ("Schlucht, in der das Gewirk als Nebel sichtbar hängt. Eine Webstelle.", "niemand, der Kettler geht hier um"),
}

# id, name, kurz, ort, haltung, wunden, anwesend, gm_figur
NPCS = [
  ("n1", "Die Weberin", "Auftraggeberin, gesichtslose Frau aus Garn", "Aschekreis", 1, 12, True, False),
  ("n2", "Der Kater", "sprechender Kater, Begleiter", "Aschekreis", 2, 4, True, True),
  ("n3", "Der Kettler", "Schicksalsbote, Mann mit Nähnadeln statt Fingern", "Fadenbruch", -2, 14, False, False),
  ("n4", "Ambros Fehling", "Spindelmeister, müde und pedantisch", "Spindelhaus", -1, 6, False, False),
  ("n5", "Agnet Rauhsohl", "Vogtin von Krähenfurt, kühl und geschäftstüchtig", "Krähenfurt", 0, 6, False, False),
  ("n6", "Wenke Sparr", "Garnhändlerin, einst Dienerin der Weberin", "Krähenfurt", 2, 6, False, False),
  ("n7", "Jorrit Keil", "Schmuggler am Flusskanal", "Krähenfurt", -1, 6, False, False),
]

# name -> (geheimnis, ziel, gruppe, typ, ref)   (geheimnis text <= ~100 chars, no minors)
HIDDEN = {
  "Die Weberin": ("Sie ist der abgetrennte Teil des Schicksals und will sich mit der Nadel wieder einweben, als Herrin über alle Fäden.", "die Nadel bekommen", "Weberin", "npc_befragt", "Wenke Sparr"),
  "Der Kater": ("Er war der letzte Gerufene: die Weberin knotete ihn zum Kater und verwahrt seinen Namen als Pfand.", "heimkehren, den Namen zurückbekommen", "Weberin", "gegenstand", "Nadel"),
  "Der Kettler": ("Er kann Fremde nicht sehen, nur ihre Wirkung, und näht jede Abweichung fest, auch die der Figuren.", "Fremde ausnähen, das Gewirk flicken", "Schicksal", "ort_betreten", "Fadenbruch"),
  "Ambros Fehling": ("Er setzt seit Jahren Fäden nach den Bestellungen der Vogtin: Gehorsam statt Lebenslauf.", "die Nadel schützen, seine Ruhe haben", "Spindelhaus", "gegenstand", "Fadenbuch"),
  "Agnet Rauhsohl": ("Sie hat frühere Gerufene an Fehling verkauft; ihre Fäden hängen im Spindelhaus.", "Macht behalten, Fremde als Hebel nutzen", "Vogtei", "npc_befragt", "Ambros Fehling"),
  "Wenke Sparr": ("Sie weiß, dass die Weberin sich als Herrin über alle Fäden wieder einweben will.", "die Weberin aufhalten, ohne selbst zu sterben", "Weberin", "npc_befragt", "Wenke Sparr"),
  "Jorrit Keil": ("Er kennt den Kanal ins Spindelhaus und hat dort die Gruft früherer Gerufener gesehen.", "Taler verdienen, dem Höchstbietenden folgen", "Schmuggler", "zeit", "14"),
}

STRAENGE = [
  ("Was ist die Nadel wirklich", [
     ("Das Fadenbuch nennt die Nadel: Knochen, nicht Eisen", "Spindelhaus"),
     ("Die Weberin brach sie sich selbst aus dem Leib", "Wenke Sparr"),
     ("Im Nebel reißt sich eine Frau einen Knochen aus der Hand", "Fadenbruch")]),
  ("Warum braucht die Weberin Fremde", [
     ("Wer von hier die Nadel fasst, reißt seinen eigenen Faden", "Der Kettler"),
     ("Im Kanal liegen Tote in fremder Kleidung, ihre Fäden abgeschnitten", "Jorrit Keil"),
     ("Die Asche im Kreis besteht aus Garn früherer Gerufener", "Aschekreis")]),
  ("Wem gehört Krähenfurt wirklich", [
     ("Fehlings Aufträge tragen das Siegel der Vogtin", "Spindelhaus"),
     ("Auf dem Markt widerspricht niemand der Vogtin, seit Jahren nicht", "Krähenfurt"),
     ("Fehling näht, was Rauhsohl bestellt", "Jorrit Keil")]),
]

START_SZENE = ("Du erwachst im Aschekreis am Moorsaum, kalte Asche unter den Fingern, ein feines Garn um das Handgelenk, und in der Hand hältst du noch, was du im Augenblick des Zugriffs gehalten hast. "
               "Neben dir kommen andere zu sich, Fremde wie du, und am Rand des Kreises sitzt ein Kater mit einem Faden um den Hals und wartet.")
PC_ZIEL = "Überlebe die Nacht und finde den Weg zurück nach Hause."
MOTIVE = ["loses Garn in der Luft", "Asche, die nicht kalt wird", "Hunde, die Fremde anheulen"]

PROMPT = """Setting: die Gramsmark, dunkles Grenzland, in dem Schicksal ein Handwerk ist. Die Spieler sind Fremde aus anderen Welten, von der Weberin für einen Mondlauf an Leihfäden gezogen. Sie haben keinen eigenen Faden im Gewirk und dürfen das Schicksal nicht auf sich aufmerksam machen. Es gibt keine Starttaverne: die Szene beginnt im Aschekreis, die Figuren treffen sich dort. Die Weberin gibt den Auftrag: Holt die Nadel aus dem Spindelhaus und bringt sie in den Aschekreis, bevor der Mond hinter die Zinne sinkt; danach löse ich die Leihe. Sie verschweigt, was die Nadel für sie bedeutet.
Die Spannung heißt hier "Blick des Schicksals". Stufen: 1-3 unbemerkt; 4-6 Fäden zittern (Zufälle, Blicke, kleine Unstimmigkeiten); 7-8 Schicksalsboten suchen (Genähte fragen nach Fremden, NPCs werden misstrauischer); 9 Eingriff (ein Regie-Hinweis sagt dann, was geschieht). Nenne den Wert nie, zeige nur Zeichen.
Fremdkraft: jede Figur hat höchstens eine übernatürliche Fähigkeit aus ihrer Heimatwelt (Merkmal "Fremdkraft: ..."). Sie wirkt, ist aber nie automatisch, nie dauerhaft und nie ein Sofort-Sieg. Jeder Einsatz zieht den Blick des Schicksals an; erzähle dann, dass die Fäden zittern. Technik aus der Heimatwelt funktioniert seltsam und nie unsichtbar.
Der Kater ist der Begleiter der Gruppe und wird von der Spielleitung gespielt: erfinde nie seine Worte, Taten oder Wahrnehmungen. Er nimmt nur wahr, was die Figuren wahrnehmen, und bemerkt nie verborgene Dinge von sich aus. NPCs reagieren auf ihn nur, wenn er laut gesprochen oder gehandelt hat.
Ton: dark fantasy, knapp, körperlich. Wiederkehrende Bilder: Garn, Asche, Nebel, Nähte. Das Schicksal ist Ordnung ohne Mitleid, die Weberin Hoffnung ohne Garantie, niemand ist nur gut. Fremde werden gespürt, nicht erkannt: Hunde und alte Frauen reagieren zuerst. Rituale der Weberin sind leises Knoten, keine Zauberei. Kinder und Jugendliche sind nie Opfer."""

STUFEN = [
  "Der Blick des Schicksals ist gering: die Fremden gehen als Fremde unter vielen durch. Erzähle ruhig und unaufgeregt.",
  "Die Fäden zittern: lass kleine Unstimmigkeiten geschehen (Münzen fallen falsch, Hunde heulen, ein Blick bleibt an den Fremden hängen), ohne zu erklären. Nenne den Wert nie.",
  "Schicksalsboten suchen die Fremden: Genähte mit zugenähten Lippen fragen nach Fremden, NPCs werden misstrauischer, der Kettler ist nur eine Szene entfernt. Erzähle dichter und bedrohlicher.",
]
EINGRIFF = ("Das Schicksal hat die Fremden gefunden. Lass es in dieser Szene zugreifen, konkret und körperlich, ohne Erklärung: der Kettler mit den Nadelfingern tritt ein und sticht einer Figur die Fremdkraft an, "
            "oder ein helfender Faden reißt (ein Verbündeter stirbt oder vergisst die Figuren), oder eine Figur steht ihrer eigenen Entsprechung aus der Mark gegenüber. Danach wird die Welt still, aber teurer: die Uhr ist eine Stufe weiter. Nenne die Spannung nicht.")
FREMD_CUE = "Die Fäden zittern: eine Fremdkraft wurde benutzt. Lass es spürbar werden (ein loser Faden, ein Hundeheulen, ein Blick aus dem Nichts), ohne den Begriff Fremdkraft oder den Wert zu nennen."
AUFTAKT = START_SZENE + " Die Weberin tritt erst auf, wenn die Figuren sich gefunden haben."
