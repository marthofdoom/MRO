# Weapon Mastery XP — model mockup (Model 1 vs Model 2)

Status: **SHIPPED — Model 2, normalized (v0.9.1).** v0.9.0 shipped raw
damage-scaled Model 2; in-game testing showed the pace ran away because
raw damage is an absolute quantity — it scales with the load order's damage
economy and with build power, so strong endgame builds level far too fast.
v0.9.1 keeps Model 2's structure (overkill excluded, weapon-agnostic) but
**normalizes each hit by the player's own typical per-hit damage**, so the
XP unit is dimensionless. See "Normalized model (v0.9.1)" below. Model 1 is
retained only as the rejected alternative and the rationale trail.

Purpose: honestly
compare two ways to make weapon masteries level at a fair rate, because
today weapons train slower than armor/magic (flat "+1 per landed hit"
undervalues real fights and overvalues swing-farming trivial mobs).

Decision pending. This doc exists so we pick with eyes open, then build
exactly one.

## The two models

**Model 1 — kill-weighted (the mental model from the brief).**
Rewards the *event* of a fight/kill, with anti-cheese on trivial one-shots.

- Landed non-killing hit: **+1**
- Killing blow: **+1** (it is also a hit) **+ KILL** where
  `KILL = 6` for One-Handed / Archery, `11` for Two-Handed
- Anti-cheese: a killing blow that is a **regular** attack (not power,
  not sneak) **and** a **one-shot** (target was at full HP) → the whole
  swing scores **0** (killing a wolf in one swing is unrewarded)
- Sneak: a sneaking hit scores the **bonus only** (the +1 is dropped).
  A sneak **kill** scores `SNEAK_KILL = 11` (1H/bow) / `12` (2H);
  a sneak hit that doesn't kill scores +1.

**Model 2 — damage-scaled with overkill excluded.**
Rewards *damage actually inflicted*, capped at the target's remaining HP.

- Each hit: **+ min(damage_dealt, target_remaining_HP) / D**, `D = 27`
  (≈ "1 XP point per 27 effective damage"; D is the single tuning knob)
- Overkill (damage past 0 HP) earns nothing → a 110-dmg swing on a
  40-HP wolf only ever banks the wolf's 40 HP of credit
- Consequence: total XP to kill any enemy ≈ **its effective HP ÷ D**,
  independent of weapon or hit count. Sneak crits just front-load the
  same total. Enemy toughness sets the reward automatically.

## Assumptions for the theoreticals

Illustrative late-game (skill 100+) numbers, not exact Requiem values:

| Enemy (effective HP) | 1H hit | 2H hit | Bow hit | Bow sneak (×3) |
|---|---|---|---|---|
| Wolf — trivial (40)  | 50 | 110 | 70 | 210 |
| Bandit — standard (350) | 50 | 110 | 70 | 210 |
| Deathlord — elite (800) | 50 | 110 | 70 | 210 |

`D = 27` was chosen so a standard 7-hit fight lands near Model 1's ~13,
making the two directly comparable. Both constants are free to retune.

## Scenario comparison

| # | Scenario | Model 1 | Model 2 |
|---|---|--:|--:|
| S1 | Wolf, 1H, one regular swing (one-shot) | **0** | 1.5 |
| S2 | Wolf, 2H, one **power** attack (one-shot) | **12** | 1.5 |
| S3 | Bandit, 1H, 7-hit fight | 13 | 13.0 |
| S4 | Bandit, 2H, 4-hit fight | 3×1+(1+11)=**15** | 13.0 |
| S5 | Bandit, bow, sneak-open then 2 hits to kill | 1+1+(1+6)=**9** | 13.0 |
| S6 | Wolf, bow, **sneak one-shot** | **11** | 1.5 |
| S7 | Deathlord, 1H, 16-hit fight | 15+(1+6)=**22** | 29.6 |
| S8 | Deathlord, 2H, 8-hit fight | 7+(1+11)=**19** | 29.6 |
| S9 | Farm 10 wolves, 1H regular one-shots | 10×0=**0** | 15 |
| S10 | Farm 10 wolves, 2H power one-shots | 10×12=**120** | 15 |

## What the theoreticals reveal

**Model 1**
- Matches the brief's intent: real fights (~13) and sneak setups reward;
  trivial *regular* one-shots give nothing (S1, S9).
- **Hole:** the anti-cheese only covers *regular* attacks. Power-attack
  one-shotting trivial mobs is fully rewarded and farmable — S10 banks
  120 for the same "kill 10 wolves" that S9 scores 0. A 2H user simply
  power-attacks and ignores the anti-cheese.
- **Residual weapon bias:** on a long elite fight the *slower* weapon
  wins because it lands more +1 hits — 1H 22 vs 2H 19 (S7 vs S8) —
  which is backwards from "2H should feel heavier."
- Needs: kill detection, power-vs-regular detection, sneak detection,
  and full-HP/one-shot detection. Four signals, several edge cases.

**Model 2**
- Weapon-agnostic by construction: 1H and 2H tie on every fight
  (S3=S4, S7=S8) because total credited damage ≈ enemy HP either way.
- Enemy toughness *is* the reward curve: wolf 1.5, bandit 13, elite 30.
  Trivial mobs are self-limiting with **no special-casing** — overkill
  exclusion does the job the anti-cheese rule does in Model 1, but
  without a farmable hole (S9=S10=15, one number, no exploit).
- Sneak isn't specially rewarded (S6 = 1.5): a sneak one-shot of a wolf
  is still a trivial kill. If we *want* to bless sneak setups, add a
  small flat sneak-open bonus on top — cleaner than Model 1's parallel
  sneak track.
- Needs: per-hit **damage** and target **remaining HP**. Both are in the
  Valhalla weapon-hit `HitData` the DR hook already intercepts, so this
  is a natural fit for the native path (and stays weapon-agnostic
  without any Papyrus event plumbing).

## Recommendation

**Model 2**, tuned via the single `D` knob, optionally plus a small flat
"sneak opener" bonus if we decide stealth deserves a nudge. It delivers
every goal in the brief — reward real fights, ignore trivial kills, close
the 1H/2H gap — with one constant, no farmable exploit, and it rides the
native hook we already have. Model 1 gives explicit per-event control but
carries the power-attack farm hole (S10) and a backwards weapon bias
(S7/S8), and needs four detection signals.

Open knobs either way: `D` (or `KILL`/`SNEAK_KILL`), whether XP is banked
per-hit or per-kill, and how this scales against the list's base
progression speed read from `experience.ini` (see the load-order-aware
regenerator work — the same "XP per fight" number has to sit sensibly
next to how fast the base game levels).

## Normalized model (v0.9.1) — the shipped refinement

**Problem with raw Model 2 (v0.9.0):** it banked `min(damage, remaining)`
directly, so "damage" is an absolute number. The XP rate `Σdamage / D`
therefore varied with (a) the load order — a 30-per-swing list and a
400-per-swing list run ~13× apart through the same `D` — and (b) build
power — a buffed endgame character banks more per hit than a fresh one for
identical work, so the strong level faster (rich-get-richer runaway). No
value of `D` fixes this, because `D` is itself an absolute damage constant.

**Fix — normalize by your own typical hit.** Divide each credited hit by a
reference damage `ref` that tracks the player's per-hit output, so `credited
/ ref` is dimensionless: **one banked action ≈ one typical connecting hit.**

```
ref  = EMA of the player's per-hit damage on this weapon skill (per 1H/2H/bow)
bank += min(damage, remaining) / ref     // overkill still excluded
```

`ref` is a per-skill exponential moving average maintained in the DLL
(`avg = 0.9*avg + 0.1*damage`, seeded on the first hit, session-scoped —
re-converges in a few hits after a load, so it is deliberately not
save-persisted). Each hit is measured against the *prior* EMA, so a power
attack or sneak crit above your average banks >1 and a chip hit <1.

**Properties**
- **Load-order invariant:** `ref` scales with the list, so the unit cancels.
  Same fight → same actions on any list. (Was the whole complaint.)
- **Build invariant:** `ref` scales with your buffs too, so getting stronger
  no longer inflates XP — it kills the runaway.
- **Damage still counts:** harder-than-typical hits bank more, softer less;
  tankier enemies still pay proportionally (more hits to kill).
- **Trash still self-limiting:** overkill cap makes a one-shot bank `≈
  remaining/ref ≈ 0`. Farm hole stays closed, no special-casing.
- Converges toward "hits-to-kill" pacing (close to Model 1) but **without**
  Model 1's power-attack farm hole or backwards 1H/2H bias.

**Curve / tuning.** The bucket now feeds the shared `L²` curve in normalized
hits. With the 2.5× weapon XP-speed default, the first mastery level (100→101)
costs `ActionsAtZero/2.5` real hits: **1H 60, 2H 36, bow 30** (`ActionsAtZero`
= 150/90/75). The relative order compensates for hit *frequency* (1H lands
more swings per fight than a bow), so fights train at rough parity.
`MRO_T_WeaponXPPerAction` is repurposed from "damage per action" to a
dimensionless **pace dial** (hits per action; higher = slower), default 1.0 —
tune live with `set MRO_T_WeaponXPPerAction to <n>`.

**Coupling.** The DLL (banks normalized actions) and Papyrus (`perAction`
default 1.0) MUST ship together: old DLL banking raw damage + new Papyrus
dividing by 1.0 would run ~50× fast. Both land in v0.9.1.
