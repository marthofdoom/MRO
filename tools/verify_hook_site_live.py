#!/usr/bin/env python3
"""Verify a hook site against the RUNNING game's memory (wine process).

Skyrim AE's exe is Steam-DRM encrypted on disk, so tools/verify_hook_site.py
cannot read real code statically. This variant reads /proc/<pid>/mem while
the game runs — decrypted ground truth. Requires the game to be running.

Usage: tools/verify_hook_site_live.py <AL-ID> <hex-insn-offset> <expected-hex>
"""
import re, struct, subprocess, sys, importlib.util

spec = importlib.util.spec_from_file_location(
    "vhs", __file__.replace("_live", ""))
vhs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vhs)


def find_game():
    out = subprocess.run(["pgrep", "-f", r"SkyrimSE\.exe"],
                         capture_output=True, text=True).stdout.split()
    for pid in out:
        try:
            maps = open(f"/proc/{pid}/maps").read()
        except OSError:
            continue
        m = re.search(r"^([0-9a-f]+)-[0-9a-f]+ r--p 00000000 .*SkyrimSE\.exe$",
                      maps, re.M)
        if m:
            return int(pid), int(m.group(1), 16)
    raise SystemExit("SkyrimSE.exe not running (or module base not found)")


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(2)
    al_id = int(sys.argv[1])
    insn_off = int(sys.argv[2], 16)
    expected = bytes.fromhex(sys.argv[3])

    db = vhs.load_database(vhs.VERSIONLIB)
    if al_id not in db:
        raise SystemExit(f"FAIL: ID {al_id} not in database")
    rva = db[al_id]

    pid, base = find_game()
    addr = base + rva + insn_off
    with open(f"/proc/{pid}/mem", "rb", buffering=0) as mem:
        mem.seek(addr)
        actual = mem.read(len(expected))
        mem.seek(base + rva + insn_off - 16)
        ctx = mem.read(48)

    print(f"pid {pid} base {base:#x}; ID {al_id} RVA {rva:#x}; site {addr:#x}")
    print(f"expected: {expected.hex()}")
    print(f"actual:   {actual.hex()}")
    if actual == expected:
        print("MATCH — hook site layout unchanged on this runtime")
    else:
        print(f"MISMATCH — context [-16..+32]: {ctx.hex()}")
        sys.exit(1)


if __name__ == "__main__":
    main()
