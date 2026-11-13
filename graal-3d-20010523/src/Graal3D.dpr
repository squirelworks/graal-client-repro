{ Graal3D: a rebuild of the Graal3D client of February 2000 (the 3D side
  project with its own server, version string GR3DV003).

  With no arguments it opens the start window, as the original did. With
  arguments it runs one session from the command line:

    Graal3D --server HOST[:PORT] --account NAME [--nick NICK] [--noudp]
    Graal3D --level FILE.x | --offline
  and for either:
    --data DIR       the folder with the player's Graal3D files (default:
                     the program's own folder)
    --window         show the window (default: headless)
    --frames N       stop after N ticks (50 ms each)
    --keys SCRIPT    hold keys from a script, e.g. "fwd*20,jump,say:hi"
    --dump FILE.bmp  write the last frame
    --x/--y/--z      start position offline
  The password comes from the environment variable GRAAL_PW (or the one
  named by --password-env). A JSON summary goes to stdout at the end, the
  log to stderr. }
program Graal3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal3D.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal3D.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils, Classes, GSurface, GFont, GAssetDirs, GStartScreen,
  Window3D, Codec3D, Config3D, Math3D, XFile3D, Render3D, World3D,
  Client3D, Res3D, GUiFont, Connect3D, Builtin3D, Run3D, Overlay3D;

const
  BuildName = 'graal-3d-20010523';
  AssetLabel = '3d';
  TickMs = 50;
  ScreenW = 640;
  ScreenH = 480;
  ChatLineY = ViewH; { the chat edit line sits under the 3D view }
  { TAdventure's and TConnectFrame's captions in Graal3D.exe }
  GameTitle = 'Graal 3D';
  StartTitle = 'Graal 3D';

type
  TOptions = record
    Online: Boolean;
    Host: string;
    Port: Integer;
    Account, Password, Nick: string;
    LevelFile: string;
    NoUdp: Boolean;
    FixedUdpPort: Integer;
    Frames: Integer;
    Keys: string;
    Dump: string;
    StartX, StartY, StartZ: Double;
  end;

  TGame = class
  public
    DataDir: string;
    World: TWorld3D;
    Client: TClient3D;
    Renderer: TRenderer3D;
    Screen: TGSurface;
    Overlay: TOverlay3D;
    ChatText: string;
    ChatFocus: Boolean;
    Message: string;
    UsedBuiltinLevel: Boolean;
    constructor Create(const ADataDir: string);
    destructor Destroy; override;
    function FindFile(const Name: string): string;
    function FindLevel(const Name: string): string;
    procedure LogLine(const S: string);
    procedure DrawScreen;
  end;

var
  Args: TStringList = nil;

function ArgCount: Integer;
begin
  if Args <> nil then Result := Args.Count else Result := ParamCount;
end;

function ArgAt(I: Integer): string;
begin
  if Args <> nil then Result := Args[I - 1] else Result := ParamStr(I);
end;

function HasArg(const Name: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ArgCount do
    if ArgAt(I) = Name then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function Arg(const Name, Def: string): string;
var
  I: Integer;
begin
  for I := 1 to ArgCount - 1 do
    if ArgAt(I) = Name then
    begin
      Result := ArgAt(I + 1);
      Exit;
    end;
  Result := Def;
end;

function NumArg(const Name: string; Def: Double): Double;
var
  Code: Integer;
  S: string;
begin
  S := Arg(Name, '');
  if S = '' then
  begin
    Result := Def;
    Exit;
  end;
  Val(S, Result, Code);
  if Code <> 0 then Result := Def;
end;

function JB(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

{ TGame }

constructor TGame.Create(const ADataDir: string);
begin
  inherited Create;
  DataDir := ADataDir;
  World := TWorld3D.Create;
  World.Models.Find := FindFile;
  Client := TClient3D.Create(World);
  Client.DataDir := DataDir;
  Client.FindLevel := FindLevel;
  Client.Log := LogLine;
  Renderer := TRenderer3D.Create(ViewW, ViewH);
  Renderer.Textures.Find := FindFile;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Overlay := TOverlay3D.Create;
end;

destructor TGame.Destroy;
begin
  Overlay.Free;
  Screen.Free;
  Renderer.Free;
  Client.Free;
  World.Free;
  inherited Destroy;
end;

function TGame.FindFile(const Name: string): string;
var
  N: string;
begin
  { file names come from levels and from other players' props: only the
    bare name is used }
  N := ExtractFileName(StringReplace(Name, '\', '/', [rfReplaceAll]));
  if (N = '') or (N = '.') or (N = '..') then
    Result := ''
  else
    Result := AssetPath(N);
end;

function TGame.FindLevel(const Name: string): string;
begin
  Result := FindFile(Name);
  if Result = '' then
    Result := AssetPath('levels/' + ExtractFileName(Name));
end;

procedure TGame.LogLine(const S: string);
begin
  { started from the start window there is no console: the error output
    is closed, and writing to it stopped the game with "File not open" }
  if TextRec(ErrOutput).Mode <> fmClosed then WriteLn(ErrOutput, S);
end;

procedure TGame.DrawScreen;
var
  I, Y: Integer;
begin
  World.Draw(Renderer);
  Screen.Fill($FF000000);
  Screen.Blit(Renderer.Surface, 0, 0, ViewW, ViewH, 0, 0);
  { the nickname banner and the logo (Overlay3D) }
  Overlay.Load(FindFile);
  Overlay.Draw(Screen, ViewW, World.Me.Nick);
  { the chat log: newest at the bottom left, older lines above }
  Y := ViewH - 5 - 14;
  for I := High(World.Chat) downto 0 do
  begin
    if Y < 0 then Break;
    DrawText(Screen, 5, Y, World.Chat[I].Text, $FFFFFFFF, 2);
    Dec(Y, 16);
  end;
  DrawChatLine(Screen, ChatLineY, ChatText, ChatFocus);
  if Client.AdminMessage <> '' then
    DrawMessageBox(Screen, 'Administrator message', Client.AdminMessage);
end;

function LoadOfflineLevel(G: TGame; const FileName: string): Boolean;
var
  Path: string;
  S: TStringList;
begin
  Path := FileName;
  if (Path <> '') and not FileExists(Path) then Path := G.FindLevel(Path);
  if Path <> '' then
  begin
    S := TStringList.Create;
    try
      S.LoadFromFile(Path);
      Result := G.World.Level.Load(ExtractFileName(Path), S.Text);
    finally
      S.Free;
    end;
    if Result then Exit;
    G.LogLine('cannot read ' + Path + '; using the stand-in level');
  end;
  G.UsedBuiltinLevel := True;
  Result := G.World.Level.Load('builtin.x', BuiltinLevel);
end;

function RunGame(Win: TWindow3D; const O: TOptions; out Msg: string): Integer;
var
  G: TGame;
  Script: TKeyScript;
  Frame, I: Integer;
  Inp: TInput3D;
  St: TStep3D;
  T0, Wait: Int64;
  Chars: string;
  Quit: Boolean;
begin
  Result := 0;
  Msg := '';
  G := TGame.Create(Arg('--data', ExtractFilePath(ParamStr(0))));
  Script := TKeyScript.Create;
  try
    if not Script.Parse(O.Keys) then
    begin
      Msg := 'bad --keys script';
      G.LogLine(Msg);
      Result := 64;
      Exit;
    end;
    G.World.Me.Nick := O.Nick;
    if O.Online then
    begin
      { The beta loads its local world at start and keeps it online (it
        ignores the server's level text). The Genesis3D BSP is not
        reproduced; the stand-in level of the February 2000 rebuild is
        used in its place. }
      if not LoadOfflineLevel(G, O.LevelFile) then
      begin
        Msg := 'Unable to load / create the starting level!';
        G.LogLine(Msg);
        Result := 1;
        Exit;
      end;
      G.World.Me.Level := 'level1.x';
      if not G.Client.Connect(O.Host, O.Port, O.Account, O.Password, O.NoUdp,
        O.FixedUdpPort) then
      begin
        Msg := 'Cannot connect to ' + O.Host + ': ' + G.Client.LastError;
        G.LogLine(Msg);
        Result := 2;
        Exit;
      end;
      G.LogLine(Format('connected to %s:%d, UDP port %d', [O.Host, O.Port, G.Client.UdpPort]));
    end
    else
    begin
      if not LoadOfflineLevel(G, O.LevelFile) then
      begin
        Msg := 'the level did not load';
        G.LogLine(Msg);
        Result := 1;
        Exit;
      end;
      G.World.Me.X := O.StartX;
      G.World.Me.Y := O.StartY;
      G.World.Me.Z := O.StartZ;
      G.World.ResetCamera;
    end;
    Frame := 0;
    Quit := False;
    repeat
      T0 := MonoUs;
      FillChar(Inp, SizeOf(Inp), 0);
      if Win <> nil then
      begin
        Win.Pump;
        if Win.Closed then Break;
        Chars := Win.TakeChars;
        for I := 1 to Length(Chars) do
          if G.Client.AdminMessage <> '' then
          begin
            if Chars[I] in [#13, #27] then G.Client.AdminMessage := '';
          end
          else if G.ChatFocus then
          begin
            case Chars[I] of
              #13:
                begin
                  if G.ChatText <> '' then G.Client.Say(G.ChatText);
                  G.ChatText := '';
                  G.ChatFocus := False;
                end;
              #27: G.ChatFocus := False;
              #8: if G.ChatText <> '' then Delete(G.ChatText, Length(G.ChatText), 1);
            else
              if (Chars[I] >= ' ') and (Chars[I] <= '~') and (Length(G.ChatText) < 200) then
                G.ChatText := G.ChatText + Chars[I];
            end;
          end
          else if Chars[I] = #13 then
            G.ChatFocus := True
          else if Chars[I] = #27 then
            Quit := True;
        if not G.ChatFocus then
        begin
          Inp.Fwd := Win.Held[k3Fwd];
          Inp.Back := Win.Held[k3Back];
          Inp.Left := Win.Held[k3Left];
          Inp.Right := Win.Held[k3Right];
          Inp.Jump := Win.Held[k3Jump];
          Inp.CameraToggle := Win.WasPressed(k3Camera);
        end;
      end;
      if Script.Count > 0 then
      begin
        St := Script.At(Frame);
        Inp.Fwd := Inp.Fwd or St.Fwd;
        Inp.Back := Inp.Back or St.Back;
        Inp.Left := Inp.Left or St.Left;
        Inp.Right := Inp.Right or St.Right;
        Inp.Jump := Inp.Jump or St.Jump;
        Inp.CameraToggle := Inp.CameraToggle or St.Cam;
        if St.Say <> '' then G.Client.Say(St.Say);
      end;
      if O.Online then G.Client.Receive;
      G.World.Step(Inp);
      if O.Online then
      begin
        G.Client.SendProps;
        G.Client.Flush;
        if not G.Client.Connected then
        begin
          Msg := G.Client.DiscMessage;
          if Msg = '' then Msg := 'You have been disconnected from the server.';
          G.LogLine(Msg);
          if not G.Client.LoggedIn then Result := 1;
          Quit := True;
        end;
      end;
      if Win <> nil then
      begin
        G.DrawScreen;
        Win.Present(G.Screen);
      end;
      Inc(Frame);
      if (O.Frames > 0) and (Frame >= O.Frames) then Quit := True;
      if StopRequested then Quit := True;
      if not Quit and ((Win <> nil) or O.Online) then
      begin
        Wait := TickMs - (MonoUs - T0) div 1000;
        if Wait > 0 then Sleep(Wait);
      end;
    until Quit;
    if O.Online and not G.Client.LoggedIn and (Result = 0) then Result := 1;
    if O.Dump <> '' then
    begin
      G.DrawScreen;
      G.Screen.SaveBMP(O.Dump);
    end;
    if Win = nil then
      WriteLn('{"build":', JsonStr(BuildName),
        ',"online":', JB(O.Online),
        ',"loggedIn":', JB(G.Client.LoggedIn),
        ',"playerId":', G.World.Me.Id,
        ',"level":', JsonStr(G.World.Level.Name),
        ',"levelFaces":', Length(G.World.Level.Faces),
        ',"builtinLevel":', JB(G.UsedBuiltinLevel),
        ',"builtinModels":', JB(G.World.Models.UsedBuiltin),
        ',"x":', JsonNum(G.World.Me.X), ',"y":', JsonNum(G.World.Me.Y),
        ',"z":', JsonNum(G.World.Me.Z), ',"angle":', G.World.Me.Angle,
        ',"onGround":', JB(G.World.OnGround),
        ',"others":', Length(G.World.Others),
        ',"udpPort":', G.Client.UdpPort,
        ',"udpIn":', G.Client.UdpIn, ',"udpOut":', G.Client.UdpOut,
        ',"chatLines":', Length(G.World.Chat),
        ',"frames":', Frame,
        ',"facesDrawn":', G.Renderer.FacesDrawn,
        ',"message":', JsonStr(Msg), '}');
    G.Client.Close;
  finally
    Script.Free;
    G.Free;
  end;
end;

procedure Usage;
begin
  WriteLn(ErrOutput, 'Graal3D (graal-delphi rebuild of the February 2000 client)');
  WriteLn(ErrOutput, '  Graal3D                         the start window');
  WriteLn(ErrOutput, '  Graal3D --server HOST[:PORT] --account NAME [--nick NICK] [--noudp]');
  WriteLn(ErrOutput, '  Graal3D --offline | --level FILE.x');
  WriteLn(ErrOutput, '  options: --data DIR --window --frames N --keys SCRIPT --dump FILE.bmp');
  WriteLn(ErrOutput, '  password: GRAAL_PW (or --password-env NAME)');
end;

procedure DefaultOptions(out O: TOptions; const C: TConfig3D);
begin
  O.Online := False;
  O.Host := C.ServerAddr;
  O.Port := C.ServerPort;
  O.Account := C.AccountName;
  O.Password := C.Password;
  O.Nick := 'Stefan';
  O.LevelFile := 'level1.x';
  O.NoUdp := C.NoUdp;
  if C.FixedPort then O.FixedUdpPort := C.FixedUdpPort else O.FixedUdpPort := 0;
  O.Frames := 0;
  O.Keys := '';
  O.Dump := '';
  O.StartX := 0;
  O.StartY := 0;
  O.StartZ := 0;
end;

function RunCommandLine: Integer;
var
  O: TOptions;
  C: TConfig3D;
  Dir, S, Msg: string;
  P: Integer;
  Win: TWindow3D;
begin
  Dir := Arg('--data', ExtractFilePath(ParamStr(0)));
  SetAssetRoots(Dir, AssetLabel);
  DefaultConfig(C);
  LoadConfig(IncludeTrailingPathDelimiter(Dir) + ConfigName, C);
  DefaultOptions(O, C);
  S := Arg('--server', '');
  if S <> '' then
  begin
    O.Online := True;
    P := Pos(':', S);
    if P > 0 then
    begin
      O.Host := Copy(S, 1, P - 1);
      O.Port := StrToIntDef(Copy(S, P + 1, MaxInt), DefaultPort);
    end
    else
    begin
      O.Host := S;
      O.Port := DefaultPort;
    end;
    O.Account := Arg('--account', O.Account);
    O.Password := SysUtils.GetEnvironmentVariable(Arg('--password-env', 'GRAAL_PW'));
    if O.Password = '' then O.Password := C.Password;
  end
  else if not HasArg('--offline') and (Arg('--level', '') = '') then
  begin
    Usage;
    Result := 64;
    Exit;
  end;
  O.Nick := Arg('--nick', O.Nick);
  O.LevelFile := Arg('--level', O.LevelFile);
  if HasArg('--noudp') then O.NoUdp := True;
  O.Frames := StrToIntDef(Arg('--frames', '0'), 0);
  O.Keys := Arg('--keys', '');
  O.Dump := Arg('--dump', '');
  O.StartX := NumArg('--x', 0);
  O.StartY := NumArg('--y', 0);
  O.StartZ := NumArg('--z', 0);
  InstallStopHandlers;
  Win := nil;
  try
    if HasArg('--window') then
    begin
      Win := TWindow3D.Create(GameTitle, ScreenW, ScreenH);
      if not Win.Ok then FreeAndNil(Win);
    end;
    Result := RunGame(Win, O, Msg);
  finally
    Win.Free;
  end;
end;

{ No arguments: the start window, the game it picks, and back to the
  start window when the game ends. As in Graal3D.exe, the start window
  (TConnectFrame, 433 x 321) and the game (TAdventure, 640 x 480) are two
  windows of their own, both titled "Graal 3D": the start window closes
  when the game opens and comes back when it ends. }
function RunGui: Integer;
var
  Win: TWindow3D;
  S: TGSurface;
  F: TConnectForm;
  C: TConfig3D;
  O: TOptions;
  Dir, Msg: string;
  Choice: TConnectChoice;
begin
  Result := 0;
  Dir := ExtractFilePath(ParamStr(0));
  SetAssetRoots(Dir, AssetLabel);
  DefaultConfig(C);
  LoadConfig(Dir + ConfigName, C);
  S := TGSurface.Create(ConnectW, ConnectH);
  Win := nil;
  try
    InstallStopHandlers;
    F.Nick := '';
    F.Host := C.ServerAddr;
    F.Port := IntToStr(C.ServerPort);
    F.Account := C.AccountName;
    F.Password := C.Password;
    F.Message := '';
    F.LogoPath := '';
    repeat
      Win := TWindow3D.Create(StartTitle, ConnectW, ConnectH);
      if not Win.Ok then
      begin
        OpenConsoleIO;
        WriteLn(ErrOutput, 'no display for the start window; run with arguments:');
        Usage;
        Result := 64;
        Exit;
      end;
      Choice := RunConnect(Win, S, F, StopRequested);
      FreeAndNil(Win);
      if (Choice = ccQuit) or StopRequested then Break;
      DefaultOptions(O, C);
      O.Nick := F.Nick;
      if Choice = ccConnect then
      begin
        O.Online := True;
        O.Host := Trim(F.Host);
        O.Port := StrToIntDef(Trim(F.Port), DefaultPort);
        O.Account := F.Account;
        O.Password := F.Password;
        C.ServerAddr := O.Host;
        C.ServerPort := O.Port;
        SaveConfig(Dir + ConfigName, C);
      end;
      Win := TWindow3D.Create(GameTitle, ScreenW, ScreenH);
      Args := TStringList.Create;
      try
        Args.Add('--data');
        Args.Add(Dir);
        if Win.Ok then RunGame(Win, O, Msg);
      finally
        FreeAndNil(Args);
        FreeAndNil(Win);
      end;
      F.Message := Msg;
    until StopRequested;
  finally
    Win.Free;
    S.Free;
  end;
end;

begin
  Randomize;
  if ParamCount = 0 then
    Halt(RunGui);
  OpenConsoleIO;
  Halt(RunCommandLine);
end.
