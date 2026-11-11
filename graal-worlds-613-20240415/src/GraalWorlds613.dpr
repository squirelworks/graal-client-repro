{ Graal Worlds 613 scaffold. It names the build and exits. It does not
  open a socket and does not load the Unity player or its plugin.

  Command line:
    GraalWorlds613            exit 0
    GraalWorlds613 --show     print the build, Unity and plugin versions, the date,
                        and the stored token (none)
  Any other argument exits 64. }
program GraalWorlds613;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/GraalWorlds613.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R GraalWorlds613.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils,
  Worlds613 in 'Worlds613.pas';

begin
  if ParamCount = 0 then Exit;
  if (ParamCount = 1) and (ParamStr(1) = '--show') then
  begin
    WriteLn('build=', BuildLabel);
    WriteLn('bundle=', BundleVersion);
    WriteLn('unity=', UnityVersion);
    WriteLn('plugin=', PluginFileVersion);
    WriteLn('date=', BuildDate);
    WriteLn('stored=', TokenLiteral);
    Exit;
  end;
  WriteLn('scaffold only: no network');
  Halt(64);
end.
