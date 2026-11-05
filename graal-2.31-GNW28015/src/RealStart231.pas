{ RealStart231: 2.31's own start window and server list.

  Both are their own 577 x 416 windows with only a close button
  (TConnectFrame and TServerListFrame are bsDialog), not screens inside
  the game window. The pictures are 2.31's own (RCDATA SCREENIMG1,
  SCREENIMG2, BUTTON1 .. BUTTON4 of Graal_231.exe), compiled into this
  program from res/ (Res231). The places come from the forms and, where
  2.31 moves things at run time, from the real 2.31 under Wine
  (2026-11-05); the words come from the install's
  languages/language<name>.txt, as 2.31 reads them, falling back to the
  forms' own captions.

  What 2.31 does differently from 2.22 (seen side by side under Wine):
  - the start window's title is always "GraalOnline": 2.31 sets it in
    code and ignores the language file's StartScreen= line;
  - five buttons: Training (the wide picture, at the top), Editor,
    Options, Get an account! and Start. Editor starts GraalEditor.exe
    from the Graal folder, or says "GraalEditor.exe has not been found in
    the Graal folder!" (StartScreen-GraalEditorError);
  - the server list's tabs are Graal Gold ('P '), Graal 3D ('3 '),
    Classic (no prefix) and Hosted ('H '), only those that hold a
    server; picking a Graal 3D server without Graal3.exe says "You need
    to download Graal3D at http://www.graalonline.com/downloads/index.php
    for playing this server!";
  - the list page shows Connect only (no Show More / Donations), with the
    server combo box under the list. }
unit RealStart231;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow, GStartScreen, Dialogs231;

type
  TRealStartArt = class
  public
    Back1, Back2: TGSurface;
    Btn: array[1..4] of TGSurface;
    Lang: TStringList;
    { graalconfig.txt (the More options window's settings) and the page
      Get an account! offers (arrays2.dat line 3) }
    Config: TGraalConfig;
    AccountUrl: string;
    constructor Create;
    destructor Destroy; override;
    { The pictures compiled into this program (res/, from Graal_231.exe)
      and the words from LangFile; False when a picture does not
      decode. }
    function Load(const LangFile: string): Boolean;
    { The language file's text for Key, trimmed, or Default when it has
      none or an empty one. }
    function Text(const Key, Default: string): string;
  end;

  TListTab = (ltGold, lt3D, ltClassic, ltHosted, ltNone);

{ The tab a server is listed on, from its name's type prefix. }
function ServerTab(const Name: string): TListTab;

{ Runs the start window and the server list in Win (reshaped to 577 x 416)
  until the player picks Training or a server. Dir is the Graal folder
  (GraalEditor.exe, Graal3.exe). False: closed, or Esc on the start
  window. }
function RunRealStart(Win: TGWindow; Art: TRealStartArt; Fetch: TListFetch;
  const Info: TStartInfo; const Dir, ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;

{ The nickname and the last account 2.22 kept (HKCU\Software\Graal\Client:
  nickname, accountname); nothing outside Windows. }
procedure ReadSavedLogin(var Nickname, Account: string);
procedure SaveLogin(const Nickname, Account: string);

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, Math, Res231, GUiFont;

const
  DlgW = 577;
  DlgH = 416;
  ColText = $FFCCCC99;     { the dialogs' text }
  ColFill = $FF005500;     { the fields and the server panel }
  ColSelect = $FF0078D7;   { a picked row }
  ColWhite = $FFFFFFFF;

{ ---- art ---- }

constructor TRealStartArt.Create;
begin
  inherited Create;
  Lang := TStringList.Create;
  Config := TGraalConfig.Create;
end;

destructor TRealStartArt.Destroy;
var
  I: Integer;
begin
  Back1.Free;
  Back2.Free;
  for I := 1 to 4 do Btn[I].Free;
  Lang.Free;
  Config.Free;
  inherited Destroy;
end;

function TRealStartArt.Load(const LangFile: string): Boolean;

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

var
  I: Integer;
begin
  Back1 := Pic('SCREENIMG1');
  Back2 := Pic('SCREENIMG2');
  for I := 1 to 4 do Btn[I] := Pic('BUTTON' + IntToStr(I));
  Result := (Back1 <> nil) and (Back2 <> nil) and (Btn[1] <> nil) and (Btn[2] <> nil) and
    (Btn[3] <> nil) and (Btn[4] <> nil);
  if (LangFile <> '') and FileExists(LangFile) then
    try
      Lang.LoadFromFile(LangFile);
    except
      Lang.Clear;
    end;
end;

function TRealStartArt.Text(const Key, Default: string): string;
var
  I: Integer;
begin
  Result := Default;
  I := Lang.IndexOfName(Key);
  if I < 0 then Exit;
  if Trim(Lang.ValueFromIndex[I]) <> '' then Result := Trim(Lang.ValueFromIndex[I]);
end;

function ServerTab(const Name: string): TListTab;
begin
  if (Length(Name) > 2) and (Name[2] = ' ') then
    case Name[1] of
      'P': Result := ltGold;
      '3': Result := lt3D;
      'H': Result := ltHosted;
      'U': Result := ltNone;
    else
      Result := ltClassic;
    end
  else
    Result := ltClassic;
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

{ ---- other programs ---- }

{ Starts Name from the Graal folder Dir with Params, as 2.31 starts
  GraalEditor.exe and Graal3.exe; False when it is not there (or, off
  Windows, cannot be started). }
function StartProgram(const Dir, Name, Params: string): Boolean;
{$IFDEF MSWINDOWS}
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  Result := False;
  if not FileExists(Dir + Name) then Exit;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  Cmd := '"' + Dir + Name + '"';
  if Params <> '' then Cmd := Cmd + ' ' + Params;
  UniqueString(Cmd);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, PChar(Dir), SI, PI);
  if Result then
  begin
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

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
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function Inside(const B: TBox; X, Y: Integer): Boolean;
begin
  Result := (X >= B.X) and (Y >= B.Y) and (X < B.X + B.W) and (Y < B.Y + B.H);
end;

{ the sunken edge of an edit or combo box: grey and dark grey over the top
  and left, light grey and white under the bottom and right }
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

procedure Edit(S: TGSurface; const B: TBox; const Text: string; Focused, Masked,
  Combo: Boolean);
var
  T: string;
  TW, X, I, AX, AY, Right: Integer;
begin
  S.FillRect(B.X + 2, B.Y + 2, B.W - 4, B.H - 4, ColFill);
  Sunken(S, B);
  Right := B.X + B.W - 2;
  if Combo then
  begin
    { the drop-down button: 17 wide inside the edge, a raised face with
      a black arrow 7 wide }
    X := B.X + B.W - 2 - 17;
    S.FillRect(X, B.Y + 2, 17, B.H - 4, $FFF5F5F5);
    S.FillRect(X, B.Y + 2, 17, 1, $FFE3E3E3);
    S.FillRect(X, B.Y + 2, 1, B.H - 4, $FFE3E3E3);
    S.FillRect(X + 15, B.Y + 2, 1, B.H - 4, $FFA6A6A6);
    S.FillRect(X + 16, B.Y + 2, 1, B.H - 4, $FF6A6A6A);
    S.FillRect(X, B.Y + B.H - 4, 17, 1, $FFA6A6A6);
    S.FillRect(X, B.Y + B.H - 3, 17, 1, $FF6A6A6A);
    AX := X + 5;
    AY := B.Y + (B.H - 4) div 2;
    for I := 0 to 3 do S.FillRect(AX + I, AY + I, 7 - 2 * I, 1, $FF000000);
    Right := X;
  end;
  if Masked then T := StringOfChar('*', Length(Text)) else T := Text;
  { an edit being typed in keeps its end in view; any other shows its
    start, cut at the right (the server list's Version: the real 2.31 on
    Windows) }
  if Focused and not Combo then
    while (T <> '') and (UiTextWidth(T, ufRegular) > Right - B.X - 6) do Delete(T, 1, 1)
  else
    while (T <> '') and (UiTextWidth(T, ufRegular) > Right - B.X - 6) do
      Delete(T, Length(T), 1);
  TW := UiTextWidth(T, ufRegular);
  if Focused and Combo and (T <> '') then
  begin
    { a focused combo shows its text picked: the blue just behind the
      text, as the real one }
    S.FillRect(B.X + 3, B.Y + 3, Min(TW + 2, Right - B.X - 4), B.H - 6, ColSelect);
    UiDrawText(S, B.X + 4, B.Y + (B.H - UiLineH) div 2, T, ColWhite, ufRegular);
  end
  else
    UiDrawText(S, B.X + 4, B.Y + (B.H - UiLineH) div 2, T, ColText, ufRegular);
  if Focused and not Combo and ((NowMs div 500) mod 2 = 0) then
    S.FillRect(B.X + 4 + TW, B.Y + 4, 1, B.H - 8, ColText);
end;

{ a picture button: the left half up, the right half pressed; the caption
  bold and centred }
procedure PicButton(S, Img: TGSurface; X, Y: Integer; const Caption: string; Down: Boolean);
var
  W, D: Integer;
begin
  if Img = nil then Exit;
  W := Img.Width div 2;
  if Down then D := 1 else D := 0;
  S.Blit(Img, D * W, 0, W, Img.Height, X, Y);
  UiDrawText(S, X + (W - UiTextWidth(Caption, ufBold)) div 2 + D,
    Y + (Img.Height - UiLineH) div 2 + D, Caption, ColText, ufBold);
end;

procedure Centred(S: TGSurface; X, Y, W: Integer; const T: string; Face: TUiFace);
begin
  UiDrawText(S, X + (W - UiTextWidth(T, Face)) div 2, Y, T, ColText, Face);
end;

{ Text broken into lines (at #10, then at spaces) to W pixels; each line
  centred, or not }
procedure Wrapped(S: TGSurface; X, Y, W: Integer; const Text: string; Centre: Boolean);
var
  Lines, Words: TStringList;
  I, J: Integer;
  Line, Cand: string;

  procedure Put(const L: string);
  begin
    if Centre then Centred(S, X, Y, W, L, ufRegular)
    else UiDrawText(S, X, Y, L, ColText, ufRegular);
    Inc(Y, UiLineH);
  end;

begin
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
        if (UiTextWidth(Cand, ufRegular) > W) and (Line <> '') then
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

{ ---- the two windows ---- }

function RunRealStart(Win: TGWindow; Art: TRealStartArt; Fetch: TListFetch;
  const Info: TStartInfo; const Dir, ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;
type
  TPage = (pgStart, pgFetch, pgList);
const
  TabNames: array[TListTab] of string = ('Graal Gold', 'Graal 3D', 'Classic', 'Hosted', '');
var
  S: TGSurface;
  Page: TPage;
  Focus, Sel, I, N, CX, CY, Row, PressBtn: Integer;
  AccPicked: Boolean;
  Clicked: Boolean;
  Chars, Note, Lang, Title1, Title2: string;
  BTraining, BEditor, BOptions, BAccount, BStart, FNick, FLang, FAcc, FPw: TBox;
  BMore, BDonate, BConnect, BGo, LList, FCombo: TBox;
  Tab, T: TListTab;
  Tabs: array of TListTab;
  Rows: array of Integer;
  TabX: Integer;
  Srv: TListServer;
  PressUntil: Int64;

  procedure Fill(Back: TGSurface);
  begin
    S.Fill($FF004000);
    if Back <> nil then S.Blit(Back, 0, 0, Back.Width, Back.Height, 0, 0);
  end;

  procedure BuildTabs;
  var
    K: TListTab;
    J: Integer;
    Has: Boolean;
  begin
    SetLength(Tabs, 0);
    for K := ltGold to ltHosted do
    begin
      Has := False;
      for J := 0 to High(Fetch.Servers) do
        if ServerTab(Fetch.Servers[J].Name) = K then Has := True;
      if Has then
      begin
        SetLength(Tabs, Length(Tabs) + 1);
        Tabs[High(Tabs)] := K;
      end;
    end;
    if Length(Tabs) > 0 then Tab := Tabs[0] else Tab := ltClassic;
  end;

  procedure BuildRows;
  var
    J: Integer;
  begin
    SetLength(Rows, 0);
    for J := 0 to High(Fetch.Servers) do
      if ServerTab(Fetch.Servers[J].Name) = Tab then
      begin
        SetLength(Rows, Length(Rows) + 1);
        Rows[High(Rows)] := J;
      end;
  end;

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
  { set in code by 2.31, whatever the language file says }
  Title1 := 'GraalOnline';
  Title2 := Art.Text('ServerList', 'Graalonline.com Server List');
  Win.Reshape(Title1, DlgW, DlgH, True);
  S := TGSurface.Create(DlgW, DlgH);
  try
    Page := pgStart;
    Note := Message;
    Lang := 'English';
    { the form says guest / guest, but 2.31 empties both before it shows
      the window (under Wine, nothing saved). The account box is first in
      the tab order: it has the focus on open, its text picked (the real
      2.31 on Windows, 2026-11-05) }
    Focus := 2;
    AccPicked := True;
    Sel := -1;
    Tab := ltClassic;
    PressBtn := 0;
    PressUntil := 0;
    { TConnectFrame }
    FNick := Box(200, 241, 177, 24);
    FLang := Box(200, 269, 177, 24);
    FAcc := Box(204, 329, 173, 24);
    FPw := Box(204, 361, 173, 24);
    { 2.31 under Wine: Training takes the wide picture at the top, Editor
      comes in under it }
    BTraining := Box(408, 185, 145, 26);
    BEditor := Box(423, 215, 105, 26);
    BOptions := Box(423, 245, 105, 26);
    BAccount := Box(408, 275, 145, 26);
    BStart := Box(423, 345, 105, 26);
    { TServerListFrame }
    LList := Box(24, 190, 201, 91);
    FCombo := Box(24, 290, 201, 23);
    { Show More and Donations as the real 2.31 shows them on Windows
      (2026-11-05), left of Connect; pressing them does nothing yet }
    BMore := Box(120, 375, 105, 26);
    BDonate := Box(240, 375, 185, 26);
    BConnect := Box(440, 375, 105, 26);
    BGo := Box(528, 288, 28, 26);
    while True do
    begin
      Win.Pump;
      if Win.Closed or (Assigned(Info.StopRequested) and Info.StopRequested()) then Exit;
      Clicked := Win.TakeClick(CX, CY);
      Chars := Win.TakeChars;
      Fetch.Poll;
      case Page of
        pgStart, pgFetch:
          begin
            if Page = pgFetch then
            begin
              Chars := '';
              Clicked := False;
              if Fetch.Done then
              begin
                BuildTabs;
                BuildRows;
                Sel := -1;
                if Length(Rows) > 0 then Sel := Rows[0];
                Page := pgList;
                Note := '';
                Win.Reshape(Title2, DlgW, DlgH, True);
                Continue;
              end;
              if Fetch.Failed then
              begin
                Note := Fetch.Status;
                Page := pgStart;
              end;
            end;
            if Pos(#27, Chars) > 0 then Exit;
            if Pos(#9, Chars) > 0 then
            begin
              { TabOrder: account, password, nickname, language }
              case Focus of
                2: Focus := 3;
                3: Focus := 0;
                0: Focus := 1;
              else
                Focus := 2;
              end;
              AccPicked := Focus = 2;
              Chars := StringReplace(Chars, #9, '', [rfReplaceAll]);
            end;
            case Focus of
              0: TypeInto(R.Nickname, Chars, 20);
              2:
                begin
                  { typing over the picked text replaces it }
                  if (Chars <> '') and (Chars[1] >= ' ') and AccPicked then R.Account := '';
                  TypeInto(R.Account, Chars, 30);
                end;
              3: TypeInto(R.Password, Chars, 30);
            end;
            if Chars <> '' then AccPicked := False;
            if Clicked then
            begin
              if Inside(FNick, CX, CY) then Focus := 0;
              if Inside(FLang, CX, CY) then Focus := 1;
              if Inside(FAcc, CX, CY) then Focus := 2;
              AccPicked := False;
              if Inside(FPw, CX, CY) then Focus := 3;
              if Inside(BTraining, CX, CY) then
              begin
                { 2.31's Training starts "GraalEditor.exe -play" from the
                  Graal folder (seen under Wine and on Windows, 2026-11-05)
                  and stays on this window; without it, the same error as
                  Editor. The rebuild then plays the tutorial itself, its
                  stand-in for the editor's play mode. }
                Press(1);
                SaveLogin(R.Nickname, R.Account);
                if not StartProgram(Dir, 'GraalEditor.exe', '-play') then
                begin
                  ShowError(Art.Text('StartScreen-GraalEditorError',
                    'GraalEditor.exe has not been found in the Graal folder!'));
                  Win.TakeClick(CX, CY);
                  Win.TakeChars;
                  R.Choice := scTraining;
                  Result := True;
                  Exit;
                end;
              end;
              if Inside(BEditor, CX, CY) then
              begin
                Press(5);
                if not StartProgram(Dir, 'GraalEditor.exe', '') then
                begin
                  ShowError(Art.Text('StartScreen-GraalEditorError',
                    'GraalEditor.exe has not been found in the Graal folder!'));
                  Win.TakeClick(CX, CY);
                  Win.TakeChars;
                end;
              end;
              if Inside(BOptions, CX, CY) then
              begin
                Press(2);
                { 2.31's More options window, over this one }
                RunMoreOptions(Art.Config, Art.Text);
                Win.TakeClick(CX, CY);
                Win.TakeChars;
              end;
              if Inside(BAccount, CX, CY) then
              begin
                Press(3);
                if Art.AccountUrl <> '' then RunOpenUrl(Art.AccountUrl, Art.Text);
                Win.TakeClick(CX, CY);
                Win.TakeChars;
              end;
            end;
            if (Page = pgStart) and ((Clicked and Inside(BStart, CX, CY)) or (Pos(#13, Chars) > 0)) then
            begin
              Press(4);
              SaveLogin(R.Nickname, R.Account);
              Note := '';
              Fetch.Start(ListHost, ListPort, R.Account, R.Password);
              Page := pgFetch;
            end;
            { drawing }
            Fill(Art.Back1);
            Centred(S, 80, 209, 281, Art.Text('StartScreen-Label1', 'Welcome to Graal!'), ufBold);
            UiDrawText(S, 72, 246, Art.Text('StartScreen-Label5', 'Nick Name:'), ColText, ufBold);
            UiDrawText(S, 72, 274, Art.Text('StartScreen-Label2', 'Language:'), ColText, ufBold);
            UiDrawText(S, 76, 332, Art.Text('ServerList-Label7', 'Account:'), ColText, ufBold);
            UiDrawText(S, 76, 364, Art.Text('ServerList-Label8', 'Password:'), ColText, ufBold);
            Edit(S, FNick, R.Nickname, Focus = 0, False, False);
            Edit(S, FLang, Lang, Focus = 1, False, True);
            Edit(S, FAcc, R.Account, (Focus = 2) and AccPicked, False, True);
            Edit(S, FPw, R.Password, Focus = 3, True, False);
            PicButton(S, Art.Btn[2], BTraining.X, BTraining.Y,
              Art.Text('StartScreen-Button2', 'Training'), Pressed(1));
            PicButton(S, Art.Btn[1], BEditor.X, BEditor.Y,
              Art.Text('StartScreen-Button5', 'Editor'), Pressed(5));
            PicButton(S, Art.Btn[1], BOptions.X, BOptions.Y,
              Art.Text('StartScreen-Button3', 'Options'), Pressed(2));
            PicButton(S, Art.Btn[2], BAccount.X, BAccount.Y,
              Art.Text('ServerList-Label6', 'Get an account!'), Pressed(3));
            PicButton(S, Art.Btn[1], BStart.X, BStart.Y,
              Art.Text('StartScreen-Button1', 'Start'), Pressed(4));
            if Note <> '' then Wrapped(S, 60, 392, 457, Note, True);
            if Page = pgFetch then
            begin
              { the small "Getting server list ..." window, 274 x 100,
                centred over the dialog }
              CX := (DlgW - 274) div 2;
              CY := (DlgH - 100) div 2;
              S.FillRect(CX, CY, 274, 100, $FF6A6A6A);
              S.FillRect(CX, CY, 273, 99, ColWhite);
              S.FillRect(CX + 1, CY + 1, 272, 98, $FFA6A6A6);
              S.FillRect(CX + 1, CY + 1, 271, 97, $FFE3E3E3);
              S.FillRect(CX + 2, CY + 2, 270, 96, $FF004000);
              S.FillRect(CX + 2, CY + 2, 270, 18, $FF0A246A);
              UiDrawText(S, CX + 6, CY + 3, Art.Text('ServerList-ShortMessageCaption',
                'Graal Server List'), ColWhite, ufBold);
              Centred(S, CX, CY + 50, 274, Art.Text('ServerList-ShortMessage2',
                'Getting server list ...'), ufRegular);
            end;
          end;
        pgList:
          begin
            if Pos(#27, Chars) > 0 then
            begin
              Page := pgStart;
              Win.Reshape(Title1, DlgW, DlgH, True);
              Continue;
            end;
            if Clicked then
            begin
              { the tabs }
              TabX := 8;
              for I := 0 to High(Tabs) do
              begin
                if (CX >= TabX) and (CX < TabX + 120) and (CY >= 136) and (CY < 161) then
                begin
                  Tab := Tabs[I];
                  BuildRows;
                end;
                Inc(TabX, 120);
              end;
              if Inside(LList, CX, CY) then
              begin
                Row := (CY - LList.Y - 2) div UiLineH;
                if (Row >= 0) and (Row <= High(Rows)) then Sel := Rows[Row];
              end;
              if Inside(BGo, CX, CY) then
              begin
                { Go: the picked server's homepage, asked first }
                Press(8);
                if (Sel >= 0) and (Sel <= High(Fetch.Servers)) and
                  (Fetch.Servers[Sel].Url <> '') then
                  RunOpenUrl(Fetch.Servers[Sel].Url, Art.Text);
                Win.TakeClick(CX, CY);
                Win.TakeChars;
              end;
            end;
            if Clicked and Inside(BMore, CX, CY) then Press(9);
            if Clicked and Inside(BDonate, CX, CY) then Press(10);
            if ((Clicked and Inside(BConnect, CX, CY)) or (Pos(#13, Chars) > 0)) and
              (Sel >= 0) and (Sel <= High(Fetch.Servers)) then
            begin
              Srv := Fetch.Servers[Sel];
              if ServerTab(Srv.Name) = lt3D then
              begin
                { a Graal3D server: 2.31 hands it to Graal3.exe }
                Press(7);
                if not StartProgram(Dir, 'Graal3.exe', '-connect "' + Srv.Host + ':' +
                  IntToStr(Srv.Port) + '"') then
                  Note := 'You need to download Graal3D at ' +
                    'http://www.graalonline.com/downloads/index.php ' +
                    'for playing this server!';
                Continue;
              end;
              R.Choice := scOnline;
              R.Host := Srv.Host;
              R.Port := Srv.Port;
              R.ServerName := ServerDisplayName(Srv.Name);
              Result := True;
              Exit;
            end;
            { drawing }
            Fill(Art.Back2);
            { the panel: raised, white over the top and left }
            S.FillRect(8, 160, 561, 163, ColFill);
            S.FillRect(8, 160, 561, 1, ColWhite);
            S.FillRect(8, 160, 1, 163, ColWhite);
            S.FillRect(8, 322, 561, 1, $FFA6A6A6);
            S.FillRect(568, 160, 1, 163, $FFA6A6A6);
            { the tabs: the picked one raised over the panel's edge }
            TabX := 8;
            for I := 0 to High(Tabs) do
            begin
              if Tabs[I] = Tab then
              begin
                S.FillRect(TabX, 137, 123, 24, ColFill);
                S.FillRect(TabX, 137, 123, 1, ColWhite);
                S.FillRect(TabX, 137, 1, 24, ColWhite);
                S.FillRect(TabX + 122, 137, 1, 23, $FFAEAEAE);
                Centred(S, TabX, 141, 123, TabNames[Tabs[I]], ufRegular);
              end
              else
              begin
                S.FillRect(TabX + 3, 141, 117, 19, ColFill);
                S.FillRect(TabX + 3, 141, 117, 1, ColWhite);
                S.FillRect(TabX + 3, 141, 1, 19, ColWhite);
                S.FillRect(TabX + 119, 141, 1, 19, $FFAEAEAE);
                Centred(S, TabX + 3, 143, 117, TabNames[Tabs[I]], ufRegular);
              end;
              Inc(TabX, 120);
            end;
            Centred(S, 16, 172, 124, Art.Text('ServerList-ListColumn1', 'Name'), ufRegular);
            Centred(S, 150, 172, 55, Art.Text('ServerList-ListColumn2', 'Players'), ufRegular);
            { the list: a white frame, a picked row in the highlight }
            S.FillRect(LList.X, LList.Y, LList.W, LList.H, ColWhite);
            S.FillRect(LList.X, LList.Y, LList.W, 1, $FFAEAEAE);
            S.FillRect(LList.X, LList.Y, 1, LList.H, $FFAEAEAE);
            S.FillRect(LList.X + 2, LList.Y + 2, LList.W - 4, LList.H - 4, ColFill);
            N := (LList.H - 4) div UiLineH;
            for I := 0 to High(Rows) do
            begin
              if I >= N then Break;
              Srv := Fetch.Servers[Rows[I]];
              CY := LList.Y + 2 + I * UiLineH + 1;
              if Rows[I] = Sel then
              begin
                S.FillRect(LList.X + 4, CY, 177, UiLineH, ColSelect);
                UiDrawText(S, LList.X + 9, CY, ServerDisplayName(Srv.Name), ColWhite, ufRegular);
                UiDrawText(S, LList.X + 179 - UiTextWidth(Srv.Players, ufRegular), CY,
                  Srv.Players, ColWhite, ufRegular);
              end
              else
              begin
                UiDrawText(S, LList.X + 9, CY, ServerDisplayName(Srv.Name), ColText, ufRegular);
                UiDrawText(S, LList.X + 179 - UiTextWidth(Srv.Players, ufRegular), CY,
                  Srv.Players, ColText, ufRegular);
              end;
            end;
            UiDrawText(S, 240, 170, Art.Text('ServerList-Label2', 'Language:'), ColText, ufRegular);
            UiDrawText(S, 240, 196, Art.Text('ServerList-Label3', 'Graal version:'), ColText, ufRegular);
            UiDrawText(S, 240, 222, Art.Text('ServerList-Label4', 'Description:'), ColText, ufRegular);
            UiDrawText(S, 240, 293, Art.Text('ServerList-Label5', 'Homepage:'), ColText, ufRegular);
            FillChar(Srv, SizeOf(Srv), 0);
            if (Sel >= 0) and (Sel <= High(Fetch.Servers)) then Srv := Fetch.Servers[Sel];
            Edit(S, Box(384, 166, 169, 24), Srv.Language, False, False, False);
            Edit(S, Box(384, 192, 169, 24), Srv.Version, False, False, False);
            S.FillRect(347, 218, 209, 69, ColFill);
            Sunken(S, Box(347, 218, 209, 69));
            Wrapped(S, 351, 220, 201, Srv.Description, False);
            Edit(S, Box(346, 289, 182, 24), Srv.Url, False, False, False);
            if Art.Btn[4] <> nil then
              S.Blit(Art.Btn[4], Ord(Pressed(8)) * (Art.Btn[4].Width div 2), 0,
                Art.Btn[4].Width div 2, Art.Btn[4].Height, BGo.X, BGo.Y);
            { the server combo box under the list }
            Edit(S, FCombo, '', False, False, True);
            { the listserver's lines, or what Connect said }
            if Note <> '' then Wrapped(S, 24, 330, 529, Note, True)
            else if Fetch.StatusLines <> '' then Wrapped(S, 24, 330, 529, Fetch.StatusLines, True)
            else Wrapped(S, 24, 330, 529, Fetch.Status, True);
            PicButton(S, Art.Btn[1], BMore.X, BMore.Y,
              Art.Text('ServerList-Button2', 'Show More'), Pressed(9));
            PicButton(S, Art.Btn[3], BDonate.X, BDonate.Y,
              Art.Text('ServerList-Button4', 'Donations'), Pressed(10));
            PicButton(S, Art.Btn[1], BConnect.X, BConnect.Y,
              Art.Text('ServerList-Button1', 'Connect'), Pressed(7));
          end;
      end;
      Win.Present(S);
      Sleep(20);
    end;
  finally
    S.Free;
  end;
end;

end.
