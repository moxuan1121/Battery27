#!/usr/bin/env python3
"""Fail if an arm64e slice has ObjC classes whose isa/superclass are not signed.

iOS 15's libobjc authenticates a class's superclass (DA key, discriminator
0xB5AB) while loading it. 1.0.1 was built by a toolchain that stored these
pointers unsigned, so Safari died in readClass() on A12+ devices as soon as
the dylib was injected. Usage: check_objc_ptrauth.py <dylib>...
"""
import struct
import sys

ISA_DISC = 0x6AE1
SUPER_DISC = 0xB5AB
KEY_DA = 2


def arm64e_slice(data):
    if struct.unpack_from('>I', data)[0] == 0xCAFEBABE:
        for i in range(struct.unpack_from('>I', data, 4)[0]):
            cpu, sub, off, size, _ = struct.unpack_from('>5I', data, 8 + i * 20)
            if cpu == 0x100000C and sub & 0xFF == 2:
                return data[off:off + size]
        return None
    magic, cpu, sub = struct.unpack_from('<III', data)
    return data if magic == 0xFEEDFACF and cpu == 0x100000C and sub & 0xFF == 2 else None


def check(path):
    m = arm64e_slice(open(path, 'rb').read())
    if m is None:
        return [f'{path}: no arm64e slice']
    segs, secs = [], {}
    p = 32
    for _ in range(struct.unpack_from('<I', m, 16)[0]):
        cmd, size = struct.unpack_from('<II', m, p)
        if cmd == 0x19:
            vm, vs, fo, _ = struct.unpack_from('<4Q', m, p + 24)
            segs.append((vm, vs, fo))
            for s in range(struct.unpack_from('<I', m, p + 64)[0]):
                q = p + 72 + s * 80
                name = m[q:q + 16].rstrip(b'\0').decode()
                secs[name] = struct.unpack_from('<QQI', m, q + 32)
        p += size

    def read(va):
        for vm, vs, fo in segs:
            if vm <= va < vm + vs:
                return struct.unpack_from('<Q', m, fo + va - vm)[0]
        raise ValueError(f'unmapped {va:#x}')

    def signed(v, disc):
        return v >> 63 and (v >> 32) & 0xFFFF == disc and (v >> 49) & 3 == KEY_DA

    if '__objc_classlist' not in secs:
        return []
    errors = []
    addr, size, _ = secs['__objc_classlist']
    for i in range(0, size, 8):
        cls = read(addr + i) & 0xFFFFFFFF
        meta = read(cls) & 0xFFFFFFFF
        for kind, va in (('class', cls), ('metaclass', meta)):
            isa, sup = read(va), read(va + 8)
            if not signed(isa, ISA_DISC):
                errors.append(f'{path}: {kind} {va:#x} isa not signed')
            if sup and not signed(sup, SUPER_DISC):
                errors.append(f'{path}: {kind} {va:#x} superclass not signed')
    return errors


if __name__ == '__main__':
    problems = [e for f in sys.argv[1:] for e in check(f)]
    print('\n'.join(problems) or f'OK: ObjC isa/superclass pointers signed in {len(sys.argv) - 1} file(s)')
    sys.exit(1 if problems else 0)
