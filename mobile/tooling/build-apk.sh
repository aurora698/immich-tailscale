#!/usr/bin/env bash
# Build the debug APK from a fresh clone.
#
# Generated sources (openapi SDK, pigeon bindings, freezed/drift/router,
# i18n loader) are vendored in this fork, so no bootstrap step is required.
# Host-specific concerns (PUB_HOSTED_URL mirror, local Gradle zip) are applied
# by the caller, never committed.
#
# Usage:  bash mobile/tooling/build-apk.sh [--release]
set -euo pipefail

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MOBILE"

MODE="--debug"
[[ "${1:-}" == "--release" ]] && MODE="--release"

flutter build apk "$MODE" --target-platform=android-arm64
echo "APK: $MOBILE/build/app/outputs/flutter-apk/app-${MODE#--}.apk"
