#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-device}"
case "$mode" in
  device) target=aarch64-apple-ios; platform=iphoneos ;;
  simulator) target=aarch64-apple-ios-sim; platform=iphonesimulator ;;
  host)
    cargo build --locked --manifest-path native/Cargo.toml --release --features test-server
    mkdir -p build/native/host
    cp native/target/release/libankipad_bridge.dylib native/target/release/sync_test_server build/native/host/
    exit ;;

  *) echo 'Usage: build-native.sh [device|simulator|host]' >&2; exit 2 ;;
esac
rustup target add "$target"
# Prevent the host macOS SDK leaking into the cross-compiled C dependencies.
export SDKROOT="$(xcrun --sdk "$platform" --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET=18.0
cargo build --locked --manifest-path native/Cargo.toml --release --lib --target "$target"
mkdir -p "build/native/$platform"
cp "native/target/$target/release/libankipad_bridge.a" "build/native/$platform/"
