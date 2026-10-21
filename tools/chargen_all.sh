#!/bin/bash
# usage (inside gpu-run): chargen_all.sh PERSONA_DIR OUT_DIR [modes...]   one model instance at a time, one server per mode
cd "$(dirname "$0")/.." || exit 1
P=$1; O=$2; shift 2; MODES=${@:-a b c bc}; port=8841
for m in $MODES; do
  ./.build/release/sl web --port $port --rules schicksal --chargen $m --fullstory --rng jitter --name chargen-$m-$(date +%H%M%S) --idle 1500 > $O/server-$m.log 2>&1 &
  pid=$!
  for i in $(seq 1 120); do curl -s -o /dev/null http://127.0.0.1:$port/state && break; sleep 1; done
  python3 tools/chargen_run.py $port $m $P $O > $O/run-$m.log 2>&1
  kill $pid; wait $pid 2>/dev/null; port=$((port+1))
done
