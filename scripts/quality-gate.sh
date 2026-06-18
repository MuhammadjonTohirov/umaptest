#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

echo "==> Running IMap tests"
xcodebuild \
  -project umaptest.xcodeproj \
  -scheme IMapTests \
  -destination "$IOS_DESTINATION" \
  test

echo "==> Building app target"
xcodebuild \
  -project umaptest.xcodeproj \
  -scheme umaptest \
  -destination "generic/platform=iOS Simulator" \
  build

echo "Quality gate passed."
