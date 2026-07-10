# Changelog

All notable changes to marth Resurgence Overhaul (formerly marth Requiem
Overhaul; renamed 2026-07-09). Every released version is
archived permanently under `releases/vX.Y.Z/` — release folders are never
deleted or overwritten.

## Unreleased

### Fixed
- **Magic XP no longer taxes the whole load order.** The last global
  Papyrus listener (RegisterForActorAction(2), spell-fire for EVERY actor)
  is replaced by a native spell-cast sink in MRO.dll that filters to the
  player before any script dispatch — the same de-globalization the
  weapon-swing watch got in v0.9.8. SCRIPT_VERSION 10 unregisters the old
  listener on existing saves. XP math unchanged.

## v0.12.0 — 2026-07-10 (alpha)

### Added
- **Live Status tells the truth (status-page 1.0 work, part 1).** The DLL
  now publishes the player's EARNED armor rating and the effective physical
  DR the native ladder actually applies (bridge globals 0x849/0x84A,
  refreshed on load and every journal open). The MCM's "Armor Rating
  (earned)" and "Physical DR" rows read those instead of re-deriving the
  ladder from full AR — which is why a ward looked like +9% past-cap DR in
  testing even though the mitigation path had itemized it out.
- Capstones also re-check when a book closes — the moment a spell tome is
  learned — so a new master spell flips without opening the magic menu.
  (The precise SpellsLearned engine event is a known AE crash vector; the
  menu triggers are the safe equivalent.)
- **Active Effects page reflects DR and Absorb accurately (status-page 1.0
  work, part 2).** A new "Resurgence - Physical Damage Reduction" row shows
  your effective DR percent (earned AR, past-cap ladder included), and the
  "Resurgence - Elemental Absorb" row now shows the strongest element's
  current absorb percent — both magnitudes kept live by the DLL on load and
  menu open, with descriptions that say what actually counts. The DR row
  follows the Physical DR toggle.

### Changed
- **FOMOD retired.** One flat package: after the v0.10.0 scope cuts the
  installer was three info-only pages and a single file choice; every real
  decision is a runtime MCM toggle. The rebalanced Experience.ini now ships
  as a separate optional zip, so a plain install can never overwrite your
  Experience settings (the old flat package force-installed it).

### Fixed
- **The MCM "Physical DR Past 75%" toggle now actually gates the native
  hook.** The DLL never read MRO_F_ArmorCap — the switch was decorative on
  the native path since the hook shipped.
- **Past-cap DR now gates on EARNED armor only (1.0 gate item).** The DR
  ladder itemizes the victim's active effects and excludes armor rating
  granted by actively cast spells (wards, flesh spells) — worn armor,
  perks, permanent abilities, and enchantments still count in full, and
  hostile armor-melt debuffs still hurt. Cast-spell AR keeps its full
  value up to the engine's 75% cap; it just can't push DR past it. (The
  display alignment shipped in this same release — see Added.)

## v0.11.0 — 2026-07-10 (alpha)

### Added
- **Magic capstones (1.0 gate feature).** Per school: at mastery 50 that
  school's master (two-handed) spells become castable one-handed
  (RightHand equip slot — cannot dual-cast); at mastery 100 they become
  dual-cast eligible (EitherHand — still requires the school's dual-cast
  perk, which is never granted automatically). Applied natively by
  MRO.dll; slot changes are runtime-only and re-asserted on load, on
  magic level-ups, and when the magic menu closes (catches newly learned
  tomes). Toggling the mastery system off restores vanilla two-handed
  casting at the next check.

### Changed
- **Renamed to marth Resurgence Overhaul** (was marth Requiem Overhaul) as
  the mod broadens beyond Requiem-based lists. File names, FormIDs, and
  saves unchanged; all display strings (MCM, FOMOD, intro, ESP header)
  carry the new name from this release on.
- Requirements corrected: unused PapyrusUtil dropped, Address Library for
  SKSE Plugins added (always a real dependency of MRO.dll).

## v0.10.0 — 2026-07-09 (alpha)

### Added
- **Progress tab.** Per-skill mastery levels and percent-to-next now live on
  their own MCM page (grouped Combat / Defense / Magic / Crafting / Commerce),
  instead of being buried in the Mastery settings page.

### Changed
- **XP-speed sliders consolidated: 14 per-skill dials -> 5 group dials**
  (Combat, Defense, Magic, Crafting, Commerce). Group sliders write the same
  per-skill globals underneath, so existing saves and the ESP are untouched;
  old per-skill values re-unify the first time a group slider is accepted.

### Removed (scope cuts, user-approved 2026-07-09)
- **Carry Weight +150** — toggle, ability, and follower grants deleted.
  SCRIPT_VERSION 8 migration strips the spell from the player and followers
  on existing saves.
- **Arrow Recovery 66%** and **Faster Cell Reset** — toggles and GMST writes
  deleted; the GMSTs were runtime-only, so the load order's values return on
  next game load. Migration forces both feature globals off.
- **Weapon XP Pace dial** (0x808) — dead since v0.9.12 dropped the divisor in
  the native path; slider removed from Tuning.
- MCM sections for the above (Quality of Life, Baked Into ESP / Vendor Gold,
  Carry Weight live-status row) and the FOMOD "Quality of Life Features" page.
- **Vendor gold doubling removed from MRO.dll** (native pass; the UI stopped
  mentioning it in the same release).
- **MRO.dll is now REQUIRED.** The Papyrus no-DLL fallback is deleted: the
  legacy 30s heartbeat branch, the per-hit Papyrus weapon-XP grant, the
  GrantCombatArmorXP combat tick, and the long-dead DrainNative* bucket
  drains (unreferenced since v0.9.11). MRO.ini =0 now disables a hook's
  system outright instead of falling back.
- DLL diagnostic logging stripped (per-hit credit/weapon-XP lines, DR-AR
  itemization) — MRO.log is quiet in normal play again.

### Fixed
- **Level-up feedback rebuilt on the vanilla skill-up banner — sound
  included.** Root cause found by reading how the engine actually does it
  (via the New-Skill-Menu / MinimalSkills / CSF sources): the real skill-up
  experience is ONE flash call — the HUD's
  `QuestUpdateBaseInstance.ShowNotification(text, status, soundID, ...,
  level, startPct, endPct)` — banner, `UISkillIncreaseSD` chime, and the
  animated progress bar together. CSF's message API sends a text-only HUD
  message, which is why masteries never had audio; every direct sound
  attempt (all BSSoundHandle variants; a raw relocation call that
  read-AV'd off the main thread — only SkyrimCrashGuard's VEH recovery
  prevented a CTD at level-up) was aiming at the wrong mechanism. Mastery
  level-ups now show a single vanilla-styled banner ("One-Handed Mastery
  increased to 5") with the chime and a progress bar fed from the real
  mastery ratio, replacing the old CSF-message + corner-notification
  double-up. Fallback for HUD replacers without the widget:
  DebugNotification + CommonLib's own PlaySound, on the UI thread.

### Notes
- DLL banner synced to v0.10.0 this build (was v0.9.12).

## v0.9.13 — 2026-07-09 (alpha)

### Fixed
- **MCM mastery progress is live again.** The percent readout read a
  Papyrus-side value that the native XP path never updates, so weapon/armor
  progress froze at its last pre-native value (looked like "weapon XP broken"
  while the real ratio climbed — v0.9.12's engine fix was working all along).
  It now reads the same ratio globals the DLL writes.
- **MCM sliders and checkboxes repaint instantly.** The compile stub for
  SkyUI's `SKI_ConfigBase` declared `SetToggleOptionValue`/`SetSliderOptionValue`
  without the trailing `a_noUpdate` parameter; the VM silently rejects calls
  whose argument count doesn't match, so every live repaint failed and values
  only updated on a page switch. Long-standing.

### Notes
- DLL unchanged from v0.9.12 (banner reads v0.9.12); this is a scripts-only
  release. Diagnostic logging stays one more cycle (sound + DR itemization
  still under test).

## v0.9.12 — 2026-07-09 (alpha)

### Fixed
- **1H (and all weapon) mastery XP truly unstalled.** The v0.9.11 clamp removal
  wasn't enough: the per-hit credit was still divided by `MRO_T_WeaponXPPerAction`,
  a global that older saves persist at its pre-v0.9.1 value of **50** (its old
  meaning was "damage per action"), taxing weapon XP 50×. The divisor is gone —
  weapons now match armor exactly (one typical hit = one action); the XP-speed
  slider remains the pacing control.
- **Level-up sound, take three.** `Play()` succeeded but a static position at the
  player's feet was still inaudible; the emitter now follows the player's 3D node
  (`SetObjectToFollow`), the standard UI-sound recipe.

## v0.9.11 — 2026-07-09 (alpha)

### Fixed
- **Weapon mastery XP no longer stalls for strong characters.** Credited damage
  was clamped to the target's *remaining* HP ("overkill earns nothing"), so a
  character who out-damages enemies (sliver kill-hits, one-shots) earned almost
  nothing and weapon skills crawled ~100× too slow. Each hit now credits its
  actual damage, normalized by your typical hit. Diagnostic logging added to
  confirm the running average isn't skewed by outliers.

## v0.9.10 — 2026-07-09 (alpha)

### Fixed
- **MCM open republishes the DR-ladder mastery fraction**, so a manual/console
  mastery change reflects in the physical-DR calc without a save reload (there's
  no heartbeat to do it anymore).
- Weapon mastery XP now buckets weapons by **type** (from the animation type)
  rather than the weapon's `skill` field, which modded weapons often leave blank.

### Diagnostics
- Logs weapon-XP detection and the per-hit credit outcome (bounded) to trace a
  mastery skill that stalls at a fixed level/progress.

## v0.9.9 — 2026-07-09 (alpha)

### Fixed
- **Mastery level-up sound is now audible.** The native play succeeded but the
  sound was built as a positional (3D) source anchored at the world origin, so it
  played into the void. It's now anchored at the player, so every mastery level-up
  (weapon, armor, magic, craft, speech) actually rings.

### Changed
- **Armor mastery XP now uses the steep weapon curve** (was L²), so armor has the
  same long endgame grind as weapons in every configuration.

### Performance
- Mod-event sink now compares its event name via an interned pointer instead of a
  per-event string compare — negligible either way, but cleaner for a broadcast
  sink in a large load order.

### Diagnostics
- Logs the player's armor rating as `full` vs `permanent` when it changes, to pin
  down where spell-fortified AR (wards, flesh spells) sits — groundwork for making
  the DR ladder read worn+perk armor only.

## v0.9.8 — 2026-07-08 (alpha)

### Performance
- **Dropped the global weapon-swing listener.** MRO watched `OnActorAction(0)`
  to refresh the equipped-weapon bonus on quick swaps — but that SKSE event is
  **global**: it dispatches to our script for *every actor's* weapon swing in the
  entire load order, and each dispatch costs Papyrus VM time even though we bail
  on non-player. In a big fight on a large list that is a heavy, load-wide tax.
  The bonus now refreshes on the **player's own hits** (already player-scoped via
  the events ability) plus inventory close, so nothing is watched list-wide. The
  rarer `action 2` (spell fire, for magic XP) is unchanged for now.
- Also run the version upgrade on game load, not only on the (now-retired) tick,
  so an update-in-place applies on saves that have already gone tickless.

### Note
- Scripts-only update; the plugin is byte-identical to v0.9.7 (its load banner
  still reads v0.9.7). Let `Scripts/` overwrite.

## v0.9.7 — 2026-07-08 (alpha)

### Fixed
- **MCM self-heal, actually fixed.** The v0.9.5 approach hooked `OnGameReload`,
  which SkyUI only calls once (from `OnInit`) — so on a save that first
  registered an older MRO it never re-ran and the stale tab list survived. The
  config now re-asserts its pages in `OnConfigOpen`, which SkyUI calls every time
  the menu opens (right before it pushes the tab list to the UI), so a dropped
  page like the long-gone "Boss Readiness" tab can no longer be stuck.

### Diagnostics
- **Level-up sound**: the scripts correctly send the play event, so the plugin
  now logs the whole sound path (event received → descriptor resolved → sound
  built → played) to `MRO.log`, to pin down why `UISkillIncrease` isn't audible
  yet on some setups.

## v0.9.6 — 2026-07-08 (alpha)

### Changed
- **The 30-second mastery heartbeat is retired.** When the SKSE plugin is
  present it now credits weapon and armor mastery XP **per hit** — applying the
  full curve and level-ups inside the combat hook — and drives bonus updates
  through mod events instead of a timer. Papyrus reconciles all mastery bonuses
  once on each game load and again whenever a skill levels or gear changes
  (weapon draw, inventory/container close), so nothing polls on a clock. The old
  heartbeat remains only as a fallback for installs without the plugin.

### Fixed
- **The mastery level-up sound now plays.** The vanilla `Sound.Play` sat in a 2D
  UI dead spot and never fired; the plugin now plays `UISkillIncrease` through
  the audio manager, so every mastery level-up (weapon, armor, magic, craft,
  speech) has its sound cue.

### Notes
- Weapon/armor XP pacing is unchanged — the curve was ported to the plugin
  verbatim; only *where* it runs moved (off the tick, onto the hit).
- Native load banner now reads **v0.9.6**.

## v0.9.5 — 2026-07-08 (alpha)

### Fixed
- **MCM self-heal, nuclear.** v0.9.4's version-bump approach relied on SkyUI's
  `CheckVersion` firing `OnVersionUpdate` on the next load — which did not clear
  stale tabs (e.g. the long-gone "Boss Readiness" page) on affected saves, and
  `setstage SKI_ConfigManagerInstance 1` never helped. The config now re-asserts
  its ModName + Pages and forces a page reset on **every game load**
  (`OnGameReload`), independent of any stored version, so it can no longer be
  stuck on an old menu. No console command needed — just load the save once.

## v0.9.4 — 2026-07-08 (alpha)

### Added
- **Armor mastery XP is now measured in the combat hook** (victim side),
  symmetric with weapon XP: when the player is struck by a weapon, the SKSE
  plugin banks the post-DR damage taken (normalized per hit) and Papyrus credits
  Evasion or Heavy Armor mastery by the worn chest. The old 30-second combat
  tick is kept only as a fallback when the hook isn't installed. (Groundwork
  toward moving XP fully off the Papyrus heartbeat.)

### Fixed
- **Crafting mastery attribution.** Every station shares one "Crafting Menu", so
  the old code left Enchanting mastery unreachable and credited Smithing+Alchemy
  for every station. The workbench keyword is now read on open and only that
  station's mastery is credited (smelter/cooking/tanning train none).
- **MCM stuck on old tabs.** The config never versioned itself, so SkyUI froze
  the page list from a save's first registration — an old save could still show
  the removed "Boss Readiness" tab, and `setstage` re-register didn't clear it.
  The MCM now versions itself and refreshes pages on load (self-healing).
- **Hook handshakes now stand down correctly.** Each native hook's DLL->Papyrus
  flag is now written 0 when the hook isn't live (not merely left alone), so
  disabling a hook with `=0`, or downgrading/removing the DLL, reliably hands
  control back to the Papyrus fallback instead of a stale save value latching it
  off (covers DR, absorb, weapon-XP and armor-XP).

### Changed
- Weapon mastery pace ~20% faster (curve shape unchanged).
- **Native hooks default ON in code**, and the plugin writes a default `MRO.ini`
  when none exists. `MRO.ini` is no longer shipped in the package, so a manual
  upgrade can never overwrite your edited hook settings; an explicit `=0` still
  forces the Papyrus fallback for that hook.
- DLL rebuilt — load banner now reads v0.9.4 (synced to the package version).

## v0.9.3 — 2026-07-08 (alpha)

First tagged pre-release.

### Added
- MCM Tuning sliders for the two combat-XP pace dials: **Weapon XP Pace**
  (`MRO_T_WeaponXPPerAction`) and **Magic XP Pace** (`MRO_T_MagicXPPerCost`).
  Previously console-only.

### Removed
- The MCM "Testing" buttons (Grant +25 Evasion / Heavy Armor Mastery) — dev
  scaffolding that permanently granted irreversible mastery levels. QA via the
  console instead: `set MRO_ML_<Skill> to <n>`.

### Changed
- FOMOD refreshed: lowercase "marth"; version now auto-stamped by `release.sh`;
  the retired cell reset is no longer advertised as a core ON feature (now
  "Faster Cell Reset", default OFF, with the all-or-nothing caveat); mastery-XP
  descriptions updated to the current model; "13 skills" → 14.
- First-run intro popup and MCM copy corrected (14 skills; DR described as
  mastery-gated rather than a stale armor number; accurate cost-curve wording).
- README: added a Roadmap section.

### Notes
- Papyrus + FOMOD/docs only — **MRO.dll is byte-identical to v0.9.1**, so the
  load banner reads v0.9.1; the MCM version (0.9.3) is the package check.

## v0.9.2 — 2026-07-08

### Changed
- **Steeper endgame mastery curve for weapons and magic.** The top mastery
  levels now cost far more than the first: cost = `ActionsAtZero · (0.30·L³ +
  0.70·L⁴)` where `L = (100+level)/100`. It equals `1.0` at L=1 (so first-level
  cost is unchanged) and `13.34` at L=1.99 (so 199→200 is ~3.4× the old L²).
  One-Handed now runs ~90 hits at 100→101 → ~1,200 at 199→200 (2H ~54→720,
  bow ~45→600, same curve, per-weapon bases for fight-parity). Armor, crafting
  and Speech keep the gentler L². Curve is shared via one `CurveMult` helper so
  the two paths can't diverge.
- **Magic mastery XP is now cost-weighted** instead of a flat +1 per cast: each
  cast grants `effective magicka cost / MRO_T_MagicXPPerCost` actions (new
  global, default **150** magicka = 1 action; higher = slower). Bigger spells
  train far more than cheap ones and spamming the fastest novice spell no longer
  farms XP; a fully cost-reduced (free) spell earns nothing, by design. The
  combat gate on Destruction/Restoration/Conjuration is unchanged. Per-school
  balance is dialable with the existing per-skill XP-speed sliders. Magicka to
  first mastery level: Illusion 3,750 / Alteration 4,500 / Conjuration 6,000 /
  Destruction 9,000 / Restoration 15,000 (150 divisor).

### Notes
- Papyrus + one new global only — **MRO.dll is byte-identical to v0.9.1**, so
  the load banner still reports v0.9.1; the MCM version (0.9.2) is the package
  check. Save-safe over v0.9.x (additive global, `GetFormFromFile` bridge).

## v0.9.1 — 2026-07-08

### Changed
- **Weapon mastery XP normalized (fixes v0.9.0 runaway pace).** v0.9.0
  banked *raw* credited damage, which is an absolute number — so the XP rate
  scaled with the load order's damage economy and with build power, and
  strong endgame characters leveled far too fast. The DLL now divides each
  credited hit by a running average of the player's own per-hit damage, so
  one banked "action" ≈ one typical connecting hit. The rate is now invariant
  to the load order and to build power; harder-than-usual hits still count
  more, tanky enemies still pay proportionally, and overkill on trash is
  still self-limiting. See `docs/WEAPON_XP_MODELS.md` (normalized model).
- `MRO_T_WeaponXPPerAction` is repurposed from "damage per action" to a
  dimensionless pace dial (hits per action; higher = slower), **default 1.0**.
  First mastery level now costs ~60 hits (1H), ~36 (2H), ~30 (bow), scaling
  with the L² curve.

### Notes
- DLL and scripts must be installed together (the bucket units changed);
  the full package handles this. Save-safe over v0.9.0 — bridge globals are
  unchanged, only their meaning/scale. DR and elemental absorb untouched.

## v0.9.0 — 2026-07-08

### Changed
- **Weapon mastery XP reworked to damage-scaled (Model 2).** The native DLL
  now measures the player's *credited* weapon damage per hit — capped at the
  target's remaining HP, so overkill on trivial mobs earns nothing — and
  banks it per weapon skill; Papyrus drains it on the heartbeat through the
  existing L^2 curve. One-Handed and Two-Handed now train at parity, tanky
  enemies pay proportionally, and swing-farming weak mobs is self-limiting.
  The DLL only measures; Papyrus owns the curve and level-ups. Rides the
  existing DR weapon-hit hook (no new hook site). Rationale and the rejected
  kill-weighted alternative are in `docs/WEAPON_XP_MODELS.md`.
- Tunable: `MRO_T_WeaponXPPerAction` (default 50 = damage per XP "action";
  lower trains faster). Stacks with the global and per-skill speed dials.
- Mastery rows in the MCM drop the redundant `+N%` — it was the level as a
  percent of cap, not the gameplay bonus. The unit-correct per-skill bonus
  is (and was) in the row's hover text.

### Removed
- **Cell reset retired** (default OFF + one-time migration force-off).
  Lowering the respawn timers was too broad: it also returned display/quest
  items to cells and reverted one-time activators (e.g. Blackreach lifts).
  The load order's own respawn timers apply again on the next load.

### Notes
- Save-safe over v0.8.x: new globals use the `GetFormFromFile` bridge (not
  quest-baked), so no VMAD migration; FormIDs are additive. MCM settings
  persist. DR and elemental absorb are unchanged from v0.8.2.

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
