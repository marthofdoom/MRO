# MRO In-Game Test Procedures

Console-driven, repeatable checks for every system. Clean up `modav`
deltas afterwards — they persist in the save.

## Install sanity
- `help MRO_ 0` — GLOBs, quests, spells, perks all resolve (FE-prefixed ESL ids)
- `help MRO_DR76 4` and `help MRO_Barter01 4` — perk ladders loaded
- Active Effects UI shows "Elemental Absorb" and "Carry Weight Bonus"
  (constant self abilities with FULL names; may take one 30s heartbeat)
- `player.getav CarryWeight` — +150 over base
- MCM "marth Requiem Overhaul" present, pages Mastery + Features (else
  `setstage ski_configmanagerinstance 1` to re-register title/tabs)

## Elemental absorb
Native as of v0.8.0 (MRO.ini bAbsorbHook=1). First confirm the hook took —
`Documents/My Games/Skyrim Special Edition/SKSE/MRO.log`:
```
Absorb site @ ID 34526 + 0x20B: E8 ?? ?? ?? ??
Absorb hook installed (site verified: E8 at ID 34526 + 0x20B)
Absorb hook active: MRO_G_NativeAbsorb=1, Papyrus absorb standing down
```
Console banner reads "absorb hook: ACTIVE". If the site byte is not E8 the
hook logs + skips and the Papyrus OnHit path stays in control (fallback).
Re-verify the offset live after any game update:
`tools/verify_hook_site_live.py 34526 0x20B E8`.
```
player.getav FireResist
player.modav FireResist 150        ; well past 100
player.damageav Health 200
player.cast 12FCD player right     ; Firebolt at self
```
Health goes UP on the hit — and, unlike the old Papyrus version (authored
base magnitude, barely visible), the native heal uses the REAL per-hit
magnitude, so it is clearly visible. Controls: at exactly 100 → no damage,
no heal; MCM toggle off → no heal. Overflow: at full health, the heal
spills into stamina/magicka (watch those bars). MCM Features > Live Status
shows "(absorbs N%)" per element while over 100.

## Physical DR ladder
```
player.getav DamageResist
player.modav DamageResist 1000     ; cross the kink
```
Wait 30s. `player.hasperk <MRO_DRxxPerk fid>` — rung matches
MCM Features > Live Status "Physical DR". At the 99% slider point damage
taken drops to ~1/25th of the engine cap's. Toggle off → perk removed
within 30s. Cleanup: `player.modav DamageResist -1000`.

## Mastery XP gating
- Swing at air / a rock / a corpse / a follower: NO progress (MCM Mastery
  page percentages unchanged).
- Land hits on a hostile enemy with base skill >= 100: progress ticks;
  level-up shows the CSF skill-increase banner AND a corner notification
  ("<Skill> Mastery increased to N") with the vanilla skill-up sound.
  Hovering a mastery row shows that skill's live bonus in the info bar.
- Casting spells out of combat: no school XP; in combat: XP per cast.
- Crafting menus and barter menus grant session XP (skill >= 100 only).

## Vendor gold
Values are baked at ESP generation from the live load order (doubled).
Merchants only re-roll chest gold on CELL RESET — wait 72+ in-game hours
away from the shop, then barter and check gold (e.g. spell vendors 1840).

## Speech mastery barter ladder
With Speech mastery leveled: buy prices drop up to 20%, sell prices rise
up to 25%. Verify perk: `player.hasperk <MRO_BarterXXPerk fid>`; compare
a vendor's price for the same item before/after `player.addperk`/removal.

## Smithing temper caps
`getgamesetting fSmithingArmorMax` — rises with Smithing mastery
(base x2 at full mastery). Temper an item at a workbench to confirm the
higher ceiling.

## Update-in-place
After installing a new MRO build over an existing save: one
"updated in place" notification on next heartbeat, no repeated intro
popup, mastery XP array intact (MCM percentages preserved).
