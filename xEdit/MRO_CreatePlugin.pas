{
  MRO_CreatePlugin.pas
  xEdit / SSEEdit script — creates MRO.esp from scratch.
  Run from the Scripting menu: Tools > Scripts > MRO_CreatePlugin

  BEFORE RUNNING:
    1. Load Skyrim.esm and Requiem.esp (plus any Requiem patches active in your list).
    2. After running, right-click MRO.esp > "Set as Active File" and save.
    3. Compile Papyrus scripts and copy .pex files into MRO.esp Data\Scripts folder.
    4. Read [MRO] NOTE lines in the log — several values need manual verification.
}
unit MRO_CreatePlugin;

uses xEditAPI, Classes, SysUtils, StrUtils, Windows;

var
  MROFile    : IwbFile;
  SkymESM    : IwbFile;
  ReqESP     : IwbFile;
  ExpMod     : IwbFile;   { Experience.esp by meh321, if present }
  DawnESM    : IwbFile;   { Dawnguard.esm }
  DBrnESM    : IwbFile;   { Dragonborn.esm }
  HasReq     : Boolean;
  HasExpMod  : Boolean;
  HasDawn    : Boolean;
  HasDBrn    : Boolean;

  { Stored record references — used to link quest properties }
  StartupQuestRec    : IInterface;

  { GlobalVariable records — stored for property wiring }
  GV_ResistCap       : IInterface;
  GV_ArmorCap        : IInterface;
  GV_Absorb          : IInterface;
  GV_CarryWeight     : IInterface;
  GV_Regen           : IInterface;
  GV_ArrowRecovery   : IInterface;
  GV_CellReset       : IInterface;
  GV_SetupDone       : IInterface;
  GV_MasteryEnabled  : IInterface;
  GV_MasteryBaseGrant: IInterface;
  GV_MasteryCap      : IInterface;

{ ===========================================================
  UTILITY
  =========================================================== }

function GetFileByName(const aName: string): IwbFile;
var i: Integer;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do
    if SameText(GetFileName(FileByIndex(i)), aName) then begin
      Result := FileByIndex(i);
      Exit;
    end;
end;

function AddNewRecord(const aSignature, aEditorID: string): IInterface;
var grp: IInterface;
begin
  grp := GroupBySignature(MROFile, aSignature);
  if not Assigned(grp) then
    grp := Add(MROFile, aSignature, True);
  Result := Add(grp, aSignature, True);
  SetElementEditValues(Result, 'EDID', aEditorID);
end;

{ Copy a record from a source file into MROFile as an override }
function OverrideRecord(sourceRec: IInterface): IInterface;
begin
  Result := wbCopyElementToFile(sourceRec, MROFile, False, True);
end;

procedure SetGMST_Float(const aEditorID: string; aValue: Extended);
var rec: IInterface;
begin
  rec := AddNewRecord('GMST', aEditorID);
  SetElementEditValues(rec, 'DATA\Value', FloatToStr(aValue));
end;

procedure SetGMST_Int(const aEditorID: string; aValue: Integer);
var rec: IInterface;
begin
  rec := AddNewRecord('GMST', aEditorID);
  SetElementEditValues(rec, 'DATA\Value', IntToStr(aValue));
end;

{ Create or get a GlobalVariable record }
function CreateGlobalVar(const aEditorID: string; isFloat: Boolean; initVal: Extended): IInterface;
begin
  Result := AddNewRecord('GLOB', aEditorID);
  if isFloat then begin
    SetElementEditValues(Result, 'FNAM',        'f');
    SetElementEditValues(Result, 'FLTV\Value',  FloatToStr(initVal));
  end else begin
    SetElementEditValues(Result, 'FNAM',        's');   { short = integer }
    SetElementEditValues(Result, 'FLTV\Value',  FloatToStr(initVal));
  end;
end;

{ ===========================================================
  INITIALIZE
  =========================================================== }

function Initialize: Integer;
begin
  Result := 0;

  SkymESM   := GetFileByName('Skyrim.esm');
  ReqESP    := GetFileByName('Requiem.esp');
  ExpMod    := GetFileByName('Experience.esp');
  DawnESM   := GetFileByName('Dawnguard.esm');
  DBrnESM   := GetFileByName('Dragonborn.esm');
  HasReq    := Assigned(ReqESP);
  HasExpMod := Assigned(ExpMod);
  HasDawn   := Assigned(DawnESM);
  HasDBrn   := Assigned(DBrnESM);

  if not Assigned(SkymESM) then begin
    AddMessage('[MRO] ERROR: Skyrim.esm not loaded. Aborting.');
    Result := 1; Exit;
  end;

  MROFile := AddNewFile;
  if not Assigned(MROFile) then begin
    AddMessage('[MRO] ERROR: Could not create plugin file. Aborting.');
    Result := 1; Exit;
  end;

  SetFileName(MROFile, 'MRO.esp');
  AddMasterIfMissing(MROFile, 'Skyrim.esm');
  if HasReq then
    AddMasterIfMissing(MROFile, 'Requiem.esp');
  if HasDawn then
    AddMasterIfMissing(MROFile, 'Dawnguard.esm');
  if HasDBrn then
    AddMasterIfMissing(MROFile, 'Dragonborn.esm');

  if HasExpMod then
    AddMessage('[MRO] Experience.esp detected — XP GMSTs skipped.')
  else
    AddMessage('[MRO] No Experience mod detected.');
  if HasDawn then
    AddMessage('[MRO] Dawnguard.esm detected — Harkon quest property will be set.')
  else
    AddMessage('[MRO] Dawnguard.esm NOT loaded — Harkon MCM panel will be hidden.');
  if HasDBrn then
    AddMessage('[MRO] Dragonborn.esm detected — Miraak quest property will be set.')
  else
    AddMessage('[MRO] Dragonborn.esm NOT loaded — Miraak MCM panel will be hidden.');

  AddMessage('[MRO] Building MRO.esp...');

  CreateGlobalVariables;
  CreateGameSettings;
  CreateCarryWeightAbility;
  CreateAbsorbMGEF;
  CreateAbsorbSpell;
  CreateStartupQuest;
  CreateMCMQuest;
  TweakVendorFactions;
  TweakPotionWeights;

  AddMessage('[MRO] Done. Save MRO.esp then compile Papyrus scripts (see BUILD.md).');
end;

{ ===========================================================
  GLOBAL VARIABLES
  One GlobalVariable per MCM-toggleable feature.
  Default 1 = enabled. Default 0 = first-run flags.
  These are read by MRO_StartupQuest at runtime so features can
  be toggled live from the MCM without restarting the game.
  =========================================================== }
procedure CreateGlobalVariables;
begin
  AddMessage('[MRO] Creating GlobalVariables...');

  GV_ResistCap        := CreateGlobalVar('MRO_F_ResistCap',        False, 1.0);
  GV_ArmorCap         := CreateGlobalVar('MRO_F_ArmorCap',         False, 1.0);
  GV_Absorb           := CreateGlobalVar('MRO_F_Absorb',           False, 1.0);
  GV_CarryWeight      := CreateGlobalVar('MRO_F_CarryWeight',      False, 1.0);
  GV_Regen            := CreateGlobalVar('MRO_F_Regen',            False, 1.0);
  GV_ArrowRecovery    := CreateGlobalVar('MRO_F_ArrowRecovery',    False, 1.0);
  GV_CellReset        := CreateGlobalVar('MRO_F_CellReset',        False, 1.0);
  GV_SetupDone        := CreateGlobalVar('MRO_SetupDone',          False, 0.0);
  GV_MasteryEnabled   := CreateGlobalVar('MRO_MasteryEnabled',     False, 1.0);
  GV_MasteryBaseGrant := CreateGlobalVar('MRO_MasteryBaseGrant',   True,  1.0);
  GV_MasteryCap       := CreateGlobalVar('MRO_MasteryCap',         False, 100.0);

  AddMessage('[MRO] GlobalVariables done (11 records).');
end;

{ ===========================================================
  GAME SETTINGS
  Values calibrated for FFVII-IX feel on top of Requiem.
  =========================================================== }
procedure CreateGameSettings;
begin
  AddMessage('[MRO] Writing game settings...');

  { ---- ELEMENTAL RESISTANCE CAP --------------------------------- }
  SetGMST_Float('fPlayerMaxResistance', 10000.0);

  { ---- PHYSICAL ARMOR -------------------------------------------
    fArmorScalingFactor halved: higher AR investment needed for the same DR.
    Phase 2 will replace this with DR = AR / (AR + 105). }
  SetGMST_Float('fArmorRatingPCMax',   10000.0);
  SetGMST_Float('fArmorRatingMax',     10000.0);
  SetGMST_Float('fMaxArmorRating',        99.0);
  SetGMST_Float('fArmorScalingFactor',    0.06);

  { ---- COMBAT HEALTH REGEN (in-combat) --------------------------
    Keep at 0 — no passive in-combat healing, like FF.
    Out-of-combat regen is handled at runtime by Papyrus (checks
    current load order value before applying). }
  SetGMST_Float('fCombatHealthRegenRateMult', 0.0);

  { ---- STAMINA REGEN IN COMBAT ----------------------------------
    Requiem already sets fCombatStaminaRegenRateMult = 0.5,
    so this override is technically redundant, but harmless. }
  SetGMST_Float('fCombatStaminaRegenRateMult', 0.5);

  { ---- ARROW RECOVERY -------------------------------------------
    66% recovery = consumables feel plentiful but not infinite.
    Requiem's value varies by list; we override to 66%. }
  SetGMST_Int('iArrowInventoryChance', 66);

  { ---- CELL RESPAWN / VENDOR RESTOCK ----------------------------
    72h (3 days) vs Requiem's 720h (30 days).
    FF games encourage farming and reliable vendor restocking. }
  SetGMST_Int('iHoursToRespawnCell',        72);
  SetGMST_Int('iHoursToRespawnCellCleared', 168);

  AddMessage('[MRO] Game settings done.');
end;

{ ===========================================================
  REGEN ABILITY — DISABLED (kept for reference)
  Out-of-combat regen is now handled entirely at runtime via
  Game.SetGameSettingFloat in MRO_StartupQuest, so we don't
  need ESP-level regen records. If the load order already
  enables regen (LoreRim does via Requiem Lite toggle), the
  Papyrus script skips applying it.
  =========================================================== }
{ procedure CreateRegenAbility; }  { see commit history if needed }

{ ===========================================================
  CARRY WEIGHT ABILITY
  +150 carry weight — enough for a full potion stock without
  encumbrance being a punishing meta-game.
  =========================================================== }
procedure CreateCarryWeightAbility;
var
  mgefRec : IInterface;
  spelRec : IInterface;
begin
  AddMessage('[MRO] Creating MRO_CarryWeightAbility...');

  mgefRec := AddNewRecord('MGEF', 'MRO_CarryWeightMGEF');
  SetElementEditValues(mgefRec, 'FULL',               'MRO Carry Weight Boost');
  SetElementEditValues(mgefRec, 'DATA\Flags',         '0');
  SetElementEditValues(mgefRec, 'DATA\Base Cost',     '0');
  SetElementEditValues(mgefRec, 'DATA\Archetype',     'ValueModifier');
  SetElementEditValues(mgefRec, 'DATA\Casting Type',  'Constant Effect');
  SetElementEditValues(mgefRec, 'DATA\Delivery',      'Self');
  SetElementEditValues(mgefRec, 'DATA\Actor Value',   'CarryWeight');
  SetElementEditValues(mgefRec, 'DATA\Magic Skill',   'None');
  SetElementEditValues(mgefRec, 'DATA\Resist Value',  'None');

  spelRec := AddNewRecord('SPEL', 'MRO_CarryWeightAbility');
  SetElementEditValues(spelRec, 'FULL',              'MRO Carry Weight Boost');
  SetElementEditValues(spelRec, 'SPIT\Type',         'Ability');
  SetElementEditValues(spelRec, 'SPIT\Cast Type',    'Constant Effect');
  SetElementEditValues(spelRec, 'SPIT\Delivery',     'Self');
  SetElementEditValues(spelRec, 'SPIT\Flags',        'No Auto Calc | PC Start Spell');
  SetElementEditValues(spelRec, 'Effects\[0]\EFID - Base Effect\EDID', 'MRO_CarryWeightMGEF');
  SetElementEditValues(spelRec, 'Effects\[0]\EFIT\Magnitude', '150');
  SetElementEditValues(spelRec, 'Effects\[0]\EFIT\Area',      '0');
  SetElementEditValues(spelRec, 'Effects\[0]\EFIT\Duration',  '0');

  AddMessage('[MRO] MRO_CarryWeightAbility done.');
end;

{ ===========================================================
  ABSORB MAGIC EFFECT
  =========================================================== }
procedure CreateAbsorbMGEF;
var rec: IInterface;
begin
  AddMessage('[MRO] Creating MRO_AbsorbMGEF...');

  rec := AddNewRecord('MGEF', 'MRO_AbsorbMGEF');
  SetElementEditValues(rec, 'FULL',               'MRO Elemental Absorption');
  SetElementEditValues(rec, 'DATA\Flags',         '0');
  SetElementEditValues(rec, 'DATA\Base Cost',     '0');
  SetElementEditValues(rec, 'DATA\Magic Skill',   'None');
  SetElementEditValues(rec, 'DATA\Resist Value',  'None');
  SetElementEditValues(rec, 'DATA\Archetype',     'Script');
  SetElementEditValues(rec, 'DATA\Casting Type',  'Constant Effect');
  SetElementEditValues(rec, 'DATA\Delivery',      'Self');

  SetElementEditValues(rec, 'VMAD\Version',       '5');
  SetElementEditValues(rec, 'VMAD\Object Format', '2');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\scriptName', 'MRO_AbsorbMGEF');

  { FireDamage  = Skyrim.esm 0x000424EF }
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[0]\propertyName', 'MagicDamageFire');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[0]\Type',          'Object');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[0]\Value\Object Union\Object v2\FormID', '000424EF');

  { FrostDamage = Skyrim.esm 0x00044BDC }
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[1]\propertyName', 'MagicDamageFrost');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[1]\Type',          'Object');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[1]\Value\Object Union\Object v2\FormID', '00044BDC');

  { ShockDamage = Skyrim.esm 0x00044BDE }
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[2]\propertyName', 'MagicDamageShock');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[2]\Type',          'Object');
  SetElementEditValues(rec, 'VMAD\Scripts\[0]\Properties\[2]\Value\Object Union\Object v2\FormID', '00044BDE');

  AddMessage('[MRO] MRO_AbsorbMGEF done.');
end;

{ ===========================================================
  ABSORB ABILITY
  =========================================================== }
procedure CreateAbsorbSpell;
var rec: IInterface;
begin
  AddMessage('[MRO] Creating MRO_AbsorbAbility...');

  rec := AddNewRecord('SPEL', 'MRO_AbsorbAbility');
  SetElementEditValues(rec, 'FULL',            'MRO Elemental Absorption');
  SetElementEditValues(rec, 'SPIT\Type',       'Ability');
  SetElementEditValues(rec, 'SPIT\Cast Type',  'Constant Effect');
  SetElementEditValues(rec, 'SPIT\Delivery',   'Self');
  SetElementEditValues(rec, 'SPIT\Flags',      'No Auto Calc | PC Start Spell');
  SetElementEditValues(rec, 'Effects\[0]\EFID - Base Effect\EDID', 'MRO_AbsorbMGEF');
  SetElementEditValues(rec, 'Effects\[0]\EFIT\Magnitude', '0');
  SetElementEditValues(rec, 'Effects\[0]\EFIT\Area',      '0');
  SetElementEditValues(rec, 'Effects\[0]\EFIT\Duration',  '0');

  AddMessage('[MRO] MRO_AbsorbAbility done.');
end;

{ ===========================================================
  STARTUP QUEST
  Drives the MRO_StartupQuest script on every game load.
  Wires all spell and GlobalVariable properties so Papyrus
  can control them without hardcoded FormIDs.
  =========================================================== }
procedure CreateStartupQuest;
var
  rec    : IInterface;
  script : IInterface;
  idx    : Integer;

  procedure AddObjProp(propName: string; targetRec: IInterface);
  begin
    if not Assigned(targetRec) then begin
      AddMessage('[MRO] StartupQuest: skipping nil property ' + propName);
      Exit;
    end;
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\propertyName', propName);
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\Type', 'Object');
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\Value\Object Union\Object v2\FormID',
      IntToHex(GetFormID(targetRec), 8));
    Inc(idx);
  end;

begin
  AddMessage('[MRO] Creating MRO_StartupQuest...');

  rec := AddNewRecord('QUST', 'MRO_StartupQuest');
  SetElementEditValues(rec, 'FULL',          'MRO Startup');
  SetElementEditValues(rec, 'DNAM\Flags',    'Start Game Enabled');   { NOT Run Once — must persist for 30s update loop }
  SetElementEditValues(rec, 'DNAM\Priority', '0');

  SetElementEditValues(rec, 'VMAD\Scripts\[0]\scriptName', 'MRO_StartupQuest');
  script := ElementByPath(rec, 'VMAD\Scripts\[0]');

  idx := 0;

  { Property 0: PlayerRef (Skyrim.esm 00000014) }
  SetElementEditValues(script, 'Properties\[0]\propertyName', 'PlayerRef');
  SetElementEditValues(script, 'Properties\[0]\Type',          'Object');
  SetElementEditValues(script, 'Properties\[0]\Value\Object Union\Object v2\FormID', '00000014');
  idx := 1;

  { Spell properties — wired by EditorID lookup after creation }
  AddMessage('[MRO] NOTE: MRO_AbsorbAbility and MRO_CarryWeightAbility must be set manually');
  AddMessage('[MRO]       (right-click script property > Edit Value > paste FormID from EDID).');
  SetElementEditValues(script, 'Properties\[1]\propertyName', 'MRO_AbsorbAbility');
  SetElementEditValues(script, 'Properties\[1]\Type',          'Object');
  SetElementEditValues(script, 'Properties\[2]\propertyName', 'MRO_CarryWeightAbility');
  SetElementEditValues(script, 'Properties\[2]\Type',          'Object');
  idx := 3;

  { Properties 3-13: GlobalVariables }
  AddObjProp('MRO_F_ResistCap',     GV_ResistCap);
  AddObjProp('MRO_F_ArmorCap',      GV_ArmorCap);
  AddObjProp('MRO_F_Absorb',        GV_Absorb);
  AddObjProp('MRO_F_CarryWeight',   GV_CarryWeight);
  AddObjProp('MRO_F_Regen',         GV_Regen);
  AddObjProp('MRO_F_ArrowRecovery', GV_ArrowRecovery);
  AddObjProp('MRO_F_CellReset',     GV_CellReset);
  AddObjProp('MRO_SetupDone',       GV_SetupDone);
  AddObjProp('MRO_MasteryEnabled',  GV_MasteryEnabled);
  AddObjProp('MRO_MasteryBaseGrant',GV_MasteryBaseGrant);
  AddObjProp('MRO_MasteryCap',      GV_MasteryCap);

  StartupQuestRec := rec;  { MCM quest needs this reference }

  AddMessage('[MRO] MRO_StartupQuest done (' + IntToStr(idx) + ' properties wired).');
  AddMessage('[MRO] NOTE: Add follower alias slots manually in xEdit after saving (see BUILD.md).');
end;

{ ===========================================================
  MCM QUEST
  Hosts the MRO_MCM script (SkyUI discovers it by script name).
  Wires GlobalVariables so the MCM can toggle each feature live.
  =========================================================== }
procedure CreateMCMQuest;
var
  rec    : IInterface;
  script : IInterface;
  idx    : Integer;

  procedure AddQuestProp(const propName: string; targetRec: IInterface);
  begin
    if not Assigned(targetRec) then begin
      AddMessage('[MRO] MCM: skipping nil property ' + propName);
      Exit;
    end;
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\propertyName', propName);
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\Type', 'Object');
    SetElementEditValues(script,
      'Properties\[' + IntToStr(idx) + ']\Value\Object Union\Object v2\FormID',
      IntToHex(GetFormID(targetRec), 8));
    Inc(idx);
  end;

  function FindQuest(const aEDID: string): IInterface;
  var fi, ri: Integer; f, g, r: IInterface;
  begin
    Result := nil;
    for fi := 0 to Pred(FileCount) do begin
      f := FileByIndex(fi);
      g := GroupBySignature(f, 'QUST');
      if not Assigned(g) then Continue;
      for ri := 0 to Pred(ElementCount(g)) do begin
        r := ElementByIndex(g, ri);
        if SameText(GetElementEditValues(r, 'EDID'), aEDID) then begin
          Result := r; Exit;
        end;
      end;
    end;
  end;

begin
  AddMessage('[MRO] Creating MRO_BossReadiness_MCM quest...');

  rec := AddNewRecord('QUST', 'MRO_BossReadiness_MCM');
  SetElementEditValues(rec, 'FULL',          'MRO Boss Readiness');
  SetElementEditValues(rec, 'DNAM\Flags',    'Start Game Enabled');
  SetElementEditValues(rec, 'DNAM\Priority', '0');

  SetElementEditValues(rec, 'VMAD\Scripts\[0]\scriptName', 'MRO_MCM');
  script := ElementByPath(rec, 'VMAD\Scripts\[0]');

  idx := 0;

  { MRO_Quest → MRO_StartupQuest (needed so MCM can call RefreshAbilities etc.) }
  AddQuestProp('MRO_Quest', StartupQuestRec);

  { Boss quest references }
  AddQuestProp('MQ206_AlduinsBane', FindQuest('MQ206'));
  AddQuestProp('MQ305_Sovngarde',   FindQuest('MQ305'));

  if HasDawn then
    AddQuestProp('DLC1VQ08_Harkon', FindQuest('DLC1VQ08'))
  else
    AddMessage('[MRO] MCM: DLC1VQ08_Harkon skipped (Dawnguard not loaded).');

  if HasDBrn then
    AddQuestProp('DLC2MQ06_Miraak', FindQuest('DLC2MQ06'))
  else
    AddMessage('[MRO] MCM: DLC2MQ06_Miraak skipped (Dragonborn not loaded).');

  { Feature flag GlobalVariables }
  AddQuestProp('MRO_MasteryEnabled',   GV_MasteryEnabled);
  AddQuestProp('MRO_MasteryBaseGrant', GV_MasteryBaseGrant);
  AddQuestProp('MRO_F_ResistCap',      GV_ResistCap);
  AddQuestProp('MRO_F_ArmorCap',       GV_ArmorCap);
  AddQuestProp('MRO_F_Absorb',         GV_Absorb);
  AddQuestProp('MRO_F_CarryWeight',    GV_CarryWeight);
  AddQuestProp('MRO_F_Regen',          GV_Regen);
  AddQuestProp('MRO_F_ArrowRecovery',  GV_ArrowRecovery);
  AddQuestProp('MRO_F_CellReset',      GV_CellReset);
  AddQuestProp('MRO_MasteryCap',       GV_MasteryCap);

  AddMessage('[MRO] MRO_BossReadiness_MCM done (' + IntToStr(idx) + ' properties set).');
end;

{ ===========================================================
  VENDOR FACTION GOLD — DOUBLE ALL VENDOR GOLD
  Reads current gold values from the load order (Requiem.esp
  overrides Skyrim.esm), then doubles whatever is currently set.
  "Current load order" values are correct because we read from
  Requiem.esp first (it overrides Skyrim.esm).
  =========================================================== }
procedure TweakVendorFactionFile(sourceFile: IwbFile);
var
  factGrp    : IInterface;
  rec        : IInterface;
  overRec    : IInterface;
  venv       : IInterface;
  goldMin    : Integer;
  goldMax    : Integer;
  edid       : string;
  i          : Integer;
  tweakCount : Integer;
begin
  if not Assigned(sourceFile) then Exit;
  factGrp := GroupBySignature(sourceFile, 'FACT');
  if not Assigned(factGrp) then Exit;

  tweakCount := 0;
  for i := 0 to Pred(ElementCount(factGrp)) do begin
    rec  := ElementByIndex(factGrp, i);
    venv := ElementByPath(rec, 'VENV');
    if not Assigned(venv) then Continue;

    goldMin := GetElementNativeValues(rec, 'VENV\Gold Min');
    goldMax := GetElementNativeValues(rec, 'VENV\Gold Max');
    if (goldMin <= 0) and (goldMax <= 0) then Continue;

    edid    := GetElementEditValues(rec, 'EDID');
    overRec := OverrideRecord(rec);
    if not Assigned(overRec) then begin
      AddMessage('[MRO] WARNING: Could not override faction ' + edid);
      Continue;
    end;

    SetElementNativeValues(overRec, 'VENV\Gold Min', goldMin * 2);
    SetElementNativeValues(overRec, 'VENV\Gold Max', goldMax * 2);
    Inc(tweakCount);
  end;

  AddMessage('[MRO] Doubled gold on ' + IntToStr(tweakCount) +
             ' vendor factions from ' + GetFileName(sourceFile));
end;

procedure TweakVendorFactions;
begin
  AddMessage('[MRO] Tweaking vendor faction gold...');
  TweakVendorFactionFile(SkymESM);
  if HasReq then TweakVendorFactionFile(ReqESP);
  AddMessage('[MRO] Vendor gold done.');
end;

{ ===========================================================
  POTION WEIGHT — REDUCE HEALING ITEMS TO 25% WEIGHT
  =========================================================== }
procedure TweakPotionFile(sourceFile: IwbFile);
const
  TargetKeywords : array[0..4] of string = (
    'MagicRestoreHealth',
    'MagicRestoreStamina',
    'MagicRestoreMagicka',
    'MagicCureDisease',
    'MagicCurePoison'
  );
var
  alchGrp    : IInterface;
  rec        : IInterface;
  overRec    : IInterface;
  kwda       : IInterface;
  kwEntry    : IInterface;
  kwEdid     : string;
  origWeight : Extended;
  newWeight  : Extended;
  edid       : string;
  i, j, k    : Integer;
  isTarget   : Boolean;
  tweakCount : Integer;
begin
  if not Assigned(sourceFile) then Exit;
  alchGrp := GroupBySignature(sourceFile, 'ALCH');
  if not Assigned(alchGrp) then Exit;

  tweakCount := 0;
  for i := 0 to Pred(ElementCount(alchGrp)) do begin
    rec := ElementByIndex(alchGrp, i);
    edid := GetElementEditValues(rec, 'EDID');

    kwda     := ElementByPath(rec, 'KWDA');
    isTarget := false;
    if Assigned(kwda) then begin
      for j := 0 to Pred(ElementCount(kwda)) do begin
        kwEntry := ElementByIndex(kwda, j);
        kwEdid  := GetElementEditValues(kwEntry, '');
        for k := 0 to High(TargetKeywords) do begin
          if SameText(kwEdid, TargetKeywords[k]) then begin
            isTarget := true;
            Break;
          end;
        end;
        if isTarget then Break;
      end;
    end;

    if not isTarget then Continue;

    origWeight := StrToFloatDef(GetElementEditValues(rec, 'DATA\Weight'), 0.0);
    if origWeight <= 0.0 then Continue;

    newWeight := origWeight * 0.25;
    if newWeight < 0.1 then newWeight := 0.1;

    overRec := OverrideRecord(rec);
    if not Assigned(overRec) then begin
      AddMessage('[MRO] WARNING: Could not override ALCH ' + edid);
      Continue;
    end;

    SetElementEditValues(overRec, 'DATA\Weight', FloatToStr(newWeight));
    Inc(tweakCount);
  end;

  AddMessage('[MRO] Reduced weight on ' + IntToStr(tweakCount) +
             ' potions from ' + GetFileName(sourceFile));
end;

procedure TweakPotionWeights;
begin
  AddMessage('[MRO] Tweaking potion weights...');
  TweakPotionFile(SkymESM);
  if HasReq then TweakPotionFile(ReqESP);
  AddMessage('[MRO] Potion weights done.');
end;

{ ===========================================================
  FINALIZE
  =========================================================== }
function Finalize: Integer;
begin
  Result := 0;
  AddMessage('[MRO] Script complete. Review all [MRO] NOTE and WARNING lines.');
  AddMessage('[MRO] Next: save MRO.esp, compile Papyrus scripts, package mod.');
  AddMessage('[MRO] REMINDER: AbsorbAbility + CarryWeightAbility FormIDs need manual wiring.');
  if HasExpMod then
    AddMessage('[MRO] REMINDER: Install MRO Optional/Experience.ini via FOMOD (FF XP rates).');
end;

end.
