# pnp-22 release note
Tag `pnp-22` = state for the 2026-10-22 Foundry session. Rollback: `git checkout aa54365` (last good commit before the PnP work: v7 d, single-player sl; original repo ~/Projects/sl is untouched at the same commit).
Start: `./play.sh web --port 8787 --rules schicksal --rng jitter --name <session>` (mic RNG falls back automatically when the microphone is silent). API: notes/API-foundry.md. Rules: notes/RULES-schicksalsschlag.md.
Known gaps: Initiative, opposed rolls (use /rollresult from Foundry), group targets; NPC Wunden default 6; /rast also heals Wunden (+1/+3, not in the spec).
