#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Running Swift Package tests (IMap)"
swift test --package-path IMap

echo "==> Building app target"
xcodebuild \
  -project umaptest.xcodeproj \
  -scheme umaptest \
  -destination "generic/platform=iOS Simulator" \
  build

echo "Quality gate passed."
