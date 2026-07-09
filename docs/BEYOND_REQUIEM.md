# Beyond Requiem — the list-profile plan for the real 1.0

**Framing (set 2026-07-08).** The Requiem-tuned mod we have now is *one profile*
of the eventual 1.0, applied when Requiem is detected. A true 1.0 detects the
load order's balance style and applies profile-appropriate defaults so MRO fits
more than Requiem/LoreRim. This doc is the decision framework and architecture
for that generalization. It is deliberately *decisions-open*: make the calls
per system after the v0.9.6 playtest, then implement.

Two release shapes, both valid:
- **1.0 of the Requiem module** — ship what we have, labeled as the Requiem
  profile of MRO. Honest, useful today, no false "works everywhere" claim.
- **MRO 1.0 (the framework)** — detection + at least one non-Requiem profile,
  plus the rename. This doc is the path to that.

Relationship to [`DYNAMIC_OR_DROP.md`](DYNAMIC_OR_DROP.md): that ledger asks
"does a feature behave as advertised on *any load order, given Requiem-style
assumptions*?" This doc asks the layer above: "when those assumptions **don't**
hold (non-Requiem list), what changes?" DYNAMIC_OR_DROP is within-profile
portability; this is across-profile design.

---

## 1. Architecture: a profile is a set of default values, not new code

MRO already separates cleanly into three layers:
- **Mechanism** — DLL hooks + Papyrus systems (DR curve, XP crediting, absorb,
  bonus application). Profile-agnostic; already written.
- **Policy/tuning** — the ~68 ESP globals (feature toggles + tuning constants:
  `MRO_F_*`, `MRO_T_*`, `MRO_Mastery*`, per-skill XP speed, DR99 target, etc.).
- **Display** — MCM + CSF.

**A "profile" is just a named set of defaults for the policy globals** (plus a
few "feature off entirely" flags). No profile needs new mechanism. Generalizing
= adding a *detection + default-selection* layer in front of the globals. This
is why the mod is well-positioned for it: the hard part (mechanism) is done and
already knob-driven.

### Who sets the defaults

1. **Regenerator (install time)** — the decided detection vehicle (see
   [`DYNAMIC_OR_DROP.md`](DYNAMIC_OR_DROP.md) §native-hybrid and the roadmap).
   A standalone script (also callable by a C# FOMOD installer; MO2 XML FOMOD
   can't run scripts, so it must also run manually) that reads `plugins.txt` +
   relevant INIs, picks a profile, and **bakes that profile's global values into
   MRO.esp** while regenerating it against the real load order. This is where
   per-list calibration lives (best armor set, spell-cost divisor, etc.).
2. **DLL (runtime)** — fills gaps the regenerator can't know statically (actual
   in-game armor values, live spell costs) and can *confirm/override* the
   detected profile at `kDataLoaded`. Also the natural place for a
   `MRO_G_Profile` global the MCM reads.
3. **MCM (runtime)** — shows the active profile, and every tuning knob stays a
   user override. Profiles set *defaults*, never a cage.

Precedence: **user MCM override > DLL runtime detection > regenerator bake >
hardcoded fallback (the Requiem profile).**

---

## 2. The Requiem-coupling ledger

Each MRO system, what it silently assumes about Requiem/LoreRim, what changes
off-Requiem, and the decision to make. Coupling = how Requiem-specific it is.

### Skill Mastery — the whole progression system · coupling: **HIGH**
- **Assumes:** the list **zeroes use-based skill XP** (Static Skill Leveling),
  so MRO's mastery is the *only* use-trained progression, gated on base skill
  ≥ 100. (`MRO_StartupQuest.psc:726`; `PROJECT_PLAYBOOK.md:110`.)
- **Off-Requiem:** a normally-leveling list still trains skills 1→100 by use.
  Mastery(100+) then stacks *on top* of vanilla leveling rather than replacing
  it. The base-100 unlock gate still reads sensibly ("vanilla-mastered, now go
  further"), but the *feel* differs and mastery is now additive power, not the
  main axis.
- **Decision:** (a) keep the base-100 gate universally (my lean: yes — it's a
  clean, list-agnostic "endgame begins" line), or gate differently per profile;
  (b) on lists where skills level fast, does mastery-on-top overpower? Consider
  a profile flag to soften the mastery *bonuses* (not the XP) when the list
  doesn't zero skill XP. Note: mastery **action costs** are derived from vanilla
  AVSK, so they're portable by construction — only the *targets* ("~1000 1H hits
  at cap") are a Requiem-combat feel choice, tunable via the XP-speed globals.

### Physical DR past the engine cap (armor masteries) · coupling: **HIGH**
- **Assumes:** a Requiem-style raised armor economy where "armor matters at
  endgame" and pushing DR past the 75% engine cap to 99% is desirable. The
  DR99 target is already auto-calibrated to the list's best heavy set.
- **Off-Requiem:** vanilla-leveled / lighter lists cap at 80% and don't want an
  armor-god ladder; it would trivialize their intended difficulty.
- **Decision:** treat DR-past-cap as a **profile feature** (default ON for
  Requiem, OFF or re-targeted elsewhere). The mechanism already reads the live
  cap GMSTs, so "off" is just a default toggle. Non-Requiem may still want the
  *armor masteries* (as flat armor-rating bonuses) without the past-cap ladder —
  keep those independently toggleable.

### Elemental resist uncap + absorb · coupling: **MEDIUM**
- **Assumes:** nothing structural — reads resistances at runtime, fully generic.
  The *defaults* (uncap ON, full-absorb at 200% resist) are Requiem balance.
- **Off-Requiem:** mechanism is fine anywhere; only the default ON/OFF and the
  absorb threshold are balance calls per list.
- **Decision:** per-profile defaults for the toggle + `MRO_T_AbsorbMax`. Low
  effort — pure default selection.

### Magic mastery XP (cost-weighted, divisor 150) · coupling: **HIGH**
- **Assumes:** Requiem spell magicka-cost economy; `MRO_T_MagicXPPerCost=150`
  gives sane pacing against Requiem costs.
- **Off-Requiem:** different spell-cost economies mis-pace magic mastery (too
  fast on cheap-spell lists, too slow on expensive ones).
- **Decision:** **regenerator scans the list's actual spell costs to
  auto-calibrate the divisor** (already flagged in the roadmap). Ship a
  per-profile fallback constant for when the scan can't run.

### Vendor gold doubling · coupling: **MEDIUM-HIGH**
- **Assumes:** a tight Requiem/LoreRim economy where doubled merchant gold is a
  deliberate QoL that doesn't break progression.
- **Off-Requiem:** generous-economy lists get further unbalanced by 2×.
- **Decision:** per-profile (default ON for Requiem; OFF or a scale factor
  elsewhere). Mechanism is native and list-agnostic; only the default changes.
  Consider a `MRO_T_VendorGoldMult` so it's a dial, not a boolean.

### Weapon / armor / magic mastery bonus magnitudes · coupling: **MEDIUM**
- **Assumes:** +50% weapon dmg, +300 armor, +50 skill are balanced against
  Requiem's damage/armor numbers. +300 armor is worth more on a low-armor list.
- **Off-Requiem:** the same numbers land differently relative to the list's
  scale.
- **Decision:** per-profile magnitudes (they're already globals/sliders). Lower
  effort than it looks — just profile defaults.

### QoL toggles (carry weight +150, arrow recovery 66%) · coupling: **LOW**
- Generic; keep as universal toggles. No per-profile decision needed beyond
  default ON/OFF taste.

### Intro popup + MCM copy · coupling: **LOW-MEDIUM**
- Text references Requiem framing in places. Make profile-aware (or neutral)
  once a second profile exists. Cosmetic but part of the "not Requiem-specific"
  claim, so it gates the rename.

---

## 3. Detection signals

Regenerator reads `plugins.txt`/`loadorder.txt` (+ INIs); DLL confirms at
runtime. Proposed signal → profile mapping:

| Signal | Meaning | Implication |
|---|---|---|
| `Requiem.esp` present | Requiem list (LoreRim, Ultimate, etc.) | **Requiem profile** (current defaults) |
| `Experience.esp` + `Experience.ini` | character leveling via Experience mod | pace character-level-linked defaults from the INI |
| Static Skill Leveling active (skill-XP zeroed) | mastery is the only use-progression | base-100 gate is the *main* axis; keep as-is |
| No skill-XP zeroing | vanilla/normal skill leveling | mastery is *additive*; consider softening bonuses |
| Encounter-Zone / deleveling overhaul (non-Requiem) | Requiem-like difficulty, different economy | a distinct non-Requiem "hard" profile |
| None of the above | vanilla-leveled | **Vanilla profile**: DR-past-cap OFF, gold OFF, gentle pacing |

Detection is best-effort and **always user-overridable** in the MCM. When
unsure, fall back to the Requiem profile (fail toward the tested config) and say
so in the MCM/log.

---

## 4. Adding a profile (the mechanical shape)

A profile is a table of default values for the policy globals. Concretely:

1. Define the profile as a named dict in the regenerator (e.g. `PROFILE_REQUIEM`,
   `PROFILE_VANILLA`), keyed by the same global EDIDs `MRO_GenerateESP.py`
   already emits (`MRO_F_*`, `MRO_T_*`, `MRO_Mastery*`, XP-speed `0x870+idx`,
   `DR99Armor`, `MagicXPPerCost`, plus new `feature-off` flags where a whole
   system is disabled).
2. Regenerator picks the profile from detection, writes those values as the
   ESP globals' initial values, and (where applicable) computes calibrated
   values (best armor set → DR99; spell-cost scan → magic divisor).
3. Add a `MRO_G_Profile` global (name/enum) so the DLL/MCM can display it.
4. MCM "About/Status" shows the active profile; all knobs remain overrides.

No new *mechanism* per profile — if a profile needs behavior MRO can't express
through existing globals, that's a mechanism gap to close first, not a profile.

---

## 5a. Decided (2026-07-08)

- **Release shape:** ship **1.0 of the Requiem module** now (clear label); build
  the framework toward a later 1.0.
- **Mastery on non-static-leveling lists:** additive + **soften the bonuses** →
  a true Vanilla profile is in scope.
- **Profiles:** **Vanilla**, **Any / generic**, and an **Experience.ini-driven**
  profile. Only **Requiem** gets bespoke treatment; everything else is one of
  those three.
- **DR-past-cap off-Requiem:** keep armor masteries as **flat bonuses, drop the
  past-cap ladder** — BUT first settle *how armor behaves on non-Requiem lists*
  (see below; the flat +armor bonus may be a no-op at a reachable vanilla cap).
- **Detection depth:** distinguish Requiem vs Experience.ini vs Vanilla/generic
  (medium — plugin presence + the Experience.ini check).
- **Name:** keep the **MRO** initials/plugin (`MRO.esp` for save-compat); change
  only what the letters stand for (drop "Requiem" from the expansion).

### OPEN — armor behavior on non-Requiem lists (to resolve before the Vanilla profile)
Vanilla armor converts rating → DR at `fArmorScalingFactor` (~0.12%/point) up to
`fMaxArmorRating` (~80% DR), and a full smithed set reaches that cap easily — the
opposite of Requiem, where armor is scarce and the cap is a long grind (which is
what the 75→99% mastery ladder rewards). Consequence: on a vanilla list a flat
**+armor-rating** mastery bonus is often a **no-op at endgame** (already capped).
So the non-Requiem armor mastery likely needs a *different* reward than "+armor":
e.g. a small flat DR inside the cap, a modest cap raise, or a defensive capstone
(stagger/stamina). Decide this when we build the Vanilla profile.

## 5b. Decisions to make (after the v0.9.6 playtest)

Ranked by how much they shape the framework. Each is a genuine call for you:

1. **Release shape** — ship "1.0 of the Requiem module" now, or hold 1.0 for the
   framework + one non-Requiem profile + rename? (My lean: ship the Requiem
   module as-is under a clear label once 0.9.6 tests clean; build the framework
   toward a later 1.0 so the rename lands with real multi-list support.)
2. **Mastery on non-static-leveling lists** — additive-and-softened, or same as
   Requiem? Decides whether "Vanilla profile" is viable or MRO stays
   Requiem-family-only for 1.0.
3. **Which non-Requiem profile first** — pure vanilla-leveled, or another
   difficulty overhaul (which one)? Pick the one you'll actually test against.
4. **DR-past-cap default off-Requiem** — off entirely, or flat armor masteries
   without the ladder?
5. **Detection depth** — how hard to try (plugin presence is easy; parsing
   Experience.ini / detecting skill-XP-zeroing is more work). Start shallow
   (Requiem present? y/n) and deepen.
6. **The name** — the rename gates the "beyond Requiem" marketing. Needs a
   name that isn't Requiem-specific and is Nexus-safe.

---

## 6. Release gate for the framework 1.0

- At least the Requiem profile **and** one non-Requiem profile, each tested on a
  representative list.
- Detection falls back to Requiem (tested config) when unsure, and logs/MCM-shows
  the chosen profile.
- Every DYNAMIC_OR_DROP item still resolved (that ledger is a prerequisite, not
  superseded).
- MCM/intro copy no longer assumes Requiem.
- Rename applied consistently (plugin stays `MRO.esp` for save-compat unless a
  clean break is chosen — decide deliberately).

Until then: the Requiem module is a legitimate, shippable 1.0-of-a-module. The
framework is the next arc, not a blocker on getting the finished Requiem work
into players' hands.
