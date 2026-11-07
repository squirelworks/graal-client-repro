{ Graal Worlds 6.114 side shell. The original is a Unity host plus the
  native Graal3DEngine. This program prints a short summary. The loopback
  path is worlds-host (C++), which sends one login-shaped frame. This
  program does not start a player and does not open a socket.

  ConnectorToken in ModulesWorlds is GNP1905C, the documented connector
  token.

  Command line:
    GraalWorlds            one line, exit 0
    GraalWorlds --list     the counts and the two Quattro names
  Any other argument exits 64. }
program GraalWorlds;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/GraalWorlds.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R GraalWorlds.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils,
  ModulesWorlds in 'ModulesWorlds.pas';

var
  I: Integer;

begin
  if ParamCount = 0 then
  begin
    WriteLn('GraalWorlds: summary shell. The loopback host is worlds-host.');
    Exit;
  end;
  if (ParamCount = 1) and (ParamStr(1) = '--list') then
  begin
    WriteLn('6.114 Worlds. Unity player plus native Graal3DEngine. This shell is neither.');
    WriteLn('Build 614 dump: ', DumpAssemblyCount, ' assemblies (',
      QuattroCount, ' Quattro, ', UnityCount, ' Unity, ',
      RuntimeCount, ' runtime, ', PluginCount, ' plugin, ',
      GeneratedCount, ' generated).');
    Write('Quattro names kept:');
    for I := 0 to High(NeededQuattro) do
      Write(' ', NeededQuattro[I]);
    WriteLn;
    WriteLn('Token ', ConnectorToken, ' (documented connector token).');
    WriteLn('The loopback host is worlds-host.');
    Exit;
  end;
  WriteLn('the loopback host is worlds-host');
  Halt(64);
end.
