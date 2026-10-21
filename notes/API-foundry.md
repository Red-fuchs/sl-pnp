# sl HTTP API for the Foundry bridge (contract v1, 2026-10-21)

Base: `http://127.0.0.1:<port>` (`sl web --port N --rules schicksal`). JSON in and out, UTF-8. All POSTs need the header `x-sl: 1` (CSRF guard, unchanged).
CORS: `Access-Control-Allow-Origin` is echoed for `http://localhost:30000`, `http://127.0.0.1:30000` and any `http://192.168.*|10.*|172.16-31.*:30000` (LAN host of Foundry); methods GET, POST, OPTIONS; headers `content-type, x-sl`. `OPTIONS` preflight answers 204.
Single-player behaviour is unchanged when `speaker` is absent.

## POST /say
`{ "text": String, "speaker"?: String }` -> `202 ok`. The player turn runs asynchronously; progress comes through SSE. `speaker` = party member name (created on first use as a PC). Slash commands (`/ende`, `/welt ...`) work as before (speaker ignored).
Busy: SSE `info` "SL denkt noch" and the text is dropped (same as today).

## POST /roll   (harness d100, schicksal engine RNG)
`{ "speaker": String, "pillar"?: "kampf"|"sozial"|"wissen", "traits"?: [String], "difficulty"?: Int, "sp"?: Int, "ergeben"?: Bool, "reason"?: String }`
- target = pillar value + fitting traits (+10/+20, negative -10/-20; trait words matched against the speaker's sheet) + `difficulty` (leicht +20, normal 0, schwer -20, sehr schwer -30; any integer accepted) + SP penalties (SP<=1: -10, SP 0: -20) + LP penalty (<=3 LP: -10).
- `sp`: Schicksalspunkte spent now, each +10 on this roll (max 3, capped by the speaker's SP); negative `sp` is not allowed (use /sp with `target`).
- Response `200`: `{ "speaker", "pillar", "reason", "target": Int, "roll": Int, "success": Bool, "dos": Int, "dof": Int, "crit": "success"|"failure"|null, "sp_left": Int }`
  - `dos` = 1 + floor((target-roll)/10) on success (else 0); `dof` = 1 + floor((roll-target)/10) on failure (else 0); 01-05 always success, 96-100 always failure; doubles (11..99, 100) make `crit`.
- `ergeben` (Schicksalsergeben, see RULES-schicksalsschlag.md): -10 as its own modifier; at >= 2 DoS the speaker gets 1 SP back (capped at spMax), a failure gets `dof + 1` (also crit/96-100). Response and SSE `roll` additionally carry `"ergeben": Bool, "sp_gained": Int` (`sp_left` is after the gain); SSE `sheet` follows. Errors (nothing rolled, nothing changed), body `{ "error": German text }`: `400` with `sp > 0` (not combinable), on `difficulty > 0` (leicht), or when already used this scene (once per scene and figure, reset on start_scene/end_scene); `409` when the speaker has pre-spent SP (`/sp mode=pre`) or SP from others (`mod`) pending.
- Side effects: SSE `roll`; the result is stored as a hard fact for the next narration of that speaker's turn ("[Fakt] Probe Kampf: 3 Grad Erfolg ...").

## POST /rollresult   (roll made in Foundry)
`{ "speaker": String, "label": String, "target": Int, "roll": Int, "ergeben"?: Bool, "difficulty"?: Int, "sp"?: Int }` -> `200 { "success", "dos", "dof", "crit", "label", "ergeben", "sp_gained" }`. With `ergeben: true` Foundry has already put the -10 into `target`; sl applies DoF+1 / the SP gain and emits `sheet` (Foundry takes the new SP from there, no local write). Same refusals as `/roll` (`400` for `sp > 0`, `difficulty > 0`, already used; `409` pending SP/mod; `404` unknown speaker). sl computes the degrees with the same rules and queues them as a hard fact for the next narration (also emits SSE `roll` with `source:"foundry"`).

## Probe flow (players roll in Foundry)
- A `/say` with `speaker` that triggers a risky/lethal action under `schicksal` does NOT auto-roll: the turn waits and SSE `probe_request` `{speaker, pillar, difficulty, reason, id, timeout}` is sent. `/say` accepts `"probe_timeout"` (seconds; absent = sl flag `--probe-timeout`, default 90; 0 = sl always rolls itself). Without `speaker` (CLI / built-in web UI) sl rolls as before.
- `POST /rollresult` or `POST /roll` with `"id"` resolves the pending turn (the result is narrated as `[Fakt]`, no second fact is queued). `409 {error, stale:true}` when the probe is already closed (timeout, GM takeover, rolled): no second roll counts. `409` when the id belongs to another figure. Refusals (ergeben etc.) leave the probe pending.
- `POST /probe/auto {id}`: GM "sl würfeln lassen" -> sl rolls itself (`200 {ok}`, else `409 stale`).
- SSE `probe_done {id, how}` with `how` = `player` | `sl` | `timeout` closes the request (sl rolling itself also emits `roll` with `source:"sl"`).
- While a probe is pending sl is busy: other `/say` get "SL denkt noch" (the bridge re-queues them). Rolls with an id must bypass that queue.
- `/rollresult` response additionally carries `sp_left` and `probe`.

## Slash command `/szene` (GM)
`POST /say {text:"/szene"}`: resets the Schicksalsergeben flag of all figures (same as `start_scene`/`end_scene`), emits `sheet` and an `info`.

## Story items
`GET /state` and SSE `sheet`: each party member additionally has `items: [{name, level}]` (the ★ Story-Items among `inventar`; the secret is never sent).

## GM purchase commands: /taler, /gegenstand, /kauf (pnp-22b)
sl books purchases, loot and pay; the narrator does not change the sheet by itself. These commands are **GM only**: the bridge sends them from the GM browser (slash commands `/taler ...`, `/gegenstand ...`, `/kauf ...` typed by the GM, or the GM button "Kauf"); a player's `/sl /taler ...` is refused by the bridge whitelist ("nur für die Spielleitung"). sl itself trusts its loopback API like `/sp geben`. Only under `--rules schicksal`.

**Currency.** 1 Taler (T) = 2 Schilling (S) = 4 Heller (H). The purse is stored in Heller (`Pc.heller`, optional in the save: older saves without it derive it from `taler` x 4; the old `taler` field stays as the whole-Taler mirror). Display "3 T 1 S 1 H" (zero parts omitted, empty purse "0 H"). Amount syntax: `N[T|S|H]`, several parts may follow each other (`1T 1S`, `3T1S1H`); no unit = Taler. Any direct write of `taler` (`/budget`, `/merkmal`, chargen) resets the Heller part, so budget Taler stay whole Taler.

| Command | Effect |
|---|---|
| `/taler <Name> +N[T\|S\|H]` / `-N[...]` | purse plus/minus; `/taler Mirne -40`, `/taler Mirne +1S`. Refused (nothing changes) when the purse would go below 0. |
| `/gegenstand <Name> +Text` / `-Text` | adds / removes an inventory entry (remove: exact name first, then a part of the name; a matching Story-Item star goes with it). Max 40 entries. |
| `/kauf <Name> <Ware> <Preis>` | pays and adds the item in one step: `/kauf Mirne Seil 1S`. The price is the trailing amount (always give the unit). Refused ("kann sich ... nicht leisten", nothing booked, nothing queued) when the purse is too small. |

`<Name>` is matched against figure names / speakers, longest name first (so "Mirne Aschenbach" works). Every success emits SSE `sheet` (Foundry syncs) and an `info` line (the chat card). `/kauf` additionally queues a hard fact for the next narration of any speaker: `[Fakt] Mirne kauft Seil für 1 S und hat danach noch 1 T 1 S. Erwähne den Kauf kurz.` (narrated with the next turn, not at once).

**HTTP** (JSON, header `x-sl: 1`): `POST /taler {speaker, betrag:"-40"|"+1S"|"-1T 1S"}` (or `delta_h` in Heller); `POST /gegenstand {speaker, add:"Fackel"}` or `{speaker, remove:"Fackel"}`; `POST /kauf {speaker, ware, preis:"1S"}` (or `preis_h` in Heller). Reply `200 {ok:true, message, name, heller, taler, geld, inventar}`; `409 {ok:false, message}` when refused (cannot afford, full); `400 {error: usage}`; `404` unknown speaker; `409` outside `schicksal`. The `message` is also sent as `info`.

`GET /state` and SSE `sheet`: each party member additionally has `heller` (Int) and `geld` (String "3 T 1 S 1 H"); `taler` stays (whole Taler, rounded down).

### Sync direction (important)
Sheet data flows **sl -> Foundry only** for Taler and gear. Foundry writes back to sl exactly two things: SP (`POST /sp`) and LP (`POST /wunden`). Consequences:
- A manual edit of the Taler / Geld attribute or deletion of a gear item in Foundry is **not** pushed to sl. The bridge warns the GM ("bitte /taler, /gegenstand oder /kauf benutzen") and re-syncs, so the sl value overwrites the edit within about a second (at the latest at the next 30 s poll). Gear items the GM adds by hand in Foundry (no bridge flag) stay in Foundry but sl does not know them.
- Recommended and consistent way: the GM uses the commands (or the "Kauf" button), sl books, `sheet` follows.
- sl never pushes a stale value: every command changes the sl state first and emits `sheet` afterwards; Foundry applies the whole party snapshot in order.

## POST /regie
`{ "text": String }` -> `202`. Hidden GM note, injected once into the next narration (never shown to players).

## POST /spannung   (GM)
`{ "set": Int }` | `{ "delta": Int }` | `{ "text": "8" | "+2" | "-1" }` -> `200 { "ok": true, "s_before": Int, "s": Int }`; the value is clamped to 1..9; `400` for anything else. Same as the chat command `/spannung N | +N | -N` (via `/say`, GM only in the Foundry bridge: the player whitelist does not contain it). Effects:
- SSE `state` (with `"s"`) and SSE `info` "Spannung 5 → 8" (the bridge hides this info line from the chat; the value is never shown to players). `GET /state` carries `"s"`.
- On a change the next narration gets a hidden cue (like `/regie`, no number): rising = denser, more threatening; falling = calmer.
- Scene-end tension: no d6 brake any more, always +-1, +-2 for a clearly tipped scene (NEIN >= 3 and no JA, or event plus failed check -> +2; JA >= 3 and no NEIN/event/failed check -> -2). Details: RULES-schicksalsschlag.md "Tension".
- Foundry: GM chat command `/spannung [N|+N|-N]` (no argument opens the dialog) and the toolbar button "Spannung" (current value, -/+, set field).

## POST /sp
`{ "speaker": String, "delta": Int, "target"?: String, "mode"?: String }` -> `200 { "name", "sp", "spMax", "pending": Int }`
- default (`mode` absent / `"adjust"`): GM grant/removal, `sp += delta` (clamped 0..spMax).
- `"pre"`: speaker pre-spends `delta` (>0) SP on their next check (+10 each, max 3). `"reroll"`: spends 2 SP to reroll the speaker's last check. `"orakel"`: spends `delta` SP to shift the next oracle odds that many steps. `"survive"`: spends 1 SP to stay alive at 0 LP.
- `target` = another party member or NPC name: the speaker spends SP so that target's next check gets `delta*10` (positive helps, negative hurts, 1 SP per +-10).
- Emits SSE `sheet`.

## POST /wunden, POST /lp   (LP edited in Foundry)
Since 2026-10-21 the stat is called **LP** (Lebenspunkte, formerly "Wunden"); same numbers and mechanics. For compatibility the endpoint `/wunden` and the JSON keys `wunden`/`wundenMax` stay; `POST /lp` is an identical alias and every response mirrors the values as `lp`/`lpMax`. The slash commands `/lp` and `/wunden` are equivalent.
`{ "speaker": String, "delta"?: Int, "set"?: Int }` (`set` wins) -> `200 { "name", "wunden", "wundenMax", "lp", "lpMax" }`; value clamped to -5...wundenMax; `404` unknown speaker. Equivalent: `POST /sp {speaker, delta, mode:"wunden"}`. Emits SSE `sheet`.

## GET /state
Existing fields unchanged, plus `"party": [ { "name", "pillars": {"kampf","sozial","wissen"}, "traits": [ {"text","kind":"minor|major","pos":Bool} ], "sp", "spMax", "wunden", "lp", "lpMax", "inventar": [String], "taler": Int } ]` (empty array when no party).

## GET /events  (SSE, `data: {json}\n\n`)
Typed events (`t`): `narr` {d: chunk, speaker?}, `narr_end`, `roll` {speaker, pillar, reason, target, roll, success, dos, dof, crit, sp_left, source?, ergeben, sp_gained}, `oracle` {q, answer, odds, p, roll}, `sheet` {party: [...as in /state]}, `info` {text}. The legacy events (`delta`, `end`, `retract`, `tool`, `event`, `world`, `state`, `user`) keep being sent for the built-in web UI; `narr`/`narr_end` mirror `delta`/`end`. `retract` also drops text already sent as `narr`.

## Errors
`400 {"error": "..."}` bad JSON / missing field; `404` unknown speaker for /sp; `409 {"error":"busy"}` only for /say while a turn runs.

## Neuwurf via POST /sp (mode reroll)
`{speaker, delta: 2, mode: "reroll"}` rerolls the speaker's last check (also one made in Foundry via /rollresult, which now stores `lastCheck`): -2 SP, same target, the second result counts (ergeben effects re-settled). `200` + SSE `roll` with `source:"neuwurf"` and `reason` ending in " (Neuwurf)", then `sheet`. `409 {error}` when SP < 2, no earlier check, or the last check already was a Neuwurf (once per check).
