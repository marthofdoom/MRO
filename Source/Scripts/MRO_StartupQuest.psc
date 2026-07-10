Scriptname MRO_StartupQuest extends Quest

; ===============================================================
; PROPERTIES — Core abilities (set by xEdit script)
; ===============================================================
Spell    Property MRO_AbsorbAbility      Auto
Spell    Property MRO_CarryWeightAbility Auto
Spell    Property MRO_EventsAbility      Auto  ; hidden, always on: hosts PO3 event receivers
Actor    Property PlayerRef              Auto
FormList Property MRO_DRPerks            Auto  ; 24 perks, index 0 = 76% DR ... 23 = 99% DR
FormList Property MRO_SpeechPerks        Auto  ; 5 perks, barter bonus rungs 1..5

; MCM tuning globals
GlobalVariable Property MRO_T_DR99Armor          Auto  ; armor rating for 99% DR (default 2000)
GlobalVariable Property MRO_T_ArmorMasteryBonus  Auto  ; armor mastery bonus at cap (default 300)
GlobalVariable Property MRO_T_WeaponMasteryBonus Auto  ; weapon mastery bonus % at cap (default 50)

; ===============================================================
; PROPERTIES — Feature flags (GlobalVariables set by xEdit)
; Null GlobalVariable = feature defaults to ON.
; ===============================================================
GlobalVariable Property MRO_F_ResistCap     Auto
GlobalVariable Property MRO_F_ArmorCap      Auto
GlobalVariable Property MRO_F_Absorb        Auto
; Features cut in v0.10.0; properties (and MRO_CarryWeightAbility above) are
; kept ONLY so the v8 migration can force them off / strip the spell on
; existing saves. No application code reads them anymore.
GlobalVariable Property MRO_F_CarryWeight   Auto
GlobalVariable Property MRO_F_ArrowRecovery Auto
GlobalVariable Property MRO_F_CellReset     Auto
GlobalVariable Property MRO_SetupDone       Auto

; ===============================================================
; MASTERY CONFIG
; ===============================================================
GlobalVariable Property MRO_MasteryEnabled   Auto
GlobalVariable Property MRO_MasteryBaseGrant Auto
GlobalVariable Property MRO_MasteryCap       Auto   ; default 100, range 50-200

; ===============================================================
; CSF SKILL ID CONSTANTS
; ===============================================================
String Property ID_OH  = "MRO_Mastery_OneHanded"   AutoReadOnly
String Property ID_TH  = "MRO_Mastery_TwoHanded"   AutoReadOnly
String Property ID_MK  = "MRO_Mastery_Marksman"    AutoReadOnly
String Property ID_LA  = "MRO_Mastery_LightArmor"  AutoReadOnly
String Property ID_HA  = "MRO_Mastery_HeavyArmor"  AutoReadOnly
String Property ID_DS  = "MRO_Mastery_Destruction" AutoReadOnly
String Property ID_RS  = "MRO_Mastery_Restoration" AutoReadOnly
String Property ID_AL  = "MRO_Mastery_Alteration"  AutoReadOnly
String Property ID_CJ  = "MRO_Mastery_Conjuration" AutoReadOnly
String Property ID_IL  = "MRO_Mastery_Illusion"    AutoReadOnly
String Property ID_SM  = "MRO_Mastery_Smithing"    AutoReadOnly
String Property ID_AC  = "MRO_Mastery_Alchemy"     AutoReadOnly
String Property ID_EN  = "MRO_Mastery_Enchanting"  AutoReadOnly
String Property ID_SP  = "MRO_Mastery_Speech"      AutoReadOnly

; ===============================================================
; PERSISTENT STATE — Mastery bonus deltas currently applied
; ===============================================================
Float _bonusWeapon  = 0.0
Float _bonusLA      = 0.0
Float _bonusHA      = 0.0
Float _bonusDS      = 0.0
Float _bonusRS      = 0.0
Float _bonusAL      = 0.0
Float _bonusCJ      = 0.0
Float _bonusIL      = 0.0
Float _bonusSM      = 0.0
Float _bonusAC      = 0.0
Float _bonusEN      = 0.0
String _activeWeaponSkill = ""
Bool   _introShown = false
; Which crafting skill the currently-open "Crafting Menu" trains, captured on
; open from the workbench keyword ("SM"/"AC"/"EN"/""). All stations share one
; menu name, so we must read the station to credit the right mastery.
String _craftSkill = ""

; Bump SCRIPT_VERSION whenever an update needs migration on existing
; saves (new arrays, changed registrations, re-applied state). The
; saved _installedVersion lags behind after an update-in-place, and
; the next heartbeat runs RunUpgrade() exactly once.
Int Property SCRIPT_VERSION = 10 AutoReadOnly
Int _installedVersion = 0

; Smithing temper caps as read from the load order before we scale them
Float _smithArmorBase  = 0.0
Float _smithWeaponBase = 0.0
Int   _speechRung      = -1

; Per-skill XP accumulators (fraction of the current level, 0-1).
; We own the XP curve explicitly (CSF's AdvanceSkill curve is opaque and
; only exposes integer levels) so the MCM can show granular progress.
Float[] _mxp

; Cached mastery level/ratio/xp-speed globals (0x850/0x860/0x870 + idx),
; filled lazily. These run per landed hit / per cast — look up once,
; cache forever (FormIDs are frozen post-release).
GlobalVariable[] _mLvlG
GlobalVariable[] _mRatG
GlobalVariable[] _mXpmG

; ===============================================================
; STARTUP
; ===============================================================
Event OnInit()
    GiveAbilitiesTo(PlayerRef)
    RegisterMasteryEvents()
    ReconcileAll()   ; GMST features + follower abilities + bridge globals + bonuses

    If !MRO_SetupDone || MRO_SetupDone.GetValueInt() == 0
        RegisterForSingleUpdate(20.0)
    Else
        RegisterForSingleUpdate(5.0)
    EndIf
EndEvent

Function RegisterMasteryEvents()
    ; The always-on events ability hosts PO3 weapon-hit receivers
    ; (PO3 per-form events never deliver to Quest scripts).
    If MRO_EventsAbility && !PlayerRef.HasSpell(MRO_EventsAbility)
        PlayerRef.AddSpell(MRO_EventsAbility, false)
    EndIf
    ; DLL -> Papyrus events that replace the 30s heartbeat: a per-hit level-up
    ; (native weapon/armor XP) and a once-per-load reconcile. SKSE persists mod-
    ; event registrations in its co-save, so registering once carries across
    ; loads; OnInit also reconciles directly to cover the first game start.
    RegisterForModEvent("MRO_MasteryLevelUp", "OnNativeMasteryLevelUp")
    RegisterForModEvent("MRO_GameLoaded", "OnNativeGameLoaded")
    RegisterForModEvent("MRO_PlayerSpellCast", "OnNativePlayerSpellCast")
    ; PERF: action 0 (weapon swing) was a GLOBAL all-actors event and the biggest
    ; Papyrus tax in big fights. Explicitly unregister it (saves that ran an older
    ; MRO still hold the registration, so dropping the call is not enough), and
    ; refresh the weapon bonus off the player's own hits instead (HandleWeaponHit).
    UnregisterForActorAction(0)
    UnregisterForActorAction(2)   ; v10: spell casts now come from the DLL's native sink
    If MasteryEnabled()
        RegisterForMenu("Crafting Menu")
        RegisterForMenu("BarterMenu")
        RegisterForMenu("InventoryMenu")   ; chest swap: refresh armor bonus
        RegisterForMenu("ContainerMenu")   ; auto-equip from a container
    EndIf
EndFunction

; ===============================================================
; UPDATE CYCLE
; ===============================================================
Event OnUpdate()
    If _installedVersion != SCRIPT_VERSION
        RunUpgrade(_installedVersion)
        _installedVersion = SCRIPT_VERSION
    EndIf

    If MRO_SetupDone && MRO_SetupDone.GetValueInt() == 0 && !_introShown
        ; Latch BEFORE showing so no re-entry or stale instance can queue
        ; the intro more than once.
        _introShown = true
        MRO_SetupDone.SetValue(1)
        RunFirstTimeSetup()
        RegisterForSingleUpdate(30.0)
        Return
    EndIf

    ; MRO.dll is REQUIRED (v0.10.0): weapon/armor XP is credited per hit and
    ; the level-up sound + bonus reconcile are driven by mod events (OnNative*
    ; handlers). Reconcile once here (covers a pending update that fired on
    ; load) and never reschedule — the legacy no-DLL heartbeat is deleted.
    ReconcileAll()
EndEvent

; ===============================================================
; EVENT-DRIVEN RECONCILE (replaces the 30s heartbeat)
; ===============================================================
; One-shot reconcile of everything the retired heartbeat did each cycle:
; publish the bridge globals the DLL reads, re-apply GMST features (they revert
; on load), refresh follower abilities, and recompute every mastery bonus to the
; current level + gear. Driven by OnInit (first start) and OnNativeGameLoaded
; (every load) instead of a timer.
Function ReconcileAll()
    PublishBridgeGlobals()
    ApplyGMSTFeatures()
    RefreshFollowerAbilities()
    If MasteryEnabled()
        UpdateWeaponMasteryBonus()
        UpdateArmorMasteryBonuses()
        UpdateMagicMasteryBonuses()
        UpdateCraftingMasteryBonuses()
        UpdateSpeechMasteryBonus()
        ApplySmithingMastery()
    EndIf
EndFunction

; DLL fires this on every kPostLoadGame / kNewGame — our per-load reconcile.
Event OnNativeGameLoaded(String eventName, String strArg, Float numArg, Form sender)
    ; Run the version upgrade HERE too, not just in OnUpdate: once a save has gone
    ; tickless (native active), OnUpdate never fires again, so an update-in-place
    ; would otherwise never run RunUpgrade (which re-registers events, e.g. the
    ; action-0 unregister). This event fires on every load via the DLL.
    If _installedVersion != SCRIPT_VERSION
        RunUpgrade(_installedVersion)
        _installedVersion = SCRIPT_VERSION
    EndIf
    ReconcileAll()
EndEvent

; DLL fires this when it credits a weapon/armor mastery level (numArg = skill
; index). The level global is already written native-side; we own the message,
; the bonus refresh, and re-publishing the armor DR fraction to the DLL.
Event OnNativeMasteryLevelUp(String eventName, String strArg, Float numArg, Form sender)
    Int idx = numArg as Int
    String sid = SkillIdFromIndex(idx)
    If sid == ""
        Return
    EndIf
    Int newLevel = 0
    GlobalVariable lg = Game.GetFormFromFile(0x850 + idx, "MRO.esp") as GlobalVariable
    If lg
        newLevel = lg.GetValueInt()
    EndIf
    AnnounceMasteryLevelUp(sid, newLevel)
    RefreshBonusForIndex(idx)
    PublishBridgeGlobals()   ; armor mastery fraction feeds the native DR calc
EndEvent

; Refresh only the bonus family the given skill index belongs to.
Function RefreshBonusForIndex(Int idx)
    If !MasteryEnabled()
        Return
    EndIf
    If idx <= 2
        UpdateWeaponMasteryBonus()
    ElseIf idx <= 4
        UpdateArmorMasteryBonuses()
    ElseIf idx <= 9
        UpdateMagicMasteryBonuses()
    ElseIf idx <= 12
        UpdateCraftingMasteryBonuses()
        ApplySmithingMastery()
    Else
        UpdateSpeechMasteryBonus()
    EndIf
EndFunction

; Inverse of SkillIndex: 0-13 -> mastery id string ("" if out of range).
String Function SkillIdFromIndex(Int idx)
    If idx == 0
        Return ID_OH
    ElseIf idx == 1
        Return ID_TH
    ElseIf idx == 2
        Return ID_MK
    ElseIf idx == 3
        Return ID_LA
    ElseIf idx == 4
        Return ID_HA
    ElseIf idx == 5
        Return ID_DS
    ElseIf idx == 6
        Return ID_RS
    ElseIf idx == 7
        Return ID_AL
    ElseIf idx == 8
        Return ID_CJ
    ElseIf idx == 9
        Return ID_IL
    ElseIf idx == 10
        Return ID_SM
    ElseIf idx == 11
        Return ID_AC
    ElseIf idx == 12
        Return ID_EN
    ElseIf idx == 13
        Return ID_SP
    EndIf
    Return ""
EndFunction

; ===============================================================
; UPDATE-IN-PLACE MIGRATION
; Runs once when the shipped script is newer than what this save
; last ran. Quiet on fresh installs (the intro covers those);
; notifies when an existing playthrough was upgraded.
; ===============================================================
Function RunUpgrade(Int fromVersion)
    ; Mastery XP accumulators: create or migrate if the skill count
    ; ever changes between versions (v2: 13 -> 14, Speech added).
    If !_mxp
        _mxp = new Float[14]
    ElseIf _mxp.Length != 14
        Float[] fresh = new Float[14]
        Int i = 0
        Int copyMax = _mxp.Length
        If copyMax > 14
            copyMax = 14
        EndIf
        While i < copyMax
            fresh[i] = _mxp[i]
            i += 1
        EndWhile
        _mxp = fresh
    EndIf

    ; v4: the CarryWeight MGEF record changed archetype (broken plain
    ; Value Modifier -> vanilla's Peak Value Modifier). Active effect
    ; instances in the save still run the old data, so strip the spell
    ; everywhere; the re-grants below hand out the fixed one.
    If fromVersion > 0 && fromVersion < 4 && MRO_CarryWeightAbility
        If PlayerRef.HasSpell(MRO_CarryWeightAbility)
            PlayerRef.RemoveSpell(MRO_CarryWeightAbility)
        EndIf
        Actor[] fols = PO3_SKSEFunctions.GetPlayerFollowers()
        Int fi = 0
        While fols && fi < fols.Length
            If fols[fi] && fols[fi].HasSpell(MRO_CarryWeightAbility)
                fols[fi].RemoveSpell(MRO_CarryWeightAbility)
            EndIf
            fi += 1
        EndWhile
    EndIf

    ; v5: retire the cell-reset feature. Lowering the respawn timers was
    ; too broad -- it also respawns display/quest items ("dolls" back in
    ; cells) and can revert one-time activators (Blackreach lifts). Force
    ; it off once for saves that stored the old default of 1; the load
    ; order's own respawn GMSTs win again on the next game load. This is
    ; the one toggle we deliberately override -- all others are preserved.
    If fromVersion > 0 && fromVersion < 5 && MRO_F_CellReset
        MRO_F_CellReset.SetValue(0.0)
    EndIf

    ; v8 (v0.10.0): scope cut -- carry weight +150, arrow recovery 66%, and
    ; cell reset are removed entirely. Force the toggles off and strip the
    ; carry-weight spell everywhere; the GMSTs the old code set are runtime-
    ; only, so the load order's own values win again on the next game load.
    If fromVersion > 0 && fromVersion < 8
        If MRO_F_CarryWeight
            MRO_F_CarryWeight.SetValue(0.0)
        EndIf
        If MRO_F_ArrowRecovery
            MRO_F_ArrowRecovery.SetValue(0.0)
        EndIf
        If MRO_F_CellReset
            MRO_F_CellReset.SetValue(0.0)
        EndIf
        If MRO_CarryWeightAbility
            If PlayerRef.HasSpell(MRO_CarryWeightAbility)
                PlayerRef.RemoveSpell(MRO_CarryWeightAbility)
            EndIf
            Actor[] cwFols = PO3_SKSEFunctions.GetPlayerFollowers()
            Int cwi = 0
            While cwFols && cwi < cwFols.Length
                If cwFols[cwi] && cwFols[cwi].HasSpell(MRO_CarryWeightAbility)
                    cwFols[cwi].RemoveSpell(MRO_CarryWeightAbility)
                EndIf
                cwi += 1
            EndWhile
        EndIf
    EndIf

    ; Re-assert everything that must survive an update: settings,
    ; abilities, and event registrations (all idempotent).
    ApplyGMSTFeatures()
    GiveAbilitiesTo(PlayerRef)
    RefreshAbilities()
    RefreshFollowerAbilities()
    RegisterMasteryEvents()

    ; Only announce true mid-playthrough upgrades, and only when the
    ; intro already ran (a fresh install announces via the intro).
    If MRO_SetupDone && MRO_SetupDone.GetValueInt() == 1
        Debug.Notification("marth Resurgence Overhaul: updated in place, settings re-applied.")
    EndIf
EndFunction

; ===============================================================
; FIRST-RUN INTRO
; ===============================================================
Function RunFirstTimeSetup()
    Debug.MessageBox("marth Resurgence Overhaul is active.\n\nThis mod rebalances late-game power scaling:\n\n- Elemental resist above 100% absorbs that element's damage as health\n  (101% = 1% absorbed, 200% = full absorb)\n- Physical DR scales past the 75% armor cap, gated by your armor mastery\n- 14-skill Mastery system unlocks after each base skill reaches 100\n\nAll features can be toggled in the MRO MCM under Features.\nMastery cap (default 100, up to 200) is adjustable under Mastery.")
EndFunction

; ===============================================================
; GMST FEATURE APPLICATION
; ===============================================================
Function ApplyGMSTFeatures()
    If FeatureEnabled(MRO_F_ResistCap)
        Game.SetGameSettingFloat("fPlayerMaxResistance", 10000.0)
    EndIf

    UpdateArmorDRFor(PlayerRef)
EndFunction

; ===============================================================
; ABILITIES
; ===============================================================
Function GiveAbilitiesTo(Actor akActor)
    If !akActor
        Return
    EndIf
    If FeatureEnabled(MRO_F_Absorb)
        If !akActor.HasSpell(MRO_AbsorbAbility)
            akActor.AddSpell(MRO_AbsorbAbility, false)
        EndIf
    EndIf
EndFunction

Function RefreshAbilities()
    If FeatureEnabled(MRO_F_Absorb)
        If !PlayerRef.HasSpell(MRO_AbsorbAbility)
            PlayerRef.AddSpell(MRO_AbsorbAbility, false)
        EndIf
    Else
        If PlayerRef.HasSpell(MRO_AbsorbAbility)
            PlayerRef.RemoveSpell(MRO_AbsorbAbility)
        EndIf
    EndIf
    ; Display-only Active Effects row for physical DR (v9): the DLL keeps its
    ; magnitude equal to the effective DR percent. Player only; follows the
    ; past-cap DR toggle. Looked up by FormID (v0.9.3 precedent, no VMAD).
    Spell drStatus = Game.GetFormFromFile(0x84C, "MRO.esp") as Spell
    If drStatus
        If FeatureEnabled(MRO_F_ArmorCap)
            If !PlayerRef.HasSpell(drStatus)
                PlayerRef.AddSpell(drStatus, false)
            EndIf
        ElseIf PlayerRef.HasSpell(drStatus)
            PlayerRef.RemoveSpell(drStatus)
        EndIf
    EndIf
EndFunction

; ===============================================================
; PAPYRUS<->DLL BRIDGE
; Fractions published for the native DR hook; MRO_G_NativeDR is set
; by the DLL when its hook is live, telling the perk ladder to stand
; down. Looked up by FormID (not VMAD) so existing saves work.
; ===============================================================
Function PublishBridgeGlobals()
    GlobalVariable la = Game.GetFormFromFile(0x818, "MRO.esp") as GlobalVariable
    If la
        la.SetValue(GetMasteryFraction(ID_LA) * 100.0)
    EndIf
    GlobalVariable ha = Game.GetFormFromFile(0x819, "MRO.esp") as GlobalVariable
    If ha
        ha.SetValue(GetMasteryFraction(ID_HA) * 100.0)
    EndIf
EndFunction

Bool Function NativeDRActive()
    GlobalVariable g = Game.GetFormFromFile(0x81A, "MRO.esp") as GlobalVariable
    Return g && g.GetValueInt() == 1
EndFunction

; MCM Testing button: grant REAL armor mastery levels via CSF and push
; them to whichever DR engine is live, immediately. Real levels survive
; the 30s heartbeat (unlike console writes to the bridge globals, which
; it overwrites) — this is the supported way to test the DR ladder.
; CSF has no decrement; use on a throwaway save.
Function TestGrantArmorMastery(Bool heavy, Int levels)
    String id = ID_LA
    If heavy
        id = ID_HA
    EndIf
    GlobalVariable lg = MasteryLevelGlobal(id)
    If !lg
        Debug.Notification("MRO: mastery level global missing - ESP out of date?")
        Return
    EndIf
    Int newLevel = lg.GetValueInt() + levels
    Float cap = GetMasteryCap()
    If newLevel > cap as Int
        newLevel = cap as Int
    EndIf
    lg.SetValue(newLevel as Float)
    AnnounceMasteryLevelUp(id, newLevel)
    PublishBridgeGlobals()
    If MasteryEnabled()
        UpdateArmorMasteryBonuses()
    EndIf
    UpdateArmorDRFor(PlayerRef)
EndFunction

; ===============================================================
; PHYSICAL DR ABOVE THE ENGINE'S ARMOR CAP — "MASTERY PERKS"
; The DR ladder is the armor masteries' signature perk: it only
; functions with a matching-type chest piece worn AND the player's
; corresponding armor mastery leveled. The reachable ceiling scales
; with mastery:  ceiling = cap + (99 - cap) * masteryFraction
; so 99% requires BOTH ~max armor rating AND full armor mastery.
; Followers use their own worn chest type but the PLAYER's mastery
; (the party ascends together). Engine cap and slope are read live
; from the GMSTs; the armor-side 99% point is the MCM slider.
; Below the kink nothing changes; enemies never get these perks.
; ===============================================================
Function UpdateArmorDRFor(Actor akActor)
    If !akActor || !MRO_DRPerks
        Return
    EndIf
    Int want = -1
    If FeatureEnabled(MRO_F_ArmorCap) && MasteryEnabled() && !NativeDRActive()
        Float mFrac = 0.0
        Int wc = WornChestClassOf(akActor)
        If wc == 0
            mFrac = GetMasteryFraction(ID_LA)
        ElseIf wc == 1
            mFrac = GetMasteryFraction(ID_HA)
        EndIf
        If mFrac > 0.0
            Float capPct  = Game.GetGameSettingFloat("fMaxArmorRating")
            Float scaling = Game.GetGameSettingFloat("fArmorScalingFactor")
            If capPct < 20.0 || capPct > 95.0
                capPct = 75.0
            EndIf
            If scaling <= 0.0
                scaling = 0.1
            EndIf
            Float kink = capPct / scaling
            Float target = 2000.0
            If MRO_T_DR99Armor
                target = MRO_T_DR99Armor.GetValue()
            EndIf
            If target <= kink + 100.0
                target = kink + 100.0
            EndIf
            Float ar = akActor.GetActorValue("DamageResist")
            If ar > kink
                Float ceiling = capPct + (99.0 - capPct) * mFrac
                Float d = capPct + (ar - kink) * (99.0 - capPct) / (target - kink)
                If d > ceiling
                    d = ceiling
                EndIf
                Int di = d as Int
                If di > 99
                    di = 99
                EndIf
                want = di - 76   ; stays -1 while below 76%
            EndIf
        EndIf
    EndIf
    Int i = 0
    While i < 24
        Perk p = MRO_DRPerks.GetAt(i) as Perk
        If p
            If i == want
                If !akActor.HasPerk(p)
                    akActor.AddPerk(p)
                EndIf
            ElseIf akActor.HasPerk(p)
                akActor.RemovePerk(p)
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

; Followers get the same permanent abilities as the player.
; Uses PO3 Papyrus Extender; dismissed followers are cleaned up
; on the next cycle only if the feature is toggled off globally.
Function RefreshFollowerAbilities()
    Actor[] followers = PO3_SKSEFunctions.GetPlayerFollowers()
    Int i = 0
    While i < followers.Length
        Actor f = followers[i]
        If f
            UpdateArmorDRFor(f)
            If FeatureEnabled(MRO_F_Absorb)
                If !f.HasSpell(MRO_AbsorbAbility)
                    f.AddSpell(MRO_AbsorbAbility, false)
                EndIf
            ElseIf f.HasSpell(MRO_AbsorbAbility)
                f.RemoveSpell(MRO_AbsorbAbility)
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

; ===============================================================
; ACTOR ACTION — Weapon swings, spell fire, bow release
; ===============================================================
; PERF: we no longer register action 0 (weapon swing). OnActorAction is a GLOBAL
; SKSE event -- it fires for EVERY actor's action in the load order, and each
; dispatch costs Papyrus VM time even though we bail on non-player. Weapon swings
; are the highest-frequency action in a fight, so watching them list-wide was a
; heavy tax; the equipped-weapon bonus now refreshes on the PLAYER's own hits
; (HandleWeaponHit, player-scoped via the AME) + inventory close. Only action 2
; (spell fire) remains, and it is far rarer than swings.
; Player spell casts, forwarded by the DLL (native TESSpellCastEvent sink,
; player-filtered before any VM dispatch). Replaces the GLOBAL
; RegisterForActorAction(2) listener — the same all-actors VM tax the
; weapon-swing watch had (v0.9.8) — with a per-cast cost of zero for
; everyone but the player. sender = the spell form.
Event OnNativePlayerSpellCast(String eventName, String strArg, Float numArg, Form sender)
    ; Per-school combat gating lives in GrantSpellMasteryXP:
    ; Illusion and Alteration train out of combat (utility schools
    ; cast mostly outside a fight); the rest require combat so
    ; casting at walls trains nothing.
    Spell sp = sender as Spell
    If sp
        GrantSpellMasteryXP(sp)
    EndIf
EndEvent

; ===============================================================
; WEAPON HITS — the damage gate for weapon mastery XP. Called by
; MRO_EventsMGEF (PO3 AME event receiver on the player); fires only
; when the player actually lands a weapon hit. XP only for living,
; hostile actor targets, so furniture, training dummies, followers,
; and air swings never count.
; ===============================================================
Function HandleWeaponHit(ObjectReference akTarget, Form akSource, Projectile akProjectile)
    If !MasteryEnabled()
        Return
    EndIf
    Weapon w = akSource as Weapon
    ; Refresh the equipped-weapon bonus on a weapon-skill change. This replaces
    ; the global OnActorAction(0) swing watch: it is player-scoped (this fires
    ; only for the player's own hits via the AME), so it costs nothing list-wide.
    If w && GetWeaponSkill(w) != _activeWeaponSkill
        UpdateWeaponMasteryBonus()
    EndIf
    ; Weapon XP itself is credited per hit by the REQUIRED MRO.dll; the old
    ; Papyrus per-hit grant fallback was deleted in v0.10.0.
EndFunction

; ===============================================================
; MENU CLOSE — Crafting mastery XP
; ===============================================================
; Every crafting station (forge, alchemy lab, enchanter, cooking, smelter,
; tanning, grindstone) opens the SAME "Crafting Menu"; there is no separate
; "EnchantConstructMenu". So capture WHICH station on open from its workbench
; keyword, and credit only that station's mastery on close. The old code keyed
; Enchanting off a menu that never fires (so Enchanting was unreachable) and
; blindly credited Smithing+Alchemy for every station.
Event OnMenuOpen(String asMenuName)
    If asMenuName == "Crafting Menu"
        _craftSkill = CraftingSkillFromStation()
    EndIf
EndEvent

Event OnMenuClose(String asMenuName)
    If asMenuName == "Crafting Menu"
        If _craftSkill == "SM" && PlayerRef.GetBaseActorValue("Smithing") >= 100.0
            GrantMasteryXP(ID_SM, GetMasteryLevel(ID_SM))
        ElseIf _craftSkill == "AC" && PlayerRef.GetBaseActorValue("Alchemy") >= 100.0
            GrantMasteryXP(ID_AC, GetMasteryLevel(ID_AC))
        ElseIf _craftSkill == "EN" && PlayerRef.GetBaseActorValue("Enchanting") >= 100.0
            GrantMasteryXP(ID_EN, GetMasteryLevel(ID_EN))
        EndIf
        _craftSkill = ""
    ElseIf asMenuName == "BarterMenu"
        If PlayerRef.GetBaseActorValue("Speechcraft") >= 100.0
            GrantMasteryXP(ID_SP, GetMasteryLevel(ID_SP))
        EndIf
    ElseIf asMenuName == "InventoryMenu" || asMenuName == "ContainerMenu"
        ; Chest / weapon swaps happen here; re-sync the equipment-dependent
        ; bonuses now (armor rating by worn chest, damage by equipped weapon)
        ; so they track gear changes without a heartbeat.
        If MasteryEnabled()
            UpdateArmorMasteryBonuses()
            UpdateWeaponMasteryBonus()
        EndIf
    EndIf
EndEvent

; Maps the workbench the player is using to a crafting mastery id. Smelter,
; cooking pot and tanning rack have no mastery -> "". Keyword lookups are by
; editor id (SKSE Keyword.GetKeyword), so no hardcoded FormIDs.
String Function CraftingSkillFromStation()
    ObjectReference furn = PlayerRef.GetFurnitureReference()
    If !furn
        Return ""
    EndIf
    Keyword kForge  = Keyword.GetKeyword("CraftingSmithingForge")
    Keyword kWheel  = Keyword.GetKeyword("CraftingSmithingSharpeningWheel")
    Keyword kArmor  = Keyword.GetKeyword("CraftingSmithingArmorTable")
    If (kForge && furn.HasKeyword(kForge)) || (kWheel && furn.HasKeyword(kWheel)) || (kArmor && furn.HasKeyword(kArmor))
        Return "SM"
    EndIf
    ; Alchemy/enchanting furniture use isAlchemy/isEnchanting (verified against
    ; Skyrim.esm) — there is NO CraftingAlchemy/CraftingEnchanting keyword.
    Keyword kAlch = Keyword.GetKeyword("isAlchemy")
    If kAlch && furn.HasKeyword(kAlch)
        Return "AC"
    EndIf
    Keyword kEnch = Keyword.GetKeyword("isEnchanting")
    If kEnch && furn.HasKeyword(kEnch)
        Return "EN"
    EndIf
    Return ""
EndFunction

; ===============================================================
; MASTERY XP GRANT
; Mastery level n is treated as skill level 100+n, continuing
; vanilla's cost curve (improveMult * L^1.95) past the cap. We use
; L^2 as the in-script approximation of L^1.95 (<6% error).
; ActionsAtZero holds each skill's action count for the 100->101
; step, computed from vanilla Skyrim.esm AVSK records with endgame
; action values (daedric weapons, adept-expert spells, valuable
; crafts) per UESP semantics. By mastery 200 (skill 300) each level
; costs 9x its mastery-0 price, exactly tracking the vanilla curve.
; LoreRim zeroes all use-based skill XP (Static Skill Leveling), so
; this system is the list's only use-trained progression.
; MRO_MasteryBaseGrant scales speed globally (2.0 = twice as fast).
; ===============================================================
Function GrantMasteryXP(String skillId, Int currentMastery)
    Int idx = SkillIndex(skillId)
    If idx < 0
        Return
    EndIf
    Float cap = GetMasteryCap()
    Float n   = currentMastery as Float
    If n >= cap
        Return
    EndIf
    If !_mxp
        _mxp = new Float[14]
    EndIf
    ; The DLL owns the ratio global for weapon/armor skills; seed the local
    ; accumulator from it so a native->Papyrus handoff resumes from true
    ; progress, not a stale local (the ratio global is the source of truth).
    GlobalVariable seedG = MasteryRatioGlobalByIndex(idx)
    If seedG
        _mxp[idx] = seedG.GetValue()
    EndIf
    Float baseGrant = 1.0
    If MRO_MasteryBaseGrant
        baseGrant = MRO_MasteryBaseGrant.GetValue()
    EndIf
    baseGrant *= XPSpeedFor(idx)   ; per-skill multiplier (weapons default 2.5x)
    Float lvl = (100.0 + n) / 100.0
    Float needed = ActionsAtZero(idx) * CurveMult(idx, lvl)
    _mxp[idx] = _mxp[idx] + (baseGrant / needed)
    If _mxp[idx] >= 1.0
        _mxp[idx] = _mxp[idx] - 1.0
        Int newLevel = currentMastery + 1
        GlobalVariable lg = MasteryLevelGlobal(skillId)
        If lg
            lg.SetValue(newLevel as Float)
        EndIf
        AnnounceMasteryLevelUp(skillId, newLevel)
    EndIf
    GlobalVariable rg = MasteryRatioGlobalByIndex(idx)
    If rg
        rg.SetValue(_mxp[idx])
    EndIf
EndFunction

; Like GrantMasteryXP but banks a fractional/multi-"action" amount in one
; call (a heartbeat can carry several fights' worth of damage) and rolls
; through as many mastery levels as the amount funds.
Function GrantMasteryXPAmount(String skillId, Int currentMastery, Float actions)
    Int idx = SkillIndex(skillId)
    If idx < 0 || actions <= 0.0
        Return
    EndIf
    If !_mxp
        _mxp = new Float[14]
    EndIf
    ; See GrantMasteryXP: seed from the ratio global (DLL-owned for weapon/armor)
    ; so a native->Papyrus handoff doesn't resume from a stale local value.
    GlobalVariable seedG = MasteryRatioGlobalByIndex(idx)
    If seedG
        _mxp[idx] = seedG.GetValue()
    EndIf
    Int capInt = GetMasteryCap() as Int
    Float baseGrant = 1.0
    If MRO_MasteryBaseGrant
        baseGrant = MRO_MasteryBaseGrant.GetValue()
    EndIf
    baseGrant *= XPSpeedFor(idx)
    Float remaining = baseGrant * actions   ; in "action" units
    Int n = currentMastery
    While remaining > 0.0 && n < capInt
        Float lvl = (100.0 + (n as Float)) / 100.0
        Float needed = ActionsAtZero(idx) * CurveMult(idx, lvl)
        Float togo = (1.0 - _mxp[idx]) * needed   ; actions left to the next level
        If remaining < togo
            _mxp[idx] = _mxp[idx] + (remaining / needed)
            remaining = 0.0
        Else
            remaining -= togo
            _mxp[idx] = 0.0
            n += 1
            GlobalVariable lg = MasteryLevelGlobal(skillId)
            If lg
                lg.SetValue(n as Float)
            EndIf
            AnnounceMasteryLevelUp(skillId, n)
        EndIf
    EndWhile
    GlobalVariable rg = MasteryRatioGlobalByIndex(idx)
    If rg
        rg.SetValue(_mxp[idx])
    EndIf
EndFunction

; Per-level cost multiplier, applied to ActionsAtZero. Weapons (idx 0-2) and
; magic (idx 5-9) use a STEEP endgame curve so the top mastery levels cost far
; more than the first: 0.30*L^3 + 0.70*L^4, which is 1.0 at L=1 (so the first
; level's cost is unchanged) and 13.34 at L=1.99 (so 199->200 is ~3.4x the L^2
; value). Armor (3-4), crafting (10-12) and Speech (13) stay on the gentler
; L^2. L = (100 + masteryLevel) / 100.
Float Function CurveMult(Int idx, Float lvl)
    ; Weapons (0-2), armor (3-4) and magic (5-9) share the steep endgame curve
    ; (armor joined in v0.9.9). Only crafting (10-12) and Speech (13) stay on L^2.
    If idx <= 9
        Return 0.30 * lvl * lvl * lvl + 0.70 * lvl * lvl * lvl * lvl
    EndIf
    Return lvl * lvl
EndFunction

; Actions for the skill-100 -> 101 step, per skill (SkillIndex order).
; Weapon actions are now NORMALIZED hits (v0.9.1): the DLL banks ~1 per solid
; hit. All three weapon skills share the SAME steep curve L (0.30*L^3+0.70*L^4
; in GrantMasteryXPAmount) but keep per-weapon BASES for fight-parity: 1H lands
; more swings per fight than a bow, so 1H's base is higher. With the 2.5x speed
; default, ActionsAtZero/2.5 = first-level hits: 1H=75, 2H=45, bow=37.5; the same
; curve carries the cap (199->200) to 1H=1000, 2H=600, bow=500. (Bases were cut
; ~20% from the v0.9.2 tuning -> ~20% faster, curve shape unchanged.) Tune
; globally via MRO_T_WeaponXPPerAction.
; Magic (5-9) shares the weapons' steep curve (see CurveMult) but keeps its own
; action unit: 1 action = MRO_T_MagicXPPerCost (150) magicka spent. Armor/
; crafting/speech below stay on L^2. Action units per skill:
;   Destr 1.35*200cost=270 -> 59          Resto 2.0*80=160 -> 99
;   Alter 3.0*200=600 -> 26               Conj  2.1*200=420 -> 38
;   Illus 4.6*150=690 -> 23               Smith 160/item, ~5/session
;   Alch  ~110/potion, ~5/session         Ench  900/item, ~2/session
Float Function ActionsAtZero(Int idx)
    If idx == 0
        Return 187.5    ; OneHanded  (~75 hits at 100->101, ~1000 at 199->200)
    ElseIf idx == 1
        Return 112.5    ; TwoHanded  (~45 hits at 100->101, ~600 at 199->200)
    ElseIf idx == 2
        Return 93.75    ; Marksman   (~37 shots at 100->101, ~500 at 199->200)
    ElseIf idx <= 4
        Return 45.0     ; Light/Heavy Armor: normalized hits TAKEN (native hook);
                        ; ~45 hits survived per first level. Tune via the LA/HA
                        ; per-skill XP-speed sliders. (Fallback path: 30s ticks.)
    ElseIf idx == 5
        Return 60.0     ; Destruction casts
    ElseIf idx == 6
        Return 100.0    ; Restoration casts (cheap heals)
    ElseIf idx == 7
        Return 30.0     ; Alteration casts
    ElseIf idx == 8
        Return 40.0     ; Conjuration casts
    ElseIf idx == 9
        Return 25.0     ; Illusion casts
    ElseIf idx == 10
        Return 4.0      ; Smithing sessions (vanilla's fastest skill)
    ElseIf idx == 11
        Return 23.0     ; Alchemy sessions
    ElseIf idx == 12
        Return 5.0      ; Enchanting sessions
    EndIf
    Return 20.0         ; Speech: barter sessions
EndFunction

Int Function SkillIndex(String skillId)
    If skillId == ID_OH
        Return 0
    ElseIf skillId == ID_TH
        Return 1
    ElseIf skillId == ID_MK
        Return 2
    ElseIf skillId == ID_LA
        Return 3
    ElseIf skillId == ID_HA
        Return 4
    ElseIf skillId == ID_DS
        Return 5
    ElseIf skillId == ID_RS
        Return 6
    ElseIf skillId == ID_AL
        Return 7
    ElseIf skillId == ID_CJ
        Return 8
    ElseIf skillId == ID_IL
        Return 9
    ElseIf skillId == ID_SM
        Return 10
    ElseIf skillId == ID_AC
        Return 11
    ElseIf skillId == ID_EN
        Return 12
    ElseIf skillId == ID_SP
        Return 13
    EndIf
    Return -1
EndFunction

; Effective physical DR% for the player right now, including the perk
; ladder above the engine cap. Used by the MCM live-status readout.
Float Function GetCurrentDRPct()
    Float capPct  = Game.GetGameSettingFloat("fMaxArmorRating")
    Float scaling = Game.GetGameSettingFloat("fArmorScalingFactor")
    If capPct < 20.0 || capPct > 95.0
        capPct = 75.0
    EndIf
    If scaling <= 0.0
        scaling = 0.1
    EndIf
    Float ar = PlayerRef.GetActorValue("DamageResist")
    Float d = ar * scaling
    ; Read the BRIDGE globals — the exact values the native hook uses —
    ; so this readout matches reality (including console overrides).
    Float mFrac = 0.0
    Int wc = WornChestWeightClass()
    If wc == 0
        GlobalVariable la = Game.GetFormFromFile(0x818, "MRO.esp") as GlobalVariable
        If la
            mFrac = la.GetValue() / 100.0
        EndIf
    ElseIf wc == 1
        GlobalVariable ha = Game.GetFormFromFile(0x819, "MRO.esp") as GlobalVariable
        If ha
            mFrac = ha.GetValue() / 100.0
        EndIf
    EndIf
    If d < capPct || !FeatureEnabled(MRO_F_ArmorCap) || !MasteryEnabled() || mFrac <= 0.0
        If d > capPct
            Return capPct
        EndIf
        Return d
    EndIf
    Float kink = capPct / scaling
    Float target = 2000.0
    If MRO_T_DR99Armor
        target = MRO_T_DR99Armor.GetValue()
    EndIf
    If target <= kink + 100.0
        target = kink + 100.0
    EndIf
    d = capPct + (ar - kink) * (99.0 - capPct) / (target - kink)
    Float ceiling = capPct + (99.0 - capPct) * mFrac
    If d > ceiling
        d = ceiling
    EndIf
    If d > 99.0
        Return 99.0
    EndIf
    Return d
EndFunction

; Progress within the current mastery level, 0-100. Reads the RATIO GLOBAL,
; not _mxp: the DLL credits weapon/armor XP natively and writes the globals
; directly, so _mxp goes stale for those skills (MCM showed 69% while the
; real ratio sat at 99% -- "weapon XP not working", 2026-07-09). The globals
; are canonical for every skill: Papyrus-credited ones sync _mxp -> global
; on each grant. _mxp remains only as a fallback for a missing global.
Float Function GetMasteryProgressPct(String skillId)
    Int idx = SkillIndex(skillId)
    If idx < 0
        Return 0.0
    EndIf
    GlobalVariable rg = MasteryRatioGlobalByIndex(idx)
    If rg
        Return rg.GetValue() * 100.0
    EndIf
    If _mxp
        Return _mxp[idx] * 100.0
    EndIf
    Return 0.0
EndFunction

Function GrantSpellMasteryXP(Spell sp)
    MagicEffect eff = sp.GetNthEffectMagicEffect(0)
    If !eff
        Return
    EndIf
    String school = eff.GetAssociatedSkill()
    ; Cost-weighted XP: each cast grants (effective magicka cost / divisor)
    ; actions, so a big expensive spell trains far more than cheap spam and
    ; there is no farming the fastest novice spell. Divisor is tunable via
    ; MRO_T_MagicXPPerCost (default 150 magicka = 1 action; higher = slower).
    ; A fully cost-reduced (free) spell costs 0 -> earns 0, by design.
    Float divisor = 150.0
    GlobalVariable mc = Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable
    If mc && mc.GetValue() > 0.0
        divisor = mc.GetValue()
    EndIf
    Float castXP = (sp.GetEffectiveMagickaCost(PlayerRef) as Float) / divisor
    If castXP <= 0.0
        Return
    EndIf
    Bool inCombat = PlayerRef.IsInCombat()
    ; Illusion and Alteration are utility schools cast mostly outside a
    ; fight — they train anytime. Destruction/Restoration/Conjuration
    ; require combat (no wall-casting to farm XP).
    If school == "Alteration" && PlayerRef.GetBaseActorValue("Alteration") >= 100.0
        GrantMasteryXPAmount(ID_AL, GetMasteryLevel(ID_AL), castXP)
    ElseIf school == "Illusion" && PlayerRef.GetBaseActorValue("Illusion") >= 100.0
        GrantMasteryXPAmount(ID_IL, GetMasteryLevel(ID_IL), castXP)
    ElseIf !inCombat
        Return
    ElseIf school == "Destruction" && PlayerRef.GetBaseActorValue("Destruction") >= 100.0
        GrantMasteryXPAmount(ID_DS, GetMasteryLevel(ID_DS), castXP)
    ElseIf school == "Restoration" && PlayerRef.GetBaseActorValue("Restoration") >= 100.0
        GrantMasteryXPAmount(ID_RS, GetMasteryLevel(ID_RS), castXP)
    ElseIf school == "Conjuration" && PlayerRef.GetBaseActorValue("Conjuration") >= 100.0
        GrantMasteryXPAmount(ID_CJ, GetMasteryLevel(ID_CJ), castXP)
    EndIf
EndFunction

; ===============================================================
; WEAPON TYPE HELPER
; ===============================================================
String Function GetWeaponSkill(Weapon w)
    If w.IsSword() || w.IsDagger() || w.IsWarAxe() || w.IsMace()
        Return "OH"
    ElseIf w.IsGreatsword() || w.IsBattleaxe() || w.IsWarhammer()
        Return "TH"
    ElseIf w.IsBow() || w.HasKeywordString("WeapTypeCrossbow")
        Return "MK"
    EndIf
    Return ""
EndFunction

; ===============================================================
; MASTERY BONUS UPDATES (30s cycle)
; Max: weapon +50% dmg, armor +50 DR, magic +50 skill, craft +25%
; All scale linearly from 0 to max as mastery goes 0 → cap.
; ===============================================================
Function UpdateWeaponMasteryBonus()
    If _bonusWeapon != 0.0
        PlayerRef.ModActorValue("AttackDamageMult", -_bonusWeapon)
        _bonusWeapon = 0.0
        _activeWeaponSkill = ""
    EndIf
    Weapon w = PlayerRef.GetEquippedWeapon()
    If !w
        Return
    EndIf
    Float maxBonus = 0.5
    If MRO_T_WeaponMasteryBonus
        maxBonus = MRO_T_WeaponMasteryBonus.GetValue() / 100.0
    EndIf
    String wSkill = GetWeaponSkill(w)
    Float newBonus = 0.0
    If wSkill == "OH"
        newBonus = GetMasteryFraction(ID_OH) * maxBonus
    ElseIf wSkill == "TH"
        newBonus = GetMasteryFraction(ID_TH) * maxBonus
    ElseIf wSkill == "MK"
        newBonus = GetMasteryFraction(ID_MK) * maxBonus
    Else
        Return
    EndIf
    If newBonus > 0.0
        PlayerRef.ModActorValue("AttackDamageMult", newBonus)
        _bonusWeapon = newBonus
        _activeWeaponSkill = wSkill
    EndIf
EndFunction

; The worn CHEST piece decides which armor mastery applies:
; light chest = Evasion mastery bonus, heavy chest = Heavy Armor
; mastery bonus, no chest (or clothing) = neither.
Function UpdateArmorMasteryBonuses()
    Int wornClass = WornChestWeightClass()
    Float maxBonus = 300.0
    If MRO_T_ArmorMasteryBonus
        maxBonus = MRO_T_ArmorMasteryBonus.GetValue()
    EndIf
    Float newLA = 0.0
    If wornClass == 0
        newLA = GetMasteryFraction(ID_LA) * maxBonus
    EndIf
    Float deltaLA = newLA - _bonusLA
    If deltaLA != 0.0
        PlayerRef.ModActorValue("DamageResist", deltaLA)
        _bonusLA = newLA
    EndIf
    Float newHA = 0.0
    If wornClass == 1
        newHA = GetMasteryFraction(ID_HA) * maxBonus
    EndIf
    Float deltaHA = newHA - _bonusHA
    If deltaHA != 0.0
        PlayerRef.ModActorValue("DamageResist", deltaHA)
        _bonusHA = newHA
    EndIf
EndFunction

; 0 = light, 1 = heavy, -1 = no chest armor worn
Int Function WornChestWeightClass()
    Return WornChestClassOf(PlayerRef)
EndFunction

Int Function WornChestClassOf(Actor akActor)
    Armor chest = akActor.GetWornForm(0x00000004) as Armor
    If !chest
        Return -1
    EndIf
    Int wc = chest.GetWeightClass()
    If wc == 0 || wc == 1
        Return wc
    EndIf
    Return -1
EndFunction

Function UpdateMagicMasteryBonuses()
    Float newDS = GetMasteryFraction(ID_DS) * 50.0
    Float deltaDS = newDS - _bonusDS
    If deltaDS != 0.0
        PlayerRef.ModActorValue("Destruction", deltaDS)
        _bonusDS = newDS
    EndIf
    Float newRS = GetMasteryFraction(ID_RS) * 50.0
    Float deltaRS = newRS - _bonusRS
    If deltaRS != 0.0
        PlayerRef.ModActorValue("Restoration", deltaRS)
        _bonusRS = newRS
    EndIf
    Float newAL = GetMasteryFraction(ID_AL) * 50.0
    Float deltaAL = newAL - _bonusAL
    If deltaAL != 0.0
        PlayerRef.ModActorValue("Alteration", deltaAL)
        _bonusAL = newAL
    EndIf
    Float newCJ = GetMasteryFraction(ID_CJ) * 50.0
    Float deltaCJ = newCJ - _bonusCJ
    If deltaCJ != 0.0
        PlayerRef.ModActorValue("Conjuration", deltaCJ)
        _bonusCJ = newCJ
    EndIf
    Float newIL = GetMasteryFraction(ID_IL) * 50.0
    Float deltaIL = newIL - _bonusIL
    If deltaIL != 0.0
        PlayerRef.ModActorValue("Illusion", deltaIL)
        _bonusIL = newIL
    EndIf
EndFunction

Function UpdateCraftingMasteryBonuses()
    Float newSM = GetMasteryFraction(ID_SM) * 25.0
    Float deltaSM = newSM - _bonusSM
    If deltaSM != 0.0
        PlayerRef.ModActorValue("SmithingMod", deltaSM)
        _bonusSM = newSM
    EndIf
    Float newAC = GetMasteryFraction(ID_AC) * 25.0
    Float deltaAC = newAC - _bonusAC
    If deltaAC != 0.0
        PlayerRef.ModActorValue("AlchemyMod", deltaAC)
        _bonusAC = newAC
    EndIf
    Float newEN = GetMasteryFraction(ID_EN) * 25.0
    Float deltaEN = newEN - _bonusEN
    If deltaEN != 0.0
        PlayerRef.ModActorValue("EnchantingMod", deltaEN)
        _bonusEN = newEN
    EndIf
EndFunction

; Speech mastery: barter price perk ladder (5 rungs; at cap buy 20%
; cheaper, sell 25% higher). Same swap pattern as the DR ladder.
Function UpdateSpeechMasteryBonus()
    If !MRO_SpeechPerks
        Return
    EndIf
    Int want = ((GetMasteryFraction(ID_SP) * 5.0) as Int) - 1
    If GetMasteryFraction(ID_SP) >= 1.0
        want = 4
    EndIf
    If want == _speechRung
        Return
    EndIf
    Int i = 0
    While i < 5
        Perk p = MRO_SpeechPerks.GetAt(i) as Perk
        If p
            If i == want
                If !PlayerRef.HasPerk(p)
                    PlayerRef.AddPerk(p)
                EndIf
            ElseIf PlayerRef.HasPerk(p)
                PlayerRef.RemovePerk(p)
            EndIf
        EndIf
        i += 1
    EndWhile
    _speechRung = want
EndFunction

; Smithing mastery raises the temper caps. The load-order base values
; are captured on first read (before we ever write) and scaled up to
; double at full mastery. GMSTs are global but NPCs don't temper, so
; this is effectively player-only.
Function ApplySmithingMastery()
    If _smithArmorBase <= 0.0
        _smithArmorBase  = Game.GetGameSettingFloat("fSmithingArmorMax")
        _smithWeaponBase = Game.GetGameSettingFloat("fSmithingWeaponMax")
        If _smithArmorBase <= 0.0
            Return
        EndIf
    EndIf
    Float frac = GetMasteryFraction(ID_SM)
    Game.SetGameSettingFloat("fSmithingArmorMax",  _smithArmorBase  * (1.0 + frac))
    Game.SetGameSettingFloat("fSmithingWeaponMax", _smithWeaponBase * (1.0 + frac))
EndFunction

; ===============================================================
; PUBLIC ACCESSORS (used by MCM)
; ===============================================================

; Returns 0-100 representing progress toward configured cap
Float Function GetMasteryBonusPct(String skillId)
    Return GetMasteryFraction(skillId) * 100.0
EndFunction

; Mastery levels live in MRO's own globals (0x850+idx), bound as each
; CSF skill's "level" in the JSONs. CSF only ever READS them: its
; Increment functions are silent no-ops without a level binding AND
; hard-cap at 100, so Papyrus writes the globals directly (found
; 2026-07-05 — before the binding existed, no mastery ever leveled).
GlobalVariable Function MasteryLevelGlobal(String skillId)
    Int idx = SkillIndex(skillId)
    If idx < 0
        Return None
    EndIf
    If !_mLvlG
        _mLvlG = new GlobalVariable[14]
    EndIf
    If !_mLvlG[idx]
        _mLvlG[idx] = Game.GetFormFromFile(0x850 + idx, "MRO.esp") as GlobalVariable
    EndIf
    Return _mLvlG[idx]
EndFunction

; Progress-to-next-level globals (0x860+idx, value 0-1) — read by the
; CSF skill menu for its progress bar.
GlobalVariable Function MasteryRatioGlobalByIndex(Int idx)
    If !_mRatG
        _mRatG = new GlobalVariable[14]
    EndIf
    If !_mRatG[idx]
        _mRatG[idx] = Game.GetFormFromFile(0x860 + idx, "MRO.esp") as GlobalVariable
    EndIf
    Return _mRatG[idx]
EndFunction

; Per-skill XP-speed multiplier (0x870+idx). Defaults: weapons 2.5, rest
; 1.0 (baked into the globals). MCM sliders write these live.
Float Function XPSpeedFor(Int idx)
    If idx < 0
        Return 1.0
    EndIf
    If !_mXpmG
        _mXpmG = new GlobalVariable[14]
    EndIf
    If !_mXpmG[idx]
        _mXpmG[idx] = Game.GetFormFromFile(0x870 + idx, "MRO.esp") as GlobalVariable
    EndIf
    If _mXpmG[idx]
        Float m = _mXpmG[idx].GetValue()
        If m > 0.0
            Return m
        EndIf
    EndIf
    Return 1.0
EndFunction

GlobalVariable Function XPSpeedGlobalByIndex(Int idx)
    XPSpeedFor(idx)   ; ensure cached
    If _mXpmG && idx >= 0 && idx < 14
        Return _mXpmG[idx]
    EndIf
    Return None
EndFunction

Int Function GetMasteryLevel(String skillId)
    GlobalVariable g = MasteryLevelGlobal(skillId)
    If g
        Return g.GetValueInt()
    EndIf
    Return 0
EndFunction

Float Function GetMasteryCap()
    If MRO_MasteryCap
        Float cap = MRO_MasteryCap.GetValue()
        If cap < 50.0
            Return 50.0
        EndIf
        If cap > 200.0
            Return 200.0
        EndIf
        Return cap
    EndIf
    Return 100.0
EndFunction

; Display name for a mastery skill, matching the MCM labels.
String Function MasteryLabel(String skillId)
    If skillId == ID_OH
        Return "One-Handed"
    ElseIf skillId == ID_TH
        Return "Two-Handed"
    ElseIf skillId == ID_MK
        Return "Archery"
    ElseIf skillId == ID_LA
        Return "Evasion"
    ElseIf skillId == ID_HA
        Return "Heavy Armor"
    ElseIf skillId == ID_DS
        Return "Destruction"
    ElseIf skillId == ID_RS
        Return "Restoration"
    ElseIf skillId == ID_AL
        Return "Alteration"
    ElseIf skillId == ID_CJ
        Return "Conjuration"
    ElseIf skillId == ID_IL
        Return "Illusion"
    ElseIf skillId == ID_SM
        Return "Smithing"
    ElseIf skillId == ID_AC
        Return "Alchemy"
    ElseIf skillId == ID_EN
        Return "Enchanting"
    ElseIf skillId == ID_SP
        Return "Speech"
    EndIf
    Return "Mastery"
EndFunction

String Function SkillIdByIndex(Int idx)
    If idx == 0
        Return ID_OH
    ElseIf idx == 1
        Return ID_TH
    ElseIf idx == 2
        Return ID_MK
    ElseIf idx == 3
        Return ID_LA
    ElseIf idx == 4
        Return ID_HA
    ElseIf idx == 5
        Return ID_DS
    ElseIf idx == 6
        Return ID_RS
    ElseIf idx == 7
        Return ID_AL
    ElseIf idx == 8
        Return ID_CJ
    ElseIf idx == 9
        Return ID_IL
    ElseIf idx == 10
        Return ID_SM
    ElseIf idx == 11
        Return ID_AC
    ElseIf idx == 12
        Return ID_EN
    ElseIf idx == 13
        Return ID_SP
    EndIf
    Return ""
EndFunction

; MCM bottom-bar text for a mastery skill row: what it grants right now
; and at the cap. Called on highlight (idx = SkillIndex order 0-13).
String Function GetMasteryHoverTextByIndex(Int idx)
    String skillId = SkillIdByIndex(idx)
    If skillId == ""
        Return ""
    EndIf
    Int lvl = GetMasteryLevel(skillId)
    Int cap = GetMasteryCap() as Int
    Float frac = GetMasteryFraction(skillId)
    String head = MasteryLabel(skillId) + " Mastery " + lvl + "/" + cap + ": "

    If skillId == ID_OH || skillId == ID_TH || skillId == ID_MK
        Float maxB = 50.0
        If MRO_T_WeaponMasteryBonus
            maxB = MRO_T_WeaponMasteryBonus.GetValue()
        EndIf
        Return head + "+" + ((frac * maxB) as Int) + "% attack damage now (at cap +" + (maxB as Int) + "%). Applies while the matching weapon is equipped."
    ElseIf skillId == ID_LA || skillId == ID_HA
        Float maxB = 300.0
        If MRO_T_ArmorMasteryBonus
            maxB = MRO_T_ArmorMasteryBonus.GetValue()
        EndIf
        String chest = "a light chest"
        If skillId == ID_HA
            chest = "a heavy chest"
        EndIf
        Return head + "+" + ((frac * maxB) as Int) + " armor rating now while " + chest + " is worn (at cap +" + (maxB as Int) + "). Feeds the Physical DR curve."
    ElseIf skillId == ID_DS || skillId == ID_RS || skillId == ID_AL || skillId == ID_CJ || skillId == ID_IL
        Return head + "+" + ((frac * 50.0) as Int) + " effective school skill now (at cap +50)."
    ElseIf skillId == ID_SM
        Return head + "+" + ((frac * 25.0) as Int) + "% tempering power and +" + ((frac * 100.0) as Int) + "% temper cap now (at cap +25% / +100%)."
    ElseIf skillId == ID_AC
        Return head + "+" + ((frac * 25.0) as Int) + "% potion strength now (at cap +25%)."
    ElseIf skillId == ID_EN
        Return head + "+" + ((frac * 25.0) as Int) + "% enchantment strength now (at cap +25%)."
    ElseIf skillId == ID_SP
        Int rung = (frac * 5.0) as Int
        If frac >= 1.0
            rung = 5
        EndIf
        Return head + "barter tier " + rung + "/5 now (at cap: buy 20% cheaper, sell 25% higher)."
    EndIf
    Return head
EndFunction

; ONE polished, vanilla-styled skill-up banner: text + chime + animated
; progress bar, rendered by the DLL through the HUD's own ShowNotification
; widget (the exact call the engine makes for real skill-ups). Replaces the
; old CSF text-only HUD message + Debug.Notification double-up and the four
; failed sound attempts. strArg carries the display name; numArg packs
; skillIndex*1000 + newLevel so the DLL can read that skill's progress
; ratio global for the bar.
Function AnnounceMasteryLevelUp(String skillId, Int newLevel)
    Int idx = SkillIndex(skillId)
    If idx < 0
        Return
    EndIf
    SendModEvent("MRO_MasteryBanner", MasteryLabel(skillId) + " Mastery", (idx * 1000 + newLevel) as Float)
EndFunction

; ===============================================================
; INTERNAL HELPERS
; ===============================================================

Float Function GetMasteryFraction(String skillId)
    Float cap = GetMasteryCap()
    Float raw = GetMasteryLevel(skillId) as Float
    If raw >= cap
        Return 1.0
    EndIf
    Return raw / cap
EndFunction

Bool Function FeatureEnabled(GlobalVariable gv)
    If !gv
        Return True
    EndIf
    Return gv.GetValueInt() == 1
EndFunction

Bool Function MasteryEnabled()
    If !MRO_MasteryEnabled
        Return True
    EndIf
    Return MRO_MasteryEnabled.GetValueInt() == 1
EndFunction
