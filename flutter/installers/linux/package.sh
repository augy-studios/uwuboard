#!/usr/bin/env bash
# Packages the Linux build (docs/desktop-features-spec.md §16): the bundle into /opt/uwuBoard/, a
# symlink on the PATH, the .desktop file (with the uwu:// handler) and icons, as a .deb (dpkg-deb),
# an .rpm (rpmbuild) and an AppImage (appimagetool). One set per processor, built on it.
#
#   installers/linux/package.sh <version> <amd64|arm64> <bundle dir> <out dir>
set -euo pipefail

version="$1"; architecture="$2"; bundle_dir="$3"; output_dir="$4"
script_dir="$(cd "$(dirname "$0")" && pwd)"
icon="$script_dir/../../assets/images/icon-512.png"
mkdir -p "$output_dir"
# The names the .rpm and the AppImage use for this processor.
case "$architecture" in
  amd64) rpm_architecture=x86_64; appimage_architecture=x86_64 ;;
  arm64) rpm_architecture=aarch64; appimage_architecture=aarch64 ;;
  *) echo "unknown arch $architecture" >&2; exit 1 ;;
esac

# Prints the .desktop file (the menu entry, and the uwu:// link handler). $1 is the command it runs.
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
package_root="$(mktemp -d)"
mkdir -p "$package_root/opt/uwuBoard" "$package_root/usr/bin" "$package_root/usr/share/applications" "$package_root/usr/share/icons/hicolor/512x512/apps" "$package_root/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle_dir/." "$package_root/opt/uwuBoard/"
ln -s /opt/uwuBoard/uwuboard "$package_root/usr/bin/uwuboard"
desktop_entry /opt/uwuBoard/uwuboard > "$package_root/usr/share/applications/uwuboard.desktop"
cp "$icon" "$package_root/usr/share/icons/hicolor/512x512/apps/uwuboard.png"
convert "$icon" -resize 256x256 "$package_root/usr/share/icons/hicolor/256x256/apps/uwuboard.png" 2>/dev/null || cp "$icon" "$package_root/usr/share/icons/hicolor/256x256/apps/uwuboard.png"
size_in_kilobytes="$(du -sk "$package_root" | cut -f1)"

# ---- .deb ----
deb_root="$(mktemp -d)"
cp -a "$package_root/." "$deb_root/"
mkdir -p "$deb_root/DEBIAN"
cat > "$deb_root/DEBIAN/control" <<EOF
Package: uwuboard
Version: $version
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: Augy Studios <noreply@uwuapps.org>
Installed-Size: $size_in_kilobytes
Depends: libgtk-3-0, libayatana-appindicator3-1 | libappindicator3-1
Homepage: https://board.uwuapps.org
Description: uwuBoard, the Kanban way
 Turn your to-do list into a clear board where you drag tasks from To Do to Done,
 or lay them out as a Timeline. Guest mode or an account, and sync between devices.
EOF
cat > "$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$deb_root/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$deb_root" "$output_dir/uwuboard-$version-$architecture.deb"

# ---- .rpm ----
# Only where rpmbuild is installed.
if command -v rpmbuild >/dev/null; then
  rpm_top_dir="$(mktemp -d)"
  mkdir -p "$rpm_top_dir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
  cat > "$rpm_top_dir/SPECS/uwuboard.spec" <<EOF
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
cp -a $package_root/. %{buildroot}/

%files
/opt/uwuBoard
/usr/bin/uwuboard
/usr/share/applications/uwuboard.desktop
/usr/share/icons/hicolor/512x512/apps/uwuboard.png
/usr/share/icons/hicolor/256x256/apps/uwuboard.png
EOF
  rpmbuild --define "_topdir $rpm_top_dir" --target "$rpm_architecture" -bb "$rpm_top_dir/SPECS/uwuboard.spec"
  cp "$rpm_top_dir"/RPMS/*/*.rpm "$output_dir/uwuboard-$version-$rpm_architecture.rpm"
fi

# ---- AppImage ----
# The bundle in an AppDir with a start script, the .desktop file and the icon, packed by
# appimagetool (downloaded once into /tmp).
app_dir="$(mktemp -d)/uwuBoard.AppDir"
mkdir -p "$app_dir/usr/lib/uwuboard"
cp -a "$bundle_dir/." "$app_dir/usr/lib/uwuboard/"
cat > "$app_dir/AppRun" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/uwuboard/uwuboard" "$@"
EOF
chmod 755 "$app_dir/AppRun"
desktop_entry uwuboard > "$app_dir/uwuboard.desktop"
cp "$icon" "$app_dir/uwuboard.png"
appimagetool_file="appimagetool-$appimage_architecture.AppImage"
if [ ! -x "/tmp/$appimagetool_file" ]; then
  curl -fsSL -o "/tmp/$appimagetool_file" "https://github.com/AppImage/appimagetool/releases/download/continuous/$appimagetool_file"
  chmod 755 "/tmp/$appimagetool_file"
fi
ARCH="$appimage_architecture" "/tmp/$appimagetool_file" --appimage-extract-and-run "$app_dir" "$output_dir/uwuboard-$version-$appimage_architecture.AppImage"

ls -lh "$output_dir"
