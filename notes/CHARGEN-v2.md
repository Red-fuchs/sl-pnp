# CHARGEN-v2: character creation systems A / B / C / B+C (branch chargen-v2, 2026-10-21)

Flag `sl --chargen a|b|c|bc` (default `a` = unchanged behaviour). Design by Fable ([review]), implemented in `Sources/SLCore/Chargen.swift`.

| mode | currency | deterministic caps | arbiter (Gemma + oracle) |
|---|---|---|---|
| a | 20 points (current) | none | no |
| b | 200 Taler | yes | no |
| c | 20 points (A economics, `teurer` = x1.5) | only the arbiter floors | yes |
| bc | 200 Taler | yes | yes |

## Decisions (Fable)
- **B+C is the recommended shape**, one currency (Taler). C alone keeps two currencies (points + Taler for tools) and is a dead end.
- **The 40-500 Taler range is rejected as a budget range.** 40 T = knife + leather, 500 T = plate + sword + shield + horse + scholar kit (~2.5x power); no narrative compensation covers a 12x money gap. 40-500 survives as the price band of things (cheapest trait 20 T ... most expensive creation purchase 100 T) and as the cash band after creation (0-60 T).
- **Budget:** fixed 200 T (= old 20 points). Optional Herkunft by d100 (real dice): 01-30 arm 170 T + SP max 6; 31-80 einfach 200 T, SP 5; 81-00 wohlhabend 230 T, SP 4. Power neutral because +1 SP max = 30 T. (NOT built in this branch: fixed 200 T only; Herkunft listed as follow-up.)
- **Trait prices:** positive minor 20 T, major 40 T (same ratio as A). Flaws refund 20/40 T.
- **Deterministic caps in B (engine, never the model):**
  - max 5 positive traits, of which max 2 major (trait spend <= 140 T);
  - max 3 paid flaws, refund <= 80 T; further flaws are kept as "Farbe" (0 T refund, no SP recovery);
  - trait text <= 40 chars and <= 3 content words (kills word-stuffing);
  - per check at most 2 fitting traits, total trait modifier clamped to +-30;
  - +1 SP max = 30 T, at most +2;
  - single creation item <= 100 T, ordinary gear only (items.json list price; unknown item 20 T); magic keywords (zauber, magie, unsterblich, drache, ...) are refused as gear and as traits in B-only;
  - cash after creation <= 60 T (rest is lost).
- **Not built (follow-ups):** Schwaechenwurf (hidden d10 on a flaw's pillar so "flaws that never matter" bite), Herkunft roll, consumable caps, Taler Herkunft.
- **Power formula (cross-system):** `P = sum price(pos traits) - 0.5 * sum refund(paid flaws) + sum list price(gear) + 30 * (SPmax - 5) + min(cash, 60) + 0.5 * max(0, cash - 60)` in Taler; band 170-230. A characters use the same formula (points x10).

## System C: Gemma as arbiter
- Model sees: sanitised story (quoted data), trait list (text, minor/major, pos/neg), gear names. Never: budget, prices, caps, SP, hidden.json, narrator prompt.
- Verdict per trait (line based, grammar constrained, names are grammar literals so the model cannot invent, rename, skip or add lines):
  `Merkmal: <name> (minor|major) | ja|fraglich|nein | Grund: ... | Tausch: -|Schwäche ... | Preis: normal|teurer`; per item `Gegenstand: <name> | passt|fraglich | Grund: ...`; final `Fairness: ...`. A `nein` is structurally impossible without a trade-off.
- Deterministic floors the model cannot override upward: positive trait with no word match in the story is at best `fraglich`; the 3rd+ major is at best `fraglich`; magic keyword -> `nein`.
- Backstops: max 2 `nein` per character (rest downgraded to `fraglich`), a trait supported by >= 2 story sentences cannot be `nein`; broken output -> 1 retry at temp 0.2, then everything `fraglich`.
- Plausibility -> oracle: `fraglich`+normal -> odds 0 (offen, p ~ 0.50); `fraglich`+teurer -> odds -1 (unwahrscheinlich). `ja`/`nein` need no dice. Tension fixed 5. Max 3 oracle questions per character (majors first), further `fraglich` count as NEIN. Results cached per trait text (no re-rolling).

| outcome | effect |
|---|---|
| ja | accepted at base price (x1.5 if `teurer`) |
| fraglich -> JA+ / JA | accepted (JA+: narrative hook, free) |
| fraglich -> NEIN | trait accepted with the trade-off flaw (refund 0); without trade-off price x1.5 |
| fraglich -> NEIN+ | trait dropped, trade-off flaw stays |
| nein | trade-off offered: accept (trait x1.5 + flaw) or decline (dropped) |

- **Injection hardening:** story goes through `clean` plus removal of `[ ] « »`, defusing of `Regie:`, `Fakt:`, `System:`, `Merkmal:` ... prefixes, wrapped in `«Geschichte» ... «Ende Geschichte»`; system prompt says the story is data. Output classes of the grammar exclude `|`, newlines and brackets. Ban list on free text (system-prompt phrases, hidden.json leak guard). Verdict effects are bounded: price factor in {1, 1.5}; trade-off flaws are minor with refund 0, max 2 per character; a verdict can never raise the budget or add a positive trait.
- **Player flow:** `/figur Name: Geschichte` (extraction as before) -> `/wunsch +Text [major] | -Text [major] | Gegenstand: X | SP: N` -> `/pruefen [Einwand]` (verdict card) -> `/annehmen alle|1,3|keins`. `/budget` and `/merkmal` stay for A/B.

## Arbiter system prompt (German)
See `chargenArbiterSystem` in Chargen.swift (Fable's 212-word text).

## Adversarial tests (SLTests, mock LM)
format injection, fake tags, prompt exfil, hidden-secret probe, flaw farming, max traits no gear, all SP / cash clamp, word-stuffed trait, lenient mock, harsh mock, oracle cache.
