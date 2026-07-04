# Dynamic-or-Drop Tracker for v1.0

Rule (set 2026-07-04): anything whose behavior depends on values baked in
from THIS machine's load order at ESP-generation time must either become
dynamic (computed at runtime in-game) or be dropped before a true 1.0
release. The shipped mod must behave as advertised on any load order.

Status values: DROP-CANDIDATE (no dynamic path found yet),
FIXABLE (dynamic path identified, not yet implemented), PORTABLE (fine as-is).

## DROP-CANDIDATE

### Vendor gold doubling
- Baked: 13 LVLI overrides with counts doubled from the winning override
  found by scanning this machine's plugins.txt/modlist.txt.
- Why not dynamic yet: leveled-list counts cannot be modified at runtime
  from Papyrus (PO3 only reads them; no SKSE scripting API writes them).
- Possible escape hatches to investigate before dropping:
  1. Runtime gold top-up: on "BarterMenu" open, resolve the merchant
     faction's chest via Faction.GetMerchantContainer(), count its gold,
     and AddItem an equal amount once per restock cycle. Needs careful
     bookkeeping (don't double-dip within one reset; track per-vendor).
  2. Our own tiny SKSE DLL that patches leveled lists at load. Breaks the
     "pure Papyrus + ESP" constraint; new toolchain (C++/CommonLibSSE).
- If neither pans out: DROP for 1.0.

## FIXABLE (make dynamic before 1.0)

### Physical DR curve kink (currently hardcoded 750 armor / 75%)
- Baked assumption: load order uses fMaxArmorRating=75 and
  fArmorScalingFactor=0.10, so the kink sits at 750 armor.
- Dynamic fix (easy): read both GMSTs at runtime
  (Game.GetGameSettingFloat) each heartbeat; kink = cap / scaling,
  slope chosen so 99% lands at kink + K armor (K configurable).
  No generation-time knowledge needed.

## PORTABLE (verified fine as-is)

- fPlayerMaxResistance=10000 GMST override — generic.
- Absorb system — reads resistances/effects at runtime, fully generic.
- DR perk ladder records themselves — static multipliers, generic
  (only the rung-selection formula needs the FIXABLE change above).
- Mastery action costs — derived from VANILLA Skyrim.esm AVSK records,
  not the load order; portable by construction.
- Mastery bonuses (+300 armor etc.) — design constants, not baked scans.
- Mod detections (World Eater's Influence, Immersive Miraak, Experience
  DLL) — runtime file/plugin checks.
- Optional Experience.ini — a user-chosen optional file, clearly labeled;
  static tuning is acceptable for an optional.
- SEQ file, FOMOD, ESL flagging — portable packaging.

## Release gate

Before tagging 1.0: every DROP-CANDIDATE resolved (implemented dynamic or
removed from ESP + texts), every FIXABLE implemented, and a clean-install
test on a non-LoreRim Requiem setup if available.
