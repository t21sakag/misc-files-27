#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
for sync_port in 18891 18901; do
  SYNC_USER1='fixture@example.test:fixture-password' SYNC_USER2='empty@example.test:fixture-password' SYNC_HOST=127.0.0.1 SYNC_PORT="$sync_port" SYNC_BASE="$RUNNER_TEMP/ui-sync-server-$sync_port" build/native/host/sync_test_server > "build/ui-sync-server-$sync_port.log" 2>&1 &
  python3 tests/seed_ui_sync.py build/native/host/libankipad_bridge.dylib build/fixture.apkg "$sync_port"
  python3 tests/delayed_sync_proxy.py --port "$((sync_port + 2))" --upstream-port "$sync_port" > "build/delayed-sync-proxy-$sync_port.log" 2>&1 &
done
python3 tests/shared_deck_fixture.py build/native/host/libankipad_bridge.dylib build/shared-fixture.apkg > build/shared-deck-server.log 2>&1 &
python3 tests/make_occlusion_image.py build/occlusion-fixture.png
