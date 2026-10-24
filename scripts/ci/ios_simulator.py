#!/usr/bin/env python3
"""The iPhone simulator that scripts/test-ios.sh tests on.

  ios_simulator.py pick                  prints "<device type id> <runtime id>"
  ios_simulator.py cache-key             prints "key=..." for $GITHUB_OUTPUT
  ios_simulator.py check <udid> <device type id> <runtime id>
                                         fails unless CoreSimulator lists that
                                         simulator, shut down and usable, with
                                         that device type and runtime
  ios_simulator.py wait-idle <seconds>   returns once the booted simulator's
                                         first-boot work looks over, or after
                                         <seconds>

The newest available iOS 17+ runtime that offers an iPhone 17 Pro is used (a newer
device-specific runtime, such as iOS 27.1 with only the iPhone Duo, is skipped);
without one, the newest runtime and its last iPhone. The cache key names everything
a saved simulator depends on: the runner image, Xcode, the runtime build and the
device type, so a change to any of them starts from a new simulator.
"""
from __future__ import annotations

import collections
import json
import os
import platform
import re
import subprocess
import sys
import time


def simctl_json(*sections: str) -> dict:
    return json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '--json', *sections]))


def version(runtime: dict) -> tuple[int, ...]:
    return tuple(int(part) for part in runtime['version'].split('.'))


def pick() -> tuple[dict, dict]:
    runtimes = [r for r in simctl_json('runtimes')['runtimes'] if r.get('isAvailable') and
                '.iOS-' in r['identifier'] and version(r) >= (17, 0)]
    if not runtimes:
        raise SystemExit('Install an iOS 17 or newer Simulator runtime in Xcode.')
    # A device-specific runtime can be newer than the general one (iOS 27.1 ships only the
    # iPhone Duo, a 386x678 pt screen), so take the newest runtime that offers the preferred
    # device instead of the newest runtime overall.
    runtime = max((r for r in runtimes if any(d['name'] == 'iPhone 17 Pro' for d in r.get('supportedDeviceTypes', []))),
                  key=version, default=max(runtimes, key=version))
    iphones = [d for d in runtime.get('supportedDeviceTypes', []) if d.get('productFamily') == 'iPhone']
    if not iphones:
        raise SystemExit('Selected runtime has no supported iPhone device type.')
    device = next((d for d in iphones if d['name'] == 'iPhone 17 Pro'), iphones[-1])
    return device, runtime


def cache_key() -> str:
    device, runtime = pick()
    xcode = re.search(r'Build version (\S+)', subprocess.check_output(['xcodebuild', '-version'], text=True))
    if not xcode:
        raise SystemExit('Could not read the Xcode build version.')
    parts = [
        'ios-simulator',
        os.environ.get('ImageOS', 'local'),
        os.environ.get('ImageVersion', 'local'),
        platform.machine(),
        'xcode-' + xcode.group(1),
        'runtime-' + runtime['buildversion'],
        device['identifier'].rsplit('.', 1)[-1],
        'v1',
    ]
    return '-'.join(re.sub(r'[^A-Za-z0-9._-]+', '_', part) for part in parts)


def check(udid: str, device_type: str, runtime: str) -> None:
    for runtime_id, devices in simctl_json('devices')['devices'].items():
        for device in devices:
            if device['udid'] != udid:
                continue
            problems = []
            if runtime_id != runtime:
                problems.append(f'runtime {runtime_id}, expected {runtime}')
            if device.get('deviceTypeIdentifier') != device_type:
                problems.append(f"device type {device.get('deviceTypeIdentifier')}, expected {device_type}")
            if not device.get('isAvailable'):
                problems.append(f"unavailable ({device.get('availabilityError', 'no reason given')})")
            if device.get('state') != 'Shutdown':
                problems.append(f"state {device.get('state')}")
            if problems:
                raise SystemExit(f'Simulator {udid}: ' + '; '.join(problems))
            return
    raise SystemExit(f'CoreSimulator does not list simulator {udid}.')


def cpu_seconds(text: str) -> float:
    total = 0.0
    for part in text.split(':'):  # ps prints minutes:seconds, with hours when needed
        total = total * 60 + float(part)
    return total


def simulator_processes() -> dict[str, tuple[float, str]]:
    """CPU seconds so far of every process running from a simulator runtime or device."""
    out = subprocess.run(['ps', '-A', '-o', 'pid=,time=,comm='], capture_output=True,
                         text=True, timeout=120).stdout
    found = {}
    for line in out.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and ('/CoreSimulator/' in parts[2] or 'RuntimeRoot' in parts[2]
                                or os.path.basename(parts[2]).startswith('SimRender')):
            try:
                found[parts[0]] = (cpu_seconds(parts[1]), os.path.basename(parts[2]))
            except ValueError:
                pass
    return found


# diagnosticd (the log daemon) and apsd (push notifications) keep using about 0.4 of a
# core in every booted simulator on the runner, set up or not; they are left out.
ALWAYS_BUSY = {'diagnosticd', 'apsd'}


def wait_idle(limit: float) -> None:
    """Returns once the simulator's other processes used under half a core for 3 minutes.

    While a first boot's work goes on they use 1 to 2 cores; once it is over, a few
    hundred processes still add up to 0.2 to 0.45 of a core between them.
    """
    window, threshold = 180.0, 0.5
    started = last_report = time.monotonic()
    samples = collections.deque()  # (time, seconds since the last sample, CPU seconds used per name)
    previous, before = simulator_processes(), started
    while True:
        time.sleep(5)
        now = time.monotonic()
        current = simulator_processes()
        used = collections.Counter()
        for pid, (cpu, name) in current.items():
            if name not in ALWAYS_BUSY:
                old = previous.get(pid)
                used[name] += cpu - old[0] if old and old[1] == name else cpu
        samples.append((now, now - before, used))
        previous, before = current, now
        while samples and samples[0][0] <= now - window:
            samples.popleft()
        covered = sum(interval for _, interval, _ in samples)
        total = collections.Counter()
        for _, _, item in samples:
            total.update(item)
        cores = sum(total.values()) / covered
        idle = covered >= window - 10 and cores < threshold
        if idle or now - last_report >= 60:
            top = ', '.join(f'{name} {cpu:.0f} s' for name, cpu in total.most_common(3)) or 'nothing'
            print(f'{now - started:4.0f} s: the simulator used {cores:.2f} cores over the last '
                  f'{covered:.0f} s ({top})', flush=True)
            last_report = now
        if idle:
            return
        if now - started >= limit:
            print(f'The simulator is still using {cores:.2f} cores after {limit:.0f} s; going on.',
                  flush=True)
            return


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'pick' and len(sys.argv) == 2:
        device, runtime = pick()
        print(device['identifier'], runtime['identifier'])
    elif command == 'cache-key' and len(sys.argv) == 2:
        print('key=' + cache_key())
    elif command == 'check' and len(sys.argv) == 5:
        check(*sys.argv[2:])
    elif command == 'wait-idle' and len(sys.argv) == 3:
        wait_idle(float(sys.argv[2]))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
