#!/bin/bash
# Build the app, launch it on one simulator, and fail if a DEBUG self-check assert crashed it.
# Usage: frontend/scripts/selfcheck.sh SIMULATOR_UDID   (each agent uses its own simulator)
set -euo pipefail
UDID=${1:?usage: selfcheck.sh SIMULATOR_UDID}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DD=${TMPDIR:-/tmp}/declutter-dd-$(echo "$ROOT" | shasum | cut -c1-8)  # one build folder per checkout

xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild -project "$ROOT/Declutter.xcodeproj" -scheme Declutter -destination "id=$UDID" \
    -derivedDataPath "$DD" build -quiet
xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/Declutter.app"
PID=$(xcrun simctl launch --terminate-running-process "$UDID" com.declutter.app | awk '{print $NF}')
sleep 5
if kill -0 "$PID" 2>/dev/null; then
    echo "self-checks passed (app still running, pid $PID)"
else
    echo "app exited within 5 s: a self-check failed (see the crash log in Console)" >&2
    exit 1
fi
