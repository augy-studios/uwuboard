#!/usr/bin/env bash
# Packages the macOS build (docs/desktop-features-spec.md §16): Flutter builds one universal app;
# it's thinned to each processor (ditto --arch), signed ad hoc, zipped for the app's own updates
# (ditto -c -k --keepParent) and put in a .dmg with an Applications link (hdiutil).
#
#   installers/macos/package.sh <version> <path to uwuBoard.app> <out dir>
set -euo pipefail

version="$1"; app_path="$2"; output_dir="$3"
mkdir -p "$output_dir"
# One .zip and one .dmg per processor: Apple silicon (arm64) and Intel (x64).
for architecture in arm64 x64; do
  # The name ditto uses for this processor.
  case "$architecture" in
    arm64) lipo_architecture=arm64 ;;
    x64) lipo_architecture=x86_64 ;;
  esac
  # The app with only this processor's code, signed ad hoc, then zipped.
  work_dir="$(mktemp -d)"
  ditto --arch "$lipo_architecture" "$app_path" "$work_dir/uwuBoard.app"
  codesign --force --deep --sign - "$work_dir/uwuBoard.app"
  ditto -c -k --keepParent "$work_dir/uwuBoard.app" "$output_dir/uwuboard-$version-mac-$architecture.zip"
  # The disk image: the app beside a link to Applications, to drag it onto.
  dmg_contents_dir="$(mktemp -d)"
  cp -R "$work_dir/uwuBoard.app" "$dmg_contents_dir/"
  ln -s /Applications "$dmg_contents_dir/Applications"
  hdiutil create -volname "uwuBoard $version" -srcfolder "$dmg_contents_dir" -ov -format UDZO "$output_dir/uwuboard-$version-mac-$architecture.dmg"
done
ls -lh "$output_dir"
