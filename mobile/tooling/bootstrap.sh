#!/usr/bin/env bash
# Regenerate the sources that upstream keeps out of git.
#
# This fork VENDORS the generated output, so a fresh clone can run
# `flutter build apk` directly. You only need this script after rebasing onto
# a newer upstream revision, or after changing a pigeon / drift schema.
#
# Usage:  bash mobile/tooling/bootstrap.sh
# Needs:  dart, flutter on PATH; `dart pub get` must resolve (see pubspec.lock).
# The openapi SDK and the i18n loader are vendored too: regenerating them needs
# the openapi-generator jar and the native-assets-hook workaround, so they are
# intentionally left to the host-side tools/gen-dart-sdk.sh and tools/i18ngen.
set -euo pipefail

MOBILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MOBILE"

echo "==> dart pub get"
dart pub get

echo "==> build_runner (freezed / drift / router)"
dart run build_runner build --delete-conflicting-outputs

echo "==> drift schema steps"
dart run drift_dev schema steps drift_schemas/main lib/data/db/main/database.steps.dart

echo "==> pigeon"
pids=()
for schema in pigeon/*.dart; do
  dart run pigeon --input "$schema" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "==> done. Review and commit the regenerated files together with the schema change."
