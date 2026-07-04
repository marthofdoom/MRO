#!/usr/bin/env python3
"""
MRO_GenerateESP.py
Generates MRO.esp for Marth Requiem Overhaul without needing SSEEdit/xEdit.
Produces a byte-for-byte valid Skyrim SE plugin.

Run: python3 MRO_GenerateESP.py [output_dir]
Default output: current directory
"""

import struct
import sys
import os
from io import BytesIO

# ──────────────────────────────────────────────────────────────────────────────
# FormIDs (plugin-local unless noted)
# Master order in TES4: 0=Skyrim.esm, 1=Update.esm, 2=Dawnguard.esm,
#                        3=HearthFires.esm, 4=Dragonborn.esm
# ──────────────────────────────────────────────────────────────────────────────

# Referenced from masters (upper byte = master index in THIS plugin's load order)
FREF_PLAYER        = 0x00000014  # Skyrim.esm  PlayerRef
FREF_MQ206         = 0x00036193  # Skyrim.esm  MQ206_AlduinsBane
FREF_MQ305         = 0x00046EF2  # Skyrim.esm  MQ305_Sovngarde
FREF_KW_FIRE       = 0x000424EF  # Skyrim.esm  MagicDamageFire
FREF_KW_FROST      = 0x00044BDC  # Skyrim.esm  MagicDamageFrost
FREF_KW_SHOCK      = 0x00044BDE  # Skyrim.esm  MagicDamageShock
FREF_DLC1_HARKON   = 0x02003C25  # Dawnguard (master idx 2): DLC1VQ08  (0x3C25 local)
FREF_DLC2_MIRAAK   = 0x0401B9D7  # Dragonborn (master idx 4): DLC2MQ06 (0x179D7 local)

# Wait — let's recalculate. The raw FormIDs from parsing are:
# Dawnguard.esm: DLC1VQ08 = 0x02007c25   (master-local, upper byte = 0x02 = Dawnguard's own index)
# Dragonborn.esm: DLC2MQ06 = 0x020179d7  (same)
# In MRO.esp, master index 2 = Dawnguard.esm, master index 4 = Dragonborn.esm.
# Formula: (master_idx_in_MRO << 24) | (raw_formid & 0x00FFFFFF)
FREF_DLC1_HARKON   = (2 << 24) | (0x02007C25 & 0x00FFFFFF)  # = 0x02007C25
FREF_DLC2_MIRAAK   = (4 << 24) | (0x020179D7 & 0x00FFFFFF)  # = 0x040179D7

# Our plugin's own records. With 5 masters, this file's own index is 0x05 —
# records MUST carry that prefix. A 0x00 prefix injects into Skyrim.esm's
# FormID space and collides with real records (0x00000810 is a Skyrim.esm
# IMAD — that collision silently killed the MCM quest for days).
OWN = 0x05000000

FID_ABSORB_MGEF    = OWN | 0x800
FID_ABSORB_SPELL   = OWN | 0x801
FID_CW_MGEF        = OWN | 0x802
FID_CW_SPELL       = OWN | 0x803
FID_G_RESISTCAP    = OWN | 0x804
FID_G_ARMORCAP     = OWN | 0x805
FID_G_ABSORB       = OWN | 0x806
FID_G_CARRYWEIGHT  = OWN | 0x807
FID_G_ARROWRECOV   = OWN | 0x809
FID_G_CELLRESET    = OWN | 0x80A
FID_G_SETUPDONE    = OWN | 0x80B
FID_G_MASTERYENA   = OWN | 0x80C
FID_G_MASTERYGNT   = OWN | 0x80D
FID_G_MASTERYCAP   = OWN | 0x80E
FID_STARTUP_QUEST  = OWN | 0x80F
FID_MCM_QUEST      = OWN | 0x810
FID_GMST_MAXRESIST = OWN | 0x811  # fPlayerMaxResistance override
FID_DR_PERK_BASE   = OWN | 0x820  # 24 hidden perks: 76%..99% physical DR
FID_DR_FLST        = OWN | 0x838  # FormList holding the 24 DR perks in order

# ──────────────────────────────────────────────────────────────────────────────
# Binary helpers
# ──────────────────────────────────────────────────────────────────────────────
FORM_VERSION = 44   # 0x2C — Skyrim SE

def subrec(rtype: str, data: bytes) -> bytes:
    assert len(rtype) == 4
    return rtype.encode('ascii') + struct.pack('<H', len(data)) + data

def record(rtype: str, formid: int, flags: int, data: bytes) -> bytes:
    assert len(rtype) == 4
    hdr = (rtype.encode('ascii')
           + struct.pack('<I', len(data))
           + struct.pack('<I', flags)
           + struct.pack('<I', formid)
           + struct.pack('<I', 0)          # VCI1
           + struct.pack('<H', FORM_VERSION)
           + struct.pack('<H', 0))         # VCI2
    return hdr + data

def group(label: str, records_data: bytes) -> bytes:
    """Top-level group (type 0)."""
    assert len(label) == 4
    total = 24 + len(records_data)
    hdr = (b'GRUP'
           + struct.pack('<I', total)
           + label.encode('ascii')
           + struct.pack('<i', 0)   # group type 0
           + struct.pack('<I', 0)   # stamp
           + struct.pack('<I', 0))  # unknown
    return hdr + records_data

def zstr(s: str) -> bytes:
    return s.encode('ascii') + b'\x00'

# ──────────────────────────────────────────────────────────────────────────────
# VMAD builder (Skyrim SE object format 2)
# ──────────────────────────────────────────────────────────────────────────────
VMAD_VERSION = 5
OBJECT_FORMAT = 2

class VMADBuilder:
    def __init__(self):
        self.scripts = []

    def add_script(self, name: str, props: list):
        """props: list of (name, value) where value is int/float/bool/formid(int)
           Use prop_obj(formid) for Object type, prop_int, prop_float, prop_bool, prop_str."""
        self.scripts.append((name, props))

    def build(self) -> bytes:
        buf = BytesIO()
        buf.write(struct.pack('<H', VMAD_VERSION))
        buf.write(struct.pack('<H', OBJECT_FORMAT))
        buf.write(struct.pack('<H', len(self.scripts)))
        for name, props in self.scripts:
            enc = name.encode('ascii')
            buf.write(struct.pack('<H', len(enc)))
            buf.write(enc)
            buf.write(struct.pack('<B', 0))   # status: 0 (matches CK output)
            buf.write(struct.pack('<H', len(props)))
            for pname, pval in props:
                penc = pname.encode('ascii')
                buf.write(struct.pack('<H', len(penc)))
                buf.write(penc)
                buf.write(bytes([pval[0]]))   # type byte
                buf.write(struct.pack('<B', 1))  # status: edited
                buf.write(pval[1:])           # value bytes
        return buf.getvalue()

def prop_obj(formid: int) -> bytes:
    # Object format 2 (SSE): Unused(uint16) + AliasID(int16, -1=not alias) + FormID(uint32)
    return bytes([1]) + struct.pack('<H', 0) + struct.pack('<h', -1) + struct.pack('<I', formid)

def prop_str(s: str) -> bytes:
    enc = s.encode('ascii')
    return bytes([2]) + struct.pack('<H', len(enc)) + enc

def prop_int(v: int) -> bytes:
    return bytes([3]) + struct.pack('<i', v)

def prop_float(v: float) -> bytes:
    return bytes([4]) + struct.pack('<f', v)

def prop_bool(v: bool) -> bytes:
    return bytes([5]) + struct.pack('<B', 1 if v else 0)

# ──────────────────────────────────────────────────────────────────────────────
# TES4 — File Header
# ──────────────────────────────────────────────────────────────────────────────
def make_tes4() -> bytes:
    masters = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"]
    hedr = struct.pack('<f', 1.70) + struct.pack('<I', 200) + struct.pack('<I', FID_DR_FLST + 1)
    body  = subrec('HEDR', hedr)
    body += subrec('CNAM', zstr("Marth"))
    body += subrec('SNAM', zstr("Marth Requiem Overhaul v0.3.1"))
    for m in masters:
        body += subrec('MAST', zstr(m))
        body += subrec('DATA', struct.pack('<Q', 0))
    return record('TES4', 0x00000000, 0x00000200, body)

# ──────────────────────────────────────────────────────────────────────────────
# GLOB — Global Variables
# ──────────────────────────────────────────────────────────────────────────────
GLOBALS = [
    ("MRO_F_ResistCap",    FID_G_RESISTCAP,   'f', 1.0),
    ("MRO_F_ArmorCap",     FID_G_ARMORCAP,    'f', 1.0),
    ("MRO_F_Absorb",       FID_G_ABSORB,      'f', 1.0),
    ("MRO_F_CarryWeight",  FID_G_CARRYWEIGHT, 'f', 1.0),
    ("MRO_F_ArrowRecovery",FID_G_ARROWRECOV,  'f', 1.0),
    ("MRO_F_CellReset",    FID_G_CELLRESET,   'f', 1.0),
    ("MRO_SetupDone",      FID_G_SETUPDONE,   'f', 0.0),
    ("MRO_MasteryEnabled", FID_G_MASTERYENA,  'f', 1.0),
    ("MRO_MasteryBaseGrant",FID_G_MASTERYGNT, 'f', 1.0),
    ("MRO_MasteryCap",     FID_G_MASTERYCAP,  'f', 100.0),
]

def make_globs() -> bytes:
    out = BytesIO()
    for edid, fid, gtype, val in GLOBALS:
        body  = subrec('EDID', zstr(edid))
        body += subrec('FNAM', gtype.encode('ascii'))
        body += subrec('FLTV', struct.pack('<f', val))
        out.write(record('GLOB', fid, 0, body))
    return group('GLOB', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# MGEF — Magic Effects
# ──────────────────────────────────────────────────────────────────────────────

# MGEF DATA layout (Skyrim SE, 152 bytes).
# Real MGEFs from Skyrim.esm confirm DATA=152. DNAM is a separate 4-byte subrecord
# (localized description string index) — we omit it for non-localized plugins.

def mgef_data(effect_type: int, primary_av: int, casting_type: int = 0, delivery: int = 0) -> bytes:
    # 152 bytes. Field positions verified against Requiem.esp scripted/value-mod MGEFs:
    #   [64] EffectType  (0=ValueModifier, 1=Script, …)
    #   [68] Primary AV
    #   [80] CastingType (0=Constant, 1=FireAndForget, 2=Concentration)
    #   [84] Delivery    (0=Self, 2=Aimed, …)
    #   [88] Secondary AV (0xFFFFFFFF=none)
    #  [112] DualCastScale (1.0)
    d = bytearray(152)
    struct.pack_into('<I', d, 12, 0xFFFFFFFF)  # MagicSkill = none
    struct.pack_into('<I', d, 16, 0xFFFFFFFF)  # MinSkillLevel = none
    struct.pack_into('<I', d, 64, effect_type)
    struct.pack_into('<I', d, 68, primary_av)
    struct.pack_into('<I', d, 80, casting_type)
    struct.pack_into('<I', d, 84, delivery)
    struct.pack_into('<I', d, 88, 0xFFFFFFFF)  # SecondaryAV = none
    struct.pack_into('<f', d, 112, 1.0)        # DualCastScale
    assert len(d) == 152
    return bytes(d)

AV_CARRYWEIGHT = 32  # kCarryWeight in Skyrim actor value enum

def make_mgefs() -> bytes:
    out = BytesIO()

    # ── AbsorbMGEF: scripted, OnHit handler, no AV change ──
    # No properties: the script resolves resistances generically via
    # SKSE GetResistance() and PO3 archetype checks.
    vmad = VMADBuilder()
    vmad.add_script("MRO_AbsorbMGEF", [])
    body  = subrec('EDID', zstr("MRO_AbsorbMGEF"))
    body += subrec('FULL', zstr("Elemental Absorb"))
    body += subrec('VMAD', vmad.build())
    body += subrec('DATA', mgef_data(effect_type=1, primary_av=0xFFFFFFFF))
    out.write(record('MGEF', FID_ABSORB_MGEF, 0, body))

    # ── CarryWeightMGEF: value modifier on CarryWeight, +150 ──
    body  = subrec('EDID', zstr("MRO_CarryWeightMGEF"))
    body += subrec('FULL', zstr("Carry Weight Bonus"))
    body += subrec('DATA', mgef_data(effect_type=0, primary_av=AV_CARRYWEIGHT))
    out.write(record('MGEF', FID_CW_MGEF, 0, body))

    return group('MGEF', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# SPEL — Spell (Ability type)
# SPIT: (cost:f)(flags:I)(type:I)(chargeTime:f)(castType:I)(delivery:I)(castDuration:f)(range:f)(perk:I)
# type 3 = Ability, castType 0 = Constant Effect, delivery 0 = Self
# ──────────────────────────────────────────────────────────────────────────────
def spit(spell_type=3, cast_type=0, delivery=0, cost=0.0, flags=0x00000000) -> bytes:
    return (struct.pack('<f', cost)
            + struct.pack('<I', flags)
            + struct.pack('<I', spell_type)
            + struct.pack('<f', 0.0)   # charge time
            + struct.pack('<I', cast_type)
            + struct.pack('<I', delivery)
            + struct.pack('<f', 0.0)   # cast duration
            + struct.pack('<f', 0.0)   # range
            + struct.pack('<I', 0))    # perk

def spell_effect(mgef_fid: int, magnitude: float, area: int = 0, duration: int = 0) -> bytes:
    efid = subrec('EFID', struct.pack('<I', mgef_fid))
    efit = subrec('EFIT', struct.pack('<f', magnitude) + struct.pack('<I', area) + struct.pack('<I', duration))
    return efid + efit

def make_spels() -> bytes:
    out = BytesIO()

    # AbsorbAbility
    body  = subrec('EDID', zstr("MRO_AbsorbAbility"))
    body += subrec('FULL', zstr("Elemental Absorb"))
    body += subrec('SPIT', spit())
    body += spell_effect(FID_ABSORB_MGEF, 1.0)
    out.write(record('SPEL', FID_ABSORB_SPELL, 0, body))

    # CarryWeightAbility
    body  = subrec('EDID', zstr("MRO_CarryWeightAbility"))
    body += subrec('FULL', zstr("Carry Weight Bonus"))
    body += subrec('SPIT', spit())
    body += spell_effect(FID_CW_MGEF, 150.0)
    out.write(record('SPEL', FID_CW_SPELL, 0, body))

    return group('SPEL', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# QUST — Quests
# ──────────────────────────────────────────────────────────────────────────────

# DNAM: (priority:B)(unknown:3B)(flags:H)(type:H)
# flags: 0x0001 = Start Game Enabled, 0x0004 = Run Once
QUST_FLAGS_STARTUP = 0x0001 | 0x0004  # startup quest: start once, run once
QUST_FLAGS_MCM     = 0x0001           # MCM quest: start game enabled only, never Run Once

def qust_dnam(priority: int = 20, flags: int = QUST_FLAGS_STARTUP) -> bytes:
    # 12 bytes (verified against real mod QUST). Extra uint32 at end is SSE addition.
    return (struct.pack('<B', priority)
            + b'\x01\x00\xff'      # unknown bytes (matched from real QUST output)
            + struct.pack('<H', flags)
            + struct.pack('<H', 0)  # type
            + struct.pack('<I', 0)) # SSE extra uint32

def make_startup_quest() -> bytes:
    vmad = VMADBuilder()
    vmad.add_script("MRO_StartupQuest", [
        ("PlayerRef",            prop_obj(FREF_PLAYER)),
        ("MRO_AbsorbAbility",    prop_obj(FID_ABSORB_SPELL)),
        ("MRO_CarryWeightAbility", prop_obj(FID_CW_SPELL)),
        ("MRO_F_ResistCap",      prop_obj(FID_G_RESISTCAP)),
        ("MRO_F_ArmorCap",       prop_obj(FID_G_ARMORCAP)),
        ("MRO_F_Absorb",         prop_obj(FID_G_ABSORB)),
        ("MRO_F_CarryWeight",    prop_obj(FID_G_CARRYWEIGHT)),
        ("MRO_F_ArrowRecovery",  prop_obj(FID_G_ARROWRECOV)),
        ("MRO_F_CellReset",      prop_obj(FID_G_CELLRESET)),
        ("MRO_SetupDone",        prop_obj(FID_G_SETUPDONE)),
        ("MRO_MasteryEnabled",   prop_obj(FID_G_MASTERYENA)),
        ("MRO_MasteryBaseGrant", prop_obj(FID_G_MASTERYGNT)),
        ("MRO_MasteryCap",       prop_obj(FID_G_MASTERYCAP)),
        ("MRO_DRPerks",          prop_obj(FID_DR_FLST)),
    ])
    body  = subrec('EDID', zstr("MRO_StartupQuest"))
    body += subrec('FULL', zstr("MRO Startup"))
    body += subrec('VMAD', vmad.build())
    body += subrec('DNAM', qust_dnam(priority=20))
    body += subrec('NEXT', b'')
    body += subrec('ANAM', struct.pack('<I', 0))
    return record('QUST', FID_STARTUP_QUEST, 0, body)

def make_mcm_quest() -> bytes:
    vmad = VMADBuilder()
    vmad.add_script("MRO_MCM", [
        ("MRO_Quest",            prop_obj(FID_STARTUP_QUEST)),
        ("MQ206_AlduinsBane",    prop_obj(FREF_MQ206)),
        ("MQ305_Sovngarde",      prop_obj(FREF_MQ305)),
        ("DLC1VQ08_Harkon",      prop_obj(FREF_DLC1_HARKON)),
        ("DLC2MQ06_Miraak",      prop_obj(FREF_DLC2_MIRAAK)),
        ("MRO_MasteryEnabled",   prop_obj(FID_G_MASTERYENA)),
        ("MRO_MasteryBaseGrant", prop_obj(FID_G_MASTERYGNT)),
        ("MRO_MasteryCap",       prop_obj(FID_G_MASTERYCAP)),
        ("MRO_F_ResistCap",      prop_obj(FID_G_RESISTCAP)),
        ("MRO_F_ArmorCap",       prop_obj(FID_G_ARMORCAP)),
        ("MRO_F_Absorb",         prop_obj(FID_G_ABSORB)),
        ("MRO_F_CarryWeight",    prop_obj(FID_G_CARRYWEIGHT)),
        ("MRO_F_ArrowRecovery",  prop_obj(FID_G_ARROWRECOV)),
        ("MRO_F_CellReset",      prop_obj(FID_G_CELLRESET)),
    ])
    body  = subrec('EDID', zstr("MRO_MCMQuest"))
    body += subrec('FULL', zstr("MRO MCM"))
    body += subrec('VMAD', vmad.build())
    body += subrec('DNAM', qust_dnam(priority=20, flags=QUST_FLAGS_MCM))
    body += subrec('NEXT', b'')
    body += subrec('ANAM', struct.pack('<I', 0))
    return record('QUST', FID_MCM_QUEST, 0, body)

# ──────────────────────────────────────────────────────────────────────────────
# LVLI — Vendor gold doubled
# Scans the LoreRim load order for the winning override of each vanilla
# VendorGold* leveled list, doubles every LVLO gold count, and emits the
# result as an override (same FormID, master 0 = Skyrim.esm).
# ──────────────────────────────────────────────────────────────────────────────
import zlib

VENDOR_GOLD_FIDS = {
    0x00072ae7: "VendorGoldMisc",
    0x00072ae8: "VendorGoldApothecary",
    0x00072ae9: "VendorGoldBlacksmith",
    0x00072aea: "VendorGoldInn",
    0x00072aeb: "VendorGoldStreetVendor",
    0x00072aec: "VendorGoldSpells",
    0x00072aed: "VendorGoldBlacksmithOrc",
    0x00017102: "VendorGoldBlacksmithTown",
    0x000d54bf: "VendorGoldFenceStage00",
    0x000d54c0: "VendorGoldFenceStage01",
    0x000d54c1: "VendorGoldFenceStage02",
    0x000d54c2: "VendorGoldFenceStage03",
    0x000d54c3: "VendorGoldFenceStage04",
}

LORERIM_PROFILE = "/mnt/gaming/modlists/LoreRim/profiles/Default"
LORERIM_MODS    = "/mnt/gaming/modlists/LoreRim/mods"
STOCK_DATA      = "/mnt/gaming/modlists/LoreRim/Stock Game/Data"

def _load_order() -> list:
    """Enabled plugin file paths in load order, resolved through MO2's VFS."""
    with open(os.path.join(LORERIM_PROFILE, "plugins.txt"), encoding='utf-8') as f:
        plugins = [ln[1:].strip() for ln in f if ln.startswith('*')]

    # modlist.txt: first line = highest priority mod
    mod_priority = []
    with open(os.path.join(LORERIM_PROFILE, "modlist.txt"), encoding='utf-8') as f:
        for ln in f:
            if ln.startswith('+'):
                mod_priority.append(ln[1:].strip())

    def resolve(name):
        for mod in mod_priority:
            p = os.path.join(LORERIM_MODS, mod, name)
            if os.path.isfile(p):
                return p
        p = os.path.join(STOCK_DATA, name)
        return p if os.path.isfile(p) else None

    base = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"]
    ordered = base + [p for p in plugins if p not in base and p != "MRO.esp"]
    return [(n, resolve(n)) for n in ordered if resolve(n)]

def _scan_plugin_lvli(path: str, targets: dict, winners: dict):
    """Update winners{local_fid: body_bytes} with this plugin's LVLI overrides."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'TES4':
        return
    tes4_size = struct.unpack_from('<I', data, 4)[0]
    tes4_body = data[24:24 + tes4_size]

    # Which master index is Skyrim.esm in this plugin?
    masters, off = [], 0
    while off < len(tes4_body) - 6:
        stype = tes4_body[off:off+4]
        ssize = struct.unpack_from('<H', tes4_body, off+4)[0]
        if stype == b'MAST':
            masters.append(tes4_body[off+6:off+6+ssize].rstrip(b'\x00').decode('ascii', 'replace').lower())
        off += 6 + ssize
    if path.endswith("Skyrim.esm"):
        sk_idx = 0
    elif "skyrim.esm" in masters:
        sk_idx = masters.index("skyrim.esm")
    else:
        return

    pos = 24 + tes4_size
    n = len(data)
    while pos < n - 24:
        if data[pos:pos+4] != b'GRUP':
            break
        gsize = struct.unpack_from('<I', data, pos+4)[0]
        label = data[pos+8:pos+12]
        if label == b'LVLI':
            rp = pos + 24
            gend = pos + gsize
            while rp < gend - 24:
                rtype = data[rp:rp+4]
                rsize = struct.unpack_from('<I', data, rp+4)[0]
                if rtype == b'GRUP':
                    rp += rsize
                    continue
                rflags = struct.unpack_from('<I', data, rp+8)[0]
                rfid   = struct.unpack_from('<I', data, rp+12)[0]
                if rtype == b'LVLI' and (rfid >> 24) == sk_idx and (rfid & 0xFFFFFF) in targets:
                    body = data[rp+24:rp+24+rsize]
                    if rflags & 0x00040000:
                        try:
                            body = zlib.decompress(body[4:])
                        except zlib.error:
                            body = None
                    if body is not None:
                        winners[rfid & 0xFFFFFF] = body
                rp += 24 + rsize
        pos += gsize

def find_vendor_gold_winners() -> dict:
    targets = {fid & 0xFFFFFF: edid for fid, edid in VENDOR_GOLD_FIDS.items()}
    winners = {}
    for name, path in _load_order():
        try:
            _scan_plugin_lvli(path, targets, winners)
        except (OSError, struct.error):
            pass
    return winners

def _double_lvlo_counts(body: bytes) -> bytes:
    out, off = bytearray(), 0
    while off < len(body) - 6:
        stype = body[off:off+4]
        ssize = struct.unpack_from('<H', body, off+4)[0]
        chunk = bytearray(body[off:off+6+ssize])
        if stype == b'LVLO' and ssize >= 12:
            count = struct.unpack_from('<I', chunk, 6+8)[0]
            struct.pack_into('<I', chunk, 6+8, count * 2)
        out += chunk
        off += 6 + ssize
    return bytes(out)

def make_lvlis(winners: dict) -> bytes:
    out = BytesIO()
    for local_fid in sorted(winners):
        body = _double_lvlo_counts(winners[local_fid])
        out.write(record('LVLI', local_fid, 0, body))  # master 0 = Skyrim.esm
    return group('LVLI', out.getvalue())

def make_gmst(formid: int, edid: str, value: float) -> bytes:
    body  = subrec('EDID', zstr(edid))
    body += subrec('DATA', struct.pack('<f', value))
    return record('GMST', formid, 0, body)

def make_gmsts() -> bytes:
    out = BytesIO()
    # Override Big Tweaks.esp (75) — GMST matching is by EDID, so a fresh FormID
    # here wins because MRO.esp loads last. fMaxArmorRating stays at the
    # load-order 75: DR above that comes from the MRO_DR perk ladder instead,
    # which keeps it player/follower-only.
    out.write(make_gmst(FID_GMST_MAXRESIST, "fPlayerMaxResistance", 10000.0))
    return group('GMST', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# PERK — Physical DR ladder above the engine's 75% armor cap
# Byte layout copied from Skyrim.esm DragonhideSpellPerk (entry point 36 =
# Mod Incoming Damage, function 3 = Multiply Value). Perk for d% total DR
# multiplies post-armor damage by (100-d)/25 since the engine already took 75%.
# ──────────────────────────────────────────────────────────────────────────────
def make_perks() -> bytes:
    out = BytesIO()
    for i in range(24):
        d = 76 + i
        mult = (100.0 - d) / 25.0
        body  = subrec('EDID', zstr("MRO_DR%02dPerk" % d))
        body += subrec('DESC', b'\x00')
        body += subrec('DATA', bytes([0, 0, 1, 0, 1]))   # trait0 lvl0 ranks1 unplayable hidden
        body += subrec('PRKE', bytes([2, 0, 0]))          # type 2 = entry point
        body += subrec('DATA', bytes([36, 3, 3]))         # Mod Incoming Damage, Multiply Value
        body += subrec('EPFT', bytes([1]))                 # param: float
        body += subrec('EPFD', struct.pack('<f', mult))
        body += subrec('PRKF', b'')
        out.write(record('PERK', FID_DR_PERK_BASE + i, 0, body))
    return group('PERK', out.getvalue())

def make_flsts() -> bytes:
    body = subrec('EDID', zstr("MRO_DRPerkList"))
    for i in range(24):
        body += subrec('LNAM', struct.pack('<I', FID_DR_PERK_BASE + i))
    return group('FLST', record('FLST', FID_DR_FLST, 0, body))

def make_qusts() -> bytes:
    out = BytesIO()
    out.write(make_startup_quest())
    out.write(make_mcm_quest())
    return group('QUST', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────
def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    out_path = os.path.join(out_dir, "MRO.esp")

    esp = BytesIO()
    winners = find_vendor_gold_winners()

    esp.write(make_tes4())
    esp.write(make_gmsts())
    esp.write(make_globs())
    esp.write(make_flsts())
    esp.write(make_lvlis(winners))
    esp.write(make_mgefs())
    esp.write(make_perks())
    esp.write(make_spels())
    esp.write(make_qusts())

    data = esp.getvalue()
    with open(out_path, 'wb') as f:
        f.write(data)

    # SEQ file: SSE only auto-starts Start-Game-Enabled quests that lack the
    # Run Once flag if they are listed in Data/SEQ/<plugin>.seq (flat array of
    # uint32 FormIDs as stored in the plugin). Without it the MCM quest never
    # starts and SkyUI has nothing to register.
    seq_dir = os.path.join(out_dir, "SEQ")
    os.makedirs(seq_dir, exist_ok=True)
    seq_path = os.path.join(seq_dir, "MRO.seq")
    with open(seq_path, 'wb') as f:
        f.write(struct.pack('<II', FID_STARTUP_QUEST, FID_MCM_QUEST))

    print(f"Written: {out_path} ({len(data):,} bytes)")
    print(f"Written: {seq_path} (2 start-game-enabled quests)")
    print()
    print("Records created:")
    print(f"  TES4  header  (masters: Skyrim, Update, Dawnguard, HearthFires, Dragonborn)")
    print(f"  GMST  x1      (fPlayerMaxResistance=10000)")
    print(f"  GLOB  x{len(GLOBALS)}     (feature flags + mastery config)")
    print(f"  FLST  x1      (MRO_DRPerkList: 24 DR perks)")
    print(f"  PERK  x24     (physical DR ladder 76-99%, Mod Incoming Damage)")
    print(f"  LVLI  x{len(winners)}     (vendor gold doubled from load-order values)")
    print(f"  MGEF  x2      (AbsorbMGEF with script, CarryWeightMGEF value modifier)")
    print(f"  SPEL  x2      (AbsorbAbility, CarryWeightAbility)")
    print(f"  QUST  x2      (MRO_StartupQuest, MRO_MCMQuest)")
    print()
    print("All script properties wired. Copy MRO.esp to your MO2 mod folder.")

if __name__ == "__main__":
    main()
