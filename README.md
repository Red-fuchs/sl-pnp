# sl — Solo-RPG-Spielleiter (Swift, lokal)

Lokales MLX-LLM (Gemma-4 E4B Heretic) spielleitet dunkle Fantasy auf Deutsch und nutzt das Orakel `Schicksal` (Swift-Library, echte Zufallsquelle mic -> jitter) direkt im Prozess. CLI + lokale Web-UI. Prompt/Few-Shot = `gm-loop/prompt.py` v3.

## Bauen
```sh
./build.sh          # DEVELOPER_DIR=Xcode noetig (Metal-Shader); schreibt .build/release/sl + mlx-swift_Cmlx.bundle (neben der Binary lassen)
swift test -c release -Xswiftc -enable-testing   # 15 Tests; Grammatik-Tests brauchen den Modellordner (tokenizer), sonst skip
```

## GPU-Slot nur bei geladenem Modell
`./play.sh [web]` startet sl ausserhalb von gpu-run mit `--lease`: sl haelt einen gpu-run-Slot (kleiner Holder-Job unter `gpu-run -n sl|sl-web --ram 10`, Datei `Sources/SLCore/Lease.swift`) nur solange das Modell geladen ist. Nach `--idle` Sekunden (Default 300, `SL_IDLE=…`) werden Gewichte + KV-Cache entladen und der Slot freigegeben; der naechste Zug zeigt "warte auf GPU …", laedt neu und baut den Kontext aus dem gespeicherten Verlauf wieder auf. gpu-run selbst ist unveraendert. Skripte/Tests, die schon in `gpu-run` laufen, rufen `.build/release/sl` ohne `--lease` auf.

## Starten (frueher: ganzer Prozess in der GPU-Queue)
```sh
./play.sh                      # neue Sitzung (gpu-run -n sl --ram 10); Ctrl-D/ /quit beendet und entlaedt
./play.sh --resume [name]      # letzte oder benannte Sitzung
./play.sh --setting "Piratenhafen, Seuche" --model <dir>|lfm --rng mic|jitter|seed:N --temp 0.7 --idle 600 --debug
./play.sh web [--port 8787]    # http://127.0.0.1:8787/ ; 10 min Leerlauf -> Modell entladen, Prozess endet (--resume zum Weiterspielen)
```
`gpu-run` startet den Job im Hintergrund (stdin = /dev/null): `play.sh` reicht die Eingabe deshalb per `--input` durch (tty -> /dev/tty, Pipe -> Temp-Datei). Pipe-Test: `printf 'Zug1\nZug2\n' | ./play.sh --rng jitter`.

Szene 1 beginnt mit dem ersten Spielerzug (das Setting wird dem Modell mitgegeben).

## Weltzustand (prompt v5)
Pro Sitzung `world.json`: Spielfigur (Name, Kurzbeschreibung, Ort, Zustand, Inventar), NPCs (Name, kurz, Ort, Zustand, Inventar, Haltung -2..2), Orte, Beziehungen, Stränge (je begrenzt, <=20 NPCs). Vor jedem Spielerzug steht ein kompakter `[Welt]`-Block (nur Relevantes: Figur, aktueller Ort, anwesende NPCs, wenige andere, offene Stränge) in der User-Nachricht - der System-Prefix bleibt cachebar. Nach jeder Erzählung läuft ein zusätzlicher grammatikbeschränkter Schritt "Weltänderung" (JSON-Delta, darf `{}` sein) auf einem eigenen Wegwerf-Cache; die Harness wendet ihn an (unbekannte Bezüge werden ignoriert, die Spielfigur wird nie NPC). Sync mit Schicksal: neuer NPC -> Liste `akteure`, Strang -> `straenge` (add/bump), NPC-Haltung -> `shift` bei sozialen Orakelfragen. Kosten: ca. 1-2 s pro Zug. Prompt-Quelle: `gm-loop/prompt.py` -> `tools/gen_prompts.py` erzeugt `Sources/SLCore/PromptsGen.swift`.

## Befehle
`/figur [Name:] <Beschreibung>` setzt die Spielfigur (DU, nie NPC) · `/welt` zeigt den Weltzustand.
`/ende` Szene beenden · `/status` · `/frage <text>` (`/frage+2 <text>` feste Quote -3..3) · `/neu [setting]` · `/quit` (Ctrl-D). Alles andere ist ein Spielerzug.
CLI zeigt Werkzeugaufrufe gedimmt (`⚀ ask_oracle: … (wahrscheinlich) → JA+ [mic]`) und Ereignisse (`⚡ akteur_handelt: erpressen + Siegel`); rng/roll/step nur in der UI, nie im Modellkontext.

## Sitzungen
`~/Claude-Workspace/gm-bench/sl-sessions/<name>/`: `state.json` (Schicksal, flock via `state.json.lock`), `chat.json` (Verlauf), `transcript.md`.

## Aufbau
- `SLCore/Grammar.swift`: xgrammar-Structural-Tags je Gate-Zustand (head, head_scene, BIND mit festem Antwort-String, Deutung|verwerfen, 3-5 Satz-Erzaehlung, end_scene->start_scene). Unbegrenzte Wiederholungen mit festem Minimum (Laengenlimits wuerden die Kompilierzeit auf >80 s treiben); Engine-Laengenlimits per `clip`.
- `SLCore/LM.swift`: MLXLLM-Textmodell (kein VLM-Turm), eigene Sample-Schleife mit Grammatikmaske, KV-Cache ueber Zuege (nur das Delta wird prefilled), Matcher-Wiederverwendung per rollback (kein Fork in xgrammar 0.1.30).
- `SLCore/Game.swift`/`Runner.swift`/`Session.swift`, `Format.swift` (fmt_* aus prompt.py), `Prompts.swift` (SYS/FEW v3, Gemma- und ChatML-Template).
- `sl/Web.swift`: NWListener nur 127.0.0.1, SSE, Host-/Origin-Pruefung.
