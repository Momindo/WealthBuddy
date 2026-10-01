#!/usr/bin/env bash
# Generates the Android and iOS folders around the existing lib/ and test/ code, applies the
# platform settings this app needs, and generates the app icon and native splash. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org ae.wealthbuddy --project-name wealth_buddy --platforms=android,ios .
python3 tool/patch_platforms.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
echo "Ready. Run: flutter test   then   flutter run"
