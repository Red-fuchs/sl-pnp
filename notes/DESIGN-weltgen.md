# World generation – design (2026-10-20, Opus draft + Fable review)

## Modes
`/welt orakel` | `/welt "text"` | `/welt mix "text"`. Web: 3 cards, text field for 2/3.
- Player text → one grammar call → slots `{ton, epoche, ort_typ, bedrohung, licht, muss_vorkommen[], darf_nicht[]}`. Show the table, let the player edit, unfilled slots → oracle.
- Player slots are hard constraints. Oracle word pairs are inspiration only and never override a filled slot. On a conflict (darf_nicht hit), reroll once, then drop the pair.
- Oracle pairs also go in as "Würze" in player mode, with ~20% neutral pairs (tables are dark by design).

## Stages (one object per call, ≤250 tokens, temp ~0.9)
1. **Prämisse** (1 line + licht slot + alltag place), prefixed to every later stage.
2. **Orte** one per call (name, 1 line, wer herrscht hier = faction implicit). Start: 3; later up to 8.
3. **NPCs** one per call. Name comes from a deterministic name generator (syllables per culture + RNG + used set) as const_string in the grammar. Role from a pool (~40), haltung enum −2..2, ort enum (existing ids), gruppe, ziel, geheimnis, enthuellung `{typ: ort_betreten|npc_befragt|gegenstand|zeit|orakel, ref: enum ids}`. Start: 2; later up to 10.
4. **Beziehungen**, not a stage of their own: from ziel/geheimnis pairs (grammar a,b = id enums) or the oracle `relationen` table.
5. **Stränge** (2–3) as question arcs: frage visible, hinweise hidden.
6. **Verknüpfungen**: which clue sits at which place/NPC (id enums only).
7. **Startszene** + PC hook/secret goal.

## Grammar/logit tactics
- Enums everywhere; ids/names/places as const_string or enum from validator state (biggest win).
- Length: regex prefix + unbounded tail (bounded repeats explode compile time).
- One few-shot per stage in a different setting (desert), ≤150 tokens.
- Banned words in the prompt (Marta, Schatten, uralt, flüstern…) + validator reject → targeted regen naming the word. No self-check stage (a 4B can't judge itself).
- Literal oracle pairs: reject if both words appear verbatim ("deute, zitiere nicht").

## Hidden vs. visible
- `hidden.json`: geheimnis, ziel, enthuellung, clues, verbirgt relations. Never in [Welt].
- NPC `bekannt:[String]`: only facts the player has learned are rendered.
- The harness decides reveals: when a condition is met, inject one line "Hinweis (verdeckt): …" into the narrator prompt for that turn → fact moves to `bekannt`.
- [Welt] stays ≤ ~600 tokens: details only for `anwesend`, places only current + adjacent.

## Timing
- Full ~4k tokens ≈ 90–120 s. Up front: Prämisse + 3 places + 2–3 NPCs + thread questions + start scene → playable ("Welt spielbar, Rest folgt").
- Rest lazily on demand at first contact (~5 s, "…"), not true idle scheduling. Always validate against the current world, not the seed. syncCache after aux.

## Progress
Stage list with counts ("Orte 4/6"); CLI = one line rewritten, web = SSE events, each finished name appears (player can veto early).
