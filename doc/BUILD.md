# BUILD

## deb package

```bash
dart pub global activate flutter_distributor
export PATH="$PATH:$HOME/.pub-cache/bin"

flutter_distributor release --name=stable --jobs=stable-linux-deb
find dist/ -name '*.deb'
```
