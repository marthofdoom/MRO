# Marth Requiem Overhaul — Build Guide

## Prerequisites
- SSEEdit 4.x (aka xEdit / SSEEdit)
- Skyrim SE or AE with SKSE64
- Requiem.esp in your load order
- Papyrus compiler (Creation Kit or Caprica standalone)

---

## Step 1 — Create the ESP

1. Open SSEEdit. Load **Skyrim.esm** and **Requiem.esp** (plus any active Requiem patches).
2. If **Experience.esp** (by meh321) is in your list, load it too — the script detects it
   and skips XP GMSTs automatically. See XP note below.
3. Tools → Apply Script → select `xEdit/MRO_CreatePlugin.pas` → Run.
4. A new `MRO.esp` appears. Watch the log for `[MRO] WARNING` lines.

**Post-script manual fixes in xEdit (required):**

5. **SPEL → MGEF links**: Open `MRO.esp → SPEL → MRO_AbsorbAbility → Effects[0] → EFID`.
   If unresolved, click and select `MRO_AbsorbMGEF`. Do the same for `MRO_CarryWeightAbility`.
6. **Startup quest properties**: Open `MRO.esp → QUST → MRO_StartupQuest → VMAD → Scripts →
   MRO_StartupQuest → Properties`. Ensure `MRO_AbsorbAbility` and `MRO_CarryWeightAbility`
   both point to the correct SPEL FormIDs in MRO.esp.
7. **Verify GMST names**: Search Requiem.esp GMST for "Armor", "Health", "Stamina".
   Confirm that `fMaxArmorRating`, `fArmorScalingFactor`, `fHealthRegenRateMult`,
   `fCombatHealthRegenRateMult`, `fCombatStaminaRegenRateMult` match what Requiem uses.
   If any name differs, update the corresponding record in MRO.esp.
8. **Add follower alias slots** (optional but recommended):
   - Open `MRO.esp → QUST → MRO_StartupQuest → Aliases`.
   - Add 10 alias slots. Each: Fill Type = `In Specific Faction`,
     Faction = `CurrentFollowerFaction` (Skyrim.esm 0x0005C84E), Optional = true.
   - Attach script `MRO_FollowerAlias` to each alias slot.
9. Right-click `MRO.esp` → Set as Active File → Ctrl+S to save.

---

## Step 2 — XP Configuration

**If Experience.esp is in your load order:**
The script skips XP GMSTs. Adjust rates in Experience's INI instead:
- Location: `SKSE\Plugins\Experience.ini` (in your Skyrim Data folder)
- Increase `fKillExperienceMult`, `fLocationExperienceMult`, and `fQuestExperienceMult`
  by ~1.5–2x for FFVII-IX pacing.
- Exact values depend on your list's preset; aim for "level every 2-3 dungeon clears."

**If no Experience mod:**
The script already sets all `fSkillUseMult_*` GMSTs to 2.0x. No action needed.

---

## Step 3 — Compile Papyrus Scripts

**Using Creation Kit:**
1. Copy `Source/Scripts/*.psc` into `<Skyrim Data>\Scripts\Source\`.
2. File → Compile Papyrus Script → select all four MRO scripts → compile.
3. Copy resulting `Scripts/*.pex` into your mod's `Scripts\` folder.

**Using Caprica (no CK):**
```bash
caprica Source/Scripts/MRO_AbsorbMGEF.psc     -o Scripts/
caprica Source/Scripts/MRO_StartupQuest.psc   -o Scripts/
caprica Source/Scripts/MRO_FollowerAlias.psc  -o Scripts/
```

---

## Step 4 — Package

Final layout:
```
MRO/
├── MRO.esp
└── Scripts/
    ├── MRO_AbsorbMGEF.pex
    ├── MRO_StartupQuest.pex
    └── MRO_FollowerAlias.pex
```
Install via Mod Organizer 2. **MRO.esp must load last** — after all Requiem patches.

---

## Systems implemented (v0.1)

| System | Implementation | FFVII-IX Calibration |
|---|---|---|
| Elemental resist cap removed | GMST: fPlayerMaxResistance/fNPCMaxResistance → 10000 | Elements matter; no artificial ceiling |
| Null at 100% resist | Engine handles naturally once cap removed | Enemy immunities work cleanly |
| Absorb at >100% resist | Papyrus OnHit → RestoreActorValue | Matching element heals you |
| Physical armor uncapped | GMST: fMaxArmorRating → 99%, fArmorScalingFactor → 0.06 | Deep investment is rewarded |
| Out-of-combat health regen | GMST: fHealthRegenRateMult → 0.5 | Walk the world map, recover gradually |
| No in-combat health regen | GMST: fCombatHealthRegenRateMult → 0.0 | Items matter in fights |
| Stamina regen in combat | GMST: fCombatStaminaRegenRateMult → 0.5 | Never fully action-locked |
| Arrow recovery | GMST: iArrowInventoryChance → 66% | Ammo is available but not infinite |
| XP rate doubled | GMST: fSkillUseMult_* → 2.0 (if no Experience mod) | Satisfying growth without grinding |
| Enemy detection range | GMST: fSneakExteriorDistanceMult → 0.75, Interior → 0.80 | Choose your fights |
| Alert timeout reduced | GMST: fDetectionEventExpireTime → 20s | Disengage and regroup |
| Vendor gold doubled | FACT record overrides from Skyrim.esm + Requiem.esp | Shops are reliable |
| Vendor restock faster | GMST: iHoursToRespawnCell → 72h (3 days) | Come back and resupply |
| Potion weight 25% | ALCH record overrides for restore/cure potions | Carry a full item stock |
| Carry weight +150 | Permanent ability (MRO_CarryWeightAbility) via startup quest | Inventory is a tool, not a puzzle |

## Planned — v0.2+

- **True diminishing-returns armor perk** (MRO_ArmorDRPerk): DR = AR / (AR + 105), ~95% at 2000 AR
- **Elemental weakness amplification**: verify negative resist floor, confirm enemy weak profiles
- **Crisis Mode (Limit Break zone)**: below 20% HP, player deals +25% damage
- **Phoenix Down**: consumable auto-revive on death, one charge per fight
- **MCM**: runtime sliders for absorb multiplier, carry weight bonus, XP rate
