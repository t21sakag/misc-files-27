"""Generate a deterministic public geometric photo fixture; no user images."""
from pathlib import Path
import struct
import sys
import zlib

width, height = 512, 384
rows = bytearray()
for y in range(height):
    rows.append(0)
    for x in range(width):
        if 64 <= x < 224 and 64 <= y < 176:
            color = (210, 55, 55)
        elif (x - 352) ** 2 + (y - 232) ** 2 < 75 ** 2:
            color = (45, 95, 220)
        else:
            color = (248, 248, 248)
        rows.extend(color)
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(image)
