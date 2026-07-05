Scriptname MRO_MCM extends SKI_ConfigBase

Quest           Property MRO_Quest              Auto

; Stamped by release.sh — do not edit by hand
String Property MRO_VERSION = "0.7.2" AutoReadOnly
Quest           Property MQ206_AlduinsBane      Auto
Quest           Property MQ305_Sovngarde        Auto
Quest           Property DLC1VQ08_Harkon        Auto
Quest           Property DLC2MQ06_Miraak        Auto

GlobalVariable  Property MRO_MasteryEnabled     Auto
GlobalVariable  Property MRO_MasteryBaseGrant   Auto
GlobalVariable  Property MRO_MasteryCap         Auto
GlobalVariable  Property MRO_F_ResistCap        Auto
GlobalVariable  Property MRO_F_ArmorCap         Auto
GlobalVariable  Property MRO_F_Absorb           Auto
GlobalVariable  Property MRO_F_CarryWeight      Auto
GlobalVariable  Property MRO_F_ArrowRecovery    Auto
GlobalVariable  Property MRO_F_CellReset        Auto
GlobalVariable  Property MRO_T_AbsorbMax        Auto
GlobalVariable  Property MRO_T_DR99Armor        Auto
GlobalVariable  Property MRO_T_ArmorMasteryBonus  Auto
GlobalVariable  Property MRO_T_WeaponMasteryBonus Auto

; Toggle option IDs
Int _oidResistCap   = -1
Int _oidArmorCap    = -1
Int _oidAbsorb      = -1
Int _oidCarryWeight = -1
Int _oidArrowRecov  = -1
Int _oidCellReset   = -1
Int _oidMastery     = -1
Int _oidVendorGold  = -1

; Slider option IDs
Int _oidMasteryCap  = -1
Int _oidAbsorbMax   = -1
Int _oidDR99Armor   = -1
Int _oidArmorMastB  = -1
Int _oidWeapMastB   = -1
Int _oidXPSpeed     = -1

; Testing buttons
Int _oidTestLA      = -1
Int _oidTestHA      = -1

; Boss readiness rows (for highlight info)
Int _oidDrain       = -1
Int _oidAldP1       = -1
Int _oidAldFinal    = -1
Int _oidHarkon      = -1
Int _oidMiraak      = -1

; ==========================================================
; INIT
; ==========================================================

Event OnConfigInit()
    ModName = "Marth Requiem Overhaul"
    Pages = new String[3]
    Pages[0] = "Boss Readiness"
    Pages[1] = "Mastery"
    Pages[2] = "Features"
EndEvent

Event OnPageReset(String a_page)
    If a_page == "Boss Readiness"
        RenderBossReadiness()
    ElseIf a_page == "Mastery"
        RenderMastery()
    ElseIf a_page == "Features"
        RenderFeatures()
    EndIf
EndEvent

; ==========================================================
; TOGGLE HANDLING
; ==========================================================

; Same null-is-ON semantics as MRO_StartupQuest.FeatureEnabled, but
; local: reading the global directly never touches the quest script.
; Cross-script calls block on the quest's instance lock, and a running
; 30s heartbeat holds it — routing toggle repaints through the quest is
; why checkboxes appeared dead until the menu was closed and reopened.
Bool Function FEnabled(GlobalVariable g)
    Return !g || g.GetValue() != 0.0
EndFunction

Event OnOptionSelect(Int a_option)
    ; Flip the global and repaint FIRST (all local, instant); only then
    ; nudge the quest to apply. Even if that call stalls behind the
    ; heartbeat, the heartbeat itself re-applies everything each cycle.
    If a_option == _oidResistCap
        Bool newVal = !FEnabled(MRO_F_ResistCap)
        MRO_F_ResistCap.SetValue(newVal as Float)
        SetToggleOptionValue(_oidResistCap, newVal)
        NudgeQuest(true, false)

    ElseIf a_option == _oidArmorCap
        Bool newVal = !FEnabled(MRO_F_ArmorCap)
        MRO_F_ArmorCap.SetValue(newVal as Float)
        SetToggleOptionValue(_oidArmorCap, newVal)
        NudgeQuest(true, false)

    ElseIf a_option == _oidAbsorb
        Bool newVal = !FEnabled(MRO_F_Absorb)
        MRO_F_Absorb.SetValue(newVal as Float)
        SetToggleOptionValue(_oidAbsorb, newVal)
        NudgeQuest(false, true)

    ElseIf a_option == _oidCarryWeight
        Bool newVal = !FEnabled(MRO_F_CarryWeight)
        MRO_F_CarryWeight.SetValue(newVal as Float)
        SetToggleOptionValue(_oidCarryWeight, newVal)
        NudgeQuest(false, true)

    ElseIf a_option == _oidArrowRecov
        Bool newVal = !FEnabled(MRO_F_ArrowRecovery)
        MRO_F_ArrowRecovery.SetValue(newVal as Float)
        SetToggleOptionValue(_oidArrowRecov, newVal)
        NudgeQuest(true, false)

    ElseIf a_option == _oidCellReset
        Bool newVal = !FEnabled(MRO_F_CellReset)
        MRO_F_CellReset.SetValue(newVal as Float)
        SetToggleOptionValue(_oidCellReset, newVal)
        NudgeQuest(true, false)

    ElseIf a_option == _oidMastery
        Bool newVal = !FEnabled(MRO_MasteryEnabled)
        MRO_MasteryEnabled.SetValue(newVal as Float)
        SetToggleOptionValue(_oidMastery, newVal)

    ElseIf a_option == _oidTestLA
        TestGrant(false)
    ElseIf a_option == _oidTestHA
        TestGrant(true)
    EndIf
EndEvent

Function NudgeQuest(Bool gmst, Bool abilities)
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If !q
        Return
    EndIf
    If gmst
        q.ApplyGMSTFeatures()
    EndIf
    If abilities
        q.RefreshAbilities()
    EndIf
EndFunction

Function TestGrant(Bool heavy)
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If !q
        Return
    EndIf
    q.TestGrantArmorMastery(heavy, 25)
    ForcePageReset()
EndFunction

; ==========================================================
; SLIDER HANDLING
; ==========================================================

Event OnOptionSliderOpen(Int a_option)
    If a_option == _oidMasteryCap
        SliderSetup(MRO_MasteryCap, 100.0, 50.0, 200.0, 10.0)
    ElseIf a_option == _oidAbsorbMax
        SliderSetup(MRO_T_AbsorbMax, 200.0, 125.0, 400.0, 25.0)
    ElseIf a_option == _oidDR99Armor
        SliderSetup(MRO_T_DR99Armor, 2000.0, 1000.0, 4500.0, 100.0)
    ElseIf a_option == _oidArmorMastB
        SliderSetup(MRO_T_ArmorMasteryBonus, 300.0, 0.0, 600.0, 25.0)
    ElseIf a_option == _oidWeapMastB
        SliderSetup(MRO_T_WeaponMasteryBonus, 50.0, 0.0, 100.0, 5.0)
    ElseIf a_option == _oidXPSpeed
        SliderSetup(MRO_MasteryBaseGrant, 1.0, 0.25, 4.0, 0.25)
    EndIf
EndEvent

Function SliderSetup(GlobalVariable gv, Float def, Float minV, Float maxV, Float step)
    Float cur = def
    If gv
        cur = gv.GetValue()
    EndIf
    SetSliderDialogStartValue(cur)
    SetSliderDialogDefaultValue(def)
    SetSliderDialogRange(minV, maxV)
    SetSliderDialogInterval(step)
EndFunction

Event OnOptionSliderAccept(Int a_option, Float a_value)
    GlobalVariable gv = None
    String fmt = "{0}"
    If a_option == _oidMasteryCap
        gv = MRO_MasteryCap
    ElseIf a_option == _oidAbsorbMax
        gv = MRO_T_AbsorbMax
    ElseIf a_option == _oidDR99Armor
        gv = MRO_T_DR99Armor
    ElseIf a_option == _oidArmorMastB
        gv = MRO_T_ArmorMasteryBonus
    ElseIf a_option == _oidWeapMastB
        gv = MRO_T_WeaponMasteryBonus
    ElseIf a_option == _oidXPSpeed
        gv = MRO_MasteryBaseGrant
        fmt = "{2}"
    EndIf
    If gv
        gv.SetValue(a_value)
        SetSliderOptionValue(a_option, a_value, fmt)
    EndIf
EndEvent

; ==========================================================
; HIGHLIGHT INFO (bottom bar text)
; ==========================================================

Event OnOptionHighlight(Int a_option)
    If a_option == _oidResistCap
        SetInfoText("Removes the 75% elemental resistance cap. 100% = immunity. Global: highly resistant enemies also gain immunity to their own element.")
    ElseIf a_option == _oidArmorCap
        SetInfoText("MASTERY PERK: physical DR past the engine cap requires the matching armor mastery. Your reachable ceiling grows with mastery level (99% only at full mastery AND max armor). Followers share your mastery. Armor UI still displays the engine cap.")
    ElseIf a_option == _oidAbsorb
        SetInfoText("Resistance above 100% heals you for that element's damage: 1% per point over 100, full heal at the Tuning slider value (default 200%). Covers spells, enchants, drains, poisons.")
    ElseIf a_option == _oidCarryWeight
        SetInfoText("Permanent +150 carry weight for you and your followers.")
    ElseIf a_option == _oidArrowRecov
        SetInfoText("Recover arrows from bodies 66% of the time (vanilla 33%).")
    ElseIf a_option == _oidCellReset
        SetInfoText("Cells respawn after 3 days (7 if cleared) instead of Requiem's 30. Shops restock fast; dungeons repopulate fast too.")
    ElseIf a_option == _oidMastery
        SetInfoText("14 skills that unlock at base skill 100 and grow with use. Armor masteries need a matching chest piece worn.")
    ElseIf a_option == _oidVendorGold
        SetInfoText("All 13 vendor gold pools doubled at game load by MRO.dll - adapts to any load order. Merchants pick it up on their next restock.")
    ElseIf a_option == _oidMasteryCap
        SetInfoText("Levels each mastery needs for its full bonus (50-200). Cost follows the vanilla skill curve extended past 100: mastery n prices like skill level 100+n, so level 200 costs 9x level 1. Discipline-specific actions (landed hits, casts, combat time, sessions).")
    ElseIf a_option == _oidAbsorbMax
        SetInfoText("Resistance at which elemental absorb heals 100% of damage. Lower = absorb builds come online faster.")
    ElseIf a_option == _oidDR99Armor
        SetInfoText("Armor rating needed for 99% physical DR (with full armor mastery). Default is auto-calibrated from your load order's best obtainable heavy set at generation time.")
    ElseIf a_option == _oidArmorMastB
        SetInfoText("Armor rating granted by a fully-leveled armor mastery while wearing a matching chest piece.")
    ElseIf a_option == _oidWeapMastB
        SetInfoText("Attack damage bonus (percent) granted by a fully-leveled weapon mastery.")
    ElseIf a_option == _oidXPSpeed
        SetInfoText("Global mastery XP speed multiplier. 2 = levels twice as fast, 0.5 = half speed.")
    ElseIf a_option == _oidTestLA || a_option == _oidTestHA
        SetInfoText("TEST BUTTON: permanently grants 25 REAL mastery levels via Custom Skills Framework (no way to remove them - throwaway saves only). Levels publish to the DR engine immediately; wear a matching chest piece and check Live Status.")
    ElseIf a_option == _oidDrain
        SetInfoText("Alduin's Drain Vitality is UNRESISTABLE and drains ~25 HP per pulse. Raw HP is the only defense - resistances do not help.")
    ElseIf a_option == _oidAldP1
        SetInfoText("Throat of the World. Threats: Fire Breath (fire resist), unresistable Drain Vitality, physical hits with 30% armor penetration. Want HP 400+, fire resist 50%+.")
    ElseIf a_option == _oidAldFinal
        SetInfoText("Sovngarde. Same threats as Phase 1 but harder; dragon priests assist. HP and potion stock matter more than fire resist.")
    ElseIf a_option == _oidHarkon
        SetInfoText("Kindred Judgment. Bring silver or Auriel's Bow; HP 450+ recommended.")
    ElseIf a_option == _oidMiraak
        SetInfoText("Summit of Apocrypha. Long multi-phase fight - HP 500+, Stamina 200+, bring supplies.")
    EndIf
EndEvent

; ==========================================================
; BOSS READINESS PAGE
; ==========================================================

Function RenderBossReadiness()
    Actor player    = Game.GetPlayer()
    Int   level     = player.GetLevel()
    Float hp        = player.GetActorValue("Health")
    Float fireRes   = player.GetActorValue("FireResist")
    Float magRes    = player.GetActorValue("MagicResist")
    Int   drainPulses = (hp / 25.0) as Int

    SetCursorFillMode(TOP_TO_BOTTOM)

    AddHeaderOption("Your Stats")
    AddTextOption("Level",          level as String)
    AddTextOption("Health",         (hp as Int) as String)
    AddTextOption("Fire Resist",    ((fireRes as Int) as String) + "%")
    AddTextOption("Magic Resist",   ((magRes as Int) as String) + "%")
    _oidDrain = AddTextOption("Drain Pulses", "~" + (drainPulses as String) + " Survivable")
    AddEmptyOption()

    AddHeaderOption("Alduin - Throat of the World")
    _oidAldP1 = AddTextOption("Status", AlduinPhase1Status(level, hp, fireRes))
    AddTextOption("Target", "L30-40, HP 400+")
    AddEmptyOption()

    Bool alduinBuffed = IsAlduinBuffed()
    String aldTarget = "L35-45, HP 450+"
    If alduinBuffed
        aldTarget = "L42-52, HP 525+"
    EndIf
    AddHeaderOption("Alduin - Sovngarde")
    _oidAldFinal = AddTextOption("Status", AlduinFinalStatus(level, hp, fireRes, alduinBuffed))
    AddTextOption("Target", aldTarget)
    If alduinBuffed
        AddTextOption("Modifier", "World Eater's Influence")
    EndIf
    AddEmptyOption()

    If DLC1VQ08_Harkon
        AddHeaderOption("Harkon")
        _oidHarkon = AddTextOption("Status", HarkonStatus(level, hp))
        AddTextOption("Target", "L40-50, HP 450+")
        AddEmptyOption()
    EndIf

    If DLC2MQ06_Miraak
        Bool miraakMod = IsMiraakModified()
        String mirTarget = "L45-55, HP 500+"
        If miraakMod
            mirTarget = "L52-62, HP 575+"
        EndIf
        AddHeaderOption("Miraak")
        _oidMiraak = AddTextOption("Status", MiraakStatus(level, hp, miraakMod))
        AddTextOption("Target", mirTarget)
        If miraakMod
            AddTextOption("Modifier", "Immersive Miraak")
        EndIf
        AddEmptyOption()
    EndIf

    AddHeaderOption("Detected Mods")
    String expStatus = "Not Detected"
    If MiscUtil.FileExists("data/skse/plugins/Experience.dll")
        expStatus = "Detected (XP-Based Leveling)"
    EndIf
    AddTextOption("Experience", expStatus)
EndFunction

; ==========================================================
; MASTERY PAGE
; ==========================================================

Function RenderMastery()
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest

    SetCursorFillMode(TOP_TO_BOTTOM)

    AddHeaderOption("Mastery System")
    String masteryStatus = "Enabled"
    If MRO_MasteryEnabled && MRO_MasteryEnabled.GetValueInt() == 0
        masteryStatus = "Disabled"
    EndIf
    AddTextOption("Status", masteryStatus)

    Float curCap = 100.0
    If q
        curCap = q.GetMasteryCap()
    ElseIf MRO_MasteryCap
        curCap = MRO_MasteryCap.GetValue()
    EndIf
    _oidMasteryCap = AddSliderOption("Mastery Cap", curCap, "{0}")
    AddEmptyOption()

    If q
        AddHeaderOption("Combat")
        RenderSkillRow(q, "One-Handed",  q.ID_OH)
        RenderSkillRow(q, "Two-Handed",  q.ID_TH)
        RenderSkillRow(q, "Archery",     q.ID_MK)
        AddEmptyOption()

        AddHeaderOption("Defense")
        RenderSkillRow(q, "Evasion",     q.ID_LA)
        RenderSkillRow(q, "Heavy Armor", q.ID_HA)
        AddEmptyOption()

        AddHeaderOption("Magic")
        RenderSkillRow(q, "Destruction", q.ID_DS)
        RenderSkillRow(q, "Restoration", q.ID_RS)
        RenderSkillRow(q, "Alteration",  q.ID_AL)
        RenderSkillRow(q, "Conjuration", q.ID_CJ)
        RenderSkillRow(q, "Illusion",    q.ID_IL)
        AddEmptyOption()

        AddHeaderOption("Crafting")
        RenderSkillRow(q, "Smithing",    q.ID_SM)
        RenderSkillRow(q, "Alchemy",     q.ID_AC)
        RenderSkillRow(q, "Enchanting",  q.ID_EN)
        AddEmptyOption()

        AddHeaderOption("Commerce")
        RenderSkillRow(q, "Speech",      q.ID_SP)
    EndIf
EndFunction

; One compact row per skill: "level/cap +bonus% (progress% to next)"
Function RenderSkillRow(MRO_StartupQuest q, String label, String skillId)
    Int lvl    = q.GetMasteryLevel(skillId)
    Int capInt = q.GetMasteryCap() as Int
    Int pct    = q.GetMasteryBonusPct(skillId) as Int
    Int prog   = q.GetMasteryProgressPct(skillId) as Int
    String v = (lvl as String) + "/" + (capInt as String) + " +" + (pct as String) + "%"
    If lvl < capInt
        v += " (" + (prog as String) + "%)"
    EndIf
    AddTextOption(label, v)
EndFunction

; ==========================================================
; FEATURES PAGE
; ==========================================================

Function RenderFeatures()
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If !q
        Return
    EndIf

    SetCursorFillMode(TOP_TO_BOTTOM)

    AddHeaderOption("Combat Balance")
    _oidResistCap  = AddToggleOption("Elemental Resist Uncapped", FEnabled(MRO_F_ResistCap))
    _oidAbsorb     = AddToggleOption("Elemental Absorb",          FEnabled(MRO_F_Absorb))
    _oidArmorCap   = AddToggleOption("Physical DR Past 75%",      FEnabled(MRO_F_ArmorCap))
    AddEmptyOption()

    AddHeaderOption("Quality of Life")
    _oidCarryWeight = AddToggleOption("Carry Weight +150",  FEnabled(MRO_F_CarryWeight))
    _oidArrowRecov  = AddToggleOption("Arrow Recovery 66%", FEnabled(MRO_F_ArrowRecovery))
    _oidCellReset   = AddToggleOption("3-Day Cell Reset",   FEnabled(MRO_F_CellReset))
    AddEmptyOption()

    AddHeaderOption("Mastery")
    _oidMastery = AddToggleOption("Skill Mastery System", FEnabled(MRO_MasteryEnabled))
    AddEmptyOption()

    AddHeaderOption("Tuning")
    _oidAbsorbMax  = AddSliderOption("Full Absorb At Resist", SliderVal(MRO_T_AbsorbMax, 200.0), "{0}%")
    _oidDR99Armor  = AddSliderOption("99% DR At Armor",       SliderVal(MRO_T_DR99Armor, 2000.0), "{0}")
    _oidArmorMastB = AddSliderOption("Armor Mastery Bonus",   SliderVal(MRO_T_ArmorMasteryBonus, 300.0), "{0}")
    _oidWeapMastB  = AddSliderOption("Weapon Mastery Bonus",  SliderVal(MRO_T_WeaponMasteryBonus, 50.0), "{0}%")
    _oidXPSpeed    = AddSliderOption("Mastery XP Speed",      SliderVal(MRO_MasteryBaseGrant, 1.0), "{2}")
    AddEmptyOption()

    AddHeaderOption("Live Status")
    Actor player = Game.GetPlayer()
    Float dr = q.GetCurrentDRPct()
    String engine = "Perk Ladder (Papyrus)"
    GlobalVariable ndr = Game.GetFormFromFile(0x81A, "MRO.esp") as GlobalVariable
    If ndr && ndr.GetValueInt() == 1
        engine = "Native (MRO.dll)"
    EndIf
    AddTextOption("DR Engine", engine)
    String chest = "None"
    Float mfrac = 0.0
    GlobalVariable laG = Game.GetFormFromFile(0x818, "MRO.esp") as GlobalVariable
    GlobalVariable haG = Game.GetFormFromFile(0x819, "MRO.esp") as GlobalVariable
    Armor worn = player.GetWornForm(0x00000004) as Armor
    If worn && worn.GetWeightClass() == 0
        chest = "Light"
        If laG
            mfrac = laG.GetValue()
        EndIf
    ElseIf worn && worn.GetWeightClass() == 1
        chest = "Heavy"
        If haG
            mfrac = haG.GetValue()
        EndIf
    EndIf
    AddTextOption("Worn Chest / Mastery", chest + " / " + (mfrac as Int) + "%")
    AddTextOption("Armor Rating", (player.GetActorValue("DamageResist") as Int) as String)
    AddTextOption("Physical DR",  ((dr as Int) as String) + "%")
    String absorbState = "Off"
    If FEnabled(MRO_F_Absorb) && q.MRO_AbsorbAbility && player.HasSpell(q.MRO_AbsorbAbility)
        absorbState = "Active"
    EndIf
    AddTextOption("Absorb Ability", absorbState)
    String cwState = "Off"
    If FEnabled(MRO_F_CarryWeight) && q.MRO_CarryWeightAbility && player.HasSpell(q.MRO_CarryWeightAbility)
        cwState = "Active"
    EndIf
    AddTextOption("Carry Weight Ability", cwState)
    AddTextOption("Fire",   ResistStatus(player, "FireResist"))
    AddTextOption("Frost",  ResistStatus(player, "FrostResist"))
    AddTextOption("Shock",  ResistStatus(player, "ElectricResist"))
    AddTextOption("Magic",  ResistStatus(player, "MagicResist"))
    AddTextOption("Poison", ResistStatus(player, "PoisonResist"))
    AddEmptyOption()

    AddHeaderOption("Baked Into ESP")
    _oidVendorGold = AddTextOption("Vendor Gold", "Doubled")
    AddEmptyOption()

    AddHeaderOption("Testing")
    _oidTestLA = AddTextOption("Grant +25 Evasion Mastery", "[Apply]")
    _oidTestHA = AddTextOption("Grant +25 Heavy Armor Mastery", "[Apply]")
    AddEmptyOption()

    AddHeaderOption("About")
    AddTextOption("Version", MRO_VERSION)
EndFunction

Float Function SliderVal(GlobalVariable gv, Float def)
    If gv
        Return gv.GetValue()
    EndIf
    Return def
EndFunction

; "62%" below absorb range, "150% (absorbs 50%)" above it
String Function ResistStatus(Actor player, String av)
    Int r = player.GetActorValue(av) as Int
    String s = (r as String) + "%"
    If r > 100
        Float fullAt = SliderVal(MRO_T_AbsorbMax, 200.0)
        If fullAt <= 100.0
            fullAt = 200.0
        EndIf
        Float frac = ((r as Float) - 100.0) / (fullAt - 100.0)
        If frac > 1.0
            frac = 1.0
        EndIf
        s += " (absorbs " + ((frac * 100.0) as Int) + "%)"
    EndIf
    Return s
EndFunction

; ==========================================================
; READINESS CALCULATIONS
; ==========================================================

String Function AlduinPhase1Status(Int level, Float hp, Float fireRes)
    If MQ206_AlduinsBane && MQ206_AlduinsBane.IsCompleted()
        Return "COMPLETED"
    EndIf
    If level >= 30 && hp >= 400.0 && fireRes >= 50.0
        Return "READY"
    ElseIf level >= 24 || hp >= 250.0
        Return "CAUTION"
    EndIf
    Return "NOT READY"
EndFunction

String Function AlduinFinalStatus(Int level, Float hp, Float fireRes, Bool alduinBuffed)
    If MQ305_Sovngarde && MQ305_Sovngarde.IsCompleted()
        Return "COMPLETED"
    EndIf
    Int   minLevel = 35
    Float minHP    = 450.0
    If alduinBuffed
        minLevel = 42
        minHP    = 525.0
    EndIf
    If level >= minLevel && hp >= minHP && fireRes >= 50.0
        Return "READY"
    ElseIf level >= (minLevel - 5) || hp >= 300.0
        Return "CAUTION"
    EndIf
    Return "NOT READY"
EndFunction

String Function HarkonStatus(Int level, Float hp)
    If DLC1VQ08_Harkon && DLC1VQ08_Harkon.IsCompleted()
        Return "COMPLETED"
    EndIf
    If level >= 40 && hp >= 450.0
        Return "READY"
    ElseIf level >= 35 || hp >= 300.0
        Return "CAUTION"
    EndIf
    Return "NOT READY"
EndFunction

String Function MiraakStatus(Int level, Float hp, Bool miraakModified)
    If DLC2MQ06_Miraak && DLC2MQ06_Miraak.IsCompleted()
        Return "COMPLETED"
    EndIf
    Int   minLevel = 45
    Float minHP    = 500.0
    If miraakModified
        minLevel = 52
        minHP    = 575.0
    EndIf
    If level >= minLevel && hp >= minHP
        Return "READY"
    ElseIf level >= (minLevel - 7) || hp >= 350.0
        Return "CAUTION"
    EndIf
    Return "NOT READY"
EndFunction

Bool Function IsAlduinBuffed()
    Return Game.IsPluginInstalled("World Eater's Influence.esp")
EndFunction

Bool Function IsMiraakModified()
    Return Game.IsPluginInstalled("ImmersiveMiraakDifficulty.esp")
EndFunction
