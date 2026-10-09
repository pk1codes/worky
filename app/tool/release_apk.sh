#!/usr/bin/env bash
# Production Android APK (App Check + live Functions API).
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build apk --release --dart-define=USE_EMULATOR=false "$@"
