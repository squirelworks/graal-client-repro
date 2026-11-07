{ TorqueHost304: the 3.04 game hosted in stock TGE 1.2.

  The engine modules live in common/torque (console, sim, gui, actionmap,
  gbitmap, math, game-tge, net-torque, guigraal). This unit is the game
  file beside that engine. It names GuiGraalCtrl's registration and the
  draw types that are not console classes. It does not execute TorqueScript
  and it does not copy an engine source.

  Counts include the command name. On a method they also include the
  object, so a minimum of 2 is a method with no script argument.
  setNickName, setAccountName, setLanguage and retrieveAccountFields are
  3.153 methods and are not on this table. Nickname, account and language
  are $pref::Graal:: variables.

  Sources: Graal_analysis torque/engine-304.md. The module order is the
  same list as common/torque/manifests/3.04.list. }
unit TorqueHost304;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  GuiGraalMethodCount = 31;
  GuiGraal3DCtrlRegistered = False;
  TorqueModuleCount = 9;
  GraalPrefCount = 13;
  GraalHostTypeCount = 7;

type
  TGuiGraalMethod = record
    Name: string;
    MinCount: Integer;
    MaxCount: Integer;
  end;

  TGraalHostType = record
    Name: string;
    Parent: string; { empty when no parent was recorded }
  end;

const
  GuiGraalMethods: array[0..GuiGraalMethodCount - 1] of TGuiGraalMethod = (
    (Name: 'moveUp'; MinCount: 3; MaxCount: 3),
    (Name: 'moveLeft'; MinCount: 3; MaxCount: 3),
    (Name: 'moveDown'; MinCount: 3; MaxCount: 3),
    (Name: 'moveRight'; MinCount: 3; MaxCount: 3),
    (Name: 'doA'; MinCount: 3; MaxCount: 3),
    (Name: 'doS'; MinCount: 3; MaxCount: 3),
    (Name: 'doD'; MinCount: 3; MaxCount: 3),
    (Name: 'doQ'; MinCount: 3; MaxCount: 3),
    (Name: 'doP'; MinCount: 3; MaxCount: 3),
    (Name: 'doM'; MinCount: 3; MaxCount: 3),
    (Name: 'doMicro'; MinCount: 3; MaxCount: 3),
    (Name: 'setChat'; MinCount: 3; MaxCount: 3),
    (Name: 'setPassWord'; MinCount: 3; MaxCount: 3),
    (Name: 'openServerList'; MinCount: 2; MaxCount: 2),
    (Name: 'selectServer'; MinCount: 3; MaxCount: 3),
    (Name: 'selectServerCategory'; MinCount: 3; MaxCount: 3),
    (Name: 'startOfflineMode'; MinCount: 2; MaxCount: 2),
    (Name: 'connectToSelectedServer'; MinCount: 2; MaxCount: 2),
    (Name: 'serverDirectConnect'; MinCount: 3; MaxCount: 3),
    (Name: 'privateMessageSend'; MinCount: 2; MaxCount: 2),
    (Name: 'playerListOpenPlayer'; MinCount: 3; MaxCount: 3),
    (Name: 'playerListProfile'; MinCount: 3; MaxCount: 3),
    (Name: 'updateLoadLevelFields'; MinCount: 2; MaxCount: 2),
    (Name: 'loadLevel'; MinCount: 5; MaxCount: 5),
    (Name: 'updatePlayerProfile'; MinCount: 12; MaxCount: 12),
    (Name: 'updatePlayerMuted'; MinCount: 3; MaxCount: 3),
    (Name: 'updateMidiVolume'; MinCount: 2; MaxCount: 2),
    (Name: 'updateMp3Volume'; MinCount: 2; MaxCount: 2),
    (Name: 'updateRadioVolume'; MinCount: 2; MaxCount: 2),
    (Name: 'updateMicroActivationLevel'; MinCount: 2; MaxCount: 2),
    (Name: 'updateGraalOptions'; MinCount: 2; MaxCount: 2)
  );

  { Linked directories under common/torque, in manifest order.
    gameobject is not a 3.04 module. }
  TorqueModules: array[0..TorqueModuleCount - 1] of string = (
    'console',
    'sim',
    'gui',
    'actionmap',
    'gbitmap',
    'math',
    'game-tge',
    'net-torque',
    'guigraal'
  );

  { $pref::Graal:: names this binary registers. Not console methods. }
  GraalPrefs: array[0..GraalPrefCount - 1] of string = (
    'nickname',
    'accountname',
    'language',
    'automapping',
    'notoalls',
    'dontloadlistheads',
    'fixedport',
    'fixedudpport',
    'noudp',
    'dontconnectlevels',
    'limitnicknames',
    'nicknamelimit',
    'defaultfontsize'
  );

  { C++ types inside the control. None of them is a console class. }
  GraalHostTypes: array[0..GraalHostTypeCount - 1] of TGraalHostType = (
    (Name: 'TDrawableObject'; Parent: ''),
    (Name: 'TLevelObject'; Parent: 'TDrawableObject'),
    (Name: 'TGaniObject'; Parent: 'TLevelObject'),
    (Name: 'TServerPlayer'; Parent: 'TGaniObject'),
    (Name: 'TDrawableSurface'; Parent: 'TDrawableObject'),
    (Name: 'TSurfaceOwner'; Parent: 'TDrawableSurface'),
    (Name: 'TGraalConnection'; Parent: '')
  );

function GuiGraalMethodIndex(const Name: string): Integer;
{ Script arguments, or -1 when the name is not on the table. }
function GuiGraalScriptArgs(const Name: string): Integer;
function GraalPrefIndex(const Name: string): Integer;
function GraalHostTypeIndex(const Name: string): Integer;

implementation

function GuiGraalMethodIndex(const Name: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(GuiGraalMethods) do
    if GuiGraalMethods[I].Name = Name then
    begin
      Result := I;
      Exit;
    end;
end;

function GuiGraalScriptArgs(const Name: string): Integer;
var
  I: Integer;
begin
  I := GuiGraalMethodIndex(Name);
  if I < 0 then Result := -1
  else Result := GuiGraalMethods[I].MinCount - 2;
end;

function GraalPrefIndex(const Name: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(GraalPrefs) do
    if GraalPrefs[I] = Name then
    begin
      Result := I;
      Exit;
    end;
end;

function GraalHostTypeIndex(const Name: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(GraalHostTypes) do
    if GraalHostTypes[I].Name = Name then
    begin
      Result := I;
      Exit;
    end;
end;

end.
