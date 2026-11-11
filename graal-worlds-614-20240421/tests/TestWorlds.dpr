{ Tests for the Worlds 6.114 summary. The 108-name dump is not stored.
  The token is GNP1905C, the documented connector token. It is not
  provisional. The playable stand-in is worlds-player. }
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

procedure TestSummary;
var
  I: Integer;
begin
  Check(WorldsLoginTokenKnown, 'connector token bytes are GNP1905C');
  Check(NativeExport = 'Flavor0', 'the known native export is Flavor0');
  Check(ConnectorToken = 'GNP1905C', 'connector token is GNP1905C');
  Check(Length(ConnectorToken) = 8, 'connector token is eight characters');
  Check(QuattroCount + UnityCount + RuntimeCount + PluginCount + GeneratedCount =
    DumpAssemblyCount, 'kind counts add up to the dump size');
  Check(DumpAssemblyCount = 108, 'build 614 count is 108');
  Check(NeededQuattroCount = 2, 'only two Quattro names are kept');
  Check(Length(NeededQuattro) = NeededQuattroCount, 'name array matches the count');
  Check(NeededQuattroIndex('Assemblies-Quattro.dll') = 0, 'gameplay assembly is named');
  Check(NeededQuattroIndex('Assemblies-graalunity.dll') = 1, 'bridge assembly is named');
  Check(NeededQuattroIndex('Graal3DEngine.dll') < 0, 'native plugin is not an IL2CPP assembly');
  Check(NeededQuattroIndex('mscorlib.dll') < 0, 'runtime names are not listed');
  for I := 0 to High(NeededQuattro) do
    Check(NeededQuattro[I] <> '', 'name ' + IntToStr(I));
end;

begin
  Passed := 0;
  Failed := 0;
  TestSummary;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
