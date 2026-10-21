# sl HTTP API for the Foundry bridge (contract v1, 2026-10-21)

Base: `http://127.0.0.1:<port>` (`sl web --port N --rules schicksal`). JSON in and out, UTF-8. All POSTs need the header `x-sl: 1` (CSRF guard, unchanged).
CORS: `Access-Control-Allow-Origin` is echoed for `http://localhost:30000`, `http://127.0.0.1:30000` and any `http://192.168.*|10.*|172.16-31.*:30000` (LAN host of Foundry); methods GET, POST, OPTIONS; headers `content-type, x-sl`. `OPTIONS` preflight answers 204.
Single-player behaviour is unchanged when `speaker` is absent.

## POST /say
`{ "text": String, "speaker"?: String }` -> `202 ok`. The player turn runs asynchronously; progress comes through SSE. `speaker` = party member name (created on first use as a PC). Slash commands (`/ende`, `/welt ...`) work as before (speaker ignored).
Busy: SSE `info` "SL denkt noch" and the text is dropped (same as today).

## POST /roll   (harness d100, schicksal engine RNG)
`{ "speaker": String, "pillar"?: "kampf"|"sozial"|"wissen", "traits"?: [String], "difficulty"?: Int, "sp"?: Int, "ergeben"?: Bool, "reason"?: String }`
- target = pillar value + fitting traits (+10/+20, negative -10/-20; trait words matched against the speaker's sheet) + `difficulty` (leicht +20, normal 0, schwer -20, sehr schwer -30; any integer accepted) + SP penalties (SP<=1: -10, SP 0: -20) + Wunden penalty (<=3 Wunden: -10).
- `sp`: Schicksalspunkte spent now, each +10 on this roll (max 3, capped by the speaker's SP); negative `sp` is not allowed (use /sp with `target`).
- Response `200`: `{ "speaker", "pillar", "reason", "target": Int, "roll": Int, "success": Bool, "dos": Int, "dof": Int, "crit": "success"|"failure"|null, "sp_left": Int }`
  - `dos` = 1 + floor((target-roll)/10) on success (else 0); `dof` = 1 + floor((roll-target)/10) on failure (else 0); 01-05 always success, 96-100 always failure; doubles (11..99, 100) make `crit`.
- `ergeben` (Schicksalsergeben, see RULES-schicksalsschlag.md): -10 as its own modifier; at >= 2 DoS the speaker gets 1 SP back (capped at spMax), a failure gets `dof + 1` (also crit/96-100). Response and SSE `roll` additionally carry `"ergeben": Bool, "sp_gained": Int` (`sp_left` is after the gain); SSE `sheet` follows. Errors (nothing rolled, nothing changed), body `{ "error": German text }`: `400` with `sp > 0` (not combinable), on `difficulty > 0` (leicht), or when already used this scene (once per scene and figure, reset on start_scene/end_scene); `409` when the speaker has pre-spent SP (`/sp mode=pre`) or SP from others (`mod`) pending.
- Side effects: SSE `roll`; the result is stored as a hard fact for the next narration of that speaker's turn ("[Fakt] Probe Kampf: 3 Grad Erfolg ...").

## POST /rollresult   (roll made in Foundry)
`{ "speaker": String, "label": String, "target": Int, "roll": Int, "ergeben"?: Bool, "difficulty"?: Int, "sp"?: Int }` -> `200 { "success", "dos", "dof", "crit", "label", "ergeben", "sp_gained" }`. With `ergeben: true` Foundry has already put the -10 into `target`; sl applies DoF+1 / the SP gain and emits `sheet` (Foundry takes the new SP from there, no local write). Same refusals as `/roll` (`400` for `sp > 0`, `difficulty > 0`, already used; `409` pending SP/mod; `404` unknown speaker). sl computes the degrees with the same rules and queues them as a hard fact for the next narration (also emits SSE `roll` with `source:"foundry"`).

## POST /regie
`{ "text": String }` -> `202`. Hidden GM note, injected once into the next narration (never shown to players).

## POST /sp
`{ "speaker": String, "delta": Int, "target"?: String, "mode"?: String }` -> `200 { "name", "sp", "spMax", "pending": Int }`
- default (`mode` absent / `"adjust"`): GM grant/removal, `sp += delta` (clamped 0..spMax).
- `"pre"`: speaker pre-spends `delta` (>0) SP on their next check (+10 each, max 3). `"reroll"`: spends 2 SP to reroll the speaker's last check. `"orakel"`: spends `delta` SP to shift the next oracle odds that many steps. `"survive"`: spends 1 SP to stay alive at 0 Wunden.
- `target` = another party member or NPC name: the speaker spends SP so that target's next check gets `delta*10` (positive helps, negative hurts, 1 SP per +-10).
- Emits SSE `sheet`.

## POST /wunden   (Wunden edited in Foundry)
`{ "speaker": String, "delta"?: Int, "set"?: Int }` (`set` wins) -> `200 { "name", "wunden", "wundenMax" }`; value clamped to -5...wundenMax; `404` unknown speaker. Equivalent: `POST /sp {speaker, delta, mode:"wunden"}`. Emits SSE `sheet`.

## GET /state
Existing fields unchanged, plus `"party": [ { "name", "pillars": {"kampf","sozial","wissen"}, "traits": [ {"text","kind":"minor|major","pos":Bool} ], "sp", "spMax", "wunden", "inventar": [String], "taler": Int } ]` (empty array when no party).

## GET /events  (SSE, `data: {json}\n\n`)
Typed events (`t`): `narr` {d: chunk, speaker?}, `narr_end`, `roll` {speaker, pillar, reason, target, roll, success, dos, dof, crit, sp_left, source?, ergeben, sp_gained}, `oracle` {q, answer, odds, p, roll}, `sheet` {party: [...as in /state]}, `info` {text}. The legacy events (`delta`, `end`, `retract`, `tool`, `event`, `world`, `state`, `user`) keep being sent for the built-in web UI; `narr`/`narr_end` mirror `delta`/`end`. `retract` also drops text already sent as `narr`.

## Errors
`400 {"error": "..."}` bad JSON / missing field; `404` unknown speaker for /sp; `409 {"error":"busy"}` only for /say while a turn runs.
