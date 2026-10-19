#!/bin/bash
# Run sl through the shared GPU queue (gpu-run). gpu-run starts the job in the background -> its stdin is /dev/null,
# so input is passed explicitly: piped stdin is spooled to a temp file, a tty is reopened via /dev/tty (sl --input).
# usage: ./play.sh [sl args...]   e.g. ./play.sh --resume   |   ./play.sh web --port 8787   |   printf 'a\nb\n' | ./play.sh --rng jitter
cd "$(dirname "$0")"
BIN=.build/release/sl; [ -x $BIN ] || { echo "erst ./build.sh" >&2; exit 1; }
if [ -t 0 ]; then IN=/dev/tty; else IN=$(mktemp -t sl-in); cat > "$IN"; trap 'rm -f "$IN"' EXIT; fi
gpu-run --status >&2
exec_label=sl; [ "$1" = web ] && exec_label=sl-web
gpu-run -n $exec_label --ram ${SL_RAM:-10} $BIN "$@" --input "$IN"
