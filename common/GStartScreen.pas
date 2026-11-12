{ GStartScreen: the start screen and server list every build opens with.

  The Graal clients open on a small dialog before the game: the nick name, the character, and
  Training, Options and Start. Start opens the server list: account,
  password, the servers the listserver sends, and Connect.

  This unit draws both into the game's own surface with the built-in font,
  so it needs no widget toolkit. Layout, wording and art are its own; it
  never draws an original start window or its images, even when an
  install is next to the program. Only the flow follows the originals. What differs per build comes in from the
  build:
    - TStartInfo: title lines and a callback that draws the character;
    - a TListFetch subclass: how that build asks its listserver for the
      list (2.05: plain zlib, id 0 "newmain") and reads the answer;
    - the build's own front end picks the Training level and runs the game.
  ParseServerList reads the list layout the 2.x listservers send. }
unit GStartScreen;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, GWindow;

type
  TStartChoice = (scQuit, scTraining, scOnline);

  TListServer = record
    Name, Language, Description, Url, Version, Players, Host: string;
    Port: Integer;
  end;
  TListServers = array of TListServer;

  TStartResult = record
    Choice: TStartChoice;
    Nickname, Account, Password, Host: string;
    Port: Integer;
    { the picked server's name as listed, without its type prefix }
    ServerName: string;
  end;

  { Fetches the server list. A build subclasses it with its own listserver
    step; the screen calls Start, then Poll every frame, and reads Servers,
    Status, Done and Failed. }
  TListFetch = class
  public
    Servers: TListServers;
    Status: string;
    { the listserver's own status lines (#10 between them), when it sent
      some }
    StatusLines: string;
    { the site and upgrade pages the listserver sent (its SITEURL and
      UPGURL packets), '' when none: 2.31 shows Show More and its second
      button only for these }
    SiteUrl, UpgradeUrl: string;
    Done, Failed: Boolean;
    { Account and Password are what the list page holds when the list is
      asked for; builds whose list step does not send them ignore them. }
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); virtual; abstract;
    procedure Poll; virtual; abstract;
  end;

  { Draws the player's character with its feet near (X, Y + 40). }
  TDrawCharacter = procedure(S: TGSurface; X, Y: Integer; const Nick: string) of object;

  TStartRect = record
    X, Y, W, H: Integer;
  end;

  { True once the program was asked to stop (SIGTERM, Ctrl+C). }
  TStopCheck = function: Boolean;

  TStartInfo = record
    Title, Subtitle: string;
    DrawCharacter: TDrawCharacter;
    { nil: never; else the screen gives up (as Quit) when it turns True }
    StopRequested: TStopCheck;
  end;

function StartRect(X, Y, W, H: Integer): TStartRect;

{ PLO id 0 of the listserver: c count, then per server c field count and
  that many strings (name, language, description, url, version, players,
  ip, port). A short or garbled list gives the servers read so far. }
function ParseServerList(const Data: string): TListServers;
{ A server name without the listserver's type prefix ('P ', 'H ', '3 ',
  'U '). }
function ServerDisplayName(const Name: string): string;

{ Runs the start screen and the server list in Win, drawing into S, until
  the player picks something. Message, when not empty, is shown first (say,
  why a login failed). ListHost / ListPort: where the server list comes
  from. False: the window was closed or Esc pressed. }
function RunStartScreen(Win: TGWindow; S: TGSurface; Fetch: TListFetch;
  const Info: TStartInfo; const DataDir, ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;

{ listserver.txt in Dir: first line the host, second the port. Missing:
  DefHost / DefPort. }
procedure ReadListServer(const Dir, DefHost: string; DefPort: Integer;
  out Host: string; out Port: Integer);
{ The first of Names (';' between them) found under the asset roots
  (GAssetDirs) or else in Dir, or ''. }
function FirstFileIn(const Dir, Names: string): string;
{ Windows GUI programs have no standard output open: with arguments, use
  the handles they were given or the console that started them. Elsewhere
  it does nothing. }
procedure OpenConsoleIO;

implementation

{ Windows comes first so GFont's DrawText is the one in scope. }
uses
  GPaths,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils, GTypes, GFont, GAssetDirs;

const
  ColBack = $FF101828;
  ColPanel = $FF1C2840;
  ColEdge = $FF5A6C96;
  ColText = $FFE8ECF4;
  ColLabel = $FF7CFC6C;   { the green labels of the 2.05 dialogs }
  ColDim = $FF8C96AA;
  ColButton = $FF34466E;
  ColButtonHot = $FF4A6296;
  ColField = $FF0A0E18;
  ColFocus = $FFF0D060;
  ColSelect = $FF2E5A9A;

function ParseServerList(const Data: string): TListServers;
var
  R: TGReader;
  Count, I, J, Fields: Integer;
  F: array[0..7] of string;
  S: TListServer;
begin
  Result := nil;
  R := TGReader.Create(Data);
  try
    if R.Eof then Exit;
    Count := R.ReadGChar;
    for I := 1 to Count do
    begin
      if R.Eof then Exit;
      Fields := R.ReadGChar;
      for J := 0 to 7 do F[J] := '';
      for J := 0 to Fields - 1 do
      begin
        if R.Eof then Exit;
        if J <= 7 then F[J] := R.ReadGString else R.ReadGString;
        if R.Overrun then Exit;
      end;
      S.Name := F[0];
      S.Language := F[1];
      S.Description := F[2];
      S.Url := F[3];
      S.Version := F[4];
      S.Players := F[5];
      S.Host := F[6];
      S.Port := StrToIntDef(F[7], 0);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := S;
    end;
  finally
    R.Free;
  end;
end;

function ServerDisplayName(const Name: string): string;
begin
  Result := Name;
  if (Length(Name) > 2) and (Name[2] = ' ') and (Pos(Name[1], 'PH3U') > 0) then
    Result := Copy(Name, 3, MaxInt);
end;

function StartRect(X, Y, W, H: Integer): TStartRect;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

{ ---- drawing helpers ---- }

{ Milliseconds for the caret blink. }
function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

type
  TRectI = record
    X, Y, W, H: Integer;
  end;

function RectI(X, Y, W, H: Integer): TRectI;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function Inside(const R: TRectI; X, Y: Integer): Boolean;
begin
  Result := (X >= R.X) and (Y >= R.Y) and (X < R.X + R.W) and (Y < R.Y + R.H);
end;

procedure Frame(S: TGSurface; const R: TRectI; Fill, Edge: Cardinal);
begin
  S.FillRect(R.X, R.Y, R.W, R.H, Edge);
  S.FillRect(R.X + 1, R.Y + 1, R.W - 2, R.H - 2, Fill);
end;

procedure Button(S: TGSurface; const R: TRectI; const Caption: string; Hot: Boolean);
var
  C: Cardinal;
begin
  if Hot then C := ColButtonHot else C := ColButton;
  Frame(S, R, C, ColEdge);
  DrawText(S, R.X + (R.W - TextWidth(Caption, 2)) div 2, R.Y + (R.H - 14) div 2,
    Caption, ColText, 2);
end;

procedure Field(S: TGSurface; const R: TRectI; const Text: string; Focused, Masked: Boolean);
var
  T: string;
  Edge: Cardinal;
begin
  if Focused then Edge := ColFocus else Edge := ColEdge;
  Frame(S, R, ColField, Edge);
  if Masked then T := StringOfChar('*', Length(Text)) else T := Text;
  { keep the end of a long entry in view }
  while (T <> '') and (TextWidth(T + '_', 2) > R.W - 10) do Delete(T, 1, 1);
  if Focused and ((NowMs div 400) mod 2 = 0) then T := T + '_';
  DrawText(S, R.X + 5, R.Y + (R.H - 14) div 2, T, ColText, 2);
end;

{ Draws Text wrapped to W pixels at scale 1 (or 2); returns the height used. }
function WrappedEx(S: TGSurface; X, Y, W: Integer; const Text: string; Color: Cardinal;
  Scale: Integer; Centered: Boolean): Integer;

  procedure Put(const Line: string);
  begin
    if Centered then
      DrawText(S, X + (W - TextWidth(Line, Scale)) div 2, Y + Result, Line, Color, Scale)
    else
      DrawText(S, X, Y + Result, Line, Color, Scale);
  end;

var
  Words: TStringList;
  Line, Cand: string;
  I: Integer;
begin
  Result := 0;
  Words := TStringList.Create;
  try
    ExtractStrings([' '], [], PChar(Text), Words);
    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      if Line = '' then Cand := Words[I] else Cand := Line + ' ' + Words[I];
      if (TextWidth(Cand, Scale) > W) and (Line <> '') then
      begin
        Put(Line);
        Inc(Result, (GlyphH + 2) * Scale);
        Line := Words[I];
      end
      else
        Line := Cand;
    end;
    if Line <> '' then
    begin
      Put(Line);
      Inc(Result, (GlyphH + 2) * Scale);
    end;
  finally
    Words.Free;
  end;
end;

function Wrapped(S: TGSurface; X, Y, W: Integer; const Text: string; Color: Cardinal;
  Scale: Integer): Integer;
begin
  Result := WrappedEx(S, X, Y, W, Text, Color, Scale, False);
end;

{ Typing into a field: printable characters add, backspace removes. }
procedure EditText(var Text: string; const Chars: string; MaxLen: Integer);
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

{ ---- the two screens ---- }

function RunStartScreen(Win: TGWindow; S: TGSurface; Fetch: TListFetch;
  const Info: TStartInfo; const DataDir, ListHost: string; ListPort: Integer;
  const Message: string; var R: TStartResult): Boolean;
type
  TPage = (pgStart, pgList);
var
  Page: TPage;
  Focus, Sel, I, CX, CY, Y, Top: Integer;
  Clicked: Boolean;
  Chars, Note: string;
  BTraining, BOptions, BStart, BConnect, BRefresh, BBack, FNick, FAcc, FPw, LList: TRectI;
  Srv: TListServer;
const
  RowH = 22;
  Rows = 8;
begin
  Result := False;
  begin
    Page := pgStart;
    Focus := 0;
    Sel := -1;
    Note := Message;
    if R.Nickname = '' then R.Nickname := 'unknown';
    if R.Account = '' then R.Account := 'guest';
    BTraining := RectI(40, 420, 170, 36);
    BOptions := RectI(235, 420, 170, 36);
    BStart := RectI(430, 420, 170, 36);
    FNick := RectI(200, 330, 250, 28);
    FAcc := RectI(150, 70, 200, 28);
    FPw := RectI(150, 104, 200, 28);
    LList := RectI(20, 150, 360, Rows * RowH + 4);
    BConnect := RectI(400, 420, 220, 36);
    BRefresh := RectI(210, 420, 170, 36);
    BBack := RectI(20, 420, 170, 36);
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
      Fetch.Poll;

      if Page = pgStart then
      begin
        { input }
        if Pos(#27, Chars) > 0 then
        begin
          R.Choice := scQuit;
          Exit;
        end;
        EditText(R.Nickname, Chars, 20);
        if Clicked then
        begin
          if Inside(BTraining, CX, CY) then
          begin
            R.Choice := scTraining;
            Result := True;
            Exit;
          end;
          if Inside(BOptions, CX, CY) then
            Note := 'Options are not built yet.';
          if Inside(BStart, CX, CY) then
          begin
            Page := pgList;
            Note := '';
            { the list is asked for with the account and password, so it
              waits for them when there is no password yet }
            if R.Password <> '' then
            begin
              Focus := 0;
              Fetch.Start(ListHost, ListPort, R.Account, R.Password);
            end
            else
            begin
              Focus := 1;
              Fetch.Status := 'Type your account and password, then press Enter or Refresh.';
            end;
          end;
        end;
        { drawing }
        S.Fill(ColBack);
        begin
          for Y := 0 to 299 do
            S.FillRect(0, Y, S.Width, 1, $FF000000 or Cardinal((16 + Y div 12) shl 16) or
              Cardinal((24 + Y div 10) shl 8) or Cardinal(40 + Y div 6));
          DrawText(S, (S.Width - TextWidth(Info.Title, 5)) div 2, 70, Info.Title, ColText, 5);
          DrawText(S, (S.Width - TextWidth(Info.Subtitle, 2)) div 2, 130,
            Info.Subtitle, ColDim, 2);
          Wrapped(S, 60, 190, 520, 'Put a Graal install next to this program to play with ' +
            'its graphics and levels; until then it uses its own.', ColDim, 1);
        end;
        Frame(S, RectI(20, 270, S.Width - 40, 200), ColPanel, ColEdge);
        Wrapped(S, 40, 285, 400, 'Pick a nick name, then Training for the offline levels ' +
          'or Start for the server list.', ColLabel, 1);
        DrawText(S, 40, 337, 'Nick name:', ColLabel, 2);
        Field(S, FNick, R.Nickname, True, False);
        { the character, idle and facing down, beside the panel text }
        if Assigned(Info.DrawCharacter) then Info.DrawCharacter(S, 500, 290, R.Nickname);
        if Note <> '' then DrawText(S, 40, 385, Note, ColFocus, 1);
        Button(S, BTraining, 'Training', Inside(BTraining, Win.MouseX, Win.MouseY));
        Button(S, BOptions, 'Options', Inside(BOptions, Win.MouseX, Win.MouseY));
        Button(S, BStart, 'Start', Inside(BStart, Win.MouseX, Win.MouseY));
      end
      else
      begin
        { input }
        if Pos(#27, Chars) > 0 then
        begin
          Page := pgStart;
          Continue;
        end;
        if Pos(#9, Chars) > 0 then Focus := 1 - Focus;
        if Focus = 0 then EditText(R.Account, Chars, 30) else EditText(R.Password, Chars, 30);
        Top := LList.Y + 2;
        if Clicked then
        begin
          if Inside(FAcc, CX, CY) then Focus := 0;
          if Inside(FPw, CX, CY) then Focus := 1;
          if Inside(LList, CX, CY) then
          begin
            I := (CY - Top) div RowH;
            if (I >= 0) and (I < Length(Fetch.Servers)) then Sel := I;
          end;
          if Inside(BBack, CX, CY) then Page := pgStart;
          if Inside(BRefresh, CX, CY) then
          begin
            Sel := -1;
            Fetch.Start(ListHost, ListPort, R.Account, R.Password);
          end;
          if Inside(BConnect, CX, CY) or ((Pos(#13, Chars) > 0) and (Sel >= 0)) then
            Clicked := True
          else
            Clicked := False;
        end
        else
        begin
          { Enter with no server picked asks for the list }
          if (Pos(#13, Chars) > 0) and (Sel < 0) then
            Fetch.Start(ListHost, ListPort, R.Account, R.Password);
          Clicked := (Pos(#13, Chars) > 0) and (Sel >= 0);
        end;
        if Clicked and (Sel >= 0) and (Sel < Length(Fetch.Servers)) then
        begin
          Srv := Fetch.Servers[Sel];
          R.Choice := scOnline;
          R.Host := Srv.Host;
          R.Port := Srv.Port;
          R.ServerName := ServerDisplayName(Srv.Name);
          Result := True;
          Exit;
        end;
        { drawing }
        S.Fill(ColBack);
        DrawText(S, 20, 18, 'Server list', ColText, 3);
        DrawText(S, 20, 77, 'Account:', ColLabel, 2);
        DrawText(S, 20, 111, 'Password:', ColLabel, 2);
        Field(S, FAcc, R.Account, Focus = 0, False);
        Field(S, FPw, R.Password, Focus = 1, True);
        Frame(S, LList, ColField, ColEdge);
        for I := 0 to Length(Fetch.Servers) - 1 do
        begin
          if I >= Rows then Break;
          if I = Sel then S.FillRect(LList.X + 2, Top + I * RowH, LList.W - 4, RowH, ColSelect);
          DrawText(S, LList.X + 8, Top + I * RowH + 4, Copy(ServerDisplayName(Fetch.Servers[I].Name), 1, 22),
            ColText, 2);
          DrawText(S, LList.X + LList.W - 8 - TextWidth(Fetch.Servers[I].Players, 2),
            Top + I * RowH + 4, Fetch.Servers[I].Players, ColDim, 2);
        end;
        Frame(S, RectI(400, 150, 220, Rows * RowH + 4), ColPanel, ColEdge);
        if (Sel >= 0) and (Sel < Length(Fetch.Servers)) then
        begin
          Srv := Fetch.Servers[Sel];
          Y := 158;
          DrawText(S, 408, Y, 'Language:', ColLabel, 1);
          DrawText(S, 480, Y, Srv.Language, ColText, 1);
          DrawText(S, 408, Y + 14, 'Version:', ColLabel, 1);
          DrawText(S, 480, Y + 14, Srv.Version, ColText, 1);
          DrawText(S, 408, Y + 28, 'Players:', ColLabel, 1);
          DrawText(S, 480, Y + 28, Srv.Players, ColText, 1);
          DrawText(S, 408, Y + 42, 'Address:', ColLabel, 1);
          DrawText(S, 480, Y + 42, Srv.Host + ':' + IntToStr(Srv.Port), ColText, 1);
          Wrapped(S, 408, Y + 62, 204, Srv.Description, ColDim, 1);
        end
        else
          Wrapped(S, 408, 158, 204, 'Pick a server, then Connect.', ColDim, 1);
        Wrapped(S, 20, 345, 600, Fetch.Status, ColDim, 1);
        Button(S, BBack, 'Back', Inside(BBack, Win.MouseX, Win.MouseY));
        Button(S, BRefresh, 'Refresh', Inside(BRefresh, Win.MouseX, Win.MouseY));
        Button(S, BConnect, 'Connect', Inside(BConnect, Win.MouseX, Win.MouseY));
      end;
      Win.Present(S);
      Sleep(20);
    end;
  end;
end;


{ ---- program helpers ---- }

procedure ReadListServer(const Dir, DefHost: string; DefPort: Integer;
  out Host: string; out Port: Integer);
var
  L: TStringList;
begin
  Host := DefHost;
  Port := DefPort;
  if not FileExists(Dir + 'listserver.txt') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(Dir + 'listserver.txt');
    if (L.Count > 0) and (Trim(L[0]) <> '') then Host := Trim(L[0]);
    if L.Count > 1 then Port := StrToIntDef(Trim(L[1]), Port);
  finally
    L.Free;
  end;
end;

function FirstFileIn(const Dir, Names: string): string;
var
  L: TStringList;
  I: Integer;
  P: string;
begin
  Result := '';
  L := TStringList.Create;
  try
    ExtractStrings([';'], [], PChar(Names), L);
    for I := 0 to L.Count - 1 do
    begin
      P := AssetPath(L[I]);
      if P = '' then P := Dir + StringReplace(L[I], '/', DirSlash, [rfReplaceAll]);
      if FileExists(P) and AssetAllowed(P) then
      begin
        Result := P;
        Exit;
      end;
    end;
  finally
    L.Free;
  end;
end;

{$IFDEF MSWINDOWS}{$IFDEF FPC}
function AttachConsole(ProcessId: DWORD): BOOL; stdcall; external 'kernel32.dll';

procedure OpenConsoleIO;
var
  H, E: THandle;
begin
  if IsConsole then Exit;
  H := GetStdHandle(STD_OUTPUT_HANDLE);
  E := GetStdHandle(STD_ERROR_HANDLE);
  try
    if (H = 0) or (H = INVALID_HANDLE_VALUE) then
    begin
      AttachConsole(DWORD(-1)); { ATTACH_PARENT_PROCESS }
      AssignFile(Output, 'CONOUT$');
      Rewrite(Output);
      AssignFile(ErrOutput, 'CONOUT$');
      Rewrite(ErrOutput);
    end
    else
    begin
      StdOutputHandle := H;
      Rewrite(Output);  { assigned to '' by the RTL: the standard output }
      Rewrite(ErrOutput);
      if (E <> 0) and (E <> INVALID_HANDLE_VALUE) then
        TextRec(ErrOutput).Handle := E;
    end;
  except
    { nowhere to write: carry on without output }
  end;
end;
{$ELSE}
procedure OpenConsoleIO;
begin
end;
{$ENDIF}{$ELSE}
procedure OpenConsoleIO;
begin
end;
{$ENDIF}

end.
