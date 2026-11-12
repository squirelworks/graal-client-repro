{ GVclForm: shows a Delphi form, read with GDfmObj from the real client's own
  resources, the way the Delphi 3 VCL showed it.

  The 1998 betas and the 1.x clients up to 1.32 were Delphi 3 programs.
  Their start dialog (TConnectFrame) is an ordinary Windows window with
  ordinary controls: group boxes, labels, pictures, radio buttons, check
  boxes, edit fields, drop-down lists and a Start button. This unit builds
  that window from the form: the same size, caption, border icons,
  position, fonts, colours, pictures, list items, tab order and enabled
  and visible states, so that each rebuild shows its own client's dialog.

  Windows: real Win32 controls (BUTTON, EDIT, COMBOBOX), created as the
  VCL created them; group boxes, panels, labels and pictures are painted
  the way the VCL's TGroupBox, TPanel, TLabel and TImage paint themselves.
  The window is owned by a hidden application window titled like the
  original's TApplication, so the taskbar shows one button, as it did.

  Other systems: the same form drawn into a TGWindow in the classic
  Windows look, with mouse and keyboard handling for its controls.

  The program reacts to the controls through OnEvent (a click, a change
  of selection or text, Enter in a field) and paints the pictures of
  owner-drawn lists (the character drop-downs) through OnDrawItem. }
unit GVclForm;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat, SysUtils, Classes, GDfmObj, GSurface;

type
  TVclKind = (vkForm, vkGroup, vkPanel, vkButton, vkRadio, vkCheck, vkEdit,
    vkCombo, vkLabel, vkImage, vkOther);

  TVclEvent = (veClick, veChange, veEnter);

  TVclForm = class;

  TVclCtl = class
  public
    Obj: TDfmObj;
    Kind: TVclKind;
    Name: string;
    Parent: TVclCtl;
    Children: TList;
    X, Y, W, H: Integer;
    Visible, Enabled: Boolean;
    Text: string;              { caption, or an edit's text }
    Items: TStringList;
    ItemIndex: Integer;
    ItemHeight: Integer;
    DropDownCount: Integer;
    OwnerDraw: Boolean;
    Checked: Boolean;
    TabOrder: Integer;
    TabStop: Boolean;
    IsDefault: Boolean;
    { font }
    FontHeight: Integer;
    FontName: string;
    FontBold, FontItalic, FontUnderline: Boolean;
    FontColor: Cardinal;       { $00BBGGRR or a system colour ($80000000 or index) }
    Color: Cardinal;
    { labels }
    Alignment: Integer;        { 0 left, 1 right, 2 centre }
    WordWrap, Transparent, AutoSizeLabel: Boolean;
    { pictures }
    Picture: TGSurface;
    Stretch: Boolean;
    TransColor: Cardinal;
    { panels }
    BevelOuter, BevelInner: Integer; { 0 none, 1 lowered, 2 raised }
    { owner-drawn lists: background and where the item text starts }
    ItemFill: Cardinal;
    ItemTextX: Integer;
{$IFDEF MSWINDOWS}
    Wnd: THandle;
    Font: THandle;
    OldProc: Pointer;
{$ENDIF}
    Id: Integer;
    constructor Create;
    destructor Destroy; override;
    function Windowed: Boolean;
    function Container: Boolean;
  end;

  TVclEventProc = procedure(Form: TVclForm; Ctl: TVclCtl; Event: TVclEvent) of object;
  { Draws item Index of the owner-drawn list Ctl into Item (already filled
    with Ctl.ItemFill, the item's size). The text is drawn afterwards at
    Ctl.ItemTextX. }
  TVclDrawItemProc = procedure(Form: TVclForm; Ctl: TVclCtl; Index: Integer;
    Selected: Boolean; Item: TGSurface) of object;

  TVclForm = class
  private
    FCtls: TList;
    FDone: Boolean;
    FResult: Integer;
{$IFDEF MSWINDOWS}
    FAppWnd: THandle;
    { TForm.AutoScroll: the scroll bars a client smaller than the controls
      gets, and where it is scrolled to }
    FRangeW, FRangeH, FScrollX, FScrollY: Integer;
    FHasH, FHasV: Boolean;
    FFocusWnd: THandle;
    procedure CreateWin(C: TVclCtl; ParentWnd: THandle);
    procedure PaintContainer(C: TVclCtl; DC: THandle);
    procedure Command(Id, Code: Integer);
    procedure AutoScrollSetup;
    procedure ScrollTo(X, Y: Integer);
    procedure ScrollInView(C: TVclCtl);
    procedure ScrollMsg(Bar, Code: Integer);
{$ENDIF}
    function Build(O: TDfmObj; Parent: TVclCtl): TVclCtl;
    procedure SyncFromWindow(C: TVclCtl);
  public
    Root: TVclCtl;
    Caption: string;
    AppTitle: string;          { the hidden application window's title }
    Width, Height: Integer;    { outer size, as the form gives it }
    ClientWidth, ClientHeight: Integer;
    { True when the form gives only ClientWidth/Height (no Width/Height):
      the window is then sized from the client area }
    SizedFromClient: Boolean;
    BorderIcons: string;       { the form's BorderIcons set, as text }
    BorderStyle: string;       { bsSizeable (the default), bsDialog, ... }
    Sizeable: Boolean;
    MinimizeBox, MaximizeBox, SystemMenu: Boolean;
    { the window's owner: True the application window (the first builds),
      False none (its own taskbar button) }
    AppOwned: Boolean;
    StayOnTop: Boolean;        { WS_EX_TOPMOST, as fsStayOnTop }
    OnEvent: TVclEventProc;
    OnDrawItem: TVclDrawItemProc;
    { Builds the form described by Dfm (which stays owned by the caller). }
    constructor Create(Dfm: TDfmObj; const AAppTitle: string);
    destructor Destroy; override;
    function Ctl(const Name: string): TVclCtl;
    function CtlCount: Integer;
    function CtlAt(I: Integer): TVclCtl;
    { State of a control by name; unknown names are ignored. }
    function GetText(const Name: string): string;
    procedure SetText(const Name, Value: string);
    function GetChecked(const Name: string): Boolean;
    procedure SetChecked(const Name: string; Value: Boolean);
    function GetItemIndex(const Name: string): Integer;
    procedure SetItemIndex(const Name: string; Value: Integer);
    procedure SetItems(const Name: string; const Values: array of string);
    procedure SetEnabled(const Name: string; Value: Boolean);
    procedure SetVisible(const Name: string; Value: Boolean);
    procedure SetHeight(const Name: string; Value: Integer);
    { The form's own caption. }
    procedure SetCaption(const Value: string);
    procedure Focus(const Name: string);
    { Shows the form and runs until Close is called (from OnEvent) or the
      window is closed (the result is then -1). }
    function ShowModal: Integer;
    procedure Close(AResult: Integer);
    { Hides and destroys the window (the controls' state stays readable). }
    procedure Hide;
    { Draws the whole form, client area only, as the classic Windows look
      (for tests and for systems without Win32). }
    procedure Render(Dest: TGSurface);
  end;

{ Decodes a BMP file (1, 4, 8, 16, 24, 32 bits; uncompressed, RLE4 or
  RLE8) into Dest; False if it is not one. }
function DecodeBmp(const S: string; Dest: TGSurface): Boolean;
{ A Delphi colour (clBtnFace, $00BBGGRR, ...) as $AARRGGBB, with the
  Windows 98 standard scheme for the system colours. }
function VclColorRGB(C: Cardinal): Cardinal;
function VclColorValue(const S: string; Default: Cardinal): Cardinal;

const
  clBtnFace = $8000000F;
  clWindow = $80000005;
  clWindowText = $80000008;
  clHighlight = $8000000D;
  clHighlightText = $8000000E;
  clBtnShadow = $80000010;
  clBtnHighlight = $80000014;
  clGrayText = $80000011;

{ The hidden application window the dialogs made (Windows), which stays for
  the program's life and owns the game window as TApplication's does; 0
  before the first dialog and on other systems. }
function VclAppWindow: PtrUInt;

implementation

uses
  GFont
{$IFDEF MSWINDOWS}
  , Windows, Messages
{$ENDIF}
  ;

{ ---- colours ---- }

function SysRGB(Index: Integer): Cardinal;
begin
  { Windows 98 "Windows Standard" scheme, $RRGGBB }
  case Index of
    0: Result := $C0C0C0;   { scrollbar }
    1: Result := $008080;   { background }
    2: Result := $000080;   { active caption }
    3: Result := $808080;   { inactive caption }
    4: Result := $C0C0C0;   { menu }
    5: Result := $FFFFFF;   { window }
    6: Result := $000000;   { window frame }
    7: Result := $000000;   { menu text }
    8: Result := $000000;   { window text }
    9: Result := $FFFFFF;   { caption text }
    10: Result := $C0C0C0;  { active border }
    11: Result := $C0C0C0;  { inactive border }
    12: Result := $808080;  { app workspace }
    13: Result := $000080;  { highlight }
    14: Result := $FFFFFF;  { highlight text }
    15: Result := $C0C0C0;  { button face }
    16: Result := $808080;  { button shadow }
    17: Result := $808080;  { gray text }
    18: Result := $000000;  { button text }
    19: Result := $C0C0C0;  { inactive caption text }
    20: Result := $FFFFFF;  { button highlight }
    21: Result := $000000;  { 3D dark shadow }
    22: Result := $DFDFDF;  { 3D light }
    23: Result := $000000;  { info text }
    24: Result := $FFFFE1;  { info background }
  else
    Result := $C0C0C0;
  end;
end;

function VclColorRGB(C: Cardinal): Cardinal;
begin
  if C and $FF000000 <> 0 then
  begin
{$IFDEF MSWINDOWS}
    Result := GetSysColor(C and $FF);
    Result := $FF000000 or ((Result and $FF) shl 16) or (Result and $FF00) or
      ((Result shr 16) and $FF);
{$ELSE}
    Result := $FF000000 or SysRGB(C and $FF);
{$ENDIF}
  end
  else
    Result := $FF000000 or ((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF);
end;

function VclColorValue(const S: string; Default: Cardinal): Cardinal;
const
  Names: array[0..40] of string = ('clBlack', 'clMaroon', 'clGreen', 'clOlive',
    'clNavy', 'clPurple', 'clTeal', 'clGray', 'clSilver', 'clRed', 'clLime',
    'clYellow', 'clBlue', 'clFuchsia', 'clAqua', 'clWhite',
    'clScrollBar', 'clBackground', 'clActiveCaption', 'clInactiveCaption',
    'clMenu', 'clWindow', 'clWindowFrame', 'clMenuText', 'clWindowText',
    'clCaptionText', 'clActiveBorder', 'clInactiveBorder', 'clAppWorkSpace',
    'clHighlight', 'clHighlightText', 'clBtnFace', 'clBtnShadow', 'clGrayText',
    'clBtnText', 'clInactiveCaptionText', 'clBtnHighlight', 'cl3DDkShadow',
    'cl3DLight', 'clInfoText', 'clInfoBk');
  Values: array[0..40] of Cardinal = ($000000, $000080, $008000, $008080,
    $800000, $800080, $808000, $808080, $C0C0C0, $0000FF, $00FF00,
    $00FFFF, $FF0000, $FF00FF, $FFFF00, $FFFFFF,
    $80000000, $80000001, $80000002, $80000003, $80000004, $80000005,
    $80000006, $80000007, $80000008, $80000009, $8000000A, $8000000B,
    $8000000C, $8000000D, $8000000E, $8000000F, $80000010, $80000011,
    $80000012, $80000013, $80000014, $80000015, $80000016, $80000017,
    $80000018);
var
  I: Integer;
begin
  for I := 0 to High(Names) do
    if SameText(Names[I], S) then begin Result := Values[I]; Exit; end;
  Result := Default;
end;

{ ---- BMP decoding ---- }

function LE(const S: string; P, N: Integer): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := N - 1 downto 0 do
    if P + I <= Length(S) then Result := (Result shl 8) or Ord(S[P + I])
    else Result := Result shl 8;
end;

function DecodeBmp(const S: string; Dest: TGSurface): Boolean;
var
  Off, HSize, W, H, Bpp, Comp, NColors, Stride, X, Y, P, I, V, Row: Integer;
  BottomUp: Boolean;
  Pal: array[0..255] of Cardinal;
  Idx: array of Byte;
  Cmd, Cnt: Integer;

  procedure Put(PX, PY: Integer; C: Cardinal);
  var
    RY: Integer;
  begin
    if (PX < 0) or (PX >= W) or (PY < 0) or (PY >= H) then Exit;
    if BottomUp then RY := H - 1 - PY else RY := PY;
    Dest.Pixels[PX + RY * W] := C;
  end;

begin
  Result := False;
  if (Length(S) < 26) or (Copy(S, 1, 2) <> 'BM') then Exit;
  Off := LE(S, 11, 4) + 1;
  HSize := LE(S, 15, 4);
  if HSize = 12 then
  begin
    W := LE(S, 19, 2);
    H := SmallInt(LE(S, 21, 2));
    Bpp := LE(S, 25, 2);
    Comp := 0;
    NColors := 0;
  end
  else
  begin
    W := LongInt(LE(S, 19, 4));
    H := LongInt(LE(S, 23, 4));
    Bpp := LE(S, 29, 2);
    Comp := LE(S, 31, 4);
    NColors := LE(S, 47, 4);
  end;
  BottomUp := H > 0;
  H := Abs(H);
  if (W <= 0) or (H <= 0) or (W > 8192) or (H > 8192) then Exit;
  if (Bpp <= 8) and (NColors = 0) then NColors := 1 shl Bpp;
  FillChar(Pal, SizeOf(Pal), 0);
  for I := 0 to NColors - 1 do
    if I <= 255 then
    begin
      if HSize = 12 then P := 15 + HSize + I * 3 else P := 15 + HSize + I * 4;
      Pal[I] := $FF000000 or (Cardinal(LE(S, P + 2, 1)) shl 16) or
        (Cardinal(LE(S, P + 1, 1)) shl 8) or Cardinal(LE(S, P, 1));
    end;
  Dest.SetSize(W, H);
  Dest.Fill($FF000000);
  if (Comp = 1) or (Comp = 2) then
  begin
    { RLE8 / RLE4: rows from the bottom }
    X := 0;
    Y := 0;
    P := Off;
    SetLength(Idx, 0);
    while P + 1 <= Length(S) do
    begin
      Cnt := Ord(S[P]);
      Cmd := Ord(S[P + 1]);
      Inc(P, 2);
      if Cnt > 0 then
      begin
        for I := 0 to Cnt - 1 do
        begin
          if Comp = 1 then V := Cmd
          else if I and 1 = 0 then V := Cmd shr 4 else V := Cmd and 15;
          Put(X, H - 1 - Y, Pal[V]);
          Inc(X);
        end;
      end
      else if Cmd = 0 then begin X := 0; Inc(Y); end
      else if Cmd = 1 then Break
      else if Cmd = 2 then
      begin
        Inc(X, Ord(S[P]));
        Inc(Y, Ord(S[P + 1]));
        Inc(P, 2);
      end
      else
      begin
        for I := 0 to Cmd - 1 do
        begin
          if Comp = 1 then V := Ord(S[P + I])
          else if I and 1 = 0 then V := Ord(S[P + I div 2]) shr 4
          else V := Ord(S[P + I div 2]) and 15;
          Put(X, H - 1 - Y, Pal[V]);
          Inc(X);
        end;
        if Comp = 1 then I := Cmd else I := (Cmd + 1) div 2;
        Inc(P, (I + 1) and not 1);
      end;
    end;
    { Put already flipped through H - 1 - Y; undo the BottomUp flip }
    if BottomUp then
    begin
      SetLength(Idx, 0);
    end;
    Result := True;
    Exit;
  end;
  Stride := ((W * Bpp + 31) div 32) * 4;
  if Off + Stride * H - 1 > Length(S) then Exit;
  for Y := 0 to H - 1 do
  begin
    Row := Off + Y * Stride;
    for X := 0 to W - 1 do
    begin
      case Bpp of
        1: V := (Ord(S[Row + X div 8]) shr (7 - X mod 8)) and 1;
        4: if X and 1 = 0 then V := Ord(S[Row + X div 2]) shr 4
           else V := Ord(S[Row + X div 2]) and 15;
        8: V := Ord(S[Row + X]);
        16: begin
              V := Ord(S[Row + X * 2]) or (Ord(S[Row + X * 2 + 1]) shl 8);
              Put(X, Y, $FF000000 or (Cardinal((V shr 10) and 31) * 255 div 31 shl 16) or
                (Cardinal((V shr 5) and 31) * 255 div 31 shl 8) or
                (Cardinal(V and 31) * 255 div 31));
              Continue;
            end;
        24, 32: begin
              P := Row + X * (Bpp div 8);
              Put(X, Y, $FF000000 or (Cardinal(Ord(S[P + 2])) shl 16) or
                (Cardinal(Ord(S[P + 1])) shl 8) or Cardinal(Ord(S[P])));
              Continue;
            end;
      else
        Exit;
      end;
      Put(X, Y, Pal[V]);
    end;
  end;
  Result := True;
end;

{ ---- controls ---- }

constructor TVclCtl.Create;
begin
  inherited Create;
  Children := TList.Create;
  Items := TStringList.Create;
  ItemIndex := -1;
  Visible := True;
  Enabled := True;
  DropDownCount := 8;
  ItemHeight := 16;
  ItemFill := clWindow;
  ItemTextX := 2;
end;

destructor TVclCtl.Destroy;
begin
  Children.Free;
  Items.Free;
  Picture.Free;
  inherited Destroy;
end;

function TVclCtl.Windowed: Boolean;
begin
  Result := Kind in [vkGroup, vkPanel, vkButton, vkRadio, vkCheck, vkEdit, vkCombo];
end;

function TVclCtl.Container: Boolean;
begin
  Result := Kind in [vkForm, vkGroup, vkPanel];
end;

function KindOf(const C: string): TVclKind;
begin
  if SameText(C, 'TGroupBox') or SameText(C, 'TRadioGroup') then Result := vkGroup
  else if SameText(C, 'TPanel') then Result := vkPanel
  else if SameText(C, 'TButton') or SameText(C, 'TBitBtn') then Result := vkButton
  else if SameText(C, 'TRadioButton') then Result := vkRadio
  else if SameText(C, 'TCheckBox') then Result := vkCheck
  else if SameText(C, 'TEdit') or SameText(C, 'TMaskEdit') then Result := vkEdit
  else if SameText(C, 'TComboBox') then Result := vkCombo
  else if SameText(C, 'TLabel') then Result := vkLabel
  else if SameText(C, 'TImage') then Result := vkImage
  else Result := vkOther;
end;

function BevelOf(const S: string; Default: Integer): Integer;
begin
  if SameText(S, 'bvNone') then Result := 0
  else if SameText(S, 'bvLowered') then Result := 1
  else if SameText(S, 'bvRaised') then Result := 2
  else Result := Default;
end;

function TVclForm.Build(O: TDfmObj; Parent: TVclCtl): TVclCtl;
var
  C: TVclCtl;
  I: Integer;
  L: TDfmStrings;
  Bmp: string;
begin
  C := TVclCtl.Create;
  C.Obj := O;
  C.Name := O.Name;
  C.Parent := Parent;
  if Parent = nil then C.Kind := vkForm else C.Kind := KindOf(O.ClassName_);
  C.X := O.Int('Left', 0);
  C.Y := O.Int('Top', 0);
  C.W := O.Int('Width', 0);
  C.H := O.Int('Height', 0);
  C.Visible := O.Bool('Visible', True);
  C.Enabled := O.Bool('Enabled', True);
  if C.Kind = vkEdit then C.Text := O.Str('Text', '')
  else C.Text := O.Str('Caption', '');
  C.TabOrder := O.Int('TabOrder', 0);
  C.TabStop := O.Bool('TabStop', C.Kind in [vkButton, vkCheck, vkEdit, vkCombo]);
  C.IsDefault := O.Bool('Default', False);
  C.Checked := O.Bool('Checked', False);
  C.Id := FCtls.Count + 100;
  { font: the control's own, or the parent's (ParentFont) }
  if (Parent <> nil) and O.Bool('ParentFont', True) and not O.Has('Font.Height') then
  begin
    C.FontHeight := Parent.FontHeight;
    C.FontName := Parent.FontName;
    C.FontBold := Parent.FontBold;
    C.FontItalic := Parent.FontItalic;
    C.FontUnderline := Parent.FontUnderline;
    C.FontColor := Parent.FontColor;
  end
  else
  begin
    if Parent <> nil then
    begin
      C.FontHeight := O.Int('Font.Height', Parent.FontHeight);
      C.FontName := O.Str('Font.Name', Parent.FontName);
      C.FontColor := VclColorValue(O.Ident('Font.Color', ''), Parent.FontColor);
    end
    else
    begin
      C.FontHeight := O.Int('Font.Height', -11);
      C.FontName := O.Str('Font.Name', 'MS Sans Serif');
      C.FontColor := VclColorValue(O.Ident('Font.Color', ''), clWindowText);
    end;
    if O.Has('Font.Color') and (O.IndexOf('Font.Color') >= 0) and
      (O.Props[O.IndexOf('Font.Color')].V.Kind = dkInt) then
      C.FontColor := Cardinal(O.Int('Font.Color', 0));
    C.FontBold := O.InSet('Font.Style', 'fsBold');
    C.FontItalic := O.InSet('Font.Style', 'fsItalic');
    C.FontUnderline := O.InSet('Font.Style', 'fsUnderline');
  end;
  { colour: own, or the parent's (ParentColor), else the class default }
  if O.Has('Color') then
  begin
    if O.Props[O.IndexOf('Color')].V.Kind = dkInt then C.Color := Cardinal(O.Int('Color', 0))
    else C.Color := VclColorValue(O.Ident('Color', ''), clBtnFace);
  end
  else if C.Kind in [vkEdit, vkCombo] then C.Color := clWindow
  else if Parent <> nil then C.Color := Parent.Color
  else C.Color := clBtnFace;
  { labels }
  if SameText(O.Ident('Alignment', ''), 'taRightJustify') then C.Alignment := 1
  else if SameText(O.Ident('Alignment', ''), 'taCenter') then C.Alignment := 2
  else C.Alignment := 0;
  if C.Kind in [vkRadio, vkCheck] then
    { taRightJustify (the default) puts the text right of the box }
    C.Alignment := Ord(SameText(O.Ident('Alignment', 'taRightJustify'), 'taLeftJustify'));
  C.WordWrap := O.Bool('WordWrap', False);
  C.Transparent := O.Bool('Transparent', False);
  C.AutoSizeLabel := O.Bool('AutoSize', True);
  { lists }
  C.ItemHeight := O.Int('ItemHeight', 16);
  C.DropDownCount := O.Int('DropDownCount', 8);
  C.OwnerDraw := SameText(O.Ident('Style', ''), 'csOwnerDrawFixed') or
    SameText(O.Ident('Style', ''), 'csOwnerDrawVariable');
  L := O.List('Items.Strings');
  for I := 0 to High(L) do C.Items.Add(L[I]);
  C.ItemIndex := O.Int('ItemIndex', -1);
  { panels }
  C.BevelOuter := BevelOf(O.Ident('BevelOuter', ''), 2);
  C.BevelInner := BevelOf(O.Ident('BevelInner', ''), 0);
  { pictures }
  if C.Kind = vkImage then
  begin
    Bmp := DfmPictureBitmap(O.Bin('Picture.Data'));
    if Bmp <> '' then
    begin
      C.Picture := TGSurface.Create(1, 1);
      if not DecodeBmp(Bmp, C.Picture) then FreeAndNil(C.Picture)
      else if C.Picture.Height > 0 then
        { TBitmap's tmAuto: the colour of the bottom-left pixel }
        C.TransColor := C.Picture.Pixels[(C.Picture.Height - 1) * C.Picture.Width];
    end;
    C.Stretch := O.Bool('Stretch', False);
  end;
  FCtls.Add(C);
  if Parent <> nil then Parent.Children.Add(C);
  for I := 0 to High(O.Children) do Build(O.Children[I], C);
  Result := C;
end;

constructor TVclForm.Create(Dfm: TDfmObj; const AAppTitle: string);
begin
  inherited Create;
  FCtls := TList.Create;
  AppTitle := AAppTitle;
  Root := Build(Dfm, nil);
  Caption := Root.Text;
  Width := Root.W;
  Height := Root.H;
  AppOwned := True;
  StayOnTop := SameText(Dfm.Ident('FormStyle', ''), 'fsStayOnTop');
  ClientWidth := Dfm.Int('ClientWidth', 0);
  ClientHeight := Dfm.Int('ClientHeight', 0);
  BorderStyle := Dfm.Ident('BorderStyle', 'bsSizeable');
  if Dfm.Has('BorderIcons') then BorderIcons := Dfm.SetText('BorderIcons')
  else BorderIcons := '[biSystemMenu,biMinimize,biMaximize]';
  SystemMenu := Pos('biSystemMenu', BorderIcons) > 0;
  MinimizeBox := Pos('biMinimize', BorderIcons) > 0;
  MaximizeBox := Pos('biMaximize', BorderIcons) > 0;
  Sizeable := SameText(BorderStyle, 'bsSizeable');
  if SameText(BorderStyle, 'bsDialog') then
  begin
    MinimizeBox := False;
    MaximizeBox := False;
  end;
  { without ClientWidth/Height, the outer size less the frame of a
    Windows 98 window (sizeable: 4 px each side, 18 px caption + 1) }
  if ClientWidth = 0 then
    if Sizeable then ClientWidth := Width - 8 else ClientWidth := Width - 6;
  if ClientHeight = 0 then
    if Sizeable then ClientHeight := Height - 27 else ClientHeight := Height - 25;
  { the other way round: many TOPTIONS forms carry only ClientWidth and
    ClientHeight, and a window made at Width x Height (0 x 0) was a bare
    caption. ShowModal sizes the real window from the client area. }
  SizedFromClient := (Width <= 0) or (Height <= 0);
  if Width <= 0 then
    if Sizeable then Width := ClientWidth + 8 else Width := ClientWidth + 6;
  if Height <= 0 then
    if Sizeable then Height := ClientHeight + 27 else Height := ClientHeight + 25;
end;

destructor TVclForm.Destroy;
var
  I: Integer;
begin
  Hide;
  for I := 0 to FCtls.Count - 1 do TVclCtl(FCtls[I]).Free;
  FCtls.Free;
  inherited Destroy;
end;

function TVclForm.Ctl(const Name: string): TVclCtl;
var
  I: Integer;
begin
  for I := 0 to FCtls.Count - 1 do
    if SameText(TVclCtl(FCtls[I]).Name, Name) then begin Result := TVclCtl(FCtls[I]); Exit; end;
  Result := nil;
end;

function TVclForm.CtlCount: Integer;
begin
  Result := FCtls.Count;
end;

function TVclForm.CtlAt(I: Integer): TVclCtl;
begin
  Result := TVclCtl(FCtls[I]);
end;

procedure TVclForm.Close(AResult: Integer);
begin
  FResult := AResult;
  FDone := True;
end;

{ ---- the classic look, drawn into a surface ---- }

procedure Line(D: TGSurface; X1, Y1, X2, Y2: Integer; C: Cardinal);
begin
  if X1 = X2 then D.FillRect(X1, Y1, 1, Y2 - Y1 + 1, C)
  else D.FillRect(X1, Y1, X2 - X1 + 1, 1, C);
end;

procedure Frame3D(D: TGSurface; X, Y, W, H: Integer; TL, BR: Cardinal);
begin
  Line(D, X, Y, X + W - 1, Y, TL);
  Line(D, X, Y, X, Y + H - 1, TL);
  Line(D, X, Y + H - 1, X + W - 1, Y + H - 1, BR);
  Line(D, X + W - 1, Y, X + W - 1, Y + H - 1, BR);
end;

procedure SimpleText(D: TGSurface; X, Y: Integer; const S: string; C: Cardinal);
begin
  GFont.DrawText(D, X, Y + 4, S, C, 1);
end;

procedure RenderCtl(F: TVclForm; C: TVclCtl; D: TGSurface; OX, OY: Integer);
var
  I, X, Y, TX: Integer;
  Face, Hi, Sh, Dk, Txt: Cardinal;
  Img: TGSurface;
  S: string;
begin
  if not C.Visible then Exit;
  Face := VclColorRGB(clBtnFace);
  Hi := VclColorRGB(clBtnHighlight);
  Sh := VclColorRGB(clBtnShadow);
  Dk := $FF000000;
  X := OX + C.X;
  Y := OY + C.Y;
  if C.Kind = vkForm then begin X := 0; Y := 0; end;
  if C.Enabled then Txt := VclColorRGB(C.FontColor) else Txt := Sh;
  case C.Kind of
    vkForm: D.FillRect(0, 0, D.Width, D.Height, VclColorRGB(C.Color));
    vkGroup:
      begin
        D.FillRect(X, Y, C.W, C.H, VclColorRGB(C.Color));
        Frame3D(D, X + 1, Y + 8, C.W - 1, C.H - 8, Hi, Hi);
        Frame3D(D, X, Y + 7, C.W - 1, C.H - 8, Sh, Sh);
        if C.Text <> '' then
        begin
          D.FillRect(X + 8, Y, GFont.TextWidth(C.Text, 1) + 2, 14, VclColorRGB(C.Color));
          SimpleText(D, X + 9, Y, C.Text, Txt);
        end;
      end;
    vkPanel:
      begin
        D.FillRect(X, Y, C.W, C.H, VclColorRGB(C.Color));
        if C.BevelOuter = 2 then Frame3D(D, X, Y, C.W, C.H, Hi, Sh)
        else if C.BevelOuter = 1 then Frame3D(D, X, Y, C.W, C.H, Sh, Hi);
      end;
    vkButton:
      begin
        D.FillRect(X, Y, C.W, C.H, Face);
        Frame3D(D, X, Y, C.W, C.H, Hi, Dk);
        Frame3D(D, X + 1, Y + 1, C.W - 2, C.H - 2, Face, Sh);
        SimpleText(D, X + (C.W - GFont.TextWidth(C.Text, 1)) div 2,
          Y + (C.H - 14) div 2, StringReplace(C.Text, '&', '', []), Txt);
      end;
    vkRadio, vkCheck:
      begin
        TX := Y + (C.H - 13) div 2;
        D.FillRect(X, TX, 13, 13, VclColorRGB(clWindow));
        Frame3D(D, X, TX, 13, 13, Sh, Hi);
        Frame3D(D, X + 1, TX + 1, 11, 11, Dk, Face);
        if C.Checked then
          if C.Kind = vkRadio then D.FillRect(X + 4, TX + 4, 5, 5, Txt)
          else for I := 0 to 6 do
            if I < 2 then D.FillRect(X + 3 + I, TX + 5 + I, 1, 3, Txt)
            else D.FillRect(X + 3 + I, TX + 7 - (I - 2), 1, 3, Txt);
        SimpleText(D, X + 17, Y + (C.H - 14) div 2, StringReplace(C.Text, '&', '', []), Txt);
      end;
    vkEdit, vkCombo:
      begin
        if C.Kind = vkCombo then I := C.ItemHeight + 6 else I := C.H;
        if C.Enabled then D.FillRect(X, Y, C.W, I, VclColorRGB(C.Color))
        else D.FillRect(X, Y, C.W, I, Face);
        Frame3D(D, X, Y, C.W, I, Sh, Hi);
        Frame3D(D, X + 1, Y + 1, C.W - 2, I - 2, Dk, Face);
        if C.Kind = vkCombo then
        begin
          D.FillRect(X + C.W - 18, Y + 2, 16, I - 4, Face);
          Frame3D(D, X + C.W - 18, Y + 2, 16, I - 4, Hi, Dk);
          for TX := 0 to 3 do
            Line(D, X + C.W - 14 + TX, Y + I div 2 - 2 + TX, X + C.W - 8 - TX,
              Y + I div 2 - 2 + TX, Dk);
          if (C.ItemIndex >= 0) and (C.ItemIndex < C.Items.Count) then
            S := C.Items[C.ItemIndex]
          else S := '';
          if C.OwnerDraw and (C.ItemIndex >= 0) and Assigned(F.OnDrawItem) then
          begin
            Img := TGSurface.Create(C.W - 22, C.ItemHeight);
            try
              Img.Fill(VclColorRGB(C.ItemFill));
              F.OnDrawItem(F, C, C.ItemIndex, False, Img);
              D.Blit(Img, 0, 0, Img.Width, Img.Height, X + 3, Y + 3);
            finally
              Img.Free;
            end;
          end;
          SimpleText(D, X + 3 + C.ItemTextX, Y + 3, S, Txt);
        end
        else
          SimpleText(D, X + 3, Y + (I - 14) div 2, C.Text, Txt);
      end;
    vkLabel:
      begin
        if not C.Transparent then D.FillRect(X, Y, C.W, C.H, VclColorRGB(C.Color));
        SimpleText(D, X, Y, StringReplace(C.Text, '&', '', []), Txt);
      end;
    vkImage:
      if C.Picture <> nil then
      begin
        for TX := 0 to C.W - 1 do
          for I := 0 to C.H - 1 do
          begin
            if C.Stretch then
              S := ''
            else if (TX >= C.Picture.Width) or (I >= C.Picture.Height) then Continue;
            if C.Stretch then
              Face := C.Picture.Pixels[(TX * C.Picture.Width div C.W) +
                (I * C.Picture.Height div C.H) * C.Picture.Width]
            else Face := C.Picture.Pixels[TX + I * C.Picture.Width];
            if C.Transparent and (Face = C.TransColor) then Continue;
            if (X + TX >= 0) and (Y + I >= 0) and (X + TX < D.Width) and (Y + I < D.Height) then
              D.Pixels[X + TX + (Y + I) * D.Width] := Face;
          end;
      end;
  end;
  if C.Container then
  begin
    { graphic controls first, then windowed ones on top, as Windows does }
    for I := 0 to C.Children.Count - 1 do
      if not TVclCtl(C.Children[I]).Windowed then RenderCtl(F, C.Children[I], D, X, Y);
    for I := 0 to C.Children.Count - 1 do
      if TVclCtl(C.Children[I]).Windowed then RenderCtl(F, C.Children[I], D, X, Y);
  end;
end;

procedure TVclForm.Render(Dest: TGSurface);
var
  I: Integer;
begin
  for I := 0 to FCtls.Count - 1 do SyncFromWindow(TVclCtl(FCtls[I]));
  Dest.SetSize(ClientWidth, ClientHeight);
  RenderCtl(Self, Root, Dest, 0, 0);
end;

{ ---- state ---- }

procedure TVclForm.SyncFromWindow(C: TVclCtl);
{$IFDEF MSWINDOWS}
var
  Buf: array[0..1023] of Char;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  if C.Wnd = 0 then Exit;
  case C.Kind of
    vkEdit:
      begin
        Buf[0] := #0;
        GetWindowText(C.Wnd, Buf, SizeOf(Buf));
        C.Text := Buf;
      end;
    vkCombo:
      begin
        C.ItemIndex := SendMessage(C.Wnd, CB_GETCURSEL, 0, 0);
        Buf[0] := #0;
        GetWindowText(C.Wnd, Buf, SizeOf(Buf));
        C.Text := Buf;
      end;
    vkRadio, vkCheck: C.Checked := SendMessage(C.Wnd, BM_GETCHECK, 0, 0) = BST_CHECKED;
  end;
{$ENDIF}
end;

function TVclForm.GetText(const Name: string): string;
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then begin Result := ''; Exit; end;
  SyncFromWindow(C);
  Result := C.Text;
  { a list's text is its selected item }
  if (C.Kind = vkCombo) and (C.ItemIndex >= 0) and (C.ItemIndex < C.Items.Count) and
    (C.OwnerDraw or SameText(C.Obj.Ident('Style', 'csDropDown'), 'csDropDownList')) then
    Result := C.Items[C.ItemIndex];
end;

procedure TVclForm.SetText(const Name, Value: string);
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.Text := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then SetWindowText(C.Wnd, PChar(Value))
  else if (C.Parent <> nil) and (C.Parent.Wnd <> 0) then
    InvalidateRect(C.Parent.Wnd, nil, True)
  else if FCtls.Count > 0 then InvalidateRect(Root.Wnd, nil, True);
{$ENDIF}
end;

function TVclForm.GetChecked(const Name: string): Boolean;
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then begin Result := False; Exit; end;
  SyncFromWindow(C);
  Result := C.Checked;
end;

procedure TVclForm.SetChecked(const Name: string; Value: Boolean);
var
  C, Sib: TVclCtl;
  I: Integer;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.Checked := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then
  begin
    SendMessage(C.Wnd, BM_SETCHECK, Ord(Value), 0);
    if C.Kind = vkRadio then
      if Value then SetWindowLong(C.Wnd, GWL_STYLE, GetWindowLong(C.Wnd, GWL_STYLE) or WS_TABSTOP)
      else SetWindowLong(C.Wnd, GWL_STYLE, GetWindowLong(C.Wnd, GWL_STYLE) and not WS_TABSTOP);
  end;
{$ENDIF}
  if (C.Kind = vkRadio) and Value and (C.Parent <> nil) then
    for I := 0 to C.Parent.Children.Count - 1 do
    begin
      Sib := C.Parent.Children[I];
      if (Sib <> C) and (Sib.Kind = vkRadio) and Sib.Checked then
        SetChecked(Sib.Name, False);
    end;
end;

function TVclForm.GetItemIndex(const Name: string): Integer;
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then begin Result := -1; Exit; end;
  SyncFromWindow(C);
  Result := C.ItemIndex;
end;

procedure TVclForm.SetItemIndex(const Name: string; Value: Integer);
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.ItemIndex := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then SendMessage(C.Wnd, CB_SETCURSEL, WPARAM(Value), 0);
{$ENDIF}
end;

procedure TVclForm.SetItems(const Name: string; const Values: array of string);
var
  C: TVclCtl;
  I: Integer;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.Items.Clear;
  for I := 0 to High(Values) do C.Items.Add(Values[I]);
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then
  begin
    SendMessage(C.Wnd, CB_RESETCONTENT, 0, 0);
    for I := 0 to C.Items.Count - 1 do
      SendMessage(C.Wnd, CB_ADDSTRING, 0, LPARAM(PChar(C.Items[I])));
  end;
{$ENDIF}
  C.ItemIndex := -1;
end;

procedure TVclForm.SetEnabled(const Name: string; Value: Boolean);
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.Enabled := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then EnableWindow(C.Wnd, Value)
  else if (C.Parent <> nil) and (C.Parent.Wnd <> 0) then
    InvalidateRect(C.Parent.Wnd, nil, True);
{$ENDIF}
end;

procedure TVclForm.SetVisible(const Name: string; Value: Boolean);
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.Visible := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then ShowWindow(C.Wnd, Ord(Value) * SW_SHOW)
  else if (C.Parent <> nil) and (C.Parent.Wnd <> 0) then
    InvalidateRect(C.Parent.Wnd, nil, True);
{$ENDIF}
end;

procedure TVclForm.SetHeight(const Name: string; Value: Integer);
var
  C: TVclCtl;
begin
  C := Ctl(Name);
  if C = nil then Exit;
  C.H := Value;
{$IFDEF MSWINDOWS}
  if C.Wnd <> 0 then
  begin
    SetWindowPos(C.Wnd, 0, 0, 0, C.W, C.H, SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE);
    InvalidateRect(C.Wnd, nil, True);
  end;
{$ENDIF}
end;

procedure TVclForm.SetCaption(const Value: string);
begin
  Caption := Value;
  Root.Text := Value;
{$IFDEF MSWINDOWS}
  if Root.Wnd <> 0 then SetWindowText(Root.Wnd, PChar(Value));
{$ENDIF}
end;

procedure TVclForm.Focus(const Name: string);
{$IFDEF MSWINDOWS}
var
  C: TVclCtl;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  C := Ctl(Name);
  if (C <> nil) and (C.Wnd <> 0) then SetFocus(C.Wnd);
{$ENDIF}
end;

{$IFDEF MSWINDOWS}

{ ---- Win32 ---- }

var
  CurForm: TVclForm;
  AppWnd: THandle = 0;
  Registered: Boolean;

function FindByWnd(F: TVclForm; Wnd: THandle): TVclCtl;
var
  I: Integer;
begin
  for I := 0 to F.FCtls.Count - 1 do
    if TVclCtl(F.FCtls[I]).Wnd = Wnd then begin Result := TVclCtl(F.FCtls[I]); Exit; end;
  Result := nil;
end;

function FindById(F: TVclForm; Id: Integer): TVclCtl;
var
  I: Integer;
begin
  for I := 0 to F.FCtls.Count - 1 do
    if TVclCtl(F.FCtls[I]).Id = Id then begin Result := TVclCtl(F.FCtls[I]); Exit; end;
  Result := nil;
end;

function MkRect(L, T, R, B: Integer): TRect;
begin
  Result.Left := L;
  Result.Top := T;
  Result.Right := R;
  Result.Bottom := B;
end;

function MakeFont(C: TVclCtl): HFONT;
var
  Wt: Integer;
begin
  if C.FontBold then Wt := FW_BOLD else Wt := FW_NORMAL;
  Result := CreateFont(C.FontHeight, 0, 0, 0, Wt, Ord(C.FontItalic),
    Ord(C.FontUnderline), 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
    CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE,
    PChar(C.FontName));
end;

function ColorRef(C: Cardinal): COLORREF;
begin
  if C and $FF000000 <> 0 then Result := GetSysColor(C and $FF)
  else Result := C and $FFFFFF;
end;

procedure DrawSurface(DC: HDC; S: TGSurface; X, Y, W, H: Integer);
var
  BI: TBitmapInfo;
begin
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := S.Width;
  BI.bmiHeader.biHeight := -S.Height;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  StretchDIBits(DC, X, Y, W, H, 0, 0, S.Width, S.Height, @S.Pixels[0], BI,
    DIB_RGB_COLORS, SRCCOPY);
end;

{ TImage.Stretch goes through StretchBlt in the DC's default mode,
  BLACKONWHITE: a shrink ANDs the source pixels that fall on one target
  pixel (which keeps dark outlines), a stretch repeats them }
function StretchPixel(Src: TGSurface; I, J, SW, SH: Integer): Cardinal;
var
  X0, X1, Y0, Y1, X, Y: Integer;
begin
  { an enlarged axis samples each target pixel's centre, rounded down }
  if SW >= Src.Width then
  begin
    X0 := (2 * I * Src.Width + Src.Width - 1) div (2 * SW);
    X1 := X0 + 1;
  end
  else
  begin
    X0 := I * Src.Width div SW;
    X1 := (I + 1) * Src.Width div SW;
  end;
  if SH >= Src.Height then
  begin
    Y0 := (2 * J * Src.Height + Src.Height - 1) div (2 * SH);
    Y1 := Y0 + 1;
  end
  else
  begin
    Y0 := J * Src.Height div SH;
    Y1 := (J + 1) * Src.Height div SH;
  end;
  if X1 <= X0 then X1 := X0 + 1;
  if Y1 <= Y0 then Y1 := Y0 + 1;
  Result := $FFFFFFFF;
  for Y := Y0 to Y1 - 1 do
    for X := X0 to X1 - 1 do
      Result := Result and Src.Pixels[X + Y * Src.Width];
end;

procedure PaintImage(DC: HDC; C: TVclCtl);
var
  Img: TGSurface;
  I, J, SW, SH: Integer;
  Bg, P: Cardinal;
begin
  if C.Picture = nil then Exit;
  if C.Stretch then begin SW := C.W; SH := C.H; end
  else
  begin
    SW := C.Picture.Width;
    SH := C.Picture.Height;
    if SW > C.W then SW := C.W;
    if SH > C.H then SH := C.H;
  end;
  if (SW <= 0) or (SH <= 0) then Exit;
  Bg := VclColorRGB(C.Parent.Color);
  Img := TGSurface.Create(SW, SH);
  try
    for J := 0 to SH - 1 do
      for I := 0 to SW - 1 do
      begin
        if C.Stretch then P := StretchPixel(C.Picture, I, J, SW, SH)
        else P := C.Picture.Pixels[I + J * C.Picture.Width];
        if C.Transparent and (P = C.TransColor) then P := Bg;
        Img.Pixels[I + J * SW] := P;
      end;
    DrawSurface(DC, Img, C.X, C.Y, SW, SH);
  finally
    Img.Free;
  end;
end;

procedure PaintLabel(DC: HDC; C: TVclCtl);
var
  R: TRect;
  Flags: UINT;
  Old: HGDIOBJ;
  Br: HBRUSH;
begin
  R := MkRect(C.X, C.Y, C.X + C.W, C.Y + C.H);
  if not C.Transparent then
  begin
    Br := CreateSolidBrush(ColorRef(C.Color));
    FillRect(DC, R, Br);
    DeleteObject(Br);
  end;
  Flags := DT_EXPANDTABS;
  if C.WordWrap then Flags := Flags or DT_WORDBREAK;
  case C.Alignment of
    1: Flags := Flags or DT_RIGHT;
    2: Flags := Flags or DT_CENTER;
  else
    Flags := Flags or DT_LEFT;
  end;
  if C.Font = 0 then C.Font := MakeFont(C);
  Old := SelectObject(DC, C.Font);
  SetBkMode(DC, TRANSPARENT);
  if C.Enabled then
  begin
    SetTextColor(DC, ColorRef(C.FontColor));
    DrawText(DC, PChar(C.Text), Length(C.Text), R, Flags);
  end
  else
  begin
    { the VCL's disabled label: white one pixel down-right, then grey }
    OffsetRect(R, 1, 1);
    SetTextColor(DC, GetSysColor(COLOR_BTNHIGHLIGHT));
    DrawText(DC, PChar(C.Text), Length(C.Text), R, Flags);
    OffsetRect(R, -1, -1);
    SetTextColor(DC, GetSysColor(COLOR_BTNSHADOW));
    DrawText(DC, PChar(C.Text), Length(C.Text), R, Flags);
  end;
  SelectObject(DC, Old);
end;

procedure FrameR(DC: HDC; R: TRect; Color: COLORREF);
var
  Br: HBRUSH;
begin
  Br := CreateSolidBrush(Color);
  FrameRect(DC, R, Br);
  DeleteObject(Br);
end;

procedure TVclForm.PaintContainer(C: TVclCtl; DC: THandle);
var
  I, TH: Integer;
  R: TRect;
  Ch: TVclCtl;
  Old: HGDIOBJ;
  Br: HBRUSH;
  Hi, Lo: COLORREF;
  TM: TTextMetric;
begin
  GetClientRect(C.Wnd, R);
  Br := CreateSolidBrush(ColorRef(C.Color));
  FillRect(DC, R, Br);
  DeleteObject(Br);
  if C.Font = 0 then C.Font := MakeFont(C);
  Old := SelectObject(DC, C.Font);
  if C.Kind = vkGroup then
  begin
    { TGroupBox.Paint (Ctl3D): an etched frame from half the text height,
      the caption at x 8 over it }
    GetTextMetrics(DC, TM);
    TH := TM.tmHeight;
    R := MkRect(0, TH div 2 - 1, C.W, C.H);
    Inc(R.Left);
    Inc(R.Top);
    FrameR(DC, R, GetSysColor(COLOR_BTNHIGHLIGHT));
    OffsetRect(R, -1, -1);
    FrameR(DC, R, GetSysColor(COLOR_BTNSHADOW));
    if C.Text <> '' then
    begin
      R := MkRect(8, 0, 0, TH);
      DrawText(DC, PChar(C.Text), Length(C.Text), R, DT_LEFT or DT_SINGLELINE or DT_CALCRECT);
      SetBkMode(DC, OPAQUE);
      SetBkColor(DC, ColorRef(C.Color));
      if C.Enabled then SetTextColor(DC, ColorRef(C.FontColor))
      else SetTextColor(DC, GetSysColor(COLOR_GRAYTEXT));
      DrawText(DC, PChar(C.Text), Length(C.Text), R, DT_LEFT or DT_SINGLELINE);
    end;
  end
  else if C.Kind = vkPanel then
  begin
    { TCustomPanel.Paint: outer bevel, inner bevel, caption centred }
    { Frame3D: the top and left edge in one colour, the bottom and right
      edge in the other }
    if C.BevelOuter in [1, 2] then
    begin
      if C.BevelOuter = 2 then
      begin
        Hi := GetSysColor(COLOR_BTNHIGHLIGHT);
        Lo := GetSysColor(COLOR_BTNSHADOW);
      end
      else
      begin
        Hi := GetSysColor(COLOR_BTNSHADOW);
        Lo := GetSysColor(COLOR_BTNHIGHLIGHT);
      end;
      FrameR(DC, MkRect(0, 0, C.W, C.H), Lo);
      FrameR(DC, MkRect(0, 0, C.W - 1, 1), Hi);
      FrameR(DC, MkRect(0, 0, 1, C.H - 1), Hi);
    end;
    if C.Text <> '' then
    begin
      R := MkRect(0, 0, C.W, C.H);
      SetBkMode(DC, TRANSPARENT);
      SetTextColor(DC, ColorRef(C.FontColor));
      DrawText(DC, PChar(C.Text), Length(C.Text), R,
        DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    end;
  end;
  SelectObject(DC, Old);
  if C = Root then SetViewportOrgEx(DC, -FScrollX, -FScrollY, nil);
  for I := 0 to C.Children.Count - 1 do
  begin
    Ch := C.Children[I];
    if Ch.Windowed or not Ch.Visible then Continue;
    if Ch.Kind = vkLabel then PaintLabel(DC, Ch)
    else if Ch.Kind = vkImage then PaintImage(DC, Ch);
  end;
end;

{ TScrollingWinControl with AutoScroll (a TForm's default): when the
  controls reach past the client area (a window frame thicker than the one
  the form was made with), scroll bars show for the controls' extent, and
  the focused control is scrolled into view (AutoScrollInView). }
procedure TVclForm.AutoScrollSetup;
var
  R: TRect;
  I, ClW, ClH: Integer;
  Ch: TVclCtl;
  SI: TScrollInfo;
begin
  FRangeW := 0;
  FRangeH := 0;
  FScrollX := 0;
  FScrollY := 0;
  FHasH := False;
  FHasV := False;
  if not Root.Obj.Bool('AutoScroll', True) then Exit;
  for I := 0 to Root.Children.Count - 1 do
  begin
    Ch := Root.Children[I];
    if not Ch.Visible then Continue;
    if Ch.X + Ch.W > FRangeW then FRangeW := Ch.X + Ch.W;
    if Ch.Y + Ch.H > FRangeH then FRangeH := Ch.Y + Ch.H;
  end;
  GetClientRect(Root.Wnd, R);
  ClW := R.Right;
  ClH := R.Bottom;
  FHasH := FRangeW > ClW;
  FHasV := FRangeH > ClH;
  { one bar takes room from the other direction }
  if FHasH and not FHasV then FHasV := FRangeH > ClH - GetSystemMetrics(SM_CYHSCROLL);
  if FHasV and not FHasH then FHasH := FRangeW > ClW - GetSystemMetrics(SM_CXVSCROLL);
  if not (FHasH or FHasV) then Exit;
  ShowScrollBar(Root.Wnd, SB_HORZ, FHasH);
  ShowScrollBar(Root.Wnd, SB_VERT, FHasV);
  GetClientRect(Root.Wnd, R);
  FillChar(SI, SizeOf(SI), 0);
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
  if FHasH then
  begin
    SI.nMax := FRangeW - 1;
    SI.nPage := R.Right;
    SetScrollInfo(Root.Wnd, SB_HORZ, SI, True);
  end;
  if FHasV then
  begin
    SI.nMax := FRangeH - 1;
    SI.nPage := R.Bottom;
    SetScrollInfo(Root.Wnd, SB_VERT, SI, True);
  end;
end;

procedure TVclForm.ScrollTo(X, Y: Integer);
var
  R: TRect;
begin
  GetClientRect(Root.Wnd, R);
  if not FHasH then X := 0
  else if X > FRangeW - R.Right then X := FRangeW - R.Right;
  if not FHasV then Y := 0
  else if Y > FRangeH - R.Bottom then Y := FRangeH - R.Bottom;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  if (X = FScrollX) and (Y = FScrollY) then Exit;
  ScrollWindowEx(Root.Wnd, FScrollX - X, FScrollY - Y, nil, nil, 0, nil,
    SW_SCROLLCHILDREN or SW_INVALIDATE or SW_ERASE);
  FScrollX := X;
  FScrollY := Y;
  if FHasH then SetScrollPos(Root.Wnd, SB_HORZ, X, True);
  if FHasV then SetScrollPos(Root.Wnd, SB_VERT, Y, True);
  InvalidateRect(Root.Wnd, nil, True);
end;

procedure TVclForm.ScrollInView(C: TVclCtl);
var
  R: TRect;
  L, T, Rt, B, X, Y: Integer;
  P: TVclCtl;
begin
  if not (FHasH or FHasV) or (C = nil) then Exit;
  { the control's top-level ancestor on the form }
  P := C;
  while (P.Parent <> nil) and (P.Parent <> Root) do P := P.Parent;
  GetClientRect(Root.Wnd, R);
  L := P.X - FScrollX;
  T := P.Y - FScrollY;
  Rt := L + P.W;
  B := T + P.H;
  X := FScrollX;
  Y := FScrollY;
  if L < 0 then X := X + L
  else if Rt > R.Right then
  begin
    if Rt - L > R.Right then Rt := L + R.Right;
    X := X + Rt - R.Right;
  end;
  if T < 0 then Y := Y + T
  else if B > R.Bottom then
  begin
    if B - T > R.Bottom then B := T + R.Bottom;
    Y := Y + B - R.Bottom;
  end;
  ScrollTo(X, Y);
end;

procedure TVclForm.ScrollMsg(Bar, Code: Integer);
var
  SI: TScrollInfo;
  P: Integer;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_ALL;
  GetScrollInfo(Root.Wnd, Bar, SI);
  P := SI.nPos;
  case Code of
    SB_LINEUP: Dec(P, 8);
    SB_LINEDOWN: Inc(P, 8);
    SB_PAGEUP: Dec(P, SI.nPage);
    SB_PAGEDOWN: Inc(P, SI.nPage);
    SB_THUMBTRACK, SB_THUMBPOSITION: P := SI.nTrackPos;
    SB_TOP: P := 0;
    SB_BOTTOM: P := SI.nMax;
  end;
  if Bar = SB_HORZ then ScrollTo(P, FScrollY) else ScrollTo(FScrollX, P);
end;

procedure TVclForm.Command(Id, Code: Integer);
var
  C, Sib: TVclCtl;
  I: Integer;
  WR: TRect;
begin
  C := FindById(Self, Id);
  if C = nil then Exit;
  case C.Kind of
    vkButton:
      if Code = BN_CLICKED then
        if Assigned(OnEvent) then OnEvent(Self, C, veClick);
    vkRadio:
      if Code = BN_CLICKED then
      begin
        { TRadioButton: checks itself and clears its siblings }
        if not C.Checked then
        begin
          SetChecked(C.Name, True);
          if C.Parent <> nil then
            for I := 0 to C.Parent.Children.Count - 1 do
            begin
              Sib := C.Parent.Children[I];
              if (Sib <> C) and (Sib.Kind = vkRadio) then SetChecked(Sib.Name, False);
            end;
        end;
        if Assigned(OnEvent) then OnEvent(Self, C, veClick);
      end;
    vkCheck:
      if Code = BN_CLICKED then
      begin
        SetChecked(C.Name, not C.Checked);
        if Assigned(OnEvent) then OnEvent(Self, C, veClick);
      end;
    vkEdit:
      if Code = EN_CHANGE then
      begin
        SyncFromWindow(C);
        if Assigned(OnEvent) then OnEvent(Self, C, veChange);
      end;
    vkCombo:
      if Code = CBN_DROPDOWN then
      begin
        { TCustomComboBox.AdjustDropDown: the list holds DropDownCount
          items (fewer when there are fewer) }
        I := C.Items.Count;
        if I > C.DropDownCount then I := C.DropDownCount;
        if I < 1 then I := 1;
        { Height is the window's own, which the field's size sets }
        GetWindowRect(C.Wnd, WR);
        SetWindowPos(C.Wnd, 0, 0, 0, C.W, C.ItemHeight * I + (WR.Bottom - WR.Top) + 2,
          SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_NOREDRAW or SWP_HIDEWINDOW);
        SetWindowPos(C.Wnd, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
          SWP_NOACTIVATE or SWP_NOREDRAW or SWP_SHOWWINDOW);
      end
      else if Code = CBN_SELCHANGE then
      begin
        SyncFromWindow(C);
        if Assigned(OnEvent) then OnEvent(Self, C, veChange);
      end;
  end;
end;

procedure DrawItem(F: TVclForm; DIS: PDrawItemStruct);
var
  C: TVclCtl;
  Item: TGSurface;
  R, TR: TRect;
  Br: HBRUSH;
  Old: HGDIOBJ;
  Sel: Boolean;
  S: string;
  W, H: Integer;
begin
  C := FindById(F, DIS^.CtlID);
  if C = nil then Exit;
  R := DIS^.rcItem;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  Sel := DIS^.itemState and ODS_SELECTED <> 0;
  { TCustomComboBox.CNDrawItem: the canvas brush is clHighlight for a
    selected item, else the control's colour; the program then draws }
  Br := CreateSolidBrush(ColorRef(C.ItemFill));
  FillRect(DIS^.hDC, R, Br);
  DeleteObject(Br);
  { the selection field (ODS_COMBOBOXEDIT): under the real clients the head
    sits one pixel lower than in a list item, the name does not }
  TR := R;
  if DIS^.itemState and $1000 <> 0 then
  begin
    Inc(R.Top);
    H := R.Bottom - R.Top;
  end;
  if Integer(DIS^.itemID) < 0 then Exit;
  if (W > 0) and (H > 0) and Assigned(F.OnDrawItem) then
  begin
    Item := TGSurface.Create(W, H);
    try
      Item.Fill(VclColorRGB(C.ItemFill));
      F.OnDrawItem(F, C, DIS^.itemID, Sel, Item);
      DrawSurface(DIS^.hDC, Item, R.Left, R.Top, W, H);
    finally
      Item.Free;
    end;
  end;
  if Integer(DIS^.itemID) < C.Items.Count then S := C.Items[DIS^.itemID] else S := '';
  if C.Font = 0 then C.Font := MakeFont(C);
  Old := SelectObject(DIS^.hDC, C.Font);
  SetBkMode(DIS^.hDC, TRANSPARENT);
  if Sel then SetTextColor(DIS^.hDC, GetSysColor(COLOR_HIGHLIGHTTEXT))
  else SetTextColor(DIS^.hDC, ColorRef(C.FontColor));
  TextOut(DIS^.hDC, TR.Left + C.ItemTextX, TR.Top, PChar(S), Length(S));
  SelectObject(DIS^.hDC, Old);
  if DIS^.itemState and ODS_FOCUS <> 0 then DrawFocusRect(DIS^.hDC, DIS^.rcItem);
end;

var
  BrushColors: array[0..15] of Cardinal;
  Brushes: array[0..15] of HBRUSH;
  BrushCount: Integer = 0;

function FillBrush(C: Cardinal): HBRUSH;
var
  I: Integer;
begin
  for I := 0 to BrushCount - 1 do
    if BrushColors[I] = C then begin Result := Brushes[I]; Exit; end;
  Result := CreateSolidBrush(ColorRef(C));
  if BrushCount <= High(Brushes) then
  begin
    BrushColors[BrushCount] := C;
    Brushes[BrushCount] := Result;
    Inc(BrushCount);
  end;
end;

function ContainerProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  C: TVclCtl;
  PS: TPaintStruct;
  DC: HDC;
begin
  Result := 0;
  if CurForm <> nil then
  begin
    C := FindByWnd(CurForm, Wnd);
    case Msg of
      WM_ERASEBKGND: begin Result := 1; Exit; end;
      WM_PAINT:
        if C <> nil then
        begin
          DC := BeginPaint(Wnd, PS);
          CurForm.PaintContainer(C, DC);
          EndPaint(Wnd, PS);
          Exit;
        end;
      WM_COMMAND:
        begin
          CurForm.Command(WP and $FFFF, (WP shr 16) and $FFFF);
          Exit;
        end;
      WM_HSCROLL, WM_VSCROLL:
        if (C = CurForm.Root) and (LP = 0) then
        begin
          if Msg = WM_HSCROLL then CurForm.ScrollMsg(SB_HORZ, WP and $FFFF)
          else CurForm.ScrollMsg(SB_VERT, WP and $FFFF);
          Exit;
        end;
      WM_MEASUREITEM:
        begin
          C := FindById(CurForm, PMeasureItemStruct(LP)^.CtlID);
          if C <> nil then PMeasureItemStruct(LP)^.itemHeight := C.ItemHeight;
          Result := 1;
          Exit;
        end;
      WM_DRAWITEM:
        begin
          DrawItem(CurForm, PDrawItemStruct(LP));
          Result := 1;
          Exit;
        end;
      WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX:
        begin
          C := FindByWnd(CurForm, LP);
          if (C <> nil) and (C.Kind = vkCombo) and C.OwnerDraw then
          begin
            { an owner-drawn list's ground is its items' fill }
            SetBkColor(WP, ColorRef(C.ItemFill));
            Result := LRESULT(FillBrush(C.ItemFill));
            Exit;
          end;
        end;
      WM_CTLCOLORSTATIC, WM_CTLCOLORBTN:
        begin
          C := FindByWnd(CurForm, LP);
          if (C <> nil) and (C.Kind = vkEdit) then
          begin
            { TWinControl.CNCtlColorStatic: a read-only or disabled edit
              keeps its own colour }
            SetBkColor(WP, ColorRef(C.Color));
            SetTextColor(WP, ColorRef(C.FontColor));
            Result := LRESULT(FillBrush(C.Color));
            Exit;
          end;
          if C <> nil then
          begin
            SetBkColor(WP, ColorRef(C.Color));
            if C.Enabled then SetTextColor(WP, ColorRef(C.FontColor));
            Result := LRESULT(GetSysColorBrush(COLOR_BTNFACE));
            Exit;
          end;
        end;
      WM_CLOSE:
        if (C <> nil) and (C.Kind = vkForm) then
        begin
          CurForm.Close(-1);
          Exit;
        end;
    end;
  end;
  Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

function EditProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  C: TVclCtl;
begin
  C := nil;
  if CurForm <> nil then C := FindByWnd(CurForm, Wnd);
  if (C <> nil) and (Msg = WM_KEYDOWN) and (WP = VK_RETURN) then
  begin
    if Assigned(CurForm.OnEvent) then CurForm.OnEvent(CurForm, C, veEnter);
    Result := 0;
    Exit;
  end;
  if (C <> nil) and (Msg = WM_CHAR) and (WP = 13) then begin Result := 0; Exit; end;
  if (C <> nil) and (Msg = WM_GETDLGCODE) and (LP <> 0) and
    (PMsg(LP)^.message = WM_KEYDOWN) and (PMsg(LP)^.wParam = VK_RETURN) then
    begin Result := DLGC_WANTALLKEYS; Exit; end;
  if (C <> nil) and (C.OldProc <> nil) then
    Result := CallWindowProc(C.OldProc, Wnd, Msg, WP, LP)
  else
    Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

function AppProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
begin
  if (Msg = WM_CLOSE) and (CurForm <> nil) then
  begin
    CurForm.Close(-1);
    Result := 0;
    Exit;
  end;
  Result := DefWindowProc(Wnd, Msg, WP, LP);
end;

procedure RegisterClasses;
var
  WC: TWndClass;
begin
  if Registered then Exit;
  Registered := True;
  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @ContainerProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hIcon := LoadIcon(HInstance, 'MAINICON');
  WC.hbrBackground := COLOR_BTNFACE + 1;
  WC.style := CS_DBLCLKS;
  WC.lpszClassName := 'TGraalVclForm';
  Windows.RegisterClass(WC);
  WC.hIcon := 0;
  WC.lpszClassName := 'TGraalVclBox';
  Windows.RegisterClass(WC);
  WC.lpfnWndProc := @AppProc;
  WC.hIcon := LoadIcon(HInstance, 'MAINICON');
  WC.hbrBackground := 0;
  WC.lpszClassName := 'TApplication';
  Windows.RegisterClass(WC);
end;

{ The VCL's window class names: a form or box registers its own Delphi
  class name, a standard control a copy of the system class under its
  Delphi name (TWinControl.CreateWnd superclasses BUTTON as TButton, ...). }
function VclClass(const Name, Base: string): string;
var
  WC: TWndClass;
begin
  Result := Name;
  if (Name <> '') and GetClassInfo(HInstance, PChar(Name), WC) then Exit;
  { Base: a system class, or one of ours ('TGraalVclForm', 'TGraalVclBox') }
  if not GetClassInfo(0, PChar(Base), WC) and
    not GetClassInfo(HInstance, PChar(Base), WC) then begin Result := Base; Exit; end;
  if Name = '' then begin Result := Base; Exit; end;
  WC.hInstance := HInstance;
  WC.lpszClassName := PChar(Name);
  if Windows.RegisterClass(WC) = 0 then Result := Base;
end;

function ByTabOrder(A, B: Pointer): Integer;
begin
  Result := TVclCtl(A).TabOrder - TVclCtl(B).TabOrder;
end;

procedure TVclForm.CreateWin(C: TVclCtl; ParentWnd: THandle);
var
  DC: HDC;
  OldF: HGDIOBJ;
  TM: TTextMetric;
  Style, ExStyle: DWORD;
  Cls: string;
  H, I: Integer;
  L: TList;
begin
  ExStyle := 0;
  Style := WS_CHILD or WS_CLIPSIBLINGS;
  if C.Visible then Style := Style or WS_VISIBLE;
  if not C.Enabled then Style := Style or WS_DISABLED;
  if C.TabStop then Style := Style or WS_TABSTOP;
  H := C.H;
  case C.Kind of
    vkGroup, vkPanel:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'TGraalVclBox');
        Style := Style or WS_CLIPCHILDREN;
        ExStyle := WS_EX_CONTROLPARENT;
      end;
    vkButton:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'BUTTON');
        if C.IsDefault then Style := Style or BS_DEFPUSHBUTTON
        else Style := Style or BS_PUSHBUTTON;
      end;
    vkRadio:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'BUTTON');
        Style := Style or BS_RADIOBUTTON;
        if C.Checked then Style := Style or WS_TABSTOP else Style := Style and not WS_TABSTOP;
        if C.Alignment = 1 then Style := Style or BS_LEFTTEXT;
      end;
    vkCheck:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'BUTTON');
        Style := Style or BS_CHECKBOX;
        if C.Alignment = 1 then Style := Style or BS_LEFTTEXT;
      end;
    vkEdit:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'EDIT');
        Style := Style or ES_AUTOHSCROLL;
        if C.Obj.Bool('ReadOnly', False) then Style := Style or ES_READONLY;
        ExStyle := WS_EX_CLIENTEDGE;
      end;
    vkCombo:
      begin
        Cls := VclClass(C.Obj.ClassName_, 'COMBOBOX');
        Style := Style or WS_VSCROLL;
        if C.OwnerDraw then
          Style := Style or CBS_DROPDOWNLIST or CBS_OWNERDRAWFIXED or CBS_HASSTRINGS
        else if SameText(C.Obj.Ident('Style', 'csDropDown'), 'csDropDownList') then
          Style := Style or CBS_DROPDOWNLIST
        else if SameText(C.Obj.Ident('Style', 'csDropDown'), 'csSimple') then
          Style := Style or CBS_SIMPLE
        else
          Style := Style or CBS_DROPDOWN or CBS_AUTOHSCROLL;
        if C.Obj.Bool('Sorted', False) then Style := Style or CBS_SORT;
        { the window includes the drop-down list: TCustomComboBox sizes it
          to DropDownCount items }
        H := C.H + C.ItemHeight * C.DropDownCount + 2;
      end;
  else
    Exit;
  end;
  C.Wnd := CreateWindowEx(ExStyle, PChar(Cls), PChar(C.Text), Style, C.X, C.Y, C.W, H,
    ParentWnd, HMENU(C.Id), HInstance, nil);
  if C.Wnd = 0 then Exit;
  C.Font := MakeFont(C);
  SendMessage(C.Wnd, WM_SETFONT, WPARAM(C.Font), 0);
  case C.Kind of
    vkRadio, vkCheck: SendMessage(C.Wnd, BM_SETCHECK, Ord(C.Checked), 0);
    vkEdit:
      begin
        if C.Obj.Int('MaxLength', 0) > 0 then
          SendMessage(C.Wnd, EM_LIMITTEXT, C.Obj.Int('MaxLength', 0), 0);
        if C.Obj.Has('PasswordChar') then
          SendMessage(C.Wnd, EM_SETPASSWORDCHAR, Ord(C.Obj.Str('PasswordChar', '*')[1]), 0);
        C.OldProc := Pointer(SetWindowLongPtr(C.Wnd, GWL_WNDPROC, LONG_PTR(@EditProc)));
      end;
    vkCombo:
      begin
        if C.OwnerDraw then
        begin
          { the selection field keeps the height the font gives (text
            height + 2), as the real lists show; the list items are
            ItemHeight (WM_MEASUREITEM) }
          DC := GetDC(C.Wnd);
          OldF := SelectObject(DC, C.Font);
          GetTextMetrics(DC, TM);
          SelectObject(DC, OldF);
          ReleaseDC(C.Wnd, DC);
          SendMessage(C.Wnd, CB_SETITEMHEIGHT, WPARAM(-1), TM.tmHeight + 2);
        end;
        for I := 0 to C.Items.Count - 1 do
          SendMessage(C.Wnd, CB_ADDSTRING, 0, LPARAM(PChar(C.Items[I])));
        SendMessage(C.Wnd, CB_SETCURSEL, WPARAM(C.ItemIndex), 0);
        { an editable list's text goes to its edit field }
        if (C.ItemIndex < 0) and (C.Text <> '') and not C.OwnerDraw and
          not SameText(C.Obj.Ident('Style', 'csDropDown'), 'csDropDownList') then
          SetWindowText(C.Wnd, PChar(C.Text));
      end;
  end;
  if C.Container then
  begin
    L := TList.Create;
    try
      for I := 0 to C.Children.Count - 1 do
        if TVclCtl(C.Children[I]).Windowed then L.Add(C.Children[I]);
      L.Sort(ByTabOrder);
      for I := 0 to L.Count - 1 do CreateWin(L[I], C.Wnd);
    finally
      L.Free;
    end;
  end;
end;

{ TButton.SetButtonStyle: the focused button is drawn as the default one;
  with another control focused, the button whose Default is True is. }
procedure UpdateDefault;
var
  I: Integer;
  C: TVclCtl;
  Foc: HWND;
  FocBtn, Want: Boolean;
  St: DWORD;
begin
  if CurForm = nil then Exit;
  Foc := GetFocus;
  FocBtn := False;
  for I := 0 to CurForm.FCtls.Count - 1 do
  begin
    C := CurForm.FCtls[I];
    if (C.Kind = vkButton) and (C.Wnd <> 0) and (C.Wnd = Foc) then FocBtn := True;
  end;
  for I := 0 to CurForm.FCtls.Count - 1 do
  begin
    C := CurForm.FCtls[I];
    if (C.Kind <> vkButton) or (C.Wnd = 0) then Continue;
    Want := (C.Wnd = Foc) or (not FocBtn and C.IsDefault);
    St := GetWindowLong(C.Wnd, GWL_STYLE) and $F;
    if Want and (St <> BS_DEFPUSHBUTTON) then
      SendMessage(C.Wnd, BM_SETSTYLE, BS_DEFPUSHBUTTON, 1)
    else if not Want and (St = BS_DEFPUSHBUTTON) then
      SendMessage(C.Wnd, BM_SETSTYLE, BS_PUSHBUTTON, 1);
  end;
  { focus moved: the new control is scrolled into view, as the VCL does }
  if (Foc <> CurForm.FFocusWnd) and (CurForm.FHasH or CurForm.FHasV) then
  begin
    CurForm.FFocusWnd := Foc;
    for I := 0 to CurForm.FCtls.Count - 1 do
    begin
      C := CurForm.FCtls[I];
      if (C.Wnd <> 0) and ((C.Wnd = Foc) or IsChild(C.Wnd, Foc)) then
      begin
        CurForm.ScrollInView(C);
        Break;
      end;
    end;
  end;
end;

function TVclForm.ShowModal: Integer;
var
  Style, ExStyle: DWORD;
  R: TRect;
  Owner: HWND;
  M: TMsg;
  I, X, Y: Integer;
  L: TList;
  Icon: HICON;
  First: TVclCtl;
begin
  RegisterClasses;
  CurForm := Self;
  FDone := False;
  FResult := -1;
  if FAppWnd = 0 then FAppWnd := AppWnd;
  if FAppWnd = 0 then
  begin
    { TApplication's window: zero size, on screen, so the taskbar shows
      the program's title and icon once }
    FAppWnd := CreateWindowEx(WS_EX_TOOLWINDOW or WS_EX_WINDOWEDGE, 'TApplication', PChar(AppTitle),
      WS_POPUP or WS_CAPTION or WS_CLIPSIBLINGS or WS_SYSMENU or WS_MINIMIZEBOX,
      GetSystemMetrics(SM_CXSCREEN) div 2, GetSystemMetrics(SM_CYSCREEN) div 2, 0, 0,
      0, 0, HInstance, nil);
    ShowWindow(FAppWnd, SW_SHOWNORMAL);
    AppWnd := FAppWnd;
  end;
  Style := WS_CAPTION or WS_CLIPCHILDREN or WS_CLIPSIBLINGS;
  if SystemMenu then Style := Style or WS_SYSMENU;
  if MinimizeBox then Style := Style or WS_MINIMIZEBOX;
  if MaximizeBox then Style := Style or WS_MAXIMIZEBOX;
  if Sizeable then Style := Style or WS_THICKFRAME
  else if SameText(BorderStyle, 'bsDialog') then Style := Style or DS_MODALFRAME
  else Style := Style or WS_BORDER;
  if SizedFromClient then
  begin
    { the outer size that holds the form's client area with this style }
    R.Left := 0;
    R.Top := 0;
    R.Right := ClientWidth;
    R.Bottom := ClientHeight;
    if AdjustWindowRectEx(R, Style, False, WS_EX_CONTROLPARENT or WS_EX_WINDOWEDGE) then
    begin
      Width := R.Right - R.Left;
      Height := R.Bottom - R.Top;
    end;
  end;
  { poScreenCenter }
  X := (GetSystemMetrics(SM_CXSCREEN) - Width) div 2;
  Y := (GetSystemMetrics(SM_CYSCREEN) - Height) div 2;
  if not SameText(Root.Obj.Ident('Position', 'poDesigned'), 'poScreenCenter') then
  begin
    X := Root.X;
    Y := Root.Y;
  end;
  ExStyle := WS_EX_CONTROLPARENT or WS_EX_WINDOWEDGE;
  if StayOnTop then ExStyle := ExStyle or WS_EX_TOPMOST;
  if AppOwned then Owner := FAppWnd else Owner := 0;
  Root.Wnd := CreateWindowEx(ExStyle, PChar(VclClass(Root.Obj.ClassName_, 'TGraalVclForm')), PChar(Caption),
    Style, X, Y, Width, Height, Owner, 0, HInstance, nil);
  Root.Font := MakeFont(Root);
  Icon := LoadIcon(HInstance, 'MAINICON');
  SendMessage(Root.Wnd, WM_SETICON, ICON_BIG, LPARAM(Icon));
  SendMessage(Root.Wnd, WM_SETICON, ICON_SMALL, LPARAM(Icon));
  L := TList.Create;
  try
    for I := 0 to Root.Children.Count - 1 do
      if TVclCtl(Root.Children[I]).Windowed then L.Add(Root.Children[I]);
    L.Sort(ByTabOrder);
    for I := 0 to L.Count - 1 do CreateWin(L[I], Root.Wnd);
  finally
    L.Free;
  end;
  AutoScrollSetup;
  FFocusWnd := 0;
  ShowWindow(Root.Wnd, SW_SHOW);
  SetForegroundWindow(Root.Wnd);
  { ActiveControl, else the first tab stop }
  First := Ctl(Root.Obj.Ident('ActiveControl', ''));
  if (First <> nil) and (First.Wnd <> 0) then SetFocus(First.Wnd)
  else SetFocus(GetNextDlgTabItem(Root.Wnd, 0, False));
  UpdateDefault;
  while not FDone do
  begin
    if not GetMessage(M, 0, 0, 0) then
    begin
      PostQuitMessage(M.wParam);
      FResult := -1;
      Break;
    end;
    if not IsDialogMessage(Root.Wnd, M) then
    begin
      TranslateMessage(M);
      DispatchMessage(M);
    end;
    UpdateDefault;
  end;
  for I := 0 to FCtls.Count - 1 do SyncFromWindow(TVclCtl(FCtls[I]));
  Result := FResult;
end;

procedure TVclForm.Hide;
var
  I: Integer;
begin
  for I := 0 to FCtls.Count - 1 do SyncFromWindow(TVclCtl(FCtls[I]));
  if Root <> nil then
  begin
    if Root.Wnd <> 0 then DestroyWindow(Root.Wnd);
    for I := 0 to FCtls.Count - 1 do
      with TVclCtl(FCtls[I]) do
      begin
        Wnd := 0;
        if Font <> 0 then DeleteObject(Font);
        Font := 0;
      end;
  end;
  { the application window stays for the program's life, as TApplication's }
  FAppWnd := 0;
  if CurForm = Self then CurForm := nil;
end;

{$ELSE}

function TVclForm.ShowModal: Integer;
begin
  { no Win32 here: the form is drawn by Render into a TGWindow by the
    caller (see GVclWindow) }
  Result := -1;
end;

procedure TVclForm.Hide;
begin
end;

{$ENDIF}


function VclAppWindow: PtrUInt;
begin
{$IFDEF MSWINDOWS}
  Result := PtrUInt(AppWnd);
{$ELSE}
  Result := 0;
{$ENDIF}
end;

end.
