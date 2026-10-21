# Schicksalsschlag rules v0.1 (session 2026-10-22)

The user's design. sl Regelwerk id: `schicksal`. These are the source of truth for the sl module, the Foundry module and the PDF.

## Character creation: word budget from the background story
- The player writes a short background story (3–8 sentences). Traits are extracted from it as **words**: Gemma in sl, or the GM by hand.
- Starting budget: **20 points**.
  - Positive trait (skill, quality, contact) costs **2** (minor) or **4** (major), e.g. „geübter Bogenschütze“ 4, „trinkfest“ 2.
  - Negative trait (flaw, debt, enemy, fear) gives back **+2** (minor) or **+4** (major).
- Leftover budget:
  - 1 point = 10 Taler starting money,
  - or **starting items by price tier (Vorschlag, 2026-10-21)**, normal gear, no magic:
    - 10 Taler = 1 point. **2** points (20 Taler): normal gear, knife/dagger or club, leather armour (armour 1);
    - **4** points (40 Taler): sword, axe or bow (also spear, crossbow), chain mail (armour 2), shield;
    - **6** points (60 Taler): plate armour (armour 3) or a firearm.
    - sl classifies by keyword; unknown items count as normal (2). `/budget` shows the tier per item.
    - **Price source:** `handout/data/items.json` (see RULES-gegenstaende.md) is the price source for gear (budget points = price ÷ 10 Taler, rounded up). The 2/4/6 tiers (20/40/60 Taler) stay as the starting-gear values; the engine keeps the keyword tiers until after the session.
  - or 3 points = +1 max Schicksalspunkt.
- Three pillars **Kampf / Sozial / Wissen**: distribute 30 / 40 / 50 in any order. These are the base values for d100.

### Worked example: Paladin (Vorschlag)
Strong kit has to be funded by flaws. Story: sworn knight of a temple order, hunted by a cult, penniless.
- Positive: „Geweihter Streiter“ (major) **−4**, „Handauflegen“ (major) **−4** → −8.
- Negative: „Heiliger Schwur (darf nicht lügen/fliehen)“ (major) **+4**, „Fanatischer Feind: Kult X“ (minor) **+2**, „Arm wie eine Kirchenmaus“ (minor) **+2** → +8.
- Budget: 20 − 8 + 8 = **20** to spend.
- `/budget taler=3 item=Plattenpanzer,Schwert,Schild sp=1`: plate **6** + sword **4** + shield **4** = 14, +1 max SP **3**, Taler **3** (= 30 Taler) → 14 + 3 + 3 = **20**, nothing left over.
- Without the three flaws (budget 12) plate and sword (10) would leave 2 points: no shield, no SP.
- Armour of the figure (leather 1, mail 2, plate 3) reduces the damage of a counterblow by its value, but never below 1 LP.

### Story items ★ (Auslegung, decided 2026-10-21: „alles kostet Budget, aber Boni wenn die Geschichte stimmig ist“)
- Every item costs its tier price. An item bought via `/budget item=…` that shares a content word with the background story or a positive trait (same matcher as for traits) becomes a **★ Story-Item**. Same prices as other items; non-story items behave as before.
- On purchase sl secretly rolls a hidden **Gegenstandsgeheimnis** (d6): 1–2 nothing, 3–4 **levelbar**, 5 **Wendung**, 6 both.
  - **levelbar:** the item grows +1 after each solved thread (`/geloest`), max +3: weapons +1 damage per level, tools +10 per level on checks that mention the item, armour counts normally. **Item caps apply** (RULES-gegenstaende.md): base weapon damage + level ≤ 5 (a sword, base 3, stops at +2; a knife, base 2, reaches +3) and base armour + level ≤ 3 (plate cannot grow). The engine clamps this in the level-up (`levelCap`).
  - **Wendung:** a hidden truth (forgery, stolen, cursed with an upside, famous previous owner) is stored in hidden.json like an NPC secret (key `★<item>`, text never contains the item name), guarded by the leak guard and revealed through the Spur/tier system. Payoff on reveal: **+1 SP**, the truth appears on the sheet.
- Players see only „★ Story-Item“ and, once grown, the level; the secret stays internal.

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
- **LP (Lebenspunkte, formerly "Wunden"; the count of remaining health, not of injuries):** 10 per PC.
  - 0 or less: down, and a Schicksalspunkt is needed to stay alive.
  - At ≤3 LP: −10 on everything.
- Initiative: everyone rolls d100 ≤ Kampf, and more DoS acts first. Simpler: players first, then opponents.

## Schicksalspunkte (SP), the "Fatedash"
- Start with **5**, max 5 (more via budget). The resource works like mana, for fate.
- **Spend** before the roll or right after it (before the result is narrated):
  - 1 SP = **±10** on a check, your own or **someone else's** (also an opponent's or an NPC's, to manipulate fate). At most 3 SP per check.
  - 1 SP = shift the **oracle odds** one step (e.g. offen → wahrscheinlich, or for an opponent worse).
  - 2 SP = **reroll** (the second roll stands).
  - 1 SP = survive at 0 LP (stays down, but alive).
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
- The −10 is its own modifier "Schicksalsergeben −10" in the calculation, not part of the difficulty. It stacks with traits, difficulty and the SP/LP thresholds (computed on the SP before the gain).
- Gain is capped at the SP maximum; at max the roll still counts as used.
- **Once per scene and figure:** a flag on the sheet, reset on `start_scene` / `end_scene`. A second use is refused ("in dieser Szene schon verbraucht").
- **Not on leicht checks** (refused by sl). "Real stakes", initiative and pure practice stay the GM's call.
- **Not combinable** with SP on the same roll: refused with 400 when `sp > 0`, 409 when pre-spent SP (`/sp mode=pre`) or SP from others (`mod`) are on the sheet.
- **Reroll (2 SP):** allowed; the second result counts, including its ergeben effects (an earlier SP gain is taken back, a failure gets +1 DoF again).
- **Foundry card:** shows "+1 SP (Schicksalsergeben)" / "Schicksalsschlag" only after sl confirmed in the `/rollresult` response; if sl refuses, the card shows the reason and no gain.
- **`/szene` (GM):** resets the once-per-scene flag of all figures (also via `start_scene`/`end_scene`); GM button "Neue Szene" in the bridge.
- Narrator fact: "[schicksalsergeben (−10), 1 SP zurück]" / "[… Schicksalsschlag, der Misserfolg wiegt einen Grad schwerer und wird härter erzählt]".
- API: `/roll` and `/rollresult` take `"ergeben": true`; replies and SSE `roll` carry `ergeben` and `sp_gained` (see API-foundry.md). Foundry: checkbox in the Probe dialog.
- Not covered by the explainer video (not re-rendered).

## Oracle (Schicksal, Mythic-like)
- Yes/no questions with odds (sicher … unmöglich) and tension/Spannung 1–9 → JA+ / JA / NEIN / NEIN+, plus event on doubles ≤ tension. Tables: `~/Projects/schicksal/Sources/Schicksal/Resources/tables_de_darkfantasy.json`.
- Spending SP shifts the odds by one step (see above).

## Content rule
- Minors are never victims of violence or of sexual content. Dark content among adults is fine.

## Probe flow in Foundry: "players roll"
In Foundry mode a risky action of a player is rolled by the player: sl sends `probe_request` (speaker, pillar, difficulty, reason, id), the bridge posts a card "Probe gefordert" with a button to the prefilled Probe dialog, and the player's `/rollresult` resolves the pending turn; sl narrates the result as a hard `[Fakt]`. If nobody rolls within the timeout (default 90 s, bridge setting or `--probe-timeout`) or the GM presses "sl würfeln lassen", sl rolls itself. The CLI/web UI (no speaker) keeps the auto roll. Deaths, `/lebt` and the minors content rule are unchanged (they act on the check result).
