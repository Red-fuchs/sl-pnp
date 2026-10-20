# Fable review v6 – f646a2a..a7c0ed3 (limit fixes F1–F5, director + leak guard, ban trie, tiers, Regelwerk, positive classes) — 2026-10-20

Read-only review. Severity: HIGH = secret reaches the player or a clue can become unreachable (hard requirement) · MED = clear logic/UX failure · LOW = polish. `file:line` = state at a7c0ed3.

## HIGH

**1. Tier 1 ("Andeutung") hands the verbatim secret to the narrator with no guard** — Director.swift:138,143,147 · Game.swift:163-164
- Scenario: one turn of "Ich frage Zubeir nach dem Wasser" = +2 Spur → tier 1. `secretList()` now excludes Zubeir, but `directorPass` still puts the full `geheimnis` into `facts` ("darf angedeutet werden"), checks its output only against `secretList()` (empty for him), and the narrator stream gets `check: nil` because `secrets.isEmpty`. Only the soft −4 penalty remains → "[Regie verdeckt] Zubeir panscht das Wasser mit Salzlake…" → narration → player. The tier that is supposed to mean "hint" is the weakest point of the whole chain.
- Fix: in `facts` use the Stichwort/topic words instead of `h.geheimnis` when `tier >= 1`; run `leakCheck` (director and `NarrStream`) against `secretList() + softList()` (soft = regen/drop only, never a hard ban).

**2. Clue-bearing threads and NPCs get evicted → clues unreachable forever** — World.swift:351 (`straenge.count > 8 → removeFirst`), World.swift:283-285 (NPC cap 20 evicts the first absent NPC) · WorldGen.swift:404 (`reveal` needs `titel == c.thread`), Director.swift:110
- Scenario: generated threads are appended first; the delta step adds a thread almost every turn (F20: 5 by turn 19). At the 9th thread the oldest generated thread is dropped, `reveal()` never finds `c.thread` again, `threadWarnings` only runs at generation time. Same for a generated clue-holder NPC that is absent when the 21st NPC arrives (`talked`/`namedBy` can no longer match a name that is not in `world.npcs`).
- Fix: in `apply()` evict the oldest thread that has no unfound clue (`hidden` is not visible in World → pass a `protected: Set<String>` or mark generated threads via `extra["gen"]`); in `addNpc` skip NPCs with `basis != 0 || hidden`-flag (`addNpcGen` sets a `fest = true`).

## MED

**3. Hard ban on short / single-token terms blocks compounds, including revealed clue words** — Director.swift:177,183 (`single` always blocked), :191-193 (`seen` by 5-letter `stem`), Game.swift:165
- Scenario: secret "…mit Salz" → variants " Salz"/"Salz" are single tokens → banned on every step. Narrator can no longer write " Salz"+"spuren", " Salz"+"fass", and – worse – the revealed clue "Salzspuren am Rand" (stem "salzs" ≠ "salz", so `seen` does not lift it) in the very turn `[Hinweis verdeckt]` asks it to. Same for "Gift" → "Giftmischer". Clue stays "found" in the panel, but the story cannot name it.
- Fix: in `banTerms` treat `w` as seen when any known word `hasPrefix(w.lowercased())`; in `buildBan` drop 1-token sequences for terms < 6 letters (leave them to the n-gram guard).

**4. `markDeaths` kills NPCs on reported speech / observed deaths, irreversibly** — World.swift:376-394 (no "sagt/erzählt/dass" hedge, passive rule kills every name before the verb)
- Scenario: "Marta erzählt, dass ihr Vater vor Jahren starb." → Marta is before `starb` → `kill(Marta)`. "Marta sah, wie Bork erschlagen wurde." → passive → Marta (p < verb) killed too. `tot` never reverts; bearer/director/`talk` are gone for her. Clues at her stay reachable only by naming her in the player line.
- Fix: add `"sagt", "erzählt", "berichtet", "dass", "sah", "hörte"` to `hedges`; for the passive rule kill only the LAST named NPC before the verb.

**5. `/gespraech` never raises the Spur (talkedThisTurn is cleared before `updateSpur`)** — Game.swift:106 (`tick` → `defer { talkedThisTurn = [] }` World.swift:433) then Game.swift:108 reads the empty set
- Scenario: player uses the 💬 buttons; the secret's Spur stays 0 although "asking the bearer" is the +1 event. Progression only through the free-text path.
- Fix: capture `let talkedNames = world.npcs.filter { world.talkedThisTurn.contains($0.id) }.map(\.name)` before `tick`, pass it to `updateSpur`.

**6. Leak is shown on screen first, retracted afterwards (no hold when the bearer is absent)** — Game.swift:331 (streams per char), :336-339 (check only at line end), :163 (`hold` only with a present bearer)
- Scenario: secret of an absent NPC, `secrets` non-empty → `hold = false` → the complete leaking sentence is streamed (165 chars/s ≈ 2 s on screen), then `.retract`. Transcript is clean, the player has read it.
- Fix: in `feed`, when `narr && ".!?".contains(ch)` run `check` on the current sentence and set `leak` immediately (abort fires on the next token); or `hold = !secrets.isEmpty`.

**7. `.info` names the bearer: "Erzählung verworfen (Geheimnis angedeutet: Geheimnis von Zubeir)"** — Game.swift:179,200 · replayed to late joiners by Web.swift:15 (`recent`)
- Scenario: the player learns which NPC holds a secret and that the last sentence touched it – metadata leak, exactly what the hold was meant to hide.
- Fix: `out(.info("Erzählung verworfen – neuer Versuch"))`; keep the topic in a `[debug]` line.

**8. Director pass + hold on every turn with any goal-bearing NPC** — Director.swift:66 (`bearers` includes `!ziel.isEmpty`), Game.swift:152,163
- Scenario: every generated NPC has a `ziel` → in generated worlds the aux prefill (~500-900 tok sys+[Welt]) + ≤120 gen tokens runs each turn, twice on a director leak (+2-4 s/turn, matches the REVIEW-grammar-engine estimate), and streaming is held on those turns although nothing in `ziel` is guarded. Cache consistency itself is fine: aux uses throwaway caches, main cache sees only `push`/`syncCache`.
- Fix: run the pass only when `namedBy(player)` ∩ bearers ≠ ∅ or a bearer is at tier ≥ 1; `hold = bearers.contains { hidden.npcs[$0]!.tier(...) == 0 }`.

**9. Only the narration line is leak-checked; oracle `q`, `expect`, `summary` reach the UI unchecked** — Game.swift:215-233 (`parseCall` → `eng.call` → `.tool`), Web.swift:27-30 (`describe`, card `q`), Runner.swift:151 (journal)
- Scenario: head "Frage: Panscht Zubeir das Wasser, weil er die Zunft retten will?" – the ban blocks exact tier-0 tokens, paraphrase/2-rare-word sentences pass; the question is printed as "⚀ ask_oracle: …", lands in the roll card, the SSE replay and transcript.md; `end_scene.summary` goes into the Journal panel and the compaction recap.
- Fix: before `eng.call`, `if leakCheck(args["q"]/["expect"]/["summary"]) != nil` → treat like `ns.leak` (abort + regen); cheap, deterministic.

**10. All-−inf logits when the only grammar-legal token is banned** — LM.swift:157-161,164,220
- Scenario: `single` ids are masked on every step, also inside enums/const tails (`en(places)`, `duSlot`, `Art:`); if a banned token is the only allowed one, `categorical` samples from NaN → `commitToken` throws → "Fehler: …" for the turn. Rare today (names/places are `seen`), but the grammar review's "apply only when `free`" was not implemented.
- Fix: `block: free ? blk : [], soft: free ? sft : []`.

## LOW

**11. `/welt debug` prints clue locations to any player** — Runner.swift:134 (`hidden.debugTable()` lists `✓/· <at>` per clue) → gate on `debug`.
**12. `softBanFor` rebuilt on every attempt** — Game.swift:60-63,172: 2 stems × 2 cases × 8 suffixes × 2 = 64 tokenizer encodes per term per generate; reuse the `banCache` pattern.
**13. Anti-stuck is dead code** — Director.swift:84-86,97-99: `engaged` always implies `gain ≥ 1`, tiers change every ≤2 engaged turns, `stuck` never reaches `stuckN`. Conversely naming the bearer + any topic word = +2/turn, an oracle JA about him +2 → tier 3 in 2-3 turns without a single clue (design, not bug; `/welt debug` shows it).
**14. 3rd attempt accepts `ns.bad`** — Game.swift:172 (`attempt < 2`), :333: meta/foreign narration on the last attempt is shown and enters history; drop the line like the leak path does.
**15. Director `ziel`/`gruppe` are never guarded** — Director.swift:138: by design ("steered, not guarded"), but a leaked hidden goal is also a spoiler; include `ziel` words in `softList` for tier 0 bearers.
**16. Legacy glyph repair skips hidden.json** — Session.swift:51,54: `world.repairText()` may change a thread title while `hidden.clues[].thread` keeps the corrupted one → unreachable for old sessions (new ones are safe: `at` comes from an enum).

## Regelwerk `frei`
True no-op: `Frei` returns 0/0/identity/identity (Regelwerk.swift:31-38); `combinedShift(nil, 0) == nil` (old path); `gate.art` false → no `Art:` line, grammar is the same sequence split into two const strings (Grammar.swift:113, gcache key changes once, harmless); `lastArt` only set under `saeulen` (Game.swift:221); panel sheet only under `saeulen`; `updateSpur` bonus 0; `talk`/`/geloest` identity. Only side effect: `classifyArt(player)` is evaluated eagerly in the capture list (Game.swift:108) – µs. `testFreiChangesNothing` covers it.

## Prompt / KV-cache consistency
OK. `directorPass` and `softBanFor` run before `push`; aux uses a fresh cache. The three rebuild paths (`AbortedError`, `TruncatedError` without salvage, salvage/truncated, leak-retry note appended to `msgs.last`) all end in `syncCache()`; `dirty` is cleared by `reset`. `compact()` keeps the `[Regie verdeckt]`/`[Hinweis verdeckt]` lines of old turns in the prompt (history only, UI strips them) – fine, but they accumulate; strip them in `compact()` like `stripWelt`.

## Grammar-mask regression (0.3 → 2.4-4.8 ms/token)
- Swift side (LM.swift:155-163, 207-222): the per-step loop is unchanged in complexity — `-inf` fill over 262k, then for every allowed id a `pen.contains(i)` hash lookup, then `MLXArray(maskBuf)`. New per step: `ban/soft.blocked()` (µs) and the `!needsApply` branch (262k `pen.contains`, only when xgrammar reports an unconstrained state — rarer with positive classes, not commoner). Not the 2 ms.
- Engine side, visible in the diff: 0f2d781 (Grammar.swift:54-63) is the only grammar change. In the vendored xgrammar a token is "uncertain" when a prefix matches the class and the next byte does not (grammar_compiler.cc:640-660); `FillNextTokenBitmask` re-walks every uncertain token on every step (grammar_matcher.cc:695-745). With `[^<.!?\n:]` only tokens containing one of six chars were uncertain; with the positive class every "Latin prefix + anything else" token joins (`_ # @ [ ] { } | \ ~ ^ $ >`, digits are in but `.`/`:` out, mixed-script and emoji suffixes — plentiful in a 262k multilingual vocab). That is a plausible 10× growth of the per-step walk and matches the magnitude. The `{6}` prefix states are affected the same way.
- Not provable read-only. Check: split `maskS` into computeMask / maskArr / commit (3 timers, one `--debug` line); then A/B `Cls.narr` negated vs positive on one narration. If the engine side confirms: keep the negated class for the narration sentence and let the existing `!isCleanText` abort (Game.swift:333) handle foreign glyphs; keep positive classes for the short gen/gate lines. Independent cheap win: replace `pen: Set<Int>` with a `[Float]` penalty table indexed by id (array read instead of hashing per allowed token).
- Caveat seen while reading: `GetFirstCharacterMask` (grammar_compiler.cc:712-721) casts class members to `uint8_t`; the `„“”‚‘’»«–—…` members (U+20xx) map to garbage bytes and only pass because the Latin-1 range `À-ÿ` happens to mark lead byte 0xE2. Do not drop that range without re-running `testUmlautLiteralsAcceptedByGrammar`.

## What held up
Hidden text reaches the narrator only through `reveal()`/`updateSpur` (tier 3), `[Hinweis verdeckt]`, `[Regie verdeckt]`; `displayStory` strips every harness tag per line; reveal events no longer go to `.world`; `/state`, SSE and transcript carry narration only; `bekannt` is the only hidden-derived text in `[Welt]`. Ban/guard never touch clue texts or goals (tests cover it); clue `at` is grammar-enumerated, so F12 typo refs cannot recur. Positive classes fix F4 at the source (test: 0 foreign tokens allowed). `/quit` over HTTP, `/fragen` boundary, `/neu` naming, SSE replay: correct.
