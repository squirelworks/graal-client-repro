{ GLaunch1x: the start dialog of the 1.x clients (1.1 to 1.41), drawn from
  the client's own form.

  Every 1.x Graal.exe opens one small Delphi form, TConnectFrame, captioned
  "Graal - The Adventure" and sized to its art; there is no bigger window
  behind it. The rebuild reads that form (RCDATA TCONNECTFRAME, compiled
  into each rebuild from its own exe by scripts/res/extract_1x.py) and
  draws it control by control: the pictures it carries (TImage), its
  labels, the mode, language and character drop-down lists, the nick
  name, server, port, account and password fields, the check box and the
  Start button, in the classic Windows look a Delphi 3 program has.

  What the form leaves to the program's code (which controls a mode shows,
  the panel's height, the default server and port) is set per build in a
  TLaunchConfig, from screenshots of each real client under Wine with every
  mode picked:

  - 1.1, 1.1.9: One Player shows no panel; One Player Online shows the
    panel (Nick Name, Server, Port); Two to Four Players show one more
    character list per player.
  - 1.28b2 to 1.39: One Player shows the panel's first row (Nick Name);
    One Player Online the whole panel (Server, Port, Account, Password,
    "Load head/colors from last session") and hides the credits picture;
    Two to Four Players hide the panel and show the extra character lists.
  - 1.41r1: the controls stay; Two to Four Players draw each player's head
    beside the character list (PaintBox1), and a click on a head picks the
    player the list is for.

  The character list is headsconfig.txt's: Name=head,gender,skin,coat,
  sleeves,shoes,belt; each entry is drawn with its head's front frame at
  half size, as the original's owner-drawn list (ComboBox1DrawItem) does. }
unit GLaunch1x;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow, GDfm1x;

type
  TLaunchStyle = (ls11, ls128, ls141);

  TLaunchConfig = record
    Style: TLaunchStyle;
    { the server field can be typed in (False: 1.1, greyed) }
    ServerEnabled: Boolean;
    DefServer: string;
    DefPort: Integer;
    { the mode picked at start: 0 One Player, 1 One Player Online }
    DefMode: Integer;
    { 1.41r1: the words come from <LangDir>language<Name>.txt
      (StartScreen=, StartScreen-Label1=, -ModeSelect-0= ...), for the
      language picked in the dialog; '' for the builds that keep the
      form's own words }
    LangDir: string;
  end;

  TCharEntry = record
    Name, Head, Gender: string;
    Colors: array[0..4] of Integer;
  end;
  TCharList = array of TCharEntry;

  { the front of head HeadFile, 32 x 32, or nil (the caller keeps it) }
  THeadIcon = function(const HeadFile: string): TGSurface of object;

  TStopCheckFn = function: Boolean;

  { The heads the character lists show, from an install in Dir: levels/
    heads/<head> (1.28b2 on), else column N of heads.gif for headN.gif
    (1.1, 1.1.9 keep every head in that one picture, 32 wide each). }
  THeadIcons = class
  private
    FDir: string;
    FNames: TStringList;
    FSheet: TGSurface;
    FSheetTried: Boolean;
  public
    constructor Create(const Dir: string);
    destructor Destroy; override;
    function Icon(const HeadFile: string): TGSurface;
  end;

  TLaunchResult = record
    Mode: Integer;            { 0 One Player, 1 Online, 2..4 that many players }
    Nickname, Server, Account, Password, Language: string;
    Port: Integer;
    LoadLast: Boolean;
    Chars: array[0..3] of Integer;
  end;

{ headsconfig.txt's lines as a list; an unknown colour is 0 (white). }
function ParseCharacters(const Text: string): TCharList;

{ Text of the install's file Path, else Default (what the exe carries). }
function InstallText(const Path, Default: string): string;
{ The languages the install has: language<Name>.txt next to the program,
  by name. }
function InstallLanguages(const Dir: string): TStringList;
{ A server address the player set next to the program: graalconfig.txt
  (serveraddr=HOST[:PORT], serverport=PORT), else listserver.txt (host,
  then port). Host and Port keep their values when there is none. }
procedure ServerOverride(const Dir: string; var Host: string; var Port: Integer);
{ graalconfig.txt's gamemode= (One Player, One Player Online, Two
  Players ...) as an index, else Default (1.41r1). }
function ConfigGameMode(const Dir: string; Default: Integer): Integer;
{ The Caption of a form, or Default. }
function FormCaption(const FormData, Default: string): string;

{ The client size of a form: its Width and Height less the frame Delphi
  counted at design time (4 + 4 across, 4 + 26 + 4 down). }
procedure FormClientSize(Form: TDfmObject; out W, H: Integer);

{ Runs the start dialog in Win (reshaped to the form's client size, titled
  with its caption) until Start; False when it is closed. R holds the
  fields at start (Nickname, Language) and the choice at the end. }
function RunLaunch1x(Win: TGWindow; const FormData: string; const Cfg: TLaunchConfig;
  const Chars: TCharList; HeadIcon: THeadIcon; Languages: TStrings;
  var R: TLaunchResult; StopRequested: TStopCheckFn = nil): Boolean;

implementation

uses
  SysUtils, GUiFont, GAssetDirs;

const
  { Windows' classic system colours (Windows 10 values), as an unthemed
    Delphi 3 form gets them }
  clBtnFace = $FFF0F0F0;
  clBtnShadow = $FFA0A0A0;
  cl3DDkShadow = $FF696969;
  cl3DLight = $FFE3E3E3;
  clBtnHighlight = $FFFFFFFF;
  clWindow = $FFFFFFFF;
  clWindowText = $FF000000;
  clHighlight = $FF0078D7;
  clHighlightText = $FFFFFFFF;
  clGrayText = $FF6D6D6D;
  clSilver = $FFC0C0C0;      { the character lists' face (ComboBox1DrawItem) }
  clListBorder = $FF646464;
  ArrowW = 17;               { a combo box's button, SM_CXVSCROLL }
  BoxSize = 13;              { a check box }

type
  TCtlKind = (ckOther, ckImage, ckLabel, ckButton, ckCombo, ckEdit, ckPanel, ckCheck, ckPaintBox);

  TCtl = class
    Obj: TDfmObject;
    Kind: TCtlKind;
    Name: string;
    X, Y, W, H: Integer;      { in the dialog }
    Visible, Enabled: Boolean;
    Parent: TCtl;
    { combo }
    Items: TStringList;
    Sel: Integer;
    OwnerDraw: Boolean;
    DropCount: Integer;
    { edit, label, button, check box }
    Text: string;
    Password: Boolean;
    Checked: Boolean;
    { label }
    Center, Wrap: Boolean;
    { image }
    Pic: TGSurface;
    Stretch: Boolean;
    TabOrder: Integer;
    destructor Destroy; override;
    function Shown: Boolean;
  end;

destructor TCtl.Destroy;
begin
  Items.Free;
  Pic.Free;
  inherited Destroy;
end;

function TCtl.Shown: Boolean;
begin
  Result := Visible and ((Parent = nil) or Parent.Shown);
end;

function ColorByName(const S: string): Integer;
const
  Names: array[0..19] of string = (
    'white', 'yellow', 'orange', 'pink', 'red', 'darkred', 'lightgreen',
    'green', 'darkgreen', 'lightblue', 'blue', 'darkblue', 'brown',
    'cynober', 'purple', 'darkpurple', 'lightgray', 'gray', 'black',
    'transparent');
var
  I: Integer;
begin
  for I := 0 to High(Names) do
    if SameText(Names[I], Trim(S)) then
    begin
      Result := I;
      Exit;
    end;
  Result := 0;
end;

function ParseCharacters(const Text: string): TCharList;
var
  L, F: TStringList;
  I, J, N, E: Integer;
  Line: string;
begin
  Result := nil;
  L := TStringList.Create;
  F := TStringList.Create;
  try
    L.Text := Text;
    N := 0;
    for I := 0 to L.Count - 1 do
    begin
      Line := Trim(L[I]);
      E := Pos('=', Line);
      if E <= 1 then Continue;
      F.CommaText := '"' + StringReplace(Copy(Line, E + 1, MaxInt), ',', '","', [rfReplaceAll]) + '"';
      SetLength(Result, N + 1);
      Result[N].Name := Copy(Line, 1, E - 1);
      if F.Count > 0 then Result[N].Head := Trim(F[0]);
      if F.Count > 1 then Result[N].Gender := Trim(F[1]);
      for J := 0 to 4 do
        if F.Count > J + 2 then Result[N].Colors[J] := ColorByName(F[J + 2])
        else Result[N].Colors[J] := 0;
      Inc(N);
    end;
  finally
    F.Free;
    L.Free;
  end;
end;

procedure FormClientSize(Form: TDfmObject; out W, H: Integer);
begin
  if Form.Has('ClientWidth') then W := Form.Int('ClientWidth', 433)
  else W := Form.Int('Width', 441) - 8;
  if Form.Has('ClientHeight') then H := Form.Int('ClientHeight', 315)
  else H := Form.Int('Height', 349) - 34;
end;

function InstallText(const Path, Default: string): string;
var
  F: TFileStream;
begin
  Result := Default;
  if not FileExists(Path) then Exit;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    Result := Default;
  end;
end;

function InstallLanguages(const Dir: string): TStringList;
var
  SR: TSearchRec;
  N: string;
begin
  Result := TStringList.Create;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      N := SR.Name;
      if SameText(Copy(N, 1, 8), 'language') and SameText(ExtractFileExt(N), '.txt') then
        Result.Add(Copy(N, 9, Length(N) - 12));
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  Result.Sort;
end;

procedure ServerOverride(const Dir: string; var Host: string; var Port: Integer);
var
  L: TStringList;
  I, C: Integer;
  D, Line, Key, Value: string;
begin
  D := IncludeTrailingPathDelimiter(Dir);
  L := TStringList.Create;
  try
    if FileExists(D + 'graalconfig.txt') then
    begin
      L.LoadFromFile(D + 'graalconfig.txt');
      for I := 0 to L.Count - 1 do
      begin
        Line := Trim(L[I]);
        C := Pos('=', Line);
        if C = 0 then Continue;
        Key := LowerCase(Trim(Copy(Line, 1, C - 1)));
        Value := Trim(Copy(Line, C + 1, MaxInt));
        if Value = '' then Continue;
        if Key = 'serveraddr' then
        begin
          C := Pos(':', Value);
          if C > 0 then
          begin
            Port := StrToIntDef(Copy(Value, C + 1, MaxInt), Port);
            Value := Copy(Value, 1, C - 1);
          end;
          Host := Value;
        end
        else if Key = 'serverport' then
          Port := StrToIntDef(Value, Port);
      end;
    end
    else if FileExists(D + 'listserver.txt') then
    begin
      L.LoadFromFile(D + 'listserver.txt');
      if (L.Count > 0) and (Trim(L[0]) <> '') then Host := Trim(L[0]);
      if L.Count > 1 then Port := StrToIntDef(Trim(L[1]), Port);
    end;
  finally
    L.Free;
  end;
end;

function ConfigGameMode(const Dir: string; Default: Integer): Integer;
const
  Modes: array[0..4] of string = ('One Player', 'One Player Online', 'Two Players',
    'Three Players', 'Four Players');
var
  L: TStringList;
  I: Integer;
  V: string;
begin
  Result := Default;
  if not FileExists(IncludeTrailingPathDelimiter(Dir) + 'graalconfig.txt') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + 'graalconfig.txt');
    V := Trim(L.Values['gamemode']);
    for I := 0 to High(Modes) do
      if SameText(V, Modes[I]) then Result := I;
  finally
    L.Free;
  end;
end;

function FormCaption(const FormData, Default: string): string;
var
  F: TDfmObject;
begin
  Result := Default;
  F := ReadDfm(FormData);
  if F <> nil then
  try
    Result := F.Str('Caption', Default);
  finally
    F.Free;
  end;
end;

{ A .bmp file as Delphi keeps it in a form: uncompressed, 1, 4, 8, 24 or
  32 bits a pixel, bottom-up or top-down. }
function DecodeBmp(const S: string; Dest: TGSurface): Boolean;

  function LE(P, N: Integer): Integer;
  var
    K: Integer;
  begin
    Result := 0;
    for K := N - 1 downto 0 do Result := (Result shl 8) or Ord(S[P + K]);
  end;

var
  Off, HdrSize, W, H, Bpp, Comp, Stride, X, Y, P, Idx, NPal, K: Integer;
  Pal: array[0..255] of Cardinal;
  BottomUp: Boolean;
begin
  Result := False;
  if (Length(S) < 54) or (Copy(S, 1, 2) <> 'BM') then Exit;
  Off := LE(11, 4);
  HdrSize := LE(15, 4);
  W := LE(19, 4);
  H := LE(23, 4);
  if H > $7FFFFFFF - 1 then H := H - Integer($100000000);
  Bpp := LE(29, 2);
  Comp := LE(31, 4);
  if (Comp <> 0) or (W <= 0) or (W > 4096) then Exit;
  BottomUp := H > 0;
  H := Abs(H);
  if (H = 0) or (H > 4096) then Exit;
  NPal := LE(47, 4);
  if (NPal = 0) and (Bpp <= 8) then NPal := 1 shl Bpp;
  if NPal > 256 then NPal := 256;
  FillChar(Pal, SizeOf(Pal), 0);
  for K := 0 to NPal - 1 do
  begin
    P := 15 + HdrSize + K * 4;
    if P + 3 > Length(S) then Break;
    Pal[K] := $FF000000 or (Cardinal(Ord(S[P + 2])) shl 16) or
      (Cardinal(Ord(S[P + 1])) shl 8) or Cardinal(Ord(S[P]));
  end;
  Stride := ((W * Bpp + 31) div 32) * 4;
  if Off + Stride * H > Length(S) then Exit;
  Dest.SetSize(W, H);
  for Y := 0 to H - 1 do
  begin
    if BottomUp then P := Off + 1 + (H - 1 - Y) * Stride
    else P := Off + 1 + Y * Stride;
    for X := 0 to W - 1 do
    begin
      case Bpp of
        1: Idx := (Ord(S[P + X div 8]) shr (7 - X mod 8)) and 1;
        4: Idx := (Ord(S[P + X div 2]) shr (4 * (1 - X mod 2))) and 15;
        8: Idx := Ord(S[P + X]);
        24, 32:
          begin
            K := P + X * (Bpp div 8);
            Dest.Pixels[X + Y * W] := $FF000000 or (Cardinal(Ord(S[K + 2])) shl 16) or
              (Cardinal(Ord(S[K + 1])) shl 8) or Cardinal(Ord(S[K]));
            Continue;
          end;
      else
        Exit;
      end;
      Dest.Pixels[X + Y * W] := Pal[Idx];
    end;
  end;
  Result := True;
end;

{ ---- heads ---- }

constructor THeadIcons.Create(const Dir: string);
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(Dir);
  FNames := TStringList.Create;
end;

destructor THeadIcons.Destroy;
var
  I: Integer;
begin
  for I := 0 to FNames.Count - 1 do FNames.Objects[I].Free;
  FNames.Free;
  FSheet.Free;
  inherited Destroy;
end;

function THeadIcons.Icon(const HeadFile: string): TGSurface;
var
  I, N: Integer;
  Img: TGSurface;
  Base, F, Ext: string;
  Found: Boolean;
begin
  I := FNames.IndexOf(LowerCase(HeadFile));
  if I >= 0 then
  begin
    Result := TGSurface(FNames.Objects[I]);
    Exit;
  end;
  Result := nil;
  Img := TGSurface.Create(0, 0);
  Found := False;
  Base := ChangeFileExt(HeadFile, '');
  for Ext in ['.gif', '.png', '.mng'] do
  begin
    { LevelSibling: FDir + name, or under a shared root this build's copy }
    for F in [LevelSibling(FDir, 'levels/heads/' + Base + Ext),
      LevelSibling(FDir, 'levels/' + Base + Ext), LevelSibling(FDir, Base + Ext)] do
      if FileExists(F) and LoadImageFile(F, Img) and (Img.Height >= 96) then
      begin
        Found := True;
        Break;
      end;
    if Found then Break;
  end;
  if Found then
  begin
    { the front: the third 32 x 32 frame }
    Result := TGSurface.Create(32, 32);
    Result.Fill(0);
    Result.Blit(Img, 0, 64, 32, 32, 0, 0);
  end
  else
  begin
    if not FSheetTried then
    begin
      FSheetTried := True;
      FSheet := TGSurface.Create(0, 0);
      F := LevelSibling(FDir, 'heads.gif');
      if not ((F <> '') and LoadImageFile(F, FSheet)) then
        FreeAndNil(FSheet);
    end;
    N := StrToIntDef(Copy(Base, 5, MaxInt), -1);
    if (FSheet <> nil) and SameText(Copy(Base, 1, 4), 'head') and (N >= 0) and
      ((N + 1) * 32 <= FSheet.Width) then
    begin
      Result := TGSurface.Create(32, 32);
      Result.Fill(0);
      Result.Blit(FSheet, N * 32, 64, 32, 32, 0, 0);
    end;
  end;
  Img.Free;
  FNames.AddObject(LowerCase(HeadFile), Result);
end;

{ ---- drawing helpers ---- }

procedure HLine(S: TGSurface; X, Y, W: Integer; C: Cardinal);
begin
  S.FillRect(X, Y, W, 1, C);
end;

procedure VLine(S: TGSurface; X, Y, H: Integer; C: Cardinal);
begin
  S.FillRect(X, Y, 1, H, C);
end;

procedure Edge(S: TGSurface; X, Y, W, H: Integer; TL, BR: Cardinal);
begin
  HLine(S, X, Y, W - 1, TL);
  VLine(S, X, Y, H - 1, TL);
  HLine(S, X, Y + H - 1, W, BR);
  VLine(S, X + W - 1, Y, H, BR);
end;

procedure Sunken(S: TGSurface; X, Y, W, H: Integer);
begin
  Edge(S, X, Y, W, H, clBtnShadow, clBtnHighlight);
  Edge(S, X + 1, Y + 1, W - 2, H - 2, cl3DDkShadow, cl3DLight);
end;

procedure Raised(S: TGSurface; X, Y, W, H: Integer);
begin
  Edge(S, X, Y, W, H, cl3DLight, cl3DDkShadow);
  Edge(S, X + 1, Y + 1, W - 2, H - 2, clBtnHighlight, clBtnShadow);
end;

{ the text with '&' marks taken out; U: the index of the underlined
  character, 0 for none }
function StripAmp(const S: string; out U: Integer): string;
var
  I: Integer;
begin
  Result := '';
  U := 0;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      Inc(I);
      if I > Length(S) then Break;
      if S[I] <> '&' then U := Length(Result) + 1;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

procedure TextAt(S: TGSurface; X, Y: Integer; const T: string; C: Cardinal);
begin
  UiDrawText(S, X, Y, T, C, ufRegular);
end;

procedure AmpText(S: TGSurface; X, Y: Integer; const T: string; C: Cardinal);
var
  U, UX: Integer;
  P: string;
begin
  P := StripAmp(T, U);
  TextAt(S, X, Y, P, C);
  if U > 0 then
  begin
    UX := X + UiTextWidth(Copy(P, 1, U - 1), ufRegular);
    HLine(S, UX, Y + 14, UiTextWidth(P[U], ufRegular) - 1, C);
  end;
end;

{ the words of T broken into lines no wider than W }
function WrapLines(const T: string; W: Integer): TStringList;
var
  Words: TStringList;
  Line, Try_: string;
  I: Integer;
begin
  Result := TStringList.Create;
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := T;
    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      if Line = '' then Try_ := Words[I] else Try_ := Line + ' ' + Words[I];
      if (Line <> '') and (UiTextWidth(Try_, ufRegular) > W) then
      begin
        Result.Add(Line);
        Line := Words[I];
      end
      else
        Line := Try_;
    end;
    if Line <> '' then Result.Add(Line);
  finally
    Words.Free;
  end;
end;

procedure DownArrow(S: TGSurface; CX, CY: Integer; C: Cardinal);
var
  I: Integer;
begin
  { 7 wide, 4 tall }
  for I := 0 to 3 do HLine(S, CX - 3 + I, CY - 1 + I, 7 - 2 * I, C);
end;

{ the small head an owner-drawn character list shows: the 32 x 32 front
  at half size }
procedure SmallHead(S: TGSurface; Img: TGSurface; X, Y: Integer);
var
  I, J: Integer;
  C: Cardinal;
begin
  if Img = nil then Exit;
  for J := 0 to 15 do
    for I := 0 to 15 do
    begin
      C := Img.GetPixel(I * 2, J * 2);
      if (C shr 24) <> 0 then S.FillRect(X + I, Y + J, 1, 1, C);
    end;
end;

{ ---- the dialog ---- }

type
  TLaunch = class
    Form: TDfmObject;
    Cfg: TLaunchConfig;
    Ctls: TList;
    Chars: TCharList;
    HeadIcon: THeadIcon;
    Focus: TCtl;          { the control with the keyboard }
    Open: TCtl;           { the combo whose list is down }
    Top_: Integer;        { first row shown in the open list }
    Player: Integer;      { 1.41r1: the player the character list is for }
    PlayerChars: array[0..3] of Integer;
    CW, CH: Integer;
    Caption: string;
    destructor Destroy; override;
    procedure Build;
    procedure AddCtl(O: TDfmObject; Parent: TCtl; OX, OY: Integer);
    function Ctl(const N: string): TCtl;
    function Mode: Integer;
    procedure Layout;
    procedure Draw(S: TGSurface);
    procedure DrawCtl(S: TGSurface; C: TCtl);
    procedure DrawCharItem(S: TGSurface; X, Y, W: Integer; Index: Integer; Back, Fore: Cardinal);
    procedure DrawList(S: TGSurface);
    function ListRect(C: TCtl; out X, Y, W, H, Rows: Integer): Boolean;
    function Click(X, Y: Integer): Boolean;   { True: Start }
    function Keys(const Chars_: string; Win: TGWindow): Boolean;
    function HitCtl(X, Y: Integer): TCtl;
    procedure SetSel(C: TCtl; I: Integer);
    procedure ApplyLanguage;
    function CharFace: Cardinal;
    procedure FocusNext(Back: Boolean);
  end;

destructor TLaunch.Destroy;
var
  I: Integer;
begin
  if Ctls <> nil then
    for I := 0 to Ctls.Count - 1 do TCtl(Ctls[I]).Free;
  Ctls.Free;
  inherited Destroy;
end;

function TLaunch.Ctl(const N: string): TCtl;
var
  I: Integer;
begin
  for I := 0 to Ctls.Count - 1 do
    if SameText(TCtl(Ctls[I]).Name, N) then
    begin
      Result := TCtl(Ctls[I]);
      Exit;
    end;
  Result := nil;
end;

procedure TLaunch.AddCtl(O: TDfmObject; Parent: TCtl; OX, OY: Integer);
var
  C: TCtl;
  Cls, D, Bmp: string;
  I: Integer;
  K: Cardinal;
begin
  C := TCtl.Create;
  Ctls.Add(C);
  C.Obj := O;
  C.Name := O.Name;
  C.Parent := Parent;
  C.X := OX + O.Int('Left', 0);
  C.Y := OY + O.Int('Top', 0);
  C.W := O.Int('Width', 0);
  C.H := O.Int('Height', 0);
  C.Visible := O.Bool('Visible', True);
  C.Enabled := O.Bool('Enabled', True);
  C.TabOrder := O.Int('TabOrder', 0);
  Cls := O.ClassName_;
  C.Text := O.Str('Caption', O.Str('Text', ''));
  if Cls = 'TImage' then
  begin
    C.Kind := ckImage;
    C.Stretch := O.Bool('Stretch', False);
    if O.Binary('Picture.Data', D) and DfmPictureBmp(D, Bmp) then
    begin
      C.Pic := TGSurface.Create(0, 0);
      if not DecodeBmp(Bmp, C.Pic) then FreeAndNil(C.Pic)
      else
      begin
        if O.Bool('AutoSize', False) then
        begin
          C.W := C.Pic.Width;
          C.H := C.Pic.Height;
        end;
        { Transparent: the colour of the bottom left pixel is not drawn
          (TBitmap's TransparentColor) }
        if O.Bool('Transparent', False) and (C.Pic.Height > 0) then
        begin
          K := C.Pic.GetPixel(0, C.Pic.Height - 1);
          for I := 0 to High(C.Pic.Pixels) do
            if C.Pic.Pixels[I] = K then C.Pic.Pixels[I] := 0;
        end;
      end;
    end;
  end
  else if Cls = 'TLabel' then
  begin
    C.Kind := ckLabel;
    C.Center := O.Str('Alignment', '') = 'taCenter';
    C.Wrap := O.Bool('WordWrap', False);
  end
  else if Cls = 'TButton' then C.Kind := ckButton
  else if Cls = 'TComboBox' then
  begin
    C.Kind := ckCombo;
    C.Items := O.List('Items.Strings');
    C.OwnerDraw := Pos('OwnerDraw', O.Str('Style', '')) > 0;
    C.DropCount := O.Int('DropDownCount', 8);
    C.Sel := -1;
    C.Text := O.Str('Text', '');
  end
  else if Cls = 'TEdit' then
  begin
    C.Kind := ckEdit;
    C.Password := O.Has('PasswordChar');
  end
  else if Cls = 'TPanel' then C.Kind := ckPanel
  else if Cls = 'TCheckBox' then
  begin
    C.Kind := ckCheck;
    C.Checked := O.Bool('Checked', False);
  end
  else if Cls = 'TPaintBox' then C.Kind := ckPaintBox
  else C.Kind := ckOther;
  for I := 0 to O.ChildCount - 1 do
    AddCtl(O.Children[I], C, C.X, C.Y);
end;

procedure TLaunch.Build;
var
  I: Integer;
begin
  Ctls := TList.Create;
  FormClientSize(Form, CW, CH);
  for I := 0 to Form.ChildCount - 1 do
    AddCtl(Form.Children[I], nil, 0, 0);
end;

function TLaunch.Mode: Integer;
var
  M: TCtl;
begin
  M := Ctl('ModeSelect');
  if (M <> nil) and (M.Sel >= 0) then Result := M.Sel else Result := 0;
end;

{ what the program's ModeSelectChange does, per build }
procedure TLaunch.Layout;
var
  M, I: Integer;
  P, E, Cr: TCtl;
begin
  M := Mode;
  P := Ctl('Panel1');
  Cr := Ctl('Image2');
  case Cfg.Style of
    ls11, ls128:
      begin
        for I := 2 to 4 do
          if Ctl('ComboBox' + IntToStr(I)) <> nil then
            Ctl('ComboBox' + IntToStr(I)).Visible := M >= I;
        if P <> nil then
        begin
          P.Visible := (M = 1) or ((M = 0) and (Cfg.Style = ls128));
          P.H := P.Obj.Int('Height', 0);
          { One Player: only the Nick Name row }
          E := Ctl('Edit3');
          if (M = 0) and (E <> nil) then P.H := (E.Y - P.Y) + E.H + 8;
        end;
        { the credits picture gives way to the whole panel }
        if (Cfg.Style = ls128) and (Cr <> nil) then Cr.Visible := M <> 1;
      end;
    ls141:
      if (M < 2) or (Player >= M) then
      begin
        Player := 0;
        E := Ctl('characterbox');
        if E <> nil then E.Sel := PlayerChars[0];
      end;
  end;
end;

function TLaunch.HitCtl(X, Y: Integer): TCtl;
var
  I: Integer;
  C: TCtl;
begin
  Result := nil;
  for I := Ctls.Count - 1 downto 0 do
  begin
    C := TCtl(Ctls[I]);
    if not C.Shown or not (C.Kind in [ckButton, ckCombo, ckEdit, ckCheck, ckPaintBox]) then Continue;
    if (X >= C.X) and (Y >= C.Y) and (X < C.X + C.W) and (Y < C.Y + C.H) then
    begin
      Result := C;
      Exit;
    end;
  end;
end;

function TLaunch.ListRect(C: TCtl; out X, Y, W, H, Rows: Integer): Boolean;
var
  N: Integer;
begin
  Result := (C <> nil) and (C.Kind = ckCombo) and (C.Items <> nil) and (C.Items.Count > 0);
  if not Result then Exit;
  N := C.Items.Count;
  Rows := N;
  if Rows > C.DropCount then Rows := C.DropCount;
  X := C.X;
  Y := C.Y + C.H;
  W := C.W;
  H := Rows * 16 + 2;
  { no room below: above the box }
  if Y + H > CH then Y := C.Y - H;
end;

{ the character lists' face: silver up to 1.39 (ComboBox1DrawItem fills
  with clSilver), the window colour in 1.41 }
function TLaunch.CharFace: Cardinal;
begin
  if Cfg.Style = ls141 then Result := clWindow else Result := clSilver;
end;

procedure TLaunch.ApplyLanguage;
var
  L: TStringList;
  Box, C: TCtl;
  I: Integer;
  V: string;
begin
  if Cfg.LangDir = '' then Exit;
  Box := Ctl('languagebox');
  if (Box = nil) or (Box.Sel < 0) then Exit;
  if not FileExists(Cfg.LangDir + 'language' + Box.Items[Box.Sel] + '.txt') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(Cfg.LangDir + 'language' + Box.Items[Box.Sel] + '.txt');
    V := Trim(L.Values['StartScreen']);
    if V <> '' then Caption := V;
    for I := 0 to Ctls.Count - 1 do
    begin
      C := TCtl(Ctls[I]);
      if C.Kind in [ckLabel, ckButton, ckCheck] then
      begin
        V := L.Values['StartScreen-' + C.Name];
        if Trim(V) <> '' then C.Text := V;
      end;
    end;
    C := Ctl('ModeSelect');
    if C <> nil then
      for I := 0 to C.Items.Count - 1 do
      begin
        V := L.Values['StartScreen-ModeSelect-' + IntToStr(I)];
        if Trim(V) <> '' then C.Items[I] := V;
      end;
  finally
    L.Free;
  end;
end;

procedure TLaunch.SetSel(C: TCtl; I: Integer);
begin
  if (C.Items = nil) or (C.Items.Count = 0) then Exit;
  if I < 0 then I := 0;
  if I >= C.Items.Count then I := C.Items.Count - 1;
  C.Sel := I;
  if (Cfg.Style = ls141) and SameText(C.Name, 'characterbox') then PlayerChars[Player] := I;
  if SameText(C.Name, 'ModeSelect') then Layout;
  if SameText(C.Name, 'languagebox') then ApplyLanguage;
end;

function TLaunch.Click(X, Y: Integer): Boolean;
var
  LX, LY, LW, LH, Rows, Row, I: Integer;
  C, B: TCtl;
begin
  Result := False;
  if Open <> nil then
  begin
    if ListRect(Open, LX, LY, LW, LH, Rows) and (X >= LX) and (X < LX + LW) and
      (Y >= LY) and (Y < LY + LH) then
    begin
      Row := (Y - LY - 1) div 16;
      if (Open.Items.Count > Rows) and (X >= LX + LW - 1 - ArrowW) then
      begin
        { the scroll bar: the upper half up a page, the lower half down }
        if Y < LY + LH div 2 then Dec(Top_, Rows) else Inc(Top_, Rows);
        if Top_ > Open.Items.Count - Rows then Top_ := Open.Items.Count - Rows;
        if Top_ < 0 then Top_ := 0;
        Exit;
      end;
      if (Row >= 0) and (Row < Rows) then SetSel(Open, Top_ + Row);
    end;
    Open := nil;
    Exit;
  end;
  C := HitCtl(X, Y);
  if C = nil then Exit;
  if not C.Enabled then Exit;
  case C.Kind of
    ckButton:
      begin
        Focus := C;
        Result := True;
      end;
    ckCombo:
      begin
        Focus := C;
        Open := C;
        if ListRect(C, LX, LY, LW, LH, Rows) then
        begin
          Top_ := C.Sel - Rows div 2;
          if Top_ > C.Items.Count - Rows then Top_ := C.Items.Count - Rows;
          if Top_ < 0 then Top_ := 0;
        end
        else
          Open := nil;
      end;
    ckEdit: Focus := C;
    ckCheck:
      begin
        Focus := C;
        C.Checked := not C.Checked;
      end;
    ckPaintBox:
      { 1.41r1: a click on a player's head picks the player the character
        list is for }
      if Mode >= 2 then
      begin
        I := (X - C.X) div 16;
        if (I >= 0) and (I < Mode) then
        begin
          Player := I;
          B := Ctl('characterbox');
          if B <> nil then B.Sel := PlayerChars[I];
        end;
      end;
  end;
end;

procedure TLaunch.FocusNext(Back: Boolean);
var
  L: TList;
  I, J, K: Integer;
  C: TCtl;
begin
  L := TList.Create;
  try
    for I := 0 to Ctls.Count - 1 do
    begin
      C := TCtl(Ctls[I]);
      if C.Shown and C.Enabled and (C.Kind in [ckButton, ckCombo, ckEdit, ckCheck]) then
        L.Add(C);
    end;
    if L.Count = 0 then Exit;
    { tab order: by TabOrder within the form, panels' controls in place }
    for I := 1 to L.Count - 1 do
      for J := I downto 1 do
      begin
        K := TCtl(L[J - 1]).TabOrder;
        if (TCtl(L[J - 1]).Parent <> nil) then K := TCtl(L[J - 1]).Parent.TabOrder * 100 + K
        else K := K * 100;
        C := TCtl(L[J]);
        if C.Parent <> nil then
        begin
          if C.Parent.TabOrder * 100 + C.TabOrder < K then L.Exchange(J, J - 1);
        end
        else if C.TabOrder * 100 < K then L.Exchange(J, J - 1);
      end;
    I := L.IndexOf(Focus);
    if Back then Dec(I) else Inc(I);
    if I < 0 then I := L.Count - 1;
    if I >= L.Count then I := 0;
    Focus := TCtl(L[I]);
  finally
    L.Free;
  end;
end;

function TLaunch.Keys(const Chars_: string; Win: TGWindow): Boolean;
var
  I: Integer;
  Ch: Char;
  LX, LY, LW, LH, Rows: Integer;
begin
  Result := False;
  { arrows move through a focused or open list }
  if (Focus <> nil) and (Focus.Kind = ckCombo) then
  begin
    if Win.WasPressed(gkDown) then
    begin
      SetSel(Focus, Focus.Sel + 1);
      if (Open = Focus) and ListRect(Open, LX, LY, LW, LH, Rows) and (Focus.Sel >= Top_ + Rows) then
        Top_ := Focus.Sel - Rows + 1;
    end;
    if Win.WasPressed(gkUp) then
    begin
      SetSel(Focus, Focus.Sel - 1);
      if (Open = Focus) and (Focus.Sel < Top_) then Top_ := Focus.Sel;
    end;
  end;
  for I := 1 to Length(Chars_) do
  begin
    Ch := Chars_[I];
    case Ch of
      #13:
        if Open <> nil then Open := nil
        else
        begin
          Result := True;
          Exit;
        end;
      #27: Open := nil;
      #9: begin Open := nil; FocusNext(False); end;
      #8:
        if (Focus <> nil) and (Focus.Kind = ckEdit) and (Focus.Text <> '') then
          Delete(Focus.Text, Length(Focus.Text), 1);
      ' ':
        if (Focus <> nil) and (Focus.Kind = ckCheck) then Focus.Checked := not Focus.Checked
        else if (Focus <> nil) and (Focus.Kind = ckEdit) then Focus.Text := Focus.Text + Ch;
    else
      if (Ch >= ' ') and (Focus <> nil) and (Focus.Kind = ckEdit) and (Length(Focus.Text) < 64) then
        Focus.Text := Focus.Text + Ch;
    end;
  end;
end;

procedure TLaunch.DrawCharItem(S: TGSurface; X, Y, W: Integer; Index: Integer; Back, Fore: Cardinal);
var
  Img: TGSurface;
begin
  S.FillRect(X, Y, W, 16, Back);
  if (Index < 0) or (Index > High(Chars)) then Exit;
  Img := nil;
  if Assigned(HeadIcon) then Img := HeadIcon(Chars[Index].Head);
  SmallHead(S, Img, X + 2, Y);
  TextAt(S, X + 22, Y, Chars[Index].Name, Fore);
end;

procedure TLaunch.DrawCtl(S: TGSurface; C: TCtl);
var
  T: string;
  L: TStringList;
  I, TX, TY, FW: Integer;
  Fore: Cardinal;
  Img: TGSurface;
begin
  case C.Kind of
    ckImage:
      if C.Pic <> nil then
      begin
        if C.Stretch and ((C.W <> C.Pic.Width) or (C.H <> C.Pic.Height)) and (C.W > 0) and (C.H > 0) then
        begin
          for TY := 0 to C.H - 1 do
            for TX := 0 to C.W - 1 do
            begin
              Fore := C.Pic.GetPixel(TX * C.Pic.Width div C.W, TY * C.Pic.Height div C.H);
              if (Fore shr 24) <> 0 then S.FillRect(C.X + TX, C.Y + TY, 1, 1, Fore);
            end;
        end
        else
          S.Blit(C.Pic, 0, 0, C.Pic.Width, C.Pic.Height, C.X, C.Y);
      end;
    ckLabel:
      if C.Wrap then
      begin
        L := WrapLines(StripAmp(C.Text, I), C.W);
        try
          for I := 0 to L.Count - 1 do
          begin
            if C.Center then TX := C.X + (C.W - UiTextWidth(L[I], ufRegular)) div 2
            else TX := C.X;
            TextAt(S, TX, C.Y + I * 16, L[I], clWindowText);
          end;
        finally
          L.Free;
        end;
      end
      else
        AmpText(S, C.X, C.Y, C.Text, clWindowText);
    ckPanel:
      begin
        S.FillRect(C.X, C.Y, C.W, C.H, clBtnFace);
        Edge(S, C.X, C.Y, C.W, C.H, clBtnHighlight, clBtnShadow);
      end;
    ckButton:
      begin
        S.FillRect(C.X, C.Y, C.W, C.H, clBtnFace);
        if Focus = C then
        begin
          { the default button: a black frame round the raised face }
          Edge(S, C.X, C.Y, C.W, C.H, clWindowText, clWindowText);
          Raised(S, C.X + 1, C.Y + 1, C.W - 2, C.H - 2);
        end
        else
          Raised(S, C.X, C.Y, C.W, C.H);
        T := StripAmp(C.Text, I);
        TX := C.X + (C.W - UiTextWidth(T, ufRegular)) div 2;
        TY := C.Y + (C.H - 16) div 2;
        AmpText(S, TX, TY, C.Text, clWindowText);
        if Focus = C then
          { the dotted focus frame }
          for I := 0 to C.W - 9 do
            if I mod 2 = 0 then
            begin
              S.FillRect(C.X + 4 + I, C.Y + 4, 1, 1, clWindowText);
              S.FillRect(C.X + 4 + I, C.Y + C.H - 5, 1, 1, clWindowText);
            end;
      end;
    ckEdit:
      begin
        { a disabled TEdit keeps its colour; only the text greys }
        S.FillRect(C.X, C.Y, C.W, C.H, clWindow);
        Sunken(S, C.X, C.Y, C.W, C.H);
        T := C.Text;
        if C.Password then T := StringOfChar('*', Length(T));
        if C.Enabled then Fore := clWindowText else Fore := clGrayText;
        TextAt(S, C.X + 4, C.Y + (C.H - 16) div 2, T, Fore);
        if Focus = C then
          VLine(S, C.X + 4 + UiTextWidth(T, ufRegular), C.Y + (C.H - 16) div 2 + 1, 14, clWindowText);
      end;
    ckCheck:
      begin
        TY := C.Y + (C.H - BoxSize) div 2;
        S.FillRect(C.X, TY, BoxSize, BoxSize, clWindow);
        Sunken(S, C.X, TY, BoxSize, BoxSize);
        if C.Checked then
          for I := 0 to 6 do
          begin
            if I < 2 then FW := 4 + I else FW := 6 - (I - 2);
            S.FillRect(C.X + 3 + I, TY + FW, 1, 3, clWindowText);
          end;
        AmpText(S, C.X + BoxSize + 4, C.Y + (C.H - 16) div 2, C.Text, clWindowText);
      end;
    ckCombo:
      begin
        if C.OwnerDraw then S.FillRect(C.X, C.Y, C.W, C.H, CharFace)
        else if C.Enabled then S.FillRect(C.X, C.Y, C.W, C.H, clWindow)
        else S.FillRect(C.X, C.Y, C.W, C.H, clBtnFace);
        Sunken(S, C.X, C.Y, C.W, C.H);
        { the button }
        FW := C.W - 4 - ArrowW;
        S.FillRect(C.X + 2 + FW, C.Y + 2, ArrowW, C.H - 4, clBtnFace);
        Raised(S, C.X + 2 + FW, C.Y + 2, ArrowW, C.H - 4);
        if C.Enabled then Fore := clWindowText else Fore := clGrayText;
        DownArrow(S, C.X + 2 + FW + ArrowW div 2, C.Y + C.H div 2, Fore);
        TY := C.Y + (C.H - 16) div 2;
        if C.OwnerDraw then
          DrawCharItem(S, C.X + 3, TY, FW - 2, C.Sel, CharFace, clWindowText)
        else
        begin
          if (C.Sel >= 0) and (C.Sel < C.Items.Count) then T := C.Items[C.Sel] else T := C.Text;
          if (Focus = C) and (Open = nil) then
          begin
            S.FillRect(C.X + 3, TY, FW - 2, 16, clHighlight);
            TextAt(S, C.X + 4, TY, T, clHighlightText);
          end
          else
          begin
            if C.Enabled then Fore := clWindowText else Fore := clGrayText;
            TextAt(S, C.X + 4, TY, T, Fore);
          end;
        end;
      end;
    ckPaintBox:
      { 1.41r1: each player's head, Two to Four Players }
      if Mode >= 2 then
        for I := 0 to Mode - 1 do
        begin
          Img := nil;
          if Assigned(HeadIcon) and (PlayerChars[I] >= 0) and (PlayerChars[I] <= High(Chars)) then
            Img := HeadIcon(Chars[PlayerChars[I]].Head);
          SmallHead(S, Img, C.X + I * 16, C.Y);
        end;
  end;
end;

procedure TLaunch.DrawList(S: TGSurface);
var
  LX, LY, LW, LH, Rows, I, Idx, IW: Integer;
  Back, Fore: Cardinal;
begin
  if not ListRect(Open, LX, LY, LW, LH, Rows) then Exit;
  S.FillRect(LX, LY, LW, LH, clWindow);
  Edge(S, LX, LY, LW, LH, clListBorder, clListBorder);
  IW := LW - 2;
  if Open.Items.Count > Rows then
  begin
    Dec(IW, ArrowW);
    { the scroll bar: two buttons and the thumb }
    S.FillRect(LX + 1 + IW, LY + 1, ArrowW, LH - 2, cl3DLight);
    S.FillRect(LX + 1 + IW, LY + 1, ArrowW, ArrowW, clBtnFace);
    Raised(S, LX + 1 + IW, LY + 1, ArrowW, ArrowW);
    S.FillRect(LX + 1 + IW, LY + LH - 1 - ArrowW, ArrowW, ArrowW, clBtnFace);
    Raised(S, LX + 1 + IW, LY + LH - 1 - ArrowW, ArrowW, ArrowW);
    DownArrow(S, LX + 1 + IW + ArrowW div 2, LY + LH - 1 - ArrowW div 2 - 1, clWindowText);
    for I := 0 to 3 do
      HLine(S, LX + 1 + IW + ArrowW div 2 - I, LY + 1 + ArrowW div 2 - 2 + I, 2 * I + 1, clWindowText);
    Idx := (LH - 2 - 2 * ArrowW - ArrowW) * Top_ div (Open.Items.Count - Rows);
    S.FillRect(LX + 1 + IW, LY + 1 + ArrowW + Idx, ArrowW, ArrowW, clBtnFace);
    Raised(S, LX + 1 + IW, LY + 1 + ArrowW + Idx, ArrowW, ArrowW);
  end;
  for I := 0 to Rows - 1 do
  begin
    Idx := Top_ + I;
    if Idx >= Open.Items.Count then Break;
    if Idx = Open.Sel then
    begin
      Back := clHighlight;
      Fore := clHighlightText;
    end
    else
    begin
      if Open.OwnerDraw then Back := CharFace else Back := clWindow;
      Fore := clWindowText;
    end;
    if Open.OwnerDraw then
      DrawCharItem(S, LX + 1, LY + 1 + I * 16, IW, Idx, Back, Fore)
    else
    begin
      S.FillRect(LX + 1, LY + 1 + I * 16, IW, 16, Back);
      TextAt(S, LX + 3, LY + 1 + I * 16, Open.Items[Idx], Fore);
    end;
  end;
end;

procedure TLaunch.Draw(S: TGSurface);
var
  I, Pass: Integer;
  C: TCtl;
begin
  S.Fill(clBtnFace);
  { VCL order: a parent's pictures and labels first, then its windowed
    controls on top; a panel's own controls with it }
  for Pass := 0 to 1 do
    for I := 0 to Ctls.Count - 1 do
    begin
      C := TCtl(Ctls[I]);
      if (C.Parent <> nil) or not C.Shown then Continue;
      if (Pass = 0) <> (C.Kind in [ckImage, ckLabel, ckPaintBox]) then Continue;
      DrawCtl(S, C);
    end;
  for I := 0 to Ctls.Count - 1 do
  begin
    C := TCtl(Ctls[I]);
    if (C.Parent <> nil) and C.Shown and (C.Kind in [ckImage, ckLabel]) and
      (C.Y < C.Parent.Y + C.Parent.H) then DrawCtl(S, C);
  end;
  for I := 0 to Ctls.Count - 1 do
  begin
    C := TCtl(Ctls[I]);
    { a control below a shortened panel's edge is cut away with it }
    if (C.Parent <> nil) and C.Shown and not (C.Kind in [ckImage, ckLabel]) and
      (C.Y < C.Parent.Y + C.Parent.H) then DrawCtl(S, C);
  end;
  if Open <> nil then DrawList(S);
end;

function RunLaunch1x(Win: TGWindow; const FormData: string; const Cfg: TLaunchConfig;
  const Chars: TCharList; HeadIcon: THeadIcon; Languages: TStrings;
  var R: TLaunchResult; StopRequested: TStopCheckFn): Boolean;
var
  L: TLaunch;
  S: TGSurface;
  C: TCtl;
  CX, CY, I, RW, RH, H: Integer;
  Go: Boolean;

  procedure FillChars(Box: TCtl; Def: Integer);
  var
    J: Integer;
  begin
    if Box = nil then Exit;
    Box.Items.Clear;
    for J := 0 to High(Chars) do Box.Items.Add(Chars[J].Name);
    if Def > High(Chars) then Def := 0;
    if Box.Items.Count > 0 then Box.Sel := Def;
  end;

  function EditText(const N: string): string;
  var
    E: TCtl;
  begin
    E := L.Ctl(N);
    if E <> nil then Result := E.Text else Result := '';
  end;

  procedure SetEdit(const N, V: string);
  var
    E: TCtl;
  begin
    E := L.Ctl(N);
    if E <> nil then E.Text := V;
  end;

begin
  Result := False;
  L := TLaunch.Create;
  S := nil;
  try
    L.Form := ReadDfm(FormData);
    if L.Form = nil then Exit;
    L.Cfg := Cfg;
    L.Chars := Chars;
    L.HeadIcon := HeadIcon;
    L.Build;
    { what FormCreate fills in }
    C := L.Ctl('ModeSelect');
    if C <> nil then L.SetSel(C, Cfg.DefMode);
    for I := 1 to 4 do FillChars(L.Ctl('ComboBox' + IntToStr(I)), I - 1);
    FillChars(L.Ctl('characterbox'), 0);
    for I := 0 to 3 do
      if I <= High(Chars) then L.PlayerChars[I] := I else L.PlayerChars[I] := 0;
    { the language list: the install's language<Name>.txt files }
    C := L.Ctl('ComboBox6');
    if C = nil then C := L.Ctl('languagebox');
    if C <> nil then
    begin
      C.Items.Clear;
      if (Languages <> nil) and (Languages.Count > 0) then C.Items.AddStrings(Languages)
      else C.Items.Add('English');
      C.Sel := C.Items.IndexOf(R.Language);
      if C.Sel < 0 then C.Sel := C.Items.IndexOf('English');
      if C.Sel < 0 then C.Sel := 0;
    end;
    L.Caption := L.Form.Str('Caption', 'Graal - The Adventure');
    L.ApplyLanguage;
    C := L.Ctl('ComboBox5');
    if C <> nil then
    begin
      C.Items.Clear;
      C.Items.Add(Cfg.DefServer);
      C.Sel := 0;
      C.Enabled := Cfg.ServerEnabled;
    end;
    SetEdit('Edit1', Cfg.DefServer);
    C := L.Ctl('Edit1');
    if C <> nil then C.Enabled := Cfg.ServerEnabled;
    SetEdit('Edit2', IntToStr(Cfg.DefPort));
    SetEdit('Edit3', R.Nickname);
    if R.Account <> '' then SetEdit('Edit4', R.Account);
    L.Focus := L.Ctl(L.Form.Str('ActiveControl', 'Button1'));
    if L.Focus = nil then L.Focus := L.Ctl('Button1');
    L.Layout;

    { the form's own frame: caption, system menu and, with biMinimize,
      a minimise button (Windows greys the maximise button beside it) }
    { the scroll range, as TScrollingWinControl works it out: the right
      and bottom edges of the visible controls }
    RW := 0;
    RH := 0;
    for I := 0 to L.Ctls.Count - 1 do
    begin
      C := TCtl(L.Ctls[I]);
      if (C.Parent <> nil) or not C.Visible then Continue;
      if C.X + C.W > RW then RW := C.X + C.W;
      { a panel counts at its design height: the One Player layout only
        shortens it after the range is set, so 1.28b2 to 1.39 show both
        bars on Windows 10 as the real ones do }
      H := C.H;
      if C.Kind = ckPanel then H := C.Obj.Int('Height', C.H);
      if C.Y + H > RH then RH := C.Y + H;
    end;
    Win.ShowForm(L.Caption, L.Form.Int('Width', L.CW + 8),
      L.Form.Int('Height', L.CH + 34), RW, RH, L.Form.Bool('AutoScroll', True), clBtnFace);
    S := TGSurface.Create(L.CW, L.CH);
    Win.TakeChars;
    while True do
    begin
      Win.Pump;
      if Win.Closed or (Assigned(StopRequested) and StopRequested()) then Exit;
      Go := False;
      while Win.TakeClick(CX, CY) do
        if L.Click(CX + Win.ScrollX, CY + Win.ScrollY) then Go := True;
      if L.Keys(Win.TakeChars, Win) then Go := True;
      I := Win.TakeWheel;
      if (I <> 0) and (L.Open <> nil) then
      begin
        Dec(L.Top_, I * 3);
        if L.Top_ > L.Open.Items.Count - L.Open.DropCount then
          L.Top_ := L.Open.Items.Count - L.Open.DropCount;
        if L.Top_ < 0 then L.Top_ := 0;
      end;
      if Go then Break;
      L.Draw(S);
      Win.Present(S);
      Sleep(20);
    end;

    { the choice }
    R.Mode := L.Mode;
    R.Nickname := EditText('Edit3');
    C := L.Ctl('ComboBox5');
    if C <> nil then R.Server := C.Items[C.Sel] else R.Server := EditText('Edit1');
    if R.Server = '' then R.Server := Cfg.DefServer;
    R.Port := StrToIntDef(EditText('Edit2'), Cfg.DefPort);
    R.Account := EditText('Edit4');
    R.Password := EditText('Edit5');
    C := L.Ctl('CheckBox1');
    R.LoadLast := (C <> nil) and C.Checked;
    C := L.Ctl('ComboBox6');
    if C = nil then C := L.Ctl('languagebox');
    if (C <> nil) and (C.Sel >= 0) then R.Language := C.Items[C.Sel];
    if L.Cfg.Style = ls141 then
      for I := 0 to 3 do R.Chars[I] := L.PlayerChars[I]
    else
      for I := 0 to 3 do
      begin
        C := L.Ctl('ComboBox' + IntToStr(I + 1));
        if (C <> nil) and (C.Sel >= 0) then R.Chars[I] := C.Sel else R.Chars[I] := I;
      end;
    Result := True;
  finally
    S.Free;
    L.Form.Free;
    L.Free;
  end;
end;

end.
