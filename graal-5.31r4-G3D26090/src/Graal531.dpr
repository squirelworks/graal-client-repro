{ Graal 5.31r4. The original late-5 client is one quattro_lib executable
  (5.30r3 and 5.31r4, FileVersion 5.303 and 5.314). Its rebuild is the
  Quattro program, common/cpp/quattro's quattro-play with the "5.31r4"
  row (gen-5, G3D26090, 5.24's receive switch without 41 and 181, no
  tiles before the warp). This program hands the game to the quattro-play
  beside it (common/GQuattroPlay.pas); the Pascal side stays the scaffold
  and opens no socket itself.

  No eight-character token is stored in those images. The login line
  sends G3D26090, the documented token, and the folder carries it:
  graal-5.31r4-G3D26090.

  Command line:
    Graal531            exit 0
    Graal531 --show     print the two file versions, the engine, the port,
                        and the token the login line sends
    Graal531 --server HOST:PORT --account NAME [--password-env VAR]
             [--server-name NAME] [--data DIR] [--seconds N]
    Graal531 --level FILE [--x X --y Y] [--data DIR] [--seconds N]
                        the game in quattro-play; the password is read from
                        VAR (default GRAAL_PW) and handed over in the
                        environment, never on a command line. The Seihai
                        secure login follows the player's setting.
  Exits 64 for any other argument, and 69 when there is no quattro-play
  (or, on Linux, no X display). }
program Graal531;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal531.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal531.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils,
  GAssetDirs in '../../common/GAssetDirs.pas',
  GQuattroPlay in '../../common/GQuattroPlay.pas',
  Late531 in 'Late531.pas';

const
  { the quattro-play row (common/cpp/quattro/net/profile.cpp) }
  QuattroBuild = '5.31r4';
  FirstServerName = 'Login';

function Arg(const Name, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = Name then
    begin
      Result := ParamStr(I + 1);
      Exit;
    end;
end;

function HasArg(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if ParamStr(I) = Name then Exit(True);
end;

{ Every option takes one value, once, from the known set. }
function ArgsWellFormed: Boolean;
var
  I, J: Integer;
  Name, Value: string;
begin
  Result := False;
  I := 1;
  while I <= ParamCount do
  begin
    Name := ParamStr(I);
    if (Name <> '--server') and (Name <> '--account') and (Name <> '--password-env') and
      (Name <> '--server-name') and (Name <> '--level') and (Name <> '--x') and
      (Name <> '--y') and (Name <> '--data') and (Name <> '--seconds') then Exit;
    if I = ParamCount then Exit;
    Value := ParamStr(I + 1);
    if (Value = '') or (Copy(Value, 1, 2) = '--') then Exit;
    for J := 1 to I - 1 do
      if ParamStr(J) = Name then Exit;
    Inc(I, 2);
  end;
  Result := True;
end;

{ The game in quattro-play: its exit code, 64 for bad arguments, 69 when it
  cannot be started here. }
function RunGame: Integer;
var
  Server, Dir, Data, Exe, Password: string;
  Online: Boolean;
  P, Port, I: Integer;
  Coordinate: Double;
  Roots: array of string;
  Args: TQuattroArgs;
begin
  Result := 64;
  if not ArgsWellFormed then Exit;
  Server := Arg('--server', '');
  Online := Server <> '';
  if Online = (Arg('--level', '') <> '') then Exit;
  if Online then
  begin
    P := Pos(':', Server);
    if (P <= 1) or (Arg('--account', '') = '') then Exit;
    if not TryStrToInt(Copy(Server, P + 1, MaxInt), Port) or (Port < 1) or (Port > 65535) then Exit;
    if HasArg('--x') or HasArg('--y') then Exit;
  end
  else if HasArg('--account') or HasArg('--password-env') or HasArg('--server-name') then Exit;
  if HasArg('--seconds') then
    if not TryStrToInt(Arg('--seconds', ''), I) or (I <= 0) then Exit;
  if HasArg('--x') and ((Pos(',', Arg('--x', '')) > 0) or not TryStrToFloat(Arg('--x', ''), Coordinate)) then Exit;
  if HasArg('--y') and ((Pos(',', Arg('--y', '')) > 0) or not TryStrToFloat(Arg('--y', ''), Coordinate)) then Exit;
  Dir := ExtractFilePath(ParamStr(0));
  Exe := QuattroProgram(Dir, Online);
  if Exe = '' then
  begin
    try
      { a Windows GUI program may have no console to write to }
      WriteLn(ErrOutput, 'no quattro-play beside the program (or no display): ',
        'the Pascal side is a scaffold with no network');
    except
      on EInOutError do ;
    end;
    Result := 69;
    Exit;
  end;
  Data := Arg('--data', Dir);
  SetAssetRoots(Data, QuattroBuild);
  SetLength(Roots, AssetRootCount);
  for I := 0 to AssetRootCount - 1 do Roots[I] := AssetRoot(I);
  Args := QuattroArgs(Dir, Roots, Arg('--level', ''), Arg('--x', '30'), Arg('--y', '30'),
    Server, Arg('--account', ''), Arg('--server-name', FirstServerName), '');
  if HasArg('--seconds') then
  begin
    I := Length(Args);
    SetLength(Args, I + 2);
    Args[I] := '--seconds';
    Args[I + 1] := Arg('--seconds', '');
  end;
  Password := '';
  if Online then Password := GetEnvironmentVariable(Arg('--password-env', 'GRAAL_PW'));
  Result := RunQuattro(Exe, QuattroBuild, Args, Password);
  if Result < 0 then Result := 69;
end;

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
  Halt(RunGame);
end.
