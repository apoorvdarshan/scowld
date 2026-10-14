#!/bin/bash
# Simulator unit and UI tests. This script never archives, uploads or publishes an app.
#
# Usage: bash scripts/test-ios.sh [extra xcodebuild arguments, e.g. -only-testing:ScowldTests]
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

# Simulator builds are signed ad hoc ("Sign to Run Locally"): no certificate or
# provisioning profile is needed, and the signature carries the application
# identifier that Keychain access requires (unit and UI tests save provider keys).
status=0
xcodebuild test \
  -project ios/Scowld.xcodeproj \
  -scheme Scowld \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$packages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -resultBundlePath "$results/Tests.xcresult" \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  "$@" \
  2>&1 | tee "$results/xcodebuild.log" || status=$?

# A test bundle that silently ran nothing must fail the run too.
if [[ -e "$results/Tests.xcresult" ]]; then
  python3 scripts/ci/check_xcresult.py "$results/Tests.xcresult" "${bundles[@]}" || status=1
else
  echo 'error: xcodebuild produced no result bundle' >&2
  status=1
fi
echo "Results: $results/Tests.xcresult"
exit "$status"
