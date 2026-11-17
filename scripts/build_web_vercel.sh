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
flutter build web --release

# Fail the deployment if Flutter did not emit a usable web bundle.
test -s build/web/main.dart.js
test -s build/web/index.html
