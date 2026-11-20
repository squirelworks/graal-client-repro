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
    Graal531            the start screen (common/GStartScreen.pas): Training
                        or a server from the listserver, played in
                        quattro-play; back to the start screen when the
                        game ends. With no display it exits 64.
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

{ The start screen borrows 5.24r4's list step and character drawing: 5.31r4
  reaches its servers through the same Login server, which the rebuild
  replaces with a Seihai listserver (ListServer524r4). }
uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GBzip2 in '../../common/GBzip2.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GQuattroPlay in '../../common/GQuattroPlay.pas',
  GAni in '../../common/GAni.pas',
  GFont in '../../common/GFont.pas',
  GWindow in '../../common/GWindow.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  Protocol524r4 in '../../graal-5.24r4-G3D15010/src/Protocol524r4.pas',
  GraalClient in '../../graal-5.24r4-G3D15010/src/GraalClient.pas',
  Adventure in '../../graal-5.24r4-G3D15010/src/Adventure.pas',
  ListServer524r4 in '../../graal-5.24r4-G3D15010/src/ListServer524r4.pas',
  StartScreen524r4 in '../../graal-5.24r4-G3D15010/src/StartScreen524r4.pas',
  RunMode in '../../graal-5.24r4-G3D15010/src/RunMode.pas',
  Late531 in 'Late531.pas';

const
  { the quattro-play row (common/cpp/quattro/net/profile.cpp) }
  QuattroBuild = '5.31r4';
  { the name 5.31r4 gives the first server it reaches, as 5.24r4 does }
  FirstServerName531 = 'Login';

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
    Server, Arg('--account', ''), Arg('--server-name', FirstServerName531), '');
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

{ Training's level: the install's offline tutorial, else its start.nw. }
procedure TrainingLevel(const Dir: string; out Path, X, Y: string);
begin
  X := '30';
  Y := '30';
  Path := FirstFileIn(Dir, 'levels/offlinetutorial_b-2.nw;levels/offlinetutorial_b-2.graal;' +
    'offlinetutorial_b-2.nw;offlinetutorial_b-2.graal');
  if Path = '' then Path := InstallPath(Dir, 'start.nw');
end;

{ No arguments: the start screen, then the game it picks in quattro-play,
  and back to the start screen when the game ends. }
function RunGui: Integer;
var
  Win: TGWindow;
  G: TAdventure;
  R: TStartResult;
  Dir, ListHost, Msg, Lvl, X, Y, Exe, PickedName: string;
  ListPort, Code, I: Integer;
  Picked: Boolean;
  Fetch: TListFetch524r4;
  Info: TStartInfo;
  Who: TCharacter524r4;
  Roots: array of string;
  Args: TQuattroArgs;
begin
  Result := 0;
  Dir := ExtractFilePath(ParamStr(0));
  Win := TGWindow.Create('Graal ' + BuildLabel531 + ' (' + Late531.ClientVersionToken + ')', ScreenW, ScreenH);
  try
    if not Win.Ok then
    begin
      OpenConsoleIO;
      try
        WriteLn(ErrOutput, 'no display for the start screen; run with --server or --level');
      except
        on EInOutError do ;
      end;
      Result := 64;
      Exit;
    end;
    InstallStopHandlers;
    ReadListServer(Dir, DefaultListHost, DefaultListPort, ListHost, ListPort);
    FillChar(R, SizeOf(R), 0);
    Msg := '';
    repeat
      Win.TakeChars;
      G := TAdventure.Create;
      Fetch := TListFetch524r4.Create;
      Who := TCharacter524r4.Create;
      try
        G.UseInstall(Dir);
        Who.G := G;
        Info.Title := 'graal-delphi';
        Info.Subtitle := '5.31r4 rebuilt';
        Info.DrawCharacter := Who.Draw;
        Info.StopRequested := StopRequested;
        Picked := RunStartScreen(Win, G.Screen, Fetch, Info, Dir, ListHost, ListPort, Msg, R);
        PickedName := FirstServerName531;
        if Picked and (R.Choice = scOnline) then
          for I := 0 to High(Fetch.Servers) do
            if (Fetch.Servers[I].Host = R.Host) and (Fetch.Servers[I].Port = R.Port) then
            begin
              PickedName := ServerDisplayName(Fetch.Servers[I].Name);
              Break;
            end;
      finally
        Who.Free;
        Fetch.Free;
        G.Free;
      end;
      if not Picked or Win.Closed or StopRequested then Exit;
      Exe := QuattroProgram(Dir, R.Choice = scOnline);
      if Exe = '' then
      begin
        Msg := 'no quattro-play beside the program';
        Continue;
      end;
      SetAssetRoots(Dir, QuattroBuild);
      SetLength(Roots, AssetRootCount);
      for I := 0 to AssetRootCount - 1 do Roots[I] := AssetRoot(I);
      if R.Choice = scTraining then
      begin
        TrainingLevel(Dir, Lvl, X, Y);
        Args := QuattroArgs(Dir, Roots, Lvl, X, Y, '', '', '', '');
      end
      else
        Args := QuattroArgs(Dir, Roots, '', '', '', R.Host + ':' + IntToStr(R.Port), R.Account,
          PickedName, R.Nickname);
      Code := RunQuattro(Exe, QuattroBuild, Args, R.Password);
      if Code <> 0 then
        Msg := 'the game ended with code ' + IntToStr(Code)
      else
        Msg := '';
    until Win.Closed or StopRequested;
  finally
    Win.Free;
  end;
end;

begin
  if ParamCount = 0 then Halt(RunGui);
  OpenConsoleIO;
  if (ParamCount = 1) and (ParamStr(1) = '--show') then
  begin
    WriteLn(FileVersion530, ' ', BuildLabel530);
    WriteLn(FileVersion531, ' ', BuildLabel531);
    WriteLn(EngineLibrary);
    WriteLn('torque=', LowerCase(BoolToStr(LinksTorque, True)));
    WriteLn('processes=', ProcessCount);
    WriteLn('port=', BakedLoginPort);
    WriteLn('stored=', TokenLiteral);
    WriteLn('sends=', Late531.ClientVersionToken);
    Exit;
  end;
  Halt(RunGame);
end.
