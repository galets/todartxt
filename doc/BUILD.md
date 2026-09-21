# BUILD :: linux DEB

> ENV: Debian 13 trixie / Flutter 3.41.7 / flutter_distributor 0.6.10

## 1. PREREQUISITES

```bash
dart pub global activate flutter_distributor
export PATH="$PATH:$HOME/.pub-cache/bin"
which dpkg-deb   # -> /usr/bin/dpkg-deb
```

## 2. CONFIG

- `distribute_options.yaml` (project root): defines `stable` release with job `stable-linux-deb` (`platform: linux`, `target: deb`). Output goes to `dist/` (gitignored).
- `linux/packaging/deb/make_config.yaml`: deb metadata. Key fields:
  - `display_name: TodartTxt`, `package_name: todart-txt`
  - `icon: branding/todart-icon.png` -> installed to `usr/share/icons/hicolor/{128x128,256x256}/apps/todart_txt.png`
  - `supported_mime_type: [text/plain]` -> desktop entry `MimeType=text/plain;`, associates `todo.txt` files
  - Binary name comes from `linux/CMakeLists.txt` (`BINARY_NAME "todart_txt"`). Packager installs to `/opt/todart_txt/` and postinst symlinks `/usr/bin/todart_txt`.
- Desktop launcher is auto-generated: `usr/share/applications/todart_txt.desktop` with `Exec=todart_txt %U`.

## 3. BUILD

```bash
flutter_distributor release --name=stable --jobs=stable-linux-deb
ls -lh dist/1.1.0+2/
# -> todart_txt-1.1.0+2-linux.deb
```

Version comes from `pubspec.yaml` (`version: 1.1.0+2`).

## 4. VERIFY

```bash
DEB=dist/1.1.0+2/todart_txt-1.1.0+2-linux.deb
dpkg-deb -c $DEB                                            # file list
dpkg-deb -f $DEB Package Version Maintainer                 # control
dpkg-deb --fsys-tarfile $DEB | tar -xO ./usr/share/applications/todart_txt.desktop
dpkg-deb --ctrl-tarfile $DEB | tar -xO ./postinst           # -> ln -s /opt/todart_txt/todart_txt /usr/bin/todart_txt
```

## 5. INSTALL

```bash
sudo apt install ./dist/1.1.0+2/todart_txt-1.1.0+2-linux.deb
which todart_txt        # -> /usr/bin/todart_txt
xdg-mime query default text/plain   # confirm association if needed
```
