# Native Rewrite Plan — MRO.dll (CommonLibSSE-NG)

Goal: one small SKSE DLL alongside the existing ESP + Papyrus, absorbing
the four systems Papyrus can't do exactly. The Papyrus layer keeps the
MCM, mastery bookkeeping, intro/upgrade logic.

Method: the same discipline that made the ESP work — never invent, copy
from working open source. Every hook below has a published mod that
already does it; we adapt their hook, we don't reverse-engineer from
scratch.

## Hook inventory (feature -> reference source)

| # | Feature | Reference (public source) | What we take |
|---|---|---|---|
| 1 | ~~DR curve via ARR-style asm cave~~ **REJECTED 2026-07-04** | [gottyduke/ArmorRatingRescaledRemake](https://github.com/gottyduke/ArmorRatingRescaledRemake) | Verified DEAD on 1.6.1170: `tools/verify_hook_site_live.py` proved both cave sites moved in the 1.6.1130+ recompile (Func2's offset lands past its function's end; Func1 lost its float math entirely). Instruction-level cave patches are banned as a strategy — one game update kills them |
| 2 | Damage-pipeline hooks (DR correction + absorb) — the new M2/M3 | [D7ry/valhallaCombat](https://github.com/D7ry/valhallaCombat) (maintained post-1.6.1170) | `write_vfunc` vtable hooks (version-independent, no code-layout dependence) and call-site `write_call` thunks — every thunk site MUST pass tools/verify_hook_site_live.py against the running 1.6.1170 game before shipping. Physical DR: adjust final damage for player/teammates by (1-ourDR)/(1-engineDR). Absorb: same pipeline, magic side |
| 3 | Vendor gold doubling, dynamic on any load order | plain SKSE kDataLoaded handler (pattern in every template) | On data-loaded: look up the 13 VendorGold* LVLIs by EditorID, double counts in memory. No baked records — DROP-CANDIDATE resolved |
| 4 | Event sinks (hit/menu/cast) + config bridge | TESHitEvent etc. — the most documented CommonLibSSE pattern | Retires MRO_EventsMGEF shim + PO3 event dependency |
| 5 | Mastery bookkeeping (stretch) | [Exit-9B/CustomSkills](https://github.com/Exit-9B/CustomSkills) — CSF is open source (MIT), itself native; skills are GlobalVariable-backed | Read CSF's source for exact level/XP semantics; drive skills natively. KNOWN VARIABLE per user's criterion (2026-07-04) — but only port if play-tested Papyrus mastery gains something concrete |

M4 scoping rule (user, 2026-07-04): port everything that is a *known
variable* (documented pattern or readable source); do not port working,
light Papyrus just for purity. Confirmed working in 0.5.1 play:
one-handed, restoration, evasion mastery XP all accruing.

## Toolchain (decided by constraints)

- Cross-compiling from Linux is not viable today: CommonLibSSE-NG needs
  MSVC ABI and the Microsoft linker ("linking must still be done with the
  Microsoft linker" — upstream README).
- **Primary: GitHub Actions, windows-latest runner** (MSVC preinstalled).
  Start from [libxse/commonlibsse-ng-template](https://github.com/libxse/commonlibsse-ng-template)
  or SkyrimDev/HelloWorld-using-CommonLibSSE-NG; both carry CI workflows.
  Build artifact = MRO.dll downloaded from the Actions run.
- Fallback: msvc-wine locally (heavier setup; only if CI iteration is
  too slow).
- Step 0 requires a GitHub remote for this repo (gh CLI available):
  `gh repo create MRO --private --source . --push` — needs user's
  public/private choice before doing it.

## Milestones — each one user-tested in game before the next

- **M0 skeleton**: template repo + CI green; DLL loads, logs its version
  and game version to `MRO.log`. Zero hooks. Proves the whole pipeline.
- **M1 vendor gold**: kDataLoaded LVLI patch (pure data edit, no code
  hooks — lowest possible crash surface). Retire the generator's LVLI
  scan + baked records.
- **M2 armor DR hook** — IMPLEMENTED 2026-07-05 (v0.7.0), awaiting
  in-game verification. Weapon-hit call thunk at Valhalla's site
  (AL 38627 + 0x4A8) with SELF-VERIFYING install (requires E8 opcode at
  the site, else logs and skips). Exact per-hit curve for player and
  teammates; mastery ceiling via bridge globals (0x818/0x819 published
  by Papyrus heartbeat); MRO_G_NativeDR (0x81A) stands the perk ladder
  down. Default ON as of v0.8.2 (verified in-game): SKSE/Plugins/MRO.ini
  bPhysicalDRHook=1; set 0 to fall back to the Papyrus ladder.
  LIVE 2026-07-04 20:00 on the user's save: self-verified E8 at
  38627+0x4A8 (site shared with another mod's trampoline — standard
  stacking, we wrap it), NativeDR handshake confirmed, Papyrus ladder
  standing down. The earlier "processHit inlined" investigation is
  RETRACTED — it was an artifact of loading versionlib-1-6-1170-0-1.bin
  (wrong binary revision) instead of versionlib-1-6-1170-0.bin.
  VALIDATE THE DATABASE FILE against crash-log ground truth before
  trusting any address (ID 38785 -> 0x6c4d90 on this exe).
  v0.7.1 (2026-07-05): the kDataLoaded write of MRO_G_NativeDR=1 was
  clobbered by save load (GlobalVariable values are save-persisted) --
  the MCM showed "Perk Ladder" and Papyrus never stood down, though the
  code hook itself was live. Fixed: re-assert on kPostLoadGame/kNewGame.
  Testing now uses MCM Features > Testing buttons (real CSF mastery
  levels via IncrementSkillBy) because the 30s heartbeat overwrites
  console writes to the bridge globals by design.
  Combat stress test pending; then retire ladder perk records.
- **M3 elemental absorb** — IMPLEMENTED 2026-07-06 (v0.8.0-wip), awaiting
  in-game verification. Call thunk at po3 PapyrusExtender's magicApply
  site (`RELOCATION_ID(33742, 34526)`, AE offset `0x20B`), `write_call<5>`
  with SELF-VERIFYING install (E8 opcode required, else logs + skips) and
  logs the raw site bytes to MRO.log. Runs the original AddTarget first,
  then heals: reads the pre-resistance magnitude straight off
  `AddTargetData::magnitude` (0x3C) — the caster's skill/perk/dual-cast-
  scaled damage at 0% resist — which the Papyrus OnHit version could not
  see (it only had the spell's authored base magnitude, so absorb read
  "too small to see"). Formula unchanged: heal = mag *
  (resist-100)/(fullAt-100), capped 1.0; spill past full HP goes 50/50 to
  stamina/magicka. Player + teammates; elemental/magic/poison resists;
  detrimental/hostile effects only. Bridge global MRO_G_NativeAbsorb
  (0x81B) stands the Papyrus OnHit path down (re-asserted on load, same
  as NativeDR). Default ON as of v0.8.2 (verified in-game): SKSE/Plugins/
  MRO.ini bAbsorbHook=1; set 0 to fall back to the Papyrus OnHit absorb.
  OFFSET VERIFIED LIVE 2026-07-06: `tools/verify_hook_site_live.py 34526
  0x20B E8` = MATCH on the user's running 1.6.1170 (offline verify is
  IMPOSSIBLE — Steam-DRM encrypts the on-disk exe; the static
  verify_hook_site.py reads garbage. Always use the _live variant against
  the running process for AE hook sites).
- **M4 cleanup**: Papyrus keeps MCM/mastery; MCM toggles write an INI or
  globals the DLL reads.

## Safety rules (non-negotiable)

- Address Library IDs only — never raw offsets. Version-gate to the
  runtime we target (1.6.1170) and no-op with a log line on mismatch.
- Every hook individually toggleable via `MRO.ini`; ship defaults
  matching whatever has been play-tested.
- One hook per release. A CTD bisects to exactly one change.
- Papyrus fallback stays in the ESP until its native replacement has
  survived real play; features swap via config, not deletion.
- Crash logs checked after every session (docs/DEBUGGING.md, crash
  analysis section).

## Open decisions for the user
1. GitHub repo: private or public? (CI needs the remote either way.)
2. Target runtime confirmed 1.6.1170 only, or multi-runtime NG build?
