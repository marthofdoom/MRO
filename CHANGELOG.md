# Changelog

All notable changes to Marth Requiem Overhaul. Every released version is
archived permanently under `releases/vX.Y.Z/` — release folders are never
deleted or overwritten.

## v0.8.2 — 2026-07-06

### Changed
- Native hooks now default **ON** (`bPhysicalDRHook=1`, `bAbsorbHook=1`):
  both the physical-DR curve and elemental absorb were verified correct
  in-game, so the exact native paths are now the shipped default and the
  Papyrus fallbacks stand down automatically. Set either to `0` in
  `SKSE/Plugins/MRO.ini` to revert to the Papyrus path. Each hook still
  self-verifies its code site and falls back on an unexpected game binary.
- MRO.dll is **byte-identical to v0.8.0/v0.8.1** (this release only flips
  the INI defaults) — its load banner still reports the v0.8.0 build.

## v0.8.1 — 2026-07-06

### Fixed
- FOMOD installer still advertised the Boss Readiness MCM page (dropped in
  v0.8.0). Removed it from the installer text and info.xml; "13-skill" ->
  "14-skill". Identical DLL/ESP to v0.8.0 — installer wording only.
- Removed the stale `FOMOD/` and `MRO-package/` layouts (superseded by
  MRO-flat / MRO-nofomod).

## v0.8.0 — 2026-07-06

Native DR and absorb hooks remain **opt-in** (MRO.ini `bPhysicalDRHook` /
`bAbsorbHook`, default 0); the Papyrus paths ship active. Absorb's native
path was verified in-game this build (frac 0.020/0.100/0.500 at resist
102/110/150 — exact). Flipping the hooks on by default is a 1.0 item.

### Added (native M3 — absorb, INI-gated default OFF)
- Elemental absorb moved into MRO.dll behind MRO.ini bAbsorbHook. Heals
  from the REAL per-hit pre-resistance magnitude (skill/perk/dual-cast-
  scaled) at po3's magicApply call site (AL 34526 + 0x20B, self-verifying
  E8, logs site bytes). The Papyrus OnHit path only saw a spell's authored
  base magnitude, so absorb read too small to notice. Formula unchanged.
  Bridge global MRO_G_NativeAbsorb (0x81B) stands the Papyrus path down.
  Offset MATCH-verified live on 1.6.1170. See docs/NATIVE_REWRITE_PLAN.md.
- Absorb now qualifies effects by archetype (value-modifier damage only),
  not just by resist flag. Requiem's frost (stamina) and shock (magicka)
  drains still absorb, but fire/frost-flagged hazards, script effects and
  staggers — the noise a QA trap cell (coc warehousetraps) spams — no
  longer grant healing.

### Added (mastery)
- Per-skill mastery XP-speed sliders (14) in the MCM; weapon skills
  default 2.5x (they train slower than armor/magic). Globals 0x870-0x87D.
- Illusion and Alteration now accrue mastery XP out of combat (utility
  schools); Destruction/Restoration/Conjuration still require combat.
- Mastery level-up now fires a corner notification + the vanilla skill-up
  sound (UISkillIncrease 0x018538) — CSF's own message was too subtle.
- Hovering a mastery skill row shows its live bonus in the MCM info bar.

### Removed
- Boss Readiness page dropped entirely (vanilla + content-mod detection).
  It was a hardcoded heuristic, not reliably dynamic per load order, so it
  told players little of value. MCM is now Mastery + Features.

### Changed
- "marth" is lowercase everywhere (MCM title + quest messages), per brand.

## v0.7.2 — 2026-07-05

### Fixed
- Native DR handshake: MRO_G_NativeDR=1 was clobbered on save load
  (GlobalVariable values are save-persisted), so the MCM showed "Perk
  Ladder" and Papyrus never stood down though the hook was live. Now
  re-asserted on kPostLoadGame/kNewGame.
- Carry weight NEVER worked: the fortify MGEF used archetype 0 (Value
  Modifier), which silently no-ops for fortify-from-ability. Now archetype
  34 (Peak Value Modifier) with DATA[48]=0.5, copied byte-for-byte from
  vanilla AbFortifyCarryWeight. Script v4 strips + re-grants the ability
  on existing saves so save-resident effect instances pick up the fix.
- MCM toggles only updated on menu re-entry: repaints were routed through
  the quest, which blocks on the 30s heartbeat's instance lock. Toggles
  now flip the global + repaint locally, then nudge the quest.
- Mastery levels NEVER leveled (since 0.5.1): CSF's Skill::Increment is a
  silent no-op without a "level" GlobalVariable binding in the skill JSON
  (and hard-caps at 100). MRO now owns 28 level/ratio globals (0x850-0x86D)
  bound in the JSONs and SetValue's them directly; CSF only reads.

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
