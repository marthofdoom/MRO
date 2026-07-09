# Debugging Cookbook — symptom → cause → fix

Every entry below was hit for real in this project. Work the table before
theorizing. The universal method when nothing matches:
**find a vanilla record that does what yours should, dump both with
`tools/dump_record.py`, and diff every subrecord** — type, order, size,
bytes. The engine rejects records silently; the diff always finds it.

Two rules of numeric diagnosis (both violated in the v0.9.10→12 1H-stall hunt,
costing two release cycles):
1. **When a computed number is wrong, log EVERY term of the formula.** The
   v0.9.11 diagnostic logged dmg, remaining, ref, and the actions *output* —
   every term except `pace`, the one that was guilty (stale at 50).
2. **Before shipping a fix, check the hypothesis reproduces the observed number.**
   The overkill-clamp theory could not explain `actions=0.011` on a NON-kill hit
   (dmg=181, remaining=756 — no clamping possible); that line was already in the
   log. actions=0.020 on a typical hit = exactly 1/50 pointed straight at pace.

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
| MCM sliders/checkboxes don't repaint on change (only on page switch); page RENDERS fine; no visible errors | Compile-stub arity mismatch: our SKI_ConfigBase stub declared `Set*OptionValue` WITHOUT the trailing `Bool a_noUpdate = false`. The compiler bakes the stub's arg count (defaults filled) into every call site, and the VM REJECTS calls whose arity differs from the runtime function — error goes only to Papyrus.0.log, which is disabled. The `Add*Option` stubs matched real arity, so pages rendered while every repaint call silently died (long-standing, found 2026-07-09) | Stub signatures must match real SkyUI EXACTLY, params AND defaults. Verify against real source — MCM Recorder ships the full `SKI_ConfigBase.psc` (`SetToggleOptionValue(Int, Bool, Bool a_noUpdate)`, `SetSliderOptionValue(Int, Float, String, Bool a_noUpdate)`). Audit the whole stub when one signature is wrong |
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
| Tuning global behaves ~N× off its documented default; changing the generator default does nothing | Same save-persistence, other direction: a NEW DEFAULT in the ESP never reaches an EXISTING save — the save's stored value wins forever. If a global's meaning/scale is ever retasked (MRO_T_WeaponXPPerAction went "damage per action"=50 → "pace dial"=1.0 in v0.9.1), every older save keeps the old-scale number silently (taxed weapon XP 50×, the v0.9.10-12 1H stall) | When ANY formula reads a tuning global, print the LIVE value before theorizing (console `help <edid>` or log it). Never retask a global's units — add a new FormID and retire the old one, or have the DLL/script migrate the stored value on version upgrade |
| MCM checkbox doesn't repaint until the menu is closed and reopened | OnOptionSelect routed a read/write through the quest script; cross-script calls block on the target's instance lock, which the 30s heartbeat holds for its whole run | Keep the repaint path local to the MCM script (read the GlobalVariable directly, SetValue, SetToggleOptionValue), and only then call into the quest. NOTE: this fix was necessary but NOT sufficient — the repaint still failed until a page switch because the compile stub's `Set*OptionValue` arity was wrong (see Papyrus/compilation table) |
| Console `set MRO_G_LAFrac to X` seems ignored / snaps back | Bridge globals are ONE-WAY (mastery level -> fraction -> global -> DLL); the 30s heartbeat republishes the real mastery over any manual write | By design. Test DR with the MCM Features > Testing buttons, which grant real mastery levels |
| CSF IncrementSkill/IncrementSkillBy do nothing, GetSkillLevel stuck at 0 | Skill JSON has no `"level"` binding — CSF's Skill::Increment silently no-ops without a Level GlobalVariable (`"levelCount"` is not a CSF key; numeric `"ratio"` is ignored; schema wants `"MRO.esp\|0xNNN"` form refs). CSF Increment also hard-caps at level 100 | Bind MRO_ML_* globals (0x850+idx) as `"level"` and MRO_MR_* (0x860+idx) as `"ratio"` in the JSONs; Papyrus writes levels via SetValue directly (bypasses the 100 cap), CSF only reads. When a framework call has no visible effect, READ ITS SOURCE — same doctrine as vanilla-record diffing |
| Load-wide FPS drop that vanishes the instant the mod is disabled | A GLOBAL SKSE actor event — `RegisterForActorAction`/`OnActorAction` — fires for **every actor in the load order**, and each firing is dispatched to your Papyrus script (VM cost) even when the handler bails on `akActor != PlayerRef`. Watching a HIGH-FREQUENCY action (weapon swing = action 0) list-wide taxes the whole VM; on a large list (LoreRim) a busy fight tanks FPS. Cost is the dispatch, not the handler body, so filtering inside the handler does NOT help. (Confirmed 2026-07-08: disabling MRO restored FPS; MRO.log was clean, ruling out the native hooks/sink; dropping the action-0 registration fixed it. The listener predated the tick-removal update — a latent tax, not a new regression.) | Don't register global actor-action events for frequent actions. Use PLAYER-SCOPED triggers: the AME weapon-hit event (`PO3_Events_AME.RegisterForWeaponHit`), a player ReferenceAlias, or menu events. `UnregisterForActorAction(n)` on upgrade — the registration persists in the save, so dropping the `RegisterForActorAction` call is NOT enough to stop the dispatch |
| MCM shows OLD title / tabs / labels after a script change | Two-layer staleness: (1) Papyrus never hot-swaps .pex — a session already running when you install keeps the old scripts; (2) SkyUI persists ModName + the Pages array in the SAVE. Pages is only written by `OnConfigInit` **and** `OnGameReload`, both of which run ONCE (OnGameReload's sole caller is OnInit → verified in SKI_ConfigBase.psc). On an existing save they already ran under the OLD script, so the stale Pages (e.g. a dropped tab) survive forever | First prove it's not stale pex: `grep -a` the INSTALLED .pex for a new-only string — new-present/old-absent = it IS the new script, so the staleness is SkyUI's cache, not the install. Then fix in code: override **`Function OnConfigOpen()`** to re-assert `Pages`/`ModName` (via your SetupPages). SkyUI calls OnConfigOpen on EVERY menu open (SKI_ConfigBase.psc:921) right before it pushes `setPageNames` with `Pages` (:923), so the tab list refreshes each open, unstickable. **Does NOT work (all tried & failed): `setstage SKI_ConfigManagerInstance 1`, GetVersion/OnVersionUpdate bump, OnGameReload override.** Add empty `OnConfigOpen`/`OnGameReload` to the repo's compile stub so the override type-checks |

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

## Papyrus engine log (Papyrus.0.log) on this setup

MRO.log only shows what OUR code prints. VM-level failures — arity-mismatch
call rejections (the Set*OptionValue repaint bug), event-registration errors,
stack dumps, whether an inherited event like OnConfigOpen fires at all — go
ONLY to the engine's Papyrus.0.log, which LoreRim ships disabled.

Enabling it is a maze (2026-07-09: two sessions produced NO log because the
edit landed in a dead ini). There are THREE Skyrim.ini's; set
`[Papyrus] bEnableLogging=1 bEnableTrace=1 bLoadDebugInformation=1` in ALL:

1. `profiles/Default/skyrim.ini` (LOWERCASE). The profile contains case-split
   duplicates (`skyrim.ini` + `Skyrim.ini`, ditto prefs/custom) on the
   case-sensitive fs; wine/MO2 resolves to lowercase — the game updates
   lowercase `skyrimprefs.ini`, never the capitalized one. An edit to
   `Skyrim.ini` (capital) is silently ignored.
2. `profiles/Default/Skyrim.ini` (capital) — keep it in sync anyway; which
   variant usvfs serves is resolution-order dependent.
3. The PREFIX-side file `<prefix>/drive_c/users/steamuser/Documents/My Games/
   Skyrim Special Edition/Skyrim.INI` — a FILE, distinct from the
   `My Games/Skyrim.INI/` *directory* that receives some SKSE logs. That
   My Games dir has the ext4 casefold attr (`lsattr` shows `F`), so any case
   spelling reaches it. MO2 has `profile_local_inis=true`, yet a session with
   ONLY the profile ini enabled wrote no log while the engine access-touched
   this file — the redirect does not reliably cover it under Proton.

The log lands in `Logs/Script/Papyrus.0.log` under `My Games/Skyrim Special
Edition/` or `My Games/Skyrim.INI/` — don't guess, `find <prefix> -iname
Papyrus.0.log -mmin -60`. No SkyrimCustom.ini currently overrides [Papyrus]
(verified 2026-07-09) — recheck if a log again fails to appear.

**REVERT all three to 0 after diagnosis** — trace logging costs perf, which
is why the list disables it.

## Crash analysis
Crash logs: `.../compatdata/3375297225/pfx/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition/SKSE/crash-*.log`.
Check POSSIBLE RELEVANT OBJECTS + CALL STACK for our forms/scripts. MRO is
pure Papyrus: it cannot cause native access violations — Papyrus bugs make
log errors, not CTDs. A deterministic same-action crash could implicate a
malformed record; random ones are other mods or the renderer.
