{ Tests for the Worlds 6.114 summary. The 108-name dump is not stored.
  The provisional token is the Linux 6.03r7 neighbour. No player starts. }
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
  Check(not WorldsLoginTokenKnown, 'dumps had no login token');
  Check(TokenIsProvisional, 'neighbour token is provisional');
  Check(ProvisionalToken = 'G3D0511C', 'neighbour is Linux 6.03r7');
  Check(Length(ProvisionalToken) = 8, 'provisional token is eight characters');
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
