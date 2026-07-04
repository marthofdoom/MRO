#!/usr/bin/env python3
"""Audit MRO.esp against the Papyrus sources. Run after EVERY generator
or script-property change; a FAIL here means runtime breakage.

Checks:
 1. Every VMAD property has a matching Property in the .psc (orphan VMAD
    props log runtime warnings and silently unfill).
 2. Every non-AutoReadOnly .psc Property is wired in the VMAD (unwired =
    None at runtime).
 3. Every shipped .pex is attached to a record, and vice versa.
 4. All own records use the own-file FormID prefix and sit inside the
    ESL-legal 0x800-0xFFF range.

Usage: tools/audit_esp.py   (from repo root or anywhere)
"""
import os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ESP = os.path.join(ROOT, 'MRO-nofomod', 'MRO.esp')
SRC = os.path.join(ROOT, 'Source', 'Scripts')
PEX_DIR = os.path.join(ROOT, 'MRO-nofomod', 'Scripts')
OWN_INDEX = 5   # number of masters; own records carry this prefix
OVERRIDE_GROUPS = {b'LVLI'}   # groups that intentionally hold master formids

def parse_vmads(data):
    vmads = {}
    i = 0
    while True:
        i = data.find(b'VMAD', i)
        if i < 0:
            break
        sz = struct.unpack_from('<H', data, i+4)[0]
        b = data[i+6:i+6+sz]
        try:
            _, _, nscripts = struct.unpack_from('<HHH', b, 0)
            off = 6
            for _ in range(nscripts):
                nl = struct.unpack_from('<H', b, off)[0]; off += 2
                sname = b[off:off+nl].decode(); off += nl
                off += 1
                nprops = struct.unpack_from('<H', b, off)[0]; off += 2
                props = set()
                for _ in range(nprops):
                    pl = struct.unpack_from('<H', b, off)[0]; off += 2
                    pname = b[off:off+pl].decode(); off += pl
                    ptype = b[off]; off += 2
                    if ptype == 1: off += 8
                    elif ptype == 2:
                        sl = struct.unpack_from('<H', b, off)[0]; off += 2 + sl
                    elif ptype in (3, 4): off += 4
                    elif ptype == 5: off += 1
                    else: raise ValueError(f'prop type {ptype}')
                    props.add(pname)
                vmads.setdefault(sname, set()).update(props)
        except Exception:
            pass
        i += 6 + sz
    return vmads

def check_formids(data):
    bad = []
    pos = 24 + struct.unpack_from('<I', data, 4)[0]
    while pos < len(data) - 24:
        if data[pos:pos+4] != b'GRUP':
            break
        gsize = struct.unpack_from('<I', data, pos+4)[0]
        label = data[pos+8:pos+12]
        rp = pos + 24
        while rp < pos + gsize - 23:
            rt = data[rp:rp+4]
            rs = struct.unpack_from('<I', data, rp+4)[0]
            fid = struct.unpack_from('<I', data, rp+12)[0]
            if fid != 0 and label not in OVERRIDE_GROUPS and rt != b'GMST' or rt == b'GMST':
                if label not in OVERRIDE_GROUPS:
                    if (fid >> 24) != OWN_INDEX:
                        bad.append(f'{rt.decode()} {fid:#010x}: wrong own prefix (want {OWN_INDEX:#x})')
                    elif not (0x800 <= (fid & 0xFFFFFF) <= 0xFFF):
                        bad.append(f'{rt.decode()} {fid:#010x}: outside ESL range 0x800-0xFFF')
            rp += 24 + rs
        pos += gsize
    return bad

def main():
    with open(ESP, 'rb') as f:
        data = f.read()
    vmads = parse_vmads(data)
    ok = True

    for script in sorted(vmads):
        psc = os.path.join(SRC, script + '.psc')
        if not os.path.exists(psc):
            print(f'FAIL {script}: VMAD references script with no source')
            ok = False
            continue
        src = open(psc).read()
        declared = set(re.findall(r'^\s*\S+(?:\[\])?\s+Property\s+(\w+)\s', src, re.M | re.I))
        autoread = set(re.findall(r'Property\s+(\w+)\s*=.*AutoReadOnly', src, re.I))
        orphan = vmads[script] - declared
        unwired = declared - vmads[script] - autoread
        if orphan:
            print(f'FAIL {script}: VMAD props with no script property: {sorted(orphan)}')
            ok = False
        if unwired:
            print(f'FAIL {script}: script props never wired: {sorted(unwired)}')
            ok = False

    shipped = {f[:-4] for f in os.listdir(PEX_DIR) if f.endswith('.pex')}
    if shipped != set(vmads):
        print(f'FAIL pex mismatch: shipped={sorted(shipped)} referenced={sorted(vmads)}')
        ok = False

    for msg in check_formids(data):
        print('FAIL', msg)
        ok = False

    print('AUDIT', 'PASS' if ok else 'FAIL')
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
