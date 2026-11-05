{ RealStart404: 4.04r2's own start screen.

  4.04r2 has no start window of its own: Graal4.exe opens its game window
  (TGraalWindow, 640 x 480 inside the frame) and the Torque engine draws
  the start screen in it, from the install's levels3d/gui pictures. The
  pictures here are those files (graalv4screen.jpg, graalv4title.png,
  defaulttextedit.png, defaultscroll.png, defaultradio.png,
  defaultcheck.png), compiled into this program from res/ (Res404). The
  places and colours were measured on the real 4.04r2 under Wine
  (2026-11-05):

  - the house picture (555 x 463) centred on dark green, the title over
    its top, 85 in from the left;
  - two panels, 75% dark red over the picture: Nickname, then Play as
    (one radio, Member), Account name (a combo box with the red shield
    arrow), Password and Save password;
  - Start under the panels, and Become a Member, Options and Offline Test
    along the bottom: flat red buttons with a black edge.

  Start logs in to the Login server named in license/license.graal (as
  the real 4.04r2 does; it has no server list). Offline Test plays the
  offline tutorial. Become a Member opens the sign-up page the licence
  file names. }
unit RealStart404;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GWindow, GStartScreen;

type
  TRealStartArt = class
  public
    Screen, Title, TextEdit, Scroll, Radio, Check: TGSurface;
    destructor Destroy; override;
    { The pictures compiled into this program (res/); False when one
      does not decode. }
    function Load: Boolean;
  end;

{ Draws the start screen in Win (640 x 480) until the player presses
  Start (R.Choice scOnline, R.Host and R.Port from Host and Port) or
  Offline Test (scTraining). SignupUrl is what Become a Member opens.
  False: closed, or Esc. }
function RunRealStart(Win: TGWindow; S: TGSurface; Art: TRealStartArt;
  const Host: string; Port: Integer; const SignupUrl, Message: string;
  StopRequested: TStopCheck; var R: TStartResult): Boolean;

{ The licence file's sign-up page (line 3), or the default. }
function LicenseSignupUrl(const Text: string): string;

const
  DefaultSignupUrl = 'http://www.graalonline.com/accounts/signup.php';
  { where the house picture sits in the 640 x 480 window }
  ScreenX = 42;
  ScreenY = 8;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Classes, SysUtils, Res404, GUiFont;

const
  ColBack = $FF004000;     { round the picture }
  ColLabel = $FFFFE0A0;    { the panels' words, bold }
  ColField = $FFEEC18A;    { what is typed in the fields }
  ColEditFill = $FF800000; { inside an edit box }
  ColPanel = $FF590000;    { the panels' fill, 75% over the picture }
  ColBtnText = $FFCCCC9A;

{ ---- art ---- }

destructor TRealStartArt.Destroy;
begin
  Screen.Free;
  Title.Free;
  TextEdit.Free;
  Scroll.Free;
  Radio.Free;
  Check.Free;
  inherited Destroy;
end;

function TRealStartArt.Load: Boolean;

  function Pic(const Name: string): TGSurface;
  var
    D: string;
  begin
    Result := nil;
    if not ResFile(Name, D) then Exit;
    Result := TGSurface.Create(0, 0);
    if not LoadImageData(D, Name, Result, False) or (Result.Width = 0) then
      FreeAndNil(Result);
  end;

begin
  Screen := Pic('GRAALV4SCREEN');
  Title := Pic('GRAALV4TITLE');
  TextEdit := Pic('DEFAULTTEXTEDIT');
  Scroll := Pic('DEFAULTSCROLL');
  Radio := Pic('DEFAULTRADIO');
  Check := Pic('DEFAULTCHECK');
  Result := (Screen <> nil) and (Title <> nil) and (TextEdit <> nil) and
    (Scroll <> nil) and (Radio <> nil) and (Check <> nil);
end;

function LicenseSignupUrl(const Text: string): string;
var
  L: TStringList;
begin
  Result := DefaultSignupUrl;
  L := TStringList.Create;
  try
    L.Text := Text;
    if (L.Count > 3) and (Pos('://', L[3]) > 0) then Result := Trim(L[3]);
  finally
    L.Free;
  end;
end;

{$IFDEF MSWINDOWS}
function ShellExecuteA(Wnd: HWND; Op, FileName, Params, Dir: PAnsiChar;
  Show: Integer): HINST; stdcall; external 'shell32.dll';
{$ENDIF}

function OpenUrl(const Url: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := ShellExecuteA(0, 'open', PAnsiChar(AnsiString(Url)), nil, nil, SW_SHOWNORMAL) > 32;
{$ELSE}
  Result := False;
{$ENDIF}
end;

{ ---- drawing ---- }

function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

type
  TBox = record
    X, Y, W, H: Integer;
  end;

function Box(X, Y, W, H: Integer): TBox;
begin
  Result.X := X + ScreenX;
  Result.Y := Y + ScreenY;
  Result.W := W;
  Result.H := H;
end;

function Inside(const B: TBox; X, Y: Integer): Boolean;
begin
  Result := (X >= B.X) and (Y >= B.Y) and (X < B.X + B.W) and (Y < B.Y + B.H);
end;

{ Src over S with its alpha; pure blue (the Torque pictures' see-through
  key) is left out }
procedure Draw(S, Src: TGSurface; SX, SY, W, H, DX, DY: Integer);
var
  I, J, X, Y: Integer;
  C, D, A: Cardinal;
begin
  if Src = nil then Exit;
  for J := 0 to H - 1 do
  begin
    Y := DY + J;
    if (Y < 0) or (Y >= S.Height) or (SY + J < 0) or (SY + J >= Src.Height) then Continue;
    for I := 0 to W - 1 do
    begin
      X := DX + I;
      if (X < 0) or (X >= S.Width) or (SX + I < 0) or (SX + I >= Src.Width) then Continue;
      C := Src.Pixels[SX + I + (SY + J) * Src.Width];
      A := C shr 24;
      if (A = 0) or ((C and $FFFFFF) = $0000FF) then Continue;
      if A = 255 then
        S.Pixels[X + Y * S.Width] := C
      else
      begin
        D := S.Pixels[X + Y * S.Width];
        S.Pixels[X + Y * S.Width] := $FF000000 or
          ((((C shr 16) and 255) * A + ((D shr 16) and 255) * (255 - A)) div 255) shl 16 or
          ((((C shr 8) and 255) * A + ((D shr 8) and 255) * (255 - A)) div 255) shl 8 or
          (((C and 255) * A + (D and 255) * (255 - A)) div 255);
      end;
    end;
  end;
end;

{ Colour over S at three quarters, a quarter of what is under it showing }
procedure Shade(S: TGSurface; const B: TBox; Color: Cardinal);
var
  I, J: Integer;
  D: Cardinal;
begin
  for J := B.Y to B.Y + B.H - 1 do
    for I := B.X to B.X + B.W - 1 do
      if (I >= 0) and (J >= 0) and (I < S.Width) and (J < S.Height) then
      begin
        D := S.Pixels[I + J * S.Width];
        S.Pixels[I + J * S.Width] := $FF000000 or
          ((((Color shr 16) and 255) * 3 + ((D shr 16) and 255)) div 4) shl 16 or
          ((((Color shr 8) and 255) * 3 + ((D shr 8) and 255)) div 4) shl 8 or
          (((Color and 255) * 3 + (D and 255)) div 4);
      end;
end;

{ a panel: dark grey then black over the top and left, white under the
  bottom and right }
procedure Panel(S: TGSurface; const B: TBox);
begin
  Shade(S, B, ColPanel);
  S.FillRect(B.X, B.Y, B.W, 1, $FF404040);
  S.FillRect(B.X, B.Y, 1, B.H, $FF404040);
  S.FillRect(B.X + 1, B.Y + 1, B.W - 2, 1, $FF000000);
  S.FillRect(B.X + 1, B.Y + 1, 1, B.H - 2, $FF000000);
  S.FillRect(B.X, B.Y + B.H - 1, B.W, 1, $FFFFFFFF);
  S.FillRect(B.X + B.W - 1, B.Y, 1, B.H, $FFFFFFFF);
end;

{ an edit box: defaulttextedit.png's nine 5 x 5 pieces round a dark red
  inside; a combo box adds defaultscroll.png's red shield arrow }
procedure Edit(S: TGSurface; Art: TRealStartArt; const B: TBox; const Text: string;
  Focused, Masked, Combo: Boolean);
var
  T: string;
  I, Right: Integer;
begin
  S.FillRect(B.X + 5, B.Y + 5, B.W - 10, B.H - 10, ColEditFill);
  for I := B.X + 5 to B.X + B.W - 6 do
  begin
    Draw(S, Art.TextEdit, 6, 1, 1, 5, I, B.Y);
    Draw(S, Art.TextEdit, 6, 13, 1, 5, I, B.Y + B.H - 5);
  end;
  for I := B.Y + 5 to B.Y + B.H - 6 do
  begin
    Draw(S, Art.TextEdit, 0, 7, 5, 1, B.X, I);
    Draw(S, Art.TextEdit, 12, 7, 5, 1, B.X + B.W - 5, I);
  end;
  Draw(S, Art.TextEdit, 0, 1, 5, 5, B.X, B.Y);
  Draw(S, Art.TextEdit, 12, 1, 5, 5, B.X + B.W - 5, B.Y);
  Draw(S, Art.TextEdit, 0, 13, 5, 5, B.X, B.Y + B.H - 5);
  Draw(S, Art.TextEdit, 12, 13, 5, 5, B.X + B.W - 5, B.Y + B.H - 5);
  Right := B.X + B.W - 4;
  if Combo then
  begin
    { the down arrow, at rest: the fourth piece of defaultscroll.png's
      top row }
    Draw(S, Art.Scroll, 55, 1, 15, 17, B.X + B.W - 17, B.Y + 2);
    Right := B.X + B.W - 18;
  end;
  if Masked then T := StringOfChar('*', Length(Text)) else T := Text;
  while (T <> '') and (UiTextWidth(T, ufRegular) > Right - B.X - 8) do Delete(T, 1, 1);
  UiDrawText(S, B.X + 5, B.Y + (B.H - UiLineH) div 2, T, ColField, ufRegular);
  if Focused and ((NowMs div 500) mod 2 = 0) then
    S.FillRect(B.X + 5 + UiTextWidth(T, ufRegular), B.Y + 5, 1, B.H - 10, ColField);
end;

{ a flat red button with a black edge, the caption centred }
procedure Button(S: TGSurface; const B: TBox; const Caption: string; Down: Boolean);
var
  D: Integer;
begin
  S.FillRect(B.X, B.Y, B.W, B.H, $FF000000);
  S.FillRect(B.X + 1, B.Y + 1, B.W - 2, B.H - 2, $FF9B2113);
  if Down then
  begin
    S.FillRect(B.X + 1, B.Y + 1, B.W - 2, 1, $FF330600);
    S.FillRect(B.X + 1, B.Y + 1, 1, B.H - 2, $FF4E0902);
    D := 1;
  end
  else
  begin
    S.FillRect(B.X + 1, B.Y + 1, B.W - 2, 1, $FFC74C3F);
    S.FillRect(B.X + 1, B.Y + 2, 1, B.H - 3, $FF6E1208);
    S.FillRect(B.X + 2, B.Y + B.H - 3, B.W - 3, 1, $FF4E0902);
    S.FillRect(B.X + 1, B.Y + B.H - 2, B.W - 2, 1, $FF330600);
    S.FillRect(B.X + B.W - 2, B.Y + 2, 1, B.H - 4, $FF9B1C0D);
    D := 0;
  end;
  UiDrawText(S, B.X + (B.W - UiTextWidth(Caption, ufRegular)) div 2 + D,
    B.Y + (B.H - UiLineH) div 2 + D, Caption, ColBtnText, ufRegular);
end;

procedure Labelled(S: TGSurface; X, Y: Integer; const T: string; Face: TUiFace);
begin
  UiDrawText(S, X + ScreenX, Y + ScreenY, T, ColLabel, Face);
end;

procedure TypeInto(var Text: string; const Chars: string; MaxLen: Integer);
var
  I: Integer;
begin
  for I := 1 to Length(Chars) do
    if Chars[I] = #8 then
    begin
      if Text <> '' then Delete(Text, Length(Text), 1);
    end
    else if (Chars[I] >= ' ') and (Chars[I] <= '~') and (Length(Text) < MaxLen) then
      Text := Text + Chars[I];
end;

{ ---- the screen ---- }

function RunRealStart(Win: TGWindow; S: TGSurface; Art: TRealStartArt;
  const Host: string; Port: Integer; const SignupUrl, Message: string;
  StopRequested: TStopCheck; var R: TStartResult): Boolean;
var
  Focus, CX, CY, PressBtn: Integer;
  Clicked, SavePw: Boolean;
  Chars, Note: string;
  P1, P2, FNick, FAcc, FPw, BStart, BMember, BOptions, BOffline, CSave: TBox;
  PressUntil: Int64;

  function Pressed(Id: Integer): Boolean;
  begin
    Result := (PressBtn = Id) and (NowMs < PressUntil);
  end;

  procedure Press(Id: Integer);
  begin
    PressBtn := Id;
    PressUntil := NowMs + 150;
  end;

begin
  Result := False;
  R.Choice := scQuit;
  Note := Message;
  Focus := 0;
  SavePw := True;
  PressBtn := 0;
  PressUntil := 0;
  { measured on the real 4.04r2, from the house picture's top left }
  P1 := Box(135, 155, 290, 50);
  P2 := Box(70, 220, 415, 80);
  FNick := Box(256, 165, 150, 22);
  FAcc := Box(322, 225, 150, 22);
  FPw := Box(322, 250, 150, 22);
  CSave := Box(323, 282, 100, 14);
  BStart := Box(251, 331, 48, 33);
  BMember := Box(81, 416, 148, 23);
  BOptions := Box(241, 416, 98, 23);
  BOffline := Box(351, 416, 118, 23);
  while True do
  begin
    Win.Pump;
    if Win.Closed or (Assigned(StopRequested) and StopRequested()) then Exit;
    Clicked := Win.TakeClick(CX, CY);
    Chars := Win.TakeChars;
    if Pos(#27, Chars) > 0 then Exit;
    if Pos(#9, Chars) > 0 then
    begin
      Focus := (Focus + 1) mod 3;
      Chars := StringReplace(Chars, #9, '', [rfReplaceAll]);
    end;
    case Focus of
      0: TypeInto(R.Nickname, Chars, 20);
      1: TypeInto(R.Account, Chars, 30);
      2: TypeInto(R.Password, Chars, 30);
    end;
    if Clicked then
    begin
      if Inside(FNick, CX, CY) then Focus := 0;
      if Inside(FAcc, CX, CY) then Focus := 1;
      if Inside(FPw, CX, CY) then Focus := 2;
      if Inside(CSave, CX, CY) then SavePw := not SavePw;
      if Inside(BMember, CX, CY) then
      begin
        Press(2);
        if not OpenUrl(SignupUrl) then Note := 'Sign up at ' + SignupUrl;
      end;
      if Inside(BOptions, CX, CY) then
      begin
        Press(3);
        Note := 'Options are not built yet.';
      end;
      if Inside(BOffline, CX, CY) then
      begin
        R.Choice := scTraining;
        Result := True;
        Exit;
      end;
    end;
    if (Clicked and Inside(BStart, CX, CY)) or (Pos(#13, Chars) > 0) then
    begin
      R.Choice := scOnline;
      R.Host := Host;
      R.Port := Port;
      R.ServerName := '';
      Result := True;
      Exit;
    end;

    { drawing }
    S.Fill(ColBack);
    Draw(S, Art.Screen, 0, 0, Art.Screen.Width, Art.Screen.Height, ScreenX, ScreenY);
    Draw(S, Art.Title, 0, 0, Art.Title.Width, Art.Title.Height, ScreenX + 85, ScreenY);
    Panel(S, P1);
    Panel(S, P2);
    Labelled(S, 152, 166, 'Nickname:', ufBold);
    Labelled(S, 87, 226, 'Play as:', ufBold);
    Labelled(S, 202, 226, 'Account name:', ufBold);
    Labelled(S, 202, 251, 'Password:', ufBold);
    Edit(S, Art, FNick, R.Nickname, Focus = 0, False, False);
    Edit(S, Art, FAcc, R.Account, Focus = 1, False, True);
    Edit(S, Art, FPw, R.Password, Focus = 2, True, False);
    { Member, picked: defaultradio.png's second state; Save password:
      defaultcheck.png's second (ticked) or first }
    Draw(S, Art.Radio, 0, 15, 13, 13, ScreenX + 87, ScreenY + 276);
    Labelled(S, 102, 274, 'Member', ufRegular);
    if SavePw then Draw(S, Art.Check, 0, 15, 13, 13, ScreenX + 323, ScreenY + 282)
    else Draw(S, Art.Check, 0, 1, 13, 13, ScreenX + 323, ScreenY + 282);
    Labelled(S, 337, 280, 'Save password', ufRegular);
    Button(S, BStart, 'Start', False);
    Button(S, BMember, 'Become a Member', Pressed(2));
    Button(S, BOptions, 'Options', Pressed(3));
    Button(S, BOffline, 'Offline Test', False);
    if Note <> '' then
    begin
      CX := ScreenX + (Art.Screen.Width - UiTextWidth(Note, ufBold)) div 2;
      UiDrawText(S, CX + 1, ScreenY + 379, Note, $FF000000, ufBold);
      UiDrawText(S, CX, ScreenY + 378, Note, ColLabel, ufBold);
    end;
    Win.Present(S);
    Sleep(20);
  end;
end;

end.
