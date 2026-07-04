Scriptname MRO_MCM extends SKI_ConfigBase

Quest           Property MRO_Quest              Auto
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

Event OnOptionSelect(Int a_option)
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If !q
        Return
    EndIf

    If a_option == _oidResistCap
        Bool newVal = !q.FeatureEnabled(MRO_F_ResistCap)
        MRO_F_ResistCap.SetValue(newVal as Float)
        SetToggleOptionValue(_oidResistCap, newVal)
        q.ApplyGMSTFeatures()

    ElseIf a_option == _oidArmorCap
        Bool newVal = !q.FeatureEnabled(MRO_F_ArmorCap)
        MRO_F_ArmorCap.SetValue(newVal as Float)
        SetToggleOptionValue(_oidArmorCap, newVal)
        q.ApplyGMSTFeatures()

    ElseIf a_option == _oidAbsorb
        Bool newVal = !q.FeatureEnabled(MRO_F_Absorb)
        MRO_F_Absorb.SetValue(newVal as Float)
        SetToggleOptionValue(_oidAbsorb, newVal)
        q.RefreshAbilities()

    ElseIf a_option == _oidCarryWeight
        Bool newVal = !q.FeatureEnabled(MRO_F_CarryWeight)
        MRO_F_CarryWeight.SetValue(newVal as Float)
        SetToggleOptionValue(_oidCarryWeight, newVal)
        q.RefreshAbilities()

    ElseIf a_option == _oidArrowRecov
        Bool newVal = !q.FeatureEnabled(MRO_F_ArrowRecovery)
        MRO_F_ArrowRecovery.SetValue(newVal as Float)
        SetToggleOptionValue(_oidArrowRecov, newVal)
        q.ApplyGMSTFeatures()

    ElseIf a_option == _oidCellReset
        Bool newVal = !q.FeatureEnabled(MRO_F_CellReset)
        MRO_F_CellReset.SetValue(newVal as Float)
        SetToggleOptionValue(_oidCellReset, newVal)
        q.ApplyGMSTFeatures()

    ElseIf a_option == _oidMastery
        Bool newVal = !q.FeatureEnabled(MRO_MasteryEnabled)
        MRO_MasteryEnabled.SetValue(newVal as Float)
        SetToggleOptionValue(_oidMastery, newVal)
    EndIf
EndEvent

; ==========================================================
; SLIDER HANDLING
; ==========================================================

Event OnOptionSliderOpen(Int a_option)
    If a_option == _oidMasteryCap
        Float curCap = 100.0
        If MRO_MasteryCap
            curCap = MRO_MasteryCap.GetValue()
        EndIf
        SetSliderDialogStartValue(curCap)
        SetSliderDialogDefaultValue(100.0)
        SetSliderDialogRange(50.0, 200.0)
        SetSliderDialogInterval(10.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int a_option, Float a_value)
    If a_option == _oidMasteryCap
        If MRO_MasteryCap
            MRO_MasteryCap.SetValue(a_value)
        EndIf
        SetSliderOptionValue(_oidMasteryCap, a_value, "{0}")
    EndIf
EndEvent

; ==========================================================
; HIGHLIGHT INFO (bottom bar text)
; ==========================================================

Event OnOptionHighlight(Int a_option)
    If a_option == _oidResistCap
        SetInfoText("Removes the 75% elemental resistance cap. 100% = immunity. Global: highly resistant enemies also gain immunity to their own element.")
    ElseIf a_option == _oidArmorCap
        SetInfoText("Physical DR keeps scaling past 75% for you and followers: 99% at ~2000 armor rating. Curve below 750 armor is unchanged. Armor UI still displays 75.")
    ElseIf a_option == _oidAbsorb
        SetInfoText("Resistance above 100% heals you for that element's damage: 1% per point over 100, full heal at 200%. Covers spells, enchants, drains, poisons.")
    ElseIf a_option == _oidCarryWeight
        SetInfoText("Permanent +150 carry weight for you and your followers.")
    ElseIf a_option == _oidArrowRecov
        SetInfoText("Recover arrows from bodies 66% of the time (vanilla 33%).")
    ElseIf a_option == _oidCellReset
        SetInfoText("Cells respawn after 3 days (7 if cleared) instead of Requiem's 30. Shops restock fast; dungeons repopulate fast too.")
    ElseIf a_option == _oidMastery
        SetInfoText("13 skills that unlock at base skill 100 and grow with use. Armor masteries need a matching chest piece worn.")
    ElseIf a_option == _oidVendorGold
        SetInfoText("All 13 vendor gold pools doubled from your load order's values. Baked into MRO.esp - reinstall to change.")
    ElseIf a_option == _oidMasteryCap
        SetInfoText("Levels each mastery needs for its full bonus (50-200). Higher = longer grind, same maximum. Per-level cost is discipline-specific (swings, casts, combat time, craft sessions) and quadruples by the cap.")
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
    _oidDrain = AddTextOption("Drain Pulses", "~" + (drainPulses as String) + " survivable")
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
    String expStatus = "Not found"
    If MiscUtil.FileExists("data/skse/plugins/Experience.dll")
        expStatus = "Found (XP-based leveling)"
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
    _oidResistCap  = AddToggleOption("Elemental Resist Uncapped", q.FeatureEnabled(MRO_F_ResistCap))
    _oidAbsorb     = AddToggleOption("Elemental Absorb",          q.FeatureEnabled(MRO_F_Absorb))
    _oidArmorCap   = AddToggleOption("Physical DR Past 75%",      q.FeatureEnabled(MRO_F_ArmorCap))
    AddEmptyOption()

    AddHeaderOption("Quality of Life")
    _oidCarryWeight = AddToggleOption("Carry Weight +150",  q.FeatureEnabled(MRO_F_CarryWeight))
    _oidArrowRecov  = AddToggleOption("Arrow Recovery 66%", q.FeatureEnabled(MRO_F_ArrowRecovery))
    _oidCellReset   = AddToggleOption("3-Day Cell Reset",   q.FeatureEnabled(MRO_F_CellReset))
    AddEmptyOption()

    AddHeaderOption("Mastery")
    _oidMastery = AddToggleOption("Skill Mastery System", q.FeatureEnabled(MRO_MasteryEnabled))
    AddEmptyOption()

    AddHeaderOption("Baked Into ESP")
    _oidVendorGold = AddTextOption("Vendor Gold", "Doubled")
EndFunction

; ==========================================================
; READINESS CALCULATIONS
; ==========================================================

String Function AlduinPhase1Status(Int level, Float hp, Float fireRes)
    If MQ206_AlduinsBane && MQ206_AlduinsBane.IsCompleted()
        Return "Completed"
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
        Return "Completed"
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
        Return "Completed"
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
        Return "Completed"
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
