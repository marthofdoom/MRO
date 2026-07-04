#!/usr/bin/env python3
"""Dump a record's subrecords from any plugin — THE core diagnostic.

Usage:
  tools/dump_record.py <EDID> [--type PERK] [--plugin path.esp]
  tools/dump_record.py MRO_DR76Perk --plugin MRO-nofomod/MRO.esp
  tools/dump_record.py DragonhideSpellPerk            # searches Skyrim.esm

Before creating any new record type, dump a working vanilla record that
does what you want and copy its subrecord list, order, and byte layouts
exactly. Never trust format documentation alone.
"""
import argparse, struct, sys, zlib

SKYRIM = "/mnt/gaming/modlists/LoreRim/Stock Game/Data/Skyrim.esm"

def walk_records(data):
    """Yield (rtype, formid, flags, decompressed_body) for every record."""
    if data[:4] != b'TES4':
        return
    pos = 24 + struct.unpack_from('<I', data, 4)[0]
    stack = [(pos, len(data))]
    while stack:
        p, end = stack.pop()
        while p < end - 24:
            t = data[p:p+4]
            if t == b'GRUP':
                gsize = struct.unpack_from('<I', data, p+4)[0]
                stack.append((p + gsize, end))
                end = p + gsize
                p += 24
                continue
            rs = struct.unpack_from('<I', data, p+4)[0]
            fl = struct.unpack_from('<I', data, p+8)[0]
            fid = struct.unpack_from('<I', data, p+12)[0]
            body = data[p+24:p+24+rs]
            if fl & 0x40000:
                try:
                    body = zlib.decompress(body[4:])
                except zlib.error:
                    body = b''
            yield t, fid, fl, body
            p += 24 + rs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('edid')
    ap.add_argument('--type', help='4-char record type filter, e.g. PERK')
    ap.add_argument('--plugin', default=SKYRIM)
    args = ap.parse_args()
    want_type = args.type.encode() if args.type else None
    with open(args.plugin, 'rb') as f:
        data = f.read()
    target = args.edid.encode() + b'\x00'
    for rtype, fid, fl, body in walk_records(data):
        if want_type and rtype != want_type:
            continue
        if body[:4] != b'EDID':
            continue
        es = struct.unpack_from('<H', body, 4)[0]
        if body[6:6+es] != target:
            continue
        print(f"=== {rtype.decode()} {args.edid} formid={fid:#010x} flags={fl:#x} ===")
        off = 0
        while off < len(body) - 6:
            st = body[off:off+4].decode('ascii', 'replace')
            ss = struct.unpack_from('<H', body, off+4)[0]
            payload = body[off+6:off+6+ss]
            shown = payload.hex() if ss <= 48 else payload[:48].hex() + '...'
            print(f"  {st}({ss}): {shown}")
            off += 6 + ss
        return
    print(f"not found: {args.edid}", file=sys.stderr)
    sys.exit(1)

if __name__ == '__main__':
    main()
