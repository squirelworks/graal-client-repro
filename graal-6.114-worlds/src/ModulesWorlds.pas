{ ModulesWorlds: a short account of the 6.114 Worlds dump.

  Build 614 had 108 assembly names. This unit keeps the counts and the two
  Quattro names the thin host mentions. It is not a dump of that list, not
  an IL2CPP player, and not the wire.

  The dumps stored no eight-character login token. ProvisionalToken is the
  documented Linux 6.03r7 neighbour. It is not a recovered 6.114 token.
  The loopback program is worlds-host, the C++ thin host beside this unit. }
unit ModulesWorlds;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  DumpAssemblyCount = 108;
  QuattroCount = 6;
  UnityCount = 80;
  RuntimeCount = 10;
  PluginCount = 11;
  GeneratedCount = 1;
  NeededQuattroCount = 2;
  { Linux 6.03r7. Provisional: the 6.114 dumps had no token of their own. }
  ProvisionalToken = 'G3D0511C';
  TokenIsProvisional = True;

const
  NeededQuattro: array[0..NeededQuattroCount - 1] of string = (
    'Assemblies-Quattro.dll',
    'Assemblies-graalunity.dll'
  );

{ The dumps did not contain a clear login token. }
function WorldsLoginTokenKnown: Boolean;
function NeededQuattroIndex(const Name: string): Integer;

implementation

function WorldsLoginTokenKnown: Boolean;
begin
  Result := False;
end;

function NeededQuattroIndex(const Name: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(NeededQuattro) do
    if NeededQuattro[I] = Name then
    begin
      Result := I;
      Exit;
    end;
end;

end.
