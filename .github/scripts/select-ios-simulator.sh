#!/usr/bin/env bash
# Print the UDID of a bootable iOS simulator, creating one if the runner has none.
#
# GitHub-hosted macOS runners occasionally hand out an image with no pre-created iPhone
# simulators (an image-rollout artifact), which makes a hard-coded
# `-destination 'name=iPhone 16'` fail with "Unable to find a device matching the
# provided destination specifier". This selector is resilient to that and to the device
# lineup changing across image/Xcode updates:
#   1. prefer an existing available "iPhone 16" (matches local dev), else
#   2. the highest-numbered available iPhone, else
#   3. create one from the newest available iOS runtime + highest-numbered iPhone type.
set -euo pipefail

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys

data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(device)


def model_number(device):
    match = re.match(r"iPhone (\d+)", device["name"])
    return int(match.group(1)) if match else -1


preferred = [d for d in candidates if d["name"] == "iPhone 16"]
chosen = preferred[0] if preferred else (max(candidates, key=model_number) if candidates else None)
print(chosen["udid"] if chosen else "")
')"

if [ -z "$udid" ]; then
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys

runtimes = [
    r["identifier"]
    for r in json.load(sys.stdin)["runtimes"]
    if r.get("isAvailable") and "iOS" in r.get("name", "")
]
print(runtimes[-1] if runtimes else "")
')"
    devtype="$(xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys

types = json.load(sys.stdin)["devicetypes"]


def base_model_number(name):
    match = re.match(r"iPhone (\d+)$", name)
    return int(match.group(1)) if match else -1


iphones = [
    (base_model_number(t["name"]), t["identifier"])
    for t in types
    if t.get("name", "").startswith("iPhone")
]
base = [t for t in iphones if t[0] >= 0]
chosen = max(base, key=lambda t: t[0]) if base else (iphones[-1] if iphones else None)
print(chosen[1] if chosen else "")
')"
    if [ -z "$runtime" ] || [ -z "$devtype" ]; then
        echo "select-ios-simulator: no iOS runtime or iPhone device type available" >&2
        exit 1
    fi
    udid="$(xcrun simctl create "CI iPhone" "$devtype" "$runtime")"
fi

echo "$udid"
