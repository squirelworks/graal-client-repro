{ Graal 2.05 rev 2 (GNW03081), rebuilt.

  Command line (no window yet; frames go to a .bmp):
    Graal205 --server HOST:PORT --account NAME [--password-env VAR]
             [--frames N] [--dump FRAME.bmp] [--sheet pics1.png]
    Graal205 --level FILE.graal|FILE.nw [--x X --y Y] [--dump FRAME.bmp]
             [--sheet pics1.png]

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

procedure Usage;
begin
  WriteLn('Graal ', ClientBuildLabel, ' (', ClientVersionToken, ') rebuild');
  WriteLn('  --server HOST:PORT --account NAME [--password-env VAR] [--frames N]');
  WriteLn('  --level FILE [--x X --y Y]');
  WriteLn('  common: [--dump FRAME.bmp] [--sheet pics1.png|.gif|.bmp]');
end;

var
  G: TAdventure;
  Server, Host, Sheet, Dump, Pw: string;
  Port, Frames, I, C: Integer;
  OK: Boolean;
  Start, Now_, Due: TDateTime;

begin
  Randomize;
  Server := Arg('--server', '');
  if (Server = '') and (Arg('--level', '') = '') then
  begin
    Usage;
    Halt(2);
  end;
  G := TAdventure.Create;
  try
    Sheet := Arg('--sheet', '');
    if Sheet <> '' then
      if not LoadImageFile(Sheet, G.Sheet) then
        WriteLn('warning: cannot load tile sheet ', Sheet, '; using index colours');
    Dump := Arg('--dump', '');
    OK := False;
    if Server <> '' then
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
      Frames := StrToIntDef(Arg('--frames', '100'), 100);
      if G.ConnectServer(Host, Port, Arg('--account', ''), Pw) then
      begin
        Start := Now;
        for I := 1 to Frames do
        begin
          G.Tick;
          if not G.Client.Connected then Break;
          { the 50 ms frame gate; a late frame is not made up }
          Due := Start + (I * TickMs) / (24.0 * 3600 * 1000);
          Now_ := Now;
          if Due > Now_ then
            Sleep(Round((Due - Now_) * 24 * 3600 * 1000));
        end;
        G.Client.Disconnect;
      end;
      OK := G.LoggedIn and G.BoardLoaded;
      G.Log(Format('frames in %d (%d msgs), out %d (%d msgs); logged in %s, board %s',
        [G.Client.FramesIn, G.Client.MessagesIn, G.Client.FramesOut,
         G.Client.MessagesOut, BoolToStr(G.LoggedIn, True),
         BoolToStr(G.BoardLoaded, True)]));
    end
    else
    begin
      OK := G.Level.LoadFromFile(Arg('--level', ''));
      if OK then
      begin
        G.Player.X := StrToFloatDef(Arg('--x', '30'), 30);
        G.Player.Y := StrToFloatDef(Arg('--y', '30'), 30);
        G.Log(Format('%s: %s, %d links, %d signs, %d chests, %d npcs, %d baddies',
          [G.Level.Name, G.Level.Magic, Length(G.Level.Links), Length(G.Level.Signs),
           Length(G.Level.Chests), Length(G.Level.NPCs), Length(G.Level.Baddies)]));
      end
      else
        G.Log('level failed: ' + G.Level.LastError);
      G.Draw;
    end;
    if Dump <> '' then
    begin
      G.Screen.SaveBMP(Dump);
      G.Log('frame written to ' + Dump);
    end;
    for I := 0 to G.LogLines.Count - 1 do
      WriteLn(G.LogLines[I]);
  finally
    G.Free;
  end;
  if OK then Halt(0) else Halt(1);
end.
