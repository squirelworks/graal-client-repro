{ Graal 2.01 rev 1 (GNW23021), rebuilt.

  Command line:
    Graal201r1 --server HOST:PORT --account NAME [--password-env VAR]
    Graal201r1 --level FILE.graal|FILE.nw [--x X --y Y]
    Graal201r1 FILE.graal|FILE.nw   open the level in the built-in editor
  common options:
    --data DIR        a Graal install: pics1, arrays.dat, levels/ganis, heads,
                      bodies, swords, shields, hats
    --window          show the game in a window and read the keyboard
                      (arrows or IJKL walk, S sword, A lift,
                      throw or open, M map, Esc quits); with a window,
                      sound effects play unless --nosound
    --nosound         no sound or music
    --headless        no drawing at all (stress runs)
    --frames N        stop after N frames; 0 = until stopped (default: 100
                      without a window or --seconds, no limit in a window)
    --seconds N       stop after N seconds
    --keys SCRIPT     scripted keys, e.g. "right*10,down*4,wait*5"; each
                      entry holds one direction for that many frames; a, s
                      and d press that game key for one frame
    --walk MODE       script (default with --keys), idle (default without),
                      or random
    --walk-ms N       random walk: a new direction every N ms (default 100)
    --seed N          random walk seed
    --link-every N    random walk: every N seconds head for the nearest link
    --nodelay         set TCP_NODELAY (2.05 leaves it off)
    --stats-every N   a JSON stats line on stdout every N seconds
    --dump FRAME.bmp  write the last frame
    --sheet FILE      a tile sheet other than the install's pics1

  Log lines go to stderr as they happen. Online, one JSON summary line goes
  to stdout at the end. SIGTERM / SIGINT (Ctrl+Break / Ctrl+C on Windows)
  end the run cleanly.

  Exit codes, online: 0 logged in and ended cleanly, 1 error, 2 never
  logged in, 3 the link dropped after login. Offline: 0 the level parsed,
  1 it did not. 64: bad command line. }
program Graal201r1;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{ A windowed program on Windows, like 2.05: started with no arguments it
  opens the start screen. With arguments it attaches to the console it was
  started from (OpenConsoleIO) and runs as before. }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal201r1.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal201r1.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils, Classes,
  GCompat in '../../common/GCompat.pas',
  GPaths in '../../common/GPaths.pas',
  GNumText in '../../common/GNumText.pas',
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GAni in '../../common/GAni.pas',
  GFont in '../../common/GFont.pas',
  GWindow in '../../common/GWindow.pas',
  Protocol201r1 in 'Protocol201r1.pas',
  GraalClient in 'GraalClient.pas',
  GGs1 in '../../common/GGs1.pas',
  Npc201r1 in 'Npc201r1.pas',
  Baddy201r1 in 'Baddy201r1.pas',
  NpcBridge201r1 in 'NpcBridge201r1.pas',
  Adventure in 'Adventure.pas',
  GSound in '../../common/GSound.pas',
  Sound201r1 in 'Sound201r1.pas',
  Map201r1 in 'Map201r1.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  StartScreen201r1 in 'StartScreen201r1.pas',
  GDfmObj in '../../common/GDfmObj.pas',
  GVclForm in '../../common/GVclForm.pas',
  GOptionsWindow in '../../common/GOptionsWindow.pas',
  GDfm in '../../common/GDfm.pas',
  GUiFont in '../../common/GUiFont.pas',
  GRes20x in '../../common/GRes20x.pas',
  ResGraal201r1 in 'ResGraal201r1.pas',
  GRealStart20 in '../../common/GRealStart20.pas',
  RunMode in 'RunMode.pas',
  GLevelWrite in '../../common/GLevelWrite.pas',
  EditorDoc in 'editor/EditorDoc.pas',
  EditorUI in 'editor/EditorUI.pas',
  EditorDialogs in 'editor/EditorDialogs.pas',
  EditorObjSets in 'editor/EditorObjSets.pas',
  EditorView in 'editor/EditorView.pas',
  EditorMain in 'editor/EditorMain.pas';

var
  { Set while the start screen runs a game: the arguments it chose, read
    in place of the command line. }
  GuiArgs: TStringList = nil;
  { why the last game ended, for the start screen }
  LastGameError: string = '';
  { Alt+Enter's screen mode (graalconfig.txt fullscreenmode), set by the
    start screen; 0: Alt+Enter does nothing }
  GuiFullW: Integer = 0;
  GuiFullH: Integer = 0;

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
  WriteLn('  --server HOST:PORT --account NAME [--password-env VAR]');
  WriteLn('  --level FILE [--x X --y Y]');
  WriteLn('  common: [--data DIR] [--window | --headless] [--frames N] [--seconds N]');
  WriteLn('          [--keys SCRIPT] [--walk script|idle|random] [--walk-ms N] [--seed N]');
  WriteLn('          [--link-every N] [--nodelay] [--stats-every N]');
  WriteLn('          [--dump FRAME.bmp] [--sheet FILE] [--nosound]');
end;

const
  { game keys in a key script: pressed on that tick }
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
  OK, Online, UseWindow, NoDelay, Dropped, Crashed, EditorFirst: Boolean;
  StartUs, GateUs, NowUs, T0, NextStatsUs: Int64;
  WasHeld: array[0..4] of Boolean;
  Typed: string;
  K: Integer;
  Chatting: Boolean;

begin
  Result := 64;
  WasHeld[0] := False;
  WasHeld[1] := False;
  WasHeld[2] := False;
  WasHeld[3] := False;
  WasHeld[4] := False;
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
  EditorFirst := HasArg('--editor');
  Account := Arg('--account', '');
  InstallStopHandlers;
  G := TAdventure.Create;
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
      { placed first: the level's NPCs see playerenters on loading }
      G.Player.X := StrToFloatDef(Arg('--x', '30'), 30);
      G.Player.Y := StrToFloatDef(Arg('--y', '30'), 30);
      OK := G.LoadLevelFile(Arg('--level', ''));
      { offline on the tutorial, 2.05 switches to the tutorial maps }
      if Copy(LowerCase(ExtractFileName(Arg('--level', ''))), 1, 9) = 'tutorial_' then
        UseTutorialMaps;
      if OK then
      begin
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

    { sound only in a window: stress runs and tests open no device }
    SoundEnabled := (Win <> nil) and not HasArg('--nosound');

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
        if Win <> nil then
        begin
          Win.Pump;
          if Win.Closed or Win.Held[gkEscape] then Break;
          { F1: the Help window (GRealStart20.RunHelp20) }
          if Win.WasPressed(gkOptions) then
          begin
            if RunHelp20(ExeResource, G.Level.Name) = oaEditLevel then
              EditorKey(Win, G, Online);
            if Win.Closed then Break;
          end;
          { Alt+Enter: the configured screen mode, the 640 x 480 picture
            filling it, and back }
          if Win.TakeFullscreenToggle and (GuiFullW > 0) then
            if not Win.Fullscreen then Win.EnterFullscreen(GuiFullW, GuiFullH)
            else Win.LeaveFullscreen(ScreenW, ScreenH);
          { F4: the built-in level editor (offline only) }
          if Win.WasPressed(gkEditor) or EditorFirst then
          begin
            EditorFirst := False;
            EditorKey(Win, G, Online);
            if Win.Closed then Break;
          end;
          { the chat line: Tab goes into it and back out; while in it the
            keys type there and Enter says the line }
          Typed := Win.TakeChars;
          for K := 1 to Length(Typed) do
            if Typed[K] = #9 then G.ChatTyping := not G.ChatTyping
            else if G.ChatTyping then
              case Typed[K] of
                #8: if G.ChatLine <> '' then SetLength(G.ChatLine, Length(G.ChatLine) - 1);
                #13:
                  begin
                    G.Say(G.ChatLine);
                    G.ChatLine := '';
                  end;
                #32..#255: if Length(G.ChatLine) < 300 then G.ChatLine := G.ChatLine + Typed[K];
              end;
          Chatting := G.ChatTyping;
          G.Keys[DirUp] := Win.Held[gkUp] and not Chatting;
          G.Keys[DirLeft] := Win.Held[gkLeft] and not Chatting;
          G.Keys[DirDown] := Win.Held[gkDown] and not Chatting;
          G.Keys[DirRight] := Win.Held[gkRight] and not Chatting;
          { the game keys act on the press, not while held }
          G.ActionKey := Win.Held[gkAction] and not WasHeld[0] and not Chatting;
          G.AttackKey := Win.Held[gkAttack] and not WasHeld[1] and not Chatting;
          G.ItemKey := Win.Held[gkItem] and not WasHeld[2] and not Chatting;
          G.MapKey := Win.Held[gkMap] and not WasHeld[3] and not Chatting;
          WasHeld[0] := Win.Held[gkAction];
          WasHeld[1] := Win.Held[gkAttack];
          WasHeld[2] := Win.Held[gkItem];
          WasHeld[3] := Win.Held[gkMap];
          G.ItemListKey := Win.Held[gkItemList] and not WasHeld[4] and not Chatting;
          WasHeld[4] := Win.Held[gkItemList];
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
    SoundShutdown;
    SoundEnabled := False;
    MapOpen := False;
    UseDefaultMaps;
    if Win <> GuiWin then Win.Free;
    Script.Free;
    Walker.Free;
    Hist.Free;
    G.Free;
  end;
  Result := ExitCode_;
end;

{ Training: the tutorial where 2.05 starts it, when it lies next to the
  program; else the built-in starter level (a start.nw next to the program
  replaces it). }
{ The Training levels this build's original exe carried in its resources
  (TUTORIALA1 .. TUTORIALC4, TUTORIALB2H the house), compiled into this
  program (ResGraal201r1): written out once as tutorial_a-1.graal ..
  tutorial_c-4.graal and tutorial_b-2_house.graal, the names their links
  use, into a folder of this build's own under the system's temp folder.
  Returns that folder's tutorial_b-4.graal, or ''. }
function WriteTutorials: string;
const
  Names: array[0..12] of string = ('A1', 'A2', 'A3', 'A4', 'B1', 'B2', 'B2H', 'B3', 'B4',
    'C1', 'C2', 'C3', 'C4');
var
  Dir, D, F: string;
  I: Integer;
  S: TFileStream;
begin
  Result := '';
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'graal-delphi-' +
    ClientBuildLabel + PathDelim;
  if not ForceDirectories(Dir) then Exit;
  for I := 0 to High(Names) do
  begin
    if not ExeResource('TUTORIAL' + Names[I], D) then Exit;
    if Names[I] = 'B2H' then F := 'tutorial_b-2_house.graal'
    else F := 'tutorial_' + LowerCase(Names[I][1]) + '-' + Names[I][2] + '.graal';
    try
      S := TFileStream.Create(Dir + F, fmCreate);
      try
        S.WriteBuffer(D[1], Length(D));
      finally
        S.Free;
      end;
    except
      Exit;
    end;
  end;
  Result := InstallPath(Dir, 'tutorial_b-4.graal');
end;

procedure TrainingLevel(const Dir: string; out Path, X, Y: string);
begin
  X := '32';
  Y := '60';
  Path := FirstFileIn(Dir, 'levels/tutorial_b-4.graal;tutorial_b-4.graal');
  if Path = '' then Path := WriteTutorials;
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
  Dir, ListHost, Msg, Lvl, X, Y: string;
  ListPort: Integer;
  Picked: Boolean;
  Fetch: TListFetch201r1;
  Info: TStartInfo;
  Who: TCharacter201r1;
  Art: TRealStart20;
begin
  Result := 0;
  Dir := ExtractFilePath(ParamStr(0));
  Art := nil;
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
    { a Delphi 5 program: the forms are owned by its TApplication window
      ("Graal"), which is the taskbar entry }
    Win.UseDelphiFrames('Graal');
    { the asset roots before anything is read from them }
    SetAssetRoots(Dir, ClientAssetFolders);
    { listserver.txt next to the program, else the community listserver in
      place of the 2.05 one, which is gone: listserver.graal.in, port 14923
      for legacy clients (14922 is the supported-clients port) }
    ReadListServer(Dir, DefaultListHost, DefaultListPort, ListHost, ListPort);
    { SIGTERM / Ctrl+C end the program on the start screen too }
    InstallStopHandlers;
    { the launcher of this build's original, from its own forms and art
      (compiled in: ResGraal201r1) }
    Art := TRealStart20.Create;
    if Art.Load(ExeResource, Dir) then
      Win.Reshape(Art.Connect.Str('Caption', 'Graal 2001'), Art.Connect.Int('ClientWidth', 476),
        Art.Connect.Int('ClientHeight', 330), True)
    else
      FreeAndNil(Art);
    FillChar(R, SizeOf(R), 0);
    if Art <> nil then ReadSavedLogin(R.Nickname, R.Account);
    Msg := '';
    repeat
      Win.TakeChars;
      G := TAdventure.Create;
      Fetch := TListFetch201r1.Create;
      Who := TCharacter201r1.Create;
      try
        G.UseInstall(Dir);
        Who.G := G;
        Info.Title := 'graal-delphi';
        Info.Subtitle := '2.01 rev 1 rebuilt';
        Info.DrawCharacter := Who.Draw;
        Info.StopRequested := StopRequested;
        if Art <> nil then
          Picked := RunRealStart20(Win, Art, Fetch, Info, ListHost, ListPort, Msg, R)
        else
          Picked := RunStartScreen(Win, G.Screen, Fetch, Info, Dir, ListHost, ListPort, Msg, R);
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
        end;
        LastGameError := '';
        { the game in its own 640 x 480 window, titled as the original's
          TAdventure ("Graal") }
        if Art <> nil then
        begin
          { Alt+Enter: the screen mode of graalconfig.txt fullscreenmode }
          GuiFullW := Art.FullScreenW;
          GuiFullH := Art.FullScreenH;
          Win.Reshape(Art.MainCaption, ScreenW, ScreenH);
        end;
        if RunGame(Win, R.Password, R.Nickname) <> 0 then
          Msg := LastGameError
        else
          Msg := '';
      finally
        FreeAndNil(GuiArgs);
      end;
      if Win.Fullscreen then Win.LeaveFullscreen(ScreenW, ScreenH);
      if (Art <> nil) and not Win.Closed then
        Win.Reshape(Art.Connect.Str('Caption', 'Graal 2001'), Art.Connect.Int('ClientWidth', 476),
          Art.Connect.Int('ClientHeight', 330), True);
    until Win.Closed or StopRequested;
  finally
    Art.Free;
    Win.Free;
  end;
end;

{ Graal201r1 level.graal: like 2.05, open the file in the editor in the
  file's folder, with the local player at 30, 30.5. }
function RunEditorFile(const FileName: string): Integer;
var
  Win: TGWindow;
  Dir, Path: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Path := ExpandFileName(FileName);
  Win := TGWindow.Create('Graal ' + ClientBuildLabel + ' (' + ClientVersionToken + ')',
    ScreenW, ScreenH);
  try
    if not Win.Ok then
    begin
      OpenConsoleIO;
      WriteLn(ErrOutput, 'no display for the editor');
      Result := 64;
      Exit;
    end;
    SetAssetRoots(Dir, ClientAssetFolders);
    if ExtractFilePath(Path) <> '' then SetCurrentDir(ExtractFilePath(Path));
    GuiArgs := TStringList.Create;
    try
      GuiArgs.Add('--window');
      GuiArgs.Add('--data');
      GuiArgs.Add(Dir);
      GuiArgs.Add('--level');
      GuiArgs.Add(Path);
      GuiArgs.Add('--x');
      GuiArgs.Add('30');
      GuiArgs.Add('--y');
      GuiArgs.Add('30.5');
      GuiArgs.Add('--editor');
      Result := RunGame(Win, '', '');
    finally
      FreeAndNil(GuiArgs);
    end;
  finally
    Win.Free;
  end;
end;

begin
  Randomize;
  if ParamCount = 0 then
    Halt(RunGui);
  if (ParamCount = 1) and (Copy(ParamStr(1), 1, 1) <> '-') and FileExists(ParamStr(1)) then
    Halt(RunEditorFile(ParamStr(1)));
  OpenConsoleIO;
  Halt(RunGame(nil, '', ''));
end.
