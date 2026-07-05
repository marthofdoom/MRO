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

## Crash analysis
Crash logs: `.../compatdata/3375297225/pfx/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition/SKSE/crash-*.log`.
Check POSSIBLE RELEVANT OBJECTS + CALL STACK for our forms/scripts. MRO is
pure Papyrus: it cannot cause native access violations — Papyrus bugs make
log errors, not CTDs. A deterministic same-action crash could implicate a
malformed record; random ones are other mods or the renderer.
