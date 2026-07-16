#!/usr/bin/env bash
# Assembles Brightsync.app from the SwiftPM release build: binary, Info.plist
# (version taken from the binary itself), icon, ad-hoc signature.
set -euo pipefail

usage() {
  cat <<'EOF'
Build Brightsync.app from the SwiftPM release build.

Usage: scripts/build-app.sh [--output <dir>] [--sign <identity>] [-h|--help]

Options:
  --output <dir>     Directory to place Brightsync.app in (default: dist)
  --sign <identity>  Code-signing identity (default: "-", ad-hoc). A stable
                     identity keeps TCC grants like Accessibility valid
                     across rebuilds.
  -h, --help         Show this help.

Example:
  scripts/build-app.sh --sign "Brightsync Dev"
EOF
}

output="dist"
sign="-"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "error: --output needs a value" >&2; exit 2; }
      output="$2"; shift 2 ;;
    --sign)
      [[ $# -ge 2 ]] || { echo "error: --sign needs a value" >&2; exit 2; }
      sign="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

swift build -c release
binary=".build/release/brightsync"
version="$("$binary" --version)"

app="$output/Brightsync.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchAgents"
cp "$binary" "$app/Contents/MacOS/brightsync"
sed "s/__VERSION__/$version/g" Packaging/Info.plist > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" > /dev/null
cp Packaging/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Packaging/cz.szypowi.brightsync.plist "$app/Contents/Library/LaunchAgents/"
codesign --force --sign "$sign" --identifier cz.szypowi.brightsync "$app"
echo "built $app (version $version)"
