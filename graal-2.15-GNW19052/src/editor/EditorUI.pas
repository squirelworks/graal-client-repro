{ EditorUI: the small widget kit the 2.05 editor screen and its dialogs
  are drawn with.

  2.05 used Delphi VCL forms (TPanel, TSpeedButton, TEdit, TListView ...)
  around a DirectDraw board. The rebuild draws everything into the one
  software surface, so these helpers draw Windows-classic looking
  controls: raised and sunken 3D edges on button-face grey. Layout comes
  from the 2.05 form resources (positions and captions); see
  graal_analysis client-internals/level-editor-205.md.

  Input reaches the editor as one TEditorInput per frame, so tests can
  drive the editor without a window. }
unit EditorUI;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface;

const
  ColFace = $FFC0C0C0;    { clBtnFace }
  ColLight = $FFFFFFFF;   { clBtnHighlight }
  ColShadow = $FF808080;  { clBtnShadow }
  ColDark = $FF000000;    { cl3DDkShadow }
  ColWindow = $FFFFFFFF;  { clWindow }
  ColText = $FF000000;
  ColGrayText = $FF808080;
  ColHighlight = $FF000080; { clHighlight }
  ColHighlightText = $FFFFFFFF;
  ColTitle = $FF000080;   { active caption }
  ColYellow = $FFFFFF00;  { clYellow }

  CharW = 6;
  LineH = 16;            { row height of lists and edits }

type
  TEditorInput = record
    MouseX, MouseY: Integer;
    Left, Right: Boolean;              { held now }
    LeftPress, RightPress: Boolean;    { went down since the last frame }
    PressX, PressY: Integer;           { where the left press was }
    RightX, RightY: Integer;
    Ctrl, Shift: Boolean;
    Chars: string;                     { typed: printable, #8, #9, #13, #27, ^A..^Z }
    Wheel: Integer;
    Up, Down, LeftKey, RightKey: Boolean; { held }
    Del, Ins, F4, F5, Esc: Boolean;    { pressed since the last frame }
    NowMs: Int64;
  end;

  TRectI = record
    X, Y, W, H: Integer;
  end;

function RectI(X, Y, W, H: Integer): TRectI;
function InRect(const R: TRectI; X, Y: Integer): Boolean;
procedure Raised(S: TGSurface; const R: TRectI);
procedure Sunken(S: TGSurface; const R: TRectI);
{ A raised panel filled with button face. }
procedure FacePanel(S: TGSurface; const R: TRectI);
procedure DrawLabel(S: TGSurface; X, Y: Integer; const T: string; Color: Cardinal);
procedure TextClip(S: TGSurface; X, Y, W: Integer; const T: string; Color: Cardinal);
procedure CenterText(S: TGSurface; const R: TRectI; const T: string; Color: Cardinal);
procedure ButtonCtl(S: TGSurface; const R: TRectI; const Caption: string; Down, Enabled: Boolean);
procedure EditCtl(S: TGSurface; const R: TRectI; const T: string; Focused, Enabled: Boolean);
procedure CheckCtl(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
procedure RadioCtl(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
procedure GroupCtl(S: TGSurface; const R: TRectI; const Caption: string);
{ A scroll bar; Pos/Max in content pixels, Page the visible span. }
procedure ScrollCtl(S: TGSurface; const R: TRectI; Vertical: Boolean; Pos, Max, Page: Integer);
{ The scroll position for a click or drag at (X, Y) on a scroll bar. }
function ScrollPosAt(const R: TRectI; Vertical: Boolean; X, Y, Max, Page: Integer): Integer;
procedure DashRect(S: TGSurface; X, Y, W, H: Integer; C1, C2: Cardinal);
procedure FrameRect(S: TGSurface; X, Y, W, H: Integer; C: Cardinal);
{ Typing into a one-line field. Returns True when Enter was pressed. }
function EditLine(var T: string; const Chars: string; MaxLen: Integer): Boolean;
{ Typing into a multi-line text: Enter adds a line break. }
procedure EditMulti(var T: string; const Chars: string; MaxLen: Integer);
{ Word wrap Text into lines of at most W pixels (existing #10 kept). }
function WrapLines(const T: string; W: Integer): string;

type
  TDialogResult = (drNone, drOk, drCancel, drYes, drNo);

  { A modal box over the editor. Step returns False once it has closed. }
  TEditorDialog = class
  public
    Bounds: TRectI;
    Caption: string;
    Result: TDialogResult;
    Tag: Integer;
    constructor Create(const ACaption: string; W, H: Integer);
    function Step(const I: TEditorInput): Boolean; virtual; abstract;
    procedure Draw(S: TGSurface); virtual;
    { Client area origin. }
    function CX: Integer;
    function CY: Integer;
  end;

  { One line of text with OK / Cancel: TLoadLevel and the save-as name. }
  TPromptDialog = class(TEditorDialog)
  public
    Prompt, Value: string;
    constructor Create(const ACaption, APrompt, AValue: string);
    function Step(const I: TEditorInput): Boolean; override;
    procedure Draw(S: TGSurface); override;
  end;

  { A message with buttons: OK, or Yes / No (/ Cancel). }
  TMessageDialog = class(TEditorDialog)
  public
    Msg: string;
    Buttons: Integer; { 1 = OK, 2 = Yes/No, 3 = Yes/No/Cancel }
    constructor Create(const ACaption, AMsg: string; AButtons: Integer);
    function Step(const I: TEditorInput): Boolean; override;
    procedure Draw(S: TGSurface); override;
  end;

implementation

uses
  SysUtils, GFont;

function RectI(X, Y, W, H: Integer): TRectI;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function InRect(const R: TRectI; X, Y: Integer): Boolean;
begin
  Result := (X >= R.X) and (Y >= R.Y) and (X < R.X + R.W) and (Y < R.Y + R.H);
end;

procedure Raised(S: TGSurface; const R: TRectI);
begin
  S.FillRect(R.X, R.Y, R.W, 1, ColLight);
  S.FillRect(R.X, R.Y, 1, R.H, ColLight);
  S.FillRect(R.X, R.Y + R.H - 1, R.W, 1, ColDark);
  S.FillRect(R.X + R.W - 1, R.Y, 1, R.H, ColDark);
  S.FillRect(R.X + 1, R.Y + R.H - 2, R.W - 2, 1, ColShadow);
  S.FillRect(R.X + R.W - 2, R.Y + 1, 1, R.H - 2, ColShadow);
end;

procedure Sunken(S: TGSurface; const R: TRectI);
begin
  S.FillRect(R.X, R.Y, R.W, 1, ColShadow);
  S.FillRect(R.X, R.Y, 1, R.H, ColShadow);
  S.FillRect(R.X + 1, R.Y + 1, R.W - 2, 1, ColDark);
  S.FillRect(R.X + 1, R.Y + 1, 1, R.H - 2, ColDark);
  S.FillRect(R.X, R.Y + R.H - 1, R.W, 1, ColLight);
  S.FillRect(R.X + R.W - 1, R.Y, 1, R.H, ColLight);
end;

procedure FacePanel(S: TGSurface; const R: TRectI);
begin
  S.FillRect(R.X, R.Y, R.W, R.H, ColFace);
  Raised(S, R);
end;

procedure DrawLabel(S: TGSurface; X, Y: Integer; const T: string; Color: Cardinal);
begin
  DrawText(S, X, Y, T, Color, 1);
end;

procedure TextClip(S: TGSurface; X, Y, W: Integer; const T: string; Color: Cardinal);
var
  U: string;
begin
  U := T;
  while (U <> '') and (TextWidth(U, 1) > W) do Delete(U, Length(U), 1);
  DrawText(S, X, Y, U, Color, 1);
end;

procedure CenterText(S: TGSurface; const R: TRectI; const T: string; Color: Cardinal);
begin
  DrawText(S, R.X + (R.W - TextWidth(T, 1)) div 2, R.Y + (R.H - GlyphH) div 2 + 1, T, Color, 1);
end;

procedure ButtonCtl(S: TGSurface; const R: TRectI; const Caption: string; Down, Enabled: Boolean);
var
  C: Cardinal;
  T: TRectI;
begin
  S.FillRect(R.X, R.Y, R.W, R.H, ColFace);
  if Down then Sunken(S, R) else Raised(S, R);
  if Enabled then C := ColText else C := ColGrayText;
  T := R;
  if Down then begin Inc(T.X); Inc(T.Y); end;
  CenterText(S, T, Caption, C);
end;

procedure EditCtl(S: TGSurface; const R: TRectI; const T: string; Focused, Enabled: Boolean);
var
  U: string;
begin
  if Enabled then S.FillRect(R.X, R.Y, R.W, R.H, ColWindow)
  else S.FillRect(R.X, R.Y, R.W, R.H, ColFace);
  Sunken(S, R);
  U := T;
  if Focused then U := U + '_';
  while (U <> '') and (TextWidth(U, 1) > R.W - 8) do Delete(U, 1, 1);
  DrawText(S, R.X + 4, R.Y + (R.H - GlyphH) div 2 + 1, U, ColText, 1);
end;

procedure CheckCtl(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
begin
  S.FillRect(X, Y, 13, 13, ColWindow);
  Sunken(S, RectI(X, Y, 13, 13));
  if Checked then
  begin
    S.FillRect(X + 3, Y + 6, 2, 3, ColText);
    S.FillRect(X + 5, Y + 7, 2, 3, ColText);
    S.FillRect(X + 7, Y + 3, 2, 5, ColText);
  end;
  DrawText(S, X + 18, Y + 3, Caption, ColText, 1);
end;

procedure RadioCtl(S: TGSurface; X, Y: Integer; const Caption: string; Checked: Boolean);
begin
  S.FillRect(X + 2, Y, 8, 12, ColWindow);
  S.FillRect(X, Y + 2, 12, 8, ColWindow);
  S.FillRect(X + 2, Y, 8, 1, ColShadow);
  S.FillRect(X, Y + 2, 1, 8, ColShadow);
  S.FillRect(X + 2, Y + 11, 8, 1, ColLight);
  S.FillRect(X + 11, Y + 2, 1, 8, ColLight);
  if Checked then S.FillRect(X + 4, Y + 4, 4, 4, ColText);
  DrawText(S, X + 18, Y + 3, Caption, ColText, 1);
end;

procedure GroupCtl(S: TGSurface; const R: TRectI; const Caption: string);
var
  TW: Integer;
begin
  FrameRect(S, R.X, R.Y + 4, R.W, R.H - 4, ColShadow);
  FrameRect(S, R.X + 1, R.Y + 5, R.W - 2, R.H - 6, ColLight);
  TW := TextWidth(Caption, 1);
  S.FillRect(R.X + 6, R.Y, TW + 6, 10, ColFace);
  DrawText(S, R.X + 9, R.Y + 1, Caption, ColText, 1);
end;

procedure FrameRect(S: TGSurface; X, Y, W, H: Integer; C: Cardinal);
begin
  if (W <= 0) or (H <= 0) then Exit;
  S.FillRect(X, Y, W, 1, C);
  S.FillRect(X, Y + H - 1, W, 1, C);
  S.FillRect(X, Y, 1, H, C);
  S.FillRect(X + W - 1, Y, 1, H, C);
end;

procedure DashRect(S: TGSurface; X, Y, W, H: Integer; C1, C2: Cardinal);
var
  I: Integer;

  procedure P(PX, PY, K: Integer);
  begin
    if (PX < 0) or (PY < 0) or (PX >= S.Width) or (PY >= S.Height) then Exit;
    if (K div 3) mod 2 = 0 then S.Pixels[PX + PY * S.Width] := C1
    else S.Pixels[PX + PY * S.Width] := C2;
  end;

begin
  for I := 0 to W - 1 do
  begin
    P(X + I, Y, I);
    P(X + I, Y + H - 1, I);
  end;
  for I := 0 to H - 1 do
  begin
    P(X, Y + I, I);
    P(X + W - 1, Y + I, I);
  end;
end;

procedure ScrollCtl(S: TGSurface; const R: TRectI; Vertical: Boolean; Pos, Max, Page: Integer);
var
  Len, ThumbLen, ThumbPos, A: Integer;
begin
  S.FillRect(R.X, R.Y, R.W, R.H, $FFE0E0E0);
  if Vertical then
  begin
    A := R.W;
    ButtonCtl(S, RectI(R.X, R.Y, R.W, A), '^', False, True);
    ButtonCtl(S, RectI(R.X, R.Y + R.H - A, R.W, A), 'v', False, True);
    Len := R.H - 2 * A;
  end
  else
  begin
    A := R.H;
    ButtonCtl(S, RectI(R.X, R.Y, A, R.H), '<', False, True);
    ButtonCtl(S, RectI(R.X + R.W - A, R.Y, A, R.H), '>', False, True);
    Len := R.W - 2 * A;
  end;
  if (Max <= 0) or (Len <= 8) then Exit;
  ThumbLen := Len * Page div (Max + Page);
  if ThumbLen < 8 then ThumbLen := 8;
  ThumbPos := (Len - ThumbLen) * Pos div Max;
  if Vertical then
    ButtonCtl(S, RectI(R.X, R.Y + A + ThumbPos, R.W, ThumbLen), '', False, True)
  else
    ButtonCtl(S, RectI(R.X + A + ThumbPos, R.Y, ThumbLen, R.H), '', False, True);
end;

function ScrollPosAt(const R: TRectI; Vertical: Boolean; X, Y, Max, Page: Integer): Integer;
var
  A, Len, P: Integer;
begin
  if Vertical then
  begin
    A := R.W;
    Len := R.H - 2 * A;
    P := Y - R.Y - A;
  end
  else
  begin
    A := R.H;
    Len := R.W - 2 * A;
    P := X - R.X - A;
  end;
  if Len <= 0 then begin Result := 0; Exit; end;
  Result := P * (Max + Page) div Len - Page div 2;
  if Result < 0 then Result := 0;
  if Result > Max then Result := Max;
end;

function EditLine(var T: string; const Chars: string; MaxLen: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(Chars) do
    case Chars[I] of
      #8: if T <> '' then Delete(T, Length(T), 1);
      #13: Result := True;
      ' '..'~', #160..#255: if Length(T) < MaxLen then T := T + Chars[I];
    end;
end;

procedure EditMulti(var T: string; const Chars: string; MaxLen: Integer);
var
  I: Integer;
begin
  for I := 1 to Length(Chars) do
    case Chars[I] of
      #8: if T <> '' then Delete(T, Length(T), 1);
      #13: if Length(T) < MaxLen then T := T + #10;
      #9: if Length(T) < MaxLen - 1 then T := T + '  ';
      ' '..'~', #160..#255: if Length(T) < MaxLen then T := T + Chars[I];
    end;
end;

function WrapLines(const T: string; W: Integer): string;
var
  I, MaxChars, Sp: Integer;
  Line: string;
begin
  MaxChars := W div CharW;
  if MaxChars < 1 then MaxChars := 1;
  Result := '';
  Line := '';
  for I := 1 to Length(T) do
  begin
    if T[I] = #10 then
    begin
      Result := Result + Line + #10;
      Line := '';
      Continue;
    end;
    if Length(Line) >= MaxChars then
    begin
      { break after the last space when there is one }
      Sp := LastDelimiter(' ', Line);
      if (Sp > 1) and (T[I] <> ' ') then
      begin
        Result := Result + Copy(Line, 1, Sp - 1) + #10;
        Line := Copy(Line, Sp + 1, MaxInt);
      end
      else
      begin
        Result := Result + Line + #10;
        Line := '';
        if T[I] = ' ' then Continue;
      end;
    end;
    Line := Line + T[I];
  end;
  Result := Result + Line;
end;

{ TEditorDialog }

constructor TEditorDialog.Create(const ACaption: string; W, H: Integer);
begin
  inherited Create;
  Caption := ACaption;
  Bounds := RectI((640 - W) div 2, (480 - H) div 2, W, H);
end;

function TEditorDialog.CX: Integer;
begin
  Result := Bounds.X + 3;
end;

function TEditorDialog.CY: Integer;
begin
  Result := Bounds.Y + 22;
end;

procedure TEditorDialog.Draw(S: TGSurface);
begin
  FacePanel(S, Bounds);
  S.FillRect(Bounds.X + 3, Bounds.Y + 3, Bounds.W - 6, 16, ColTitle);
  DrawText(S, Bounds.X + 7, Bounds.Y + 7, Caption, ColHighlightText, 1);
end;

{ TPromptDialog }

constructor TPromptDialog.Create(const ACaption, APrompt, AValue: string);
begin
  inherited Create(ACaption, 360, 110);
  Prompt := APrompt;
  Value := AValue;
end;

function TPromptDialog.Step(const I: TEditorInput): Boolean;
begin
  Result := True;
  if EditLine(Value, I.Chars, 255) then
  begin
    Self.Result := drOk;
    Result := False;
    Exit;
  end;
  if I.Esc or (Pos(#27, I.Chars) > 0) then
  begin
    Self.Result := drCancel;
    Result := False;
    Exit;
  end;
  if I.LeftPress then
  begin
    if InRect(RectI(CX + 186, CY + 54, 75, 25), I.PressX, I.PressY) then
    begin
      Self.Result := drOk;
      Result := False;
    end
    else if InRect(RectI(CX + 270, CY + 54, 75, 25), I.PressX, I.PressY) then
    begin
      Self.Result := drCancel;
      Result := False;
    end;
  end;
end;

procedure TPromptDialog.Draw(S: TGSurface);
begin
  inherited Draw(S);
  DrawLabel(S, CX + 12, CY + 8, Prompt, ColText);
  EditCtl(S, RectI(CX + 12, CY + 22, 333, 22), Value, True, True);
  ButtonCtl(S, RectI(CX + 186, CY + 54, 75, 25), 'OK', False, True);
  ButtonCtl(S, RectI(CX + 270, CY + 54, 75, 25), 'Cancel', False, True);
end;

{ TMessageDialog }

constructor TMessageDialog.Create(const ACaption, AMsg: string; AButtons: Integer);
begin
  inherited Create(ACaption, 340, 120);
  Msg := AMsg;
  Buttons := AButtons;
end;

function TMessageDialog.Step(const I: TEditorInput): Boolean;
const
  Codes: array[0..2] of TDialogResult = (drYes, drNo, drCancel);
var
  K, X0: Integer;
begin
  Result := True;
  if (Pos(#13, I.Chars) > 0) then
  begin
    if Buttons = 1 then Self.Result := drOk else Self.Result := drYes;
    Result := False;
    Exit;
  end;
  if I.Esc or (Pos(#27, I.Chars) > 0) then
  begin
    if Buttons = 2 then Self.Result := drNo else Self.Result := drCancel;
    Result := False;
    Exit;
  end;
  if not I.LeftPress then Exit;
  X0 := Bounds.X + (Bounds.W - Buttons * 80) div 2;
  for K := 0 to Buttons - 1 do
    if InRect(RectI(X0 + K * 80, Bounds.Y + Bounds.H - 34, 75, 25), I.PressX, I.PressY) then
    begin
      if Buttons = 1 then Self.Result := drOk else Self.Result := Codes[K];
      Result := False;
      Exit;
    end;
end;

procedure TMessageDialog.Draw(S: TGSurface);
const
  Caps: array[0..2] of string = ('&Yes', '&No', 'Cancel');
var
  K, X0, Y: Integer;
  Lines, L: string;
  P: Integer;
begin
  inherited Draw(S);
  Lines := WrapLines(Msg, Bounds.W - 30) + #10;
  Y := CY + 10;
  repeat
    P := Pos(#10, Lines);
    L := Copy(Lines, 1, P - 1);
    Lines := Copy(Lines, P + 1, MaxInt);
    DrawLabel(S, CX + 12, Y, L, ColText);
    Inc(Y, 12);
  until Lines = '';
  X0 := Bounds.X + (Bounds.W - Buttons * 80) div 2;
  for K := 0 to Buttons - 1 do
    if Buttons = 1 then
      ButtonCtl(S, RectI(X0, Bounds.Y + Bounds.H - 34, 75, 25), 'OK', False, True)
    else
      ButtonCtl(S, RectI(X0 + K * 80, Bounds.Y + Bounds.H - 34, 75, 25),
        StringReplace(Caps[K], '&', '', []), False, True);
end;

end.
