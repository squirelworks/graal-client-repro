{ Adventure: TAdventure, the game state and frame loop of 4.04r2, carried
  over from the 3.153 rebuild (and from 2.22 before it), since all of them
  speak the gen-5 wire. What 4.04r2 does differently, from the notes and
  the lab runs of the real client (graal_analysis protocol/v4x-clients.md,
  version-profiles/4.04-4.20.toml, client-internals/live-behaviour-404.md):
  - the first server is a game server named Login; it hands the client on
    with 178 (x,name,host,port), split on commas only;
  - after the login burst: 23 idle.gani and 157 idle, 46 ENTERLEVEL, 44
    (the window list), the own props, 24, then 34 pics1.png;
  - walking sends GANI and SPRITE on the first step, then X2 / Y2 (78, 79:
    half-pixels, sign in the low bit) every 50 ms tick, only the axes that
    moved; X and Y (15, 16) are never sent; each new gani goes out once per
    connection as 23 NAME.gani and 157;
  - 24 = 9 every 5.14 s, alone in the level too; no tamper check;
  - 98 handled server ids, 182 and 183 among them.
  The notes below are the 2.22 ones they came from.

  As in 2.05, TAdventure owns the level, the local player, the link to the
  server and the frame function that runs on a 50 ms gate. 2.22 adds gmaps
  (a grid of levels played as one world), a level cache that lets it ask
  for a level by mod time (PLI_LEVELWARPMOD), and the 2.1+ player props
  (GANI as a string, OSTYPE, TEXTCODEPAGE, GMAPLEVELX/Y).

  Sources: graal_analysis protocol/player-props.md (2.22 parser sets),
  client-internals/feature-specs/06-gmap-overworld.md (gmap login and edge
  crossings captured from a real 2.22), decomp-findings-2026-10-24-b/
  08-lab-findings-levelchange-24-178.md (39 after each client warp, 24,
  178), the b4_222 capture (first client frame, walk props) and run-222d
  (movement, turns, the link probe). }
unit Adventure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GTypes, GLevel, GSurface, GArrays, GAni, GBuiltin, GAssetDirs, GraalClient, Protocol404;

const
  { The game view. 640x480 is assumed for 2.22 as for 2.05; not read from
    the binary. }
  ScreenW = 640;
  ScreenH = 480;

  { Directions, as the walking routine numbers them. }
  DirUp = 0;
  DirLeft = 1;
  DirDown = 2;
  DirRight = 3;

  { The colour list (client-internals/body-colours-and-attributes.md). }
  ColorTable: array[0..19] of Cardinal = (
    $FFFFFFFF, $FFFFFF00, $FFFFAD6B, $FFFF8484, $FFFF0000, $FFCE1829,
    $FF84FF84, $FF00FF00, $FF00C600, $FF8484FF, $FF0000FF, $FF0000C6,
    $FF840000, $FF00FFFF, $FFFF00FF, $FF840084, $FFCECECE, $FF848484,
    $FF000008, $00000000);


type
  { Images and ganis from the player's install, loaded once and kept. }
  TAssets = class
  private
    FNames: TStringList;  { lower-case key -> TGSurface or TGraalAni }
    function FindFile(const Name: string; const Dirs: array of string): string;
  public
    Dir: string;          { install folder; '' = none }
    Missing: TStringList; { names looked for and not found, once each }
    constructor Create;
    destructor Destroy; override;
    { Nil when not found. Kind picks the sub-folders searched. }
    function Image(const Name, Kind: string): TGSurface;
    function Ani(const Name: string): TGraalAni;
    { A file in the install (levels/ first), or ''. }
    function LevelFile(const Name: string): string;
  end;

  { A level as the client keeps it for the session: the board, links and
    signs as last sent, and the mod time the server gave it. }
  TCachedLevel = class(TAdventureLevel)
  public
    ModTime: Cardinal;
    HasModTime: Boolean;
    HasBoard: Boolean;
  end;

  { A GRMAP001 file: a grid of level names played as one world
    (formats/gmap.md). }
  TGmap = class
  public
    Name: string;
    Width, Height: Integer;
    Cells: TStringList; { row-major level names, '' for an empty cell }
    constructor Create;
    destructor Destroy; override;
    function LoadFromString(const Data: string): Boolean;
    { The level of a cell, or '' outside the grid or for an empty cell. }
    function CellName(CX, CY: Integer): string;
    { The cell of a level name; False when it is not on this map. }
    function FindCell(const Level: string; out CX, CY: Integer): Boolean;
  end;

  TServerPlayer = class
  public
    Id: Integer;
    Nickname, Account, Level, HeadImage, BodyImage, SwordImage, ShieldImage,
    Chat, Language, OsType: string;
    Attr: array[1..5] of string;
    X, Y: Double;       { tiles, top-left of the 3x3-tile sprite box }
    Z, GmapX, GmapY: Integer;
    Sprite, Status, MaxPower, Power, Rupees, Arrows, Bombs: Integer;
    SwordPower, ShieldPower, GlovePower, BombPower, CodePage: Integer;
    Colors: array[0..4] of Integer;
    Dir: Integer;
    AniName: string;
    AniStart: Integer;  { frame the animation started on }
    { -1: the animation runs with time. Otherwise the step to draw (a
      player whose server sends only the old sprite prop). }
    FixedStep: Integer;
    HasGani: Boolean;   { a GANI prop was seen: the pose comes from it }
    Gone: Boolean;      { PCONNECTED or a level leave seen }
    BodyCache: TGSurface; { the body recoloured for this player }
    BodyKey: string;
    constructor Create;
    destructor Destroy; override;
    { Parses a prop stream. Stops at the first id the stream does not
      accept, the way 2.22 does, and returns the ids applied. Other is the
      OTHERPLPROPS stream. Frame is the tick, for a new animation. }
    function ApplyProps(R: TGReader; Other: Boolean; Frame: Integer): string;
    { The pose from an old-style sprite prop (no GANI from the server). }
    procedure PoseFromSprite;
    procedure SetAni(const Name: string; Frame: Integer);
  end;

  TAdventure = class
  private
    FClient: TAdventureClient;
    FLog: TStrings;
    FSentX, FSentY: Double;
    FSentDir, FSentGmapX, FSentGmapY: Integer;
    FNextShowImgMs: Int64;
    FGanisAsked: string;  { ',name,' for each gani asked this connection }
    FSentGani: string;
    FPropsSent: Boolean;
    FOthers: TList;
    { addtiledef lines seen in level scripts: 'prefix'#9'image', newest
      first; FTileDefLevel is the level last scanned }
    FTileDefs: TStringList;
    FTileDefLevel: string;
    FLevels: TStringList;  { lower-case name -> TCachedLevel }
    FLevelDir: string;     { folder of the level file played offline }
    FWarpPending: Boolean; { a link warp was asked of the server }
    FWarpX, FWarpY: Double;
    FWarpLevel: string;
    FWarpTimed: string;    { the level a timed warp waits for }
    FWarpT0: Int64;
    FAdjacentAsked: TStringList;
    FGmapWanted: string;   { a .gmap asked for with WANTFILE }
    FAccount, FPassword, FHost: string;
    FPort: Word;
    { the level that LEVELNAME named last: the data after it is its own
      (a gmap neighbour's data goes to that neighbour, not the player's) }
    FCurrentData: TCachedLevel;
    procedure WarpDone;
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure ClientLog(const Line: string);
    function PointBlocked(PX, PY: Double): Boolean;
    procedure SendLoginFrame;
    procedure SendMovedProps;
    function BodyFor(P: TServerPlayer): TGSurface;
    function GetOther(I: Integer): TServerPlayer;
    function GetOtherCount: Integer;
    function GetCurrent: TCachedLevel;
    procedure SetGmap(const Name: string);
    procedure AskAdjacent;
    procedure CrossEdges;
    procedure ReceiveFile(const Data: string);
    procedure ServerWarp(const Data: string);
    procedure AskGani(const Name: string);
  public
    { The name the client gives the server it is on. The first server is
      Login; 178 names the next one. While the lower-case name starts with
      'login' no players and no HUD are drawn (live-behaviour-404.md). }
    ServerName: string;
    Level: TCachedLevel;   { the level the player is in }
    Gmap: TGmap;           { the active gmap, nil off a gmap or before it loads }
    GmapName: string;      { the active gmap's name, '' off a gmap }
    Player: TServerPlayer;
    Screen: TGSurface;
    Sheet: TGSurface;    { pics1 }
    SheetBuiltin: Boolean; { Sheet is the built-in default }
    Arrays: TGArrays;
    Assets: TAssets;
    Frame: Integer;
    WorldTime: Cardinal;
    ServerMessage, DisconnectReason: string;
    LoggedIn, BoardLoaded: Boolean;
    Frozen: Boolean;
    { No drawing in the tick: for stress runs. }
    Headless: Boolean;
    { Log lines also go to stderr as they happen. The in-memory log keeps
      the last LogKeep lines either way. }
    Echo: Boolean;
    { Timings, in ms: connect to the first board (-1 until then), and
      each link warp from the request to the new board. }
    ConnectAtMs: Int64;
    LoginMs: Integer;
    WarpsSent: Integer;
    WarpTimes: array of Integer; { the first WarpCount entries are used }
    WarpCount: Integer;
    EdgeCrossings: Integer;
    ServerWarps: Integer;
    Handled, Ignored: array[0..255] of Integer;
    { Held direction keys for this tick: up, left, down, right. }
    Keys: array[0..3] of Boolean;
    { The clock the tick reads, in ms; tests set it. }
    ClockMs: Int64;
    UseWallClock: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Log(const S: string);
    { Points pics1, arrays.dat and the image folders at an install. }
    procedure UseInstall(const Dir: string);
    { Draws P with the camera at (CamX, CamY) pixels; also used for the
      character on the start screen. }
    procedure DrawPlayer(P: TServerPlayer; CamX, CamY: Integer);
    { The built-in tile sheet and tile types (done by Create). }
    procedure UseBuiltins;
    { Adds the lines of a tiledefs file (as 3.04's) as addtiledefs. }
    procedure LoadTileDefsFile(const Path: string);
    { Notes the addtiledef lines in L's NPC scripts. }
    procedure NoteTileDefs(L: TAdventureLevel);
    { The tile sheet for a level: an addtiledef image whose prefix starts
      the level name, else pics1. }
    function TileSheetFor(const LevelName: string): TGSurface;
    property TileDefs: TStringList read FTileDefs;
    { the secure login's wait, fallback or stop (GSecLogin) }
    procedure CheckSecureLogin;
    function ConnectServer(const Host: string; Port: Word;
      const Account, Password: string): Boolean;
    { The walking routine for one direction key (one step). }
    procedure WalkStep(Dir: Integer);
    { One frame: network in, game step, network out, draw. }
    procedure Tick;
    procedure Draw;
    { True while the server's name starts with 'login'. }
    function LoginSession: Boolean;
    { Loads a level (or a .gmap and its levels) from disk for offline play;
      links then look for their levels next to it, then in the install. }
    function LoadLevelFile(const FileName: string): Boolean;
    { The cached level of that name; Make adds an empty one. }
    function CachedLevel(const Name: string; Make: Boolean): TCachedLevel;
    { The tile at a position in the current gmap's world (or the level when
      not on a gmap), -1 where no board is known. }
    function WorldTile(GX, GY: Integer): Integer;
    { The link under the player, or -1. }
    function LinkAt(PX, PY: Double): Integer;
    { Takes link I: online, asks the server for the level; offline, loads
      it. Returns False when the level cannot be had. }
    function FollowLink(I: Integer): Boolean;
    { One message from the server, as the client's dispatcher hands it on. }
    procedure Receive(Id: Integer; const Data: string);
    { The gani the player shows now. }
    function OwnGani: string;
    { Another player by id; Make adds it when it is not known yet. }
    function FindOther(Id: Integer; Make: Boolean): TServerPlayer;
    procedure RemoveOther(Id: Integer);
    property Others[I: Integer]: TServerPlayer read GetOther;
    property OtherCount: Integer read GetOtherCount;
    property Client: TAdventureClient read FClient;
    property LogLines: TStrings read FLog;
    property Current: TCachedLevel read GetCurrent;
  end;

{ Wall-clock milliseconds, for login and warp timings. }
function NowMs: Int64;
{ Fallback tile sheet when pics1 is not available: each tile gets a flat
  colour derived from its index, so a frame still shows the board layout. }
procedure MakeIndexSheet(Sheet: TGSurface);
{ Old-style sprite prop -> pose (servers that send no GANI). }
function SpriteWalkStep(Sprite: Integer): Integer;

implementation

uses
  GSecLogin, SysUtils, Math;

procedure MakeIndexSheet(Sheet: TGSurface);
var
  T, SX, SY: Integer;
  H: Cardinal;
begin
  Sheet.SetSize(128 * TileSize, 32 * TileSize);
  for T := 0 to 4095 do
  begin
    TileSheetPos(T, SX, SY);
    { Knuth's multiplicative hash, kept in 32 bits without overflowing }
    H := Cardinal((Int64(T) * 2654435761) and $FFFFFFFF);
    Sheet.FillRect(SX, SY, TileSize, TileSize, $FF000000 or (H shr 8));
    Sheet.FillRect(SX, SY, TileSize, 1, $FF202020);
    Sheet.FillRect(SX, SY, 1, TileSize, $FF202020);
  end;
end;

{ Words split on spaces (TStrings.DelimitedText is newer than Delphi 5). }
procedure SplitSpaces(const S: string; Words: TStrings);
var
  I, St: Integer;
begin
  Words.Clear;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
    if I > Length(S) then Break;
    St := I;
    while (I <= Length(S)) and (S[I] <> ' ') do Inc(I);
    Words.Add(Copy(S, St, I - St));
  end;
end;

function EndsWith(const S, Tail: string): Boolean;
begin
  Result := (Length(S) >= Length(Tail)) and
    (LowerCase(Copy(S, Length(S) - Length(Tail) + 1, MaxInt)) = LowerCase(Tail));
end;

{ TAssets }

constructor TAssets.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FNames.Sorted := True;
  Missing := TStringList.Create;
  Missing.Sorted := True;
  Missing.Duplicates := dupIgnore;
end;

destructor TAssets.Destroy;
var
  I: Integer;
begin
  for I := 0 to FNames.Count - 1 do FNames.Objects[I].Free;
  FNames.Free;
  Missing.Free;
  inherited Destroy;
end;

function TAssets.FindFile(const Name: string; const Dirs: array of string): string;
var
  I, J, K: Integer;
  Base, Cand: string;
  Exts: array[0..2] of string;
begin
  { the asset roots (GAssetDirs), set by UseInstall }
  Result := '';
  if (AssetRootCount = 0) or (Name = '') then Exit;
  Base := ChangeFileExt(Name, '');
  Exts[0] := ExtractFileExt(Name);
  Exts[1] := '.png';
  Exts[2] := '.gif';
  for K := 0 to AssetRootCount - 1 do
    for I := 0 to High(Dirs) do
      for J := 0 to 2 do
      begin
        if Exts[J] = '' then Continue;
        Cand := AssetRoot(K) + Dirs[I] + Base + Exts[J];
        if FileExists(Cand) and AssetAllowed(Cand) then
        begin
          Result := Cand;
          Exit;
        end;
      end;
end;

function TAssets.LevelFile(const Name: string): string;
begin
  Result := '';
  if (Name = '') or (Pos('..', Name) > 0) or (Pos('/', Name) > 0) or
    (Pos('\', Name) > 0) then Exit;
  Result := AssetPath('levels/' + Name);
  { the 4.x installs keep the offline tutorial in levels/tutorial/ }
  if Result = '' then Result := AssetPath('levels/tutorial/' + Name);
  if Result = '' then Result := AssetPath(Name);
end;

function TAssets.Image(const Name, Kind: string): TGSurface;
var
  Key, F, D: string;
  I: Integer;
  S: TGSurface;
  Ok: Boolean;
begin
  Result := nil;
  if Name = '' then Exit;
  { one entry per name and kind: each kind searches its own folders, and a
    miss under one kind (the built-in stand-in) must not hide the file
    another kind finds, e.g. levels/weapons/wbomb1.gif }
  Key := 'img:' + LowerCase(Name);
  if Kind <> '' then Key := Key + '|' + Kind;
  I := FNames.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGSurface(FNames.Objects[I]);
    Exit;
  end;
  if Kind = 'head' then F := FindFile(Name, ['levels/heads/', 'levels/', ''])
  else if Kind = 'body' then F := FindFile(Name, ['levels/bodies/', 'levels/', ''])
  else if Kind = 'sword' then F := FindFile(Name, ['levels/swords/', 'levels/', ''])
  else if Kind = 'shield' then F := FindFile(Name, ['levels/shields/', 'levels/', ''])
  else if Kind = 'hat' then F := FindFile(Name, ['levels/hats/', 'levels/', ''])
  else F := FindFile(Name, ['', 'levels/', 'levels/images/', 'levels/tiles/']);
  S := nil;
  if F <> '' then
  begin
    S := TGSurface.Create(0, 0);
    if Kind = 'body' then Ok := LoadImageIndexed(F, S)
    else Ok := LoadImageFile(F, S);
    if not Ok then FreeAndNil(S);
  end;
  { nothing on disk: the built-in default of that name, if there is one }
  if (S = nil) and BuiltinFile(Name, D) then
  begin
    S := TGSurface.Create(0, 0);
    if not LoadImageData(D, Name, S, Kind = 'body') then FreeAndNil(S);
  end;
  if S = nil then Missing.Add(Name);
  FNames.AddObject(Key, S);
  Result := S;
end;

function TAssets.Ani(const Name: string): TGraalAni;
var
  Key, F, N: string;
  I: Integer;
  A: TGraalAni;
begin
  N := Name;
  if EndsWith(N, '.gani') then SetLength(N, Length(N) - 5);
  Key := 'ani:' + LowerCase(N);
  I := FNames.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGraalAni(FNames.Objects[I]);
    Exit;
  end;
  A := nil;
  if (Dir <> '') and (N <> '') and (Pos('..', N) = 0) then
  begin
    F := IncludeTrailingPathDelimiter(Dir) + 'levels/ganis/' + N + '.gani';
    if not (FileExists(F) and AssetAllowed(F)) then
      F := IncludeTrailingPathDelimiter(Dir) + 'ganis/' + N + '.gani';
    if not AssetAllowed(F) then F := '';
    if FileExists(F) then
    begin
      A := TGraalAni.Create;
      if not A.LoadFromFile(F) then FreeAndNil(A);
    end;
  end;
  if (A = nil) and BuiltinFile(N + '.gani', F) then
  begin
    A := TGraalAni.Create;
    if not A.LoadFromString(F) then FreeAndNil(A);
  end;
  if A = nil then Missing.Add(N + '.gani');
  FNames.AddObject(Key, A);
  Result := A;
end;

{ TGmap }

constructor TGmap.Create;
begin
  inherited Create;
  Cells := TStringList.Create;
end;

destructor TGmap.Destroy;
begin
  Cells.Free;
  inherited Destroy;
end;

function TGmap.LoadFromString(const Data: string): Boolean;
var
  Lines, Row: TStringList;
  I, J: Integer;
  S, W: string;
  InNames: Boolean;
begin
  Result := False;
  Width := 0;
  Height := 0;
  Cells.Clear;
  Lines := TStringList.Create;
  Row := TStringList.Create;
  try
    Lines.Text := StringReplace(Data, #13, '', [rfReplaceAll]);
    if (Lines.Count = 0) or (Trim(Lines[0]) <> 'GRMAP001') then Exit;
    InNames := False;
    for I := 1 to Lines.Count - 1 do
    begin
      S := Trim(Lines[I]);
      if InNames then
      begin
        if S = 'LEVELNAMESEND' then
        begin
          InNames := False;
          Continue;
        end;
        Row.CommaText := S;
        for J := 0 to Row.Count - 1 do Cells.Add(Trim(Row[J]));
        Continue;
      end;
      W := UpperCase(Copy(S, 1, Pos(' ', S + ' ') - 1));
      if W = 'WIDTH' then Width := StrToIntDef(Trim(Copy(S, 6, MaxInt)), 0)
      else if W = 'HEIGHT' then Height := StrToIntDef(Trim(Copy(S, 7, MaxInt)), 0)
      else if W = 'LEVELNAMES' then InNames := True;
    end;
    if (Width <= 0) or (Height <= 0) or (Width > 256) or (Height > 256) then Exit;
    while Cells.Count < Width * Height do Cells.Add('');
    Result := True;
  finally
    Lines.Free;
    Row.Free;
  end;
end;

function TGmap.CellName(CX, CY: Integer): string;
begin
  Result := '';
  if (CX < 0) or (CY < 0) or (CX >= Width) or (CY >= Height) then Exit;
  Result := Cells[CY * Width + CX];
end;

function TGmap.FindCell(const Level: string; out CX, CY: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  CX := 0;
  CY := 0;
  if Width <= 0 then Exit;
  for I := 0 to Width * Height - 1 do
    if (Cells[I] <> '') and (LowerCase(Cells[I]) = LowerCase(Level)) then
    begin
      CX := I mod Width;
      CY := I div Width;
      Result := True;
      Exit;
    end;
end;

{ TServerPlayer }

constructor TServerPlayer.Create;
begin
  inherited Create;
  { a new player: orange, darkred, black, darkred, black; body.png; head0 }
  Colors[0] := 2;
  Colors[1] := 5;
  Colors[2] := 18;
  Colors[3] := 5;
  Colors[4] := 18;
  BodyImage := 'body.png';
  HeadImage := 'head0.png';
  Dir := DirDown;
  AniName := 'idle';
  FixedStep := -1;
  Language := 'English';
end;

destructor TServerPlayer.Destroy;
begin
  BodyCache.Free;
  inherited Destroy;
end;

{ The walk frames of the classic sprite numbers (2.05 sprite-step table):
  sprite numbers 1 to 5 are walk poses. }
function SpriteWalkStep(Sprite: Integer): Integer;
const
  Steps: array[1..5] of Integer = (3, 2, 1, 0, 0);
var
  S: Integer;
begin
  S := Sprite div 4;
  if (S >= 1) and (S <= 5) then Result := Steps[S] else Result := -1;
end;

procedure TServerPlayer.PoseFromSprite;
var
  St: Integer;
begin
  St := SpriteWalkStep(Sprite);
  if St >= 0 then
  begin
    AniName := 'walk';
    FixedStep := St;
  end
  else
  begin
    AniName := 'idle';
    FixedStep := 0;
  end;
end;

procedure TServerPlayer.SetAni(const Name: string; Frame: Integer);
begin
  if Name <> AniName then
  begin
    AniName := Name;
    AniStart := Frame;
  end;
end;

function TServerPlayer.ApplyProps(R: TGReader; Other: Boolean; Frame: Integer): string;
var
  P, V, I: Integer;
  S: string;
begin
  Result := '';
  while not R.Eof do
  begin
    P := R.ReadGChar;
    { the ids the parsers accept: 2.22's, raised to 80 as in 2.31 and
      3.153 (protocol/player-props.md; version-profiles/3.04-3.153.md),
      which 4.x keeps (X2 / Y2 / Z2) }
    if Other then
    begin
      if (P = 1) or ((P >= 3) and (P <= 7)) or (P = 14) or (P = 22) or
        ((P >= 25) and (P <= 29)) or (P = 77) or (P > 80) then Exit;
    end
    else if (P = 50) or (P = 51) or (P = 53) or ((P >= 75) and (P <= 77)) or
      (P > 80) then Exit;
    case P of
      PLPROP_NICKNAME: Nickname := R.ReadGString;
      PLPROP_MAXPOWER: MaxPower := R.ReadGChar;
      PLPROP_CURPOWER: Power := R.ReadGChar;
      PLPROP_RUPEESCOUNT: Rupees := R.ReadGInt3;
      PLPROP_ARROWSCOUNT: Arrows := R.ReadGChar;
      PLPROP_BOMBSCOUNT: Bombs := R.ReadGChar;
      PLPROP_GLOVEPOWER: GlovePower := R.ReadGChar;
      PLPROP_BOMBPOWER: BombPower := R.ReadGChar;
      PLPROP_SWORDPOWER: { c(power + 30) + image, or c(power) }
        begin
          V := R.ReadGChar;
          if V > 4 then
          begin
            SwordPower := V - 30;
            SwordImage := R.ReadGString;
          end
          else
            SwordPower := V;
        end;
      PLPROP_SHIELDPOWER: { c(power + 10) + image, or c(power) }
        begin
          V := R.ReadGChar;
          if V > 3 then
          begin
            ShieldPower := V - 10;
            ShieldImage := R.ReadGString;
          end
          else
            ShieldPower := V;
        end;
      PLPROP_GANI: { 2.1 and later: the animation name }
        begin
          S := R.ReadGString;
          if EndsWith(S, '.gani') then SetLength(S, Length(S) - 5);
          if S <> '' then
          begin
            HasGani := True;
            FixedStep := -1;
            SetAni(S, Frame);
          end;
        end;
      PLPROP_HEADGIF:
        begin
          V := R.ReadGChar;
          if V >= 100 then
            HeadImage := R.ReadChars(V - 100)
          else
            HeadImage := 'head' + IntToStr(V) + '.png';
        end;
      PLPROP_CURCHAT: Chat := R.ReadGString;
      PLPROP_COLORS: for I := 0 to 4 do Colors[I] := R.ReadGChar;
      PLPROP_ID: Id := R.ReadGShort;
      PLPROP_X: X := R.ReadGChar / 2;
      PLPROP_Y: Y := R.ReadGChar / 2;
      PLPROP_SPRITE:
        begin
          Sprite := R.ReadGChar;
          Dir := Sprite mod 4;
          if Other and not HasGani then PoseFromSprite;
        end;
      PLPROP_STATUS: Status := R.ReadGChar;
      PLPROP_GMAPLEVELX: GmapX := R.ReadGChar;
      PLPROP_GMAPLEVELY: GmapY := R.ReadGChar;
      PLPROP_Z: Z := R.ReadGChar - 50;
      PLPROP_CARRYSPRITE, PLPROP_HORSEBUSHES, PLPROP_EFFECTCOLORS,
      PLPROP_MAGICPOINTS, PLPROP_ALIGNMENT, PLPROP_ADDITFLAGS, PLPROP_PSTATUSMSG:
        R.ReadGChar;
      PLPROP_JOINLEAVELVL: if R.ReadGChar = 0 then Gone := True;
      PLPROP_CURLEVEL: Level := R.ReadGString;
      PLPROP_GATTRIB1..PLPROP_GATTRIB5:
        Attr[P - PLPROP_GATTRIB1 + 1] := R.ReadGString;
      PLPROP_ACCOUNTNAME: Account := R.ReadGString;
      PLPROP_BODYIMG: BodyImage := R.ReadGString;
      PLPROP_PLANGUAGE: Language := R.ReadGString;
      PLPROP_OSTYPE: OsType := R.ReadGString;
      PLPROP_TEXTCODEPAGE: CodePage := R.ReadGInt3;
      PLPROP_X2, PLPROP_Y2, PLPROP_Z2:
        { s: abs(v * 16) shl 1, low bit = sign; half-pixels }
        begin
          V := R.ReadGShort;
          if (V and 1) <> 0 then V := -(V shr 1) else V := V shr 1;
          case P of
            PLPROP_X2: X := V / 16;
            PLPROP_Y2: Y := V / 16;
          else
            Z := Round(V / 16);
          end;
        end;
      PLPROP_HORSEGIF, PLPROP_GATTRIB6..PLPROP_GATTRIB9,
      PLPROP_GATTRIB10..PLPROP_GATTRIB30:
        R.ReadGString;
      PLPROP_CARRYNPC, PLPROP_KILLSCOUNT, PLPROP_DEATHSCOUNT,
      PLPROP_ONLINESECS, PLPROP_UDPPORT, PLPROP_RATING:
        R.ReadGInt3;
      PLPROP_APCOUNTER: R.ReadGShort;
      PLPROP_IPADDR: R.ReadGInt5;
      PLPROP_ATTACHNPC:
        begin
          R.ReadGChar;
          R.ReadGInt3;
        end;
      PLPROP_PCONNECTED:
        begin
          Gone := True;
          if not R.Eof then R.ReadByte;
        end;
    else
      Exit; { unknown size: the rest of the stream is lost }
    end;
    if R.Overrun then Exit;
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(P);
  end;
end;

{ TAdventure }

constructor TAdventure.Create;
begin
  inherited Create;
  FLog := TStringList.Create;
  LoginMs := -1;
  UseWallClock := True;
  FClient := TAdventureClient.Create;
  FClient.OnMessage := HandleMessage;
  FClient.OnLog := ClientLog;
  FLevels := TStringList.Create;
  FLevels.Sorted := True;
  FAdjacentAsked := TStringList.Create;
  FAdjacentAsked.Sorted := True;
  FAdjacentAsked.Duplicates := dupIgnore;
  Level := CachedLevel('', True);
  Player := TServerPlayer.Create;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Sheet := TGSurface.Create(0, 0);
  Arrays := TGArrays.Create;
  Assets := TAssets.Create;
  FOthers := TList.Create;
  FTileDefs := TStringList.Create;
  UseBuiltins;
end;

procedure TAdventure.UseBuiltins;
var
  D: string;
begin
  if BuiltinFile('pics1.png', D) and LoadImageData(D, 'pics1.png', Sheet, False) then
    SheetBuiltin := True;
  if BuiltinFile('arrays.dat', D) then Arrays.LoadFromString(D);
end;

destructor TAdventure.Destroy;
var
  I: Integer;
begin
  FClient.Free;
  for I := 0 to FLevels.Count - 1 do FLevels.Objects[I].Free;
  FLevels.Free;
  FAdjacentAsked.Free;
  Gmap.Free;
  Player.Free;
  Screen.Free;
  Sheet.Free;
  Arrays.Free;
  Assets.Free;
  for I := 0 to FOthers.Count - 1 do TServerPlayer(FOthers[I]).Free;
  FOthers.Free;
  FTileDefs.Free;
  FLog.Free;
  inherited Destroy;
end;

function NowMs: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

{ A duration in ms that fits an Integer, whatever the clock did. }
function ClampMs(V: Int64): Integer;
begin
  if V < 0 then Result := 0
  else if V > MaxInt then Result := MaxInt
  else Result := V;
end;

const
  LogKeep = 1000;

procedure TAdventure.Log(const S: string);
var
  Line: string;
begin
  Line := Format('[%5d] %s', [Frame, S]);
  if Echo then WriteLn(ErrOutput, Line);
  if FLog.Count >= LogKeep then FLog.Delete(0);
  FLog.Add(Line);
end;

procedure TAdventure.ClientLog(const Line: string);
begin
  Log(Line);
end;

function TAdventure.GetCurrent: TCachedLevel;
begin
  Result := Level;
end;

function TAdventure.CachedLevel(const Name: string; Make: Boolean): TCachedLevel;
var
  I: Integer;
begin
  I := FLevels.IndexOf(LowerCase(Name));
  if I >= 0 then
  begin
    Result := TCachedLevel(FLevels.Objects[I]);
    Exit;
  end;
  Result := nil;
  if not Make then Exit;
  Result := TCachedLevel.Create;
  Result.Name := Name;
  FLevels.AddObject(LowerCase(Name), Result);
end;

{ The first of Rels found under the asset roots, or ''. }
function FirstAssetPath(const Rels: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Rels) do
  begin
    Result := AssetPath(Rels[I]);
    if Result <> '' then Exit;
  end;
end;

procedure TAdventure.UseInstall(const Dir: string);
var
  P: string;
begin
  Assets.Dir := Dir;
  { the folder itself, then graal-assets/<version>/ and graal-assets/common/ }
  SetAssetRoots(Dir, ClientBuildLabel);
  if AssetsFolder <> '' then Log('assets: ' + AssetsFolder);
  { the install's tile sheet and tile types replace the built-in ones, but
    not a sheet given with --sheet }
  if (Sheet.Width = 0) or SheetBuiltin then
  begin
    { the 4.x installs keep their tile sheets in levels/tiles/ }
    P := FirstAssetPath(['pics1.png', 'pics1.gif', 'levels/tiles/pics1.png',
      'levels/tiles/pics1.gif']);
    if (P <> '') and LoadImageFile(P, Sheet) then SheetBuiltin := False;
  end;
  LoadTileDefsFile(AssetPath('levels/tiledefs/tiledefsOffline.txt'));
  P := AssetPath('arrays.dat');
  if (P <> '') and Arrays.LoadFromFile(P) then
    Log('arrays.dat loaded')
  else
    Log('arrays.dat not found in ' + Dir + ': using the built-in tile types');
end;

{ The tile definitions file 3.04 reads for offline play
  (levels/tiledefs/tiledefsOffline.txt; lab-304-linux-2026-10-30.md): one
  line per sheet, IMAGE,PREFIX,... Each line is taken as an addtiledef.
  The 4.x installs ship no such file; one dropped there is read. }
procedure TAdventure.LoadTileDefsFile(const Path: string);
var
  L, Parts: TStringList;
  I: Integer;
  Img, Prefix: string;
begin
  if Path = '' then Exit;
  L := TStringList.Create;
  Parts := TStringList.Create;
  try
    try
      L.LoadFromFile(Path);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
    begin
      Parts.Clear;
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Trim(L[I]);
      if Parts.Count < 2 then Continue;
      Img := Trim(Parts[0]);
      Prefix := LowerCase(Trim(Parts[1]));
      if (Img = '') or (Pos('..', Img) > 0) then Continue;
      if FTileDefs.IndexOf(Prefix + #9 + Img) < 0 then
        FTileDefs.Add(Prefix + #9 + Img);
    end;
    Log(Format('%d tile definitions from %s', [FTileDefs.Count, ExtractFileName(Path)]));
  finally
    Parts.Free;
    L.Free;
  end;
end;

procedure TAdventure.CheckSecureLogin;
begin
  FClient.CheckSecure;
  if not (FClient.Sec.State in [ssRefused, ssNoAnswer, ssFailed]) then Exit;
  if (FClient.Sec.State <> ssFailed) and MayFallBack(FClient.Sec.Mode, FClient.Sec.Server) then
  begin
    { auto: this server does not speak SEI00001 (graal-client-repro #148);
      log in the original way and skip the probe there next time }
    Log('secure login: ' + FClient.Sec.Why + '; logging in the original way');
    RememberRefused(FClient.Sec.Server);
    FClient.Disconnect;
    FClient.Sec.ForceClassic := True;
    if FClient.Connect(FHost, FPort) then
    begin
      FClient.SendLogin(FAccount, FPassword, 'English');
      FClient.Flush;
    end
    else
      Log('connect failed: ' + FClient.LastError);
    Exit;
  end;
  DisconnectReason := 'secure login: ' + FClient.Sec.Why;
  Log(DisconnectReason);
  FClient.Disconnect;
  FClient.Sec.Finish;
end;

function TAdventure.ConnectServer(const Host: string; Port: Word;
  const Account, Password: string): Boolean;
begin
  FHost := Host;
  FPort := Port;
  FAccount := Account;
  FPassword := Password;
  ConnectAtMs := NowMs;
  LoginMs := -1;
  FClient.Sec.Mode := ConfiguredSecMode;
  FClient.Sec.ServerKey := ConfiguredServerKey;
  FClient.Sec.ForceClassic := False;
  Result := FClient.Connect(Host, Port);
  if not Result then
  begin
    Log('connect failed: ' + FClient.LastError);
    Exit;
  end;
  Log(Format('connected to %s:%d, key %d, token %s', [Host, Port, FClient.Key,
    ClientVersionToken]));
  FClient.SendLogin(Account, Password, 'English');
  FClient.Flush;
end;

{ ---- walking (client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md;
  run-222d shows 2.22 moving 0.5 a frame, as 2.05 does) ---- }

function TileOf(V: Double): Integer;
begin
  Result := Floor(V + 0.0001);
end;

function TAdventure.WorldTile(GX, GY: Integer): Integer;
var
  CX, CY: Integer;
  L: TCachedLevel;
begin
  Result := -1;
  if Gmap = nil then
  begin
    if (GX < 0) or (GY < 0) or (GX >= BoardW) or (GY >= BoardH) then Exit;
    Result := Level.Tile(GX, GY);
    Exit;
  end;
  if (GX < 0) or (GY < 0) then Exit;
  CX := GX div BoardW;
  CY := GY div BoardH;
  L := CachedLevel(Gmap.CellName(CX, CY), False);
  if (L = nil) or (Gmap.CellName(CX, CY) = '') then Exit;
  Result := L.Tile(GX - CX * BoardW, GY - CY * BoardH);
end;

function TAdventure.PointBlocked(PX, PY: Double): Boolean;
var
  TX, TY, I, T: Integer;
begin
  Result := False;
  { chests: x, y to x + 2, y + 2, edges included, opened or not }
  for I := 0 to High(Level.Chests) do
    if (PX >= Level.Chests[I].X) and (PX <= Level.Chests[I].X + 2) and
      (PY >= Level.Chests[I].Y) and (PY <= Level.Chests[I].Y + 2) then
    begin
      Result := True;
      Exit;
    end;
  TX := TileOf(PX);
  TY := TileOf(PY);
  if Gmap = nil then
  begin
    { off a gmap the edge is open, so level links can be reached (as in
      2.05; run-222d: the player reaches x = -0.5 on the level's left
      edge) }
    if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
    Result := not Arrays.TilePassable(Level.Tile(TX, TY));
    Exit;
  end;
  { on a gmap the neighbours' boards decide; the outer edge of the map
    and cells whose level has not arrived are walls (not measured) }
  T := WorldTile(TX + Player.GmapX * BoardW, TY + Player.GmapY * BoardH);
  if T < 0 then Result := True
  else Result := not Arrays.TilePassable(T);
end;

procedure TAdventure.WalkStep(Dir: Integer);
const
  StepX: array[0..3] of Double = (0, -0.5, 0, 0.5);
  StepY: array[0..3] of Double = (-0.5, 0, 0.5, 0);
  { probe offsets from the sprite's top-left: fixed axis, then six points }
  Fixed: array[0..3] of Double = (1.0, 0.5, 3.0, 2.5);
  Along: array[0..3, 0..5] of Double = (
    (0.525, 1.475, 1.525, 2.475, 2.525, 0.475),
    (1.025, 1.975, 2.025, 2.975, 3.025, 0.975),
    (0.525, 1.475, 1.525, 2.475, 2.525, 0.475),
    (1.025, 1.975, 2.025, 2.975, 3.025, 0.975));
  Speed = 1.0; { on foot }
var
  NX, NY, F: Double;
  B: array[0..5] of Boolean;
  I: Integer;
begin
  Player.Dir := Dir;
  NX := Player.X + StepX[Dir] * Speed;
  NY := Player.Y + StepY[Dir] * Speed;
  for I := 0 to 5 do
    if (Dir = DirUp) or (Dir = DirDown) then
      B[I] := PointBlocked(NX + Along[Dir, I], NY + Fixed[Dir])
    else
      B[I] := PointBlocked(NX + Fixed[Dir], NY + Along[Dir, I]);
  if B[0] or B[1] or B[2] or B[3] then
  begin
    { 1. corner nudge }
    if B[0] and not B[2] and not B[3] and not B[4] then
    begin
      if (Dir = DirUp) or (Dir = DirDown) then NX := NX + 0.1 else NY := NY + 0.1;
    end
    else if not B[0] and not B[1] and B[3] and not B[5] then
    begin
      if (Dir = DirUp) or (Dir = DirDown) then NX := NX - 0.1 else NY := NY - 0.1;
    end;
    { 2. take the step back, the nudge stays }
    NX := NX - StepX[Dir] * Speed;
    NY := NY - StepY[Dir] * Speed;
    { 3. flush snap along the facing, when the fraction is above zero }
    case Dir of
      DirUp: if Frac(NY) > 0 then NY := Floor(NY);
      DirLeft: if Frac(NX + 0.5) > 0 then NX := Floor(NX + 0.5) - 0.5;
      DirDown: if Frac(NY) > 0 then NY := Floor(NY + 1);
      DirRight: if Frac(NX + 0.5) > 0 then NX := Floor(NX + 1.5) - 0.5;
    end;
  end;
  { after every step: snap out of the thin band at a tile line }
  F := NY - Floor(NY);
  if (F < 0.0625) or (F > 0.9375) then NY := Floor(NY + 0.0625);
  F := (NX + 0.5) - Floor(NX + 0.5);
  if (F < 0.0625) or (F > 0.9375) then NX := Floor(NX + 0.5 + 0.0625) - 0.5;
  Player.X := NX;
  Player.Y := NY;
end;

{ ---- other players ---- }

function TAdventure.GetOther(I: Integer): TServerPlayer;
begin
  Result := TServerPlayer(FOthers[I]);
end;

function TAdventure.GetOtherCount: Integer;
begin
  Result := FOthers.Count;
end;

function TAdventure.FindOther(Id: Integer; Make: Boolean): TServerPlayer;
var
  I: Integer;
begin
  for I := 0 to FOthers.Count - 1 do
  begin
    Result := TServerPlayer(FOthers[I]);
    if Result.Id = Id then Exit;
  end;
  Result := nil;
  if not Make then Exit;
  Result := TServerPlayer.Create;
  Result.Id := Id;
  Result.FixedStep := 0;
  FOthers.Add(Result);
end;

procedure TAdventure.RemoveOther(Id: Integer);
var
  P: TServerPlayer;
begin
  P := FindOther(Id, False);
  if P = nil then Exit;
  FOthers.Remove(P);
  P.Free;
end;

{ ---- levels, gmaps, links ---- }

function ReadFileText(const FileName: string; out Data: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Data := '';
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Data, F.Size);
      if F.Size > 0 then F.ReadBuffer(Data[1], F.Size);
      Result := True;
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TAdventure.SetGmap(const Name: string);
var
  F, Data: string;
begin
  if (Gmap <> nil) and (LowerCase(Gmap.Name) = LowerCase(Name)) then Exit;
  GmapName := Name;
  FreeAndNil(Gmap);
  FAdjacentAsked.Clear;
  { the install (or the folder of an offline level) first, then the server }
  F := '';
  if (FLevelDir <> '') and (LevelSibling(FLevelDir, Name) <> '') then F := LevelSibling(FLevelDir, Name)
  else F := Assets.LevelFile(Name);
  if (F <> '') and ReadFileText(F, Data) then
  begin
    Gmap := TGmap.Create;
    Gmap.Name := Name;
    if not Gmap.LoadFromString(Data) then
    begin
      Log('gmap ' + Name + ': not a GRMAP001 file');
      FreeAndNil(Gmap);
    end;
  end;
  if (Gmap = nil) and FClient.Connected and (FGmapWanted <> Name) then
  begin
    FClient.SendPacket(PLI_WANTFILE, Name);
    FGmapWanted := Name;
    Log('WANTFILE ' + Name);
  end;
  if Gmap <> nil then
    Log(Format('gmap %s: %dx%d', [Name, Gmap.Width, Gmap.Height]));
end;

{ PLI_ADJACENTLEVEL for the 3x3 neighbourhood, the current cell skipped,
  in row order (lan-222m): i5 mod time (0 when not cached) + name. }
procedure TAdventure.AskAdjacent;
var
  DX, DY: Integer;
  N: string;
  L: TCachedLevel;
  MT: Cardinal;
begin
  if (Gmap = nil) or not FClient.Connected then Exit;
  for DX := -1 to 1 do
    for DY := -1 to 1 do
    begin
      if (DX = 0) and (DY = 0) then Continue;
      N := Gmap.CellName(Player.GmapX + DX, Player.GmapY + DY);
      if N = '' then Continue;
      if FAdjacentAsked.IndexOf(LowerCase(N)) >= 0 then Continue;
      FAdjacentAsked.Add(LowerCase(N));
      L := CachedLevel(N, False);
      MT := 0;
      if (L <> nil) and L.HasModTime and L.HasBoard then MT := L.ModTime;
      FClient.SendPacket(PLI_ADJACENTLEVEL, GInt5(MT) + N);
    end;
end;

function TAdventure.LoadLevelFile(const FileName: string): Boolean;
var
  Data, N, P, D: string;
  CX, CY: Integer;
  L: TCachedLevel;
begin
  Result := False;
  FLevelDir := ExtractFilePath(FileName);
  if EndsWith(FileName, '.gmap') then
  begin
    SetGmap(ExtractFileName(FileName));
    if Gmap = nil then
    begin
      Level.LastError := 'cannot read the gmap';
      Exit;
    end;
    { every cell's level from the same folder }
    for CY := 0 to Gmap.Height - 1 do
      for CX := 0 to Gmap.Width - 1 do
      begin
        N := Gmap.CellName(CX, CY);
        if N = '' then Continue;
        P := LevelSibling(FLevelDir, N);
        if not FileExists(P) then P := Assets.LevelFile(N);
        L := CachedLevel(N, True);
        if (P <> '') and L.LoadFromFile(P) then L.HasBoard := True;
        L.Name := N;
      end;
    Player.GmapX := 0;
    Player.GmapY := 0;
    Level := CachedLevel(Gmap.CellName(0, 0), True);
    Player.Level := GmapName;
    Result := Level.HasBoard;
    Exit;
  end;
  FreeAndNil(Gmap);
  GmapName := '';
  L := CachedLevel(ExtractFileName(FileName), True);
  if not FileExists(FileName) and BuiltinFile(ExtractFileName(FileName), D) and
    (LowerCase(ExtractFileExt(FileName)) <> '.png') then
  begin
    { a built-in level: links from it look in the install, then here }
    Result := L.LoadFromString(D);
    FLevelDir := '';
  end
  else
    Result := L.LoadFromFile(FileName);
  L.HasBoard := Result;
  L.Name := ExtractFileName(FileName);
  if not Result then Level.LastError := L.LastError;
  if Result then Level := L;
  Player.Level := Level.Name;
end;

function TAdventure.LinkAt(PX, PY: Double): Integer;
var
  I: Integer;
  L: TLevelLink;
begin
  for I := 0 to High(Level.Links) do
  begin
    L := Level.Links[I];
    if (PX >= L.X) and (PX < L.X + L.W) and (PY >= L.Y) and (PY < L.Y + L.H) then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

{ An arrival is a number, or playerx / playery (or a negative number, "-1"
  in 2.22's own reading) for "keep the player's coordinate". }
function Arrival(const S: string; Keep: Double): Double;
var
  V: Double;
begin
  Result := Keep;
  if (S = '') or (LowerCase(Copy(S, 1, 6)) = 'player') then Exit;
  if not TryStrToFloat(S, V) then Exit;
  if V >= 0 then Result := V;
end;

function TAdventure.FollowLink(I: Integer): Boolean;
var
  L: TLevelLink;
  NX, NY: Double;
  Path: string;
  C: TCachedLevel;
begin
  Result := False;
  if (I < 0) or (I > High(Level.Links)) then Exit;
  L := Level.Links[I];
  NX := Arrival(L.NewX, Player.X);
  NY := Arrival(L.NewY, Player.Y);
  if FClient.Connected then
  begin
    if FWarpPending then Exit;
    { 2.22 asks with LEVELWARPMOD when it holds the level (its mod time
      first), else with LEVELWARP; 4.04r2 is taken to do the same, with no
      tamper check after it }
    C := CachedLevel(L.Dest, False);
    if (C <> nil) and C.HasModTime and C.HasBoard then
      FClient.SendPacket(PLI_LEVELWARPMOD, GInt5(C.ModTime) +
        GChar(Round(NX * 2)) + GChar(Round(NY * 2)) + L.Dest)
    else
      FClient.SendPacket(PLI_LEVELWARP, GChar(Round(NX * 2)) +
        GChar(Round(NY * 2)) + L.Dest);
    FWarpPending := True;
    FWarpX := NX;
    FWarpY := NY;
    FWarpLevel := L.Dest;
    Inc(WarpsSent);
    FWarpTimed := L.Dest;
    FWarpT0 := NowMs;
    Log(Format('LEVELWARP %s %.1f,%.1f', [L.Dest, NX, NY]));
    Result := True;
    Exit;
  end;
  Path := '';
  if (FLevelDir <> '') and (LevelSibling(FLevelDir, L.Dest) <> '') then
    Path := LevelSibling(FLevelDir, L.Dest)
  else
    Path := Assets.LevelFile(L.Dest);
  if Path = '' then Path := L.Dest; { LoadLevelFile tries the built-in ones }
  if not LoadLevelFile(Path) then
  begin
    Log('link to ' + L.Dest + ': ' + Level.LastError);
    Exit;
  end;
  if Gmap <> nil then
  begin
    { a link into a gmap: the arrival is in that map's first cell }
    Player.GmapX := 0;
    Player.GmapY := 0;
  end;
  Player.X := NX;
  Player.Y := NY;
  Log(Format('link to %s at %.1f,%.1f', [Level.Name, NX, NY]));
  Result := True;
end;

{ A timed link warp has its board: one more warp time. }
procedure TAdventure.WarpDone;
begin
  if FWarpTimed = '' then Exit;
  if WarpCount = Length(WarpTimes) then
    SetLength(WarpTimes, 2 * WarpCount + 16);
  WarpTimes[WarpCount] := ClampMs(NowMs - FWarpT0);
  Inc(WarpCount);
  FWarpTimed := '';
end;

{ ---- gmap edges (06-gmap-overworld.md, the 2.22 lab capture): crossing is
  client-driven; the wrapped local position and the changed cell prop go
  out in one props message, and 2.22 re-sends the tamper check ---- }

procedure TAdventure.CrossEdges;
var
  Crossed: Boolean;
  N: string;
begin
  if Gmap = nil then Exit;
  Crossed := False;
  if (Player.X >= BoardW) and (Gmap.CellName(Player.GmapX + 1, Player.GmapY) <> '') then
  begin
    Player.X := Player.X - BoardW;
    Inc(Player.GmapX);
    Crossed := True;
  end
  else if (Player.X < 0) and (Gmap.CellName(Player.GmapX - 1, Player.GmapY) <> '') then
  begin
    Player.X := Player.X + BoardW;
    Dec(Player.GmapX);
    Crossed := True;
  end;
  if (Player.Y >= BoardH) and (Gmap.CellName(Player.GmapX, Player.GmapY + 1) <> '') then
  begin
    Player.Y := Player.Y - BoardH;
    Inc(Player.GmapY);
    Crossed := True;
  end
  else if (Player.Y < 0) and (Gmap.CellName(Player.GmapX, Player.GmapY - 1) <> '') then
  begin
    Player.Y := Player.Y + BoardH;
    Dec(Player.GmapY);
    Crossed := True;
  end;
  if not Crossed then Exit;
  Inc(EdgeCrossings);
  N := Gmap.CellName(Player.GmapX, Player.GmapY);
  Level := CachedLevel(N, True);
  Level.Name := N;
  BoardLoaded := Level.HasBoard;
  while FOthers.Count > 0 do RemoveOther(Others[0].Id);
  Log(Format('crossed into %s (cell %d,%d)', [N, Player.GmapX, Player.GmapY]));
  if FClient.Connected then
    AskAdjacent;
end;

{ ---- props to the server ---- }

function TAdventure.OwnGani: string;
begin
  Result := Player.AniName;
end;

{ 23 NAME.gani and 157 (UPDATEGANI: i5 checksum 0, as the client holds no
  copy, then the name), once per gani and connection (third lab run). }
procedure TAdventure.AskGani(const Name: string);
begin
  if (Name = '') or (Pos(',' + Name + ',', FGanisAsked) > 0) then Exit;
  if FGanisAsked = '' then FGanisAsked := ',';
  FGanisAsked := FGanisAsked + Name + ',';
  FClient.SendPacket(PLI_WANTFILE, Name + '.gani');
  FClient.SendPacket(PLI_UPDATEGANI, GInt5(0) + Name);
end;

{ X2 / Y2 / Z2 as sent: abs(v * 16) shl 1, low bit = sign. }
function Pos2(V: Double): string;
var
  N: Integer;
begin
  N := Round(Abs(V) * 16) shl 1;
  if V < 0 then N := N or 1;
  Result := GShort(N);
end;

{ The messages after the login burst, as the third lab run saw 4.04r2
  send them: 23 idle.gani and 157 idle; 46 ENTERLEVEL; 44 (the window
  list); the own props; 24; 34 pics1.png. The real client also asks for
  its head and default weapon images and sends four 152 / 154 GUI texts
  (pmguilds, pmservers, the lister options); not yet. ADJACENTLEVEL on a
  gmap. The props set (0, 18, 31, 33, 52, 75, 76) is 3.04's, assumed. }
procedure TAdventure.SendLoginFrame;
var
  F: string;
  MT: Cardinal;
begin
  AskGani(OwnGani);
  FClient.SendPacket(PLI_ENTERLEVEL, '');
  { the real client sends the titles of every open window on the machine;
    the rebuild names only its own }
  FClient.SendPacket(PLI_PROCESSLIST, ExtractFileName(ParamStr(0)));
  FClient.SendPacket(PLI_PLAYERPROPS,
    GChar(PLPROP_NICKNAME) + GString(Player.Nickname) +
    GChar(PLPROP_STATUS) + GChar(Player.Status) +
    GChar(PLPROP_UDPPORT) + GInt3(0) +   { no UDP peer channel yet }
    GChar(PLPROP_ADDITFLAGS) + GChar(0) +
    GChar(PLPROP_PLANGUAGE) + GString(Player.Language) +
    GChar(PLPROP_OSTYPE) + GString(OsType) +
    GChar(PLPROP_TEXTCODEPAGE) + GInt3(TextCodePage));
  FClient.SendPacket(PLI_SHOWIMG, GChar(9));
  FNextShowImgMs := ClockMs + ShowImgEveryMs;
  MT := 0;
  F := Assets.FindFile('pics1.png', ['', 'levels/', 'levels/images/']);
  if F <> '' then
    MT := Cardinal(Round((FileDateToDateTime(FileAge(F)) - 25569.0) * 86400.0));
  FClient.SendPacket(PLI_UPDATEFILE, GInt5(MT) + 'pics1.png');
  AskAdjacent;
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentDir := Player.Dir;
  FSentGani := OwnGani;
  FSentGmapX := Player.GmapX;
  FSentGmapY := Player.GmapY;
  FPropsSent := True;
end;

{ Every 50 ms tick (lab): GANI and SPRITE when they change, then the axes
  that moved as X2 / Y2; the gmap cell props on a crossing. }
procedure TAdventure.SendMovedProps;
var
  S, G: string;
begin
  if not FPropsSent then Exit;
  S := '';
  G := OwnGani;
  { a new gani goes out with SPRITE, as on the first step of a walk }
  if G <> FSentGani then
  begin
    AskGani(G);
    S := S + GChar(PLPROP_GANI) + GString(G) + GChar(PLPROP_SPRITE) + GChar(Player.Dir);
  end
  else if Player.Dir <> FSentDir then
    S := S + GChar(PLPROP_SPRITE) + GChar(Player.Dir);
  if Player.GmapX <> FSentGmapX then S := S + GChar(PLPROP_GMAPLEVELX) + GChar(Player.GmapX);
  if Player.GmapY <> FSentGmapY then S := S + GChar(PLPROP_GMAPLEVELY) + GChar(Player.GmapY);
  if Player.X <> FSentX then S := S + GChar(PLPROP_X2) + Pos2(Player.X);
  if Player.Y <> FSentY then S := S + GChar(PLPROP_Y2) + Pos2(Player.Y);
  if S = '' then Exit;
  FClient.SendPacket(PLI_PLAYERPROPS, S);
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentDir := Player.Dir;
  FSentGani := G;
  FSentGmapX := Player.GmapX;
  FSentGmapY := Player.GmapY;
end;

{ ---- messages from the server ---- }

procedure TAdventure.Receive(Id: Integer; const Data: string);
begin
  HandleMessage(Id, Data);
end;

{ PLO_FILE (102, behind RAWDATA): i5 mod time, c name length, name, data
  (2.22 gets file mod times; version-profiles/2.22-2.31.md). Only a .gmap
  is kept; other files are not saved yet. }
procedure TAdventure.ReceiveFile(const Data: string);
var
  R: TGReader;
  Name, Body: string;
begin
  R := TGReader.Create(Data);
  try
    R.ReadGInt5;
    Name := R.ReadGString;
    Body := R.ReadRest;
  finally
    R.Free;
  end;
  Log(Format('FILE %s (%d bytes)', [Name, Length(Body)]));
  if EndsWith(Name, '.gmap') and (LowerCase(Name) = LowerCase(GmapName)) then
  begin
    FreeAndNil(Gmap);
    Gmap := TGmap.Create;
    Gmap.Name := Name;
    if not Gmap.LoadFromString(Body) then
    begin
      Log('gmap ' + Name + ': not a GRMAP001 file');
      FreeAndNil(Gmap);
      Exit;
    end;
    Log(Format('gmap %s: %dx%d', [Name, Gmap.Width, Gmap.Height]));
    if FPropsSent then AskAdjacent;
  end;
end;

{ PLO_SERVERWARP (178): four comma fields, 2 = host, 3 = port; the client
  closes the link and logs in there with a new key and the same account
  (08-lab-findings, part C). Fewer fields: ignored. }
procedure SplitCommas(const S: string; L: TStringList);
var
  I, From: Integer;
begin
  L.Clear;
  From := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ',') then
    begin
      L.Add(Copy(S, From, I - From));
      From := I + 1;
    end;
end;

procedure TAdventure.ServerWarp(const Data: string);
var
  F: TStringList;
  Port: Integer;
begin
  F := TStringList.Create;
  try
    { split on commas only: a server name may hold spaces
      (5.00-6.03.toml, serverwarp_fields) }
    SplitCommas(Data, F);
    if F.Count < 4 then Exit;
    Port := StrToIntDef(F[3], -1);
    if (Port <= 0) or (Port > 65535) or (F[2] = '') then
    begin
      Log('SERVERWARP: bad host or port');
      Exit;
    end;
    Log(Format('SERVERWARP to %s %s:%d', [F[1], F[2], Port]));
    Inc(ServerWarps);
    FClient.Flush;
    FClient.Disconnect;
    LoggedIn := False;
    BoardLoaded := False;
    FPropsSent := False;
    FWarpPending := False;
    FGanisAsked := '';
    FNextShowImgMs := 0;
    while FOthers.Count > 0 do RemoveOther(Others[0].Id);
    ServerName := F[1];
    ConnectServer(F[2], Port, FAccount, FPassword);
  finally
    F.Free;
  end;
end;

procedure TAdventure.HandleMessage(Id: Integer; const Data: string);
var
  R: TGReader;
  S: string;
  V, I, X0, Y0, W, H, MX, MY: Integer;
  L: TLevelLink;
  SG: TLevelSign;
  CH: TLevelChest;
  Words: TStringList;
  OP: TServerPlayer;
  T: TCachedLevel;
  Replaced: Boolean;
begin
  if not PLOKnown(Id) then
  begin
    { 2.22 has no case for it: silently ignored }
    if (Id >= 0) and (Id <= 255) then Inc(Ignored[Id]);
    Exit;
  end;
  R := TGReader.Create(Data);
  try
    case Id of
      PLO_PLAYERPROPS:
        begin
          S := Player.ApplyProps(R, False, Frame);
          Log('PLAYERPROPS ' + S);
          if not LoggedIn then LoggedIn := True;
        end;
      PLO_OTHERPLPROPS: { s id + prop stream; an unknown id adds the player }
        begin
          if Length(Data) < 2 then Exit;
          V := R.ReadGShort;
          OP := FindOther(V, True);
          OP.ApplyProps(R, True, Frame);
          if OP.Gone then RemoveOther(V);
        end;
      PLO_PLAYERWARP: { c x*2, c y*2, level }
        begin
          Player.X := R.ReadGChar / 2;
          Player.Y := R.ReadGChar / 2;
          Player.Level := R.ReadRest;
          FWarpPending := False;
          FSentX := Player.X;
          FSentY := Player.Y;
          if not EndsWith(Player.Level, '.gmap') then
          begin
            FreeAndNil(Gmap);
            GmapName := '';
          end;
          Log(Format('PLAYERWARP %s %.1f,%.1f', [Player.Level, Player.X, Player.Y]));
        end;
      PLO_PLAYERWARP2: { c x*2, c y*2, c z, c gmap x, c gmap y, level }
        begin
          Player.X := R.ReadGChar / 2;
          Player.Y := R.ReadGChar / 2;
          R.ReadGChar; { z: not read by 2.22 }
          MX := R.ReadGChar;
          MY := R.ReadGChar;
          Player.Level := R.ReadRest;
          FWarpPending := False;
          FSentX := Player.X;
          FSentY := Player.Y;
          if EndsWith(Player.Level, '.gmap') then
          begin
            SetGmap(Player.Level);
            if Gmap <> nil then
            begin
              { clamped to the grid }
              MX := Max(0, Min(MX, Gmap.Width - 1));
              MY := Max(0, Min(MY, Gmap.Height - 1));
            end;
            Player.GmapX := MX;
            Player.GmapY := MY;
            FSentGmapX := MX;
            FSentGmapY := MY;
            if Gmap <> nil then
            begin
              Level := CachedLevel(Gmap.CellName(MX, MY), True);
              Level.Name := Gmap.CellName(MX, MY);
            end;
          end;
          Log(Format('PLAYERWARP2 %s %.1f,%.1f cell %d,%d', [Player.Level, Player.X,
            Player.Y, MX, MY]));
        end;
      PLO_LEVELNAME:
        begin
          if EndsWith(Data, '.gmap') then
          begin
            { the "named level" goes back to the gmap after a level's data }
            SetGmap(Data);
          end
          else
          begin
            T := CachedLevel(Data, True);
            T.Name := Data;
            if FWarpPending and (Data = FWarpLevel) then
            begin
              { the server sends no PLAYERWARP for a link: the client
                completes its own pending warp when the level arrives }
              while FOthers.Count > 0 do RemoveOther(Others[0].Id);
              Player.X := FWarpX;
              Player.Y := FWarpY;
              Player.Level := Data;
              FWarpPending := False;
              FreeAndNil(Gmap);
              GmapName := '';
              Level := T;
              BoardLoaded := T.HasBoard;
              if BoardLoaded then
                WarpDone;
            end
            else if (Gmap = nil) or (LowerCase(Gmap.CellName(Player.GmapX, Player.GmapY)) =
              LowerCase(Data)) or (GmapName = '') then
            begin
              if Level <> T then
              begin
                while FOthers.Count > 0 do RemoveOther(Others[0].Id);
                Level := T;
                BoardLoaded := T.HasBoard;
              end;
            end;
            { a neighbour's data goes to its own cached level }
            FCurrentData := T;
          end;
          Log('LEVELNAME ' + Data);
        end;
      PLO_BOARDPACKET:
        begin
          T := FCurrentData;
          if T = nil then T := Level;
          if T.LoadBoardPacket(Data) then
          begin
            T.HasBoard := True;
            SetLength(T.Links, 0);
            SetLength(T.Signs, 0);
          end;
          if T = Level then BoardLoaded := T.HasBoard;
          if BoardLoaded and LoggedIn and (LoginMs < 0) and (ConnectAtMs > 0) then
            LoginMs := ClampMs(NowMs - ConnectAtMs);
          if T.HasBoard and (FWarpTimed <> '') and (LowerCase(T.Name) = LowerCase(FWarpTimed)) then
            WarpDone;
          if T.HasBoard then
            Log('BOARDPACKET ' + T.Name + ' loaded')
          else
            Log('BOARDPACKET rejected: ' + T.LastError);
        end;
      PLO_LEVELBOARD: ; { empty in 2.2x bursts; the board comes as 101 }
      PLO_LEVELMODTIME:
        begin
          T := FCurrentData;
          if T = nil then T := Level;
          T.ModTime := R.ReadGInt5;
          T.HasModTime := not R.Overrun;
        end;
      PLO_LEVELLINK: { "dest x y w h newx newy" as text }
        begin
          T := FCurrentData;
          if T = nil then T := Level;
          Words := TStringList.Create;
          try
            SplitSpaces(Data, Words);
            if Words.Count >= 5 then
            begin
              L.Dest := Words[0];
              L.X := Trunc(StrToFloatDef(Words[1], 0));
              L.Y := Trunc(StrToFloatDef(Words[2], 0));
              L.W := Trunc(StrToFloatDef(Words[3], 0));
              L.H := Trunc(StrToFloatDef(Words[4], 0));
              L.NewX := 'playerx';
              L.NewY := 'playery';
              if Words.Count >= 6 then L.NewX := Words[5];
              if Words.Count >= 7 then L.NewY := Words[6];
              if L.NewX = '-1' then L.NewX := 'playerx';
              if L.NewY = '-1' then L.NewY := 'playery';
              SetLength(T.Links, Length(T.Links) + 1);
              T.Links[High(T.Links)] := L;
            end;
          finally
            Words.Free;
          end;
        end;
      PLO_LEVELSIGN:
        begin
          T := FCurrentData;
          if T = nil then T := Level;
          SG.X := R.ReadGChar;
          SG.Y := R.ReadGChar;
          SG.Text := DecodeSignText(R.ReadRest);
          SetLength(T.Signs, Length(T.Signs) + 1);
          T.Signs[High(T.Signs)] := SG;
        end;
      PLO_LEVELCHEST: { c opened, c x, c y, c item, c sign }
        begin
          T := FCurrentData;
          if T = nil then T := Level;
          R.ReadGChar;
          CH.X := R.ReadGChar;
          CH.Y := R.ReadGChar;
          CH.Item := R.ReadGChar;
          CH.Sign := R.ReadGChar;
          { a chest is sent on every visit: one per position }
          Replaced := False;
          for I := 0 to High(T.Chests) do
            if (T.Chests[I].X = CH.X) and (T.Chests[I].Y = CH.Y) then
            begin
              T.Chests[I] := CH;
              Replaced := True;
            end;
          if not Replaced then
          begin
            SetLength(T.Chests, Length(T.Chests) + 1);
            T.Chests[High(T.Chests)] := CH;
          end;
        end;
      PLO_BOARDMODIFY, PLO_BOARDMODIFY2:
        begin
          { 7: c x, c y, c w, c h, w*h s tiles; 186: c map x, c map y first
            (packet-ids.md); a short payload is dropped }
          T := Level;
          if Id = PLO_BOARDMODIFY2 then
          begin
            MX := R.ReadGChar;
            MY := R.ReadGChar;
            if Gmap <> nil then
            begin
              T := CachedLevel(Gmap.CellName(MX, MY), False);
              if Gmap.CellName(MX, MY) = '' then T := nil;
            end;
          end;
          X0 := R.ReadGChar;
          Y0 := R.ReadGChar;
          W := R.ReadGChar;
          H := R.ReadGChar;
          if (T <> nil) and (R.Remaining >= 2 * W * H) then
            for I := 0 to W * H - 1 do
            begin
              V := R.ReadGShort;
              if (X0 + I mod W < BoardW) and (Y0 + I div W < BoardH) then
                T.Tiles[(Y0 + I div W) * BoardW + X0 + I mod W] := V;
            end;
        end;
      PLO_SIGNATURE: { 1: quit; 0: quit unless the host is loopback }
        begin
          V := R.ReadGChar;
          Log('SIGNATURE ' + IntToStr(V));
          if (V = 1) or ((V = 0) and (FHost <> '127.0.0.1') and (FHost <> 'localhost')) then
          begin
            DisconnectReason := 'signature ' + IntToStr(V);
            FClient.Disconnect;
          end;
        end;
      PLO_NEWWORLDTIME: WorldTime := R.ReadGInt4;
      PLO_STARTMESSAGE: ServerMessage := Data;
      PLO_DISCMESSAGE:
        begin
          DisconnectReason := Data;
          Log('DISCMESSAGE ' + Data);
        end;
      PLO_WARPFAILED:
        begin
          FWarpPending := False;
          Log('WARPFAILED ' + Data);
        end;
      PLO_FILE: ReceiveFile(Data);
      PLO_SETACTIVELEVEL:
        begin
          if EndsWith(Data, '.gmap') then SetGmap(Data);
          FCurrentData := nil;
          Log('SETACTIVELEVEL ' + Data);
        end;
      PLO_FREEZEPLAYER2: Frozen := True;
      PLO_UNFREEZEPLAYER: Frozen := False;
      PLO_SERVERWARP: ServerWarp(Data);
      PLO_LISTPROCESSES:
        { The real 4.04r2 answers with the titles of every open window on
          the machine. The rebuild names only itself, so it never tells a
          server what else runs on the player's computer. }
        FClient.SendPacket(PLI_PROCESSLIST, ExtractFileName(ParamStr(0)));
      PLO_HASPROCESSRUNNING:
        { The real client answers whether a title is open; the id of that
          answer is not in the notes, so the rebuild accepts 183 and sends
          nothing back. }
        ;
      PLO_TOALL: Log('TOALL ' + Data);
    else
      ; { handled by 2.22; their effects belong to later stages }
    end;
    if (Id >= 0) and (Id <= 255) then Inc(Handled[Id]);
  finally
    R.Free;
  end;
end;

{ ---- the frame ---- }

{ How far ahead of the body's centre the link is tested. Measured on 2.05;
  run-222d's left-edge probe on 2.22 (warps from y 31.5 and 32, none from
  32.5) fits the same point. }
const
  LinkAhead = 1.25;

procedure TAdventure.Tick;
var
  D: Integer;
  Moved: Boolean;
  AX, AY: Double;
begin
  Inc(Frame);
  if UseWallClock then ClockMs := NowMs;
  if FClient.Connected then
  begin
    FClient.Poll;
    if not FClient.Connected and not FClient.Sec.Awaiting then
      Log('link closed: ' + FClient.LastError);
  end;
  if FClient.Sec.State in [ssAwaitS1, ssRefused, ssNoAnswer, ssFailed] then
    CheckSecureLogin;
  { the first frame after the login burst }
  if LoggedIn and not FPropsSent and FClient.Connected then SendLoginFrame;
  { keys run in the order up, left, down, right, each from where the
    earlier ones left the player }
  Moved := False;
  AX := 0;
  AY := 0;
  if not Frozen then
    for D := 0 to 3 do
      if Keys[D] then
      begin
        WalkStep(D);
        Moved := True;
        case D of
          DirUp: AY := AY - LinkAhead;
          DirLeft: AX := AX - LinkAhead;
          DirDown: AY := AY + LinkAhead;
          DirRight: AX := AX + LinkAhead;
        end;
      end;
  if Moved then Player.SetAni('walk', Frame) else Player.SetAni('idle', Frame);
  if Moved then CrossEdges;
  { links are tested on the player's own walk, at one point: the body's
    centre pushed ahead in the walking direction }
  if Moved then FollowLink(LinkAt(Player.X + 1.5 + AX, Player.Y + 2 + AY));
  SendMovedProps;
  { 24 = 9 every 5.14 s, alone in the level too (third lab run) }
  if FPropsSent and FClient.Connected and (FNextShowImgMs > 0) and
    (ClockMs >= FNextShowImgMs) then
  begin
    FClient.SendPacket(PLI_SHOWIMG, GChar(9));
    FNextShowImgMs := ClockMs + ShowImgEveryMs;
  end;
  FClient.Flush;
  if not Headless then Draw;
end;

{ A colour prop as an index into the 20 colours; a hostile or garbled
  value (below 0, above 19) wraps instead of indexing out of the table. }
function ColorIndex(C: Integer): Integer;
begin
  Result := ((C mod 20) + 20) mod 20;
end;

function TAdventure.BodyFor(P: TServerPlayer): TGSurface;
var
  Src: TGSurface;
  Key: string;
  I: Integer;
begin
  Result := nil;
  Src := Assets.Image(P.BodyImage, 'body');
  if Src = nil then Exit;
  if Length(Src.Indices) = 0 then
  begin
    Result := Src; { not a palette image: drawn as it is }
    Exit;
  end;
  Key := P.BodyImage;
  for I := 0 to 4 do Key := Key + ',' + IntToStr(P.Colors[I]);
  if P.BodyCache = nil then P.BodyCache := TGSurface.Create(0, 0);
  if Key <> P.BodyKey then
  begin
    P.BodyCache.SetSize(Src.Width, Src.Height);
    P.BodyCache.Indices := Src.Indices;
    P.BodyCache.Palette := Src.Palette;
    { entry 5 skin, 6 coat, 4 sleeves, 3 shoes, 1 belt; 0 the outline (18);
      2 is the clear colour }
    P.BodyCache.Recolor([5, 6, 4, 3, 1, 0, 2],
      [ColorTable[ColorIndex(P.Colors[0])], ColorTable[ColorIndex(P.Colors[1])],
       ColorTable[ColorIndex(P.Colors[2])], ColorTable[ColorIndex(P.Colors[3])],
       ColorTable[ColorIndex(P.Colors[4])], ColorTable[18], 0]);
    P.BodyKey := Key;
  end;
  Result := P.BodyCache;
end;

procedure TAdventure.DrawPlayer(P: TServerPlayer; CamX, CamY: Integer);
var
  A: TGraalAni;
  St, I, K, BX, BY: Integer;
  Parts: TGraalAniPartList;
  Spr: TGraalAniSprite;
  Img: TGSurface;
  SheetName, AttrName: string;
begin
  BX := Round((P.X + P.GmapX * BoardW) * TileSize) - CamX;
  BY := Round((P.Y + P.GmapY * BoardH) * TileSize) - CamY;
  if Gmap = nil then
  begin
    BX := Round(P.X * TileSize) - CamX;
    BY := Round(P.Y * TileSize) - CamY;
  end;
  A := Assets.Ani(P.AniName);
  if A = nil then A := Assets.Ani('idle');
  if A = nil then
  begin
    { no ganis available: a 32x32 marker where the body is }
    Screen.FillRect(BX + 8, BY + 16, 32, 2, $FFFFFFFF);
    Screen.FillRect(BX + 8, BY + 46, 32, 2, $FFFFFFFF);
    Screen.FillRect(BX + 8, BY + 16, 2, 32, $FFFFFFFF);
    Screen.FillRect(BX + 38, BY + 16, 2, 32, $FFFFFFFF);
    Exit;
  end;
  if P.FixedStep >= 0 then
  begin
    St := P.FixedStep;
    if St > High(A.Steps) then St := 0;
  end
  else
    St := A.StepAt(Frame - P.AniStart);
  if (St < 0) or (St > High(A.Steps)) then Exit;
  Parts := A.Steps[St].Dirs[P.Dir and 3];
  for I := 0 to High(Parts) do
  begin
    if not A.FindSprite(Parts[I].Sprite, Spr) then Continue;
    SheetName := UpperCase(Spr.Sheet);
    if SheetName = 'SPRITES' then Img := Assets.Image('sprites.png', '')
    else if SheetName = 'HEAD' then Img := Assets.Image(P.HeadImage, 'head')
    else if SheetName = 'BODY' then Img := BodyFor(P)
    else if SheetName = 'SWORD' then Img := Assets.Image(P.SwordImage, 'sword')
    else if SheetName = 'SHIELD' then Img := Assets.Image(P.ShieldImage, 'shield')
    else if Copy(SheetName, 1, 4) = 'ATTR' then
    begin
      K := StrToIntDef(Copy(SheetName, 5, 1), 0);
      AttrName := '';
      if (K >= 1) and (K <= 5) then
      begin
        AttrName := P.Attr[K];
        if AttrName = '' then AttrName := A.DefaultAttr[K];
      end;
      Img := Assets.Image(AttrName, 'hat');
    end
    else
      Img := Assets.Image(Spr.Sheet, '');
    if Img <> nil then
      Screen.Blit(Img, Spr.X, Spr.Y, Spr.W, Spr.H, BX + Parts[I].X, BY + Parts[I].Y);
  end;
end;

{ GS1's addtiledef IMAGE,PREFIX[,TYPE] swaps the tile sheet for every level
  whose name starts with PREFIX (2.22's offline tutorial sets picso.png
  for "offlinetutorial" this way). Without a script engine the rebuild
  reads the line wherever it is in a level's NPCs, without its condition. }
procedure TAdventure.NoteTileDefs(L: TAdventureLevel);
var
  I, P, E: Integer;
  Src, Low, Args, Img, Prefix: string;
  Parts: TStringList;
begin
  Parts := TStringList.Create;
  try
    for I := 0 to High(L.NPCs) do
    begin
      Src := L.NPCs[I].Script;
      Low := LowerCase(Src);
      P := Pos('addtiledef ', Low);
      while P > 0 do
      begin
        E := P + Length('addtiledef ');
        Args := '';
        while (E <= Length(Src)) and not (Src[E] in [';', #10, #13, '}']) do
        begin
          Args := Args + Src[E];
          Inc(E);
        end;
        Parts.CommaText := '';
        Parts.Delimiter := ',';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := Args;
        if Parts.Count >= 2 then
        begin
          Img := Trim(Parts[0]);
          Prefix := LowerCase(Trim(Parts[1]));
          if (Img <> '') and (Pos('#', Img) = 0) and (Pos('..', Img) = 0) then
          begin
            if FTileDefs.IndexOf(Prefix + #9 + Img) >= 0 then
              FTileDefs.Delete(FTileDefs.IndexOf(Prefix + #9 + Img));
            FTileDefs.Insert(0, Prefix + #9 + Img);
          end;
        end;
        Delete(Low, 1, E - 1);
        Delete(Src, 1, E - 1);
        P := Pos('addtiledef ', Low);
      end;
    end;
  finally
    Parts.Free;
  end;
end;

function TAdventure.TileSheetFor(const LevelName: string): TGSurface;
var
  I, T: Integer;
  N, Prefix: string;
  S: TGSurface;
begin
  Result := Sheet;
  N := LowerCase(LevelName);
  for I := 0 to FTileDefs.Count - 1 do
  begin
    T := Pos(#9, FTileDefs[I]);
    Prefix := Copy(FTileDefs[I], 1, T - 1);
    if Copy(N, 1, Length(Prefix)) = Prefix then
    begin
      S := Assets.Image(Copy(FTileDefs[I], T + 1, MaxInt), '');
      if (S <> nil) and (S.Width > 0) then Result := S;
      Exit;
    end;
  end;
end;

procedure TAdventure.Draw;
var
  CamX, CamY, TX, TY, X0, Y0, I, T, WorldW, WorldH, PX, PY: Integer;
  Tiles: TGSurface;
begin
  Screen.Fill($FF000000);
  if Sheet.Width = 0 then MakeIndexSheet(Sheet);
  if Level.Name <> FTileDefLevel then
  begin
    NoteTileDefs(Level);
    FTileDefLevel := Level.Name;
  end;
  Tiles := TileSheetFor(Level.Name);
  { on a gmap the camera works in world tiles: local + 64 x cell }
  PX := 0;
  PY := 0;
  WorldW := BoardW;
  WorldH := BoardH;
  if Gmap <> nil then
  begin
    PX := Player.GmapX * BoardW;
    PY := Player.GmapY * BoardH;
    WorldW := Gmap.Width * BoardW;
    WorldH := Gmap.Height * BoardH;
  end;
  { centre on the player's body (the sprite box is 3 tiles wide) }
  CamX := Round((Player.X + PX + 1.5) * TileSize) - ScreenW div 2;
  CamY := Round((Player.Y + PY + 2) * TileSize) - ScreenH div 2;
  if CamX > WorldW * TileSize - ScreenW then CamX := WorldW * TileSize - ScreenW;
  if CamY > WorldH * TileSize - ScreenH then CamY := WorldH * TileSize - ScreenH;
  if CamX < 0 then CamX := 0;
  if CamY < 0 then CamY := 0;
  X0 := CamX div TileSize;
  Y0 := CamY div TileSize;
  for TY := Y0 to Y0 + ScreenH div TileSize + 1 do
    for TX := X0 to X0 + ScreenW div TileSize + 1 do
      if (TX < WorldW) and (TY < WorldH) then
      begin
        T := WorldTile(TX, TY);
        if T >= 0 then
          DrawTile(Screen, Tiles, T, TX * TileSize - CamX, TY * TileSize - CamY);
      end;
  { on the Login server the draw-layer mask is 0: the level is only a
    backdrop, no players are drawn }
  if LoginSession then Exit;
  { others first, then the player on top }
  for I := 0 to FOthers.Count - 1 do
    DrawPlayer(Others[I], CamX, CamY);
  DrawPlayer(Player, CamX, CamY);
end;

function TAdventure.LoginSession: Boolean;
begin
  Result := LowerCase(Copy(ServerName, 1, 5)) = 'login';
end;

end.
