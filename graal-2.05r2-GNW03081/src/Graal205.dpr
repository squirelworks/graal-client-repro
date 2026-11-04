{ Graal 2.05 rev 2 (GNW03081), rebuilt.

  Command line:
    Graal205 --server HOST:PORT --account NAME [--password-env VAR]
    Graal205 --level FILE.graal|FILE.nw [--x X --y Y]
  common options:
    --data DIR        a Graal install: pics1, arrays.dat, levels/ganis, heads,
                      bodies, swords, shields, hats
    --window          show the game in a window and read the keyboard
                      (arrows or IJKL walk, Esc quits)
    --frames N        stop after N frames (default: 100 headless, no limit
                      in a window)
    --keys SCRIPT     scripted keys, e.g. "right*10,down*4,wait*5"; each
                      entry holds one direction for that many frames
    --dump FRAME.bmp  write the last frame
    --sheet FILE      a tile sheet other than the install's pics1

  Exit code 0 when the run reached its goal: online, logged in and the board
  loaded; offline, the level parsed. }
program Graal205;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GAni in '../../common/GAni.pas',
  GWindow in '../../common/GWindow.pas',
  Protocol205 in 'Protocol205.pas',
  GraalClient in 'GraalClient.pas',
  Adventure in 'Adventure.pas';

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
    if ParamStr(I) = Name then Result := True;
end;

procedure Usage;
begin
  WriteLn('Graal ', ClientBuildLabel, ' (', ClientVersionToken, ') rebuild');
  WriteLn('  --server HOST:PORT --account NAME [--password-env VAR]');
  WriteLn('  --level FILE [--x X --y Y]');
  WriteLn('  common: [--data DIR] [--window] [--frames N] [--keys SCRIPT]');
  WriteLn('          [--dump FRAME.bmp] [--sheet FILE]');
end;

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

var
  G: TAdventure;
  Win: TGWindow;
  Script: TKeyScript;
  Server, Host, Sheet, Dump, Pw, Data: string;
  Port, Frames, I, C, D: Integer;
  OK, Online, UseWindow: Boolean;
  Start, Now_, Due: TDateTime;

begin
  Randomize;
  Server := Arg('--server', '');
  if (Server = '') and (Arg('--level', '') = '') then
  begin
    Usage;
    Halt(2);
  end;
  Online := Server <> '';
  UseWindow := HasArg('--window');
  G := TAdventure.Create;
  Win := nil;
  Script := TKeyScript.Create;
  try
    Sheet := Arg('--sheet', '');
    if Sheet <> '' then
      if not LoadImageFile(Sheet, G.Sheet) then
        WriteLn('warning: cannot load tile sheet ', Sheet, '; using index colours');
    Data := Arg('--data', '');
    if Data <> '' then G.UseInstall(Data);
    Script.Parse(Arg('--keys', ''));
    Dump := Arg('--dump', '');
    if UseWindow then Frames := StrToIntDef(Arg('--frames', '0'), 0)
    else Frames := StrToIntDef(Arg('--frames', '100'), 100);
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
      Pw := GetEnvironmentVariable(Arg('--password-env', 'GRAAL_PW'));
      if not G.ConnectServer(Host, Port, Arg('--account', ''), Pw) then
        Frames := -1;
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

    if UseWindow and (Frames >= 0) then
    begin
      Win := TGWindow.Create('Graal ' + ClientBuildLabel + ' (' + ClientVersionToken + ')',
        ScreenW, ScreenH);
      if not Win.Ok then
      begin
        G.Log('no display: running without a window');
        FreeAndNil(Win);
      end;
    end;

    { the frame loop: a 50 ms gate, a late frame is not made up }
    I := 0;
    Start := Now;
    while (Frames >= 0) and ((Frames = 0) or (I < Frames)) do
    begin
      if Win <> nil then
      begin
        Win.Pump;
        if Win.Closed or Win.Held[gkEscape] then Break;
        G.Keys[DirUp] := Win.Held[gkUp];
        G.Keys[DirLeft] := Win.Held[gkLeft];
        G.Keys[DirDown] := Win.Held[gkDown];
        G.Keys[DirRight] := Win.Held[gkRight];
      end
      else
      begin
        if (Frames = 0) then Frames := 100;
        for D := 0 to 3 do G.Keys[D] := False;
      end;
      D := Script.DirAt(I);
      if D >= 0 then G.Keys[D] := True;
      G.Tick;
      if Win <> nil then Win.Present(G.Screen);
      Inc(I);
      if Online and not G.Client.Connected then Break;
      Due := Start + (I * TickMs) / (24.0 * 3600 * 1000);
      Now_ := Now;
      if Due > Now_ then
        Sleep(Round((Due - Now_) * 24 * 3600 * 1000))
      else if Now_ - Due > 1 / (24.0 * 3600) then
        Start := Now_ - (I * TickMs) / (24.0 * 3600 * 1000); { a stall is one frame }
    end;

    if Online then
    begin
      G.Client.Flush;
      G.Client.Disconnect;
      OK := G.LoggedIn and G.BoardLoaded;
      G.Log(Format('frames in %d (%d msgs), out %d (%d msgs); logged in %s, board %s',
        [G.Client.FramesIn, G.Client.MessagesIn, G.Client.FramesOut,
         G.Client.MessagesOut, BoolToStr(G.LoggedIn, True),
         BoolToStr(G.BoardLoaded, True)]));
    end
    else if I = 0 then
      G.Draw;
    G.Log(Format('player at %.2f,%.2f facing %d', [G.Player.X, G.Player.Y, G.Player.Dir]));
    for I := 0 to G.OtherCount - 1 do
      G.Log(Format('other player %d %s at %.1f,%.1f sprite %d', [G.Others[I].Id,
        G.Others[I].Nickname, G.Others[I].X, G.Others[I].Y, G.Others[I].Sprite]));
    if G.Assets.Missing.Count > 0 then
      G.Log('not found in the install: ' + G.Assets.Missing.CommaText);
    if Dump <> '' then
    begin
      G.Screen.SaveBMP(Dump);
      G.Log('frame written to ' + Dump);
    end;
    for I := 0 to G.LogLines.Count - 1 do
      WriteLn(G.LogLines[I]);
  finally
    Win.Free;
    Script.Free;
    G.Free;
  end;
  if OK then Halt(0) else Halt(1);
end.
