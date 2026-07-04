Scriptname MRO_StartupQuest extends Quest

; ===============================================================
; PROPERTIES — Core abilities (set by xEdit script)
; ===============================================================
Spell    Property MRO_AbsorbAbility      Auto
Spell    Property MRO_CarryWeightAbility Auto
Actor    Property PlayerRef              Auto
FormList Property MRO_DRPerks            Auto  ; 24 perks, index 0 = 76% DR ... 23 = 99% DR

; ===============================================================
; PROPERTIES — Feature flags (GlobalVariables set by xEdit)
; Null GlobalVariable = feature defaults to ON.
; ===============================================================
GlobalVariable Property MRO_F_ResistCap     Auto
GlobalVariable Property MRO_F_ArmorCap      Auto
GlobalVariable Property MRO_F_Absorb        Auto
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

; Per-skill XP accumulators (fraction of the current level, 0-1).
; We own the XP curve explicitly (CSF's AdvanceSkill curve is opaque and
; only exposes integer levels) so the MCM can show granular progress.
Float[] _mxp

; ===============================================================
; STARTUP
; ===============================================================
Event OnInit()
    ApplyGMSTFeatures()
    GiveAbilitiesTo(PlayerRef)

    If MasteryEnabled()
        RegisterForActorAction(0)
        RegisterForActorAction(2)
        RegisterForActorAction(6)
        RegisterForMenu("Crafting Menu")
        RegisterForMenu("EnchantConstructMenu")
    EndIf

    If !MRO_SetupDone || MRO_SetupDone.GetValueInt() == 0
        RegisterForSingleUpdate(20.0)
    Else
        RegisterForSingleUpdate(5.0)
    EndIf
EndEvent

; ===============================================================
; UPDATE CYCLE
; ===============================================================
Event OnUpdate()
    ApplyGMSTFeatures()
    RefreshFollowerAbilities()

    If MRO_SetupDone && MRO_SetupDone.GetValueInt() == 0 && !_introShown
        ; Latch BEFORE showing so no re-entry or stale instance can queue
        ; the intro more than once.
        _introShown = true
        MRO_SetupDone.SetValue(1)
        RunFirstTimeSetup()
        RegisterForSingleUpdate(30.0)
        Return
    EndIf

    If MasteryEnabled()
        UpdateWeaponMasteryBonus()
        UpdateArmorMasteryBonuses()
        UpdateMagicMasteryBonuses()
        UpdateCraftingMasteryBonuses()
        If PlayerRef.IsInCombat()
            GrantCombatArmorXP()
        EndIf
    EndIf

    RegisterForSingleUpdate(30.0)
EndEvent

; ===============================================================
; FIRST-RUN INTRO
; ===============================================================
Function RunFirstTimeSetup()
    Debug.MessageBox("Marth Requiem Overhaul is active.\n\nThis mod rebalances Requiem's late-game power scaling:\n\n- Elemental resist above 100% absorbs spell damage as health\n  (101% = 1% absorbed, 200% = 100% absorbed)\n- Physical DR past 75% now scales, reaching 99% at ~2000 armor\n- Vendor gold doubled\n- 13-skill Mastery system unlocks after each base skill reaches 100\n\nAll features can be toggled in the MRO MCM under Features.\nMastery cap (default 100, up to 200) is adjustable under Mastery.")
EndFunction

; ===============================================================
; GMST FEATURE APPLICATION
; ===============================================================
Function ApplyGMSTFeatures()
    If FeatureEnabled(MRO_F_ResistCap)
        Game.SetGameSettingFloat("fPlayerMaxResistance", 10000.0)
    EndIf

    UpdateArmorDRFor(PlayerRef)

    If FeatureEnabled(MRO_F_ArrowRecovery)
        Game.SetGameSettingInt("iArrowInventoryChance", 66)
    EndIf

    If FeatureEnabled(MRO_F_CellReset)
        Game.SetGameSettingInt("iHoursToRespawnCell",        72)
        Game.SetGameSettingInt("iHoursToRespawnCellCleared", 168)
    EndIf
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
    If FeatureEnabled(MRO_F_CarryWeight)
        If !akActor.HasSpell(MRO_CarryWeightAbility)
            akActor.AddSpell(MRO_CarryWeightAbility, false)
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
    If FeatureEnabled(MRO_F_CarryWeight)
        If !PlayerRef.HasSpell(MRO_CarryWeightAbility)
            PlayerRef.AddSpell(MRO_CarryWeightAbility, false)
        EndIf
    Else
        If PlayerRef.HasSpell(MRO_CarryWeightAbility)
            PlayerRef.RemoveSpell(MRO_CarryWeightAbility)
        EndIf
    EndIf
EndFunction

; ===============================================================
; PHYSICAL DR ABOVE THE ENGINE'S 75% ARMOR CAP
; The engine caps armor DR at 75% (750 armor at Requiem's 0.10/pt).
; Above that, a hidden Mod Incoming Damage perk supplies the rest:
;   DR% = 75 + (armor - 750) * 0.0192, capped at 99% (~2000 armor)
; Below 750 armor nothing changes; enemies never get these perks.
; ===============================================================
Function UpdateArmorDRFor(Actor akActor)
    If !akActor || !MRO_DRPerks
        Return
    EndIf
    Int want = -1
    If FeatureEnabled(MRO_F_ArmorCap)
        Float ar = akActor.GetActorValue("DamageResist")
        If ar > 750.0
            Int d = (75.0 + (ar - 750.0) * 0.0192) as Int
            If d > 99
                d = 99
            EndIf
            want = d - 76   ; stays -1 while below 76%
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
            If FeatureEnabled(MRO_F_CarryWeight)
                If !f.HasSpell(MRO_CarryWeightAbility)
                    f.AddSpell(MRO_CarryWeightAbility, false)
                EndIf
            ElseIf f.HasSpell(MRO_CarryWeightAbility)
                f.RemoveSpell(MRO_CarryWeightAbility)
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

; ===============================================================
; ACTOR ACTION — Weapon swings, spell fire, bow release
; ===============================================================
Event OnActorAction(Int actionType, Actor akActor, Form akSource, Int slot)
    If akActor != PlayerRef
        Return
    EndIf
    If actionType == 0
        Weapon w = akSource as Weapon
        If !w
            Return
        EndIf
        String wSkill = GetWeaponSkill(w)
        If wSkill == "OH" && PlayerRef.GetBaseActorValue("OneHanded") >= 100.0
            GrantMasteryXP(ID_OH, CustomSkills.GetSkillLevel(ID_OH))
        ElseIf wSkill == "TH" && PlayerRef.GetBaseActorValue("TwoHanded") >= 100.0
            GrantMasteryXP(ID_TH, CustomSkills.GetSkillLevel(ID_TH))
        EndIf
        If wSkill != _activeWeaponSkill
            UpdateWeaponMasteryBonus()
        EndIf
        Return
    EndIf
    If actionType == 2
        Spell sp = akSource as Spell
        If sp
            GrantSpellMasteryXP(sp)
        EndIf
        Return
    EndIf
    If actionType == 6
        If PlayerRef.GetBaseActorValue("Marksman") >= 100.0
            GrantMasteryXP(ID_MK, CustomSkills.GetSkillLevel(ID_MK))
        EndIf
    EndIf
EndEvent

; ===============================================================
; MENU CLOSE — Crafting mastery XP
; ===============================================================
Event OnMenuClose(String asMenuName)
    If asMenuName == "Crafting Menu"
        If PlayerRef.GetBaseActorValue("Smithing") >= 100.0
            GrantMasteryXP(ID_SM, CustomSkills.GetSkillLevel(ID_SM))
        EndIf
        If PlayerRef.GetBaseActorValue("Alchemy") >= 100.0
            GrantMasteryXP(ID_AC, CustomSkills.GetSkillLevel(ID_AC))
        EndIf
    ElseIf asMenuName == "EnchantConstructMenu"
        If PlayerRef.GetBaseActorValue("Enchanting") >= 100.0
            GrantMasteryXP(ID_EN, CustomSkills.GetSkillLevel(ID_EN))
        EndIf
    EndIf
EndEvent

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
        _mxp = new Float[13]
    EndIf
    Float baseGrant = 1.0
    If MRO_MasteryBaseGrant
        baseGrant = MRO_MasteryBaseGrant.GetValue()
    EndIf
    Float lvl = (100.0 + n) / 100.0
    Float needed = ActionsAtZero(idx) * lvl * lvl
    _mxp[idx] = _mxp[idx] + (baseGrant / needed)
    If _mxp[idx] >= 1.0
        _mxp[idx] = _mxp[idx] - 1.0
        CustomSkills.IncrementSkill(skillId)
        CustomSkills.ShowSkillIncreaseMessage(skillId, currentMastery + 1)
    EndIf
EndFunction

; Actions for the skill-100 -> 101 step, per skill (SkillIndex order).
; Derived from vanilla AVSK (improveMult * 100^1.95 / XP-per-action):
;   OneHanded  6.3*14dmg=88/act -> 181    TwoHanded 5.95*24=143 -> 111
;   Marksman   9.3*19=177 -> 90           armor ~115/hit, ~3 hits/tick
;   Destr 1.35*200cost=270 -> 59          Resto 2.0*80=160 -> 99
;   Alter 3.0*200=600 -> 26               Conj  2.1*200=420 -> 38
;   Illus 4.6*150=690 -> 23               Smith 160/item, ~5/session
;   Alch  ~110/potion, ~5/session         Ench  900/item, ~2/session
Float Function ActionsAtZero(Int idx)
    If idx == 0
        Return 180.0    ; OneHanded swings
    ElseIf idx == 1
        Return 110.0    ; TwoHanded swings
    ElseIf idx == 2
        Return 90.0     ; Marksman shots
    ElseIf idx <= 4
        Return 45.0     ; Light/Heavy Armor 30s combat ticks
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
    EndIf
    Return 5.0          ; Enchanting sessions
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
    EndIf
    Return -1
EndFunction

; Progress within the current mastery level, 0-100.
Float Function GetMasteryProgressPct(String skillId)
    Int idx = SkillIndex(skillId)
    If idx < 0 || !_mxp
        Return 0.0
    EndIf
    Return _mxp[idx] * 100.0
EndFunction

Function GrantSpellMasteryXP(Spell sp)
    MagicEffect eff = sp.GetNthEffectMagicEffect(0)
    If !eff
        Return
    EndIf
    String school = eff.GetAssociatedSkill()
    If school == "Destruction" && PlayerRef.GetBaseActorValue("Destruction") >= 100.0
        GrantMasteryXP(ID_DS, CustomSkills.GetSkillLevel(ID_DS))
    ElseIf school == "Restoration" && PlayerRef.GetBaseActorValue("Restoration") >= 100.0
        GrantMasteryXP(ID_RS, CustomSkills.GetSkillLevel(ID_RS))
    ElseIf school == "Alteration" && PlayerRef.GetBaseActorValue("Alteration") >= 100.0
        GrantMasteryXP(ID_AL, CustomSkills.GetSkillLevel(ID_AL))
    ElseIf school == "Conjuration" && PlayerRef.GetBaseActorValue("Conjuration") >= 100.0
        GrantMasteryXP(ID_CJ, CustomSkills.GetSkillLevel(ID_CJ))
    ElseIf school == "Illusion" && PlayerRef.GetBaseActorValue("Illusion") >= 100.0
        GrantMasteryXP(ID_IL, CustomSkills.GetSkillLevel(ID_IL))
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
    String wSkill = GetWeaponSkill(w)
    Float newBonus = 0.0
    If wSkill == "OH"
        newBonus = GetMasteryFraction(ID_OH) * 0.5
    ElseIf wSkill == "TH"
        newBonus = GetMasteryFraction(ID_TH) * 0.5
    ElseIf wSkill == "MK"
        newBonus = GetMasteryFraction(ID_MK) * 0.5
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
    Float newLA = 0.0
    If wornClass == 0
        newLA = GetMasteryFraction(ID_LA) * 300.0
    EndIf
    Float deltaLA = newLA - _bonusLA
    If deltaLA != 0.0
        PlayerRef.ModActorValue("DamageResist", deltaLA)
        _bonusLA = newLA
    EndIf
    Float newHA = 0.0
    If wornClass == 1
        newHA = GetMasteryFraction(ID_HA) * 300.0
    EndIf
    Float deltaHA = newHA - _bonusHA
    If deltaHA != 0.0
        PlayerRef.ModActorValue("DamageResist", deltaHA)
        _bonusHA = newHA
    EndIf
EndFunction

; 0 = light, 1 = heavy, -1 = no chest armor worn
Int Function WornChestWeightClass()
    Armor chest = PlayerRef.GetWornForm(0x00000004) as Armor
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

Function GrantCombatArmorXP()
    Int wornClass = WornChestWeightClass()
    If wornClass == 0 && PlayerRef.GetBaseActorValue("LightArmor") >= 100.0
        GrantMasteryXP(ID_LA, CustomSkills.GetSkillLevel(ID_LA))
    ElseIf wornClass == 1 && PlayerRef.GetBaseActorValue("HeavyArmor") >= 100.0
        GrantMasteryXP(ID_HA, CustomSkills.GetSkillLevel(ID_HA))
    EndIf
EndFunction

; ===============================================================
; PUBLIC ACCESSORS (used by MCM)
; ===============================================================

; Returns 0-100 representing progress toward configured cap
Float Function GetMasteryBonusPct(String skillId)
    Return GetMasteryFraction(skillId) * 100.0
EndFunction

Int Function GetMasteryLevel(String skillId)
    Return CustomSkills.GetSkillLevel(skillId)
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

; ===============================================================
; INTERNAL HELPERS
; ===============================================================

Float Function GetMasteryFraction(String skillId)
    Float cap = GetMasteryCap()
    Float raw = CustomSkills.GetSkillLevel(skillId) as Float
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
