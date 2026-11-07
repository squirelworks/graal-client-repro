{ ModulesWorlds: a short account of the 6.114 Worlds dump.

  Build 614 had 108 assembly names. This unit keeps the counts and the two
  Quattro names the thin host mentions. It is not a dump of that list, not
  an IL2CPP player, and not the wire.

  ConnectorToken is GNP1905C, the documented connector token. The connector
  script supplies that token. The loopback program is worlds-host, the C++
  thin host beside this unit. }
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
  { Connector token from the 6.1.1.3 note. Provisional for this host:
    the 6.114 dump did not store a clear login literal. }
  ConnectorToken = 'GNP1905C';
  ConnectorTokenProvisional = True;
  { Build 71243 publishes the native plugin under this export name.
    Builds 548 through 614 use an obfuscated name that was not recovered. }
  NativeExport = 'Flavor0';

const
  NeededQuattro: array[0..NeededQuattroCount - 1] of string = (
    'Assemblies-Quattro.dll',
    'Assemblies-graalunity.dll'
  );

{ True when ConnectorToken is the documented connector token GNP1905C. }
function WorldsLoginTokenKnown: Boolean;
function NeededQuattroIndex(const Name: string): Integer;

implementation

function WorldsLoginTokenKnown: Boolean;
begin
  Result := ConnectorToken = 'GNP1905C';
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
