Scriptname MRO_MCM extends SKI_ConfigBase

Quest           Property MRO_Quest              Auto

; Stamped by release.sh — do not edit by hand
String Property MRO_VERSION = "0.9.6" AutoReadOnly

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
Int _oidWeapXP      = -1
Int _oidMagicXP     = -1

; Per-skill XP-speed slider OIDs, index = SkillIndex order (0-13)
Int[] _oidXpm

; Mastery skill-row OIDs, index = SkillIndex order (0-13). Highlight shows
; that skill's current bonus in the bottom bar.
Int[] _oidSkill

; ==========================================================
; INIT
; ==========================================================

Event OnConfigInit()
    SetupPages()
EndEvent

; SkyUI caches ModName/Pages in the SAVE. The documented refresh path is to
; bump GetVersion so CheckVersion() fires OnVersionUpdate on the next load --
; but that path proved unreliable in the field: once a save has recorded a
; given version, or if the delta fires but the flash tab cache never rebuilds,
; stale tabs (e.g. the long-gone "Boss Readiness" page) persist forever and
; `setstage SKI_ConfigManagerInstance 1` does NOT clear them.
;
; Nuclear fix: don't trust the version delta at all. OnGameReload below
; re-asserts ModName + Pages and forces a page reset on EVERY load, so the
; config can never be stuck on old identity regardless of stored version.
; GetVersion is still bumped as belt-and-suspenders for the first-install path.
Int Function GetVersion()
    Return 3
EndFunction

Event OnVersionUpdate(Int a_version)
    SetupPages()
EndEvent

; Runs on every game load (base calls CheckVersion here; we add an
; unconditional self-heal on top). Setting Pages here means the next time the
; MCM opens, SkyUI's setPageNames pushes the current tab list and any stale
; page vanishes; setting ModName refreshes the title on the next page draw.
Function OnGameReload()
    parent.OnGameReload()
    SetupPages()
    ForcePageReset()
EndFunction

Function SetupPages()
    ModName = "marth Requiem Overhaul"
    Pages = new String[2]
    Pages[0] = "Mastery"
    Pages[1] = "Features"
EndFunction

Event OnPageReset(String a_page)
    If a_page == "Mastery"
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
    ElseIf a_option == _oidWeapXP
        SliderSetup(Game.GetFormFromFile(0x808, "MRO.esp") as GlobalVariable, 1.0, 0.25, 5.0, 0.25)
    ElseIf a_option == _oidMagicXP
        SliderSetup(Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable, 150.0, 25.0, 500.0, 25.0)
    Else
        Int xi = XpmIndexOf(a_option)
        If xi >= 0
            MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
            Float def = 1.0
            If xi < 3
                def = 2.5   ; weapon skills default faster
            EndIf
            SliderSetup(q.XPSpeedGlobalByIndex(xi), def, 0.25, 5.0, 0.25)
        EndIf
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
    ElseIf a_option == _oidWeapXP
        gv = Game.GetFormFromFile(0x808, "MRO.esp") as GlobalVariable
        fmt = "{2}"
    ElseIf a_option == _oidMagicXP
        gv = Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable
    Else
        Int xi = XpmIndexOf(a_option)
        If xi >= 0
            MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
            gv = q.XPSpeedGlobalByIndex(xi)
            fmt = "{2}x"
        EndIf
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
        SetInfoText("OFF by default. Speeds cell respawn (3/7 days) to restock shops and repopulate dungeons -- but respawn is all-or-nothing: it also returns display/quest items to cells and can revert one-time activators (e.g. Blackreach lifts). Leave off unless you accept that.")
    ElseIf a_option == _oidMastery
        SetInfoText("14 skills that unlock at base skill 100 and grow with use. Armor masteries need a matching chest piece worn.")
    ElseIf a_option == _oidVendorGold
        SetInfoText("All 13 vendor gold pools doubled at game load by MRO.dll - adapts to any load order. Merchants pick it up on their next restock.")
    ElseIf a_option == _oidMasteryCap
        SetInfoText("Levels each mastery needs for its full bonus (50-200). Cost rises steeply with level; weapons and magic use an extra-steep endgame curve, so the final levels cost many times the first. Each skill trains on its own action: weapon damage dealt, magicka spent, combat time, or craft/barter sessions.")
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
    ElseIf a_option == _oidWeapXP
        SetInfoText("Weapon mastery pace: hits per XP action (higher = slower). Applies to all weapon skills and scales the whole weapon curve. Default 1.0.")
    ElseIf a_option == _oidMagicXP
        SetInfoText("Magic mastery pace: magicka spent per XP action (higher = slower). Bigger spells train more; cheap spam trains little. Default 150.")
    ElseIf XpmIndexOf(a_option) >= 0
        SetInfoText("XP-speed multiplier for THIS mastery only. 2.5 = 2.5x faster to the next level. Weapon skills default to 2.5 (they train slower than armor/magic); everything else defaults to 1.")
    ElseIf MasteryOidIndex(a_option) >= 0
        MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
        If q
            SetInfoText(q.GetMasteryHoverTextByIndex(MasteryOidIndex(a_option)))
        EndIf
    EndIf
EndEvent

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
        _oidSkill = new Int[14]
        AddHeaderOption("Combat")
        RenderSkillRow(q, "One-Handed",  q.ID_OH, 0)
        RenderSkillRow(q, "Two-Handed",  q.ID_TH, 1)
        RenderSkillRow(q, "Archery",     q.ID_MK, 2)
        AddEmptyOption()

        AddHeaderOption("Defense")
        RenderSkillRow(q, "Evasion",     q.ID_LA, 3)
        RenderSkillRow(q, "Heavy Armor", q.ID_HA, 4)
        AddEmptyOption()

        AddHeaderOption("Magic")
        RenderSkillRow(q, "Destruction", q.ID_DS, 5)
        RenderSkillRow(q, "Restoration", q.ID_RS, 6)
        RenderSkillRow(q, "Alteration",  q.ID_AL, 7)
        RenderSkillRow(q, "Conjuration", q.ID_CJ, 8)
        RenderSkillRow(q, "Illusion",    q.ID_IL, 9)
        AddEmptyOption()

        AddHeaderOption("Crafting")
        RenderSkillRow(q, "Smithing",    q.ID_SM, 10)
        RenderSkillRow(q, "Alchemy",     q.ID_AC, 11)
        RenderSkillRow(q, "Enchanting",  q.ID_EN, 12)
        AddEmptyOption()

        AddHeaderOption("Commerce")
        RenderSkillRow(q, "Speech",      q.ID_SP, 13)
        AddEmptyOption()

        AddHeaderOption("XP Speed (per skill)")
        _oidXpm = new Int[14]
        RenderXpmSlider(q, "One-Handed",  0)
        RenderXpmSlider(q, "Two-Handed",  1)
        RenderXpmSlider(q, "Archery",     2)
        RenderXpmSlider(q, "Evasion",     3)
        RenderXpmSlider(q, "Heavy Armor", 4)
        RenderXpmSlider(q, "Destruction", 5)
        RenderXpmSlider(q, "Restoration", 6)
        RenderXpmSlider(q, "Alteration",  7)
        RenderXpmSlider(q, "Conjuration", 8)
        RenderXpmSlider(q, "Illusion",    9)
        RenderXpmSlider(q, "Smithing",    10)
        RenderXpmSlider(q, "Alchemy",     11)
        RenderXpmSlider(q, "Enchanting",  12)
        RenderXpmSlider(q, "Speech",      13)
    EndIf
EndFunction

; One compact row per skill: "level/cap +bonus% (progress% to next)".
; Highlighting the row shows its live bonus in the bottom bar.
Function RenderSkillRow(MRO_StartupQuest q, String label, String skillId, Int idx)
    Int lvl    = q.GetMasteryLevel(skillId)
    Int capInt = q.GetMasteryCap() as Int
    Int prog   = q.GetMasteryProgressPct(skillId) as Int
    ; Row shows level/cap and progress-to-next only. The old "+N%" was just
    ; level-as-percent-of-cap (redundant with lvl/cap) and misread as the
    ; gameplay bonus; the real, unit-correct bonus lives in the hover text.
    String v = (lvl as String) + "/" + (capInt as String)
    If lvl < capInt
        v += " (" + (prog as String) + "%)"
    EndIf
    _oidSkill[idx] = AddTextOption(label, v)
EndFunction

; Returns the SkillIndex for a mastery skill-row oid, or -1 if not one.
Int Function MasteryOidIndex(Int a_option)
    If !_oidSkill
        Return -1
    EndIf
    Int i = 0
    While i < 14
        If _oidSkill[i] == a_option
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Function RenderXpmSlider(MRO_StartupQuest q, String label, Int idx)
    Float cur = 1.0
    GlobalVariable g = q.XPSpeedGlobalByIndex(idx)
    If g
        cur = g.GetValue()
    EndIf
    _oidXpm[idx] = AddSliderOption(label, cur, "{2}x")
EndFunction

; Returns the SkillIndex for an XP-speed slider oid, or -1 if not one.
Int Function XpmIndexOf(Int a_option)
    If !_oidXpm
        Return -1
    EndIf
    Int i = 0
    While i < 14
        If _oidXpm[i] == a_option
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
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
    _oidCellReset   = AddToggleOption("Faster Cell Reset",  FEnabled(MRO_F_CellReset))
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
    _oidWeapXP     = AddSliderOption("Weapon XP Pace", SliderVal(Game.GetFormFromFile(0x808, "MRO.esp") as GlobalVariable, 1.0), "{2}")
    _oidMagicXP    = AddSliderOption("Magic XP Pace",  SliderVal(Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable, 150.0), "{0}")
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
