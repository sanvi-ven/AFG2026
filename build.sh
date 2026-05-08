#!/bin/bash
set -e

# Determine app directory
if [ -f pubspec.yaml ]; then
  APP_DIR=.
else
  APP_DIR=frontend
fi

# Find or setup Flutter
if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN=$(command -v flutter)
elif [ -x "$PWD/.flutter-sdk/bin/flutter" ]; then
  FLUTTER_BIN="$PWD/.flutter-sdk/bin/flutter"
else
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable .flutter-sdk
  FLUTTER_BIN="$PWD/.flutter-sdk/bin/flutter"
fi

# Build web
"$FLUTTER_BIN" config --enable-web
cd "$APP_DIR"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --release --dart-define=API_BASE_URL=${API_BASE_URL:-https://api.yourdomain.com}
cd - >/dev/null

# Copy to dist
rm -rf dist
mkdir -p dist
cp -R "$APP_DIR"/build/web/. dist/
