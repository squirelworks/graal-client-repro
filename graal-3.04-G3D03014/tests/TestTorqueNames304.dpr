{ Tests for the 3.04 name table in TorqueNames304.

  The table is not the engine host. This program does not compile the
  common/torque units and it does not boot a console. It checks the names
  against manifests/3.04.list, which stays the TGE 1.2 module list. }
program TestTorqueNames304;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  TorqueNames304 in '../src/TorqueNames304.pas';

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
  I := GraalDrawTypeIndex('TServerPlayer');
  Check(I >= 0, 'TServerPlayer is a draw type');
  Check(GraalDrawTypes[I].Parent = 'TGaniObject', 'TServerPlayer parent is TGaniObject');
  I := GraalDrawTypeIndex('TGaniObject');
  Check(GraalDrawTypes[I].Parent = 'TLevelObject', 'TGaniObject parent is TLevelObject');
  I := GraalDrawTypeIndex('TLevelObject');
  Check(GraalDrawTypes[I].Parent = 'TDrawableObject', 'TLevelObject parent is TDrawableObject');
  I := GraalDrawTypeIndex('TGraalConnection');
  Check((I >= 0) and (GraalDrawTypes[I].Parent = ''), 'TGraalConnection has no recorded parent');
  Check(GraalDrawTypeIndex('TGraalUniverse') < 0, 'TGraalUniverse is not a 3.04 type');
end;

procedure TestModules;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    LoadManifest(L);
    Check(L.Count = TorqueModuleCount, 'manifest length matches the name table');
    for I := 0 to High(TorqueModules) do
      Check((I < L.Count) and (L[I] = TorqueModules[I]), 'module name ' + TorqueModules[I]);
    Check(L.IndexOf('game-tge') >= 0, 'name table includes game-tge');
    Check(L.IndexOf('gameobject') < 0, 'GameObject is not a 3.04 module name');
    Check(L.IndexOf('guigraal') >= 0, 'name table includes guigraal');
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
