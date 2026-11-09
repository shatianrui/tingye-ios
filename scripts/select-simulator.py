"""Select the newest installed iPhone runtime; simctl JSON order is not version order."""
import json
import re
import sys

candidates = [
    (tuple(map(int, re.findall(r'\d+', runtime))), device)
    for runtime, devices in json.load(sys.stdin)['devices'].items()
    if '.iOS-' in runtime
    for device in devices
    if device.get('isAvailable', False) and device['name'].startswith('iPhone')
]
if not candidates:
    raise SystemExit('No available iPhone simulator runtime')
version, device = max(candidates, key=lambda pair: pair[0])
print('Selected ' + device['name'] + ', iOS ' + '.'.join(map(str, version)), file=sys.stderr)
print(device['udid'])
