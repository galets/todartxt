# ANDROID :: build APK

> ENV: Debian 13 trixie / Flutter 3.41.7 / toolchain26 / SDK 35+36 / AGP 9.1.0 / KGP 2.4.0 / Gradle 9.3.1 / JDK 21 (Studio JBR)

## 0. VARS

```bash
export TC=$HOME/.local/lib/toolchain26
export STUDIO=$TC/android-studio
export SDK=$TC/android-sdk
export JAVA_HOME=$STUDIO/jbr
export ANDROID_SDK_ROOT=$SDK ANDROID_HOME=$SDK
export PATH=$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH
```

## 1. BOOTSTRAP :: cmdline-tools -> SDK

Task -> unpack cmdline-tools (no unzip on host, use python zipfile) -> accept licenses -> install packages.

```bash
mkdir -p $SDK/cmdline-tools
curl -sSLo /tmp/cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
python3 -c "import zipfile; zipfile.ZipFile('/tmp/cmdtools.zip').extractall('/tmp/cmdtools')"
rm -rf $SDK/cmdline-tools/latest && mkdir -p $SDK/cmdline-tools/latest
cp -r /tmp/cmdtools/cmdline-tools/. $SDK/cmdline-tools/latest/
rm -rf /tmp/cmdtools /tmp/cmdtools.zip
chmod +x $SDK/cmdline-tools/latest/bin/*
yes | sh $SDK/cmdline-tools/latest/bin/sdkmanager --sdk_root=$SDK --licenses
sh $SDK/cmdline-tools/latest/bin/sdkmanager --sdk_root=$SDK \
  "platform-tools" "platforms;android-35" "build-tools;35.0.0"
# NOTE: flutter auto-pulls platforms;android-36 + cmake 3.22.1 on first build
```

Verify:

```bash
ls $SDK                               # -> build-tools/ cmdline-tools/ licenses/ platform-tools/ platforms/
$SDK/platform-tools/adb version
flutter config --android-sdk $SDK
flutter doctor --android-licenses
flutter doctor -v                     # -> [✓] Android toolchain
```

## 2. FIX :: app KGP missing

Task -> `flutter build apk` fails with `Unresolved reference 'compilerOptions'` / `'jvmTarget'` in `android/app/build.gradle.kts`.
Cause -> `gradle.properties: android.builtInKotlin=false`, but kotlin plugin never applied.
Fix -> apply KGP after AGP, before flutter plugin:

```bash
cat android/app/build.gradle.kts
```

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
```

## 3. BUILD :: APK

Task -> release APK (debug-signed, see `signingConfigs.getByName("debug")`).

```bash
export JAVA_HOME=$STUDIO/jbr ANDROID_SDK_ROOT=$SDK ANDROID_HOME=$SDK
flutter build apk --release
ls -lh build/app/outputs/flutter-apk/
# -> app-release.apk (~47MB) + app-release.apk.sha1
```

## 4. DEPLOY :: device

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell pm list packages | grep todart
# -> package:com.todart.todart_txt
```

## 5. REBUILD :: one-liner

```bash
export TC=$HOME/.local/lib/toolchain26 STUDIO=$TC/android-studio SDK=$TC/android-sdk
export JAVA_HOME=$STUDIO/jbr ANDROID_SDK_ROOT=$SDK ANDROID_HOME=$SDK
export PATH=$JAVA_HOME/bin:$SDK/platform-tools:$PATH
flutter build apk --release && ls -lh build/app/outputs/flutter-apk/app-release.apk
```
