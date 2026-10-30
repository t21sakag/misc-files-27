"""Read bounded thin ARM64 Mach-O metadata; OS codesign performs validation."""
import plistlib
import struct


def commands(data):
    assert len(data) >= 32 and data[:4] == b'\xcf\xfa\xed\xfe', 'Expected a 64-bit Mach-O executable'
    assert struct.unpack_from('<I', data, 4)[0] == 0x100000c, 'Expected ARM64 executable'
    count, size = struct.unpack_from('<II', data, 16)
    position, end = 32, 32+size
    assert count <= 32768 and size <= 1024*1024 and end <= len(data), 'Invalid load command region'
    for _ in range(count):
        assert position+8 <= end, 'Missing load command'
        command, length = struct.unpack_from('<II', data, position)
        assert length >= 8 and position+length <= end, 'Invalid load command length'
        yield command, position, length
        position += length
    assert position == end, 'Load command region mismatch'


def device_executable(data):
    platforms = []
    for command, position, length in commands(data):
        if command == 0x32:
            assert length >= 24, 'Truncated build platform'
            platforms.append(struct.unpack_from('<I', data, position+8)[0])
    assert platforms == [2], 'Expected iOS device executable, not simulator/macOS'


def xml_entitlements(data):
    signatures = [(position, length) for command,position,length in commands(data) if command == 0x1d]
    assert len(signatures) == 1, 'Expected one code signature'
    position, length = signatures[0]
    assert length >= 16
    offset, size = struct.unpack_from('<II', data, position+8)
    assert size >= 12 and size <= 16*1024*1024 and offset <= len(data)-size, 'Invalid signature region'
    signature = data[offset:offset+size]
    magic, length, count = struct.unpack_from('>III', signature)
    assert magic == 0xfade0cc0 and 12 <= length <= size and count <= (length-12)//8, 'Invalid signature superblob'
    slots = []
    for index in range(count):
        kind, offset = struct.unpack_from('>II', signature, 12+8*index)
        if kind != 5: continue
        assert 12+8*count <= offset <= length-8, 'Invalid XML slot offset'
        magic, size = struct.unpack_from('>II', signature, offset)
        assert magic == 0xfade7171 and 8 <= size <= length-offset, 'Invalid XML entitlement blob'
        value = plistlib.loads(signature[offset+8:offset+size])
        assert isinstance(value,dict), 'Invalid XML entitlement value'
        slots.append(value)
    assert len(slots) == 1, 'Expected one XML entitlement declaration for local resigning'
    return slots[0]
