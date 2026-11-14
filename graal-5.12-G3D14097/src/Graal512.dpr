{ Graal 5.12 (G3D14097), rebuilt. The original is a Delphi launcher over
  a C++ engine library for Windows; this rebuild carries the 3.153 one
  over, since 5.12 keeps the gen-5 wire (graal_analysis
  protocol/v5x-clients.md).

  Command line:
    Graal512 --server HOST:PORT --account NAME [--password-env VAR]
             [--server-name NAME]
    Graal512 --level FILE.graal|FILE.nw|FILE.gmap [--x X --y Y]
  --server-name: what the client calls that server (default Login, as
  5.12 calls the first server it reaches: no characters are drawn until
  a server warp (178) names another).
  common options:
    --data DIR        a Graal install: pics1, arrays.dat, levels/ganis, heads,
                      bodies, swords, shields, hats
    --window          show the game in a window and read the keyboard
                      (arrows or IJKL walk, Esc quits)
    --headless        no drawing at all (stress runs)
    --frames N        stop after N frames; 0 = until stopped (default: 100
                      without a window or --seconds, no limit in a window)
    --seconds N       stop after N seconds
    --keys SCRIPT     scripted keys, e.g. "right*10,down*4,wait*5"; each
                      entry holds one direction for that many frames
    --walk MODE       script (default with --keys), idle (default without),
                      or random
    --walk-ms N       random walk: a new direction every N ms (default 100)
    --seed N          random walk seed
    --link-every N    random walk: every N seconds head for the nearest link
    --nodelay         set TCP_NODELAY (5.12's setting is not traced)
    --stats-every N   a JSON stats line on stdout every N seconds
    --dump FRAME.bmp  write the last frame
    --sheet FILE      a tile sheet other than the install's pics1

  Log lines go to stderr as they happen. Online, one JSON summary line goes
  to stdout at the end. SIGTERM / SIGINT (Ctrl+Break / Ctrl+C on Windows)
  end the run cleanly.

  Exit codes, online: 0 logged in and ended cleanly, 1 error, 2 never
  logged in, 3 the link dropped after login. Offline: 0 the level parsed,
  1 it did not. 64: bad command line. }
program Graal512;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{ A windowed program on Windows, like 2.05: started with no arguments it
  opens the start screen. With arguments it attaches to the console it was
  started from (OpenConsoleIO) and runs as before. }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal512.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal512.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

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
  GAni in '../../common/GAni.pas',
  GFont in '../../common/GFont.pas',
  GSound in '../../common/GSound.pas',
  GWindow in '../../common/GWindow.pas',
  GEngineHost in '../../common/GEngineHost.pas',
  Protocol512 in 'Protocol512.pas',
  GraalClient in 'GraalClient.pas',
  Adventure in 'Adventure.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  ListServer512 in 'ListServer512.pas',
  StartScreen512 in 'StartScreen512.pas',
  RunMode in 'RunMode.pas',
  GUiFont in '../../common/GUiFont.pas',
  PlayerList512 in 'PlayerList512.pas',
  Tray512 in 'Tray512.pas';

var
  { Set while the start screen runs a game: the arguments it chose, read
    in place of the command line. }
  GuiArgs: TStringList = nil;
  { why the last game ended, for the start screen }
  LastGameError: string = '';

function ArgCount: Integer;
begin
  if GuiArgs <> nil then Result := GuiArgs.Count else Result := ParamCount;
end;

function ArgAt(I: Integer): string;
begin
  if GuiArgs <> nil then Result := GuiArgs[I - 1] else Result := ParamStr(I);
end;

function Arg(const Name, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  for I := 1 to ArgCount - 1 do
    if ArgAt(I) = Name then
    begin
      Result := ArgAt(I + 1);
      Exit;
    end;
end;

function HasArg(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ArgCount do
    if ArgAt(I) = Name then Result := True;
end;


procedure Usage;
begin
  WriteLn('Graal ', ClientBuildLabel, ' (', ClientVersionToken, ') rebuild');
  WriteLn('  (no arguments: the start screen, Training or the server list)');
  WriteLn('  --server HOST:PORT --account NAME [--password-env VAR] [--server-name NAME]');
  WriteLn('  --level FILE [--x X --y Y]');
  WriteLn('  --engine [--engine-lib FILE] [--window] [--frames N] [--connect NAME@HOST:PORT]');
  WriteLn('           [--players-log] [--players-dump LIST.bmp]');
  WriteLn('  common: [--data DIR] [--window | --headless] [--frames N] [--seconds N]');
  WriteLn('          [--keys SCRIPT] [--walk script|idle|random] [--walk-ms N] [--seed N]');
  WriteLn('          [--link-every N] [--nodelay] [--stats-every N]');
  WriteLn('          [--dump FRAME.bmp] [--sheet FILE]');
end;

const
  { --keys entries for the game keys (a, s, d, q), beside the directions }
  ScriptKeyA = 10;
  ScriptKeyS = 11;
  ScriptKeyD = 12;
  ScriptKeyQ = 13;

type
  TKeyScript = class
  public
    Dirs: array of Integer;  { -1 = no key }
    procedure Parse(const S: string);
    function DirAt(Frame: Integer): Integer;
  end;

procedure TKeyScript.Parse(const S: string);
var
  Items: TStringList;
  I, J, N, D, Star: Integer;
  Name: string;
begin
  Items := TStringList.Create;
  try
    Items.CommaText := S;
    for I := 0 to Items.Count - 1 do
    begin
      Star := Pos('*', Items[I]);
      if Star > 0 then
      begin
        Name := LowerCase(Copy(Items[I], 1, Star - 1));
        N := StrToIntDef(Copy(Items[I], Star + 1, MaxInt), 1);
      end
      else
      begin
        Name := LowerCase(Items[I]);
        N := 1;
      end;
      if Name = 'up' then D := DirUp
      else if Name = 'left' then D := DirLeft
      else if Name = 'down' then D := DirDown
      else if Name = 'right' then D := DirRight
      else if Name = 'a' then D := ScriptKeyA
      else if Name = 's' then D := ScriptKeyS
      else if Name = 'd' then D := ScriptKeyD
      else if Name = 'q' then D := ScriptKeyQ
      else D := -1;
      for J := 1 to N do
      begin
        SetLength(Dirs, Length(Dirs) + 1);
        Dirs[High(Dirs)] := D;
      end;
    end;
  finally
    Items.Free;
  end;
end;

function TKeyScript.DirAt(Frame: Integer): Integer;
begin
  if (Frame >= 0) and (Frame <= High(Dirs)) then Result := Dirs[Frame]
  else Result := -1;
end;

{ The middle and largest of the first N warp times. }
procedure WarpStats(G: TAdventure; out P50, Max: Integer);
var
  A: array of Integer;
  I, J, T: Integer;
begin
  P50 := 0;
  Max := 0;
  if G.WarpCount = 0 then Exit;
  SetLength(A, G.WarpCount);
  for I := 0 to G.WarpCount - 1 do A[I] := G.WarpTimes[I];
  for I := 1 to High(A) do
  begin
    T := A[I];
    J := I - 1;
    while (J >= 0) and (A[J] > T) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := T;
  end;
  P50 := A[High(A) div 2];
  Max := A[High(A)];
end;

function StatsJson(const Kind, EndState, Error, Account: string; G: TAdventure;
  H: TTickHistogram; Ticks: Integer; RunUs: Int64; NoDelay: Boolean): string;
var
  WP50, WMax: Integer;
  Login: string;
begin
  WarpStats(G, WP50, WMax);
  if G.LoginMs >= 0 then Login := IntToStr(G.LoginMs) else Login := 'null';
  Result := '{"kind":' + JsonStr(Kind) +
    ',"version":' + JsonStr(ClientBuildLabel) +
    ',"token":' + JsonStr(ClientVersionToken) +
    ',"account":' + JsonStr(Account);
  if EndState <> '' then
    Result := Result + ',"end":' + JsonStr(EndState) + ',"error":' + JsonStr(Error);
  Result := Result +
    ',"login_ms":' + Login +
    ',"run_s":' + JsonMs(RunUs / 1000000.0) +
    ',"ticks":' + IntToStr(Ticks) +
    ',"frames_in":' + IntToStr(G.Client.FramesIn) +
    ',"frames_out":' + IntToStr(G.Client.FramesOut) +
    ',"msgs_in":' + IntToStr(G.Client.MessagesIn) +
    ',"msgs_out":' + IntToStr(G.Client.MessagesOut) +
    ',"bytes_in":' + IntToStr(G.Client.BytesIn) +
    ',"bytes_out":' + IntToStr(G.Client.BytesOut) +
    ',"warps":' + IntToStr(G.WarpsSent) +
    ',"warps_done":' + IntToStr(G.WarpCount) +
    ',"warp_ms_p50":' + IntToStr(WP50) +
    ',"warp_ms_max":' + IntToStr(WMax) +
    ',"tick_ms_p50":' + JsonMs(H.QuantileMs(0.5)) +
    ',"tick_ms_p99":' + JsonMs(H.QuantileMs(0.99)) +
    ',"tick_ms_max":' + JsonMs(H.MaxMs) +
    ',"rss_peak_kib":';
  if PeakRssKiB >= 0 then Result := Result + IntToStr(PeakRssKiB)
  else Result := Result + 'null';
  Result := Result + ',"nodelay":' + LowerCase(BoolToStr(NoDelay, True)) + '}';
end;

{ One game: from the command line, or as the start screen chose it (then
  GuiWin is the window to play in, and nothing goes to stdout). Returns
  the exit code. }
function RunGame(GuiWin: TGWindow; const GuiPw, GuiNick: string): Integer;
var
  G: TAdventure;
  Win: TGWindow;
  Script: TKeyScript;
  Walker: TWalker;
  Hist: TTickHistogram;
  Server, Host, Sheet, Dump, Pw, Data, Account, WalkName, EndState, Error: string;
  Port, Frames, I, C, D, Seconds, StatsEvery, ExitCode_: Integer;
  OK, Online, UseWindow, NoDelay, Dropped, Crashed: Boolean;
  StartUs, GateUs, NowUs, T0, NextStatsUs: Int64;
  WasHeld: array[0..3] of Boolean;

begin
  Result := 64;
  ExitCode_ := 64;
  Server := Arg('--server', '');
  if (Server = '') and (Arg('--level', '') = '') then
  begin
    Usage;
    Exit;
  end;
  Online := Server <> '';
  UseWindow := HasArg('--window') and not HasArg('--headless');
  NoDelay := HasArg('--nodelay');
  Account := Arg('--account', '');
  InstallStopHandlers;
  G := TAdventure.Create;
  G.ServerName := Arg('--server-name', FirstServerName);
  G.Echo := GuiWin = nil;
  G.Headless := HasArg('--headless');
  if GuiNick <> '' then G.Player.Nickname := GuiNick;
  Win := GuiWin;
  Script := TKeyScript.Create;
  Walker := TWalker.Create(Cardinal(StrToIntDef(Arg('--seed', '1'), 1)));
  Hist := TTickHistogram.Create;
  Dropped := False;
  Crashed := False;
  Error := '';
  I := 0;
  StartUs := MonoUs;
  try
    Sheet := Arg('--sheet', '');
    if Sheet <> '' then
      if LoadImageFile(Sheet, G.Sheet) then
        G.SheetBuiltin := False
      else
        G.Log('warning: cannot load tile sheet ' + Sheet + '; using the built-in one');
    Data := Arg('--data', '');
    { no --data: the program's folder (and a graal-assets beside it) }
    if Data = '' then Data := ExtractFilePath(ParamStr(0));
    G.UseInstall(Data);
    Script.Parse(Arg('--keys', ''));
    if Arg('--keys', '') <> '' then WalkName := Arg('--walk', 'script')
    else WalkName := Arg('--walk', 'idle');
    WalkName := LowerCase(WalkName);
    if WalkName = 'random' then Walker.Mode := wmRandom
    else if WalkName = 'idle' then Walker.Mode := wmIdle
    else Walker.Mode := wmScript;
    Walker.WalkTicks := StrToIntDef(Arg('--walk-ms', '100'), 100) div TickMs;
    if Walker.WalkTicks < 1 then Walker.WalkTicks := 1;
    Walker.LinkEveryTicks := StrToIntDef(Arg('--link-every', '0'), 0) * 1000 div TickMs;
    Dump := Arg('--dump', '');
    Seconds := StrToIntDef(Arg('--seconds', '0'), 0);
    StatsEvery := StrToIntDef(Arg('--stats-every', '0'), 0);
    if HasArg('--frames') then Frames := StrToIntDef(Arg('--frames', '0'), 0)
    else if UseWindow or (Seconds > 0) then Frames := 0
    else Frames := 100;
    OK := False;

    if Online then
    begin
      C := Pos(':', Server);
      if C > 0 then
      begin
        Host := Copy(Server, 1, C - 1);
        Port := StrToIntDef(Copy(Server, C + 1, MaxInt), 14802);
      end
      else
      begin
        Host := Server;
        Port := 14802;
      end;
      if GuiWin <> nil then Pw := GuiPw
      else Pw := SysUtils.GetEnvironmentVariable(Arg('--password-env', 'GRAAL_PW'));
      if G.ConnectServer(Host, Port, Account, Pw) then
      begin
        if NoDelay and not G.Client.Socket.SetNoDelay(True) then
          G.Log('warning: TCP_NODELAY could not be set');
      end
      else
      begin
        Error := G.Client.LastError;
        Frames := -1;
      end;
    end
    else
    begin
      OK := G.LoadLevelFile(Arg('--level', ''));
      if OK then
      begin
        G.Player.X := StrToFloatDef(Arg('--x', '30'), 30);
        G.Player.Y := StrToFloatDef(Arg('--y', '30'), 30);
        G.Log(Format('%s: %s, %d links, %d signs, %d chests, %d npcs, %d baddies',
          [G.Level.Name, G.Level.Magic, Length(G.Level.Links), Length(G.Level.Signs),
           Length(G.Level.Chests), Length(G.Level.NPCs), Length(G.Level.Baddies)]));
      end
      else
      begin
        G.Log('level failed: ' + G.Level.LastError);
        Frames := -1;
      end;
    end;

    if UseWindow and (Frames >= 0) and (Win = nil) then
    begin
      Win := TGWindow.Create('Graal ' + ClientBuildLabel + ' (' + ClientVersionToken + ')',
        ScreenW, ScreenH);
      if not Win.Ok then
      begin
        G.Log('no display: running without a window');
        FreeAndNil(Win);
      end;
    end;

    { sound only with a window to play in }
    if Win <> nil then SoundEnabled := True;
    FillChar(WasHeld, SizeOf(WasHeld), 0);
    { the frame loop: a 50 ms gate; a late frame is not made up }
    StartUs := MonoUs;
    GateUs := StartUs;
    NextStatsUs := StartUs + Int64(StatsEvery) * 1000000;
    try
      while Frames >= 0 do
      begin
        if StopRequested then
        begin
          G.Log('stop requested');
          Break;
        end;
        if (Frames > 0) and (I >= Frames) then Break;
        if (Seconds > 0) and (MonoUs - StartUs >= Int64(Seconds) * 1000000) then Break;
        for D := 0 to 3 do G.Keys[D] := False;
        G.AttackHeld := False;
        if Win <> nil then
        begin
          Win.Pump;
          if Win.Closed or Win.Held[gkEscape] then Break;
          G.Keys[DirUp] := Win.Held[gkUp];
          G.Keys[DirLeft] := Win.Held[gkLeft];
          G.Keys[DirDown] := Win.Held[gkDown];
          G.Keys[DirRight] := Win.Held[gkRight];
          { A, S, D and Q go in on the press; S is also held for the
            lay mode (A with S held) }
          G.ActionKey := Win.Held[gkAction] and not WasHeld[0];
          G.AttackKey := Win.Held[gkAttack] and not WasHeld[1];
          G.ItemKey := Win.Held[gkItem] and not WasHeld[2];
          G.ItemListKey := Win.Held[gkItemList] and not WasHeld[3];
          G.AttackHeld := Win.Held[gkAttack];
          WasHeld[0] := Win.Held[gkAction];
          WasHeld[1] := Win.Held[gkAttack];
          WasHeld[2] := Win.Held[gkItem];
          WasHeld[3] := Win.Held[gkItemList];
        end;
        if Walker.Mode = wmScript then D := Script.DirAt(I)
        else D := Walker.DirAt(I, G.Level, G.Player.X, G.Player.Y);
        case D of
          DirUp..DirRight: G.Keys[D] := True;
          ScriptKeyA: G.ActionKey := True;
          ScriptKeyS: G.AttackKey := True;
          ScriptKeyD: G.ItemKey := True;
          ScriptKeyQ: G.ItemListKey := True;
        end;
        T0 := MonoUs;
        G.Tick;
        Hist.Add(MonoUs - T0);
        if Win <> nil then Win.Present(G.Screen);
        Inc(I);
        if Online and not G.Client.Connected then
        begin
          Dropped := True;
          Error := G.Client.LastError;
          if Error = '' then Error := G.DisconnectReason;
          Break;
        end;
        NowUs := MonoUs;
        if (StatsEvery > 0) and (NowUs >= NextStatsUs) and (GuiWin = nil) then
        begin
          WriteLn(StatsJson('stats', '', '', Account, G, Hist, I, NowUs - StartUs, NoDelay));
          Flush(Output);
          Inc(NextStatsUs, Int64(StatsEvery) * 1000000);
        end;
        Inc(GateUs, TickMs * 1000);
        if GateUs > NowUs then
          Sleep((GateUs - NowUs) div 1000)
        else if NowUs - GateUs > 1000000 then
          GateUs := NowUs; { a stall is one frame }
      end;
    except
      on E: Exception do
      begin
        Crashed := True;
        Error := E.ClassName + ': ' + E.Message;
        G.Log('error: ' + Error);
      end;
    end;

    if Online then
    begin
      { a clean logout: what is queued goes out, then the link closes }
      G.Client.Flush;
      G.Client.Disconnect;
      OK := G.LoggedIn and G.BoardLoaded;
      G.Log(Format('frames in %d (%d msgs), out %d (%d msgs); logged in %s, board %s',
        [G.Client.FramesIn, G.Client.MessagesIn, G.Client.FramesOut,
         G.Client.MessagesOut, BoolToStr(G.LoggedIn, True),
         BoolToStr(G.BoardLoaded, True)]));
    end;
    if (Dump <> '') or ((I = 0) and not Online) then
      G.Draw;
    G.Log(Format('player at %.2f,%.2f facing %d', [G.Player.X, G.Player.Y, G.Player.Dir]));
    for C := 0 to G.OtherCount - 1 do
      G.Log(Format('other player %d %s at %.1f,%.1f sprite %d', [G.Others[C].Id,
        G.Others[C].Nickname, G.Others[C].X, G.Others[C].Y, G.Others[C].Sprite]));
    if G.Assets.Missing.Count > 0 then
      G.Log('not found in the install: ' + G.Assets.Missing.CommaText);
    if Dump <> '' then
    begin
      G.Screen.SaveBMP(Dump);
      G.Log('frame written to ' + Dump);
    end;

    if Online then
    begin
      if Crashed then begin EndState := 'error'; ExitCode_ := 1; end
      else if not OK then begin EndState := 'nologin'; ExitCode_ := 2; end
      else if Dropped then begin EndState := 'dropped'; ExitCode_ := 3; end
      else begin EndState := 'clean'; ExitCode_ := 0; end;
      if GuiWin = nil then
        WriteLn(StatsJson('summary', EndState, Error, Account, G, Hist, I,
          MonoUs - StartUs, NoDelay));
      if Error <> '' then LastGameError := Error
      else if not OK then LastGameError := 'the server did not log you in'
      else LastGameError := '';
    end
    else if OK and not Crashed then ExitCode_ := 0
    else ExitCode_ := 1;
  finally
    if Win <> GuiWin then Win.Free;
    Script.Free;
    Walker.Free;
    SoundShutdown;
    Hist.Free;
    G.Free;
  end;
  Result := ExitCode_;
end;

{ Training. Whether 5.12 has offline play at all is not traced (its
  start goes to the Login server). The rebuild keeps 3.153's Training:
  the offline tutorial levels (offlinetutorial_b-2 at 30, 30) when they lie
  in the install, else the built-in starter level (a start.nw next to the
  program replaces it), so a level can be walked without a server. }
procedure TrainingLevel(const Dir: string; out Path, X, Y: string);
begin
  X := '30';
  Y := '30';
  Path := FirstFileIn(Dir, 'levels/offlinetutorial_b-2.nw;levels/offlinetutorial_b-2.graal;offlinetutorial_b-2.nw;offlinetutorial_b-2.graal');
  if Path = '' then
  begin
    Path := InstallPath(Dir, 'start.nw');
    X := '30';
    Y := '30';
  end;
end;

{ No arguments: the start screen, then the game it picks, and back to the
  start screen when the game ends (Esc, or a failed or dropped login). }
function RunGui: Integer;
var
  Win: TGWindow;
  G: TAdventure;
  R: TStartResult;
  Dir, ListHost, ArrHost, Msg, Lvl, X, Y: string;
  ListPort: Integer;
  Picked: Boolean;
  Fetch: TListFetch512;
  Info: TStartInfo;
  Who: TCharacter512;
  PickedName: string;
  I: Integer;
begin
  Result := 0;
  Dir := ExtractFilePath(ParamStr(0));
  Win := TGWindow.Create('Graal ' + ClientBuildLabel + ' (' + ClientVersionToken + ')',
    ScreenW, ScreenH);
  try
    if not Win.Ok then
    begin
      OpenConsoleIO;
      WriteLn(ErrOutput, 'no display for the start screen; run with arguments:');
      Usage;
      Result := 64;
      Exit;
    end;
    { 5.12 has no listserver; the rebuild's list comes from
      listserver.txt next to the program, or listserver.graal.in:14922 }
    { SIGTERM / Ctrl+C end the program on the start screen too }
    InstallStopHandlers;
    SetAssetRoots(Dir, ClientBuildLabel);
    ReadListServer(Dir, DefaultListHost, DefaultListPort, ListHost, ListPort);
    FillChar(R, SizeOf(R), 0);
    Msg := '';
    repeat
      Win.TakeChars;
      G := TAdventure.Create;
      Fetch := TListFetch512.Create;
      Who := TCharacter512.Create;
      try
        G.UseInstall(Dir);
        Who.G := G;
        Info.Title := 'graal-delphi';
        Info.Subtitle := '5.12 rebuilt';
        Info.DrawCharacter := Who.Draw;
        Info.StopRequested := StopRequested;
        Picked := RunStartScreen(Win, G.Screen, Fetch, Info, Dir, ListHost, ListPort, Msg, R);
        { the picked server's name, as if the Login server had warped
          there; a server not on the list is the Login server }
        PickedName := FirstServerName;
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
      GuiArgs := TStringList.Create;
      try
        GuiArgs.Add('--window');
        GuiArgs.Add('--data');
        GuiArgs.Add(Dir);
        if R.Choice = scTraining then
        begin
          TrainingLevel(Dir, Lvl, X, Y);
          GuiArgs.Add('--level');
          GuiArgs.Add(Lvl);
          GuiArgs.Add('--x');
          GuiArgs.Add(X);
          GuiArgs.Add('--y');
          GuiArgs.Add(Y);
        end
        else
        begin
          GuiArgs.Add('--server');
          GuiArgs.Add(R.Host + ':' + IntToStr(R.Port));
          GuiArgs.Add('--account');
          GuiArgs.Add(R.Account);
          GuiArgs.Add('--server-name');
          GuiArgs.Add(PickedName);
        end;
        LastGameError := '';
        if RunGame(Win, R.Password, R.Nickname) <> 0 then
          Msg := LastGameError
        else
          Msg := '';
      finally
        FreeAndNil(GuiArgs);
      end;
    until Win.Closed or StopRequested;
  finally
    Win.Free;
  end;
end;

{ The game window's title: "G r a a l" with eight spaces spread at random
  before and after it, as the 4.x and 5.x launchers set it (the 5.12 lab
  run saw the spaced-out title; version-profiles/lab-v5-2026-10-30.md). }
function PaddedTitle: string;
var
  I: Integer;
begin
  I := Random(9);
  Result := StringOfChar(' ', I) + 'G r a a l' + StringOfChar(' ', 8 - I);
end;

{ A server's name as the 5.12 window shows it once logged in there: each
  character followed by a space ("L a b   S e r v e r", the 5.12 lab run
  of 2026-10-30 after the warp to "Lab Server"). }
function SpacedTitle(const Name: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Name) do
  begin
    if I > 1 then Result := Result + ' ';
    Result := Result + Name[I];
  end;
end;

{ Graal512 --engine: the launcher over the rebuilt engine library
  (common/cpp/graalengine, plan Track C3). The real 5.12 is the 5.0
  launcher over GraalEngine.dll: the launcher owns the window, registers
  the 5.0 set of draw callbacks, calls graal_engineInitialize and
  loadGraalGui, then calls renderGraalCanvas from its frame method and
  forwards keys (Graal_analysis torque/5007-launcher.md). This does the
  same through GEngineHost, as the 4.04r2 launcher does, and tells the
  library it is 5.12 (the 5.12 wire row and the 5.0 GS2 profile). The
  menus are the install's own, run on the GS2 machine; Start logs in
  through the library's session.
  Options: --engine-lib FILE, --window, --frames N, --dump FRAME.bmp,
  --connect NAME@HOST:PORT, --players-log (the player list at the end),
  --players-dump LIST.bmp (the Players window at the end). }
type
  { Heads for the Players window, read once each from the install and
    graal-assets (as the engine's session finds them, downloads included). }
  THeadCache = class
  private
    FNames: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const Name: string): TGSurface;
  end;

constructor THeadCache.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FNames.CaseSensitive := False;
  FNames.OwnsObjects := True;
end;

destructor THeadCache.Destroy;
begin
  FNames.Free;
  inherited;
end;

function THeadCache.Find(const Name: string): TGSurface;
var
  I: Integer;
  P: string;
  S: TGSurface;
begin
  I := FNames.IndexOf(Name);
  if I >= 0 then
  begin
    Result := TGSurface(FNames.Objects[I]);
    Exit;
  end;
  Result := nil;
  if (Pos('/', Name) > 0) or (Pos('\', Name) > 0) or (Pos('..', Name) > 0) then Exit;
  P := AssetPath('levels/heads/' + Name);
  if P = '' then P := AssetPath('levels/images/downloads/' + Name);
  if P = '' then P := AssetPath('levels/' + Name);
  if P = '' then P := AssetPath(Name);
  S := nil;
  if P <> '' then
  begin
    S := TGSurface.Create(1, 1);
    if not LoadImageFile(P, S) then FreeAndNil(S);
  end;
  { a miss is kept too, so it is not looked for every frame; the engine
    may download the file later, so a miss is forgotten when the list
    changes }
  FNames.AddObject(Name, S);
  Result := S;
end;

function RunEngine: Integer;
const
  { The 5.12 game window: 800 x 600 inside the frame (measured on the lab's
    5.12 screenshot, 2026-10-30), where the stand-in keeps 640 x 480. }
  EngineW = 800;
  EngineH = 600;
  ArrowVK: array[0..3] of Integer = ($26, $25, $28, $27);
  ArrowKey: array[0..3] of TGKey = (gkUp, gkLeft, gkDown, gkRight);
var
  Host: TEngineHost;
  Win, Players: TGWindow;
  ListPic: TGSurface;
  Heads: THeadCache;
  Tray: Boolean;
  Lib, Dump, Target, Chars, Titled: string;
  Frames, I, K, X, Y, At, Colon, LogSeen, ListSeen: Integer;
  Was: array[0..4] of Boolean;
  NextUs: Int64;
begin
  Result := 1;
  Lib := Arg('--engine-lib', ExtractFilePath(ParamStr(0)) + EngineLibName);
  Dump := Arg('--dump', '');
  if HasArg('--frames') then Frames := StrToIntDef(Arg('--frames', '0'), 0)
  else if HasArg('--window') then Frames := 0
  else Frames := 1;
  Win := nil;
  Players := nil;
  Tray := False;
  ListPic := TGSurface.Create(PlayerListW, PlayerListH);
  Heads := THeadCache.Create;
  SetAssetRootsFor(ExtractFilePath(ParamStr(0)), Arg('--data', ''), ClientBuildLabel);
  Host := TEngineHost.Create(EngineW, EngineH);
  try
    if not Host.Load(Lib) then
    begin
      WriteLn(Host.Error);
      Exit;
    end;
    Host.RegisterSlots(EngineBuild50);
    if not Host.SetBuild(ClientBuildLabel) then
      WriteLn('engine library has no ', ClientBuildLabel, ' build; it runs as its default');
    if Host.Missing.Count > 0 then
      WriteLn('engine slots with no launcher function: ', Host.Missing.CommaText);
    if not Host.Initialize(ParamStr(0)) then
    begin
      { the original's warning when the engine refuses to start }
      WriteLn('The execution file could not be started. Check it with your virus checker and drivers.');
      Exit;
    end;
    Host.LoadGui;
    Target := Arg('--connect', '');
    if Target <> '' then
    begin
      At := LastDelimiter('@', Target);
      Colon := LastDelimiter(':', Target);
      if (At > 0) and (Colon > At) then
        Host.Connect(AnsiString(Copy(Target, 1, At - 1)), AnsiString(Copy(Target, At + 1, Colon - At - 1)),
          StrToIntDef(Copy(Target, Colon + 1, MaxInt), 0));
    end
    else
      { 5.12's engine has no main-menu script: the launcher's own window is
        the menu, and the client goes to the Login server (the licence's
        first host) as guest, whose scripted lists come next. }
      Host.OpenServerList;
    if HasArg('--window') then
    begin
      Win := TGWindow.Create(PaddedTitle, EngineW, EngineH);
      if not Win.Ok then FreeAndNil(Win);
      { the launcher's Players window (TPlayerList) and its tray icon; both
        windows start shown, as the tray menu's two check marks say }
      if Win <> nil then
      begin
        GWindowClass := 'TPlayerList';
        Players := TGWindow.Create(PlayerListTitle(0), PlayerListW, PlayerListH);
        GWindowClass := 'TGraalWindow';
        if not Players.Ok then FreeAndNil(Players);
        Tray := TrayStart('Graal');
      end;
    end;
    ListSeen := -1;
    Titled := '';
    FillChar(Was, SizeOf(Was), 0);
    LogSeen := 0;
    I := 0;
    NextUs := MonoUs;
    while (Frames = 0) or (I < Frames) do
    begin
      if StopRequested then Break;
      if Win <> nil then
      begin
        Win.Pump;
        if Win.Closed then Break;
        if (Players <> nil) and Players.Closed then
        begin
          { closing the Players window hides it; the tray brings it back }
          Players.Closed := False;
          Players.SetShown(False);
        end;
        case TrayTake of
          tcShowGame: Win.SetShown(not Win.Shown);
          tcShowPlayers: if Players <> nil then Players.SetShown(not Players.Shown);
          tcQuit: Break;
        end;
        if Tray then TraySetChecks(Win.Shown, (Players <> nil) and Players.Shown);
        Host.Active := True;
        for K := 0 to 3 do
          if Win.Held[ArrowKey[K]] <> Was[K] then
          begin
            Was[K] := Win.Held[ArrowKey[K]];
            Host.Key(ArrowVK[K], 0, 0, Was[K]);
          end;
        if Win.Held[gkEscape] <> Was[4] then
        begin
          Was[4] := Win.Held[gkEscape];
          Host.Key($1B, 27, 0, Was[4]);
        end;
        Chars := Win.TakeChars;
        for K := 1 to Length(Chars) do
        begin
          Host.Key(0, Ord(Chars[K]), 0, True);
          Host.Key(0, Ord(Chars[K]), 0, False);
        end;
        while Win.TakeClick(X, Y) do
        begin
          Host.Mouse(X, Y, EngineMouseDown, 0, 1, 0, 0);
          Host.Mouse(X, Y, EngineMouseUp, 0, 0, 0, 0);
        end;
      end;
      Host.Screen.Fill($FF000000);
      Host.Render;
      if Host.ServerName <> Titled then
      begin
        { each login (OnServerLogin) retitles the window with the server }
        Titled := Host.ServerName;
        if Win <> nil then Win.SetTitle(SpacedTitle(Titled));
        WriteLn('logged in to ', Titled);
      end;
      if Win <> nil then Win.Present(Host.Screen);
      if Host.ListChanges <> ListSeen then
      begin
        { the engine's player list changed: the Players window, its title
          and the tray tip follow }
        ListSeen := Host.ListChanges;
        Heads.Free;
        Heads := THeadCache.Create;
        DrawPlayerList(ListPic, Host, Heads.Find);
        if Players <> nil then
        begin
          Players.SetTitle(PlayerListTitle(Host.OnlineCount));
          Players.Present(ListPic);
        end;
        if Tray and (Host.ServerName <> '') then TraySetTip(TrayTip(Host.ServerName, Host.OnlineCount));
      end;
      while LogSeen < Host.Log.Count do
      begin
        WriteLn(Host.Log[LogSeen]);
        Inc(LogSeen);
      end;
      Inc(I);
      { the launcher's frame tick: 50 ms, headless too, so a --connect run
        has time to hear the server }
      Inc(NextUs, 50000);
      if NextUs > MonoUs then Sleep((NextUs - MonoUs) div 1000);
    end;
    if Dump <> '' then Host.Screen.SaveBMP(Dump);
    if HasArg('--players-dump') then ListPic.SaveBMP(Arg('--players-dump', ''));
    if HasArg('--players-log') then
    begin
      { the list as the launcher holds it, one row per line (lab checks) }
      WriteLn(PlayerListTitle(Host.OnlineCount));
      for K := 0 to High(Host.Players) do
        WriteLn('  ', Host.Players[K].Id, ' ', Host.Players[K].Nick, ' ', Host.Players[K].Head, ' ',
          Host.Players[K].Props, ' $', IntToHex(Host.Players[K].Flags, 4));
    end;
    Result := 0;
  finally
    if Tray then TrayStop;
    Players.Free;
    Win.Free;
    Host.Free;
    Heads.Free;
    ListPic.Free;
  end;
end;

begin
  Randomize;
  if ParamCount = 0 then
    Halt(RunGui);
  OpenConsoleIO;
  if HasArg('--engine') then Halt(RunEngine);
  Halt(RunGame(nil, '', ''));
end.
