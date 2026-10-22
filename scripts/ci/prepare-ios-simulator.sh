#!/bin/bash
# CI only: creates the simulator that scripts/test-ios.sh tests on, lets it finish the
# work of its first boot, shuts it down cleanly and leaves a copy in the given folder
# for the iOS tests workflow to cache. Nothing is ever installed on it.
# See docs/ios-testing.md.
#
# Usage: bash scripts/ci/prepare-ios-simulator.sh <snapshot folder>
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
snapshot="${1:?Usage: prepare-ios-simulator.sh <snapshot folder>}"
devices_dir="$HOME/Library/Developer/CoreSimulator/Devices"

read -r device_type runtime <<< "$(python3 scripts/ci/ios_simulator.py pick)"
simulator_id="$(xcrun simctl create 'Scowld CI' "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
echo "Booted the new simulator $simulator_id in $SECONDS s"

# The costliest part of a first boot: minutes in, SpringBoard has PosterBoard prewarm
# the wallpaper gallery (5 to 12 minutes after boot on the runner). Only a simulator
# that got through it is worth keeping.
outcome='Prewarm is complete|prewarm bailed|prewarm finished with error|Prewarm invalidated'
line=
until [[ -n "$line" ]]; do
  if (( SECONDS >= 900 )); then
    echo 'error: PosterBoard has not logged the end of its gallery prewarm 15 minutes after boot; nothing to save' >&2
    exit 1
  fi
  sleep 10
  line="$(xcrun simctl spawn "$simulator_id" log show --style compact --last 30m \
    --predicate 'subsystem == "com.apple.PosterBoard" AND category == "Prewarm"' 2>/dev/null \
    | grep -m 1 -E "$outcome" || true)"
done
echo "Gallery prewarm over $SECONDS s after the boot started: $line"
if [[ "$line" != *'Prewarm is complete'* ]]; then
  echo 'error: the gallery prewarm did not complete; nothing to save' >&2
  exit 1
fi

# The rest of the first boot (Shortcuts, App Store engagement, widgets, Calendar,
# Spotlight's extraction service and more) keeps one or two CPUs busy for another
# 4 to 10 minutes. Wait for that to end, for 10 minutes at most.
python3 scripts/ci/ios_simulator.py wait-idle 600

# Not only the first boot: every boot has SpringBoard ask PosterBoard to prewarm the
# gallery again, and PosterBoard renders all 368 previews again each time, two to
# eight minutes after the boot. Keynote mode, PosterBoard's switch for demo devices,
# makes it skip the prewarm. (A new simulator resets it during its first boot.)
xcrun simctl spawn "$simulator_id" defaults write com.apple.PosterBoard.unprotectedUserDefaults \
  KEYNOTE_MODE -bool YES
if [[ "$(xcrun simctl spawn "$simulator_id" defaults read com.apple.PosterBoard.unprotectedUserDefaults KEYNOTE_MODE)" != 1 ]]; then
  echo 'error: could not turn on PosterBoard keynote mode; nothing to save' >&2
  exit 1
fi

xcrun simctl shutdown "$simulator_id"
rm -rf "$snapshot"
mkdir -p "$snapshot"
# An APFS clone: takes seconds and leaves the original for cleanup to delete.
cp -cpR "$devices_dir/$simulator_id" "$snapshot/$simulator_id"
printf 'udid=%s\ndevice_type=%s\nruntime=%s\n' "$simulator_id" "$device_type" "$runtime" \
  > "$snapshot/snapshot.txt"
echo "Set up and shut down the simulator $simulator_id in $SECONDS s ($(du -sh "$snapshot/$simulator_id" | cut -f1))"
