{ 5th Graal (gen 1, linked 1998-10-19), rebuilt.

  Command line:
    GraalB5 --server HOST:PORT [--nick NAME]
    GraalB5 --level FILE.graal [--x X --y Y]
  common options:
    --data DIR        a Graal install: pics1, arrays.dat, levels/
    --window          show the game in a window and read the keyboard
                      (arrows or IJKL walk, Esc quits)
    --headless        no drawing at all (stress runs)
    --frames N        stop after N frames; 0 = until stopped (default: 100
                      without a window or --seconds, no limit in a window)
    --seconds N       stop after N seconds
    --keys SCRIPT     scripted keys, e.g. "right*10,down*4,wait*5"
    --walk MODE       script (default with --keys), idle (default without),
                      or random
    --walk-ms N       random walk: a new direction every N ms (default 100)
    --seed N          random walk seed
    --stats-every N   a JSON stats line on stdout every N seconds
    --dump FRAME.bmp  write the last frame
    --sheet FILE      a tile sheet other than the install's pics1

  There is no account or password in this build: it joins a relay game
  and sends its nickname to the players it pairs with. --account is taken
  as the nickname when --nick is not given.

  Log lines go to stderr as they happen. Online, one JSON summary line goes
  to stdout at the end. SIGTERM / SIGINT end the run cleanly.

  Exit codes, online: 0 joined and ended cleanly, 1 error, 2 never joined,
  3 the link dropped after joining. Offline: 0 the level parsed, 1 it did
  not. 64: bad command line. }
program GraalB5;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/GraalB5.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R GraalB5.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils, Classes,
  GCompat in '../../common/GCompat.pas',
  GPaths in '../../common/GPaths.pas',
  GNumText in '../../common/GNumText.pas',
  GTypes in '../../common/GTypes.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GBetaHud in '../../common/GBetaHud.pas',
  GArrays in '../../common/GArrays.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GAni in '../../common/GAni.pas',
  GFont in '../../common/GFont.pas',
  GWindow in '../../common/GWindow.pas',
  GRelay in '../../common/GRelay.pas',
  ProtocolB5 in 'ProtocolB5.pas',
  Adventure in 'Adventure.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  StartScreenB5 in 'StartScreenB5.pas',
  RunMode in 'RunMode.pas',
  GDfmObj in '../../common/GDfmObj.pas',
  GVclForm in '../../common/GVclForm.pas',
  GBetaStart in '../../common/GBetaStart.pas',
  RealResB5 in 'RealResB5.pas'
{$IFDEF MSWINDOWS}, Windows{$ENDIF};

var
  GuiArgs: TStringList = nil;
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

function BuildTitle: string;
begin
  Result := ClientBuildName + ' (' + ClientLinkDate + ')';
end;

procedure Usage;
begin
  WriteLn(BuildTitle, ' rebuild, 1998 relay (gen 1)');
  WriteLn('  (no arguments: the start screen, Training or the connect dialog)');
  WriteLn('  --server HOST:PORT [--nick NAME]');
  WriteLn('  --level FILE [--x X --y Y]');
  WriteLn('  common: [--data DIR] [--window | --headless] [--frames N] [--seconds N]');
  WriteLn('          [--keys SCRIPT] [--walk script|idle|random] [--walk-ms N] [--seed N]');
  WriteLn('          [--stats-every N] [--dump FRAME.bmp] [--sheet FILE]');
end;

type
  TKeyScript = class
  public
    Dirs: array of Integer;
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

function StatsJson(const Kind, EndState, Error, Nick: string; G: TAdventure;
  H: TTickHistogram; Ticks: Integer; RunUs: Int64): string;
var
  Join: string;
begin
  if G.JoinMs >= 0 then Join := IntToStr(G.JoinMs) else Join := 'null';
  Result := '{"kind":' + JsonStr(Kind) +
    ',"version":' + JsonStr(ClientBuildLabel) +
    ',"token":' + JsonStr(ClientLinkDate) +
    ',"account":' + JsonStr(Nick);
  if EndState <> '' then
    Result := Result + ',"end":' + JsonStr(EndState) + ',"error":' + JsonStr(Error);
  Result := Result +
    ',"login_ms":' + Join +
    ',"run_s":' + JsonMs(RunUs / 1000000.0) +
    ',"ticks":' + IntToStr(Ticks) +
    ',"lines_in":' + IntToStr(G.FixedLink.LinesIn + G.RoomLink.LinesIn) +
    ',"lines_out":' + IntToStr(G.FixedLink.LinesOut + G.RoomLink.LinesOut) +
    ',"bytes_in":' + IntToStr(G.FixedLink.BytesIn + G.RoomLink.BytesIn) +
    ',"bytes_out":' + IntToStr(G.FixedLink.BytesOut + G.RoomLink.BytesOut) +
    ',"partners":' + IntToStr(G.RoomLink.Partners.Count) +
    ',"tick_ms_p50":' + JsonMs(H.QuantileMs(0.5)) +
    ',"tick_ms_p99":' + JsonMs(H.QuantileMs(0.99)) +
    ',"tick_ms_max":' + JsonMs(H.MaxMs) +
    ',"rss_peak_kib":';
  if PeakRssKiB >= 0 then Result := Result + IntToStr(PeakRssKiB)
  else Result := Result + 'null';
  Result := Result + '}';
end;

{ The offline start level: the first of the build's training levels found
  next to the program, else the built-in starter level. }
procedure TrainingLevel(const Dir: string; out Path: string);
begin
  Path := FirstFileIn(Dir, TrainingLevels);
  if Path = '' then Path := InstallPath(Dir, 'start.nw');
end;

function RunGame(GuiWin: TGWindow; const GuiNick: string): Integer;
var
  G: TAdventure;
  Win: TGWindow;
  Script: TKeyScript;
  Walker: TWalker;
  Hist: TTickHistogram;
  Server, Host, Sheet, Dump, Data, Nick, WalkName, EndState, Error, Lvl: string;
  Port, Frames, I, C, D, Seconds, StatsEvery, ExitCode_: Integer;
  OK, Online, UseWindow, Dropped, Crashed: Boolean;
  StartUs, GateUs, NowUs, T0, NextStatsUs: Int64;
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
  Nick := Arg('--nick', Arg('--account', ''));
  if GuiNick <> '' then Nick := GuiNick;
  InstallStopHandlers;
  G := TAdventure.Create;
  G.Echo := GuiWin = nil;
  G.Headless := HasArg('--headless');
  Win := GuiWin;
  Script := TKeyScript.Create;
  Walker := TWalker.Create(Cardinal(StrToIntDef(Arg('--seed', '1'), 1)));
  Hist := TTickHistogram.Create;
  Dropped := False;
  Crashed := False;
  Error := '';
  I := 0;
  try
    Data := Arg('--data', '');
    if Data = '' then Data := ExtractFilePath(ParamStr(0));
    Data := IncludeTrailingPathDelimiter(Data);
    G.UseInstall(Data);
    Sheet := Arg('--sheet', '');
    if Sheet <> '' then
      if LoadImageFile(Sheet, G.Sheet) then G.SheetBuiltin := False
      else G.Log('warning: cannot load tile sheet ' + Sheet);
    Script.Parse(Arg('--keys', ''));
    if Arg('--keys', '') <> '' then WalkName := Arg('--walk', 'script')
    else WalkName := Arg('--walk', 'idle');
    WalkName := LowerCase(WalkName);
    if WalkName = 'random' then Walker.Mode := wmRandom
    else if WalkName = 'idle' then Walker.Mode := wmIdle
    else Walker.Mode := wmScript;
    Walker.WalkTicks := StrToIntDef(Arg('--walk-ms', '100'), 100) div TickMs;
    if Walker.WalkTicks < 1 then Walker.WalkTicks := 1;
    Dump := Arg('--dump', '');
    Seconds := StrToIntDef(Arg('--seconds', '0'), 0);
    StatsEvery := StrToIntDef(Arg('--stats-every', '0'), 0);
    if HasArg('--frames') then Frames := StrToIntDef(Arg('--frames', '0'), 0)
    else if UseWindow or (Seconds > 0) then Frames := 0
    else Frames := 100;

    { the level: given, or (online) the training level the player is on
      until the server's level choice moves it }
    Lvl := Arg('--level', '');
    if Lvl = '' then TrainingLevel(Data, Lvl);
    OK := G.LoadLevelFile(Lvl);
    if OK then
    begin
      G.Player.X := StrToFloatDef(Arg('--x', OfflineStartX), 30);
      G.Player.Y := StrToFloatDef(Arg('--y', OfflineStartY), 30);
      G.Log(Format('%s: %s, %d links, %d signs, %d chests, %d npcs, %d baddies',
        [G.Level.Name, G.Level.Magic, Length(G.Level.Links), Length(G.Level.Signs),
         Length(G.Level.Chests), Length(G.Level.NPCs), Length(G.Level.Baddies)]));
    end
    else
    begin
      G.Log('level failed: ' + G.Level.LastError);
      if not Online then Frames := -1;
    end;

    if Online then
    begin
      C := Pos(':', Server);
      if C > 0 then
      begin
        Host := Copy(Server, 1, C - 1);
        Port := StrToIntDef(Copy(Server, C + 1, MaxInt), DialogPort);
      end
      else
      begin
        Host := Server;
        Port := DialogPort;
      end;
      if not G.ConnectServer(Host, Port, Nick) then
      begin
        Error := G.FixedLink.LastError + G.RoomLink.LastError;
        Frames := -1;
      end;
    end;

    if UseWindow and (Frames >= 0) and (Win = nil) then
    begin
      Win := TGWindow.Create(BuildTitle, ScreenW, ScreenH);
      if not Win.Ok then
      begin
        G.Log('no display: running without a window');
        FreeAndNil(Win);
      end;
    end;

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
          G.Keys[DirUp] := Win.Held[gkUp];
          G.Keys[DirLeft] := Win.Held[gkLeft];
          G.Keys[DirDown] := Win.Held[gkDown];
          G.Keys[DirRight] := Win.Held[gkRight];
        end;
        if Walker.Mode = wmScript then D := Script.DirAt(I)
        else D := Walker.DirAt(I, G.Level, G.Player.X, G.Player.Y);
        if D >= 0 then G.Keys[D] := True;
        T0 := MonoUs;
        G.Tick;
        Hist.Add(MonoUs - T0);
        if Win <> nil then Win.Present(G.Screen);
        Inc(I);
        if Online and not G.Connected then
        begin
          Dropped := True;
          Error := G.FixedLink.LastError + G.RoomLink.LastError;
          Break;
        end;
        NowUs := MonoUs;
        if (StatsEvery > 0) and (NowUs >= NextStatsUs) and (GuiWin = nil) then
        begin
          WriteLn(StatsJson('stats', '', '', Nick, G, Hist, I, NowUs - StartUs));
          Flush(Output);
          Inc(NextStatsUs, Int64(StatsEvery) * 1000000);
        end;
        Inc(GateUs, TickMs * 1000);
        if GateUs > NowUs then
          Sleep((GateUs - NowUs) div 1000)
        else if NowUs - GateUs > 1000000 then
          GateUs := NowUs;
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
      G.Disconnect;
      OK := G.Joined;
      G.Log(Format('lines in %d, out %d; joined %s; partners %d',
        [G.FixedLink.LinesIn + G.RoomLink.LinesIn,
         G.FixedLink.LinesOut + G.RoomLink.LinesOut,
         BoolToStr(G.Joined, True), G.RoomLink.Partners.Count]));
    end;
    if (Dump <> '') or ((I = 0) and not Online) then G.Draw;
    G.Log(Format('player at %.2f,%.2f facing %d', [G.Player.X, G.Player.Y, G.Player.Dir]));
    for C := 0 to G.OtherCount - 1 do
      G.Log(Format('other player %s %s at %.1f,%.1f sprite %d', [G.Others[C].Id,
        G.Others[C].Nickname, G.Others[C].X, G.Others[C].Y, G.Others[C].Sprite]));
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
        WriteLn(StatsJson('summary', EndState, Error, Nick, G, Hist, I, MonoUs - StartUs));
      if Error <> '' then LastGameError := Error
      else if not OK then LastGameError := 'the relay did not answer'
      else LastGameError := '';
    end
    else if OK and not Crashed then ExitCode_ := 0
    else ExitCode_ := 1;
  finally
    if Win <> GuiWin then Win.Free;
    Script.Free;
    Walker.Free;
    Hist.Free;
    G.Free;
  end;
  Result := ExitCode_;
end;

{ The shared start screen (systems without Win32), then the game it
  picks, and back to the start screen when the game ends. }
function RunSharedStart: Integer;
var
  Win: TGWindow;
  G: TAdventure;
  R: TStartResult;
  Dir, Host, Msg, Lvl: string;
  Port: Integer;
  Picked: Boolean;
  Dialog: TConnectDialogB5;
  Info: TStartInfo;
  Who: TCharacterB5;
begin
  Result := 0;
  Dir := ExtractFilePath(ParamStr(0));
  Win := TGWindow.Create(BuildTitle, ScreenW, ScreenH);
  try
    if not Win.Ok then
    begin
      OpenConsoleIO;
      WriteLn(ErrOutput, 'no display for the start screen; run with arguments:');
      Usage;
      Result := 64;
      Exit;
    end;
    InstallStopHandlers;
    SetAssetRoots(Dir, ClientBuildLabel);
    { the connect dialog's host: listserver.txt next to the program, else
      the build's default }
    ReadListServer(Dir, DialogHost, DialogPort, Host, Port);
    FillChar(R, SizeOf(R), 0);
    Msg := '';
    repeat
      Win.TakeChars;
      G := TAdventure.Create;
      Dialog := TConnectDialogB5.Create;
      Who := TCharacterB5.Create;
      try
        G.UseInstall(Dir);
        Who.G := G;
        Info.Title := 'graal-delphi';
        Info.Subtitle := ClientBuildName + ' rebuilt (1998 relay)';
        Info.DrawCharacter := Who.Draw;
        Info.StopRequested := StopRequested;
        Picked := RunStartScreen(Win, G.Screen, Dialog, Info, Dir, Host, Port, Msg, R);
      finally
        Who.Free;
        Dialog.Free;
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
          TrainingLevel(Dir, Lvl);
          GuiArgs.Add('--level');
          GuiArgs.Add(Lvl);
        end
        else
        begin
          GuiArgs.Add('--server');
          GuiArgs.Add(R.Host + ':' + IntToStr(R.Port));
        end;
        LastGameError := '';
        if RunGame(Win, R.Nickname) <> 0 then Msg := LastGameError else Msg := '';
      finally
        FreeAndNil(GuiArgs);
      end;
    until Win.Closed or StopRequested;
  finally
    Win.Free;
  end;
end;

{ No arguments: the build's own start dialog, built from its TConnectFrame
  form (src/RealResB5.pas, from the real client), then the game in a
  window shaped as its TAdventure form. Closing the game window ends the
  program, as in the original; a failed connection is reported and the
  dialog shown again. Systems without Win32 use the shared start screen. }
function RunGui: Integer;
{$IFDEF MSWINDOWS}
var
  Info: TBetaStartInfo;
  Choice: TBetaChoice;
  GF: TBetaGameForm;
  Dir, Host, Lvl, FormData, HeadsFile: string;
  Port, I: Integer;
  Win: TGWindow;
begin
  Result := 0;
  Info := Default(TBetaStartInfo);
  Dir := ExtractFilePath(ParamStr(0));
  if not RealResource('TCONNECTFRAME', Info.FormData) then
  begin
    Result := RunSharedStart;
    Exit;
  end;
  InstallStopHandlers;
  SetAssetRoots(Dir, ClientBuildLabel);
  ReadListServer(Dir, DialogHost, DialogPort, Host, Port);
  Info.AppTitle := 'Graal';
  Info.Nick := '';
  { the real dialog is owned by the application window and stays on top }
  Info.AppOwned := True;
  Info.StayOnTop := True;
  { the lists shrink the heads in GDI's default mode }
  Info.HeadPick := False;
  SetLength(Info.Names, 0);
  if CharacterNames[0] <> '' then
  begin
    SetLength(Info.Names, Length(CharacterNames));
    for I := 0 to High(CharacterNames) do Info.Names[I] := CharacterNames[I];
  end;
  Info.Heads := nil;
  HeadsFile := AssetPath('heads.gif');
  if HeadsFile = '' then HeadsFile := AssetPath('heads.png');
  if HeadsFile <> '' then
  begin
    Info.Heads := TGSurface.Create(1, 1);
    if not LoadImageFile(HeadsFile, Info.Heads) then FreeAndNil(Info.Heads);
  end;
  try
    repeat
      if not RunBetaStart(Info, Choice) or StopRequested then Exit;
      Info.Nick := Choice.Nick;
      FormData := '';
      RealResource('TADVENTURE', FormData);
      BetaGameForm(FormData, GF);
      { at run time the view fills the window and there is no chat field }
      GF.ChatH := 0;
      { the game window as the original makes it (read on Windows): a
        TAdventure owned by the application window, WS_EX_APPWINDOW, WS_EX_CONTROLPARENT, WS_EX_WINDOWEDGE, WS_EX_ACCEPTFILES }
      GWindowClass := 'TAdventure';
      GWindowOwner := VclAppWindow;
      GWindowExStyle := $00050110;
      { Alt+Enter reports that the display mode cannot be changed, as the original does }
      GAltEnterMode := 2;
      Win := TGWindow.Create(GF.Caption, GF.ViewW, GF.ViewH);
      GuiArgs := TStringList.Create;
      try
        Win.VclFrame(GF.Caption, GF.Width, GF.Height, GF.ViewW, GF.ViewH, GF.ChatH,
          GF.MinBox, GF.MaxBox);
        GuiArgs.Add('--window');
        GuiArgs.Add('--data');
        GuiArgs.Add(Dir);
        if Choice.Mode = bmOnline then
        begin
          { the dialog's server field, when the player changed it; else the
            relay of listserver.txt or the rebuild's default (the hosts the
            originals were pre-filled with are gone) }
          GuiArgs.Add('--server');
          if Choice.HostEdited and (Trim(Choice.Host) <> '') then
            GuiArgs.Add(Trim(Choice.Host) + ':' + IntToStr(Choice.Port))
          else if Choice.Port > 0 then
            GuiArgs.Add(Host + ':' + IntToStr(Choice.Port))
          else
            GuiArgs.Add(Host + ':' + IntToStr(Port));
        end
        else
        begin
          TrainingLevel(Dir, Lvl);
          GuiArgs.Add('--level');
          GuiArgs.Add(Lvl);
        end;
        LastGameError := '';
        if (RunGame(Win, Choice.Nick) <> 0) and (Choice.Mode = bmOnline) and
          not Win.Closed and not StopRequested then
        begin
          MessageBox(0, PChar('Could not connect: ' + LastGameError), 'Graal',
            MB_OK or MB_ICONEXCLAMATION);
          Continue;
        end;
        Exit;
      finally
        FreeAndNil(GuiArgs);
        Win.Free;
      end;
    until StopRequested;
  finally
    Info.Heads.Free;
  end;
end;
{$ELSE}
begin
  Result := RunSharedStart;
end;
{$ENDIF}

begin
  Randomize;
  if ParamCount = 0 then
    Halt(RunGui);
  OpenConsoleIO;
  Halt(RunGame(nil, ''));
end.
