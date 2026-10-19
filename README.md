# sl — Solo-RPG-Spielleiter (Swift, lokal)

Lokales MLX-LLM (Gemma-4 E4B Heretic) spielleitet dunkle Fantasy auf Deutsch und nutzt das Orakel `Schicksal` (Swift-Library, echte Zufallsquelle mic -> jitter) direkt im Prozess. CLI + lokale Web-UI. Prompt/Few-Shot = `gm-loop/prompt.py` v3.

## Bauen
```sh
./build.sh          # DEVELOPER_DIR=Xcode noetig (Metal-Shader); schreibt .build/release/sl + mlx-swift_Cmlx.bundle (neben der Binary lassen)
swift test -c release -Xswiftc -enable-testing   # 15 Tests; Grammatik-Tests brauchen den Modellordner (tokenizer), sonst skip
```

## Starten (immer ueber die GPU-Queue)
```sh
./play.sh                      # neue Sitzung (gpu-run -n sl --ram 10); Ctrl-D/ /quit beendet und entlaedt
./play.sh --resume [name]      # letzte oder benannte Sitzung
./play.sh --setting "Piratenhafen, Seuche" --model <dir>|lfm --rng mic|jitter|seed:N --temp 0.7 --idle 600 --debug
./play.sh web [--port 8787]    # http://127.0.0.1:8787/ ; 10 min Leerlauf -> Modell entladen, Prozess endet (--resume zum Weiterspielen)
```
`gpu-run` startet den Job im Hintergrund (stdin = /dev/null): `play.sh` reicht die Eingabe deshalb per `--input` durch (tty -> /dev/tty, Pipe -> Temp-Datei). Pipe-Test: `printf 'Zug1\nZug2\n' | ./play.sh --rng jitter`.

Szene 1 beginnt mit dem ersten Spielerzug (das Setting wird dem Modell mitgegeben).

## Befehle
`/ende` Szene beenden · `/status` · `/frage <text>` (`/frage+2 <text>` feste Quote -3..3) · `/neu [setting]` · `/quit` (Ctrl-D). Alles andere ist ein Spielerzug.
CLI zeigt Werkzeugaufrufe gedimmt (`⚀ ask_oracle: … (wahrscheinlich) → JA+ [mic]`) und Ereignisse (`⚡ akteur_handelt: erpressen + Siegel`); rng/roll/step nur in der UI, nie im Modellkontext.

## Sitzungen
`~/Claude-Workspace/gm-bench/sl-sessions/<name>/`: `state.json` (Schicksal, flock via `state.json.lock`), `chat.json` (Verlauf), `transcript.md`.

## Aufbau
- `SLCore/Grammar.swift`: xgrammar-Structural-Tags je Gate-Zustand (head, head_scene, BIND mit festem Antwort-String, Deutung|verwerfen, 3-5 Satz-Erzaehlung, end_scene->start_scene). Unbegrenzte Wiederholungen mit festem Minimum (Laengenlimits wuerden die Kompilierzeit auf >80 s treiben); Engine-Laengenlimits per `clip`.
- `SLCore/LM.swift`: MLXLLM-Textmodell (kein VLM-Turm), eigene Sample-Schleife mit Grammatikmaske, KV-Cache ueber Zuege (nur das Delta wird prefilled), Matcher-Wiederverwendung per rollback (kein Fork in xgrammar 0.1.30).
- `SLCore/Game.swift`/`Runner.swift`/`Session.swift`, `Format.swift` (fmt_* aus prompt.py), `Prompts.swift` (SYS/FEW v3, Gemma- und ChatML-Template).
- `sl/Web.swift`: NWListener nur 127.0.0.1, SSE, Host-/Origin-Pruefung.
