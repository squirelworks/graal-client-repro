{ Tests for the 3.04 game hosted in TGE 1.2.

  The method table is TorqueHost304. The engine units compiled below are
  the common/torque modules 3.04 links. They stay empty stubs; this test
  only checks that they still compile next to the game table, and that
  the table matches manifests/3.04.list. }
program TestHost304;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  TorqueHost304 in '../src/TorqueHost304.pas',
  TqConsole in '../../common/torque/console/TqConsole.pas',
  TqSim in '../../common/torque/sim/TqSim.pas',
  TqGui in '../../common/torque/gui/TqGui.pas',
  TqActionMap in '../../common/torque/actionmap/TqActionMap.pas',
  TqGBitmap in '../../common/torque/gbitmap/TqGBitmap.pas',
  TqMath in '../../common/torque/math/TqMath.pas',
  TqGameTge in '../../common/torque/game-tge/TqGameTge.pas',
  TqNetTorque in '../../common/torque/net-torque/TqNetTorque.pas',
  TqGuiGraal in '../../common/torque/guigraal/TqGuiGraal.pas';

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

function ManifestPath: string;
begin
  Result := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))
    + '../../common/torque/manifests/3.04.list');
end;

procedure LoadManifest(L: TStrings);
var
  Raw: TStringList;
  I: Integer;
  S: string;
begin
  L.Clear;
  Raw := TStringList.Create;
  try
    Raw.LoadFromFile(ManifestPath);
    for I := 0 to Raw.Count - 1 do
    begin
      S := Trim(Raw[I]);
      if (S = '') or (S[1] = '#') then Continue;
      L.Add(S);
    end;
  finally
    Raw.Free;
  end;
end;

procedure TestMethods;
var
  I: Integer;
begin
  Check(Length(GuiGraalMethods) = GuiGraalMethodCount, '31 GuiGraalCtrl methods');
  Check(not GuiGraal3DCtrlRegistered, 'GuiGraal3DCtrl is not registered');
  Check(GuiGraalScriptArgs('moveUp') = 1, 'moveUp takes one script argument');
  Check(GuiGraalScriptArgs('openServerList') = 0, 'openServerList takes none');
  Check(GuiGraalScriptArgs('loadLevel') = 3, 'loadLevel takes three');
  Check(GuiGraalScriptArgs('updatePlayerProfile') = 10, 'updatePlayerProfile takes ten');
  Check(GuiGraalMethods[GuiGraalMethodIndex('loadLevel')].MinCount = 5, 'loadLevel count is 5');
  Check(GuiGraalMethods[GuiGraalMethodIndex('updatePlayerProfile')].MaxCount = 12,
    'updatePlayerProfile count is 12');
  Check(GuiGraalMethodIndex('setNickName') < 0, 'setNickName is not a 3.04 method');
  Check(GuiGraalMethodIndex('setAccountName') < 0, 'setAccountName is not a 3.04 method');
  Check(GuiGraalMethodIndex('setLanguage') < 0, 'setLanguage is not a 3.04 method');
  Check(GuiGraalMethodIndex('retrieveAccountFields') < 0,
    'retrieveAccountFields is not a 3.04 method');
  Check(GraalPrefIndex('nickname') >= 0, 'nickname is a Graal pref');
  Check(GraalPrefIndex('accountname') >= 0, 'accountname is a Graal pref');
  Check(GraalPrefIndex('language') >= 0, 'language is a Graal pref');
  for I := 0 to High(GuiGraalMethods) do
    Check(GuiGraalMethods[I].MinCount = GuiGraalMethods[I].MaxCount,
      'fixed count ' + GuiGraalMethods[I].Name);
end;

procedure TestTypes;
var
  I: Integer;
begin
  I := GraalHostTypeIndex('TServerPlayer');
  Check(I >= 0, 'TServerPlayer is a draw type');
  Check(GraalHostTypes[I].Parent = 'TGaniObject', 'TServerPlayer parent is TGaniObject');
  I := GraalHostTypeIndex('TGaniObject');
  Check(GraalHostTypes[I].Parent = 'TLevelObject', 'TGaniObject parent is TLevelObject');
  I := GraalHostTypeIndex('TLevelObject');
  Check(GraalHostTypes[I].Parent = 'TDrawableObject', 'TLevelObject parent is TDrawableObject');
  I := GraalHostTypeIndex('TGraalConnection');
  Check((I >= 0) and (GraalHostTypes[I].Parent = ''), 'TGraalConnection has no recorded parent');
  Check(GraalHostTypeIndex('TGraalUniverse') < 0, 'TGraalUniverse is not a 3.04 type');
end;

procedure TestModules;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    LoadManifest(L);
    Check(L.Count = TorqueModuleCount, 'manifest length matches the host');
    for I := 0 to High(TorqueModules) do
      Check((I < L.Count) and (L[I] = TorqueModules[I]), 'module ' + TorqueModules[I]);
    Check(L.IndexOf('game-tge') >= 0, 'stock TGE game layer is linked');
    Check(L.IndexOf('gameobject') < 0, 'GameObject is not a 3.04 module');
    Check(L.IndexOf('guigraal') >= 0, 'GuiGraalCtrl module is linked');
  finally
    L.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestMethods;
  TestTypes;
  TestModules;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
