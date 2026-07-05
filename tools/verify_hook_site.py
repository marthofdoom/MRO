#!/usr/bin/env python3
"""Verify a native hook site against the LOCAL game binary before shipping.

Resolves an Address Library ID to this machine's binary offset, then
compares the actual bytes at (address + instruction offset) with the
bytes a reference mod documents for its patch site. Match = the
function layout is unchanged on our runtime = the hook is proven safe.
Mismatch = DO NOT ship the hook; the game version reorganized the code.

Usage:
  tools/verify_hook_site.py <AL-ID> <hex-offset> <expected-hex-bytes>
  tools/verify_hook_site.py 44014 0xFF 0F57C9F30F104D77

Decode logic ported from CommonLibSSE-NG's REL::IDDatabase (unpack_file).
"""
import struct, sys

VERSIONLIB = ("/mnt/gaming/modlists/LoreRim/mods/Address Library for SKSE Plugins"
              "/SKSE/Plugins/versionlib-1-6-1170-0.bin")
GAME_EXE = "/mnt/gaming/modlists/LoreRim/Stock Game/SkyrimSE.exe"


def load_database(path):
    with open(path, 'rb') as f:
        data = f.read()
    pos = 0
    def rd(fmt):
        nonlocal pos
        vals = struct.unpack_from(fmt, data, pos)
        pos += struct.calcsize(fmt)
        return vals[0] if len(vals) == 1 else vals
    fmt_ver = rd('<i')
    assert fmt_ver == 2, f"unsupported AL format {fmt_ver}"
    rd('<4i')                       # game version
    name_len = rd('<i')
    pos += name_len                 # module name
    ptr_size = rd('<i')
    count = rd('<i')

    id2off = {}
    prev_id = prev_off = 0
    for _ in range(count):
        t = rd('<B')
        lo, hi = t & 0xF, t >> 4
        if lo == 0:   cur_id = rd('<Q')
        elif lo == 1: cur_id = prev_id + 1
        elif lo == 2: cur_id = prev_id + rd('<B')
        elif lo == 3: cur_id = prev_id - rd('<B')
        elif lo == 4: cur_id = prev_id + rd('<H')
        elif lo == 5: cur_id = prev_id - rd('<H')
        elif lo == 6: cur_id = rd('<H')
        elif lo == 7: cur_id = rd('<I')
        else: raise ValueError(f"id type {lo}")
        tmp = (prev_off // ptr_size) if (hi & 8) else prev_off
        h = hi & 7
        if h == 0:   off = rd('<Q')
        elif h == 1: off = tmp + 1
        elif h == 2: off = tmp + rd('<B')
        elif h == 3: off = tmp - rd('<B')
        elif h == 4: off = tmp + rd('<H')
        elif h == 5: off = tmp - rd('<H')
        elif h == 6: off = rd('<H')
        elif h == 7: off = rd('<I')
        else: raise ValueError(f"off type {h}")
        if hi & 8:
            off *= ptr_size
        id2off[cur_id] = off
        prev_id, prev_off = cur_id, off
    return id2off


def rva_to_file_offset(exe_data, rva):
    e_lfanew = struct.unpack_from('<I', exe_data, 0x3C)[0]
    nsec = struct.unpack_from('<H', exe_data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from('<H', exe_data, e_lfanew + 20)[0]
    sec0 = e_lfanew + 24 + opt_size
    for i in range(nsec):
        s = sec0 + i * 40
        vsize, va, rsize, rptr = struct.unpack_from('<IIII', exe_data, s + 8)
        if va <= rva < va + max(vsize, rsize):
            return rptr + (rva - va)
    raise ValueError(f"RVA {rva:#x} not in any section")


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(2)
    al_id = int(sys.argv[1])
    insn_off = int(sys.argv[2], 16)
    expected = bytes.fromhex(sys.argv[3])

    db = load_database(VERSIONLIB)
    if al_id not in db:
        print(f"FAIL: ID {al_id} not in database")
        sys.exit(1)
    rva = db[al_id]
    with open(GAME_EXE, 'rb') as f:
        exe = f.read()
    fo = rva_to_file_offset(exe, rva + insn_off)
    actual = exe[fo:fo + len(expected)]

    print(f"ID {al_id} -> RVA {rva:#x}; site RVA {rva + insn_off:#x} (file {fo:#x})")
    print(f"expected: {expected.hex()}")
    print(f"actual:   {actual.hex()}")
    if actual == expected:
        print("MATCH — hook site layout unchanged on this runtime")
    else:
        # print surrounding bytes to help relocate the site
        ctx = exe[fo - 16:fo + 32]
        print(f"MISMATCH — context [-16..+32]: {ctx.hex()}")
        sys.exit(1)


if __name__ == '__main__':
    main()
