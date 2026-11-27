"""Generate opaque RGB app icons for the Cover Room edition (stdlib only)."""
import math
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'Tingye/Resources/Assets.xcassets/AppIcon.appiconset'


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def icon(name, colors):
    # Three oversized, gently fanned clothbound covers; a rising semicircle
    # and four page arcs distinguish our foreground cover at home-screen size.
    palette = [bytes.fromhex(c) for c in colors]
    raw = bytearray()
    stack = [(theta, math.cos(theta), math.sin(theta), dx, dy, color)
             for theta, dx, dy, color in [(-0.19, -50, -5, 1), (0.13, 44, -8, 2), (0, 0, 14, 3)]]
    for y in range(1024):
        raw.append(0)
        for x in range(1024):
            col = 0
            for _, co, si, dx, dy, c in stack:
                ox, oy = x - 512 - dx, y - 512 - dy
                u, v = co * ox + si * oy, -si * ox + co * oy
                if abs(u) >= 228 or abs(v) >= 304:
                    continue
                if max(0, abs(u)-210)**2 + max(0, abs(v)-286)**2 > 18**2:
                    continue
                col = c
                if c == 3:
                    if u < -183: col = 4
                    if (u-84)**2 + (v+133)**2 < 42**2: col = 5
                    if v > -45:
                        r = math.hypot(u-139, (v-320)*0.96)
                        if r < 292 and (int(r)//31)%2 == 0: col = 4
            raw.extend(palette[col])
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',1024,1024,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b'')
    (OUT / name).write_bytes(data)


if __name__ == '__main__':
    icon('AppIcon.png', ('232340','bcb8e5','867fa9','ffc4a6','bd6961','fff0bb'))
    icon('AppIcon-dark.png', ('141426','77729e','4d486f','d79e91','995b65','ffdf97'))
    icon('AppIcon-tinted.png', ('141414','777777','555555','cacaca','858585','f8f8f8'))
