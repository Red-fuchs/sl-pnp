# pnp-22 / pnp-22b / pnp-22c / pnp-22d release note (session 2026-10-22)
Tags: `pnp-22` = first state for the session (do not move). `pnp-22b` = earlier final state (annotated, left as is). **`pnp-22c` = final state** (sl-pnp and sl-foundry, annotated; adds tension rules + `/spannung`). Rollback to the state before pnp-22c: `git checkout pnp-22b` in both repos. Rollback: `git checkout pnp-22` (sl-pnp: `aa54365` is the last commit before the whole PnP work; ~/Projects/sl is untouched). sl-foundry: `git checkout pnp-22` is not defined there, use `git checkout 5715d4d` (state before pnp-22b).
API: notes/API-foundry.md. Rules: notes/RULES-schicksalsschlag.md. Foundry module docs: ~/Projects/sl-foundry/README.md.

## pnp-22d: setting "Fadenleihe / Die Weberin" (one-shot, 2026-10-22)
Temporary isekai: characters from any world are pulled into the Gramsmark by the Weberin (a power working "against Fate"), must fetch the Nadel from the Spindelhaus in one moon-run and must not draw Fate's attention. Twist: the Weberin IS the severed half of Fate. The GM plays a familiar ("der Kater", name slot) who only perceives what the party perceives.
- **Start sl with the world:** `SL_IDLE=1800 ./play.sh web --port 8787 --rules schicksal --rng jitter --welt weberin --name pnp-2026-10-22` (CLI: `./play.sh --welt weberin`). Or in a fresh session before the first turn: `/welt vorlage weberin`. The template lives in `worlds/weberin/` (`vorlage.json` narrator block + tier cues + Eingriff cue, `world.json`, `hidden.json`); search order `$SL_WORLDS`, `./worlds`, repo `worlds/`. It sets rules `schicksal`, Blick 3, opening scene at the Aschekreis. To rename the familiar, replace "Der Kater" in world.json and hidden.json (before the session starts).
- **Blick des Schicksals = Spannung.** Tiers 1-3 unbemerkt / 4-6 Fäden zittern / 7-8 Schicksalsboten / 9 Eingriff. Entering a new tier sends the narrator a hidden cue (never the number). At 9 the `[Regie verdeckt]` Eingriff cue goes out (Kettler / a thread snaps / paradox), `world.eingriffe` counts it and the tension resets to 5; the GM advances the clock and gives a Fadenmal by hand. `/spannung` works as before.
- **Fremdkraft:** `/merkmal +Fremdkraft: Hexenblick` = one per character, always a major positive trait (4 points, +20 on fitting checks). Every check (sl roll or Foundry `/rollresult`) that fits it raises the tension by 1 automatically, with an info line `Fremdkraft: <Name> nutzt <trait>. Blick des Schicksals a -> b` and a hidden narrator cue (threads tremble). A reroll does not count twice.
- **Familiar:** the GM speaks as a party member (speaker = the familiar's name). NPC `gmFigur` flag: the narrator never voices it or invents its perceptions (prompt block). Costs: whisper 0, `/vertrauter laut` +1, `/vertrauter eingriff` +2 (hidden cue each), Spindelhaus +1 by `/spannung +1`.
- **Material:** player PDF `tutorial/Schicksalsschlag-Spieler.pdf` (14 pages, setting on p. 2-3), GM sheet `handout/oneshot/Schicksalsschlag-OneShot-SL.pdf` (5 pages), single content source `handout/oneshot/content.py` (`python3 handout/oneshot/build.py` regenerates world seed, GM PDF and Foundry journals).
- **Foundry (not imported):** journal texts waiting in `handout/oneshot/foundry/`: `Die-Berufung_Spieler.html`, `Weberin-SL_nur-GM.html` (GM only), `Der-Kater_GM-Actor.html`.
- Tests: 205 green (`VorlageTests`: seed consistency, ContentRule, tiers, Fremdkraft, engine raise). Live check (headless sl on :8861 under gpu-run, scratch session weberin-live): world loads at Blick 3 with the Kater as gmFigur, Fremdkraft check 3 -> 4 -> 5 (unrelated check leaves it), `/spannung 8` then a Fremdkraft check gives 9 and the Eingriff reset to 5, `/vertrauter laut|eingriff` +1/+2, first narrated turn plays the Weberin without leaks. Note: the `/state` tension value only refreshes at scene/tool events, `/spannung` (no argument) shows the live value.
- Rollback: `git checkout pnp-22c`.

## What pnp-22c adds over pnp-22b
- Tension (Spannung): d6 brake dropped (always +-1 at scene end, also away from 5), +-2 for a clearly tipped scene (NEIN >= 3 and no JA, or event + failed check -> +2; JA >= 3 and no NEIN/event/failed check -> -2), bounds 1..9. Rules: notes/RULES-schicksalsschlag.md "Tension".
- GM control `/spannung +N | -N | N` (HTTP `POST /spannung`, Foundry GM button "Spannung" with dialog, chat command; players refused, value never shown to players); the narrator gets a hidden tone cue on change. API: notes/API-foundry.md.
- Handout (full) + tutorial updated; player handout unchanged (it does not mention tension).

## What pnp-22b adds over pnp-22
- GM purchase commands `/kauf`, `/taler`, `/gegenstand` (GM only, slash + HTTP), purse in Heller ("3 T 1 S 1 H"), `[Fakt]` for the narrator, GM button "Kauf". Taler/gear are one-way sl -> Foundry (hand edits are overwritten).
- Tutorial page + player handout: commands as typed in Foundry (`/sl /figur ...`), damage wording (a hit on a PC costs at least 1 LP), coins/shopping, new Mirne screenshots.
- Foundry sheet shows LP / SP captions, Probe dialog says "Zielzahl".

## Rehearsal 2026-10-21 (Foundry headless, scratch data dir, real sl on :8851, 2 players from Haiku action lists + GM)
- Tests: sl 193 (190 + 3 full-story), schicksal 41, node rules.test + t2 (mock e2e) + t8 (GM bookings) green; `test/livecheck.mjs` (now with /kauf, /taler, player refusal) green against real sl; `test/final.mjs` = Mirne screenshots + 10-turn session.
- Flow verified: /figur with full backstory (flaws and skills extracted), /merkmal, /saeulen, /budget (Armbrust becomes a star item), probe request -> player rolls -> narration, SP spend with GM approval, Schicksalsergeben (success +1 SP, failure = Schicksalsschlag), /szene, GM takeover, timeout fallback, oracle, /kauf (booked in sl, Foundry sheet follows, refused when too poor), player /taler refused, LP damage and LP write-back from Foundry, pause. No harness leaks.
- Timings (sl Gemma, M1 Max): narrated turn 9-16 s total (first token 3-4 s, 8-14 s for the first turn after a pause), probe turn incl. player roll ~10-15 s after the roll, GM booking card ~1 s, /figur with extraction ~25-40 s (model load from cold 2 s, then the GPU queue wait dominates), model stays warm 15 min idle.

## Start checklist (exact commands, in this order)
1. Tailscale (only for remote players): open the Tailscale app and sign in, then `~/Projects/sl-foundry/online.sh start` (prints the player URL `https://<mac>.<tailnet>.ts.net`; first time: approve Funnel via the link it shows, run again). Check with `online.sh status`.
2. sl for the session on 8787 (the bridge default; stop any other sl on 8787 first): `cd ~/Projects/sl-pnp && SL_IDLE=1800 ./play.sh web --port 8787 --rules schicksal --rng jitter --name pnp-2026-10-22` (take a GPU slot via the built-in lease; the model loads with the first turn, 1-2 min; after 30 min idle it unloads and reloads on the next turn). Resume after a crash: same line with `--resume pnp-2026-10-22`.
3. Foundry: start the Foundry app, launch the world (world "Schicksalsschlag", system Simple World-Building, modules SL-Bridge on). **The GM opens `http://localhost:30000`** (not the tailscale URL), otherwise the browser blocks the bridge to sl. Players use the Funnel URL or the LAN link.
4. Passwords: Foundry admin password = Setup > Configuration > Administrator Password (set it before `online.sh start`, otherwise the setup page is open to the internet). User passwords: in the world, User Management, give every player and the Gamemaster a password; delete unused users. (Passwords are not stored in any repo; hand them out per player.)
5. Per player: assign the figure (User Configuration > Character) after `/sl /figur Name: Geschichte` created it; the figure name must equal the sl name. Test `/sl Hallo`.
6. GM before the first scene: lamp green, one test turn so the model is warm; print or open `~/Projects/sl-pnp/handout/Schicksalsschlag-Spieler.pdf` (players) and the full handout (GM).
7. During play: tension by GM only: `/spannung 7`, `/spannung +1`, `/spannung -2` (or the button "Spannung"); it changes the narrator's tone, players never see the value. Bookings by GM only: `/kauf Name Ware Preis`, `/taler Name ±N[T|S|H]`, `/gegenstand Name +Text|-Text` (or button "Kauf"); `/szene` between scenes; "sl pausieren" if sl hangs.
8. After the session: `~/Projects/sl-foundry/online.sh stop`; stop sl (Ctrl-C in its terminal or `pkill -f "sl web --lease --idle .* --port 8787"`).
9. Never start two models at once: one sl instance at a time on the GPU.

## Known gaps
- Initiative, opposed rolls (use `/rollresult` / two Probe cards, GM compares), group targets; NPC LP default 6; `/rast` also heals LP (+1/+3, not in the spec).
- Purchases are narrated with the next turn (the `[Fakt]` waits for it); the GM books, players cannot. Prices come from the handout lists; sl does not check them.
- Hand edits of Taler / gear in Foundry are overwritten by sl (by design); hand-added gear without bridge flag stays only in Foundry.
- Character extraction by Gemma is model dependent: negatives are sometimes missed, fix with `/sl /merkmal`; `/merkmal`, `/budget` only before the first check.
- The worldbuilding system is verified up to Foundry v12 only (V1 application warnings in the console, works under v13).
- Cards of other players' sl commands are public chat.
- The chargen experiment (branch `chargen-v2`, worktree ~/Projects/sl-pnp-chargen) is NOT part of pnp-22b.

## pnp-22e (2026-10-21, Spieltest-Fixes)
- Foundry-Bridge: Probe-Knopf auch bei eingeklappter v13-Seitenleiste (schwebender Knopf am Chat-Eingabefeld; die Leiste lag bei 1622 px ausserhalb des Bildschirms), Eigenschaften-Haken mit Hinweis "Noch keine Eigenschaften", Situationsbonus ±10/±20 nur für die SL, Neuwurf (2 SP) Knopf auf der Ergebniskarte (`POST /sp mode=reroll`).
- sl: `foundryRoll` merkt jetzt jede Foundry-Probe als `lastCheck` (vorher nur Schicksalsergeben), damit der Neuwurf die richtige Probe trifft; `SR.reroll` (einmal pro Probe, 2 SP, Ergebnis mit `source:"neuwurf"` und Grund "(Neuwurf)"). Test `testErgeben` erweitert, 205 Tests grün.
- Hinweis: bei "sl würfeln lassen" kann sl über den Anlass-Text zusätzlich passende Eigenschaften anrechnen (Wortabgleich im Harness).
