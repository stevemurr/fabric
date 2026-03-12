#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
EXECUTABLE="$BUILD_DIR/FabricBrokerRuntime"
PLIST_DEST="$HOME/Library/LaunchAgents/com.stevemurr.fabric.broker.plist"

cd "$ROOT_DIR"
swift build -c release
"$EXECUTABLE" --describe > "$PLIST_DEST"
launchctl unload "$PLIST_DEST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DEST"
echo "Installed launch agent at $PLIST_DEST"
