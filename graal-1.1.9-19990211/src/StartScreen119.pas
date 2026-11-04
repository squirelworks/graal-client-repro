{ StartScreen119: the 1.1.9 start, a game mode and a connect dialog.

  1.1.9 has no server list. It opens on a game mode (One Player, One
  Player Online, Two Players, Four Players) and, online, a connect dialog
  with the relay's host and port in it (graal_analysis
  protocol/relay-1998.md, "Server discovery" in
  client-internals/build-catalogue.md). This rebuild offers the two
  one-player modes. The dialog is filled from listserver.txt next to the
  program, else with listserver.graal.in:14802.

  The layout, wording and look are this rebuild's own, drawn with the
  built-in font; no original window, form or image is drawn. }
unit StartScreen119;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GWindow, GStartScreen, Adventure;

type
  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter119 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

{ Runs the mode page and the connect dialog until the player picks. R
  comes back with Choice scTraining (One Player) or scOnline (Host, Port),
  or scQuit. Message, when not empty, is shown first. }
function RunConnectScreen(Win: TGWindow; S: TGSurface; const Info: TStartInfo;
  const DefHost: string; DefPort: Integer; const Message: string;
  var R: TStartResult): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, GFont;

const
  ColBack = $FF141C14;
  ColPanel = $FF203020;
  ColEdge = $FF6C8C5A;
  ColText = $FFECF4E8;
  ColLabel = $FFF0D878;
  ColDim = $FF98A890;
  ColButton = $FF34502E;
  ColButtonHot = $FF4C7244;
  ColField = $FF0A100A;
  ColFocus = $FFF0D060;

type
  TBox = record
    X, Y, W, H: Integer;
  end;

function Box(X, Y, W, H: Integer): TBox;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function Inside(const B: TBox; X, Y: Integer): Boolean;
begin
  Result := (X >= B.X) and (Y >= B.Y) and (X < B.X + B.W) and (Y < B.Y + B.H);
end;

function Ms: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

procedure Panel(S: TGSurface; const B: TBox; Fill: Cardinal);
begin
  S.FillRect(B.X, B.Y, B.W, B.H, ColEdge);
  S.FillRect(B.X + 1, B.Y + 1, B.W - 2, B.H - 2, Fill);
end;

procedure Button(S: TGSurface; const B: TBox; const Caption: string; Hot: Boolean);
begin
  if Hot then Panel(S, B, ColButtonHot) else Panel(S, B, ColButton);
  DrawText(S, B.X + (B.W - TextWidth(Caption, 2)) div 2, B.Y + (B.H - 14) div 2,
    Caption, ColText, 2);
end;

procedure Field(S: TGSurface; const B: TBox; const Text: string; Focused: Boolean);
var
  T: string;
begin
  if Focused then S.FillRect(B.X, B.Y, B.W, B.H, ColFocus)
  else S.FillRect(B.X, B.Y, B.W, B.H, ColEdge);
  S.FillRect(B.X + 1, B.Y + 1, B.W - 2, B.H - 2, ColField);
  T := Text;
  while (T <> '') and (TextWidth(T + '_', 2) > B.W - 10) do Delete(T, 1, 1);
  if Focused and ((Ms div 400) mod 2 = 0) then T := T + '_';
  DrawText(S, B.X + 5, B.Y + (B.H - 14) div 2, T, ColText, 2);
end;

procedure Edit(var Text: string; const Chars, Allowed: string; MaxLen: Integer);
var
  I: Integer;
begin
  for I := 1 to Length(Chars) do
    if Chars[I] = #8 then
    begin
      if Text <> '' then Delete(Text, Length(Text), 1);
    end
    else if (Chars[I] >= ' ') and (Chars[I] <= '~') and (Length(Text) < MaxLen) and
      ((Allowed = '') or (Pos(Chars[I], Allowed) > 0)) then
      Text := Text + Chars[I];
end;

function RunConnectScreen(Win: TGWindow; S: TGSurface; const Info: TStartInfo;
  const DefHost: string; DefPort: Integer; const Message: string;
  var R: TStartResult): Boolean;
var
  Online: Boolean;
  Focus, CX, CY, Y: Integer;
  Clicked, Go: Boolean;
  Chars, Note, PortText: string;
  BOne, BOnline, BQuit, BConnect, BBack, FNick, FHost, FPort: TBox;
begin
  Result := False;
  Online := False;
  Focus := 0;
  Note := Message;
  if R.Nickname = '' then R.Nickname := 'unknown';
  if R.Host = '' then R.Host := DefHost;
  if R.Port = 0 then R.Port := DefPort;
  PortText := IntToStr(R.Port);
  FNick := Box(220, 250, 240, 28);
  BOne := Box(40, 410, 170, 36);
  BOnline := Box(235, 410, 210, 36);
  BQuit := Box(470, 410, 130, 36);
  FHost := Box(160, 200, 300, 28);
  FPort := Box(160, 240, 100, 28);
  BBack := Box(40, 410, 170, 36);
  BConnect := Box(430, 410, 170, 36);
  while True do
  begin
    Win.Pump;
    if Win.Closed or (Assigned(Info.StopRequested) and Info.StopRequested()) then
    begin
      R.Choice := scQuit;
      Exit;
    end;
    Clicked := Win.TakeClick(CX, CY);
    Chars := Win.TakeChars;
    S.Fill(ColBack);
    for Y := 0 to 159 do
      S.FillRect(0, Y, S.Width, 1, $FF000000 or Cardinal((20 + Y div 10) shl 16) or
        Cardinal((32 + Y div 6) shl 8) or Cardinal(20 + Y div 12));
    DrawText(S, (S.Width - TextWidth(Info.Title, 5)) div 2, 40, Info.Title, ColText, 5);
    DrawText(S, (S.Width - TextWidth(Info.Subtitle, 2)) div 2, 100, Info.Subtitle, ColDim, 2);

    if not Online then
    begin
      if Pos(#27, Chars) > 0 then
      begin
        R.Choice := scQuit;
        Exit;
      end;
      Edit(R.Nickname, Chars, '', 20);
      if Clicked and Inside(BQuit, CX, CY) then
      begin
        R.Choice := scQuit;
        Exit;
      end;
      if (Clicked and Inside(BOne, CX, CY)) or (Pos(#13, Chars) > 0) then
      begin
        R.Choice := scTraining;
        Result := True;
        Exit;
      end;
      if Clicked and Inside(BOnline, CX, CY) then
      begin
        Online := True;
        Focus := 0;
        Note := '';
        Continue;
      end;
      Panel(S, Box(20, 180, S.Width - 40, 210), ColPanel);
      DrawText(S, 40, 195, 'Game mode', ColLabel, 2);
      DrawText(S, 40, 222, 'One Player: your own levels, offline.', ColDim, 1);
      DrawText(S, 40, 234, 'One Player Online: the same levels, with the players met on them.',
        ColDim, 1);
      DrawText(S, 40, 257, 'Nick name:', ColLabel, 2);
      Field(S, FNick, R.Nickname, True);
      if Assigned(Info.DrawCharacter) then Info.DrawCharacter(S, 500, 290, R.Nickname);
      if Note <> '' then DrawText(S, 40, 370, Copy(Note, 1, 90), ColFocus, 1);
      Button(S, BOne, 'One Player', Inside(BOne, Win.MouseX, Win.MouseY));
      Button(S, BOnline, 'One Player Online', Inside(BOnline, Win.MouseX, Win.MouseY));
      Button(S, BQuit, 'Quit', Inside(BQuit, Win.MouseX, Win.MouseY));
    end
    else
    begin
      if Pos(#27, Chars) > 0 then
      begin
        Online := False;
        Continue;
      end;
      if Pos(#9, Chars) > 0 then Focus := 1 - Focus;
      if Focus = 0 then Edit(R.Host, Chars, '', 60)
      else Edit(PortText, Chars, '0123456789', 5);
      Go := Pos(#13, Chars) > 0;
      if Clicked then
      begin
        if Inside(FHost, CX, CY) then Focus := 0;
        if Inside(FPort, CX, CY) then Focus := 1;
        if Inside(BBack, CX, CY) then
        begin
          Online := False;
          Continue;
        end;
        if Inside(BConnect, CX, CY) then Go := True;
      end;
      if Go then
      begin
        R.Port := StrToIntDef(PortText, 0);
        if (Trim(R.Host) = '') or (R.Port <= 0) or (R.Port > 65535) then
          Note := 'Type a host and a port from 1 to 65535.'
        else
        begin
          R.Host := Trim(R.Host);
          R.Choice := scOnline;
          Result := True;
          Exit;
        end;
      end;
      Panel(S, Box(20, 160, S.Width - 40, 230), ColPanel);
      DrawText(S, 40, 172, 'Connect to a game server', ColLabel, 2);
      DrawText(S, 40, 206, 'Server:', ColLabel, 2);
      DrawText(S, 40, 246, 'Port:', ColLabel, 2);
      Field(S, FHost, R.Host, Focus = 0);
      Field(S, FPort, PortText, Focus = 1);
      DrawText(S, 40, 290, 'Tab moves between the fields; Enter connects.', ColDim, 1);
      if Note <> '' then DrawText(S, 40, 370, Copy(Note, 1, 90), ColFocus, 1);
      Button(S, BBack, 'Back', Inside(BBack, Win.MouseX, Win.MouseY));
      Button(S, BConnect, 'Connect', Inside(BConnect, Win.MouseX, Win.MouseY));
    end;
    Win.Present(S);
    Sleep(20);
  end;
end;

procedure TCharacter119.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
