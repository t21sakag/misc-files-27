"""Valid, highly compressed oversized image for pre-decode size validation."""
from pathlib import Path
import struct
import sys
import zlib

width, height = 10000, 3000
row = b'\0' + bytes([35, 140, 85]) * width
compressor = zlib.compressobj()
compressed = b''.join(compressor.compress(row) for _ in range(height)) + compressor.flush()
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', compressed) + chunk(b'IEND', b'')
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(image)
