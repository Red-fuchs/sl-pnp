# Fable review – world state v5 (f1ef53d..8850e94)

## Findings
1. HIGH npc() fuzzy match (World.swift:42): empty `wer` resolves to NPC #0; prefix merges distinct names (Idalia→Ida, Borka→Bork, Wachen→Wache). Fix: guard empty, whole-token match.
2. HIGH figuren overwrites existing NPC ort/kurz each turn (World.swift:105-110); NPC drops from "Hier" when the model relabels a place. Fix: existing NPC ignores figuren.ort (only npc_ort moves it); new NPC ort = world.ort; kurz only if empty or equal to the role word.
3. HIGH nameHints treats dative objects as people (World.swift:175): "gibt dem Kind Brot" → NPC "Brot", also pushed to Schicksal akteure. Fix: article/gender agreement or namens/genannt/comma form; optionally require ≥2 occurrences.
4. MED Player character becomes an NPC (World.swift:38,106): exact-name check only; "Aether der Graue"≠"Aether"; role-named PC ("Matrose") → NPC. Fix: token match against PC name/kurz head noun; /figur purges NPCs with that name.
5. MED World↔Schicksal lists diverge and grow without bound (World.swift:109,140; schicksal Engine.swift:203-206): eviction never removes engine entries, `lists add` has no dedup or cap; relations keyed by name go stale after a rename. Fix: remove on eviction, dedup, key relations by id.
6. MED Rename picks the wrong role NPC (World.swift:166). Fix: prefer here() candidates, else create a new NPC.
7. MED haltung→shift ignores polarity (Game.swift:135, World.swift:84): "Greift Bork mich an?" gets an inverted shift. Fix: apply only for social verbs (hilft|vertraut|verrät|gibt|lässt|glaubt…).
8. MED Negative Content-Length crashes the server (Web.swift:79-81). Fix: max(0,…), cap body and /say text length.
9. LOW-MED Data race on runner.session (Runner.swift:127 vs Web.swift:38,41). Fix: put the name in the locked snapshot.
10. LOW-MED World strings reach the prompt unsanitized: newline, `---`, `|`, `<turn|>`. Fix: one clean() at all entry points.
11. LOW Delta step sees a stale [Welt] after start_scene (Game.swift:92→156). Fix: rebuild world.block() at worldStep time.
12. LOW Junk entries: empty kurz, 40-char mid-word cuts, empty stand. Fix: ≤4-word filter, cut at word boundaries, omit the dash when empty, reject du/dir/dich.
13. LOW Silent world loss on resume when decoding fails (Session.swift:48). Fix: warn or throw.
14. LOW kurz churn (fixed together with #2).
15. LOW SSE connections not pruned; aux() re-prefills ~700 tokens every turn (consider a persisted side-cache prefix).
KV/prefix stability: OK.

## Design recommendations
- Slot cards with a fixed slot order, ≤6 entries, e.g. `Marta (Wirtin · hier · misstrauisch · trägt Schlüssel)`; `Du = Aether` on its own line.
- Presence flag `anwesend` instead of matching place strings: start_scene clears it for everyone except beteiligte.
- The narrator registers its own characters: a mandatory grammar tail on the narration step, `Figuren: Marta (Wirtin), …` or `-`, stripped from display. The delta step then only handles items, haltung and threads.
- Confirm, don't extract: pre-scan for name candidates; the delta step only accepts or rejects them. Add a negative few-shot (a known NPC returns → no new figuren).
- One registry: derive Schicksal akteure/straenge from the world.
