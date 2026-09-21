# BUILD

## deb package

```bash
dart pub global activate flutter_distributor
export PATH="$PATH:$HOME/.pub-cache/bin"

flutter_distributor release --name=stable --jobs=stable-linux-deb
find dist/ -name '*.deb'
```

## android release build (via flutter_distributor)

```bash
dart pub global activate flutter_distributor
export PATH="$PATH:$HOME/.pub-cache/bin"

flutter_distributor release --name=stable --jobs=stable-android-apk
find dist/ -name '*.apk' -o -name '*.aab'
```

> NOTE: `android/app/build.gradle.kts` currently signs the release build
> with the debug keys. Add your own signing config before publishing
> (e.g. to Google Play, which requires the `.aab`).
