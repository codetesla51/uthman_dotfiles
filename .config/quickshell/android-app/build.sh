#!/bin/bash
# Build the PhoneRelay APK without Gradle: javac -> d8 -> aapt2 link ->
# append classes.dex -> zipalign -> apksigner. Needs JDK 17 (mise: java@17)
# and ~/Android/Sdk (build-tools + platforms/android-34). Output: out/phonerelay.apk
set -euo pipefail
cd "$(dirname "$0")"
SDK="$HOME/Android/Sdk"
BT="$SDK/build-tools"
AJ="$SDK/platforms/android-34/android.jar"
rm -rf out classes && mkdir -p out classes

javac --release 8 -classpath "$AJ" -d classes $(find src -name '*.java')
echo "javac OK"
"$BT/d8" --release --min-api 33 --lib "$AJ" --output out $(find classes -name '*.class')
echo "d8 OK -> out/classes.dex"
"$BT/aapt2" link -o out/base.unsigned.apk --manifest AndroidManifest.xml -I "$AJ" \
  --min-sdk-version 33 --target-sdk-version 34 --version-code 1 --version-name 1.0
echo "aapt2 link OK"

# append classes.dex at apk root (python zipfile; no `zip` binary on box)
python3 - <<'EOF'
import zipfile
z = zipfile.ZipFile('out/base.unsigned.apk', 'a', zipfile.ZIP_DEFLATED)
z.write('out/classes.dex', 'classes.dex')
z.close()
EOF
"$BT/zipalign" -f 4 out/base.unsigned.apk out/base.aligned.apk
echo "zipalign OK"

if [ ! -f keystore.jks ]; then
  keytool -genkeypair -keystore keystore.jks -alias relay -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android -dname "CN=PhoneRelay" >/dev/null 2>&1
  echo "keystore generated (first run)"
fi
"$BT/apksigner" sign --ks keystore.jks --ks-pass pass:android --key-pass pass:android \
  --out out/phonerelay.apk out/base.aligned.apk
echo "signed: out/phonerelay.apk"
"$BT/apksigner" verify out/phonerelay.apk && echo "verify OK"