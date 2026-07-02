#!/usr/bin/env bash
# Fast build+test loop driver for TopManager.
# Usage:
#   scripts/test.sh build   # compile only (fast gate)
#   scripts/test.sh test    # compile + run unit tests
#   scripts/test.sh         # same as "test"
set -euo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-test}"
DEST='platform=macOS,arch=arm64'
COMMON=(-project TopManager.xcodeproj -scheme TopManager -configuration Debug -destination "$DEST" CODE_SIGNING_ALLOWED=NO)

case "$ACTION" in
  build)
    xcodebuild "${COMMON[@]}" build 2>&1 | tail -20
    ;;
  test)
    xcodebuild "${COMMON[@]}" test 2>&1 \
      | grep -E "Test Suite|Executed|error:|warning:.*unused|BUILD|TEST (SUCCEEDED|FAILED)|failed \(" \
      | tail -40
    ;;
  *)
    echo "unknown action: $ACTION" >&2; exit 2 ;;
esac
