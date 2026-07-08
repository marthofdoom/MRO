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
FID_G_ABSORBMAX    = OWN | 0x812  # tuning: resist at which absorb = 100% (default 200)
FID_G_DR99ARMOR    = OWN | 0x813  # tuning: armor rating where DR reaches 99% (default 2000)
FID_G_ARMORMASTB   = OWN | 0x814  # tuning: armor mastery bonus at cap (default 300)
FID_G_WEAPMASTB    = OWN | 0x815  # tuning: weapon mastery bonus %% at cap (default 50)
FID_G_WEAPXPPERACT = OWN | 0x808  # tuning: normalized hits per mastery-XP "action", dimensionless (default 1.0, higher = slower); v0.9.1 normalized model, docs/WEAPON_XP_MODELS.md
FID_EVENTS_MGEF    = OWN | 0x816  # hidden AME hosting PO3 event receivers
FID_EVENTS_SPELL   = OWN | 0x817  # always-on ability carrying it
FID_G_LAFRAC       = OWN | 0x818  # bridge: player Evasion mastery fraction 0-100 (Papyrus->DLL)
FID_G_HAFRAC       = OWN | 0x819  # bridge: player Heavy mastery fraction 0-100 (Papyrus->DLL)
FID_G_NATIVEDR     = OWN | 0x81A  # bridge: DLL sets 1 when its DR hook is active (DLL->Papyrus)
FID_G_NATIVEABS    = OWN | 0x81B  # bridge: DLL sets 1 when its absorb hook is active (DLL->Papyrus)
FID_G_NATIVEWXP    = OWN | 0x81C  # bridge: DLL sets 1 when native weapon-XP measuring is live (DLL->Papyrus)
FID_X_PENDOH       = OWN | 0x81D  # bridge: DLL banks player-dealt credited 1H damage (DLL->Papyrus)
FID_X_PENDTH       = OWN | 0x81E  # bridge: DLL banks player-dealt credited 2H damage
FID_X_PENDMK       = OWN | 0x81F  # bridge: DLL banks player-dealt credited Archery damage
FID_DR_PERK_BASE   = OWN | 0x820  # 24 hidden perks: 76%..99% physical DR
FID_DR_FLST        = OWN | 0x838  # FormList holding the 24 DR perks in order
FID_SP_PERK_BASE   = OWN | 0x840  # 5 hidden perks: barter bonus ladder (Speech mastery)
FID_SP_FLST        = OWN | 0x845  # FormList holding the 5 barter perks in order
FID_G_MAGICXPPERCOST = OWN | 0x846  # tuning: effective magicka cost per magic mastery-XP "action" (default 150, higher = slower); cost-weighted spell XP

# Mastery LEVEL globals, one per skill in SkillIndex order (OH TH MK LA
# HA DS RS AL CJ IL SM AC EN SP). Bound as each CSF skill's "level" in
# the CustomSkills JSONs; CSF only READS them (its own Increment caps at
# a hardcoded 100 and its Level binding is required for any level at all
# — found 2026-07-05: JSONs without "level" make every CSF increment a
# silent no-op). Papyrus writes these directly via SetValue, which also
# lets masteries exceed 100 for the MCM's 200 cap. Non-VMAD, looked up
# by FormID like the bridge globals.
FID_ML_BASE        = OWN | 0x850  # ..0x85D
# Mastery progress-ratio globals (0-1), same order: published from the
# Papyrus _mxp accumulators so the CSF skill menu shows progress.
FID_MR_BASE        = OWN | 0x860  # ..0x86D
# Per-skill XP-speed multipliers, same order. 1.0 = default rate; the
# three weapon skills default to 2.5 (weapon mastery trained far slower
# than armor/magic in play). MCM slider per skill; multiplies the grant.
FID_XPM_BASE       = OWN | 0x870  # ..0x87D

MASTERY_SKILLS = ["OneHanded", "TwoHanded", "Marksman", "LightArmor",
                  "HeavyArmor", "Destruction", "Restoration", "Alteration",
                  "Conjuration", "Illusion", "Smithing", "Alchemy",
                  "Enchanting", "Speech"]
# Default per-skill XP-speed multiplier (index order = MASTERY_SKILLS).
# Weapons (OneHanded/TwoHanded/Marksman) 2.5x; everything else 1.0.
XPM_DEFAULTS = [2.5, 2.5, 2.5, 1.0, 1.0, 1.0, 1.0, 1.0,
                1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

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
    hedr = struct.pack('<f', 1.70) + struct.pack('<I', 200) + struct.pack('<I', FID_SP_FLST + 1)
    body  = subrec('HEDR', hedr)
    body += subrec('CNAM', zstr("Marth"))
    body += subrec('SNAM', zstr("Marth Requiem Overhaul v0.9.2"))
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
    ("MRO_F_CellReset",    FID_G_CELLRESET,   'f', 0.0),  # default OFF: cell respawn is too broad (respawns display/quest items, reverts one-time activators e.g. Blackreach lifts)
    ("MRO_SetupDone",      FID_G_SETUPDONE,   'f', 0.0),
    ("MRO_MasteryEnabled", FID_G_MASTERYENA,  'f', 1.0),
    ("MRO_MasteryBaseGrant",FID_G_MASTERYGNT, 'f', 1.0),
    ("MRO_MasteryCap",     FID_G_MASTERYCAP,  'f', 100.0),
    ("MRO_T_AbsorbMax",    FID_G_ABSORBMAX,   'f', 200.0),
    ("MRO_T_DR99Armor",    FID_G_DR99ARMOR,   'f', 2000.0),
    ("MRO_T_ArmorMasteryBonus",  FID_G_ARMORMASTB, 'f', 300.0),
    ("MRO_T_WeaponMasteryBonus", FID_G_WEAPMASTB,  'f', 50.0),
    ("MRO_T_WeaponXPPerAction",  FID_G_WEAPXPPERACT, 'f', 1.0),
    ("MRO_T_MagicXPPerCost",     FID_G_MAGICXPPERCOST, 'f', 150.0),
    # Papyrus<->DLL bridge globals: accessed via GetFormFromFile /
    # TESDataHandler::LookupForm — deliberately NOT VMAD-wired so they
    # work on saves whose quest instances predate them.
    ("MRO_G_LAFrac",       FID_G_LAFRAC,      'f', 0.0),
    ("MRO_G_HAFrac",       FID_G_HAFRAC,      'f', 0.0),
    ("MRO_G_NativeDR",     FID_G_NATIVEDR,    'f', 0.0),
    ("MRO_G_NativeAbsorb", FID_G_NATIVEABS,   'f', 0.0),
    ("MRO_G_NativeWeaponXP", FID_G_NATIVEWXP, 'f', 0.0),
    ("MRO_X_PendOH",       FID_X_PENDOH,      'f', 0.0),
    ("MRO_X_PendTH",       FID_X_PENDTH,      'f', 0.0),
    ("MRO_X_PendMK",       FID_X_PENDMK,      'f', 0.0),
]
# Mastery level + ratio globals (see FID_ML_BASE comment)
for _i, _sk in enumerate(MASTERY_SKILLS):
    GLOBALS.append((f"MRO_ML_{_sk}", FID_ML_BASE + _i, 'f', 0.0))
for _i, _sk in enumerate(MASTERY_SKILLS):
    GLOBALS.append((f"MRO_MR_{_sk}", FID_MR_BASE + _i, 'f', 0.0))
# Per-skill XP-speed multipliers (see FID_XPM_BASE comment)
for _i, _sk in enumerate(MASTERY_SKILLS):
    GLOBALS.append((f"MRO_XPM_{_sk}", FID_XPM_BASE + _i, 'f', XPM_DEFAULTS[_i]))

def make_globs(overrides: dict = None) -> bytes:
    out = BytesIO()
    for edid, fid, gtype, val in GLOBALS:
        if overrides and edid in overrides:
            val = overrides[edid]
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

# MGEF flags: 0x200 = No Duration, 0x400 = No Magnitude (hides the
# meaningless "1%" on script-archetype constant abilities in the UI)
def mgef_data(effect_type: int, primary_av: int, casting_type: int = 0, delivery: int = 0, flags: int = 0, f48: float = 0.0) -> bytes:
    # 152 bytes. Field positions verified against Requiem.esp scripted/value-mod MGEFs:
    #   [48] float field vanilla AbFortifyCarryWeight carries 0.5 in (taper curve
    #        region) — copied verbatim for fortify-type effects
    #   [64] EffectType  (0=ValueModifier, 1=Script, 34=PeakValueModifier, …)
    #   [68] Primary AV
    #   [80] CastingType (0=Constant, 1=FireAndForget, 2=Concentration)
    #   [84] Delivery    (0=Self, 2=Aimed, …)
    #   [88] Secondary AV (0xFFFFFFFF=none)
    #  [112] DualCastScale (1.0)
    d = bytearray(152)
    struct.pack_into('<I', d, 0, flags)
    struct.pack_into('<I', d, 12, 0xFFFFFFFF)  # MagicSkill = none
    struct.pack_into('<I', d, 16, 0xFFFFFFFF)  # MinSkillLevel = none
    struct.pack_into('<f', d, 48, f48)
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

    # Subrecord order and required subrecords (SNDD, DNAM) verified against
    # Skyrim.esm AbAlduinInvulnerabilityEffect: EDID, VMAD, FULL, DATA,
    # SNDD (empty), DNAM (zero description lstring).

    # ── AbsorbMGEF: scripted, OnHit handler, no AV change ──
    # No properties: the script resolves resistances generically via
    # SKSE GetResistance() and PO3 archetype checks.
    vmad = VMADBuilder()
    vmad.add_script("MRO_AbsorbMGEF", [
        ("MRO_T_AbsorbMax",    prop_obj(FID_G_ABSORBMAX)),
        ("MRO_G_NativeAbsorb", prop_obj(FID_G_NATIVEABS)),
    ])
    body  = subrec('EDID', zstr("MRO_AbsorbMGEF"))
    body += subrec('VMAD', vmad.build())
    body += subrec('FULL', zstr("MRO - Elemental Absorb"))
    body += subrec('DATA', mgef_data(effect_type=1, primary_av=0xFFFFFFFF, flags=0x600))
    body += subrec('SNDD', b'')
    body += subrec('DNAM', zstr("Marth Requiem Overhaul: elemental resistances above 100% convert that element's damage into healing. Full absorption at the MCM-configured resistance (default 200%). Overhealing spills into stamina and magicka."))
    out.write(record('MGEF', FID_ABSORB_MGEF, 0, body))

    # ── CarryWeightMGEF: fortify CarryWeight, +150 ──
    # Field-for-field copy of Skyrim.esm AbFortifyCarryWeight (the Steed
    # Stone effect): archetype 34 = Peak Value Modifier, flags Recover
    # (0x2) + No Area (0x800) + Power Affects Magnitude (0x200000), and
    # 0.5 at DATA[48]. Archetype 0 (plain Value Modifier) silently failed
    # to raise CarryWeight from a constant ability (found 2026-07-04).
    # Only knowing deviation: vanilla's Hide-in-UI (0x8000) dropped so
    # the buff shows in Active Effects.
    body  = subrec('EDID', zstr("MRO_CarryWeightMGEF"))
    body += subrec('FULL', zstr("MRO - Carry Weight Bonus"))
    body += subrec('DATA', mgef_data(effect_type=34, primary_av=AV_CARRYWEIGHT, flags=0x200802, f48=0.5))
    body += subrec('SNDD', b'')
    body += subrec('DNAM', zstr("Marth Requiem Overhaul: permanent bonus carry weight for you and your followers. Toggleable in the MRO MCM."))
    out.write(record('MGEF', FID_CW_MGEF, 0, body))

    # ── EventsMGEF: hidden receiver for PO3 per-form events ──
    # (PO3 events never deliver to Quest scripts; this AME forwards to
    # the startup quest.) 0x8000 = Hide in UI.
    vmad = VMADBuilder()
    vmad.add_script("MRO_EventsMGEF", [
        ("MRO_Quest", prop_obj(FID_STARTUP_QUEST)),
    ])
    body  = subrec('EDID', zstr("MRO_EventsMGEF"))
    body += subrec('VMAD', vmad.build())
    body += subrec('DATA', mgef_data(effect_type=1, primary_av=0xFFFFFFFF, flags=0x8600))
    body += subrec('SNDD', b'')
    body += subrec('DNAM', zstr(""))
    out.write(record('MGEF', FID_EVENTS_MGEF, 0, body))

    return group('MGEF', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# SPEL — Spell (Ability type)
# SPIT: (cost:f)(flags:I)(type:I)(chargeTime:f)(castType:I)(delivery:I)(castDuration:f)(range:f)(perk:I)
# type 4 = Ability (verified against Skyrim.esm AbAlduinInvulnerability —
# type 3 is Lesser Power, which never applies as a constant effect and was
# why absorb/carry weight silently did nothing). castType 0 = Constant,
# delivery 0 = Self. OBND/ETYP/DESC are required subrecords.
# ──────────────────────────────────────────────────────────────────────────────
FREF_ETYP_EITHERHAND = 0x00013F44  # Skyrim.esm equip type used by vanilla abilities

def spit(spell_type=4, cast_type=0, delivery=0, cost=0.0, flags=0x00000000) -> bytes:
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
    body += subrec('OBND', bytes(12))
    body += subrec('FULL', zstr("MRO - Elemental Absorb"))
    body += subrec('ETYP', struct.pack('<I', FREF_ETYP_EITHERHAND))
    body += subrec('DESC', zstr(""))
    body += subrec('SPIT', spit())
    body += spell_effect(FID_ABSORB_MGEF, 1.0)
    out.write(record('SPEL', FID_ABSORB_SPELL, 0, body))

    # CarryWeightAbility
    body  = subrec('EDID', zstr("MRO_CarryWeightAbility"))
    body += subrec('OBND', bytes(12))
    body += subrec('FULL', zstr("MRO - Carry Weight Bonus"))
    body += subrec('ETYP', struct.pack('<I', FREF_ETYP_EITHERHAND))
    body += subrec('DESC', zstr(""))
    body += subrec('SPIT', spit())
    body += spell_effect(FID_CW_MGEF, 150.0)
    out.write(record('SPEL', FID_CW_SPELL, 0, body))

    # EventsAbility (hidden plumbing, no FULL so nothing shows anywhere)
    body  = subrec('EDID', zstr("MRO_EventsAbility"))
    body += subrec('OBND', bytes(12))
    body += subrec('ETYP', struct.pack('<I', FREF_ETYP_EITHERHAND))
    body += subrec('DESC', zstr(""))
    body += subrec('SPIT', spit())
    body += spell_effect(FID_EVENTS_MGEF, 0.0)
    out.write(record('SPEL', FID_EVENTS_SPELL, 0, body))

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
        ("MRO_EventsAbility",    prop_obj(FID_EVENTS_SPELL)),
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
        ("MRO_SpeechPerks",      prop_obj(FID_SP_FLST)),
        ("MRO_T_DR99Armor",      prop_obj(FID_G_DR99ARMOR)),
        ("MRO_T_ArmorMasteryBonus",  prop_obj(FID_G_ARMORMASTB)),
        ("MRO_T_WeaponMasteryBonus", prop_obj(FID_G_WEAPMASTB)),
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
        ("MRO_MasteryEnabled",   prop_obj(FID_G_MASTERYENA)),
        ("MRO_MasteryBaseGrant", prop_obj(FID_G_MASTERYGNT)),
        ("MRO_MasteryCap",       prop_obj(FID_G_MASTERYCAP)),
        ("MRO_F_ResistCap",      prop_obj(FID_G_RESISTCAP)),
        ("MRO_F_ArmorCap",       prop_obj(FID_G_ARMORCAP)),
        ("MRO_F_Absorb",         prop_obj(FID_G_ABSORB)),
        ("MRO_F_CarryWeight",    prop_obj(FID_G_CARRYWEIGHT)),
        ("MRO_F_ArrowRecovery",  prop_obj(FID_G_ARROWRECOV)),
        ("MRO_F_CellReset",      prop_obj(FID_G_CELLRESET)),
        ("MRO_T_AbsorbMax",      prop_obj(FID_G_ABSORBMAX)),
        ("MRO_T_DR99Armor",      prop_obj(FID_G_DR99ARMOR)),
        ("MRO_T_ArmorMasteryBonus",  prop_obj(FID_G_ARMORMASTB)),
        ("MRO_T_WeaponMasteryBonus", prop_obj(FID_G_WEAPMASTB)),
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

def _scan_plugin_lvli(path: str, targets: dict, winners: dict, armo: dict = None, gmst: dict = None):
    """One pass per plugin: LVLI winners (targets), plus optionally the
    winning ARMO (slotflags, armortype, rating) per formid and winning
    float GMSTs named in gmst{lower_edid: value}."""
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
        sk_idx = -1
        if armo is None and gmst is None:
            return

    pos = 24 + tes4_size
    n = len(data)
    while pos < n - 24:
        if data[pos:pos+4] != b'GRUP':
            break
        gsize = struct.unpack_from('<I', data, pos+4)[0]
        label = data[pos+8:pos+12]
        want_lvli = label == b'LVLI' and sk_idx >= 0
        want_armo = label == b'ARMO' and armo is not None
        want_gmst = label == b'GMST' and gmst is not None
        if want_lvli or want_armo or want_gmst:
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
                body = data[rp+24:rp+24+rsize]
                if rflags & 0x00040000:
                    try:
                        body = zlib.decompress(body[4:])
                    except zlib.error:
                        body = None
                if body is not None:
                    if want_lvli and rtype == b'LVLI' and (rfid >> 24) == sk_idx and (rfid & 0xFFFFFF) in targets:
                        winners[rfid & 0xFFFFFF] = body
                    elif want_armo and rtype == b'ARMO' and not (rflags & 0x4):  # skip Non-Playable
                        parsed = _parse_armo(body)
                        if parsed:
                            armo[rfid & 0xFFFFFF] = parsed
                    elif want_gmst and rtype == b'GMST':
                        ep = body.find(b'EDID')
                        dp = body.find(b'DATA')
                        if ep == 0 and dp > 0:
                            es = struct.unpack_from('<H', body, 4)[0]
                            edid = body[6:6+es].rstrip(b'\x00').decode('ascii', 'replace').lower()
                            if edid in gmst and struct.unpack_from('<H', body, dp+4)[0] == 4:
                                gmst[edid] = struct.unpack_from('<f', body, dp+6)[0]
                rp += 24 + rsize
        pos += gsize

def _parse_armo(body: bytes):
    """(slotflags, armortype, rating) from an ARMO body, or None."""
    slot, atype, rating = None, None, None
    off = 0
    while off < len(body) - 6:
        st = body[off:off+4]
        ss = struct.unpack_from('<H', body, off+4)[0]
        if st == b'BOD2' and ss >= 8:
            slot  = struct.unpack_from('<I', body, off+6)[0]
            atype = struct.unpack_from('<I', body, off+6+4)[0]
        elif st == b'BODT' and ss >= 12:
            slot  = struct.unpack_from('<I', body, off+6)[0]
            atype = struct.unpack_from('<I', body, off+6+8)[0]
        elif st == b'DNAM' and ss >= 4:
            rating = struct.unpack_from('<i', body, off+6)[0] / 100.0
        off += 6 + ss
    if slot is None or atype is None or rating is None:
        return None
    return (slot, atype, rating)

# Best obtainable heavy set from the load order -> default 99%-DR armor
# target, so "extreme effort" is calibrated against gear that actually
# exists. Model: best base per slot + full tempering (2x smithing-mastery
# cap on 5 pieces) + skill/perk headroom (x1.75) + armor mastery (+300).
ARMOR_SLOTS = {0x4: 'body', 0x1: 'head', 0x8: 'hands', 0x80: 'feet', 0x200: 'shield'}

def estimate_dr99_armor(armo: dict, smith_max: float) -> int:
    best = {}
    for slot_flags, atype, rating in armo.values():
        # Heavy only; Requiem rates endgame pieces very high (daedric
        # chest = 600), so the sanity bound is generous. Multi-slot
        # entries are creature skins / outfits, not equippable pieces.
        if atype != 1 or not (5.0 <= rating <= 800.0):
            continue
        hits = [name for bit, name in ARMOR_SLOTS.items() if slot_flags & bit]
        if len(hits) != 1:
            continue
        name = hits[0]
        if rating > best.get(name, 0.0):
            best[name] = rating
    base = sum(best.values())
    temper = 5 * smith_max * 2.0          # full tempering at doubled mastery cap
    est = (base + temper) * 1.15 + 300.0  # skill-perk headroom + armor mastery
    est = int(round(est / 100.0) * 100)
    est = max(1500, min(4500, est))
    print(f"  DR99 estimate: best heavy set {base:.0f} "
          f"({', '.join(f'{k} {v:.0f}' for k, v in sorted(best.items()))}) "
          f"+ temper {temper:.0f} -> target {est}")
    return est

def find_load_order_data():
    """One walk: vendor-gold LVLI winners, winning ARMO stats, key GMSTs."""
    targets = {fid & 0xFFFFFF: edid for fid, edid in VENDOR_GOLD_FIDS.items()}
    winners, armo = {}, {}
    gmst = {'fsmithingarmormax': 60.0}
    for name, path in _load_order():
        try:
            _scan_plugin_lvli(path, targets, winners, armo, gmst)
        except (OSError, struct.error):
            pass
    return winners, armo, gmst

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
        # Layout matches Skyrim.esm crFalmerPoison05 exactly: playable=1,
        # hidden=0, and NO trailing PRKF after the final entry (vanilla
        # omits it; a trailing PRKF makes the loader reject the record).
        body  = subrec('EDID', zstr("MRO_DR%02dPerk" % d))
        body += subrec('FULL', zstr("MRO Damage Resist %d%%" % d))
        body += subrec('DESC', zstr(""))
        body += subrec('DATA', bytes([0, 0, 1, 1, 0]))   # trait0 lvl0 ranks1 playable notHidden
        body += subrec('PRKE', bytes([2, 0, 0]))          # type 2 = entry point
        body += subrec('DATA', bytes([36, 3, 3]))         # Mod Incoming Damage, Multiply Value
        body += subrec('EPFT', bytes([1]))                 # param: float
        body += subrec('EPFD', struct.pack('<f', mult))
        out.write(record('PERK', FID_DR_PERK_BASE + i, 0, body))
    out.write(make_speech_perks())
    return group('PERK', out.getvalue())

# ──────────────────────────────────────────────────────────────────────────────
# Speech mastery barter ladder — entry points copied from Skyrim.esm
# Haggling00: entry 8 = Mod Buy Prices (multiply <1), entry 60 = Mod Sell
# Prices (multiply >1). Multi-entry perks put PRKF after each entry except
# the last. Rung i (1..5): buy * (1 - 0.04*i), sell * (1 + 0.05*i)
# -> at full mastery: buy 20% cheaper, sell 25% higher.
# ──────────────────────────────────────────────────────────────────────────────
def make_speech_perks() -> bytes:
    out = BytesIO()
    for i in range(5):
        rung = i + 1
        buy_mult  = 1.0 - 0.04 * rung
        sell_mult = 1.0 + 0.05 * rung
        body  = subrec('EDID', zstr("MRO_Barter%02dPerk" % rung))
        body += subrec('FULL', zstr("MRO Barter Rank %d" % rung))
        body += subrec('DESC', zstr(""))
        body += subrec('DATA', bytes([0, 0, 1, 1, 0]))
        body += subrec('PRKE', bytes([2, 0, 0]))
        body += subrec('DATA', bytes([60, 3, 2]))          # Mod Sell Prices, Multiply
        body += subrec('EPFT', bytes([1]))
        body += subrec('EPFD', struct.pack('<f', sell_mult))
        body += subrec('PRKF', b'')
        body += subrec('PRKE', bytes([2, 0, 0]))
        body += subrec('DATA', bytes([8, 3, 2]))           # Mod Buy Prices, Multiply
        body += subrec('EPFT', bytes([1]))
        body += subrec('EPFD', struct.pack('<f', buy_mult))
        out.write(record('PERK', FID_SP_PERK_BASE + i, 0, body))
    return out.getvalue()

def make_flsts() -> bytes:
    out = BytesIO()
    body = subrec('EDID', zstr("MRO_DRPerkList"))
    for i in range(24):
        body += subrec('LNAM', struct.pack('<I', FID_DR_PERK_BASE + i))
    out.write(record('FLST', FID_DR_FLST, 0, body))
    body = subrec('EDID', zstr("MRO_BarterPerkList"))
    for i in range(5):
        body += subrec('LNAM', struct.pack('<I', FID_SP_PERK_BASE + i))
    out.write(record('FLST', FID_SP_FLST, 0, body))
    return group('FLST', out.getvalue())

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
    winners, armo, gmst = find_load_order_data()
    dr99 = estimate_dr99_armor(armo, gmst['fsmithingarmormax'])

    esp.write(make_tes4())
    esp.write(make_gmsts())
    esp.write(make_globs({"MRO_T_DR99Armor": float(dr99)}))
    esp.write(make_flsts())
    # Vendor gold LVLI overrides retired in v0.6.0: MRO.dll doubles the
    # lists in memory at data load (dynamic on any load order).
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
    print(f"  (vendor gold now doubled at runtime by MRO.dll — no LVLI records)")
    print(f"  MGEF  x2      (AbsorbMGEF with script, CarryWeightMGEF value modifier)")
    print(f"  SPEL  x2      (AbsorbAbility, CarryWeightAbility)")
    print(f"  QUST  x2      (MRO_StartupQuest, MRO_MCMQuest)")
    print()
    print("All script properties wired. Copy MRO.esp to your MO2 mod folder.")

if __name__ == "__main__":
    main()
