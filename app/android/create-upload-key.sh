#!/usr/bin/env bash
# Creates VouchFlow's Google Play upload key and android/key.properties.
#
# Run once, from anywhere:  bash app/android/create-upload-key.sh
#
# You choose the password; it is typed here, never stored anywhere except
# key.properties (which git ignores). Keep the .jks file and the password
# safe and backed up: without them you cannot publish updates to the app.
set -euo pipefail

cd "$(dirname "$0")"
KEYSTORE="$HOME/vouchflow-upload-key.jks"
ALIAS="vouchflow-upload"

# macOS ships a placeholder /usr/bin/keytool that fails without a system
# Java; use the one inside Android Studio or Homebrew's OpenJDK instead.
KEYTOOL=""
for candidate in \
  "${JAVA_HOME:+$JAVA_HOME/bin/keytool}" \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
  "/opt/homebrew/opt/openjdk@17/bin/keytool" \
  "/opt/homebrew/opt/openjdk/bin/keytool"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then KEYTOOL="$candidate"; break; fi
done
if [ -z "$KEYTOOL" ]; then
  echo "No Java keytool found. Install Android Studio or run: brew install openjdk@17" >&2
  exit 1
fi

if [ -f "$KEYSTORE" ]; then
  echo "A key already exists at $KEYSTORE. Not overwriting it." >&2
  exit 1
fi

read -r -s -p "Choose a password for the upload key (at least 8 characters): " PASS; echo
read -r -s -p "Type it again: " PASS2; echo
if [ "$PASS" != "$PASS2" ] || [ ${#PASS} -lt 8 ]; then
  echo "The passwords did not match or were too short. Nothing was created." >&2
  exit 1
fi

"$KEYTOOL" -genkeypair -v \
  -keystore "$KEYSTORE" -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=VouchFlow, O=TechOn Software LLC, L=Dar es Salaam, C=TZ"

umask 077
cat > key.properties <<EOF
storePassword=$PASS
keyPassword=$PASS
keyAlias=$ALIAS
storeFile=$KEYSTORE
EOF

echo
echo "Done. Upload key: $KEYSTORE"
echo "Back it up now (for example to a USB drive and a password manager)."
