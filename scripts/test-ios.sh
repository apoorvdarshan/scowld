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

devices_dir="$HOME/Library/Developer/CoreSimulator/Devices"
read -r device_type runtime <<< "$(python3 scripts/ci/ios_simulator.py pick)"
simulator_id=
boot_pid=

cleanup() {
  if [[ -n "${boot_pid:-}" ]]; then
    kill "$boot_pid" >/dev/null 2>&1 || true
  fi
  # Only the simulator this invocation created or restored is removed.
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# On CI the workflow restores a simulator that has already been through its first
# boot (made by scripts/ci/prepare-ios-simulator.sh) into IOS_SIM_SNAPSHOT, and sets
# IOS_SIM_SNAPSHOT_RESTORED=true. It is moved into CoreSimulator's device set and used
# if CoreSimulator accepts it. Otherwise, and on local runs, the script creates a new
# simulator, as it always did.
snapshot="${IOS_SIM_SNAPSHOT:-}"
use_snapshot() {
  local id
  id="$(sed -n 's/^udid=//p' "$snapshot/snapshot.txt" 2>/dev/null || true)"
  if [[ ! "$id" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ||
        ! -f "$snapshot/$id/device.plist" ]]; then
    echo 'warning: the restored simulator is incomplete; using a new simulator' >&2
    return 1
  fi
  if [[ -e "$devices_dir/$id" ]]; then
    echo "warning: a simulator $id already exists; using a new simulator" >&2
    return 1
  fi
  mkdir -p "$devices_dir"
  mv "$snapshot/$id" "$devices_dir/$id"
  simulator_id="$id"
  # CoreSimulator reads the device folders when its service starts.
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  if ! python3 scripts/ci/ios_simulator.py check "$id" "$device_type" "$runtime"; then
    echo 'warning: CoreSimulator does not accept the restored simulator; using a new simulator' >&2
    xcrun simctl delete "$id" >/dev/null 2>&1 || rm -rf "${devices_dir:?}/$id"
    simulator_id=
    return 1
  fi
  echo "Using the simulator restored from the cache ($id)"
}
restored=false
if [[ -n "$snapshot" && "${IOS_SIM_SNAPSHOT_RESTORED:-}" == true ]] && use_snapshot; then
  restored=true
else
  # A task-owned simulator: never erase or reset a developer's existing one.
  simulator_id="$(xcrun simctl create 'Scowld CI' "$device_type" "$runtime")"
fi

# A new simulator finishes setting itself up in the background, and the costliest
# step comes minutes after the first boot: SpringBoard schedules a background task in
# which PosterBoard prewarms the wallpaper gallery, rendering dozens of wallpapers. It
# ran 5 to 12 minutes after boot. On the GitHub runner (3 CPUs, 7 GB, no GPU) that
# rendering takes every CPU and about 2 GB of memory for one to three minutes, and UI
# tests running meanwhile saw accessibility checks of 4 to 30 seconds instead of a
# fraction of one. So a new simulator boots while the app builds (simctl boot itself
# took 2 to 6 minutes on CI), and on CI the tests wait for PosterBoard to log the end
# of the prewarm.
#
# A restored simulator has been through all of that, and PosterBoard's keynote mode
# keeps it from prewarming again. It boots after the build: on its own the build takes
# 1 to 2 minutes, next to a boot 5 to 15.
boot_started=$SECONDS
if [[ "$restored" == false ]]; then
  xcrun simctl boot "$simulator_id" &
  boot_pid=$!
fi

# Returns once PosterBoard has logged the outcome of its gallery prewarm, or 15 minutes
# after the boot (the slowest runner measured needed 12); then the tests start anyway.
wait_for_simulator_setup() {
  local outcome='Prewarm is complete|prewarm bailed|prewarm finished with error|Prewarm invalidated'
  local started=$SECONDS line
  while true; do
    line="$(xcrun simctl spawn "$simulator_id" log show --style compact --last 30m \
      --predicate 'subsystem == "com.apple.PosterBoard" AND category == "Prewarm"' 2>/dev/null \
      | grep -m 1 -E "$outcome" || true)"
    if [[ -n "$line" ]]; then
      echo "Simulator set up $(( (SECONDS - boot_started) / 60 )) min after the boot started; waited $((SECONDS - started)) s after the build: $line"
      return 0
    fi
    if (( SECONDS - boot_started >= 900 )); then
      echo 'warning: PosterBoard has not logged the end of its gallery prewarm 15 minutes after boot; starting the tests anyway' >&2
      return 0
    fi
    sleep 10
  done
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
build_started=$SECONDS
xcodebuild build-for-testing "${xcode_options[@]}" \
  -resultBundlePath "$results/Build.xcresult" \
  2>&1 | tee "$results/xcodebuild.log" || status=$?
echo "Built in $((SECONDS - build_started)) s"

if [[ "$status" == 0 ]]; then
  if [[ "$restored" == true ]]; then
    boot_started=$SECONDS
    xcrun simctl boot "$simulator_id"
    xcrun simctl bootstatus "$simulator_id" -b >/dev/null
    echo "Booted the restored simulator in $((SECONDS - boot_started)) s"
  else
    # A failed boot stops the run here.
    wait "$boot_pid"
    boot_pid=
    # Only CI waits for the setup: the slowdown was measured on the GitHub runner.
    if [[ "${CI:-}" == true ]]; then
      wait_for_simulator_setup
    fi
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
