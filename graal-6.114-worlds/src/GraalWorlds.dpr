{ Graal Worlds 6.114 scaffold. The original is a Unity host plus a native
  Graal plugin. This program is the empty shell: it names the IL2CPP
  assemblies and exits. It does not start a player, load a plugin, or
  open a socket.

  The login token was not recovered, so the folder is graal-6.114-worlds
  and not graal-6.114-<token>.

  Command line:
    GraalWorlds            exit 0
    GraalWorlds --list     print each assembly and what it is for
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
  if ParamCount = 0 then Exit;
  if (ParamCount = 1) and (ParamStr(1) = '--list') then
  begin
    for I := 0 to High(WorldsAssemblies) do
      WriteLn(WorldsAssemblies[I].Name, '  ',
        WorldsAssemblyPurpose(WorldsAssemblies[I].Name));
    Exit;
  end;
  WriteLn('scaffold only: no player and no network');
  Halt(64);
end.
