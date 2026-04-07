#!/usr/bin/env zsh
set -e

cd "$(dirname "$0")/../frontend"
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
