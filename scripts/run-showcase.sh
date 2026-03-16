#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! launchctl print "gui/$(id -u)/com.stevemurr.fabric.broker" >/dev/null 2>&1; then
  echo "Fabric broker LaunchAgent is not running."
  echo "Install it first with ./scripts/install-launch-agent.sh"
  exit 1
fi

swift build --target FabricShowcase
binary=".build/debug/FabricShowcase"

if [[ ! -x "$binary" ]]; then
  echo "Expected showcase binary at $binary"
  exit 1
fi

"$binary" --role browser >/tmp/fabric-showcase-browser.log 2>&1 &
"$binary" --role notes >/tmp/fabric-showcase-notes.log 2>&1 &
"$binary" --role lens >/tmp/fabric-showcase-lens.log 2>&1 &

echo "Launched FabricShowcase roles:"
echo "  browser -> /tmp/fabric-showcase-browser.log"
echo "  notes   -> /tmp/fabric-showcase-notes.log"
echo "  lens    -> /tmp/fabric-showcase-lens.log"
