#!/bin/bash
# Simulator unit and UI tests. This script never archives, uploads or publishes an app.
#
# Usage: bash scripts/test-ios.sh [extra xcodebuild test arguments, e.g. -only-testing:ScowldTests]
# A partial run must name the bundles it expects in IOS_TEST_BUNDLES.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived_data="${IOS_TEST_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Scowld-simulator-tests}"
packages="${IOS_TEST_PACKAGES:-$derived_data/SourcePackages}"
results="${IOS_TEST_RESULTS:-$derived_data/TestResults/$(date -u +%Y%m%dT%H%M%SZ)-$$}"
read -r -a bundles <<< "${IOS_TEST_BUNDLES:-ScowldTests ScowldUITests}"
mkdir -p "$results"
if [[ -e "$results/Tests.xcresult" ]]; then
  echo 'Choose an unused IOS_TEST_RESULTS directory; existing results are preserved.' >&2
  exit 1
fi

xcodebuild -version

# Create a task-owned simulator: never erase or reset a developer's existing one.
simulator_id="$(python3 - <<'PY'
import json, subprocess
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '--json']))
def version(runtime):
    return tuple(int(part) for part in runtime['version'].split('.'))
runtimes = [r for r in data['runtimes'] if r.get('isAvailable') and
            '.iOS-' in r['identifier'] and version(r) >= (17, 0)]
if not runtimes:
    raise SystemExit('Install an iOS 17 or newer Simulator runtime in Xcode.')
runtime = max(runtimes, key=version)
iphones = [d for d in runtime.get('supportedDeviceTypes', []) if d.get('productFamily') == 'iPhone']
if not iphones:
    raise SystemExit('Selected runtime has no supported iPhone device type.')
device = next((d for d in iphones if d['name'] == 'iPhone 17 Pro'), iphones[-1])
print(subprocess.check_output(['xcrun', 'simctl', 'create', 'Scowld CI',
      device['identifier'], runtime['identifier']], text=True).strip())
PY
)"

cleanup() {
  # Only the simulator created by this invocation is removed.
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Why the simulator boots only after the build, and why CI removes dasd from it.
#
# A new simulator spends its first minutes setting itself up. On the GitHub runner
# (3 CPUs, 7 GB, no GPU) a simulator booting during the build slowed the build from
# 1-2 minutes to 5-16, so the app and its tests are built first and the simulator
# boots afterwards.
#
# The costliest part of that setup comes 8 to 11 minutes after the first boot:
# SpringBoard has dasd, the daemon that schedules background system tasks, run
# com.apple.springboard.posterboardupdate.prewarm, in which PosterBoard renders the
# wallpaper gallery's 368 previews. That takes every CPU for 1 to 4 minutes, and UI
# tests running meanwhile saw accessibility checks of 4 to 30 seconds and failed at
# random. Waiting for it to end made the job about 4 minutes slower. Instead, as soon
# as the new simulator takes commands, CI removes dasd from it; in every run measured
# that was before dasd had accepted the task, SpringBoard logged "Failed to submit
# posters task" and nothing was rendered. That stops every background task in this
# throwaway simulator; the app uses none, and no test relies on one. If dasd cannot
# be removed, the tests wait for the prewarm to end instead.

# Removes dasd from the booted simulator. Fails if it is still loaded 30 s later.
remove_background_task_scheduler() {
  # spawn waits until the simulator's launchd takes commands (2 to 5 minutes after
  # the boot on CI). launchctl warns "Please switch to user/foreground/com.apple.dasd
  # service identifier" and removes the service all the same.
  xcrun simctl spawn "$simulator_id" launchctl bootout system/com.apple.dasd || true
  local deadline=$((SECONDS + 30)) services
  while true; do
    # One "PID Status Label" line per loaded service; empty output means launchctl failed.
    services="$(xcrun simctl spawn "$simulator_id" launchctl list 2>/dev/null || true)"
    if [[ -n "$services" ]] && ! grep -q 'com\.apple\.dasd$' <<< "$services"; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      return 1
    fi
    sleep 2
  done
}

# Fallback for when dasd could not be removed: returns once PosterBoard has logged the
# outcome of its gallery prewarm, or 15 minutes after the boot started (the slowest
# runner measured needed 12); then the tests start anyway.
wait_for_gallery_prewarm() {
  local outcome='Prewarm is complete|prewarm bailed|prewarm finished with error|Prewarm invalidated'
  local line
  while (( SECONDS - boot_started < 900 )); do
    line="$(xcrun simctl spawn "$simulator_id" log show --style compact --last 30m \
      --predicate 'subsystem == "com.apple.PosterBoard" AND category == "Prewarm"' 2>/dev/null \
      | grep -m 1 -E "$outcome" || true)"
    if [[ -n "$line" ]]; then
      echo "PosterBoard's gallery prewarm ended $(( (SECONDS - boot_started) / 60 )) min after the boot started: $line"
      return 0
    fi
    sleep 10
  done
  echo 'warning: PosterBoard has not logged the end of its gallery prewarm 15 minutes after boot; starting the tests anyway' >&2
}

# Simulator builds are signed ad hoc ("Sign to Run Locally"): no certificate or
# provisioning profile is needed, and the signature carries the application
# identifier that Keychain access requires (unit and UI tests save provider keys).
# Failure screenshots and recordings stay in the result bundle; the simulator
# diagnostics collection is skipped (on CI it only timed out after 10 minutes).
xcode_options=(
  -project ios/Scowld.xcodeproj
  -scheme Scowld
  -configuration Debug
  -destination "platform=iOS Simulator,id=$simulator_id"
  -destination-timeout 120
  -derivedDataPath "$derived_data"
  -clonedSourcePackagesDirPath "$packages"
  -onlyUsePackageVersionsFromResolvedFile
  -enableCodeCoverage YES
)
status=0
xcodebuild build-for-testing "${xcode_options[@]}" \
  -resultBundlePath "$results/Build.xcresult" \
  2>&1 | tee "$results/xcodebuild.log" || status=$?

if [[ "$status" == 0 ]]; then
  boot_started=$SECONDS
  # A failed boot stops the run here.
  xcrun simctl boot "$simulator_id"
  # Only CI removes dasd: the slowdown was measured on the GitHub runner.
  if [[ "${CI:-}" == true ]]; then
    if remove_background_task_scheduler; then
      echo "Removed dasd from the simulator $((SECONDS - boot_started)) s after the boot started; no first-boot background task (wallpaper gallery prewarm included) will run."
      prewarm_pending=
    else
      echo '::warning::dasd is still loaded in the CI simulator; the tests wait for its wallpaper gallery prewarm instead, which is slower.'
      prewarm_pending=1
    fi
  fi
  xcrun simctl bootstatus "$simulator_id" -b
  if [[ -n "${prewarm_pending:-}" ]]; then
    wait_for_gallery_prewarm
  fi
  xcodebuild test-without-building "${xcode_options[@]}" \
    -resultBundlePath "$results/Tests.xcresult" \
    -parallel-testing-enabled NO \
    -maximum-concurrent-test-simulator-destinations 1 \
    -collect-test-diagnostics never \
    "$@" \
    2>&1 | tee -a "$results/xcodebuild.log" || status=$?
fi

# A test bundle that silently ran nothing must fail the run too.
if [[ -e "$results/Tests.xcresult" ]]; then
  python3 scripts/ci/check_xcresult.py "$results/Tests.xcresult" "${bundles[@]}" || status=1
else
  echo 'error: xcodebuild produced no result bundle' >&2
  status=1
fi
echo "Results: $results/Tests.xcresult"
exit "$status"
