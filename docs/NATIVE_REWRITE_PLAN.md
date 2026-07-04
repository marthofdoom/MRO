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
| 1 | Exact continuous DR curve past cap, player/follower-scoped | [gottyduke/ArmorRatingRescaledRemake](https://github.com/gottyduke/ArmorRatingRescaledRemake) | Trampoline hook on the armor DR calculation (Address Library IDs). We add an actor check: player/teammate -> our kinked curve with mastery ceiling; everyone else -> vanilla. Replaces the 24-perk ladder + 30s lag |
| 2 | Per-actor resistance behavior + elemental absorb on real damage | [Jampi0n/Skyrim-ResistancesRescaled](https://github.com/Jampi0n/Skyrim-ResistancesRescaled) | Per-resistance damage-reduction hook, already player-scoped — solves "enemies also uncap" AND gives the exact applied damage, so absorb heals true numbers (enchants, traps, everything). Replaces MRO_AbsorbMGEF approximations |
| 3 | Vendor gold doubling, dynamic on any load order | plain SKSE kDataLoaded handler (pattern in every template) | On data-loaded: look up the 13 VendorGold* LVLIs by EditorID, double counts in memory. No baked records — DROP-CANDIDATE resolved |
| 4 | (later) hit events, temper caps | po3 CommonLibSSE usage | Only if we retire more Papyrus |

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
- **M2 armor DR hook** (ArmorRatingRescaledRemake pattern): behind an
  INI flag, default off until tested. Retire perk ladder when confirmed.
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
