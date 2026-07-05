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
  down. Default OFF: SKSE/Plugins/MRO.ini bPhysicalDRHook=0.
  ENABLE FLOW: run tools/verify_hook_site_live.py 38627 0x4A8 (expect
  E8) with the game running, then flip the INI, then check MRO.log for
  "DR hook installed". Retire perk ladder records after play-testing.
- **M3 resist/absorb hook** (ResistancesRescaled pattern): same
  flag-gated rollout. Retire MRO_AbsorbMGEF heal path.
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
