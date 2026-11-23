#!/usr/bin/env bash
# Builds the tsnet bridge into mobile/android/app/libs/tsbridge.aar with gomobile.
#
# Needs: Go (>= 1.24), an Android NDK, and a JDK to run gobind. Run it from
# anywhere; it always writes into the app module next to this directory.
set -euo pipefail
cd "$(dirname "$0")"

ANDROID_API=26
TARGETS=android/arm64,android/amd64
OUT=../app/libs/tsbridge.aar

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    [[ -n "$candidate" && -d "$candidate/ndk" ]] || continue
    ANDROID_NDK_HOME="$candidate/ndk/$(ls "$candidate/ndk" | sort -V | tail -1)"
    break
  done
fi
if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "error: set ANDROID_NDK_HOME (or ANDROID_HOME with an installed NDK)" >&2
  exit 1
fi
export ANDROID_NDK_HOME

export PATH="$(go env GOPATH)/bin:$PATH"
if ! command -v gomobile >/dev/null; then
  echo "==> installing gomobile and gobind"
  (cd "$(mktemp -d)" && go install golang.org/x/mobile/cmd/gomobile@latest golang.org/x/mobile/cmd/gobind@latest)
fi

echo "==> go mod tidy"
go mod tidy

# gomobile refuses to bind unless x/mobile is a tool dependency of the module.
if ! grep -q "tool golang.org/x/mobile/cmd/gobind" go.mod; then
  go get -tool golang.org/x/mobile/cmd/gobind
fi

echo "==> gomobile init"
gomobile init

echo "==> gomobile bind -> $OUT"
mkdir -p "$(dirname "$OUT")"
gomobile bind \
  -target="$TARGETS" \
  -androidapi "$ANDROID_API" \
  -javapkg=app.alextran.immich \
  -ldflags="-s -w" \
  -trimpath \
  -o "$OUT" \
  .

echo "==> done: $OUT ($(du -h "$OUT" | cut -f1))"
