{ Tests for the Worlds 6.114 scaffold. The catalogue is the build 614
  assembly list. No player is started. }
program TestWorlds;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  ModulesWorlds in '../src/ModulesWorlds.pas';

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

procedure TestCatalogue;
var
  I, J: Integer;
  Seen: array[0..WorldsAssemblyCount - 1] of Boolean;
begin
  Check(ScaffoldOnly, 'scaffold only, no wire client');
  Check(not WorldsLoginTokenKnown, 'login token was not recovered');
  Check(Length(WorldsAssemblies) = WorldsAssemblyCount, '614 assembly count');
  Check(WorldsAssemblies[0].Name = 'Assemblies-Quattro.dll', 'gameplay assembly is first');
  Check(WorldsAssemblyIndex('Assemblies-graalunity.dll') >= 0, 'native-bridge assembly is listed');
  Check(WorldsAssemblyIndex('Graal3DEngine.dll') < 0, 'native plugin is not an IL2CPP assembly');
  Check(WorldsAssemblyIndex('Firebase.App.dll') < 0, '614 list has no Firebase assembly');
  Check(WorldsAssemblyIndex('Assembly-CSharp-firstpass.dll') < 0,
    '614 list has no firstpass assembly');
  Check(Pos('type bodies were not recovered',
    WorldsAssemblyPurpose('Assemblies-Quattro.dll')) > 0,
    'gameplay types are not invented');
  Check(Pos('native bridge', WorldsAssemblyPurpose('Assemblies-graalunity.dll')) > 0,
    'graalunity is the bridge');
  Check(WorldsAssemblyPurpose('mscorlib.dll') = 'Language runtime.', 'runtime role');
  Check(WorldsAssemblyPurpose('UnityEngine.CoreModule.dll') =
    'Unity engine module or Unity package.', 'Unity role');
  for I := 0 to High(Seen) do
    Seen[I] := False;
  for I := 0 to High(WorldsAssemblies) do
  begin
    Check(WorldsAssemblies[I].Name <> '', 'name ' + IntToStr(I));
    Check(WorldsAssemblyPurpose(WorldsAssemblies[I].Name) <> '',
      'purpose ' + WorldsAssemblies[I].Name);
    J := WorldsAssemblyIndex(WorldsAssemblies[I].Name);
    Check((J = I) and not Seen[I], 'unique ' + WorldsAssemblies[I].Name);
    if (J >= 0) and (J <= High(Seen)) then
      Seen[J] := True;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestCatalogue;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
