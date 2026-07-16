#!/usr/bin/env bash
# Installs Brightsync.app and enables its launch-at-login agent.
set -euo pipefail

usage() {
  cat <<'EOF'
Install Brightsync.app and enable launch at login.

Builds the app (unless --skip-build), unregisters any previously installed
copy, replaces it, and registers the embedded launchd agent through the new
app (--autostart enable), which also starts it.

Usage: scripts/install-app.sh [--app-dir <dir>] [--sign <identity>] [--skip-build] [-h|--help]

Options:
  --app-dir <dir>    Install destination (default: /Applications)
  --sign <identity>  Code-signing identity passed to build-app.sh
  --skip-build       Use the existing dist/Brightsync.app instead of rebuilding
  -h, --help         Show this help.

Example:
  scripts/install-app.sh
EOF
}

app_dir="/Applications"
skip_build=0
sign=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-dir)
      [[ $# -ge 2 ]] || { echo "error: --app-dir needs a value" >&2; exit 2; }
      app_dir="$2"; shift 2 ;;
    --sign)
      [[ $# -ge 2 ]] || { echo "error: --sign needs a value" >&2; exit 2; }
      sign="$2"; shift 2 ;;
    --skip-build) skip_build=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

if [[ $skip_build -eq 0 ]]; then
  build_args=(--output dist)
  [[ -n "$sign" ]] && build_args+=(--sign "$sign")
  scripts/build-app.sh "${build_args[@]}"
elif [[ ! -d dist/Brightsync.app ]]; then
  echo "error: dist/Brightsync.app not found; run without --skip-build first" >&2
  exit 1
fi

app="$app_dir/Brightsync.app"
rm -rf "$app"
cp -R dist/Brightsync.app "$app"

# Refresh LaunchServices' record of the bundle: Background Task Management
# resolves the agent's bundle-relative program through a bookmark that goes
# stale when the app is replaced ("Could not find and/or execute program").
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$lsregister" -f "$app"

# enable re-registers from scratch (see Autostart.swift), refreshing the
# launch constraint Background Task Management pins to the registered binary.
"$app/Contents/MacOS/brightsync" --autostart enable

started() {
  launchctl print "gui/$(id -u)/cz.szypowi.brightsync" 2> /dev/null | grep -q 'state = running'
}
for _ in 1 2 3 4 5 6 7 8; do started && break; sleep 1; done
started || { echo "error: agent not running, check the logs" >&2; exit 1; }
echo "installed $app"
echo "logs: log stream --predicate 'subsystem == \"cz.szypowi.brightsync\"'"
