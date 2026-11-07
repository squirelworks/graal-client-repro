{ Graal 5.31r4 scaffold. The original late-5 client is one quattro_lib
  executable (5.30r3 and 5.31r4, FileVersion 5.303 and 5.314). This
  program names that cut and exits. It does not open a socket.

  The folder is graal-5.31r4. The login line sends G3D0511C, the
  Linux 6.037 neighbour, because 5.31r4 has no exact row.

  Command line:
    Graal531            exit 0
    Graal531 --show     print the two file versions, the engine, the port,
                        and the token the login line sends
  Any other argument exits 64. }
program Graal531;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal531.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal531.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils,
  Late531 in 'Late531.pas';

begin
  if ParamCount = 0 then Exit;
  if (ParamCount = 1) and (ParamStr(1) = '--show') then
  begin
    WriteLn(FileVersion530, ' ', BuildLabel530);
    WriteLn(FileVersion531, ' ', BuildLabel531);
    WriteLn(EngineLibrary);
    WriteLn('torque=', LowerCase(BoolToStr(LinksTorque, True)));
    WriteLn('processes=', ProcessCount);
    WriteLn('port=', BakedLoginPort);
    WriteLn('stored=', TokenLiteral);
    WriteLn('sends=', ClientVersionToken);
    Exit;
  end;
  WriteLn('scaffold only: no network');
  Halt(64);
end.
