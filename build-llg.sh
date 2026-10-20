#!/bin/sh
# Builds llguidance (Rust, C API) into vendor/llg/{libllguidance.a,llguidance.h}. Needs cargo + git. Target dir lives outside the repo and is removed afterwards (KEEP_TARGET=1 to keep).
set -e
cd "$(dirname "$0")"
TAG=${LLG_TAG:-v1.9.1}
COMMIT=${LLG_COMMIT:-6cef6ed9c973c2a155a85f2bb1996320af28b289}
CACHE=${LLG_CACHE:-$HOME/.cache/sl-llg}
SRC=$CACHE/src; export CARGO_TARGET_DIR=$CACHE/target
if [ -f vendor/llg/libllguidance.a ] && [ "$(cat vendor/llg/VERSION 2>/dev/null)" = "$COMMIT" ] && [ -z "$FORCE" ]; then echo "llg up to date ($TAG)"; exit 0; fi
mkdir -p "$CACHE" vendor/llg
[ -d "$SRC/.git" ] || git clone -q https://github.com/guidance-ai/llguidance.git "$SRC"
git -C "$SRC" fetch -q --tags origin 2>/dev/null || true
git -C "$SRC" checkout -q "$COMMIT"
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "commit mismatch" >&2; exit 1; }
(cd "$SRC" && cargo build --release -p llguidance --lib --locked 2>&1 | tail -3 || cargo build --release -p llguidance --lib 2>&1 | tail -3)
cp "$CARGO_TARGET_DIR/release/libllguidance.a" vendor/llg/
strip -S vendor/llg/libllguidance.a 2>/dev/null || true
cp "$SRC/parser/llguidance.h" vendor/llg/ && cp "$SRC/parser/llguidance.h" Sources/CLlguidance/include/llguidance.h
echo "$COMMIT" > vendor/llg/VERSION
[ -n "$KEEP_TARGET" ] || rm -rf "$CARGO_TARGET_DIR"
echo "ok: vendor/llg/libllguidance.a ($TAG)"
