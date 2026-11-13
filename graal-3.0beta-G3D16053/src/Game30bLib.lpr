{ Game30bLib: the 3.0beta 2D game (TAdventure and the listserver step) as a
  shared library with a plain C interface, for the Torque control
  GuiGraalCtrl (common/torque/guigraal). The C++ side loads it with dlopen
  and calls the g304_* functions below; game304_abi.h there is the same
  list for C.

  Every function takes the handle g304_create returned. Strings in are
  UTF-8, NUL-terminated. Strings out stay valid until the next call on the
  same handle. No exception leaves the library: a failure is a result of
  0 (or -1) and the text is in g304_error.

  Built by common/torque/guigraal/Makefile (make lib); scripts/build.sh
  builds it on Linux for the release. }
library Game30bLib;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Math,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GBzip2 in '../../common/GBzip2.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GAni in '../../common/GAni.pas',
  GFont in '../../common/GFont.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  Protocol30b in 'Protocol30b.pas',
  GraalClient in 'GraalClient.pas',
  Adventure in 'Adventure.pas',
  ListServer30b in 'ListServer30b.pas',
  StartScreen30b in 'StartScreen30b.pas';

type
  TLogProc = procedure(Ctx: Pointer; Line: PAnsiChar); cdecl;

  TSession = class
  public
    Dir, Nick, Error, Ret, Mode: string;
    G: TAdventure;
    Fetch: TListFetch30b;
    ListHost: string;
    ListPort: Integer;
    Hosts: TListHosts;
    LogProc: TLogProc;
    LogCtx: Pointer;
    constructor Create(const ADir: string);
    destructor Destroy; override;
    procedure Line(const S: string);
    procedure NewGame;
    function Give(const S: string): PAnsiChar;
  end;

constructor TSession.Create(const ADir: string);
begin
  inherited Create;
  Dir := IncludeTrailingPathDelimiter(ADir);
  SetAssetRoots(Dir, ClientBuildLabel);
  ListHostsFor(Dir, ListHost, ListPort, Hosts);
  Mode := '';
  NewGame;
end;

destructor TSession.Destroy;
begin
  Fetch.Free;
  if G <> nil then
  begin
    if G.Client.Connected then
    begin
      G.Client.Flush;
      G.Client.Disconnect;
    end;
    G.Free;
  end;
  inherited Destroy;
end;

procedure TSession.Line(const S: string);
begin
  if Assigned(LogProc) then LogProc(LogCtx, PAnsiChar(AnsiString(S)));
end;

{ One TAdventure per game: the listserver, a connect and offline play each
  start from a fresh one (rebuild policy; 3.04 keeps one session object). }
procedure TSession.NewGame;
begin
  if G <> nil then
  begin
    if G.Client.Connected then G.Client.Disconnect;
    FreeAndNil(G);
  end;
  G := TAdventure.Create;
  G.Echo := False;
  G.OnLine := Line;
  G.UseInstall(Dir);
  if Nick <> '' then G.Player.Nickname := Nick;
end;

function TSession.Give(const S: string): PAnsiChar;
begin
  Ret := S;
  Result := PAnsiChar(Ret);
end;

function S(H: Pointer): TSession; inline;
begin
  Result := TSession(H);
end;

function Str(P: PAnsiChar): string;
begin
  if P = nil then Result := '' else Result := string(AnsiString(P));
end;

{ ---- the C interface ---- }

function g304_create(Dir: PAnsiChar): Pointer; cdecl;
begin
  try
    Result := TSession.Create(Str(Dir));
  except
    Result := nil;
  end;
end;

procedure g304_free(H: Pointer); cdecl;
begin
  try
    S(H).Free;
  except
  end;
end;

procedure g304_set_log(H: Pointer; Proc: TLogProc; Ctx: Pointer); cdecl;
begin
  S(H).LogProc := Proc;
  S(H).LogCtx := Ctx;
end;

function g304_error(H: Pointer): PAnsiChar; cdecl;
begin
  Result := S(H).Give(S(H).Error);
end;

procedure g304_set_nickname(H: Pointer; Nick: PAnsiChar); cdecl;
begin
  S(H).Nick := Str(Nick);
  if S(H).G <> nil then S(H).G.Player.Nickname := S(H).Nick;
end;

{ Starts asking the listserver. 1 started, 0 failed at once. }
function g304_list_open(H: Pointer; Account, Password: PAnsiChar): Integer; cdecl;
var
  T: TSession;
begin
  Result := 0;
  T := S(H);
  try
    FreeAndNil(T.Fetch);
    T.Fetch := TListFetch30b.Create;
    T.Fetch.SetFallbacks(T.Hosts);
    T.Line(Format('server lister: asking %s:%d', [T.ListHost, T.ListPort]));
    T.Fetch.Start(T.ListHost, T.ListPort, Str(Account), Str(Password));
    if T.Fetch.Failed then
    begin
      T.Error := T.Fetch.Status;
      Exit;
    end;
    Result := 1;
  except
    on E: Exception do T.Error := E.Message;
  end;
end;

{ 0 still waiting, 1 the list is in, -1 failed (g304_list_status says why),
  -2 no list asked for. }
function g304_list_poll(H: Pointer): Integer; cdecl;
var
  T: TSession;
begin
  T := S(H);
  Result := -2;
  if T.Fetch = nil then Exit;
  try
    T.Fetch.Poll;
    if T.Fetch.Done then Result := 1
    else if T.Fetch.Failed then
    begin
      Result := -1;
      T.Error := T.Fetch.Status;
    end
    else Result := 0;
  except
    on E: Exception do
    begin
      T.Error := E.Message;
      Result := -1;
    end;
  end;
end;

function g304_list_status(H: Pointer): PAnsiChar; cdecl;
begin
  if S(H).Fetch = nil then Result := S(H).Give('')
  else Result := S(H).Give(S(H).Fetch.Status);
end;

function g304_list_count(H: Pointer): Integer; cdecl;
begin
  if S(H).Fetch = nil then Result := 0
  else Result := Length(S(H).Fetch.Servers);
end;

{ Field F of server I, in the listserver's order: 0 name, 1 language,
  2 description, 3 url, 4 version, 5 players, 6 host, 7 port. }
function g304_list_field(H: Pointer; I, F: Integer): PAnsiChar; cdecl;
var
  V: string;
begin
  V := '';
  if (S(H).Fetch <> nil) and (I >= 0) and (I < Length(S(H).Fetch.Servers)) then
    with S(H).Fetch.Servers[I] do
      case F of
        0: V := Name;
        1: V := Language;
        2: V := Description;
        3: V := Url;
        4: V := Version;
        5: V := Players;
        6: V := Host;
        7: V := IntToStr(Port);
      end;
  Result := S(H).Give(V);
end;

{ Opens the game connection and sends the 3.04 login. 1 connected. }
function g304_connect(H: Pointer; Host: PAnsiChar; Port: Integer;
  Account, Password: PAnsiChar): Integer; cdecl;
var
  T: TSession;
begin
  Result := 0;
  T := S(H);
  try
    T.NewGame;
    T.Mode := 'online';
    if T.G.ConnectServer(Str(Host), Word(Port), Str(Account), Str(Password)) then
      Result := 1
    else
      T.Error := T.G.Client.LastError;
  except
    on E: Exception do T.Error := E.Message;
  end;
end;

const
  TutorialLevels = 'levels/tutorial/offlinetutorial_b-2.graal;levels/offlinetutorial_b-2.nw;' +
    'levels/offlinetutorial_b-2.graal;offlinetutorial_b-2.nw;offlinetutorial_b-2.graal';

{ Loads a level, gmap or .nw from disk for offline play, the player at
  (X, Y) tiles. 1 loaded. A gmap whose cells this rebuild cannot name (the
  3.04 tutorial gmap is GENERATED, with no LEVELNAMES) falls back to the
  tutorial level offlinetutorial_b-2.graal, which 3.04's player unit names
  (304-adventure.md). }
function g304_offline(H: Pointer; Level: PAnsiChar; X, Y: Double): Integer; cdecl;
var
  T: TSession;
  Path, Alt: string;
  OK: Boolean;
begin
  Result := 0;
  T := S(H);
  try
    T.NewGame;
    T.Mode := 'offline';
    Path := Str(Level);
    OK := T.G.LoadLevelFile(Path);
    if not OK and (LowerCase(ExtractFileExt(Path)) = '.gmap') then
    begin
      Alt := FirstFileIn(T.Dir, TutorialLevels);
      T.Line(Format('gmap %s has no level this rebuild can name; playing %s',
        [ExtractFileName(Path), ExtractFileName(Alt)]));
      T.NewGame;
      T.Mode := 'offline';
      OK := (Alt <> '') and T.G.LoadLevelFile(Alt);
    end;
    if not OK then
    begin
      T.Error := T.G.Level.LastError;
      T.Mode := '';
      Exit;
    end;
    T.G.Player.X := X;
    T.G.Player.Y := Y;
    Result := 1;
  except
    on E: Exception do T.Error := E.Message;
  end;
end;

{ The install's offline start (304-adventure.md: startOfflineMode loads
  offlinetutorial.gmap), else the tutorial's first level the start screen
  uses; '' when the install has neither. }
function g304_offline_path(H: Pointer): PAnsiChar; cdecl;
begin
  Result := S(H).Give(FirstFileIn(S(H).Dir,
    'maps/offlinetutorial.gmap;levels/tutorial/offlinetutorial.gmap;levels/offlinetutorial.gmap;' +
    'offlinetutorial.gmap;' + TutorialLevels));
end;

{ Direction keys: 0 up, 1 left, 2 down, 3 right. }
procedure g304_key(H: Pointer; Dir, Down: Integer); cdecl;
begin
  if (S(H).G <> nil) and (Dir >= 0) and (Dir <= 3) then S(H).G.Keys[Dir] := Down <> 0;
end;

procedure g304_say(H: Pointer; Text: PAnsiChar); cdecl;
begin
  try
    if S(H).G <> nil then S(H).G.Say(Str(Text));
  except
    on E: Exception do S(H).Error := E.Message;
  end;
end;

procedure g304_toall(H: Pointer; Text: PAnsiChar); cdecl;
begin
  try
    if (S(H).G <> nil) and S(H).G.Client.Connected then
    begin
      S(H).G.Client.SendToAll(Str(Text));
      S(H).G.Client.Flush;
    end;
  except
    on E: Exception do S(H).Error := E.Message;
  end;
end;

{ One 50 ms frame: network in, the game step, network out, draw. 1 the
  game goes on, 0 an online link dropped (g304_error says why). }
function g304_tick(H: Pointer; Draw: Integer): Integer; cdecl;
var
  T: TSession;
begin
  Result := 1;
  T := S(H);
  if (T.G = nil) or (T.Mode = '') then Exit;
  try
    T.G.Headless := Draw = 0;
    T.G.Tick;
    if (T.Mode = 'online') and not T.G.Client.Connected then
    begin
      T.Error := T.G.Client.LastError;
      if T.Error = '' then T.Error := T.G.DisconnectReason;
      T.Mode := '';
      Result := 0;
    end;
  except
    on E: Exception do
    begin
      T.Error := E.ClassName + ': ' + E.Message;
      Result := 0;
    end;
  end;
end;

{ Bit 0 connected, 1 logged in, 2 board loaded, 3 offline play. }
function g304_state(H: Pointer): Integer; cdecl;
var
  G: TAdventure;
begin
  Result := 0;
  G := S(H).G;
  if G = nil then Exit;
  if G.Client.Connected then Result := Result or 1;
  if G.LoggedIn then Result := Result or 2;
  if G.BoardLoaded then Result := Result or 4;
  if S(H).Mode = 'offline' then Result := Result or 8;
end;

{ The last frame: Width x Height pixels, $AARRGGBB, rows top down. }
function g304_frame(H: Pointer; out W, Hh: Integer): Pointer; cdecl;
var
  Scr: TGSurface;
begin
  Result := nil;
  W := 0;
  Hh := 0;
  if S(H).G = nil then Exit;
  Scr := S(H).G.Screen;
  W := Scr.Width;
  Hh := Scr.Height;
  if Length(Scr.Pixels) > 0 then Result := @Scr.Pixels[0];
end;

{ The player: level name, x, y, direction, as text 'level x y dir'. }
function g304_player(H: Pointer): PAnsiChar; cdecl;
var
  G: TAdventure;
begin
  G := S(H).G;
  if G = nil then Result := S(H).Give('')
  else Result := S(H).Give(Format('%s %.2f %.2f %d', [G.Level.Name, G.Player.X,
    G.Player.Y, G.Player.Dir], DefaultFormatSettings));
end;

exports
  g304_create, g304_free, g304_set_log, g304_error, g304_set_nickname,
  g304_list_open, g304_list_poll, g304_list_status, g304_list_count,
  g304_list_field, g304_connect, g304_offline, g304_offline_path, g304_key,
  g304_say, g304_toall, g304_tick, g304_state, g304_frame, g304_player;

begin
  { The host is C++: no floating-point exception traps from this side. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
end.
