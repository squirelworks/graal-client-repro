{ Connect3D: the start window (the original's TConnectFrame) and the
  screen drawing around the 3D view.

  The start window is Graal3D's own: its own window, "Graal 3D", 433 x 321
  inside the frame, drawn on the picture Graal3D.exe carries in that form
  (TConnectFrame.Image1, compiled in from res/STARTIMAGE.jpg through
  Res3D; the words Nickname, Server IP, Port, Account and Password are
  part of that picture). The five fields sit where the form puts them
  (Edit3, ComboBox5, Edit2, Edit4, Edit5 at x 114, y 96 / 135 / 171 /
  208 / 246, 185 x 24): dark red (the form's Color 64) with white text
  and Windows' sunken edge; Server IP is a combo box. Two buttons, as the
  later beta's form has them (read from its TConnectFrame): "&Start"
  (336, 240, 75 x 28) and "Start Local" (328, 272, 89 x 28), which plays
  offline; no Quit (the window's close button quits). The start picture
  in the beta is byte-identical to the February 2000 one. Seen under Wine (2026-11-05), the nickname starts empty and the
  others come from graal3dconfig.txt (account and password guest). }
unit Connect3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, Window3D;

const
  { TConnectFrame's client area (its Image1) }
  ConnectW = 433;
  ConnectH = 321;

type
  TConnectChoice = (ccQuit, ccConnect, ccOffline);
  TStopFn = function: Boolean;

  TConnectForm = record
    Nick, Host, Port, Account, Password: string;
    Message: string;
    LogoPath: string;
  end;

{ Shows the start window until a choice is made. S is ConnectW x
  ConnectH. }
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
  SysUtils, GFont, GUiFont, Res3D;

const
  ColBack = $FF20283A;
  ColPanel = $FF2E3A52;
  ColEdge = $FF8090B0;
  ColField = $FF101820;
  ColFocus = $FFFFD060;
  ColText = $FFFFFFFF;
  ColDim = $FFB0B8C8;

  FieldCount = 5;
  { the form's Color = 64: TColor $000040, red 64 }
  ColEdit = $FF400000;
  ColWhite = $FFFFFFFF;
  ColFace = $FFF5F5F5;

type
  TStringListLite = array of string;

var
  StartImage: TGSurface;

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
const
  Tops: array[0..4] of Integer = (96, 135, 171, 208, 246);
begin
  X := 114;
  Y := Tops[I];
  W := 185;
  H := 24;
end;

procedure StartRect(out X, Y, W, H: Integer);
begin
  X := 336;
  Y := 240;
  W := 75;
  H := 28;
end;

procedure LocalRect(out X, Y, W, H: Integer);
begin
  X := 328;
  Y := 272;
  W := 89;
  H := 28;
end;

{ a push button with Windows' raised edges; Under is the index of the
  & letter (0 for none) }
procedure DrawButton(S: TGSurface; X, Y, W, H: Integer; const T: string;
  Under: Integer);
var
  TW, AX, AY: Integer;
begin
  S.FillRect(X, Y, W, H, $FF000000);
  S.FillRect(X + 1, Y + 1, W - 2, H - 2, $FFF5F5F5);
  S.FillRect(X + 1, Y + 1, W - 2, 1, $FFFFFFFF);
  S.FillRect(X + 1, Y + 1, 1, H - 2, $FFFFFFFF);
  S.FillRect(X + 2, Y + 2, W - 4, 1, $FFE3E3E3);
  S.FillRect(X + 2, Y + 2, 1, H - 4, $FFE3E3E3);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, $FF6A6A6A);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, $FF6A6A6A);
  S.FillRect(X + 2, Y + H - 3, W - 4, 1, $FFA6A6A6);
  S.FillRect(X + W - 3, Y + 2, 1, H - 4, $FFA6A6A6);
  TW := UiTextWidth(T, ufRegular);
  AX := X + (W - TW) div 2;
  AY := Y + (H - UiLineH) div 2;
  UiDrawText(S, AX, AY, T, $FF000000, ufRegular);
  if Under > 0 then
    S.FillRect(AX + UiTextWidth(Copy(T, 1, Under - 1), ufRegular), AY + UiLineH - 3,
      UiTextWidth(Copy(T, Under, 1), ufRegular), 1, $FF000000);
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

function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

{ The picture of TConnectFrame.Image1, decoded once. }
function Picture: TGSurface;
var
  D: string;
begin
  if StartImage = nil then
  begin
    StartImage := TGSurface.Create(0, 0);
    if ResFile('STARTIMAGE', D) then LoadImageData(D, 'startimage.jpg', StartImage, False);
  end;
  Result := StartImage;
end;

{ An edit box with Windows' sunken edge: grey 166 then 106 over the top
  and left, 227 then white under the bottom and right (as drawn under
  Wine) }
procedure Sunken(S: TGSurface; X, Y, W, H: Integer);
begin
  S.FillRect(X, Y, W, 1, $FFA6A6A6);
  S.FillRect(X, Y, 1, H, $FFA6A6A6);
  S.FillRect(X + 1, Y + 1, W - 2, 1, $FF6A6A6A);
  S.FillRect(X + 1, Y + 1, 1, H - 2, $FF6A6A6A);
  S.FillRect(X, Y + H - 1, W, 1, ColWhite);
  S.FillRect(X + W - 1, Y, 1, H, ColWhite);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, $FFE3E3E3);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, $FFE3E3E3);
end;

procedure DrawConnect(S: TGSurface; const F: TConnectForm; Focus: Integer);
var
  I, X, Y, W, H, R, AX, AY, TW: Integer;
  P: TGSurface;
  T: string;
begin
  S.Fill($FF000000);
  P := Picture;
  if P.Width > 0 then S.Blit(P, 0, 0, P.Width, P.Height, 0, 0)
  else
  begin
    { no picture: the words it carries }
    S.Fill($FF5A3A1E);
    UiDrawText(S, 160, 30, 'Graal 3d', ColWhite, ufBold);
    for I := 0 to FieldCount - 1 do
    begin
      FieldRect(I, X, Y, W, H);
      case I of
        0: T := 'Nickname';
        1: T := 'Server IP';
        2: T := 'Port';
        3: T := 'Account';
      else
        T := 'Password';
      end;
      UiDrawText(S, 36, Y + 4, T, ColWhite, ufRegular);
    end;
  end;
  for I := 0 to FieldCount - 1 do
  begin
    FieldRect(I, X, Y, W, H);
    S.FillRect(X + 2, Y + 2, W - 4, H - 4, ColEdit);
    Sunken(S, X, Y, W, H);
    R := X + W - 2;
    if I = 1 then
    begin
      { ComboBox5's drop-down button: 17 wide inside the edge }
      R := X + W - 2 - 17;
      S.FillRect(R, Y + 2, 17, H - 4, ColFace);
      S.FillRect(R, Y + 2, 17, 1, ColWhite);
      S.FillRect(R, Y + 2, 1, H - 4, ColWhite);
      S.FillRect(R + 1, Y + 3, 15, 1, $FFE3E3E3);
      S.FillRect(R + 1, Y + 3, 1, H - 6, $FFE3E3E3);
      S.FillRect(R + 15, Y + 2, 1, H - 4, $FFA6A6A6);
      S.FillRect(R + 16, Y + 2, 1, H - 4, $FF6A6A6A);
      S.FillRect(R, Y + H - 4, 17, 1, $FFA6A6A6);
      S.FillRect(R, Y + H - 3, 17, 1, $FF6A6A6A);
      AX := R + 5;
      AY := Y + (H - 4) div 2;
      for AX := 0 to 3 do S.FillRect(R + 5 + AX, AY + AX, 7 - 2 * AX, 1, $FF000000);
    end;
    T := FieldText(F, I);
    if I = 4 then T := StringOfChar('*', Length(T));
    while (T <> '') and (UiTextWidth(T, ufRegular) > R - X - 6) do Delete(T, 1, 1);
    TW := UiTextWidth(T, ufRegular);
    UiDrawText(S, X + 3, Y + (H - UiLineH) div 2, T, ColWhite, ufRegular);
    if (I = Focus) and ((NowMs div 500) mod 2 = 0) then
      S.FillRect(X + 3 + TW, Y + 4, 1, H - 8, ColWhite);
  end;
  { &Start (the default push button) and Start Local }
  StartRect(X, Y, W, H);
  DrawButton(S, X, Y, W, H, 'Start', 1);
  LocalRect(X, Y, W, H);
  DrawButton(S, X, Y, W, H, 'Start Local', 0);
  if F.Message <> '' then
  begin
    T := F.Message;
    while (T <> '') and (UiTextWidth(T, ufRegular) > ConnectW - 12) do Delete(T, Length(T), 1);
    S.FillRect(0, ConnectH - UiLineH - 4, ConnectW, UiLineH + 4, $C0000000);
    UiDrawText(S, (ConnectW - UiTextWidth(T, ufRegular)) div 2, ConnectH - UiLineH - 2, T,
      $FFFFD060, ufRegular);
  end;
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
            { Start is the default button }
            Result := ccConnect;
            Exit;
          end;
        #27: ;
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
      StartRect(X, Y, W, H);
      if Inside(MX, MY, X, Y, W, H) then
      begin
        Result := ccConnect;
        Exit;
      end;
      LocalRect(X, Y, W, H);
      if Inside(MX, MY, X, Y, W, H) then
      begin
        Result := ccOffline;
        Exit;
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

initialization
finalization
  StartImage.Free;
end.
