# Changelog

All notable changes to Marth Requiem Overhaul. Every released version is
archived permanently under `releases/vX.Y.Z/` — release folders are never
deleted or overwritten.

## v0.7.0 — 2026-07-05

### Added (native M2 — SHIPPED OFF BY DEFAULT)
- Physical DR moved into MRO.dll behind SKSE/Plugins/MRO.ini
  bPhysicalDRHook (default 0): exact per-hit curve for player and
  teammates at a self-verifying weapon-hit call site (refuses to
  install unless the code site matches). Papyrus perk ladder stands
  down automatically via MRO_G_NativeDR when the hook is live.
- Bridge globals 0x818-0x81A (mastery fractions, native handshake).
- FOMOD descriptions synced with 0.6/0.7 behavior.

## v0.6.1 — 2026-07-04

### Changed
- MCM: version shown under Features > About; capitalization made
  consistent (Detected/Not Detected, COMPLETED, Survivable); stale
  "13 skills" and hardcoded 200% texts corrected.
- release.sh now stamps the version into the MCM and compiles all
  scripts automatically.

## v0.6.0 — 2026-07-04

### Changed (native M1)
- Vendor gold doubling moved into MRO.dll: the 13 vanilla VendorGold*
  lists are doubled in memory at data load — dynamic on any load order.
  Baked LVLI overrides and the generator load-order scan retired.
  Values on LoreRim are identical to 0.5.x; merchants update on their
  next restock. Requires the MRO.dll from this release.
- Last DYNAMIC_OR_DROP drop-candidate resolved.

## v0.5.1 — 2026-07-04

### Fixed
- Weapon mastery XP was never granted in 0.4.x: PO3 per-form events do
  not deliver to Quest scripts (registration silently succeeds). Hits
  are now received by a hidden always-on ability (MRO_EventsMGEF) and
  forwarded to the quest. Script v3 grants the ability on existing saves.

## v0.5.0 — 2026-07-04

### Changed
- DR ladder is now a MASTERY PERK: it only functions with the matching
  armor mastery, and the reachable DR ceiling scales with mastery level
  (99% requires BOTH max armor AND full mastery). Followers share the
  player's mastery. First of the planned per-skill mastery perks.
- 99%-DR armor target auto-calibrated from the load order's best
  obtainable heavy gear at generation time (LoreRim: 3000). MCM slider
  range extended to 4500.

### Decided
- Native (CommonLibSSE-NG) rewrite deferred: cannot be done crash-safe
  in one shot without a toolchain and iterative in-game testing. It
  remains the planned vehicle for 1.0's dynamic vendor gold and exact
  damage hooks.

## v0.4.2 — 2026-07-04

### Changed
- Active effects renamed with MRO prefix and given real descriptions;
  the meaningless "1%" magnitude on Elemental Absorb is hidden
  (No Magnitude/No Duration MGEF flags).

## v0.4.1 — 2026-07-04

### Fixed
- Ladder perks (DR + barter) now carry FULL names — console help lists
  perks by display name, so nameless perks were invisible to `help` even
  when loaded.

## v0.4.0 — 2026-07-04

### Fixed
- Ability spells were SPIT type 3 (Lesser Power) — absorb and carry
  weight NEVER applied. Now type 4 (Ability) with required OBND/ETYP/DESC
  subrecords; both show in Active Effects.
- DR perks were rejected by the loader (trailing PRKF, hidden flags);
  layout now byte-matches vanilla.
- Weapon mastery XP was granted per swing, even at air/rocks. Now gated
  on real landed hits against living hostile actors (PO3 OnWeaponHit)
  and per-level hit costs doubled (360/220/180). Spell XP requires combat.

### Added
- MCM Tuning sliders: full-absorb resist point, 99%-DR armor rating,
  armor/weapon mastery bonus sizes, mastery XP speed.
- MCM Live Status: armor rating, effective physical DR%, per-element
  resist with absorb percentage.
- DR curve kink now read live from the load order's armor GMSTs
  (resolves a DYNAMIC_OR_DROP item).
- Speech as 14th mastery: barter sessions train it; 5-rung perk ladder
  (buy up to 20% cheaper, sell up to 25% higher — Haggling entry points).
- Smithing mastery raises temper caps (up to 2x at full mastery).
- Absorb overflow: healing past full health spills into stamina/magicka.
- Script v2 migration (accumulator array 13 -> 14) via update-in-place.

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
