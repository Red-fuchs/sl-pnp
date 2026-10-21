# Schicksalsschlag rules v0.1 (session 2026-10-22)

The user's design. sl Regelwerk id: `schicksal`. These are the source of truth for the sl module, the Foundry module and the PDF.

## Character creation: word budget from the background story
- The player writes a short background story (3–8 sentences). Traits are extracted from it as **words**: Gemma in sl, or the GM by hand.
- Starting budget: **20 points**.
  - Positive trait (skill, quality, contact) costs **2** (minor) or **4** (major), e.g. „geübter Bogenschütze“ 4, „trinkfest“ 2.
  - Negative trait (flaw, debt, enemy, fear) gives back **+2** (minor) or **+4** (major).
- Leftover budget:
  - 1 point = 10 Taler starting money,
  - or 2 points = 1 starting item (normal gear, no magic),
  - or 3 points = +1 max Schicksalspunkt.
- Three pillars **Kampf / Sozial / Wissen**: distribute 30 / 40 / 50 in any order. These are the base values for d100.

## Skill check: d100 roll-under with degrees
- Target number = pillar + traits + difficulty.
  - A fitting positive trait adds +10 (minor) or +20 (major); a fitting negative trait gives −10 or −20.
  - Difficulty: leicht +20, normal ±0, schwer −20, sehr schwer −30.
- Roll d100 (01–100). **Roll ≤ target = success.**
- **Degrees:** DoS = 1 + ⌊(target − roll) / 10⌋. On a failure, DoF = 1 + ⌊(roll − target) / 10⌋.
- 01–05 is always a success (at least 1 DoS); 96–100 is always a failure.
- **Doubles** (11, 22 … 99, 100):
  - a success becomes a **critical success**: the GM adds a twist in your favour;
  - a failure becomes a **critical failure**: complication.
- **Opposed check:** both roll, more DoS wins; on a tie the higher target number wins.

## Combat (d100, lean)
- Attack = Kampf check.
  - Defence: the defender rolls Kampf as an opposed check (parry/dodge), or the attacker simply needs ≥1 DoS against a passive defender.
- Damage = weapon (fist 1, knife/club 2, sword/axe 3, bow 3, firearm 4) + DoS − armour (cloth 0, leather 1, mail 2, plate 3).
- **Wunden:** 10 per PC.
  - 0 or less: down, and a Schicksalspunkt is needed to stay alive.
  - At ≤3 Wunden: −10 on everything.
- Initiative: everyone rolls d100 ≤ Kampf, and more DoS acts first. Simpler: players first, then opponents.

## Schicksalspunkte (SP), the "Fatedash"
- Start with **5**, max 5 (more via budget). The resource works like mana, for fate.
- **Spend** before the roll or right after it (before the result is narrated):
  - 1 SP = **±10** on a check, your own or **someone else's** (also an opponent's or an NPC's, to manipulate fate). At most 3 SP per check.
  - 1 SP = shift the **oracle odds** one step (e.g. offen → wahrscheinlich, or for an opponent worse).
  - 2 SP = **reroll** (the second roll stands).
  - 1 SP = survive at 0 Wunden (stays down, but alive).
- **Threshold:**
  - At **SP ≤ 1**: "schicksalsmüde", **−10** on all checks.
  - At **SP 0**: **−20**, and oracle questions in your favour go one step worse.
- **Recovery:**
  - short rest (an hour): +1;
  - night's rest / safe place: +3;
  - strong roleplay of one of your **negative** traits, so that it costs you something: +1 (GM's call);
  - feast/celebration/temple: +2;
  - completing a thread: +2.
  - Max stays the cap.

## Schicksalsergeben (house rule, decided 2026-10-21)

> **Schicksalsergeben.** Vor dem Wurf, bei einer Probe mit echtem Einsatz (SL entscheidet; nie bei leichten Proben, Initiative oder reinen Übungen), kannst du dich dem Schicksal ergeben: −10 auf die Probe. Gelingt sie trotzdem mit mindestens 2 Erfolgsgraden, erhältst du 1 Schicksalspunkt zurück (nicht über dein Maximum). Scheitert sie, ist es ein Schicksalsschlag: der Misserfolg zählt einen Fehlergrad mehr und wird härter erzählt.
>
> Einmal pro Szene und Figur. Nicht kombinierbar mit Schicksalspunkten auf derselben Probe, weder eigenen noch fremden. Ein Neuwurf (2 SP) bleibt erlaubt, das zweite Ergebnis zählt.

Math and decisions:
- With T' = T − 10 the check is rolled against T'. The SP gain needs DoS ≥ 2, i.e. roll ≤ T' − 10 = **T − 20**.
- 01–05 always succeed with DoS = 1 + max(0, T' − roll) / 10, so there is no special case (T' = 40, roll 3 → DoS 4, gain).
- A failure gets **DoF + 1**, on every failure: also 96–100 and critical failures (no extra rule). Example T50: roll 45 vs T' 40 → DoF 2; roll 44 (double) → critical failure, DoF 2.
- The −10 is its own modifier "Schicksalsergeben −10" in the calculation, not part of the difficulty. It stacks with traits, difficulty and the SP/Wunden thresholds (computed on the SP before the gain).
- Gain is capped at the SP maximum; at max the roll still counts as used.
- **Once per scene and figure:** a flag on the sheet, reset on `start_scene` / `end_scene`. A second use is refused ("in dieser Szene schon verbraucht").
- **Not on leicht checks** (refused by sl). "Real stakes", initiative and pure practice stay the GM's call.
- **Not combinable** with SP on the same roll: refused with 400 when `sp > 0`, 409 when pre-spent SP (`/sp mode=pre`) or SP from others (`mod`) are on the sheet.
- **Reroll (2 SP):** allowed; the second result counts, including its ergeben effects (an earlier SP gain is taken back, a failure gets +1 DoF again).
- Narrator fact: "[schicksalsergeben (−10), 1 SP zurück]" / "[… Schicksalsschlag, der Misserfolg wiegt einen Grad schwerer und wird härter erzählt]".
- API: `/roll` and `/rollresult` take `"ergeben": true`; replies and SSE `roll` carry `ergeben` and `sp_gained` (see API-foundry.md). Foundry: checkbox in the Probe dialog.
- Not covered by the explainer video (not re-rendered).

## Oracle (Schicksal, Mythic-like)
- Yes/no questions with odds (sicher … unmöglich) and tension/Spannung 1–9 → JA+ / JA / NEIN / NEIN+, plus event on doubles ≤ tension. Tables: `~/Projects/schicksal/Sources/Schicksal/Resources/tables_de_darkfantasy.json`.
- Spending SP shifts the odds by one step (see above).

## Content rule
- Minors are never victims of violence or of sexual content. Dark content among adults is fine.
