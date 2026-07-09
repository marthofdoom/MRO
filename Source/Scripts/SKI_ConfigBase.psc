; Minimal compilation stub for SKI_ConfigBase.
; At runtime this class is provided by SkyUI's BSA.
; Only declares the subset of the API used by MRO_MCM.psc.
Scriptname SKI_ConfigBase extends SKI_QuestBase Hidden

String[] Property Pages Auto
String Property ModName Auto

Int Property OPTION_FLAG_NONE
    Int Function Get()
        Return 0
    EndFunction
EndProperty

Int Property OPTION_FLAG_DISABLED
    Int Function Get()
        Return 1
    EndFunction
EndProperty

Int Property TOP_TO_BOTTOM
    Int Function Get()
        Return 2
    EndFunction
EndProperty

Int Property LEFT_TO_RIGHT
    Int Function Get()
        Return 1
    EndFunction
EndProperty

Event OnConfigInit()
EndEvent

Event OnPageReset(String a_page)
EndEvent

Event OnOptionSelect(Int a_option)
EndEvent

Event OnOptionSliderOpen(Int a_option)
EndEvent

Event OnOptionSliderAccept(Int a_option, Float a_value)
EndEvent

Event OnOptionHighlight(Int a_option)
EndEvent

; Non-native in the real base: does version check + config-manager registration.
; Declared here only so MRO_MCM can override it and call parent.OnGameReload().
; This empty body is never shipped — SkyUI's real .pex runs at load time.
Function OnGameReload()
EndFunction

; Called by SkyUI every time the config page is opened, right before it pushes
; the Pages array to the UI (setPageNames). Empty in the real base; declared
; here so MRO_MCM can override it to re-assert its tab list on every open.
Function OnConfigOpen()
EndFunction

Int Function AddHeaderOption(String a_text, Int a_flags = 0) native
Int Function AddTextOption(String a_text, String a_value, Int a_flags = 0) native
Int Function AddToggleOption(String a_text, Bool a_checked, Int a_flags = 0) native
Int Function AddSliderOption(String a_text, Float a_value, String a_format = "{0}", Int a_flags = 0) native
Int Function AddEmptyOption() native
Function SetCursorFillMode(Int a_fillMode) native
Function SetCursorPosition(Int a_position) native
; SIGNATURES MUST MATCH REAL SKYUI EXACTLY — the compiler bakes the stub's arg
; count (defaults filled in) into every call site, and the VM REJECTS calls
; whose arity differs from the runtime function. These two were declared
; without the trailing a_noUpdate for months: pages rendered (the Add* stubs
; matched), but every repaint call silently failed, so sliders/checkboxes
; only updated on a page switch (re-render from globals). Silent because
; Papyrus logging is off. Real signatures verified against SkyUI source
; (SKI_ConfigBase.psc:869/:1184).
Function SetToggleOptionValue(Int a_option, Bool a_checked, Bool a_noUpdate = false) native
Function SetSliderOptionValue(Int a_option, Float a_value, String a_formatString = "{0}", Bool a_noUpdate = false) native
Function SetSliderDialogStartValue(Float a_value) native
Function SetSliderDialogDefaultValue(Float a_value) native
Function SetSliderDialogRange(Float a_min, Float a_max) native
Function SetSliderDialogInterval(Float a_interval) native
Function ForcePageReset() native
Function SetInfoText(String a_text) native
Function SetTitleText(String a_text) native
