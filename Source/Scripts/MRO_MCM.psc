Scriptname MRO_MCM extends SKI_ConfigBase

Quest           Property MRO_Quest              Auto

; Stamped by release.sh — do not edit by hand
String Property MRO_VERSION = "0.12.0" AutoReadOnly

GlobalVariable  Property MRO_MasteryEnabled     Auto
GlobalVariable  Property MRO_MasteryBaseGrant   Auto
GlobalVariable  Property MRO_MasteryCap         Auto
GlobalVariable  Property MRO_F_ResistCap        Auto
GlobalVariable  Property MRO_F_ArmorCap         Auto
GlobalVariable  Property MRO_F_Absorb           Auto
GlobalVariable  Property MRO_T_AbsorbMax        Auto
GlobalVariable  Property MRO_T_DR99Armor        Auto
GlobalVariable  Property MRO_T_ArmorMasteryBonus  Auto
GlobalVariable  Property MRO_T_WeaponMasteryBonus Auto

; Toggle option IDs
Int _oidResistCap   = -1
Int _oidArmorCap    = -1
Int _oidAbsorb      = -1
Int _oidMastery     = -1

; Slider option IDs
Int _oidMasteryCap  = -1
Int _oidAbsorbMax   = -1
Int _oidDR99Armor   = -1
Int _oidArmorMastB  = -1
Int _oidWeapMastB   = -1
Int _oidXPSpeed     = -1
Int _oidMagicXP     = -1

; Group XP-speed slider OIDs: 0=Combat 1=Defense 2=Magic 3=Crafting 4=Commerce.
; One dial per skill family; accepting a value writes every member skill's
; per-skill global, so the ESP and existing saves stay untouched.
Int[] _oidXpg

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

; THE reliable self-heal hook. OnGameReload only runs once (from the base's
; OnInit), so on a save that first registered an OLD MRO it never re-runs and
; the stale Pages array (e.g. the dropped "Boss Readiness" tab) survives. SkyUI
; calls OnConfigOpen on EVERY menu open, immediately before it pushes Pages to
; the UI (setPageNames) -- so re-asserting the tab list here can never be stuck,
; no matter how old the save is.
Function OnConfigOpen()
    SetupPages()
    ; Version in the menu header, re-stamped every open: the one at-a-glance
    ; proof of which script build is live (user couldn't tell v0.9.13 landed
    ; because nothing visible changed, 2026-07-09).
    SetTitleText("marth Resurgence Overhaul  v" + MRO_VERSION)
    ; No heartbeat republishes the mastery fraction the native DR calc reads, so
    ; do it on MCM open: otherwise an out-of-band mastery change (console set, or
    ; the cap slider) won't reach the DR ladder until the next load or level-up.
    ; Safe now that the 30s tick is gone (no quest instance-lock to block on).
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If q
        q.PublishBridgeGlobals()
    EndIf
EndFunction

Function SetupPages()
    ModName = "marth Resurgence Overhaul"
    Pages = new String[3]
    Pages[0] = "Mastery"
    Pages[1] = "Progress"
    Pages[2] = "Features"
EndFunction

Event OnPageReset(String a_page)
    ResetOids()
    If a_page == "Mastery"
        RenderMastery()
    ElseIf a_page == "Progress"
        RenderProgress()
    ElseIf a_page == "Features"
        RenderFeatures()
    EndIf
EndEvent

; SkyUI option IDs restart on every page render, so an oid recorded on one
; page can collide with an option on another. Forget everything before each
; render; only the page being drawn repopulates its own handles.
Function ResetOids()
    _oidResistCap  = -1
    _oidArmorCap   = -1
    _oidAbsorb     = -1
    _oidMastery    = -1
    _oidMasteryCap = -1
    _oidAbsorbMax  = -1
    _oidDR99Armor  = -1
    _oidArmorMastB = -1
    _oidWeapMastB  = -1
    _oidXPSpeed    = -1
    _oidMagicXP    = -1
    _oidXpg   = None
    _oidSkill = None
EndFunction

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
        NudgeQuest(true, true)   ; abilities too: the DR status row follows this toggle

    ElseIf a_option == _oidAbsorb
        Bool newVal = !FEnabled(MRO_F_Absorb)
        MRO_F_Absorb.SetValue(newVal as Float)
        SetToggleOptionValue(_oidAbsorb, newVal)
        NudgeQuest(false, true)

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
    ElseIf a_option == _oidMagicXP
        SliderSetup(Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable, 150.0, 25.0, 500.0, 25.0)
    Else
        Int gi = XpgIndexOf(a_option)
        If gi >= 0
            MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
            Float def = 1.0
            If gi == 0
                def = 2.5   ; weapon skills default faster
            EndIf
            SliderSetup(q.XPSpeedGlobalByIndex(GroupFirstSkill(gi)), def, 0.25, 5.0, 0.25)
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
    ElseIf a_option == _oidMagicXP
        gv = Game.GetFormFromFile(0x846, "MRO.esp") as GlobalVariable
    Else
        Int gi = XpgIndexOf(a_option)
        If gi >= 0
            ; Group slider: write every member skill's per-skill global.
            MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
            Int si = GroupFirstSkill(gi)
            Int last = GroupLastSkill(gi)
            While si <= last
                GlobalVariable mg = q.XPSpeedGlobalByIndex(si)
                If mg
                    mg.SetValue(a_value)
                EndIf
                si += 1
            EndWhile
            SetSliderOptionValue(a_option, a_value, "{2}x")
            Return
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
    ElseIf a_option == _oidMastery
        SetInfoText("14 skills that unlock at base skill 100 and grow with use. Armor masteries need a matching chest piece worn.")
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
    ElseIf a_option == _oidMagicXP
        SetInfoText("Magic mastery pace: magicka spent per XP action (higher = slower). Bigger spells train more; cheap spam trains little. Default 150.")
    ElseIf XpgIndexOf(a_option) >= 0
        SetInfoText("XP-speed multiplier for every mastery in this group. 2.5 = 2.5x faster to the next level. Combat defaults to 2.5 (weapon skills train slower than armor/magic); the rest default to 1.")
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
        AddHeaderOption("XP Speed (per group)")
        _oidXpg = new Int[5]
        RenderXpgSlider(q, "Combat",   0)
        RenderXpgSlider(q, "Defense",  1)
        RenderXpgSlider(q, "Magic",    2)
        RenderXpgSlider(q, "Crafting", 3)
        RenderXpgSlider(q, "Commerce", 4)
    EndIf
EndFunction

; ==========================================================
; PROGRESS PAGE — per-skill mastery levels, read-only
; ==========================================================

Function RenderProgress()
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If !q
        Return
    EndIf

    SetCursorFillMode(TOP_TO_BOTTOM)

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

; SkillIndex range for an XP-speed group (contiguous by construction):
; Combat 0-2, Defense 3-4, Magic 5-9, Crafting 10-12, Commerce 13.
Int Function GroupFirstSkill(Int gi)
    If gi == 0
        Return 0
    ElseIf gi == 1
        Return 3
    ElseIf gi == 2
        Return 5
    ElseIf gi == 3
        Return 10
    EndIf
    Return 13
EndFunction

Int Function GroupLastSkill(Int gi)
    If gi == 0
        Return 2
    ElseIf gi == 1
        Return 4
    ElseIf gi == 2
        Return 9
    ElseIf gi == 3
        Return 12
    EndIf
    Return 13
EndFunction

; Displayed value = the group's first member (members only diverge if an old
; save carries per-skill values from the pre-group MCM; accepting re-unifies).
Function RenderXpgSlider(MRO_StartupQuest q, String label, Int gi)
    Float cur = 1.0
    GlobalVariable g = q.XPSpeedGlobalByIndex(GroupFirstSkill(gi))
    If g
        cur = g.GetValue()
    EndIf
    _oidXpg[gi] = AddSliderOption(label, cur, "{2}x")
EndFunction

; Returns the group index for an XP-speed group slider oid, or -1 if not one.
Int Function XpgIndexOf(Int a_option)
    If !_oidXpg
        Return -1
    EndIf
    Int i = 0
    While i < 5
        If _oidXpg[i] == a_option
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

    AddHeaderOption("Mastery")
    _oidMastery = AddToggleOption("Skill Mastery System", FEnabled(MRO_MasteryEnabled))
    AddEmptyOption()

    AddHeaderOption("Tuning")
    _oidAbsorbMax  = AddSliderOption("Full Absorb At Resist", SliderVal(MRO_T_AbsorbMax, 200.0), "{0}%")
    _oidDR99Armor  = AddSliderOption("99% DR At Armor",       SliderVal(MRO_T_DR99Armor, 2000.0), "{0}")
    _oidArmorMastB = AddSliderOption("Armor Mastery Bonus",   SliderVal(MRO_T_ArmorMasteryBonus, 300.0), "{0}")
    _oidWeapMastB  = AddSliderOption("Weapon Mastery Bonus",  SliderVal(MRO_T_WeaponMasteryBonus, 50.0), "{0}%")
    _oidXPSpeed    = AddSliderOption("Mastery XP Speed",      SliderVal(MRO_MasteryBaseGrant, 1.0), "{2}")
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
    ; The DLL publishes the ladder's TRUE inputs on every journal open:
    ; earned AR (cast-spell AR like wards itemized out) and the effective DR
    ; the native path actually applies. The old Papyrus re-derivation read
    ; FULL AR, so a ward looked like it added past-cap DR when it didn't.
    Float arShow = player.GetActorValue("DamageResist")
    GlobalVariable effAR = Game.GetFormFromFile(0x849, "MRO.esp") as GlobalVariable
    GlobalVariable effDR = Game.GetFormFromFile(0x84A, "MRO.esp") as GlobalVariable
    If effAR && effAR.GetValue() > 0.0
        arShow = effAR.GetValue()
    EndIf
    If effDR && effDR.GetValue() > 0.0
        dr = effDR.GetValue()
    EndIf
    AddTextOption("Armor Rating (earned)", (arShow as Int) as String)
    AddTextOption("Physical DR",  ((dr as Int) as String) + "%")
    String absorbState = "Off"
    If FEnabled(MRO_F_Absorb) && q.MRO_AbsorbAbility && player.HasSpell(q.MRO_AbsorbAbility)
        absorbState = "Active"
    EndIf
    AddTextOption("Absorb Ability", absorbState)
    AddTextOption("Fire",   ResistStatus(player, "FireResist"))
    AddTextOption("Frost",  ResistStatus(player, "FrostResist"))
    AddTextOption("Shock",  ResistStatus(player, "ElectricResist"))
    AddTextOption("Magic",  ResistStatus(player, "MagicResist"))
    AddTextOption("Poison", ResistStatus(player, "PoisonResist"))
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
