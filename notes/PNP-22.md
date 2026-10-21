# pnp-22 / pnp-22b release note (session 2026-10-22)
Tags: `pnp-22` = first state for the session (do not move). **`pnp-22b` = final state** (sl-pnp and sl-foundry, annotated). Rollback: `git checkout pnp-22` (sl-pnp: `aa54365` is the last commit before the whole PnP work; ~/Projects/sl is untouched). sl-foundry: `git checkout pnp-22` is not defined there, use `git checkout 5715d4d` (state before pnp-22b).
API: notes/API-foundry.md. Rules: notes/RULES-schicksalsschlag.md. Foundry module docs: ~/Projects/sl-foundry/README.md.

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
7. During play: bookings by GM only: `/kauf Name Ware Preis`, `/taler Name ±N[T|S|H]`, `/gegenstand Name +Text|-Text` (or button "Kauf"); `/szene` between scenes; "sl pausieren" if sl hangs.
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
