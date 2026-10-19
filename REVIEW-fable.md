# Review sl (read-only, Fable) — Stand 2026-10-19

Geprüft gegen: gm-loop/prompt.py v3, gm2.py + stress-Befunde, stress/lib.py (Chat/Template), Schicksal-Engine (~/Projects/schicksal), mlx-swift-lm 3.32.3 (Checkout in .build), Heretic-Modellordner (config.json, tokenizer, chat_template.jinja). Nicht gebaut, kein Modell geladen.

Was stimmt (verifiziert, kein Handlungsbedarf):
- Mixed 4/6-bit: alle 347 Module mit `.scales` im Index stehen 1:1 in `config.quantization`; `BaseConfiguration.QuantizationContainer` überspringt `mode`, dekodiert pro Layer `{group_size,bits}`; `loadWeights` quantisiert nur Module mit vorhandenen scales (Load.swift:389). Default gs32/4bit greift nirgends falsch.
- Template: `Tmpl.gemma` = `<bos><|turn>system\n…<turn|>\n<|turn>user\n…<turn|>\n<|turn>model\n` entspricht exakt dem Stock-Gemma-4-Template (lmstudio-community/…/chat_template.jinja: system-Turn, Gen-Prompt ohne `<|channel>thought`), das der Python-Harness für heretic erzwungen hat (stress/lib.py:60). Heretic-Template (Datum-Prefix, thinking=true) wird korrekt umgangen.
- EOS: `<turn|>`=106 als Grammar-EOS und Stop; `<eos>`=1 und `<|tool_response>`=50 zusätzlich im Stop-Set, werden von der Maske ohnehin nie freigegeben. Entspricht gm.py:94.
- Gate-Zustände: head / head_scene (nur start_scene) / BIND mit fixem Antwort-String aus dem echten Orakelergebnis / EVH (Deutung oder "verwerfen") / NARR 3–5 Sätze / ask nur bei offener Szene und <6 Fragen / first:true wird vom Harness nur bei `scene==0` injiziert (Engine.swift:175 erzwingt dann "erwartet"). q wird aus der Frage-Zeile übernommen.
- fmtResult/fmtEvent/fmtKnown = prompt.py 1:1 (Tests decken es ab); rng/roll/step gelangen über diesen Pfad nicht ins Modell.
- Web: Listener auf 127.0.0.1 (Web.swift:68), kein Dateisystemzugriff → kein Path-Traversal, eine Generierung zur Zeit (busy-Flag), Idle-Unload 600 s.
- play.sh nutzt gpu-run mit Label + `--ram` (Default 10 GB), Unload bei Ctrl-D / Idle.

---

## BLOCKER

### B1 — KV-Cache verliert das letzte Token jedes grammatik-terminierten Turns
`Sources/SLCore/LM.swift:103-108`

```swift
let r = try con.commitToken(Int32(tok))
…
if r.isTerminated { break }          // ← bricht ab, BEVOR das Token in den Cache geht
let o = ctx.model(LMInput.Text(tokens: MLXArray([Int32(tok)])) …, cache: cache, …)
```

Bei jedem Tool-Call (`…}</ask_oracle>`, `</start_scene>`, `</end_scene>`) und bei 5-Satz-Erzählungen terminiert die Grammatik auf dem letzten Token. Dieses Token wird gesampelt, in `out` übernommen, aber nie durch das Modell geschickt. Der Cache enthält danach `…</ask_oracle` + `<turn|>\n<|turn>user…`, die Historie (`msgs`) sagt `…</ask_oracle>`. Prefix ≠ gerenderte Historie, bei jedem Tool-Turn, kumulativ über die Sitzung. Nach `syncCache()` (Resume/Compact/Fehler) ist der Kontext dann plötzlich anders als während des Spiels. `cached` zählt ebenfalls eins zu wenig.

Fix (ein zusätzlicher Forward pro Turn, ~30 ms):
```swift
let r = try con.commitToken(Int32(tok))
det.append(token: tok)
if let s = det.next() { out += s; onDelta(s) }
n += 1
let o = ctx.model(LMInput.Text(tokens: MLXArray([Int32(tok)]))[text: .newAxis], cache: cache, state: nil)
cached += 1
logits = o.logits
if r.isTerminated { eval(logits); break }
asyncEval(logits)
```
(Alternative — Token-Text an `pending` hängen statt feeden — ist wegen BPE-Grenze zu `<turn|>` nicht sicher.)

### B2 — Modell wird über den VLM-Pfad geladen (Audio+Vision-Tower bf16 mit im RAM)
`Sources/SLCore/LM.swift:46` (`loadModel(from:using:)`) + `Package.swift:16` (MLXVLM)

`ModelFactoryRegistry` probiert zuerst `MLXVLM.TrampolineModelFactory`, dann LLM (ModelFactory.swift:489-499). Da MLXVLM gelinkt ist und `model_type: gemma4` dort registriert ist (VLMModelFactory.swift:99), lädt sl `Gemma4ForConditionalGeneration` komplett: audio_tower + vision_tower (unquantisiert, bf16, ClippedLinear-Statistiken inkl.) ≈ +2 GB RAM, längerer Load, Gemma4Processor. Nur wenn der VLM-Load wirft, fällt es stumm auf MLXLLM zurück — man sieht nicht, welcher Pfad lief. Für ein Text-only-Spiel unnötig, und `--ram 10` in play.sh wurde vermutlich ohne Tower kalkuliert.

Fix: explizit Text-Factory, MLXVLM aus Package.swift entfernen:
```swift
let c = try await LLMModelFactory.shared.load(from: dir, using: TokLoader())   // MLXLLM, sanitize wirft Tower-Gewichte weg (Gemma4.swift:67-101)
```
Bleibt MLXVLM absichtlich (Zukunft: Bilder), dann wenigstens `LLMModelFactory.shared` aufrufen und `--ram` entsprechend setzen.

---

## SHOULD

### S1 — `/frage` schiebt rohes JSON (rng, roll, p, step) in den Modellkontext
`Sources/SLCore/Runner.swift:81`
```swift
try run { try game.turn("Ich frage das Schicksal: \(q)\n[Orakel] \(r.json)", pre: r) }
```
Verstößt gegen prompt.py ("kein JSON, keine rng/step/roll-Zahlen für das Modell") und gegen die Regel "rng-Labels nur in der UI". Das Few-Shot-Format wird gebrochen, der Modell-Turn sieht `[Orakel] {"answer":"JA","event":null,"p":71,"rng":"mic","roll":88,…}`.
Fix:
```swift
var fb = fmtResult("ask_oracle", r)
if evInfo("ask_oracle", r) != nil, !(game.eng.st.akteure.isEmpty && game.eng.st.straenge.isEmpty) { fb += "\n" + fmtKnown(…) }
try run { try game.turn("Ich frage das Schicksal: \(q)\n" + fb, pre: r) }
```

### S2 — Nach end_scene ist Erzählung statt start_scene erlaubt
`Sources/SLCore/Grammar.swift:68`
```swift
else { parts.append(.or([narr, startScene])) }   // after end_scene: narrate or open the next scene
```
Spec/Stress-Befund: nach end_scene nur start_scene. Mit `narr` kann der Zug ohne offene Szene enden; der nächste Spielerzug landet dann in head_scene und erzwingt start_scene erst dort — tolerierbar, aber abweichend, und bei `/ende` ("Die Szene ist hier zu Ende.") hat das Modell für ein sofortiges start_scene gar keine Information. Vorschlag: `narr` nur bei `forceEnd`-Turns zulassen (Gate-Flag durchreichen), sonst nur `startScene`. Testfall in `testStateMachine` (g2) entsprechend verschärfen.

### S3 — Schema-Längen aus tools.json fehlen → Engine-Fehler statt Grammatik-Schranke
`Sources/SLCore/Grammar.swift:44` (`str = {"type":"string"}`)
Die Engine validiert `maxLength` (Schema.swift:30-31): q 200, expect 300, el.* 80, summary 400, why 120. Die Grammatik ist unbeschränkt; überschreitet das Modell die Länge, kommt `[Orakel] Fehler: args.el.ort: max 80 Zeichen` und ein Head-Retry. gm2.py hatte die Schemas aus tools.json inkl. maxLength in der Lark-Grammatik. xgrammar unterstützt `maxLength` für Strings (json_schema_converter.cc:3183).
Fix: pro Feld eigenes Schema, z. B. `.js(#"{"type":"string","maxLength":80}"#)` für ort/beteiligte, 300 expect, 400 summary, 120 why; Frage-Zeile (`Gr.q`) auf ≤200 Zeichen begrenzen (`[^\n<]{4,199}` — Kompilierzeit prüfen, sonst nur im Harness kürzen).

### S4 — Kein flock auf die Schicksal-State-Datei
`Sources/SLCore/Session.swift:44-47`, `Engine.load/save` (schicksal Engine.swift:55-61)
Die Schicksal-CLI nimmt einen exklusiven `flock` auf `<state>.lock` (schicksal/Sources/CLI/main.swift:24-31); sl schreibt `state.json` ohne Lock. Läuft parallel `schicksal …` (Skill) auf derselben Sitzung oder ein zweites `sl --resume <name>`, überschreiben sich Zustände (Seed-Draws, Journal) gegenseitig. Fix: in `Session` beim Öffnen `open(statePath+".lock", O_CREAT|O_RDWR)` + `flock(LOCK_EX|LOCK_NB)`, bei Fehler `SLError("Sitzung ist von einem anderen Prozess gesperrt")`; fd bei `/neu` und Prozessende schließen.

### S5 — CLI hält die gpu-run-GPU-Sperre unbegrenzt am Prompt
`Sources/sl/main.swift:87` (`while let l = readLine()`), `play.sh:10`
gpu-run ist FIFO mit einer GPU-Sperre; `sl` (CLI) wartet ohne Timeout auf Eingabe und blockiert so alle anderen Sessions, solange der Nutzer nicht `/quit` tippt. Regel: Idle ≤10 min. Fix: stdin mit `poll()`/`select` und `--idle` (Default 600 s) lesen; bei Timeout "Leerlauf – Modell entladen" ausgeben, Sitzung ist ohnehin gespeichert, `exit(0)` (Resume via `--resume`). `sl web` hat das bereits (Web.swift:120-126).

### S6 — Web: Host-Prüfung per Präfix, kein Origin-Check
`Sources/sl/Web.swift:96-97, 108-114`
- `host.hasPrefix("localhost")` akzeptiert `localhost.angreifer.tld` (DNS-Rebinding: Domain zeigt auf 127.0.0.1, Browser schickt genau diesen Host) → Angreiferseite darf Antworten lesen und `/say` posten. Fix: Host ohne Port exakt gegen `127.0.0.1`/`localhost`/`[::1]` vergleichen.
- POST `/say` ohne Origin/Sec-Fetch-Site-Prüfung: eine fremde Seite kann (simple request, Antwort unlesbar) Spielerzüge, `/neu` oder `/quit` injizieren. Fix: wenn `Origin` vorhanden, muss er `http://127.0.0.1:<port>` oder `http://localhost:<port>` sein; sonst 403.

### S7 — Web: `/state` blockiert während der Generierung; Crash wenn `game == nil`
`Sources/sl/Web.swift:60, 100-103`
`work.sync { state(runner, busy: b) }` wartet auf die serielle `work`-Queue, die gerade 20–60 s generiert → Seitenaufbau hängt (Story erscheint erst nach dem Zug). Schlägt `startNew` fehl (z. B. Engine-Fehler), ist `runner.game` nil; `state()` → `r.status()` → `game.eng` auf implicitly-unwrapped Optional → Absturz, sowohl im Job-Abschluss (Zeile 60) als auch bei `/state`.
Fix: `Status`/`story` aus einem per `NSLock` geschützten Snapshot lesen, den `Runner` nach jedem `onMsg`/Tool-Event aktualisiert; `state()` mit `guard r.game != nil` absichern.

### S8 — Fehlerpfad lässt hängenden User-Turn in `msgs`
`Sources/SLCore/Runner.swift:71`, `Sources/SLCore/Game.swift:71`
`push(.u(player))` passiert vor der Generierung; wirft `generate` (maxTok, Grammar), bleibt die Spielernachricht ohne Modellantwort in `msgs` (und via `onMsg` bereits in chat.json). Der nächste Zug erzeugt zwei User-Turns hintereinander — außerhalb des Few-Shot-Musters und des getesteten Formats. Fix: in `run` bei Fehler `game.msgs` auf den Stand vor dem Zug zurücksetzen (Count merken, `removeLast(n)`), dann `syncCache()` und speichern.

### S9 — Streaming-Detokenizer ohne Abschluss-Flush
`Sources/SLCore/LM.swift:113-119`
`NaiveStreamingDetokenizer.next()` gibt `nil` zurück, wenn das letzte Token nur ein unvollständiges UTF-8-Zeichen liefert (Tokenizer.swift:133-136); der Rest wird erst mit dem nächsten Token emittiert — am Turn-Ende nie. Betrifft Satzende mit Anführungszeichen/Sonderzeichen aus Byte-Fallback-Tokens: `out` ist dann kürzer als der Cache-Inhalt, `parseCall` könnte `</…>` verfehlen. Fix: nach der Schleife `let full = ctx.tokenizer.decode(tokenIds: gen)`; falls `full.count > out.count`, Rest per `onDelta` nachliefern und `out = full`.

---

## NICE

- `LM.swift:149` — `temp <= 0` ergibt `1/temp = inf` → NaN-Logits. `if temp <= 0 { tok = argMax(l) }`.
- `LM.swift:130-139` — Maske wird pro Token als 262 144-Float-Array auf der CPU gebaut und hochgeladen (≈1 MB/Token). Die Lib macht es genauso (GuidedGenerationLoop.swift:563-595), aber ein einmal allokierter Puffer + `MLXArray(buffer)` spart Allokationen; alternativ `bitmaskToMLXArray` wiederverwenden.
- `LM.swift:66-73` / `Grammar.swift` — ~15 Gate-Varianten werden beim ersten Auftreten kalt kompiliert (README warnt: hunderte ms, hier bis ~0,3 s). Beim Start im Hintergrund vorkompilieren (alle `Gate`-Kombinationen aus `testFewShotAcceptedByGrammar` + `ans` ∈ {JA+,JA,NEIN+,NEIN}).
- `Grammar.swift:39` — `sent` erlaubt führendes Leerzeichen; `Tmpl.turn` trimmt beim Re-Render → Token-Divergenz nach Resync (harmlos, aber vermeidbar: `[ ]?` nur ab dem 2. Satz).
- `Grammar.swift:58-59` — bei `/ende` ohne offene Szene greift zuerst head_scene (start_scene erzwungen); besser in `Runner.ende()` mit `guard game.eng.st.open else { sink(.info("keine offene Szene")) }` abfangen.
- `Game.swift:57-63` — `compact()` kann mit einer `[Orakel] …`-User-Nachricht beginnen, deren Tool-Call weggeschnitten ist. Beim Kürzen bis zur nächsten echten Spielernachricht (nicht `[Orakel]`-Präfix) zurückgehen.
- `Runner.swift:68` — `if m.count > 40 { game.sys = SYS }` ist ein No-op (`sys` ist bereits `SYS`).
- `main.swift:52-54` — `Session(name:)` legt das Verzeichnis an, bevor `--resume <name>` auf Existenz geprüft wird → leere Sitzungsordner bei Tippfehlern.
- `Web.swift:176` — totes `m.card`-Handling (`const r=document.createElement('div')` wird verworfen); Karten erscheinen erst mit dem nächsten `state`. Entweder die Karte sofort in `#rolls` einhängen oder den Zweig streichen.
- `Web.swift:105-107` — SSE ohne Heartbeat; `EventSource` reconnectet zwar, aber ein Kommentar-Ping alle 30 s hält Proxies/Browser ruhig und erlaubt tote Verbindungen früher zu räumen.
- `play.sh:7` — `trap … EXIT` läuft erst nach `gpu-run`; ok. Für `sl web` wäre `gpu-run … --ram` mit `SL_RAM` Default auf den tatsächlichen Peak (nach B2 messen, ki-top) zu setzen.
- Tests: `GrammarTests` laufen nur mit Modellordner; für CI ohne Modell einen Vocab-Dump (tokenizer.json → `[String]`) cachen und `GrammarTokenizer` daraus bauen.

---

## Reihenfolge für den ersten echten Lauf
1. B1 (Cache-Prefix), 2. B2 (Text-Factory, RAM), 3. S1 (`/frage`-Format), 4. S8 (Fehlerpfad), 5. S5/S4 (Ressourcen- und Lock-Regeln), 6. S2/S3 (Gate-Feinheiten), 7. S6/S7 (Web).
