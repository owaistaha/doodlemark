#!/bin/bash
# Prints the UDID of an available iPad simulator on the newest installed iOS
# runtime, preferring iPad (A16) (the one the tests are run on locally).
# Used by CI; works locally too:  xcodebuild ... -destination "id=$(scripts/pick_ipad_simulator.sh)"
set -euo pipefail
xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
def version(key):  # com.apple.CoreSimulator.SimRuntime.iOS-26-5 -> (26, 5)
    return tuple(int(p) for p in key.rsplit("iOS-", 1)[1].split("-"))
ios = sorted((k for k in runtimes if ".SimRuntime.iOS-" in k), key=version, reverse=True)
for key in ios:
    ipads = [d for d in runtimes[key] if d["name"].startswith("iPad")]
    if ipads:
        best = next((d for d in ipads if d["name"] == "iPad (A16)"), ipads[0])
        print(best["udid"])
        print(best["name"], "on iOS", ".".join(map(str, version(key))), file=sys.stderr)
        sys.exit(0)
sys.exit("No available iPad simulator")
'
