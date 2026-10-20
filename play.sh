#!/bin/bash
# Run sl. The GPU slot is NOT held for the whole process: with --lease sl takes a gpu-run slot (a small holder job under
# `gpu-run -n sl|sl-web --ram 10`) only while the model is loaded, and gives it back after SL_IDLE seconds idle (default 300).
# The next turn re-queues ("warte auf GPU …"), reloads the model and rebuilds the context from the saved history.
# usage: ./play.sh [sl args...]   e.g. ./play.sh --resume   |   ./play.sh web --port 8787   |   printf 'a\nb\n' | ./play.sh --rng jitter
# Jobs that already run inside gpu-run (tests, scripts) call .build/release/sl WITHOUT --lease.
cd "$(dirname "$0")"
BIN=.build/release/sl; [ -x $BIN ] || { echo "erst ./build.sh" >&2; exit 1; }
if [ "$1" = web ]; then shift; exec $BIN web --lease ${SL_IDLE:+--idle $SL_IDLE} "$@"; fi
exec $BIN --lease ${SL_IDLE:+--idle $SL_IDLE} "$@"
