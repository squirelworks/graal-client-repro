{ Connect3D: the start window (the original's TConnectFrame) and the
  screen drawing around the 3D view.

  The start window holds the nickname (default "Stefan"), the host, the
  port (14901), and the account and password (both "guest"), as the
  original's did, with logo.bmp on top when the player's files have it.
  The layout and look are this build's own. Offline is this build's
  addition: it walks the client's default level, level1.x, with no
  server. }
unit Connect3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, Window3D;

type
  TConnectChoice = (ccQuit, ccConnect, ccOffline);
  TStopFn = function: Boolean;

  TConnectForm = record
    Nick, Host, Port, Account, Password: string;
    Message: string;
    LogoPath: string;
  end;

{ Shows the start window until a choice is made. }
function RunConnect(Win: TWindow3D; S: TGSurface; var F: TConnectForm;
  Stop: TStopFn): TConnectChoice;
{ Draws the window once (tests and --dump). Focus is the field index. }
procedure DrawConnect(S: TGSurface; const F: TConnectForm; Focus: Integer);
{ The chat edit line under the view, and the chat log over it. }
procedure DrawChatLine(S: TGSurface; Y: Integer; const Text: string; Focused: Boolean);
{ A message box in the middle of the view ("Administrator message"). }
procedure DrawMessageBox(S: TGSurface; const Title, Text: string);

implementation

uses
  SysUtils, GFont;

const
  ColBack = $FF20283A;
  ColPanel = $FF2E3A52;
  ColEdge = $FF8090B0;
  ColField = $FF101820;
  ColFocus = $FFFFD060;
  ColText = $FFFFFFFF;
  ColDim = $FFB0B8C8;
  ColButton = $FF3C5078;

  FieldCount = 5;
  BtnConnect = 5;
  BtnOffline = 6;
  BtnQuit = 7;

type
  TStringListLite = array of string;

procedure SplitLines(const Text: string; out L: TStringListLite);
var
  S: string;
  P: Integer;
begin
  SetLength(L, 0);
  S := StringReplace(Text, #13, '', [rfReplaceAll]);
  while S <> '' do
  begin
    P := Pos(#10, S);
    if P = 0 then P := Length(S) + 1;
    SetLength(L, Length(L) + 1);
    L[High(L)] := Copy(S, 1, P - 1);
    Delete(S, 1, P);
  end;
end;

procedure Box(S: TGSurface; X, Y, W, H: Integer; Fill, Edge: Cardinal);
begin
  S.FillRect(X, Y, W, H, Edge);
  S.FillRect(X + 1, Y + 1, W - 2, H - 2, Fill);
end;

procedure FieldRect(I: Integer; out X, Y, W, H: Integer);
begin
  X := 250;
  Y := 190 + I * 34;
  W := 260;
  H := 26;
end;

procedure ButtonRect(I: Integer; out X, Y, W, H: Integer);
begin
  Y := 370;
  W := 120;
  H := 30;
  X := 120 + (I - BtnConnect) * 140;
end;

function FieldText(const F: TConnectForm; I: Integer): string;
begin
  case I of
    0: Result := F.Nick;
    1: Result := F.Host;
    2: Result := F.Port;
    3: Result := F.Account;
  else
    Result := F.Password;
  end;
end;

procedure SetFieldText(var F: TConnectForm; I: Integer; const T: string);
begin
  case I of
    0: F.Nick := T;
    1: F.Host := T;
    2: F.Port := T;
    3: F.Account := T;
  else
    F.Password := T;
  end;
end;

procedure DrawConnect(S: TGSurface; const F: TConnectForm; Focus: Integer);
const
  Labels: array[0..4] of string = ('Nickname', 'Server', 'Port', 'Account', 'Password');
  Btns: array[0..2] of string = ('Connect', 'Offline', 'Quit');
var
  I, X, Y, W, H: Integer;
  Logo: TGSurface;
  T: string;
  E: Cardinal;
begin
  S.Fill(ColBack);
  Logo := TGSurface.Create(0, 0);
  try
    if (F.LogoPath <> '') and LoadImageFile(F.LogoPath, Logo) and (Logo.Width > 0) then
      S.Blit(Logo, 0, 0, Logo.Width, Logo.Height, (S.Width - Logo.Width) div 2, 12)
    else
    begin
      T := 'Graal3D';
      DrawText(S, (S.Width - TextWidth(T, 5)) div 2, 40, T, ColText, 5);
      T := 'graal-delphi rebuild of the February 2000 client';
      DrawText(S, (S.Width - TextWidth(T, 1)) div 2, 90, T, ColDim, 1);
    end;
  finally
    Logo.Free;
  end;
  Box(S, 100, 175, 440, 240, ColPanel, ColEdge);
  for I := 0 to FieldCount - 1 do
  begin
    FieldRect(I, X, Y, W, H);
    DrawText(S, 120, Y + 6, Labels[I], ColText, 2);
    if I = Focus then E := ColFocus else E := ColEdge;
    Box(S, X, Y, W, H, ColField, E);
    T := FieldText(F, I);
    if I = 4 then T := StringOfChar('*', Length(T));
    while (T <> '') and (TextWidth(T + '_', 2) > W - 10) do Delete(T, 1, 1);
    if I = Focus then T := T + '_';
    DrawText(S, X + 5, Y + 6, T, ColText, 2);
  end;
  for I := BtnConnect to BtnQuit do
  begin
    ButtonRect(I, X, Y, W, H);
    Box(S, X, Y, W, H, ColButton, ColEdge);
    T := Btns[I - BtnConnect];
    DrawText(S, X + (W - TextWidth(T, 2)) div 2, Y + 8, T, ColText, 2);
  end;
  if F.Message <> '' then
  begin
    T := F.Message;
    if TextWidth(T, 1) > S.Width - 20 then T := Copy(T, 1, (S.Width - 20) div GlyphW);
    DrawText(S, (S.Width - TextWidth(T, 1)) div 2, 425, T, ColFocus, 1);
  end;
  T := 'Not affiliated with GraalOnline, Cyberjoueurs or Stephane Portha.';
  DrawText(S, (S.Width - TextWidth(T, 1)) div 2, S.Height - 12, T, ColDim, 1);
end;

function Inside(MX, MY, X, Y, W, H: Integer): Boolean;
begin
  Result := (MX >= X) and (MY >= Y) and (MX < X + W) and (MY < Y + H);
end;

function RunConnect(Win: TWindow3D; S: TGSurface; var F: TConnectForm;
  Stop: TStopFn): TConnectChoice;
var
  Focus, I, MX, MY, X, Y, W, H: Integer;
  Chars, T: string;
  C: Char;
begin
  Focus := 0;
  Result := ccQuit;
  while not Win.Closed do
  begin
    if Assigned(Stop) and Stop() then Exit;
    Win.Pump;
    Chars := Win.TakeChars;
    for I := 1 to Length(Chars) do
    begin
      C := Chars[I];
      case C of
        #9: Focus := (Focus + 1) mod FieldCount;
        #13:
          begin
            Result := ccConnect;
            Exit;
          end;
        #27: Exit;
        #8:
          begin
            T := FieldText(F, Focus);
            if T <> '' then SetFieldText(F, Focus, Copy(T, 1, Length(T) - 1));
          end;
      else
        if (C >= ' ') and (C <= '~') and (Length(FieldText(F, Focus)) < 200) then
          SetFieldText(F, Focus, FieldText(F, Focus) + C);
      end;
    end;
    if Win.TakeClick(MX, MY) then
    begin
      for I := 0 to FieldCount - 1 do
      begin
        FieldRect(I, X, Y, W, H);
        if Inside(MX, MY, X, Y, W, H) then Focus := I;
      end;
      for I := BtnConnect to BtnQuit do
      begin
        ButtonRect(I, X, Y, W, H);
        if Inside(MX, MY, X, Y, W, H) then
        begin
          case I of
            BtnConnect: Result := ccConnect;
            BtnOffline: Result := ccOffline;
          else
            Result := ccQuit;
          end;
          Exit;
        end;
      end;
    end;
    DrawConnect(S, F, Focus);
    Win.Present(S);
    Sleep(30);
  end;
end;

procedure DrawChatLine(S: TGSurface; Y: Integer; const Text: string; Focused: Boolean);
var
  T: string;
  E: Cardinal;
begin
  if Focused then E := ColFocus else E := ColEdge;
  Box(S, 0, Y, S.Width, S.Height - Y, ColField, E);
  T := Text;
  while (T <> '') and (TextWidth(T + '_', 2) > S.Width - 10) do Delete(T, 1, 1);
  if Focused then T := T + '_';
  DrawText(S, 5, Y + (S.Height - Y - 14) div 2, T, ColText, 2);
end;

procedure DrawMessageBox(S: TGSurface; const Title, Text: string);
var
  Lines: TStringListLite;
  Y, I: Integer;
begin
  Box(S, 80, 120, S.Width - 160, 200, ColPanel, ColEdge);
  DrawText(S, 95, 132, Title, ColFocus, 2);
  SplitLines(Text, Lines);
  Y := 160;
  for I := 0 to High(Lines) do
  begin
    if Y > 300 then Break;
    DrawText(S, 95, Y, Copy(Lines[I], 1, (S.Width - 190) div GlyphW), ColText, 1);
    Inc(Y, 10);
  end;
  DrawText(S, 95, 304, 'Enter to close', ColDim, 1);
end;

end.
