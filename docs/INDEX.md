# MRO Documentation Index — start here

This project is designed so any capable model or person can continue it
from these docs alone. Load documents on demand, not all at once.

## Read order for a fresh session

1. **PROJECT_PLAYBOOK.md** (always) — repo map, the build loop, the
   worked example, and the non-optional rules. ~2 pages.
2. **DEBUGGING.md** (when something misbehaves) — symptom → cause → fix
   for every failure class hit so far, plus the universal diff-against-
   vanilla method.
3. **MANUAL_MOD_CREATION_GUIDE.md** (when creating/altering RECORDS) —
   the binary format reference: record/group/subrecord encoding, verified
   recipes (GLOB, QUST, VMAD, MGEF, SPEL, PERK, FLST, LVLI, GMST, SEQ),
   Papyrus-on-Linux compilation, FOMOD rules.
4. **TESTING.md** (before claiming anything works) — console procedures
   per system.
5. **DYNAMIC_OR_DROP.md** (before adding features / planning 1.0) — the
   portability ledger and the native-hybrid direction.
6. **BEYOND_REQUIEM.md** (planning the real 1.0) — the list-profile plan:
   MRO as a framework with Requiem as its first detected profile, the
   Requiem-coupling ledger per system, and the decisions to make for
   non-Requiem lists.

## Tools (use instead of re-deriving)

- `tools/compile.sh all` — compile + distribute pex. Zero setup.
- `tools/dump_record.py <EDID> [--plugin p]` — inspect any record, ours
  or vanilla. THE diagnostic; use before writing any new record type.
- `tools/audit_esp.py` — wiring + FormID audit. Run after every change;
  PASS is a merge gate.

## The one principle

When touching the binary format: **copy a working vanilla record, never
trust documentation** — including this documentation. If a record
misbehaves, dump it and its vanilla twin and diff subrecords. Every
multi-day bug in this project (TES4 flags, FOMOD wrapper, SPIT type,
PERK layout, FormID prefix, SEQ) ended the moment we compared bytes
against something that worked.
