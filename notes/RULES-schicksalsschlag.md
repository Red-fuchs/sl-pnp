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

## Oracle (Schicksal, Mythic-like)
- Yes/no questions with odds (sicher … unmöglich) and tension/Spannung 1–9 → JA+ / JA / NEIN / NEIN+, plus event on doubles ≤ tension. Tables: `~/Projects/schicksal/Sources/Schicksal/Resources/tables_de_darkfantasy.json`.
- Spending SP shifts the odds by one step (see above).

## Content rule
- Minors are never victims of violence or of sexual content. Dark content among adults is fine.
