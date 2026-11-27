#!/usr/bin/env bash
set -euo pipefail

# Install Flutter only inside this ephemeral Vercel build.
FLUTTER_HOME="${TMPDIR:-/tmp}/spotmate-flutter-sdk"
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"
export CI=true

flutter --version
flutter config --enable-web
flutter pub get
# Unpack the HaloBerry artwork pack when it is present in the Git tree.
python3 scripts/install_space100_art.py
# Install user-uploaded illustrated avatar posture batches as Flutter assets.
python3 scripts/install_avatar_actions.py
flutter build web --release \
  --dart-define="GOOGLE_OAUTH_ENABLED=${GOOGLE_OAUTH_ENABLED:-false}" \
  --dart-define="TENOR_API_KEY=${TENOR_API_KEY:-}" \
  --dart-define="GIPHY_API_KEY=${GIPHY_API_KEY:-}"

# Fail the deployment if Flutter did not emit a usable web bundle.
test -s build/web/main.dart.js
test -s build/web/index.html
