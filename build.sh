#!/bin/sh
# Metal shaders (mlx) need the Xcode toolchain's `metal`; CommandLineTools alone fails with "unable to spawn process 'metal'".
# First time: xcodebuild -downloadComponent MetalToolchain (if Xcode reports it missing).
cd "$(dirname "$0")"
./build-llg.sh || exit 1
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
swift build -c release "$@" && echo "ok: .build/release/sl (metallib in .build/release/mlx-swift_Cmlx.bundle, keep next to the binary)"
