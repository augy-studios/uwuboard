#!/usr/bin/env bash
# Packages the Linux build (docs/desktop-features-spec.md §16): the bundle into /opt/uwuBoard/, a
# symlink on the PATH, the .desktop file (with the uwu:// handler) and icons, as a .deb (dpkg-deb),
# an .rpm (rpmbuild) and an AppImage (appimagetool). One set per processor, built on it.
#
#   installers/linux/package.sh <version> <amd64|arm64> <bundle dir> <out dir>
set -euo pipefail

version="$1"; arch="$2"; bundle="$3"; out="$4"
here="$(cd "$(dirname "$0")" && pwd)"
icon="$here/../../assets/images/icon-512.png"
mkdir -p "$out"
case "$arch" in
  amd64) rpm_arch=x86_64; appimage_arch=x86_64 ;;
  arm64) rpm_arch=aarch64; appimage_arch=aarch64 ;;
  *) echo "unknown arch $arch" >&2; exit 1 ;;
esac

desktop_entry() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=uwuBoard
GenericName=Kanban board
Comment=Turn your to-do list into a clear board where you drag tasks from To Do to Done
Exec=$1 %u
Icon=uwuboard
Terminal=false
Categories=Office;ProjectManagement;
MimeType=x-scheme-handler/uwu;
StartupWMClass=uwuboard
Keywords=kanban;todo;tasks;timeline;gantt;
EOF
}

# ---- the tree, shared by the .deb and the .rpm ----
root="$(mktemp -d)"
mkdir -p "$root/opt/uwuBoard" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps" "$root/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$root/opt/uwuBoard/"
ln -s /opt/uwuBoard/uwuboard "$root/usr/bin/uwuboard"
desktop_entry /opt/uwuBoard/uwuboard > "$root/usr/share/applications/uwuboard.desktop"
cp "$icon" "$root/usr/share/icons/hicolor/512x512/apps/uwuboard.png"
convert "$icon" -resize 256x256 "$root/usr/share/icons/hicolor/256x256/apps/uwuboard.png" 2>/dev/null || cp "$icon" "$root/usr/share/icons/hicolor/256x256/apps/uwuboard.png"
size_kb="$(du -sk "$root" | cut -f1)"

# ---- .deb ----
deb="$(mktemp -d)"
cp -a "$root/." "$deb/"
mkdir -p "$deb/DEBIAN"
cat > "$deb/DEBIAN/control" <<EOF
Package: uwuboard
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: Augy Studios <noreply@uwuapps.org>
Installed-Size: $size_kb
Depends: libgtk-3-0, libayatana-appindicator3-1 | libappindicator3-1
Homepage: https://board.uwuapps.org
Description: uwuBoard, the Kanban way
 Turn your to-do list into a clear board where you drag tasks from To Do to Done,
 or lay them out as a Timeline. Guest mode or an account, and sync between devices.
EOF
cat > "$deb/DEBIAN/postinst" <<'EOF'
#!/bin/sh
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$deb/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$deb" "$out/uwuboard-$version-$arch.deb"

# ---- .rpm ----
if command -v rpmbuild >/dev/null; then
  top="$(mktemp -d)"
  mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
  cat > "$top/SPECS/uwuboard.spec" <<EOF
Name: uwuboard
Version: $version
Release: 1
Summary: uwuBoard, the Kanban way
License: MIT
URL: https://board.uwuapps.org
Requires: gtk3
AutoReqProv: no
%define _build_id_links none
%define __strip /bin/true

%description
Turn your to-do list into a clear board where you drag tasks from To Do to Done,
or lay them out as a Timeline.

%install
cp -a $root/. %{buildroot}/

%files
/opt/uwuBoard
/usr/bin/uwuboard
/usr/share/applications/uwuboard.desktop
/usr/share/icons/hicolor/512x512/apps/uwuboard.png
/usr/share/icons/hicolor/256x256/apps/uwuboard.png
EOF
  rpmbuild --define "_topdir $top" --target "$rpm_arch" -bb "$top/SPECS/uwuboard.spec"
  cp "$top"/RPMS/*/*.rpm "$out/uwuboard-$version-$rpm_arch.rpm"
fi

# ---- AppImage ----
appdir="$(mktemp -d)/uwuBoard.AppDir"
mkdir -p "$appdir/usr/lib/uwuboard"
cp -a "$bundle/." "$appdir/usr/lib/uwuboard/"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/uwuboard/uwuboard" "$@"
EOF
chmod 755 "$appdir/AppRun"
desktop_entry uwuboard > "$appdir/uwuboard.desktop"
cp "$icon" "$appdir/uwuboard.png"
tool="appimagetool-$appimage_arch.AppImage"
if [ ! -x "/tmp/$tool" ]; then
  curl -fsSL -o "/tmp/$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/$tool"
  chmod 755 "/tmp/$tool"
fi
ARCH="$appimage_arch" "/tmp/$tool" --appimage-extract-and-run "$appdir" "$out/uwuboard-$version-$appimage_arch.AppImage"

ls -lh "$out"
