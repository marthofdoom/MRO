# Debugging Cookbook — symptom → cause → fix

Every entry below was hit for real in this project. Work the table before
theorizing. The universal method when nothing matches:
**find a vanilla record that does what yours should, dump both with
`tools/dump_record.py`, and diff every subrecord** — type, order, size,
bytes. The engine rejects records silently; the diff always finds it.

## Records / ESP

| Symptom | Cause | Fix |
|---|---|---|
| Record absent from `help <edid> 4` in-game, but present when parsing the ESP | Loader rejected it: wrong/extra/missing subrecord vs vanilla layout | Diff against vanilla twin. Known: PERK must have no trailing PRKF after last entry, playable=1 hidden=0 |
| Constant ability does nothing, not in Active Effects | SPIT spell type 3 (Lesser Power) — must be **4** (Ability). Or SPEL missing OBND/ETYP/DESC | See guide "SPEL (ability)" recipe |
| Fortify-AV ability applies but the actor value never moves | MGEF archetype 0 (Value Modifier) silently no-ops for fortify-from-ability; vanilla fortify MGEFs are archetype **34 (Peak Value Modifier)** + Recover flag | Copy the vanilla twin's DATA field-for-field (AbFortifyCarryWeight: flags 0x208802, 0.5 at DATA[48], archetype 34). Record fixes don't reach active-effect instances already in saves — bump SCRIPT_VERSION and Remove+AddSpell in the migration |
| One record broken while its neighbors work | FormID collides with a real record in a master (own prefix wrong) | Own records need own-file master index prefix (0x05 with 5 masters) AND 0x800-0xFFF (ESL). `tools/audit_esp.py` checks both |
| Start-game-enabled quest never starts on existing save | No Run Once flag + no SEQ file | Generator writes SEQ/MRO.seq — ship it. Run Once quests don't need SEQ (which is why one quest works and the other doesn't) |
| MCM never appears | Quest not running (above), or quest has Run Once (SkyUI can't re-register), or SkyUI hasn't rescanned | Fix flags/SEQ; then `setstage ski_configmanagerinstance 1` |
| GMST override ignored | Another plugin loads later, or an SKSE DLL manages that setting | GMSTs match by EDID, last plugin wins; also re-apply from script heartbeat to beat runtime writers |
| Script property is None at runtime | VMAD property name doesn't match .psc Property, or not wired at all | `tools/audit_esp.py` |
| "invalid vector subscript" dialog from MO2 on install | FOMOD `<group>` missing `<plugins order="Explicit">` wrapper | See guide FOMOD section; empty-install options need `<files/>` |

## Papyrus / compilation

| Symptom | Cause | Fix |
|---|---|---|
| "unknown type X" compiling, X is a vanilla/SKSE class | Missing .psc in import path | One-line stub in Source/Scripts: `Scriptname X extends Form Hidden` |
| "cannot relatively compare variables to None" at a nonsense line | Stripped Actor.psc from compiler bundle shadowing SKSE's | SKSE64 sources must be in imports (tools/compile.sh has them) |
| Error line numbers don't match the file | Multibyte UTF-8 in source | ASCII only, everywhere |
| `â€¢` garbage in-game text | Non-ASCII in user-facing strings | ASCII only |
| Compiler can't run (mono errors) | System wine lacks Mono | Use Proton Hotfix wine — baked into tools/compile.sh |

## Runtime behavior

| Symptom | Cause | Fix |
|---|---|---|
| Popup/effect repeats every load or randomly | State flag set AFTER a queued UI call, or FormIDs changed between installs orphaning globals | Latch before showing; never change FormIDs post-release |
| Old script instances erroring in logs after update | Prior install had different FormIDs; orphaned instances in save | Inert noise on a test save; keep FormIDs stable so it never recurs |
| Mastery/percent progress from swinging at air | RegisterForActorAction(0) fires on swings, not hits | PO3 `RegisterForWeaponHit` → OnWeaponHit; gate on living hostile Actor target |
| PO3 event registered but NEVER fires (e.g. zero weapon XP) | Receiver script extends Quest — PO3 per-form events only deliver to ObjectReference/ActiveMagicEffect/ReferenceAlias scripts | Host registrations on a hidden always-on ability's AME (MRO_EventsMGEF pattern) and forward to the quest |
| Vendor gold unchanged after LVLI override | Merchant chest only re-rolls on cell reset | Wait 72+ in-game hours away from the cell |
| Feature works for player but not followers | Ability/perk granted to player only | Follower loop via `PO3_SKSEFunctions.GetPlayerFollowers()` in the heartbeat |
| GMST you scale keeps growing each cycle | Reading back your own written value | Capture base before first write, keep in a saved script var |
| DLL writes a GlobalVariable at kDataLoaded but Papyrus reads the old value in-game | GlobalVariable values are SAVE-PERSISTED: loading a save restores its stored value over anything written earlier (cost us the v0.7.0 NativeDR handshake) | Re-assert DLL-owned globals on `kPostLoadGame` and `kNewGame`, not just kDataLoaded |
| MCM checkbox doesn't repaint until the menu is closed and reopened | OnOptionSelect routed a read/write through the quest script; cross-script calls block on the target's instance lock, which the 30s heartbeat holds for its whole run | Keep the repaint path local to the MCM script (read the GlobalVariable directly, SetValue, SetToggleOptionValue), and only then call into the quest |
| Console `set MRO_G_LAFrac to X` seems ignored / snaps back | Bridge globals are ONE-WAY (mastery level -> fraction -> global -> DLL); the 30s heartbeat republishes the real mastery over any manual write | By design. Test DR with the MCM Features > Testing buttons, which grant real mastery levels |
| CSF IncrementSkill/IncrementSkillBy do nothing, GetSkillLevel stuck at 0 | Skill JSON has no `"level"` binding — CSF's Skill::Increment silently no-ops without a Level GlobalVariable (`"levelCount"` is not a CSF key; numeric `"ratio"` is ignored; schema wants `"MRO.esp\|0xNNN"` form refs). CSF Increment also hard-caps at level 100 | Bind MRO_ML_* globals (0x850+idx) as `"level"` and MRO_MR_* (0x860+idx) as `"ratio"` in the JSONs; Papyrus writes levels via SetValue directly (bypasses the 100 cap), CSF only reads. When a framework call has no visible effect, READ ITS SOURCE — same doctrine as vanilla-record diffing |
| MCM shows OLD title / tabs / labels after a script change | Two-layer staleness: (1) Papyrus never hot-swaps .pex — a session already running when you install keeps the old scripts; (2) SkyUI caches ModName + the Pages array (set in OnConfigInit, runs once per save) even after the new pex loads | Prove it: `grep -a` the INSTALLED .pex for the new vs old string — new-present/old-absent = running an old pex. Fix: full save reload (rendered rows update immediately; they regen per open), then `setstage SKI_ConfigManagerInstance 1` to re-register title + tabs |

## Native hooks (pre-ship verification — MANDATORY)

- **SkyrimSE.exe is Steam-DRM encrypted on disk.** Static byte reads
  return noise. Verify hook sites against the RUNNING game:
  `tools/verify_hook_site_live.py <AL-ID> <insn-offset> <expected-hex>`
  (reads /proc/<pid>/mem at module base + AL-resolved RVA).
- **MULTIPLE versionlib .bin files can exist for one game version**
  (e.g. versionlib-1-6-1170-0.bin vs -0-1.bin for a different binary
  revision). The wrong one parses fine and yields plausible-but-shifted
  addresses — half a day was lost to "proving" a function inlined that
  wasn't. Validate the DB against crash-log ground truth first: a crash
  log line like "38785+0x16D => exe+0x6C4EFD" pins ID 38785 to
  0x6c4d90; check `load_database(...)[38785]` matches before believing
  anything else.
- `tools/verify_hook_site.py` parses the local Address Library .bin
  (decode ported from CommonLibSSE REL::IDDatabase) — useful for the
  ID->RVA mapping even when disk bytes are useless.
- **Instruction-cave / fixed-offset asm patches are banned**: the
  1.6.1130+ recompile moved ArmorRatingRescaledRemake's both cave sites
  (verified live 2026-07-04) — one game update = CTD. Prefer
  `write_vfunc` vtable hooks (layout-independent); call-site thunks
  only with a live byte-match first.
- capstone (pip --user --break-system-packages) disassembles live
  dumps when hunting for relocated code.
- **"MRO.log is missing" but the DLL loaded fine**: check skse64.log —
  `plugin MRO.dll ... loaded correctly` means SetupLog ran, so the log
  exists *somewhere*. On this LoreRim setup SKSE::log::log_directory()
  resolved to `Documents/My Games/`**`Skyrim.INI`**`/SKSE/MRO.log` (an
  sMyGamesDirectory quirk — other plugins still used "Skyrim Special
  Edition"). `find <prefix> -iname MRO.log` finds it. The prefix for a
  non-Steam shortcut lives under `~/.local/share/Steam/steamapps/
  compatdata/<id>/pfx`, not the modlist folder. For a throwaway diagnostic
  build you can force the log somewhere readable by writing a game-root-
  relative path (`Data/SKSE/Plugins/MRO.log`, like ReadIni) — MO2's USVFS
  redirects it to the Overwrite folder on the real filesystem.

## Crash analysis
Crash logs: `.../compatdata/3375297225/pfx/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition/SKSE/crash-*.log`.
Check POSSIBLE RELEVANT OBJECTS + CALL STACK for our forms/scripts. MRO is
pure Papyrus: it cannot cause native access violations — Papyrus bugs make
log errors, not CTDs. A deterministic same-action crash could implicate a
malformed record; random ones are other mods or the renderer.
