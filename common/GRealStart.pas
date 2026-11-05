{ GRealStart: a client's own start window and server list, laid out from
  that client's own forms and drawn with its own art.

  The 2.x clients open on two Delphi dialogs before the game: the start
  window (class TConnectFrame) and the server list (TServerListFrame),
  each its own window with a dialog frame (bsDialog: a caption and only the
  close button), centred on the screen and sized to its art. The program
  carries both forms in its resources (RCDATA TCONNECTFRAME,
  TSERVERLISTFRAME) with every label, field and button in place, and the
  art beside them (RCDATA SCREENIMG1/2, BUTTON1..4, the buttons' glyphs
  inside the forms).

  A build pulls those resources out of the real exe with
  scripts/res/extract_res.py into its src/res/ and links them in
  (src/<Program>Res.res), so the rebuilt program carries its own copy and
  needs no original beside it. This unit reads the forms (GDfm) and draws
  them the way the VCL did: the background picture, then each container's
  graphic controls (labels, picture buttons), then its windowed controls
  (edits, combo boxes, list views, panels, check boxes) over them. The
  words come from the install's languages/language<name>.txt when there is
  one (keys "<Form>-<Component>", as the clients read them), else from the
  forms. What the clients add at run time (the start window's Training,
  Options and Start buttons in 2.1 and NewWorld, where no form holds them)
  comes from the build's TRealStartSpec, placed from screenshots of the
  real client under Wine.

  Everything here is the same for every build that uses it; what differs
  (which pictures, where the run-time buttons go, whether the account is
  asked on the start window or on the list) is in the build's spec. }
unit GRealStart;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow, GStartScreen, GDfm;

type
  { A control the client creates at run time, as the form would hold it:
    "Form|Class|Name|Left|Top|Width|Height|Caption|Glyph resource|Font.Color" }
  TRealStartSpec = record
    { the real program's file names in an install (';' between), a
      fallback for resources this program was built without }
    ExeNames: string;
    StartBack, ListBack: string;
    { the start window's and the list's titles when the language file has
      none (2.17.1 sets its own, "Graal2002") }
    StartTitle, ListTitle: string;
    { the language file is not read for the start window's title }
    FixedStartTitle: Boolean;
    { NewMain and NewWorld beta 1 ask the account on the list }
    AccountOnList: Boolean;
    { lines of run-time controls, #10 between them }
    Runtime: string;
    { the list's tabs (2.17.1: "Graal Gold" and "Classic"), lines of
      "prefix|caption": servers whose name starts with "prefix " go on that
      tab, "*" takes the rest; '': no tabs }
    Tabs: string;
    { the control focused when the start window opens ('' : the nick
      name, Edit3) }
    StartFocus: string;
  end;

  TRealStart = class
  private
    FExe: string;
    FImages: TStringList;
    function Res(const Name: string; out Data: string): Boolean;
    procedure AddRuntime(const Line: string);
    procedure LoadGlyphs(N: TDfmNode; const Form: string);
  public
    Spec: TRealStartSpec;
    StartForm, ListForm, MsgForm: TDfmNode;
    StartBack, ListBack: TGSurface;
    Lang: TStringList;
    Languages: TStringList;
    { headsconfig.txt: Name=headN.gif,gender,skin,coat,sleeves,shoes,belt }
    Heads: TStringList;
    HeadPics: TList;
    { the character the box opens on: graalconfig.txt's head= }
    HeadIndex: Integer;
    { the install's graalconfig.txt ('' : none) }
    ConfigFile: string;
    constructor Create;
    destructor Destroy; override;
    { The forms and art from this program's own resources, else from the
      real program in Dir; the words from Dir's languages/; False when the
      forms or the pictures are missing. }
    function Load(const Dir: string; const ASpec: TRealStartSpec): Boolean;
    function Text(const Key, Default: string): string;
    function HasText(const Key: string): Boolean;
    { the glyph of the picture button Name on Form ('StartScreen' or
      'ServerList') }
    function Glyph(const Form, Name: string): TGSurface;
    function StartTitle: string;
    function ListTitle: string;
    { the game window's title: the language file's MainWindow= }
    function GameTitle: string;
  end;

{ Runs the start window and the server list in Win until the player picks
  Training or a server. False: closed, or Esc on the start window. }
function RunRealStart(Win: TGWindow; RS: TRealStart; Fetch: TListFetch;
  const Info: TStartInfo; const ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;

{ The nickname and the last account the real clients keep
  (HKCU\Software\Graal\Client: nickname, accountname, the last used
  first); nothing outside Windows. }
procedure ReadSavedLogin(var Nickname, Account: string);
procedure SaveLogin(const Nickname, Account: string);

{ The head picked in the character box (headsconfig.txt's line Index):
  its file and the five colour names. }
function HeadEntry(RS: TRealStart; Index: Integer; out HeadFile: string;
  Colors: TStrings): Boolean;

{ Graal's colour names (white .. transparent) to the palette index; -1 when
  unknown. }
function GraalColorIndex(const Name: string): Integer;

type
  { the look picked on the start window, for the game's player }
  TGuiLook = record
    Valid: Boolean;
    Head: string;
    Colors: array[0..4] of Integer;
  end;

var
  GuiLook: TGuiLook;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, Math, GPeRes, GUiFont;

function ConfigHead(const F: string): string; forward;

const
  ColWhite = $FFFFFFFF;
  { Wine's highlight, as on the real clients' screenshots }
  ColSelect = $FF3096FA;


function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

{ ---- the art ---- }

constructor TRealStart.Create;
begin
  inherited Create;
  FImages := TStringList.Create;
  Lang := TStringList.Create;
  Languages := TStringList.Create;
  Heads := TStringList.Create;
  HeadIndex := -1;
  HeadPics := TList.Create;
end;

destructor TRealStart.Destroy;
var
  I: Integer;
begin
  for I := 0 to FImages.Count - 1 do FImages.Objects[I].Free;
  FImages.Free;
  for I := 0 to HeadPics.Count - 1 do TGSurface(HeadPics[I]).Free;
  HeadPics.Free;
  StartForm.Free;
  ListForm.Free;
  MsgForm.Free;
  StartBack.Free;
  ListBack.Free;
  Lang.Free;
  Languages.Free;
  Heads.Free;
  inherited Destroy;
end;

function TRealStart.Res(const Name: string; out Data: string): Boolean;
begin
  Result := OwnResource(Name, Data);
  if not Result and (FExe <> '') then Result := PeResource(FExe, RT_RCDATA, Name, Data);
end;

function Picture(const Data, Name: string): TGSurface;
begin
  Result := TGSurface.Create(0, 0);
  if not LoadImageData(Data, Name, Result, False) or (Result.Width = 0) then
    FreeAndNil(Result);
end;

{ a glyph's transparent colour is its bottom-left pixel, as a VCL
  TBitmap's }
procedure KeyOut(S: TGSurface);
var
  I: Integer;
  K: Cardinal;
begin
  if (S = nil) or (S.Width = 0) or (S.Height = 0) then Exit;
  K := S.Pixels[(S.Height - 1) * S.Width];
  for I := 0 to S.Width * S.Height - 1 do
    if S.Pixels[I] = K then S.Pixels[I] := 0;
end;

procedure TRealStart.LoadGlyphs(N: TDfmNode; const Form: string);
var
  I: Integer;
  G: TGSurface;
  D: string;
begin
  if N.ClassName_ = 'TPaintButton' then
  begin
    G := nil;
    { a glyph the client sets at run time wins over the form's }
    if (N.Str('GlyphResource', '') <> '') and Res(N.Str('GlyphResource', ''), D) then
      G := Picture(D, N.Str('GlyphResource', ''));
    D := DfmBitmap(N.Bin('Glyph.Data'));
    if (G = nil) and (D <> '') then G := Picture(D, 'glyph.bmp');
    if G <> nil then
    begin
      KeyOut(G);
      FImages.AddObject(Form + '.' + N.Name, G);
    end;
  end;
  for I := 0 to N.Count - 1 do LoadGlyphs(N.Child(I), Form);
end;

procedure TRealStart.AddRuntime(const Line: string);
var
  F: TStringList;
  Form, N: TDfmNode;
begin
  F := TStringList.Create;
  try
    F.Delimiter := '|';
    F.StrictDelimiter := True;
    F.DelimitedText := Line;
    if F.Count < 4 then Exit;
    if F[0] = 'ServerList' then Form := ListForm else Form := StartForm;
    if Form = nil then Exit;
    { "Form|=Prop|Name|Value": a property the client sets at run time on
      a control its form holds (a glyph from the resources) }
    if Copy(F[1], 1, 1) = '=' then
    begin
      N := Form.Find(F[2]);
      if N <> nil then N.Props.Values[Copy(F[1], 2, MaxInt)] := F[3];
      Exit;
    end;
    if F.Count < 8 then Exit;
    N := TDfmNode.Create;
    N.Parent := Form;
    N.ClassName_ := F[1];
    N.Name := F[2];
    N.Props.Add('Left=' + F[3]);
    N.Props.Add('Top=' + F[4]);
    N.Props.Add('Width=' + F[5]);
    N.Props.Add('Height=' + F[6]);
    N.Props.Add('Caption=' + F[7]);
    N.Props.Add('Font.Style=[fsBold]');
    N.Props.Add('NumGlyphs=2');
    if (F.Count > 8) and (F[8] <> '') then N.Props.Add('GlyphResource=' + F[8]);
    if (F.Count > 9) and (F[9] <> '') then N.Props.Add('Font.Color=' + F[9])
    else N.Props.Add('Font.Color=clWindowText');
    if (F.Count > 10) and (F[10] <> '') then N.Props.Add('Color=' + F[10]);
    Form.Children.Add(N);
  finally
    F.Free;
  end;
end;

function TRealStart.Load(const Dir: string; const ASpec: TRealStartSpec): Boolean;
var
  D, LDir, F, Hc: string;
  L: TStringList;
  SR: TSearchRec;
  I, P: Integer;
  G: TGSurface;
begin
  Spec := ASpec;
  FExe := FirstFileIn(Dir, Spec.ExeNames);
  if Res('TCONNECTFRAME', D) then StartForm := ParseDfm(D);
  if Res('TSERVERLISTFRAME', D) then ListForm := ParseDfm(D);
  if Res('TSHORTMESSAGE', D) then MsgForm := ParseDfm(D);
  if Res(Spec.StartBack, D) then StartBack := Picture(D, Spec.StartBack);
  if Res(Spec.ListBack, D) then ListBack := Picture(D, Spec.ListBack);
  Result := (StartForm <> nil) and (ListForm <> nil) and (StartBack <> nil) and
    (ListBack <> nil);
  if not Result then Exit;
  L := TStringList.Create;
  try
    L.Text := Spec.Runtime;
    for I := 0 to L.Count - 1 do
      if Trim(L[I]) <> '' then AddRuntime(Trim(L[I]));
  finally
    L.Free;
  end;
  LoadGlyphs(StartForm, 'StartScreen');
  LoadGlyphs(ListForm, 'ServerList');
  { the languages: languages/language<Name>.txt (NewWorld: next to the
    program) }
  LDir := IncludeTrailingPathDelimiter(Dir) + 'languages' + PathDelim;
  if not DirectoryExists(LDir) then LDir := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(LDir + 'language*.txt', faAnyFile, SR) = 0 then
  begin
    repeat
      F := Copy(SR.Name, 9, Length(SR.Name) - 12);
      F := StringReplace(F, '#U00f1', #$F1, [rfReplaceAll]);
      F := StringReplace(F, '#U00e7', #$E7, [rfReplaceAll]);
      F := StringReplace(F, '#U00ea', #$EA, [rfReplaceAll]);
      Languages.Add(F);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  Languages.Sort;
  if Languages.IndexOf('English') < 0 then Languages.Insert(0, 'English');
  F := LDir + 'languageEnglish.txt';
  if FileExists(F) then
    try
      Lang.LoadFromFile(F);
    except
      Lang.Clear;
    end;
  { the characters: the install's headsconfig.txt, else the one this
    program carries }
  Hc := '';
  F := FirstFileIn(Dir, 'headsconfig.txt');
  L := TStringList.Create;
  try
    if F <> '' then
      try
        L.LoadFromFile(F);
      except
        L.Clear;
      end;
    if (L.Count = 0) and OwnResource('HEADSCONFIG', Hc) then L.Text := Hc;
    for I := 0 to L.Count - 1 do
    begin
      P := Pos('=', L[I]);
      if P > 1 then
      begin
        Heads.Add(L[I]);
        G := nil;
        F := Trim(Copy(L[I], P + 1, MaxInt));
        if Pos(',', F) > 0 then F := Copy(F, 1, Pos(',', F) - 1);
        F := FirstFileIn(Dir, 'levels/heads/' + F + ';levels/' + F + ';' + F);
        if F <> '' then
        begin
          G := TGSurface.Create(0, 0);
          if not LoadImageFile(F, G) or (G.Width = 0) then FreeAndNil(G);
        end;
        HeadPics.Add(G);
      end;
    end;
  finally
    L.Free;
  end;
  ConfigFile := FirstFileIn(Dir, 'graalconfig.txt');
  HeadIndex := Heads.IndexOfName(ConfigHead(ConfigFile));
  if (HeadIndex < 0) and (Heads.Count > 0) then HeadIndex := 0;
end;

function TRealStart.HasText(const Key: string): Boolean;
begin
  Result := Lang.IndexOfName(Key) >= 0;
end;

function TRealStart.Text(const Key, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  I := Lang.IndexOfName(Key);
  if I < 0 then Exit;
  if Trim(Lang.ValueFromIndex[I]) <> '' then Result := Trim(Lang.ValueFromIndex[I]);
end;

function TRealStart.Glyph(const Form, Name: string): TGSurface;
var
  I: Integer;
begin
  I := FImages.IndexOf(Form + '.' + Name);
  if I < 0 then Result := nil else Result := TGSurface(FImages.Objects[I]);
end;

function TRealStart.StartTitle: string;
begin
  if Spec.StartTitle <> '' then Result := Spec.StartTitle
  else Result := StartForm.Str('Caption', 'Graal');
  if not Spec.FixedStartTitle then Result := Text('StartScreen', Result);
end;

function TRealStart.ListTitle: string;
begin
  if Spec.ListTitle <> '' then Result := Spec.ListTitle
  else Result := ListForm.Str('Caption', 'Graalonline.com Server List');
  Result := Text('ServerList', Result);
end;

function TRealStart.GameTitle: string;
begin
  Result := Text('MainWindow', 'Graal');
end;

function GraalColorIndex(const Name: string): Integer;
const
  Names: array[0..19] of string = ('white', 'yellow', 'orange', 'pink', 'red',
    'darkred', 'lightgreen', 'green', 'darkgreen', 'lightblue', 'blue',
    'darkblue', 'brown', 'cynober', 'purple', 'darkpurple', 'lightgray', 'gray',
    'black', 'transparent');
var
  I: Integer;
begin
  for I := 0 to High(Names) do
    if SameText(Trim(Name), Names[I]) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

{ the look of headsconfig.txt's line Index into GuiLook }
procedure PickLook(RS: TRealStart; Index: Integer);
var
  L: TStringList;
  F: string;
  I, C: Integer;
begin
  GuiLook.Valid := False;
  L := TStringList.Create;
  try
    if not HeadEntry(RS, Index, F, L) or (F = '') then Exit;
    GuiLook.Head := F;
    for I := 0 to 4 do
    begin
      C := -1;
      { the list: gender, skin, coat, sleeves, shoes, belt }
      if I + 1 < L.Count then C := GraalColorIndex(L[I + 1]);
      if C < 0 then C := 0;
      GuiLook.Colors[I] := C;
    end;
    GuiLook.Valid := True;
  finally
    L.Free;
  end;
end;

{ graalconfig.txt's head=Name: the real clients keep the last character
  there }
function ConfigHead(const F: string): string;
var
  L: TStringList;
  I: Integer;
begin
  Result := '';
  if (F = '') or not FileExists(F) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(F);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
      if SameText(Copy(Trim(L[I]), 1, 5), 'head=') then
        Result := Trim(Copy(Trim(L[I]), 6, MaxInt));
  finally
    L.Free;
  end;
end;

procedure SaveConfigHead(const F, Name: string);
var
  L: TStringList;
  I: Integer;
  Done: Boolean;
begin
  if (F = '') or not FileExists(F) or (Name = '') then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(F);
      Done := False;
      for I := 0 to L.Count - 1 do
        if SameText(Copy(Trim(L[I]), 1, 5), 'head=') then
        begin
          if Trim(Copy(Trim(L[I]), 6, MaxInt)) = Name then Exit;
          L[I] := 'head=' + Name;
          Done := True;
        end;
      if not Done then L.Add('head=' + Name);
      L.SaveToFile(F);
    except
      { a read-only install keeps its old choice }
    end;
  finally
    L.Free;
  end;
end;

function HeadEntry(RS: TRealStart; Index: Integer; out HeadFile: string;
  Colors: TStrings): Boolean;
var
  V: string;
  L: TStringList;
  I: Integer;
begin
  Result := False;
  HeadFile := '';
  if (RS = nil) or (Index < 0) or (Index >= RS.Heads.Count) then Exit;
  V := RS.Heads.ValueFromIndex[Index];
  L := TStringList.Create;
  try
    L.CommaText := V;
    if L.Count = 0 then Exit;
    HeadFile := Trim(L[0]);
    if Colors <> nil then
    begin
      Colors.Clear;
      { gender, then skin, coat, sleeves, shoes, belt }
      for I := 2 to L.Count - 1 do Colors.Add(Trim(L[I]));
    end;
    Result := True;
  finally
    L.Free;
  end;
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

{ ---- drawing a form ---- }

type
  TBox = record
    X, Y, W, H: Integer;
  end;

  { what the windowed controls hold }
  TFormState = class
  public
    Values: TStringList;     { Name=text of edits and combo boxes }
    Focus: string;           { the focused control's name }
    Pressed: string;         { a picture button held down }
    PressUntil: Int64;
    Checked: TStringList;    { check boxes ticked }
    Rows: TStringList;       { list view rows: "name"#9"players" }
    Sel: Integer;
    Memo: TStringList;       { Name=text of rich edits and multi-line labels }
    TabNames: TStringList;   { the tab control's tabs }
    TabIndex: Integer;
    { Fetch.Servers index of each row }
    RowMap: array of Integer;
    constructor Create;
    destructor Destroy; override;
    function V(const Name: string): string;
    procedure SetV(const Name, Value: string);
  end;

constructor TFormState.Create;
begin
  inherited Create;
  Values := TStringList.Create;
  Checked := TStringList.Create;
  Rows := TStringList.Create;
  Memo := TStringList.Create;
  TabNames := TStringList.Create;
  Sel := -1;
end;

destructor TFormState.Destroy;
begin
  Values.Free;
  Checked.Free;
  Rows.Free;
  Memo.Free;
  TabNames.Free;
  inherited Destroy;
end;

function TFormState.V(const Name: string): string;
var
  I: Integer;
begin
  I := Values.IndexOfName(Name);
  if I < 0 then Result := '' else Result := Copy(Values[I], Length(Name) + 2, MaxInt);
end;

procedure TFormState.SetV(const Name, Value: string);
var
  I: Integer;
begin
  I := Values.IndexOfName(Name);
  if I < 0 then Values.Add(Name + '=' + Value)
  else Values[I] := Name + '=' + Value;
end;

function Abs_(N: TDfmNode): TBox;
var
  P: TDfmNode;
begin
  Result.X := N.Int('Left', 0);
  Result.Y := N.Int('Top', 0);
  Result.W := N.Int('Width', 0);
  Result.H := N.Int('Height', 0);
  P := N.Parent;
  while (P <> nil) and (P.Parent <> nil) do
  begin
    Inc(Result.X, P.Int('Left', 0));
    Inc(Result.Y, P.Int('Top', 0));
    P := P.Parent;
  end;
end;

function Inside(const B: TBox; X, Y: Integer): Boolean;
begin
  Result := (X >= B.X) and (Y >= B.Y) and (X < B.X + B.W) and (Y < B.Y + B.H);
end;

function Shown(N: TDfmNode): Boolean;
var
  B: TBox;
begin
  B := Abs_(N);
  Result := N.Bool('Visible', True) and (B.X < 1000) and (B.Y < 1000);
end;

function FontColor(N: TDfmNode): Cardinal;
var
  P: TDfmNode;
begin
  P := N;
  while P <> nil do
  begin
    if P.Has('Font.Color') then
    begin
      Result := DfmColor(P.Str('Font.Color', ''), $FF000000);
      Exit;
    end;
    P := P.Parent;
  end;
  Result := $FF000000;
end;

function Face(N: TDfmNode): TUiFace;
begin
  if Pos('fsBold', N.Str('Font.Style', '')) > 0 then Result := ufBold else Result := ufRegular;
end;

function Graphic(N: TDfmNode): Boolean;
begin
  Result := (N.ClassName_ = 'TLabel') or (N.ClassName_ = 'TPaintButton') or
    (N.ClassName_ = 'TImage') or (N.ClassName_ = 'TBevel') or (N.ClassName_ = 'TSpeedButton');
end;

function NoAmp(const S: string): string;
begin
  Result := StringReplace(S, '&&', #1, [rfReplaceAll]);
  Result := StringReplace(Result, '&', '', [rfReplaceAll]);
  Result := StringReplace(Result, #1, '&', [rfReplaceAll]);
end;

{ Text broken into lines (at #10, then at spaces) to W pixels }
procedure WrapLines(const Text: string; W: Integer; F: TUiFace; Out_: TStrings);
var
  Lines, Words: TStringList;
  I, J: Integer;
  Line, Cand: string;
begin
  Out_.Clear;
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
        if (UiTextWidth(Cand, F) > W) and (Line <> '') then
        begin
          Out_.Add(Line);
          Line := Words[J];
        end
        else
          Line := Cand;
      end;
      Out_.Add(Line);
    end;
  finally
    Words.Free;
    Lines.Free;
  end;
end;

{ the sunken edge of an edit or combo box under Wine's default look:
  grey and dark grey over the top and left, light grey and white under the
  bottom and right (measured on the real clients' screenshots) }
procedure Sunken(S: TGSurface; const B: TBox);
begin
  S.FillRect(B.X, B.Y, B.W, 1, $FFA6A6A6);
  S.FillRect(B.X, B.Y, 1, B.H, $FFA6A6A6);
  S.FillRect(B.X + 1, B.Y + 1, B.W - 2, 1, $FF6A6A6A);
  S.FillRect(B.X + 1, B.Y + 1, 1, B.H - 2, $FF6A6A6A);
  S.FillRect(B.X, B.Y + B.H - 1, B.W, 1, ColWhite);
  S.FillRect(B.X + B.W - 1, B.Y, 1, B.H, ColWhite);
  S.FillRect(B.X + 1, B.Y + B.H - 2, B.W - 2, 1, $FFE3E3E3);
  S.FillRect(B.X + B.W - 2, B.Y + 1, 1, B.H - 2, $FFE3E3E3);
end;

procedure Raised(S: TGSurface; X, Y, W, H: Integer);
begin
  S.FillRect(X, Y, W, H, $FFD4D0C8);
  S.FillRect(X, Y, W, 1, ColWhite);
  S.FillRect(X, Y, 1, H, ColWhite);
  S.FillRect(X, Y + H - 1, W, 1, $FF404040);
  S.FillRect(X + W - 1, Y, 1, H, $FF404040);
  S.FillRect(X + 1, Y + H - 2, W - 2, 1, $FF808080);
  S.FillRect(X + W - 2, Y + 1, 1, H - 2, $FF808080);
end;

{ the caption of a picture button: bold, centred, the accelerator letter
  (after '&') in red, as the 2.x buttons draw it }
procedure ButtonCaption(S: TGSurface; const B: TBox; const Caption: string; Col: Cardinal;
  F: TUiFace; D: Integer);
var
  Plain: string;
  X, Y, I: Integer;
  Amp: Boolean;
begin
  Plain := NoAmp(Caption);
  X := B.X + (B.W - UiTextWidth(Plain, F)) div 2 + D;
  Y := B.Y + (B.H - UiLineH) div 2 + D;
  Amp := False;
  I := 1;
  while I <= Length(Caption) do
  begin
    if (Caption[I] = '&') and (I < Length(Caption)) and (Caption[I + 1] <> '&') then
      Amp := True
    else
    begin
      if Amp then UiDrawText(S, X, Y, Caption[I], $FFFF0000, F)
      else UiDrawText(S, X, Y, Caption[I], Col, F);
      Inc(X, UiTextWidth(Caption[I], F));
      Amp := False;
      if (Caption[I] = '&') then Inc(I);
    end;
    Inc(I);
  end;
end;

{ the place of tab I of a tab control at B: the picked one 2 px taller
  and wider, as Wine draws them }
function TabBox(const B: TBox; Names: TStrings; I, Picked: Integer): TBox;
var
  K, X: Integer;
begin
  X := B.X;
  for K := 0 to I - 1 do Inc(X, UiTextWidth(Names[K], ufRegular) + 14);
  Result.X := X;
  Result.Y := B.Y + 2;
  Result.W := UiTextWidth(Names[I], ufRegular) + 14;
  Result.H := B.H - 2;
  if I = Picked then
  begin
    if I > 0 then Dec(Result.X, 2);
    Inc(Result.W, 4);
    Dec(Result.Y, 2);
    Inc(Result.H, 2);
  end;
end;

type
  TFormPainter = class
  public
    RS: TRealStart;
    FormKey: string;   { 'StartScreen' / 'ServerList' }
    St: TFormState;
    Surf: TGSurface;
    { the window's picture, which a tab control shows through beside its
      tabs }
    BackPic: TGSurface;
    procedure Paint(Root: TDfmNode);
    procedure PaintNode(N: TDfmNode);
    procedure PaintChildren(N: TDfmNode);
    function Caption(N: TDfmNode): string;
    function Hit(Root: TDfmNode; X, Y: Integer): TDfmNode;
  end;

function TFormPainter.Caption(N: TDfmNode): string;
begin
  { a control the client words from another form's key (LangKey, set in
    the build's spec) }
  if N.Has('LangKey') and RS.HasText(N.Str('LangKey', '')) then
    Result := RS.Text(N.Str('LangKey', ''), N.Str('Caption', ''))
  else if RS.HasText(FormKey + '-' + N.Name) then
    Result := RS.Text(FormKey + '-' + N.Name, N.Str('Caption', ''))
  else Result := N.Str('Caption', '');
end;

procedure TFormPainter.PaintChildren(N: TDfmNode);
var
  I: Integer;
begin
  for I := 0 to N.Count - 1 do
    if Graphic(N.Child(I)) and Shown(N.Child(I)) then PaintNode(N.Child(I));
  for I := 0 to N.Count - 1 do
    if not Graphic(N.Child(I)) and Shown(N.Child(I)) then PaintNode(N.Child(I));
end;

procedure TFormPainter.Paint(Root: TDfmNode);
begin
  PaintChildren(Root);
end;

procedure TFormPainter.PaintNode(N: TDfmNode);
var
  B, Btn: TBox;
  C, Back, Tc: Cardinal;
  T: string;
  L: TStringList;
  I, Y, X, D, W, Col0, HeadI: Integer;
  G: TGSurface;
  F: TUiFace;
  Down, Focused, Combo, Masked: Boolean;
begin
  B := Abs_(N);
  C := FontColor(N);
  F := Face(N);
  if N.ClassName_ = 'TLabel' then
  begin
    I := St.Memo.IndexOfName(N.Name);
    if I >= 0 then T := St.Memo.ValueFromIndex[I] else T := NoAmp(Caption(N));
    if T = '' then Exit;
    if not N.Bool('Transparent', False) and N.Has('Color') then
      Surf.FillRect(B.X, B.Y, B.W, B.H, DfmColor(N.Str('Color', ''), 0));
    L := TStringList.Create;
    try
      if N.Bool('WordWrap', False) then WrapLines(T, B.W, F, L) else L.Text := T;
      Y := B.Y;
      for I := 0 to L.Count - 1 do
      begin
        W := UiTextWidth(L[I], F);
        if N.Str('Alignment', '') = 'taCenter' then X := B.X + (B.W - W) div 2
        else if N.Str('Alignment', '') = 'taRightJustify' then X := B.X + B.W - W
        else X := B.X;
        UiDrawText(Surf, X, Y, L[I], C, F);
        Inc(Y, UiLineH);
      end;
    finally
      L.Free;
    end;
  end
  else if N.ClassName_ = 'TPaintButton' then
  begin
    G := RS.Glyph(FormKey, N.Name);
    Down := (St.Pressed = N.Name) and (NowMs < St.PressUntil);
    D := Ord(Down);
    if G <> nil then
    begin
      W := G.Width div Max(1, N.Int('NumGlyphs', 1));
      if N.Int('NumGlyphs', 1) < 2 then D := 0;
      Surf.Blit(G, D * W, 0, W, G.Height, B.X + (B.W - W) div 2, B.Y + (B.H - G.Height) div 2);
    end;
    T := Caption(N);
    if T <> '' then ButtonCaption(Surf, B, T, C, F, Ord(Down));
  end
  else if (N.ClassName_ = 'TEdit') or (N.ClassName_ = 'TComboBox') then
  begin
    Back := DfmColor(N.Str('Color', 'clWindow'), ColWhite);
    Surf.FillRect(B.X + 2, B.Y + 2, B.W - 4, B.H - 4, Back);
    Sunken(Surf, B);
    Combo := N.ClassName_ = 'TComboBox';
    Focused := St.Focus = N.Name;
    W := B.W - 2;
    if Combo then
    begin
      { the drop-down button: 17 wide inside the edge, a raised face with
        a black arrow 7 wide }
      X := B.X + B.W - 2 - 17;
      Surf.FillRect(X, B.Y + 2, 17, B.H - 4, $FFF5F5F5);
      Surf.FillRect(X, B.Y + 2, 17, 1, $FFE3E3E3);
      Surf.FillRect(X, B.Y + 2, 1, B.H - 4, $FFE3E3E3);
      Surf.FillRect(X + 1, B.Y + 3, 15, 1, ColWhite);
      Surf.FillRect(X + 1, B.Y + 3, 1, B.H - 6, ColWhite);
      Surf.FillRect(X + 15, B.Y + 2, 1, B.H - 4, $FFA6A6A6);
      Surf.FillRect(X + 16, B.Y + 2, 1, B.H - 4, $FF6A6A6A);
      Surf.FillRect(X, B.Y + B.H - 4, 17, 1, $FFA6A6A6);
      Surf.FillRect(X, B.Y + B.H - 3, 17, 1, $FF6A6A6A);
      Y := B.Y + (B.H - 4) div 2;
      for I := 0 to 3 do Surf.FillRect(X + 5 + I, Y + I, 7 - 2 * I, 1, $FF000000);
      W := B.W - 2 - 17;
    end;
    T := St.V(N.Name);
    Masked := N.Str('PasswordChar', '') <> '';
    if Masked then T := StringOfChar('*', Length(T));
    X := B.X + 4;
    HeadI := -1;
    if N.Name = 'characterbox' then
    begin
      HeadI := RS.Heads.IndexOfName(T);
      if (HeadI >= 0) and (HeadI < RS.HeadPics.Count) and (RS.HeadPics[HeadI] <> nil) then
      begin
        { the head facing down (the third 32 x 32 frame) at half size, as
          the box draws its items }
        G := TGSurface(RS.HeadPics[HeadI]);
        if G.Height >= 96 then
          for Y := 0 to 15 do
            for D := 0 to 15 do
            begin
              Tc := G.Pixels[2 * D + (64 + 2 * Y) * G.Width];
              if ((Tc shr 24) <> 0) and (B.Y + (B.H - 16) div 2 + Y < Surf.Height) then
                Surf.Pixels[X + D + (B.Y + (B.H - 16) div 2 + Y) * Surf.Width] := Tc;
            end;
        Inc(X, 20);
      end;
    end;
    while (T <> '') and (UiTextWidth(T, ufRegular) > W - (X - B.X) - 4) do
      Delete(T, 1, 1);
    if Focused and Combo and (T <> '') then
    begin
      { a focused list combo box shows its item picked, across the box }
      Surf.FillRect(B.X + 3, B.Y + 3, W - 4, B.H - 6, ColSelect);
      UiDrawText(Surf, X, B.Y + (B.H - UiLineH) div 2, T, ColWhite, ufRegular);
    end
    else
      UiDrawText(Surf, X, B.Y + (B.H - UiLineH) div 2, T, C, ufRegular);
    if Focused and not Combo and ((NowMs div 500) mod 2 = 0) then
      Surf.FillRect(X + UiTextWidth(T, ufRegular), B.Y + 4, 1, B.H - 8, C);
  end
  else if (N.ClassName_ = 'TRichEdit') or (N.ClassName_ = 'TMemo') then
  begin
    Back := DfmColor(N.Str('Color', 'clWindow'), ColWhite);
    Surf.FillRect(B.X + 2, B.Y + 2, B.W - 4, B.H - 4, Back);
    Sunken(Surf, B);
    I := St.Memo.IndexOfName(N.Name);
    if I >= 0 then
    begin
      L := TStringList.Create;
      try
        WrapLines(St.Memo.ValueFromIndex[I], B.W - 8, ufRegular, L);
        for I := 0 to L.Count - 1 do
          if 3 + (I + 1) * UiLineH <= B.H then
            UiDrawText(Surf, B.X + 4, B.Y + 3 + I * UiLineH, L[I], C, ufRegular);
      finally
        L.Free;
      end;
    end;
  end
  else if N.ClassName_ = 'TCheckBox' then
  begin
    Y := B.Y + (B.H - 13) div 2;
    Surf.FillRect(B.X, Y, 13, 13, ColWhite);
    Btn.X := B.X; Btn.Y := Y; Btn.W := 13; Btn.H := 13;
    Sunken(Surf, Btn);
    if St.Checked.IndexOf(N.Name) >= 0 then
      for I := 0 to 6 do
      begin
        if I < 2 then D := 6 + I - 2 else D := 7 - (I - 2) + 1;
        Surf.FillRect(B.X + 3 + I, Y + D - 1, 1, 3, $FF000000);
      end;
    UiDrawText(Surf, B.X + 17, B.Y + (B.H - UiLineH) div 2, NoAmp(Caption(N)), C, F);
  end
  else if N.ClassName_ = 'TListView' then
  begin
    Back := DfmColor(N.Str('Color', 'clWindow'), ColWhite);
    Surf.FillRect(B.X, B.Y, B.W, B.H, $FFAEAEAE);
    Surf.FillRect(B.X + 1, B.Y + 1, B.W - 2, B.H - 2, ColWhite);
    Surf.FillRect(B.X + 2, B.Y + 2, B.W - 4, B.H - 4, Back);
    Col0 := N.Int('Columns[0].Width', 108);
    Y := B.Y + 2;
    if N.Str('ShowColumnHeaders', 'True') <> 'False' then
    begin
      { the header under Wine: white, grey lines after each column, the
        captions black }
      Surf.FillRect(B.X + 2, Y, B.W - 4, 20, ColWhite);
      Surf.FillRect(B.X + 2 + Col0 - 1, Y + 2, 1, 16, $FFB2B2B2);
      Surf.FillRect(B.X + 2 + Col0 + N.Int('Columns[1].Width', 55) - 1, Y + 2, 1, 16, $FFB2B2B2);
      UiDrawText(Surf, B.X + 8, Y + 2, RS.Text(FormKey + '-ListColumn1',
        N.Str('Columns[0].Caption', 'Name')), $FF000000, ufRegular);
      UiDrawText(Surf, B.X + 2 + Col0 + 6, Y + 2, RS.Text(FormKey + '-ListColumn2',
        N.Str('Columns[1].Caption', 'Players')), $FF000000, ufRegular);
      Inc(Y, 20);
    end;
    { a small-image list puts the rows' text after a 17 px icon place }
    if N.Has('SmallImages') then X := B.X + 2 + 17 + 4 else X := B.X + 2 + 4;
    for I := 0 to St.Rows.Count - 1 do
    begin
      if Y + UiLineH + 1 > B.Y + B.H - 2 then Break;
      T := St.Rows[I];
      if I = St.Sel then
      begin
        W := B.X + 2 + Col0 + N.Int('Columns[1].Width', 55) - (X - 2);
        if St.Focus = N.Name then
        begin
          Surf.FillRect(X - 2, Y, W, UiLineH + 1, ColSelect);
          Tc := ColWhite;
        end
        else
        begin
          { picked, without the focus (HideSelection off): light grey,
            black text }
          Surf.FillRect(X - 2, Y, W, UiLineH + 1, $FFF5F5F5);
          Tc := $FF000000;
        end;
      end
      else Tc := C;
      UiDrawText(Surf, X, Y, Copy(T, 1, Pos(#9, T + #9) - 1), Tc, ufRegular);
      T := Copy(T, Pos(#9, T + #9) + 1, MaxInt);
      if N.Str('Columns[1].Alignment', '') = 'taRightJustify' then
        UiDrawText(Surf, B.X + 2 + Col0 + N.Int('Columns[1].Width', 55) - 6 -
          UiTextWidth(T, ufRegular), Y, T, Tc, ufRegular)
      else
        UiDrawText(Surf, B.X + 2 + Col0 + 6, Y, T, Tc, ufRegular);
      Inc(Y, UiLineH + 1);
    end;
  end
  else if N.ClassName_ = 'TTabControl' then
  begin
    { the tabs over the panel below: picked first-drawn last, raised
      over the panel's top edge; beside them the window's picture }
    if BackPic <> nil then Surf.Blit(BackPic, B.X, B.Y, B.W, B.H - 2, B.X, B.Y);
    for I := 0 to St.TabNames.Count - 1 do
      if I <> St.TabIndex then
      begin
        Btn := TabBox(B, St.TabNames, I, St.TabIndex);
        Surf.FillRect(Btn.X, Btn.Y, Btn.W, Btn.H, $FFAEAEAE);
        Surf.FillRect(Btn.X + 1, Btn.Y + 1, Btn.W - 2, Btn.H - 1, $FFF5F5F5);
        Surf.FillRect(Btn.X + 2, Btn.Y + 2, Btn.W - 4, Btn.H - 2,
          DfmColor(N.Str('Color', 'clGreen'), $FF008000));
        UiDrawText(Surf, Btn.X + 7, Btn.Y + 4, St.TabNames[I], C, ufRegular);
      end;
    Surf.FillRect(B.X, B.Y + B.H - 2, B.W, 1, ColWhite);
    if (St.TabIndex >= 0) and (St.TabIndex < St.TabNames.Count) then
    begin
      Btn := TabBox(B, St.TabNames, St.TabIndex, St.TabIndex);
      Surf.FillRect(Btn.X, Btn.Y, Btn.W, Btn.H, $FFAEAEAE);
      Surf.FillRect(Btn.X + 1, Btn.Y + 1, Btn.W - 2, Btn.H - 1, $FFFCFCFC);
      Surf.FillRect(Btn.X + 1, Btn.Y + 2, Btn.W - 3, Btn.H - 1,
        DfmColor(N.Str('Color', 'clGreen'), $FF008000));
      Surf.FillRect(Btn.X + Btn.W - 2, Btn.Y + 2, 1, Btn.H - 2, ColWhite);
      UiDrawText(Surf, Btn.X + 7, Btn.Y + 4, St.TabNames[St.TabIndex], C, ufRegular);
    end;
  end
  else if (N.ClassName_ = 'TPanel') or (N.ClassName_ = 'TGroupBox') then
  begin
    if N.Has('Color') then
      Surf.FillRect(B.X, B.Y, B.W, B.H, DfmColor(N.Str('Color', ''), $FFD4D0C8));
    if N.Str('BevelOuter', 'bvRaised') = 'bvRaised' then
    begin
      Surf.FillRect(B.X, B.Y, B.W, 1, ColWhite);
      Surf.FillRect(B.X, B.Y, 1, B.H, ColWhite);
      Surf.FillRect(B.X, B.Y + B.H - 1, B.W, 1, $FF808080);
      Surf.FillRect(B.X + B.W - 1, B.Y, 1, B.H, $FF808080);
    end;
    T := NoAmp(Caption(N));
    if (T <> '') and (N.Count = 0) then
    begin
      if N.Str('Alignment', 'taCenter') = 'taLeftJustify' then X := B.X
      else X := B.X + (B.W - UiTextWidth(T, F)) div 2;
      UiDrawText(Surf, X, B.Y + (B.H - UiLineH) div 2, T, C, F);
    end;
    PaintChildren(N);
  end;
end;

{ the topmost shown control at (X, Y) }
function TFormPainter.Hit(Root: TDfmNode; X, Y: Integer): TDfmNode;
var
  I: Integer;
  H: TDfmNode;
begin
  Result := nil;
  for I := Root.Count - 1 downto 0 do
  begin
    if not Shown(Root.Child(I)) then Continue;
    if Root.Child(I).Count > 0 then
    begin
      H := Hit(Root.Child(I), X, Y);
      if H <> nil then
      begin
        Result := H;
        Exit;
      end;
    end;
    if Inside(Abs_(Root.Child(I)), X, Y) and (Root.Child(I).ClassName_ <> 'TPanel') and
      (Root.Child(I).ClassName_ <> 'TLabel') then
    begin
      Result := Root.Child(I);
      Exit;
    end;
  end;
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

{ the editable controls in tab order }
procedure TabList(N: TDfmNode; L: TStringList);
var
  I: Integer;
  C: TDfmNode;
begin
  for I := 0 to N.Count - 1 do
  begin
    C := N.Child(I);
    if not Shown(C) then Continue;
    if (C.ClassName_ = 'TEdit') or (C.ClassName_ = 'TComboBox') then
      if not C.Bool('ReadOnly', False) then
        L.AddObject(Format('%.4d', [C.Int('TabOrder', 0) + 100 * L.Count]), C);
    if C.Count > 0 then TabList(C, L);
  end;
end;

{ ---- the two windows ---- }

function RunRealStart(Win: TGWindow; RS: TRealStart; Fetch: TListFetch;
  const Info: TStartInfo; const ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;
type
  TPage = (pgStart, pgFetch, pgList);
var
  S: TGSurface;
  Page: TPage;
  P: TFormPainter;
  StS, LiS: TFormState;
  Cur: TFormState;
  Form, H: TDfmNode;
  CX, CY, I, Row, LH: Integer;
  Clicked, Fetched: Boolean;
  Chars, Note, V, Key: string;
  Tabs, TabPre: TStringList;
  Srv: TListServer;
  B: TBox;
  Msg: TDfmNode;

  procedure ShowPage(Pg: TPage);
  begin
    Page := Pg;
    if Page = pgList then
    begin
      Win.Reshape(RS.ListTitle, RS.ListForm.Int('ClientWidth', 577),
        RS.ListForm.Int('ClientHeight', 416), True);
      S.SetSize(RS.ListForm.Int('ClientWidth', 577), RS.ListForm.Int('ClientHeight', 416));
    end
    else if Pg = pgStart then
    begin
      Win.Reshape(RS.StartTitle, RS.StartForm.Int('ClientWidth', 577),
        RS.StartForm.Int('ClientHeight', 416), True);
      S.SetSize(RS.StartForm.Int('ClientWidth', 577), RS.StartForm.Int('ClientHeight', 416));
    end;
  end;

  procedure Press(St: TFormState; const Name: string);
  begin
    St.Pressed := Name;
    St.PressUntil := NowMs + 150;
  end;

  { the tab a server goes on: its name's type prefix ("P "), else "*" }
  function TabOf(const Name: string): Integer;
  var
    K: Integer;
    Pre: string;
  begin
    Result := -1;
    Pre := '';
    if (Length(Name) > 2) and (Name[2] = ' ') then Pre := Name[1];
    for K := 0 to TabPre.Count - 1 do
      if (TabPre[K] = Pre) and (Pre <> '') then Result := K;
    if Result < 0 then Result := TabPre.IndexOf('*');
  end;

  procedure ListRows;
  var
    K: Integer;
  begin
    LiS.Rows.Clear;
    SetLength(LiS.RowMap, 0);
    if (LiS.TabNames.Count > 0) and (LiS.TabIndex < 0) then
    begin
      { the first tab that holds a server }
      for K := High(Fetch.Servers) downto 0 do
        if (TabOf(Fetch.Servers[K].Name) >= 0) and ((LiS.TabIndex < 0) or
          (TabOf(Fetch.Servers[K].Name) < LiS.TabIndex)) then
          LiS.TabIndex := TabOf(Fetch.Servers[K].Name);
    end;
    for K := 0 to High(Fetch.Servers) do
      if (LiS.TabNames.Count = 0) or (TabOf(Fetch.Servers[K].Name) = LiS.TabIndex) then
      begin
        LiS.Rows.Add(ServerDisplayName(Fetch.Servers[K].Name) + #9 + Fetch.Servers[K].Players);
        SetLength(LiS.RowMap, Length(LiS.RowMap) + 1);
        LiS.RowMap[High(LiS.RowMap)] := K;
      end;
    if (LiS.Sel < 0) and (LiS.Rows.Count > 0) then LiS.Sel := 0;
    if LiS.Sel >= LiS.Rows.Count then LiS.Sel := LiS.Rows.Count - 1;
  end;

  procedure ShowServer;
  begin
    FillChar(Srv, SizeOf(Srv), 0);
    if (LiS.Sel >= 0) and (LiS.Sel <= High(LiS.RowMap)) then
      Srv := Fetch.Servers[LiS.RowMap[LiS.Sel]];
    LiS.SetV('Edit1', ServerDisplayName(Srv.Name));
    LiS.SetV('Edit2', Srv.Language);
    LiS.SetV('Edit3', Srv.Version);
    LiS.SetV('Edit4', Srv.Url);
    LiS.Memo.Values['RichEdit1'] := Srv.Description;
    LiS.Memo.Values['Description'] := Srv.Description;
  end;

  procedure NextFocus(St: TFormState; Root: TDfmNode);
  var
    K: Integer;
  begin
    Tabs.Clear;
    TabList(Root, Tabs);
    Tabs.Sort;
    if Tabs.Count = 0 then Exit;
    K := 0;
    while (K < Tabs.Count) and (TDfmNode(Tabs.Objects[K]).Name <> St.Focus) do Inc(K);
    if K >= Tabs.Count then K := -1;
    St.Focus := TDfmNode(Tabs.Objects[(K + 1) mod Tabs.Count]).Name;
  end;

  { a combo box steps to its next item }
  procedure Cycle(St: TFormState; const Name: string);
  var
    Items: TStringList;
    K: Integer;
  begin
    Items := TStringList.Create;
    try
      if Name = 'languagebox' then Items.Assign(RS.Languages)
      else if Name = 'characterbox' then
        for K := 0 to RS.Heads.Count - 1 do Items.Add(RS.Heads.Names[K])
      else Exit;
      if Items.Count = 0 then Exit;
      K := Items.IndexOf(St.V(Name));
      St.SetV(Name, Items[(K + 1) mod Items.Count]);
    finally
      Items.Free;
    end;
  end;

  procedure Account(St: TFormState);
  var
    K: Integer;
  begin
    R.Account := St.V('accountbox');
    R.Password := St.V('passedit');
    R.Nickname := StS.V('Edit3');
    SaveLogin(R.Nickname, R.Account);
    { the character box's pick dresses the player and is kept for next
      time, as the real clients do }
    K := RS.Heads.IndexOfName(StS.V('characterbox'));
    if (K >= 0) and (RS.StartForm.Find('characterbox') <> nil) then
    begin
      PickLook(RS, K);
      SaveConfigHead(RS.ConfigFile, RS.Heads.Names[K]);
    end;
  end;

begin
  Result := False;
  R.Choice := scQuit;
  S := TGSurface.Create(0, 0);
  P := TFormPainter.Create;
  StS := TFormState.Create;
  LiS := TFormState.Create;
  Tabs := TStringList.Create;
  TabPre := TStringList.Create;
  try
    P.RS := RS;
    LiS.TabIndex := -1;
    Tabs.Text := RS.Spec.Tabs;
    for I := 0 to Tabs.Count - 1 do
      if Pos('|', Tabs[I]) > 0 then
      begin
        TabPre.Add(Copy(Tabs[I], 1, Pos('|', Tabs[I]) - 1));
        LiS.TabNames.Add(Copy(Tabs[I], Pos('|', Tabs[I]) + 1, MaxInt));
      end;
    Tabs.Clear;
    P.Surf := S;
    { the nick and account the clients keep in the registry }
    if R.Nickname = '' then ReadSavedLogin(R.Nickname, R.Account);
    StS.SetV('Edit3', R.Nickname);
    StS.SetV('languagebox', 'English');
    if (RS.HeadIndex >= 0) and (RS.HeadIndex < RS.Heads.Count) then StS.SetV('characterbox', RS.Heads.Names[RS.HeadIndex]);
    if RS.Spec.AccountOnList then Cur := LiS else Cur := StS;
    Cur.SetV('accountbox', R.Account);
    { the password box opens with the form's text ("guest") }
    if R.Password = '' then
    begin
      if RS.Spec.AccountOnList then H := RS.ListForm.Find('passedit')
      else H := RS.StartForm.Find('passedit');
      if H <> nil then Cur.SetV('passedit', H.Str('Text', ''));
    end
    else Cur.SetV('passedit', R.Password);
    LiS.Checked.Add('CheckBox1');
    if RS.Spec.StartFocus <> '' then StS.Focus := RS.Spec.StartFocus
    else StS.Focus := 'Edit3';
    Note := Message;
    Fetched := False;
    ShowPage(pgStart);
    while True do
    begin
      Win.Pump;
      if Win.Closed then
      begin
        { the list's close button goes back to the start window }
        if Page <> pgList then Exit;
        Exit;
      end;
      if Assigned(Info.StopRequested) and Info.StopRequested() then Exit;
      Clicked := Win.TakeClick(CX, CY);
      Chars := Win.TakeChars;
      Fetch.Poll;
      if Page = pgList then
      begin
        Form := RS.ListForm;
        Cur := LiS;
        P.FormKey := 'ServerList';
      end
      else
      begin
        Form := RS.StartForm;
        Cur := StS;
        P.FormKey := 'StartScreen';
      end;
      P.St := Cur;
      if Page = pgFetch then
      begin
        Chars := '';
        Clicked := False;
        if Fetch.Done then
        begin
          Fetched := True;
          ListRows;
          ShowServer;
          LiS.Focus := 'ListView1';
          ShowPage(pgList);
          Continue;
        end;
        if Fetch.Failed then
        begin
          Note := Fetch.Status;
          ShowPage(pgStart);
        end;
      end;
      if Pos(#27, Chars) > 0 then
      begin
        if Page = pgList then
        begin
          ShowPage(pgStart);
          Continue;
        end;
        Exit;
      end;
      while Pos(#9, Chars) > 0 do
      begin
        Delete(Chars, Pos(#9, Chars), 1);
        NextFocus(Cur, Form);
      end;
      Key := Chars;
      Chars := StringReplace(Chars, #13, '', [rfReplaceAll]);
      if Cur.Focus <> '' then
      begin
        H := Form.Find(Cur.Focus);
        if (H <> nil) and ((H.ClassName_ = 'TEdit') or
          ((H.ClassName_ = 'TComboBox') and (H.Str('Style', '') = ''))) then
        begin
          V := Cur.V(Cur.Focus);
          TypeInto(V, Chars, 30);
          Cur.SetV(Cur.Focus, V);
        end;
      end;
      H := nil;
      if Clicked then
      begin
        H := P.Hit(Form, CX, CY);
        if H <> nil then
        begin
          if (H.ClassName_ = 'TEdit') or (H.ClassName_ = 'TComboBox') then
          begin
            if not H.Bool('ReadOnly', False) then Cur.Focus := H.Name;
            if (H.ClassName_ = 'TComboBox') and (H.Str('Style', '') <> '') then Cycle(Cur, H.Name);
          end
          else if H.ClassName_ = 'TPaintButton' then Press(Cur, H.Name)
          else if H.ClassName_ = 'TCheckBox' then
          begin
            I := Cur.Checked.IndexOf(H.Name);
            if I >= 0 then Cur.Checked.Delete(I) else Cur.Checked.Add(H.Name);
          end
          else if (H.ClassName_ = 'TTabControl') and (LiS.TabNames.Count > 0) then
          begin
            for I := 0 to LiS.TabNames.Count - 1 do
              if Inside(TabBox(Abs_(H), LiS.TabNames, I, LiS.TabIndex), CX, CY) then
              begin
                LiS.TabIndex := I;
                LiS.Sel := 0;
                ListRows;
                ShowServer;
              end;
          end
          else if H.ClassName_ = 'TListView' then
          begin
            Cur.Focus := H.Name;
            B := Abs_(H);
            LH := B.Y + 2;
            if H.Str('ShowColumnHeaders', 'True') <> 'False' then Inc(LH, 20);
            Row := (CY - LH) div (UiLineH + 1);
            if (CY >= LH) and (Row >= 0) and (Row < LiS.Rows.Count) then
            begin
              LiS.Sel := Row;
              ShowServer;
            end;
          end;
        end;
      end;
      case Page of
        pgStart:
          begin
            if (H <> nil) and (H.Name = 'Button2') then
            begin
              Account(StS);
              R.Choice := scTraining;
              Result := True;
              Exit;
            end;
            if (H <> nil) and (H.Name = 'Button3') then
              Note := 'The options window is not built yet.';
            if ((H <> nil) and (H.Name = 'Button1')) or (Pos(#13, Key) > 0) then
            begin
              Press(StS, 'Button1');
              Note := '';
              if RS.Spec.AccountOnList then
              begin
                { NewMain and NewWorld beta 1: the list opens at once and
                  asks the listserver; the account comes after }
                if not Fetched then Fetch.Start(ListHost, ListPort, '', '');
                ListRows;
                ShowServer;
                LiS.Focus := 'accountbox';
                ShowPage(pgList);
                Continue;
              end;
              Account(StS);
              Fetch.Start(ListHost, ListPort, R.Account, R.Password);
              Page := pgFetch;
            end;
          end;
        pgList:
          begin
            if RS.Spec.AccountOnList and not Fetched and Fetch.Done then
            begin
              Fetched := True;
              ListRows;
              ShowServer;
            end;
            LiS.Memo.Values['Label11'] := StringReplace(Fetch.StatusLines, #10, #13#10,
              [rfReplaceAll]);
            if LiS.Memo.Values['Label11'] = '' then LiS.Memo.Values['Label11'] := Fetch.Status;
            if (((H <> nil) and (H.Name = 'Button1')) or (Pos(#13, Key) > 0)) and
              (LiS.Sel >= 0) and (LiS.Sel <= High(LiS.RowMap)) then
            begin
              Press(LiS, 'Button1');
              if RS.Spec.AccountOnList then Account(LiS) else Account(StS);
              Srv := Fetch.Servers[LiS.RowMap[LiS.Sel]];
              R.Choice := scOnline;
              R.Host := Srv.Host;
              R.Port := Srv.Port;
              R.ServerName := ServerDisplayName(Srv.Name);
              Result := True;
              Exit;
            end;
          end;
      end;
      { drawing }
      S.Fill($FF004000);
      if Page = pgList then P.BackPic := RS.ListBack else P.BackPic := RS.StartBack;
      S.Blit(P.BackPic, 0, 0, P.BackPic.Width, P.BackPic.Height, 0, 0);
      P.Paint(Form);
      if (Note <> '') and (Page <> pgList) then
        UiDrawText(S, 8, S.Height - UiLineH - 2, Note, ColWhite, ufRegular);
      if Page = pgFetch then
      begin
        { the short message window (TShortMessage), centred over the
          dialog, with its caption bar }
        Msg := RS.MsgForm;
        if Msg <> nil then
        begin
          B.W := Msg.Int('ClientWidth', Msg.Int('Width', 282) - 8);
          B.H := Msg.Int('ClientHeight', Msg.Int('Height', 127) - 27);
        end
        else
        begin
          B.W := 274;
          B.H := 93;
        end;
        B.X := (S.Width - B.W) div 2;
        B.Y := (S.Height - B.H - 19) div 2;
        Raised(S, B.X - 3, B.Y - 3, B.W + 6, B.H + 19 + 6);
        S.FillRect(B.X, B.Y, B.W, 18, $FF0A246A);
        UiDrawText(S, B.X + 4, B.Y + 1, RS.Text('ServerList-ShortMessageCaption',
          'Graal Server List'), ColWhite, ufBold);
        if Msg <> nil then
          S.FillRect(B.X, B.Y + 19, B.W, B.H, DfmColor(Msg.Str('Color', 'clBtnFace'), $FFD4D0C8))
        else
          S.FillRect(B.X, B.Y + 19, B.W, B.H, $FF008000);
        V := RS.Text('ServerList-ShortMessage2', 'Getting server list ...');
        if (Msg <> nil) and (Msg.Str('Color', 'clBtnFace') = 'clBtnFace') then
          UiDrawText(S, B.X + (B.W - UiTextWidth(V, ufRegular)) div 2, B.Y + 19 + 20, V,
            $FF000000, ufRegular)
        else
          UiDrawText(S, B.X + (B.W - UiTextWidth(V, ufRegular)) div 2, B.Y + 19 + 20, V,
            ColWhite, ufRegular);
      end;
      Win.Present(S);
      Sleep(20);
    end;
  finally
    TabPre.Free;
    Tabs.Free;
    LiS.Free;
    StS.Free;
    P.Free;
    S.Free;
  end;
end;

end.
