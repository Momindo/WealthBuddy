#!/usr/bin/env bash
# Generates the Android and iOS platform folders around the existing lib/ and test/ code,
# then applies the settings this app needs. Safe to re-run: existing files are kept.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org ae.wealthbuddy --project-name wealth_buddy --platforms=android,ios .

# flutter_secure_storage 11 needs Android 7.0 (API 24) or later.
for f in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$f" ]; then
    sed -i.bak -E 's/minSdk( =|Version)? *=? *flutter\.minSdkVersion/minSdk = 24/' "$f" && rm -f "$f.bak"
  fi
done

# Keep the app's data out of Android cloud backups: the encryption key can't be restored with it.
manifest=android/app/src/main/AndroidManifest.xml
if [ -f "$manifest" ] && ! grep -q 'android:allowBackup' "$manifest"; then
  sed -i.bak 's/<application/<application android:allowBackup="false" android:fullBackupContent="false"/' "$manifest" && rm -f "$manifest.bak"
fi

flutter pub get
echo "Ready. Run: flutter test   then   flutter run"
