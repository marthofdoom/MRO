# Changelog

All notable changes to Marth Requiem Overhaul. Every released version is
archived permanently under `releases/vX.Y.Z/` — release folders are never
deleted or overwritten.

## v0.3.1 — 2026-07-03

First fully working build.

### Fixed
- FormID collision: own records now use the correct `0x05` own-file prefix.
  Previous builds injected into Skyrim.esm's FormID space, colliding with a
  vanilla IMAD record and silently deleting the MCM quest at runtime.
- Added `SEQ/MRO.seq` — required for the (non-Run-Once) MCM quest to start.
- MCM layout rebuilt to SkyUI conventions: short row values, long
  descriptions in the bottom info bar via OnOptionHighlight.
- Intro popup latched (flag set before display + session guard) — no more
  repeated message boxes.
- Armor masteries gated on worn chest piece type (light/heavy).
- FOMOD: `<plugins order="Explicit">` wrapper (fixes MO2 "invalid vector
  subscript"), flat archive layout, four descriptive install pages.

### Features (as of this version)
- Elemental resistance uncap (GMST, EDID-matched, beats Big Tweaks).
- Elemental absorb: resist >100% heals 1%/point of matching damage, full
  absorb at 200%. Spells, enchantments, drains, poisons. Player + followers.
- Physical DR ladder: 24 hidden Mod Incoming Damage perks scale DR 75-99%
  across 750-2000 armor rating. Player + followers only; engine curve below
  750 untouched.
- 13-skill Mastery system (CSF): weapons +50% dmg, armor +300 AR (worn chest
  gated), magic +50 skill, crafting +25%. Cap 50-200 via MCM.
- Vendor gold doubled (13 LVLI overrides derived from the live load order).
- Carry weight +150, arrow recovery 66%, 3-day cell reset.
- MCM: Boss Readiness / Mastery / Features pages.

### Removed during development
- Final Fantasy branding; out-of-combat regen feature (bogus GMST); potion
  weight claims (never implemented); armor scaling factor override (replaced
  by the DR ladder); MRO_FollowerAlias.pex (dead code — followers handled
  via PO3 GetPlayerFollowers).
