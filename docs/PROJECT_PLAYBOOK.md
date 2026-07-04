# MRO Project Playbook — how to do everything, copy-paste ready

Read docs/INDEX.md first if you haven't. This file is the operational
manual: repo map, standard workflows, and one worked example. All commands
run from the repo root.

## Repo map

```
MRO_GenerateESP.py       THE generator: emits MRO.esp + SEQ/MRO.seq from
                         pure Python. All records defined here. Never
                         hand-edit the ESP.
Source/Scripts/*.psc     Papyrus sources. MRO_* are shipped; everything
                         else is a compile-only stub (never ship stubs).
MRO-nofomod/             Flat package (known-good install path).
MRO-flat/                Same payload + fomod/ installer config.
tools/compile.sh         Compile scripts + copy pex to both packages.
tools/dump_record.py     Dump any record's subrecords (ours or vanilla).
tools/audit_esp.py       ESP<->script wiring + FormID audit. Run always.
release.sh               Cut an immutable release into releases/vX.Y.Z/.
VERSION / CHANGELOG.md   Version state. Bump on every kept build.
docs/                    This folder. Everything learned lives here.
```

Shipped scripts and their jobs:
- `MRO_StartupQuest.psc` — the engine room: 30s heartbeat, GMSTs, ability
  and perk-ladder distribution (player + PO3 followers), all mastery XP
  and bonuses, update-in-place migration (`SCRIPT_VERSION`).
- `MRO_MCM.psc` — SkyUI MCM (3 pages). Short row values; long text via
  OnOptionHighlight/SetInfoText only.
- `MRO_AbsorbMGEF.psc` — ActiveMagicEffect on the player/followers;
  OnHit absorb logic.

## The loop (every change)

```bash
python3 MRO_GenerateESP.py MRO-nofomod/     # if generator changed (~60s)
cp MRO-nofomod/MRO.esp MRO-flat/ && cp MRO-nofomod/SEQ/MRO.seq MRO-flat/SEQ/
tools/compile.sh all                        # if any .psc changed
python3 tools/audit_esp.py                  # must PASS
rm -f MRO-test-nofomod.zip MRO-v*.zip
(cd MRO-nofomod && zip -rq ../MRO-test-nofomod.zip .)
(cd MRO-flat    && zip -rq "../MRO-v$(cat VERSION).zip" .)
git add -A && git commit -m "..."
```
Release-worthy state: `./release.sh <new-version>` instead of the zip
lines (it rebuilds, archives immutably, commits, tags).

## Worked example: add a feature toggle end to end

Goal: new MCM-toggleable feature "X" driven by a GlobalVariable.

1. Generator: new FID in the `OWN | 0x8xx` block (next free; stay inside
   0x800-0xFFF), add `("MRO_F_X", FID_G_X, 'f', 1.0)` to `GLOBALS`, wire
   `("MRO_F_X", prop_obj(FID_G_X))` into BOTH quests' VMAD prop lists.
2. `MRO_StartupQuest.psc`: `GlobalVariable Property MRO_F_X Auto`, use
   `FeatureEnabled(MRO_F_X)` wherever behavior branches (None fails open).
3. `MRO_MCM.psc`: property, `_oidX` int, AddToggleOption in RenderFeatures,
   branch in OnOptionSelect (SetValue + SetToggleOptionValue + call the
   apply function), SetInfoText branch in OnOptionHighlight.
4. If the save needs migration (new arrays, new registrations): bump
   `SCRIPT_VERSION` and extend `RunUpgrade()`.
5. Run the loop above. Audit must PASS (it catches VMAD typos).
6. In-game: `help MRO_F_X 3` shows the global; toggle in MCM; verify.
7. Add a row to docs/TESTING.md.

## Rules that are not optional

- New record type? Dump a working vanilla equivalent FIRST
  (`tools/dump_record.py <edid>`) and copy it byte-for-byte. Format docs
  lie; Skyrim.esm doesn't. (This rule was bought with days of debugging.)
- FormIDs are forever once a build reaches a save. Never renumber.
- Own records: prefix 0x05, range 0x800-0xFFF (ESL). Audit enforces.
- ASCII everywhere (sources and user-facing strings).
- Releases and tags are immutable. Bump VERSION instead.
- Anything derived from THIS machine's load order at generation time is
  a portability liability — check docs/DYNAMIC_OR_DROP.md before adding
  more, and record new ones there.
- After changing GLOB defaults or record layouts, reinstall the zip in
  MO2 before testing — the game reads the installed copy, not the repo.

## Environment facts

- MO2 instance: /mnt/gaming/modlists/LoreRim (profile Default;
  plugins.txt / modlist.txt live there). MRO.esp loads last.
- Vanilla masters: "/mnt/gaming/modlists/LoreRim/Stock Game/Data/".
- Game logs/saves (Proton prefix): .../compatdata/3375297225/pfx/
  drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition/
- MRO.esp is ESL-flagged (TES4 flag 0x200) → loads as FE:xxx.
- The load order zeroes all vanilla use-based skill XP (Static Skill
  Leveling): MRO masteries are the only use-trained progression.
