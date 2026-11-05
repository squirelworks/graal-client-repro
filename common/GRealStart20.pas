{ GRealStart20: the launcher of the 2.0x clients (2.0 to 2.05 rev 2), laid
  out from the build's own forms and drawn with its own art. Each build
  compiles in its original exe's resources (src/Res<Program>.pas, made by
  scripts/res20x/make_res20x.py) and hands them in through a TResLookup.

  As in the real clients, side by side under Wine:

  - The start window is the form TConnectFrame itself: a 476 x 330 dialog
    with only the close button (bsDialog), titled with the form's caption
    ("Graal 2001"), over the art SCREENIMG1. Its labels, the language box
    and the nickname come from the form. The Training, Options and Start
    buttons are painted on it (left half of BUTTON1 up, right half down,
    bold captions with the accelerator letter in red) at (336, 240),
    (200, 280) and (336, 280), measured on the real 2.05 rev 2 and 2.0.
  - A language file next to the program (language<Name>.txt, as 2.05 rev 2
    ships languageEnglish.txt) renames the start window's controls by
    their component names, StartScreen-<Name>=..., as the real clients do;
    with 2.05 rev 2's English file that turns the welcome text into
    "Account:", as it does on the real one.
  - Start hides the start window and opens the server list, the form
    TServerListFrame (577 x 416, "Graalonline.com Server List", over
    SCREENIMG2), with the "Getting server list ..." box (the form
    TShortMessage, 274 x 93) over it while the listserver answers. The
    account and password are typed on the list, under the servers, and
    Connect logs in with them. 'P ' servers carry the gold icon of the
    form's image list and lose the prefix; other prefixes stay in the
    name, as on the real 2.05 rev 2.

  Every control is placed from its form: left, top, width, height,
  colours (clGreen boxes, clLime text), captions, alignment and word wrap;
  picture buttons (TPaintButton) from their own Glyph.Data. Text uses
  common/GUiFont (Liberation Sans) for the forms' MS Sans Serif. }
unit GRealStart20;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow, GStartScreen, GDfm;

type
  TResLookup = function(const Name: string; out Data: string): Boolean;

  TRealStart20 = class
  public
    Back1, Back2, Button: TGSurface;
    Icons: array of TGSurface;
    Connect, List, Short: TDfmNode;
    MainCaption: string;
    Lang: TStringList;
    Languages: TStringList;
    LanguageName: string;
    constructor Create;
    destructor Destroy; override;
    { The art and forms through Res; the language files from Dir.
      False when the art or a form is missing. }
    function Load(Res: TResLookup; const Dir: string): Boolean;
    { The language file's text for Key, or Default. }
    function Text(const Key, Default: string): string;
  end;

{ Runs the start window and the server list in Win until the player picks
  Training or a server. False: closed, or Esc on the start window. }
function RunRealStart20(Win: TGWindow; Art: TRealStart20; Fetch: TListFetch;
  const Info: TStartInfo; const ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;

{ The server list's icon for a listed name (0 gold, 1 under construction,
  -1 none) and the name as the list shows it. }
function ListIcon(const Name: string): Integer;
function ListName(const Name: string): string;

{ The nickname and the last account the 2.0x clients keep
  (HKCU\Software\Graal\Client: nickname, accountname, the last used
  first); nothing outside Windows. The real clients fill the start window's
  nickname from there. }
procedure ReadSavedLogin(var Nickname, Account: string);
procedure SaveLogin(const Nickname, Account: string);

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, GUiFont;

const
  ColSelect = $FF3399FF;
  ColWhite = $FFFFFFFF;
  ColRed = $FFFF0000;
  ColBlack = $FF000000;

function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

{ ---- art ---- }

{ A picture (BMP or JPEG) from bytes; its bottom-left pixel's colour is
  made see-through when Keyed, as Delphi's glyphs and image lists do. }
function Picture(const Data, Ext: string; Keyed: Boolean): TGSurface;
var
  I: Integer;
  Key: Cardinal;
begin
  Result := TGSurface.Create(0, 0);
  if not LoadImageData(Data, 'x' + Ext, Result, False) or (Result.Width = 0) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  SetLength(Result.Indices, 0);
  SetLength(Result.Palette, 0);
  if Keyed then
  begin
    Key := Result.Pixels[(Result.Height - 1) * Result.Width];
    for I := 0 to High(Result.Pixels) do
      if Result.Pixels[I] = Key then Result.Pixels[I] := 0;
  end;
end;

{ Glyph.Data: a 32-bit size, then a BMP. }
function Glyph(N: TDfmNode): TGSurface;
var
  D: string;
begin
  Result := nil;
  if N = nil then Exit;
  D := N.Str('Glyph.Data');
  if Length(D) < 8 then Exit;
  Result := Picture(Copy(D, 5, MaxInt), '.bmp', True);
end;

constructor TRealStart20.Create;
begin
  inherited Create;
  Lang := TStringList.Create;
  Languages := TStringList.Create;
end;

destructor TRealStart20.Destroy;
var
  I: Integer;
begin
  Back1.Free;
  Back2.Free;
  Button.Free;
  for I := 0 to High(Icons) do Icons[I].Free;
  Connect.Free;
  List.Free;
  Short.Free;
  Lang.Free;
  Languages.Free;
  inherited Destroy;
end;

procedure LoadIcons(Art: TRealStart20);
var
  N: TDfmNode;
  D: string;
  P, Cx, Cy, Count, I, X, Y, PerRow: Integer;
  Strip: TGSurface;
begin
  if Art.List = nil then Exit;
  N := Art.List.Find('ImageList1');
  if N = nil then Exit;
  D := N.Str('Bitmap');
  Cx := N.Int('Width', 16);
  Cy := N.Int('Height', 16);
  { Delphi 4 wrote either its own layout (size, count, a BMP of the images
    side by side) or ImageList_Write's ("IL" header, a BMP four images a
    row, then the mask) }
  P := Pos('BM', D);
  if P = 0 then Exit;
  if Copy(D, 1, 2) = 'IL' then
  begin
    Count := Ord(D[5]) or (Ord(D[6]) shl 8);
    PerRow := 4;
  end
  else
  begin
    Count := Ord(D[5]) or (Ord(D[6]) shl 8);
    PerRow := 1000;
  end;
  Strip := Picture(Copy(D, P, MaxInt), '.bmp', False);
  if Strip = nil then Exit;
  try
    SetLength(Art.Icons, Count);
    for I := 0 to Count - 1 do
    begin
      Art.Icons[I] := TGSurface.Create(Cx, Cy);
      for Y := 0 to Cy - 1 do
        for X := 0 to Cx - 1 do
          Art.Icons[I].Pixels[Y * Cx + X] :=
            Strip.GetPixel((I mod PerRow) * Cx + X, (I div PerRow) * Cy + Y);
      { black is the images' background }
      for X := 0 to High(Art.Icons[I].Pixels) do
        if Art.Icons[I].Pixels[X] and $FFFFFF = 0 then Art.Icons[I].Pixels[X] := 0;
    end;
  finally
    Strip.Free;
  end;
end;

function TRealStart20.Load(Res: TResLookup; const Dir: string): Boolean;

  function Pic(const Name, Ext: string; Keyed: Boolean): TGSurface;
  var
    D: string;
  begin
    Result := nil;
    if Res(Name, D) then Result := Picture(D, Ext, Keyed);
  end;

  function Form(const Name: string): TDfmNode;
  var
    D: string;
  begin
    Result := nil;
    if Res(Name, D) then Result := ParseDfm(D);
  end;

  procedure FindLanguages(const Path: string);
  var
    SR: TSearchRec;
    L: string;
  begin
    if FindFirst(Path + 'language*.txt', faAnyFile, SR) = 0 then
    begin
      repeat
        L := Copy(SR.Name, 9, Length(SR.Name) - 12);
        if (L <> '') and (Languages.IndexOf(L) < 0) then
          Languages.AddObject(L, TObject(PtrInt(0)));
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  end;

var
  Adv: TDfmNode;
  F: string;
begin
  Back1 := Pic('SCREENIMG1', '.jpg', False);
  Back2 := Pic('SCREENIMG2', '.jpg', False);
  Button := Pic('BUTTON1', '.bmp', True);
  Connect := Form('TCONNECTFRAME');
  List := Form('TSERVERLISTFRAME');
  Short := Form('TSHORTMESSAGE');
  Adv := Form('TADVENTURE');
  MainCaption := 'Graal';
  if Adv <> nil then MainCaption := Adv.Str('Caption', 'Graal');
  Adv.Free;
  LoadIcons(Self);
  { the language files the install has, as the language box lists them;
    the configured one (graalconfig.txt language=) first picked }
  Languages.Sorted := True;
  FindLanguages(Dir);
  FindLanguages(Dir + 'languages' + PathDelim);
  if Languages.Count = 0 then Languages.Add('English');
  LanguageName := 'English';
  F := Dir + 'graalconfig.txt';
  if FileExists(F) then
  begin
    Lang.LoadFromFile(F);
    if Lang.Values['language'] <> '' then LanguageName := Lang.Values['language'];
    Lang.Clear;
  end;
  if Languages.IndexOf(LanguageName) < 0 then LanguageName := Languages[0];
  F := Dir + 'language' + LanguageName + '.txt';
  if not FileExists(F) then F := Dir + 'languages' + PathDelim + 'language' + LanguageName + '.txt';
  if FileExists(F) then
    try
      Lang.LoadFromFile(F);
    except
      Lang.Clear;
    end;
  if Lang.Values['MainWindow'] <> '' then MainCaption := Lang.Values['MainWindow'];
  Result := (Back1 <> nil) and (Back2 <> nil) and (Button <> nil) and (Connect <> nil) and
    (List <> nil);
end;

function TRealStart20.Text(const Key, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  I := Lang.IndexOfName(Key);
  if (I >= 0) and (Lang.ValueFromIndex[I] <> '') then Result := Lang.ValueFromIndex[I];
end;

function ListIcon(const Name: string): Integer;
begin
  Result := -1;
  if (Length(Name) > 2) and (Name[2] = ' ') then
    case Name[1] of
      'P': Result := 0;
      'U': Result := 1;
    end;
end;

function ListName(const Name: string): string;
begin
  if ListIcon(Name) >= 0 then Result := Copy(Name, 3, MaxInt) else Result := Name;
end;

{ ---- saved login ---- }

{$IFDEF MSWINDOWS}
const
  LoginKey = 'Software\Graal\Client';

function RegString(K: HKEY; const Name: string; var Value: string): Boolean;
var
  T, N: DWORD;
  Buf: array[0..1023] of Char;
begin
  N := SizeOf(Buf) - 1;
  FillChar(Buf, SizeOf(Buf), 0);
  Result := (RegQueryValueExA(K, PChar(Name), nil, @T, @Buf[0], @N) = ERROR_SUCCESS) and
    (T = REG_SZ);
  if Result then Value := PChar(@Buf[0]);
end;

{ accountname is a comma list, the last used first }
procedure ReadSavedLogin(var Nickname, Account: string);
var
  K: HKEY;
  L: string;
begin
  if RegOpenKeyExA(HKEY_CURRENT_USER, LoginKey, 0, KEY_READ, K) <> ERROR_SUCCESS then Exit;
  RegString(K, 'nickname', Nickname);
  L := '';
  if RegString(K, 'accountname', L) and (L <> '') then
  begin
    if Pos(',', L) > 0 then Account := Copy(L, 1, Pos(',', L) - 1) else Account := L;
  end;
  RegCloseKey(K);
end;

procedure SaveLogin(const Nickname, Account: string);
var
  K: HKEY;
  D: DWORD;
  Old, List: string;
  Items: TStringList;
  I: Integer;
begin
  { the account moves to the front of the list }
  Old := '';
  if RegOpenKeyExA(HKEY_CURRENT_USER, LoginKey, 0, KEY_READ, K) = ERROR_SUCCESS then
  begin
    RegString(K, 'accountname', Old);
    RegCloseKey(K);
  end;
  List := Account;
  Items := TStringList.Create;
  try
    Items.StrictDelimiter := True;
    Items.CommaText := Old;
    for I := 0 to Items.Count - 1 do
      if (Items[I] <> '') and (Items[I] <> Account) then List := List + ',' + Items[I];
  finally
    Items.Free;
  end;
  if RegCreateKeyExA(HKEY_CURRENT_USER, LoginKey, 0, nil, 0, KEY_WRITE, nil, K, @D) <>
    ERROR_SUCCESS then Exit;
  RegSetValueExA(K, 'nickname', 0, REG_SZ, PChar(Nickname), Length(Nickname) + 1);
  RegSetValueExA(K, 'accountname', 0, REG_SZ, PChar(List), Length(List) + 1);
  RegCloseKey(K);
end;
{$ELSE}
procedure ReadSavedLogin(var Nickname, Account: string);
begin
end;

procedure SaveLogin(const Nickname, Account: string);
begin
end;
{$ENDIF}

{ ---- drawing the forms' controls ---- }

{ A caption's accelerator: '&' marks the next letter; '&&' is a '&'. }
procedure SplitAccel(const Caption: string; out Plain: string; out Accel: Integer);
var
  I: Integer;
begin
  Plain := '';
  Accel := 0;
  I := 1;
  while I <= Length(Caption) do
  begin
    if (Caption[I] = '&') and (I < Length(Caption)) then
    begin
      Inc(I);
      if Caption[I] <> '&' then Accel := Length(Plain) + 1;
    end;
    Plain := Plain + Caption[I];
    Inc(I);
  end;
end;

{ The sunken edge of an edit box, as Wine draws it beside the real client }
procedure Sunken(S: TGSurface; X, Y, W, H: Integer);
begin
  S.FillRect(X, Y, W, 1, $FFA0A0A0);
  S.FillRect(X, Y, 1, H, $FFA0A0A0);
  S.FillRect(X + 1, Y + 1, W - 2, 1, $FF696969);
  S.FillRect(X + 1, Y + 1, 1, H - 2, $FF696969);
  S.FillRect(X, Y + H - 1, W, 1, ColWhite);
  S.FillRect(X + W - 1, Y, 1, H, ColWhite);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, $FFE3E3E3);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, $FFE3E3E3);
end;

function Bold(N: TDfmNode): TUiFace;
begin
  if Pos('fsBold', N.Str('Font.Style')) > 0 then Result := ufBold else Result := ufRegular;
end;

{ Text broken into lines to W pixels }
procedure Wrapped(S: TGSurface; X, Y, W, MaxH: Integer; const Text: string; Color: Cardinal;
  Face: TUiFace; Align: Integer);
var
  Lines, Words: TStringList;
  I, J, Y0: Integer;
  Line, Cand: string;

  procedure Put(const L: string);
  var
    LX: Integer;
  begin
    if (MaxH > 0) and (Y + UiLineH > Y0 + MaxH + 2) then Exit;
    case Align of
      1: LX := X + (W - UiTextWidth(L, Face)) div 2;
      2: LX := X + W - UiTextWidth(L, Face);
    else
      LX := X;
    end;
    UiDrawText(S, LX, Y, L, Color, Face);
    Inc(Y, UiLineH);
  end;

begin
  Y0 := Y;
  Lines := TStringList.Create;
  Words := TStringList.Create;
  try
    Lines.Text := StringReplace(Text, #13, '', [rfReplaceAll]);
    for I := 0 to Lines.Count - 1 do
    begin
      Words.Clear;
      ExtractStrings([' '], [], PChar(Lines[I]), Words);
      Line := '';
      for J := 0 to Words.Count - 1 do
      begin
        if Line = '' then Cand := Words[J] else Cand := Line + ' ' + Words[J];
        if (UiTextWidth(Cand, Face) > W) and (Line <> '') then
        begin
          Put(Line);
          Line := Words[J];
        end
        else
          Line := Cand;
      end;
      Put(Line);
    end;
  finally
    Words.Free;
    Lines.Free;
  end;
end;

{ Cuts T to W pixels with "..." as a list view does }
function Ellipsis(const T: string; W: Integer; Face: TUiFace): string;
begin
  Result := T;
  if UiTextWidth(Result, Face) <= W then Exit;
  while (Result <> '') and (UiTextWidth(Result + '...', Face) > W) do
    Delete(Result, Length(Result), 1);
  Result := Result + '...';
end;

procedure DrawLabel(S: TGSurface; N: TDfmNode; const Caption: string);
var
  Plain: string;
  A, Align: Integer;
  Col: Cardinal;
begin
  SplitAccel(Caption, Plain, A);
  Col := DfmColor(N.Str('Font.Color'), ColBlack);
  if N.Str('Alignment') = 'taCenter' then Align := 1
  else if N.Str('Alignment') = 'taRightJustify' then Align := 2
  else Align := 0;
  if N.Bool('WordWrap') then
    Wrapped(S, N.Int('Left'), N.Int('Top'), N.Int('Width'), N.Int('Height'), Plain, Col, Bold(N), Align)
  else if Align = 1 then
    UiDrawText(S, N.Int('Left') + (N.Int('Width') - UiTextWidth(Plain, Bold(N))) div 2,
      N.Int('Top'), Plain, Col, Bold(N))
  else
    UiDrawText(S, N.Int('Left'), N.Int('Top'), Plain, Col, Bold(N));
end;

{ an edit, combo or rich edit box of the form }
procedure DrawBox(S: TGSurface; N: TDfmNode; const Text: string; Focused: Boolean);
var
  X, Y, W, H, I, AX, AY, Right, TW: Integer;
  T: string;
  Fill, Col: Cardinal;
  Combo, Rich: Boolean;
begin
  X := N.Int('Left');
  Y := N.Int('Top');
  W := N.Int('Width');
  H := N.Int('Height');
  Fill := DfmColor(N.Str('Color'), ColWhite);
  Col := DfmColor(N.Str('Font.Color'), ColBlack);
  Combo := N.ClassName_ = 'TComboBox';
  Rich := (N.ClassName_ = 'TRichEdit') or (N.ClassName_ = 'TMemo');
  S.FillRect(X + 2, Y + 2, W - 4, H - 4, Fill);
  Sunken(S, X, Y, W, H);
  Right := X + W - 2;
  if Combo then
  begin
    { the drop-down button, 17 wide inside the edge, an arrow 7 wide }
    AX := X + W - 2 - 17;
    S.FillRect(AX, Y + 2, 17, H - 4, $FFF0F0F0);
    S.FillRect(AX, Y + 2, 17, 1, ColWhite);
    S.FillRect(AX, Y + 2, 1, H - 4, ColWhite);
    S.FillRect(AX + 15, Y + 2, 1, H - 4, $FFA0A0A0);
    S.FillRect(AX + 16, Y + 2, 1, H - 4, $FF696969);
    S.FillRect(AX, Y + H - 4, 17, 1, $FFA0A0A0);
    S.FillRect(AX, Y + H - 3, 17, 1, $FF696969);
    AY := Y + (H - 4) div 2;
    for I := 0 to 3 do S.FillRect(AX + 5 + I, AY + I, 7 - 2 * I, 1, ColBlack);
    Right := AX;
  end;
  if Rich then
  begin
    Wrapped(S, X + 3, Y + 2, W - 6, H - 4, Text, Col, Bold(N), 0);
    Exit;
  end;
  if N.Str('PasswordChar') <> '' then T := StringOfChar('*', Length(Text)) else T := Text;
  while (T <> '') and (UiTextWidth(T, Bold(N)) > Right - X - 6) do Delete(T, 1, 1);
  TW := UiTextWidth(T, Bold(N));
  if Focused and Combo and (N.Str('Style') = 'csDropDownList') then
  begin
    { a focused drop-down list shows its item picked }
    S.FillRect(X + 3, Y + 3, Right - X - 4, H - 6, ColSelect);
    UiDrawText(S, X + 4, Y + (H - UiLineH) div 2, T, ColWhite, Bold(N));
  end
  else
    UiDrawText(S, X + 4, Y + (H - UiLineH) div 2, T, Col, Bold(N));
  if Focused and not (Combo and (N.Str('Style') = 'csDropDownList')) and
    ((NowMs div 500) mod 2 = 0) then
    S.FillRect(X + 4 + TW, Y + 4, 1, H - 8, Col);
end;

procedure DrawPanel(S: TGSurface; N: TDfmNode);
var
  Plain: string;
  A, X: Integer;
begin
  S.FillRect(N.Int('Left'), N.Int('Top'), N.Int('Width'), N.Int('Height'),
    DfmColor(N.Str('Color'), $FFC0C0C0));
  SplitAccel(N.Str('Caption'), Plain, A);
  if N.Str('Alignment') = 'taLeftJustify' then X := N.Int('Left')
  else X := N.Int('Left') + (N.Int('Width') - UiTextWidth(Plain, Bold(N))) div 2;
  UiDrawText(S, X, N.Int('Top') + (N.Int('Height') - UiLineH) div 2, Plain,
    DfmColor(N.Str('Font.Color'), ColBlack), Bold(N));
end;

{ A picture button: a glyph (or BUTTON1) with two states side by side, the
  caption bold and centred, its accelerator letter red }
procedure PicButton(S, Img: TGSurface; X, Y: Integer; const Caption: string; Down: Boolean);
var
  W, D, TX, TY, A: Integer;
  Plain: string;
begin
  if Img = nil then Exit;
  W := Img.Width div 2;
  if Down then D := 1 else D := 0;
  S.Blit(Img, D * W, 0, W, Img.Height, X, Y);
  SplitAccel(Caption, Plain, A);
  if Plain = '' then Exit;
  TX := X + (W - UiTextWidth(Plain, ufBold)) div 2 + D;
  TY := Y + (Img.Height - UiLineH) div 2 + D;
  if A > 0 then
  begin
    UiDrawText(S, TX, TY, Copy(Plain, 1, A - 1), ColBlack, ufBold);
    Inc(TX, UiTextWidth(Copy(Plain, 1, A - 1), ufBold));
    UiDrawText(S, TX, TY, Plain[A], ColRed, ufBold);
    Inc(TX, UiTextWidth(Plain[A], ufBold));
    UiDrawText(S, TX, TY, Copy(Plain, A + 1, MaxInt), ColBlack, ufBold);
  end
  else
    UiDrawText(S, TX, TY, Plain, ColBlack, ufBold);
end;

function Inside(N: TDfmNode; X, Y: Integer): Boolean;
begin
  Result := (N <> nil) and (X >= N.Int('Left')) and (Y >= N.Int('Top')) and
    (X < N.Int('Left') + N.Int('Width')) and (Y < N.Int('Top') + N.Int('Height'));
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

{ ---- the windows ---- }

function RunRealStart20(Win: TGWindow; Art: TRealStart20; Fetch: TListFetch;
  const Info: TStartInfo; const ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;
type
  TPage = (pgStart, pgFetch, pgList);
const
  BtnTraining: array[0..1] of Integer = (336, 240);
  BtnOptions: array[0..1] of Integer = (200, 280);
  BtnStart: array[0..1] of Integer = (336, 280);
  RowH = 17;
var
  S: TGSurface;
  Page: TPage;
  Focus, Sel, I, CX, CY, Row, PressBtn, LX, LY, LW, LH, Icon, W1, W2: Integer;
  Clicked: Boolean;
  Chars, Note, T, Title1, Title2: string;
  Srv: TListServer;
  PressUntil, FetchStart: Int64;
  N, LV, Rich, AccBox, PassBox, ConnectBtn: TDfmNode;
  Glyphs: TList;
  Col: Cardinal;
  ExtraSent: Boolean;

  function Pressed(Id: Integer): Boolean;
  begin
    Result := (PressBtn = Id) and (NowMs < PressUntil);
  end;

  procedure Press(Id: Integer);
  begin
    PressBtn := Id;
    PressUntil := NowMs + 150;
  end;

  function InBtn(const P: array of Integer; X, Y: Integer): Boolean;
  begin
    Result := (X >= P[0]) and (Y >= P[1]) and (X < P[0] + Art.Button.Width div 2) and
      (Y < P[1] + Art.Button.Height);
  end;

  function Shape(Form: TDfmNode; const Title: string): Boolean;
  begin
    Win.Reshape(Title, Form.Int('ClientWidth', 476), Form.Int('ClientHeight', 330), True);
    S.SetSize(Form.Int('ClientWidth', 476), Form.Int('ClientHeight', 330));
    Result := True;
  end;

  function GlyphOf(Node: TDfmNode): TGSurface;
  var
    K: Integer;
  begin
    K := Art.List.Children.IndexOf(Node);
    Result := TGSurface(Glyphs[K]);
  end;

  procedure ShortBox(const Msg: string);
  var
    BW, BH, BX, BY, CapH: Integer;
  begin
    { TShortMessage: 274 x 93, green, its text at 20, 20, under a dialog
      caption of its own ("Graal Server List") }
    BW := 274;
    BH := 93;
    if Art.Short <> nil then
    begin
      BW := Art.Short.Int('ClientWidth', 274);
      BH := Art.Short.Int('ClientHeight', 93);
    end;
    CapH := 18;
    BX := (S.Width - BW) div 2;
    BY := (S.Height - BH - CapH) div 2;
    S.FillRect(BX - 3, BY - 3, BW + 6, BH + CapH + 6, $FFC0C0C0);
    S.FillRect(BX - 3, BY - 3, BW + 6, 1, ColWhite);
    S.FillRect(BX - 3, BY - 3, 1, BH + CapH + 6, ColWhite);
    S.FillRect(BX + BW + 2, BY - 3, 1, BH + CapH + 6, ColBlack);
    S.FillRect(BX - 3, BY + BH + CapH + 2, BW + 6, 1, ColBlack);
    S.FillRect(BX, BY, BW, CapH, $FF000080);
    UiDrawText(S, BX + 3, BY + 1, 'Graal Server List', ColWhite, ufBold);
    S.FillRect(BX, BY + CapH, BW, BH, $FF008000);
    Wrapped(S, BX + 20, BY + CapH + 20, BW - 40, BH - 40, Msg, $FF00FF00, ufRegular, 0);
  end;

begin
  Result := False;
  R.Choice := scQuit;
  S := TGSurface.Create(1, 1);
  Glyphs := TList.Create;
  try
    for I := 0 to Art.List.ChildCount - 1 do Glyphs.Add(Glyph(Art.List.Child(I)));
    Title1 := Art.Connect.Str('Caption', 'Graal 2001');
    Title2 := Art.List.Str('Caption', 'Graalonline.com Server List');
    Shape(Art.Connect, Title1);
    Page := pgStart;
    Note := Message;
    Focus := 0; { the language box: the form's first control }
    Sel := -1;
    PressBtn := 0;
    PressUntil := 0;
    FetchStart := 0;
    ExtraSent := False;
    LV := Art.List.Find('ListView1');
    Rich := Art.List.Find('RichEdit1');
    AccBox := Art.List.Find('accountbox');
    PassBox := Art.List.Find('passedit');
    ConnectBtn := Art.List.Find('Button1');
    while True do
    begin
      Win.Pump;
      if Win.Closed or (Assigned(Info.StopRequested) and Info.StopRequested()) then Exit;
      Clicked := Win.TakeClick(CX, CY);
      Chars := Win.TakeChars;
      Fetch.Poll;
      case Page of
        pgStart:
          begin
            if Pos(#27, Chars) > 0 then Exit;
            if Pos(#9, Chars) > 0 then
            begin
              Focus := 1 - Focus;
              Chars := StringReplace(Chars, #9, '', [rfReplaceAll]);
            end;
            if Focus = 1 then TypeInto(R.Nickname, Chars, 20);
            if Clicked then
            begin
              if Inside(Art.Connect.Find('languagebox'), CX, CY) then
              begin
                Focus := 0;
                I := Art.Languages.IndexOf(Art.LanguageName);
                Art.LanguageName := Art.Languages[(I + 1) mod Art.Languages.Count];
              end;
              if Inside(Art.Connect.Find('Edit3'), CX, CY) then Focus := 1;
              if InBtn(BtnTraining, CX, CY) then
              begin
                SaveLogin(R.Nickname, R.Account);
                R.Choice := scTraining;
                Result := True;
                Exit;
              end;
              if InBtn(BtnOptions, CX, CY) then
              begin
                Press(2);
                Note := 'The options window is not built yet.';
              end;
            end;
            if (Clicked and InBtn(BtnStart, CX, CY)) or (Pos(#13, Chars) > 0) then
            begin
              Press(3);
              Note := '';
              { the list is asked for before any account, as 2.0x does }
              Fetch.Start(ListHost, ListPort, '', '');
              FetchStart := NowMs;
              ExtraSent := False;
              Page := pgFetch;
              Shape(Art.List, Title2);
              Continue;
            end;
            { drawing: the art, then the form's controls }
            S.Fill($FF004000);
            S.Blit(Art.Back1, 0, 0, Art.Back1.Width, Art.Back1.Height, 0, 0);
            for I := 0 to Art.Connect.ChildCount - 1 do
            begin
              N := Art.Connect.Child(I);
              if not N.Bool('Visible', True) then Continue;
              T := Art.Text('StartScreen-' + N.Name, N.Str('Caption'));
              if N.ClassName_ = 'TLabel' then DrawLabel(S, N, T)
              else if SameText(N.Name, 'languagebox') then DrawBox(S, N, Art.LanguageName, Focus = 0)
              else if N.ClassName_ = 'TEdit' then DrawBox(S, N, R.Nickname, Focus = 1)
              else if N.ClassName_ = 'TComboBox' then DrawBox(S, N, '', False);
            end;
            PicButton(S, Art.Button, BtnTraining[0], BtnTraining[1],
              Art.Text('StartScreen-Button2', '&Training'), Pressed(1));
            PicButton(S, Art.Button, BtnOptions[0], BtnOptions[1],
              Art.Text('StartScreen-Button3', '&Options'), Pressed(2));
            PicButton(S, Art.Button, BtnStart[0], BtnStart[1],
              Art.Text('StartScreen-Button1', '&Start'), Pressed(3));
            if Note <> '' then
              Wrapped(S, 24, 300, 428, 32, Note, $FF00FF00, ufRegular, 1);
          end;
        pgFetch, pgList:
          begin
            if Page = pgFetch then
            begin
              Clicked := False;
              { a listserver that waits for an account (the public legacy
                port) gets an empty one after 2.5 s }
              if not Fetch.Done and not Fetch.Failed and not ExtraSent and
                (NowMs - FetchStart > 2500) then
              begin
                ExtraSent := True;
                { the form's own defaults when nothing was typed }
                if R.Account = '' then
                  Fetch.Start(ListHost, ListPort, 'guest', 'guest')
                else
                  Fetch.Start(ListHost, ListPort, R.Account, R.Password);
              end;
              if Fetch.Done then
              begin
                Page := pgList;
                Sel := -1;
                if Length(Fetch.Servers) > 0 then Sel := 0;
              end
              else if Fetch.Failed and (Chars <> '') then
              begin
                Note := Fetch.Status;
                Page := pgStart;
                Shape(Art.Connect, Title1);
                Continue;
              end;
              Chars := '';
            end;
            if Pos(#27, Chars) > 0 then
            begin
              Page := pgStart;
              Shape(Art.Connect, Title1);
              Continue;
            end;
            if Pos(#9, Chars) > 0 then
            begin
              if Focus = 2 then Focus := 3 else Focus := 2;
              Chars := StringReplace(Chars, #9, '', [rfReplaceAll]);
            end;
            if Focus = 2 then TypeInto(R.Account, Chars, 30);
            if Focus = 3 then TypeInto(R.Password, Chars, 30);
            if Clicked then
            begin
              if Inside(AccBox, CX, CY) then Focus := 2;
              if Inside(PassBox, CX, CY) then Focus := 3;
              if Inside(LV, CX, CY) then
              begin
                Row := (CY - LV.Int('Top') - 2) div RowH;
                if (Row >= 0) and (Row <= High(Fetch.Servers)) then Sel := Row;
              end;
              for I := 0 to Art.List.ChildCount - 1 do
              begin
                N := Art.List.Child(I);
                if (N.ClassName_ = 'TPaintButton') and (N <> ConnectBtn) and Inside(N, CX, CY) then
                  Press(10 + I);
              end;
            end;
            if (Page = pgList) and (((Clicked and Inside(ConnectBtn, CX, CY)) or (Pos(#13, Chars) > 0)) and
              (Sel >= 0) and (Sel <= High(Fetch.Servers))) then
            begin
              Srv := Fetch.Servers[Sel];
              SaveLogin(R.Nickname, R.Account);
              R.Choice := scOnline;
              R.Host := Srv.Host;
              R.Port := Srv.Port;
              R.ServerName := ListName(Srv.Name);
              Result := True;
              Exit;
            end;
            FillChar(Srv, SizeOf(Srv), 0);
            if (Sel >= 0) and (Sel <= High(Fetch.Servers)) then Srv := Fetch.Servers[Sel];
            { drawing }
            S.Fill($FF004000);
            S.Blit(Art.Back2, 0, 0, Art.Back2.Width, Art.Back2.Height, 0, 0);
            for I := 0 to Art.List.ChildCount - 1 do
            begin
              N := Art.List.Child(I);
              if not N.Bool('Visible', True) then Continue;
              if N.ClassName_ = 'TLabel' then
              begin
                T := N.Str('Caption');
                DrawLabel(S, N, T);
              end
              else if N.ClassName_ = 'TPanel' then DrawPanel(S, N)
              else if N.ClassName_ = 'TPaintButton' then
                PicButton(S, GlyphOf(N), N.Int('Left'), N.Int('Top'), N.Str('Caption'),
                  Pressed(10 + I))
              else if N = AccBox then DrawBox(S, N, R.Account, Focus = 2)
              else if N = PassBox then DrawBox(S, N, R.Password, Focus = 3)
              else if SameText(N.Name, 'Edit1') then DrawBox(S, N, ListName(Srv.Name), False)
              else if SameText(N.Name, 'Edit2') then DrawBox(S, N, Srv.Language, False)
              else if SameText(N.Name, 'Edit3') then DrawBox(S, N, Srv.Version, False)
              else if SameText(N.Name, 'Edit4') then DrawBox(S, N, Srv.Url, False)
              else if N = Rich then DrawBox(S, N, Srv.Description, False)
              else if N = LV then
              begin
                LX := N.Int('Left');
                LY := N.Int('Top');
                LW := N.Int('Width');
                LH := N.Int('Height');
                S.FillRect(LX, LY, LW, LH, DfmColor(N.Str('Color'), ColWhite));
                Sunken(S, LX, LY, LW, LH);
                W1 := N.Int('Columns[0].Width', 108);
                W2 := N.Int('Columns[1].Width', 55);
                Col := DfmColor(N.Str('Font.Color'), ColBlack);
                for Row := 0 to High(Fetch.Servers) do
                begin
                  CY := LY + 2 + Row * RowH;
                  if CY + RowH > LY + LH - 2 then Break;
                  Icon := ListIcon(Fetch.Servers[Row].Name);
                  if (Icon >= 0) and (Icon <= High(Art.Icons)) then
                    S.Blit(Art.Icons[Icon], 0, 0, Art.Icons[Icon].Width, Art.Icons[Icon].Height,
                      LX + 4, CY);
                  { the columns run from the list's inner edge: the
                    name (its icon in the first 21 pixels) to W1, the
                    players right-aligned 6 pixels inside W1 + W2 }
                  T := Ellipsis(ListName(Fetch.Servers[Row].Name), W1 - 29, ufRegular);
                  if Row = Sel then
                  begin
                    S.FillRect(LX + 21, CY, W1 + W2 - 19, RowH, ColSelect);
                    Col := ColWhite;
                  end
                  else
                    Col := DfmColor(N.Str('Font.Color'), ColBlack);
                  UiDrawText(S, LX + 25, CY, T, Col, ufRegular);
                  UiDrawText(S, LX + 2 + W1 + W2 - 6 - UiTextWidth(Fetch.Servers[Row].Players,
                    ufRegular), CY, Fetch.Servers[Row].Players, Col, ufRegular);
                end;
              end;
            end;
            { 2.02 on build their description box at run time where 2.0's
              form has its RichEdit1 }
            if Rich = nil then
            begin
              S.FillRect(346, 172, 205, 65, $FF008000);
              Sunken(S, 344, 170, 209, 69);
              Wrapped(S, 347, 172, 203, 65, Srv.Description, $FF00FF00, ufRegular, 0);
            end;
            if Page = pgFetch then
            begin
              if Fetch.Failed then ShortBox(Fetch.Status)
              else ShortBox('Getting server list ...');
            end;
          end;
      end;
      Win.Present(S);
      Sleep(20);
    end;
  finally
    for I := 0 to Glyphs.Count - 1 do TGSurface(Glyphs[I]).Free;
    Glyphs.Free;
    S.Free;
  end;
end;

end.
