{ Adventure: TAdventure, the game state and frame loop of 3.151, carried
  over from the 2.22 rebuild, since 3.151 speaks the 2.22 wire
  (graal_analysis protocol/v3x-clients.md, version-profiles/3.04-3.153.md).
  What 3.151 does differently (the 3.04 lab run stands in for it, since
  3.151 was never run: version-profiles/lab-304-linux-2026-10-30.md): no tamper check (39)
  anywhere, no periodic 24 over TCP (its 5.1 s message goes to other
  players over UDP), first props 0, 18, 31, 33, 52, 75 (linux) and 76,
  then UPDATEFILE for the player's head; and it does not handle 44, 182
  or 183.
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
  Classes, GTypes, GLevel, GSurface, GArrays, GAni, GBuiltin, GAssetDirs, GraalClient, Protocol3151;

const
  { The game view: 800 x 600, as the Linux 3.04 opens (lab run), taken for
    the Linux 3.151. (3.153's 640x480 was assumed for 2.22 as for 2.05; not read from
    the binary.) }
  ScreenW = 800;
  ScreenH = 600;

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
    HitSecond: Integer; { second of the day this player's swing last hit us }
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

  { The player's actions, carried over from the 2.22 rebuild (3.04 speaks
    the 2.22 wire; its local player is the same game in C++:
    graal_analysis torque/304-adventure.md). }

  { An item lying on the board (client-internals/item-drops.md). }
  TFloorItem = record
    X, Y: Double;     { tiles, top-left }
    Item: Integer;    { index into ItemNames }
    Life: Integer;    { counts down one per 50 ms tick from 164 }
    Permanent: Boolean; { made with a life below 100: shown, never taken }
  end;

  { An object in flight after a throw. }
  TThrownObject = record
    X, Y, DX, DY: Double; { top-left of the 2 x 2 object, tiles per tick }
    Kind, Age: Integer;   { lift table entry; ticks in the air }
  end;

  TBomb = record
    X, Y: Double;          { top-left of the 2 x 2 bomb }
    Power, Fuse: Integer;  { power 1 to 3; ticks left }
    Mine: Boolean;         { laid by this player }
  end;

  { An explosion: a cross of 2 x 2 pieces, Reach pieces each way. }
  TBlast = record
    X, Y: Double;
    Reach, Kind, Age: Integer;
    Mine: Boolean;
  end;

  { A weapon in the player's list: a built-in one (Item is its item
    number) or a server NPC weapon (Item -1). }
  TWeapon = record
    Name, Image: string;
    Item: Integer;
  end;

  { A flying shot: Kind 0 arrow, 1 fireball, 2 fireblast, 3 nuke; Sprite
    is its sprite table entry (arrows 107 + direction). }
  TShot = record
    X, Y: Double;
    Dir, Sprite, Kind: Integer;
    Mine: Boolean;   { shot by this player: never hits this player }
    Back: Integer;   { ticks left of a bounce off a shield, or 0 }
  end;

  TAdventure = class
  private
    FModeUntil: Integer;   { frame the sword swing, spin or lift ends }
    FListWasDown: Boolean;
    FHurtCount: Integer;   { hurt mode: ticks left of 40 }
    FKnockX, FKnockY: Double;
    FEntryX, FEntryY: Double; { where the player came into this level }
    FEntryLevel: string;
    FClient: TAdventureClient;
    FLog: TStrings;
    FSentX, FSentY: Double;
    FSentDir, FSentGmapX, FSentGmapY: Integer;
    FSentGani: string;
    FPropsSent: Boolean;
    FOthers: TList;
    { addtiledef lines seen in level scripts: 'prefix'#9'image', newest
      first; FTileDefLevel is the level last scanned }
    FTileDefs: TStringList;
    { the sheet type of each FTileDefs entry (Values, by entry), 0 when not
      given }
    FTileDefTypes: TStringList;
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
    procedure KnockStep;
    procedure CheckSwordHits;
    procedure ItemListKeys;
    procedure TickCombat;
    procedure DrawCombat(CamX, CamY: Integer);
  public
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
    { Each log line as it is made, for a host (the Torque control). }
    OnLine: TLogEvent;
    { Weapons allowed (sword, bombs, shots), and alignment points 0 to 100. }
    WeaponsOn: Boolean;
    AP: Integer;
    { Game keys pressed this tick (down edges), from GuiGraalCtrl's doA,
      doS, doD and doQ: A action (lift, throw, open), S attack (sword,
      spin, throw), D weapon, Q the item list. }
    ActionKey, AttackKey, ItemKey, ItemListKey: Boolean;
    { S is held now (not only pressed): S held with A lays items, with D
      picks the next weapon }
    AttackHeld: Boolean;
    { the item chosen in the lay mode (ModeLay), or -1 }
    LayItem: Integer;
    { What the player is doing: ModeFree, ModeSword, ModeLift, ModeCarry,
      ModeSpin, ModeDead, ModeHide, ModeLay. }
    Mode: Integer;
    { The lift table entry carried (0 bush, 1 sign, 2 pot, 3 stone,
      4 black stone), or -1. }
    CarryKind: Integer;
    Items: array of TFloorItem;
    Thrown: array of TThrownObject;
    Bombs: array of TBomb;
    Blasts: array of TBlast;
    { The weapon list, in arrival order, and the selected entry. }
    Weapons: array of TWeapon;
    Selected: Integer;
    Shots: array of TShot;
    { The item list window (Q) is open: it takes the keys. }
    ItemListOpen: Boolean;
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
    { Adds the lines of a 3.04 tiledefs file as addtiledefs. }
    procedure LoadTileDefsFile(const Path: string);
    { Notes the addtiledef lines in L's NPC scripts. }
    procedure NoteTileDefs(L: TAdventureLevel);
    { The tile sheet for a level: an addtiledef image whose prefix starts
      the level name, else pics1. }
    function TileSheetFor(const LevelName: string): TGSurface;
    function TileDefFor(const LevelName: string): Integer;
    function SheetTypeFor(const LevelName: string): Integer;
    procedure NoteLevelTileDefs;
    function TileBlocks(T: Integer): Boolean;
    property TileDefs: TStringList read FTileDefs;
    function ConnectServer(const Host: string; Port: Word;
      const Account, Password: string): Boolean;
    { The walking routine for one direction key (one step). }
    procedure WalkStep(Dir: Integer);
    { The player's own chat text (prop 12): kept on the player and, online,
      sent as a player prop. }
    procedure Say(const Text: string);
    { One frame: network in, game step, network out, draw. }
    procedure Tick;
    procedure Draw;
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
    { The A-key probe: one tile beyond the middle of the leading edge. }
    procedure ProbePoint(out PX, PY: Double);
    { The first of the first MaxCount objects of table List (9 cut, 11
      lift) whose 2 x 2 tiles lie on the board around (PX, PY), with its
      top-left in OX, OY; -1 when none. }
    function MatchObject(List, MaxCount: Integer; PX, PY: Double;
      out OX, OY: Integer): Integer;
    { Writes object I of table List over the 2 x 2 at X, Y; online, sends
      the change when a tile differs. }
    procedure PutObject(X, Y, List, I: Integer; Send: Boolean);
    { The S key: throws what is carried, swings the sword and cuts, or
      during a swing with the has-spin status, spins. }
    procedure Attack;
    { The A key: throws, lifts, or opens a chest. }
    procedure Action;
    procedure Throw;
    { A floor item at X, Y (tiles); Life 164 for a dropped item. }
    procedure AddItem(X, Y: Double; Item, Life: Integer);
    procedure RemoveItem(I: Integer);
    { What taking item I gives offline (and from a chest). }
    procedure GiveItem(Item: Integer);
    procedure TickItems;
    procedure DrawItems(CamX, CamY: Integer);
    procedure DrawChests(Tiles: TGSurface; CamX, CamY: Integer);
    procedure DrawObjectTiles(List, I, X, Y: Integer);
    procedure DrawCarried(Kind, X, Y: Integer);
    { Not in hurt mode and not dead. }
    function Hurtable: Boolean;
    { Hearts off (clamped to the maximum first), hurt mode with a
      five-tile knockback along (KX, KY), or death. }
    procedure HurtPlayer(Hearts, KX, KY: Double);
    { After death, on a direction key: hearts by AP, at the level's entry. }
    procedure Respawn;
    procedure LayBombOf(Power: Integer);
    procedure AddBlast(X, Y: Double; Reach, Kind: Integer; Mine: Boolean);
    { Adds a weapon unless the list has its name, and selects it. }
    procedure AddWeapon(const Name, Image: string; Item: Integer);
    { A built-in weapon by item number (7 bow, 8 bomb, 12 superbomb, 20 to
      23); other numbers add nothing. }
    procedure AddDefaultWeapon(Item: Integer);
    procedure RemoveWeapon(const Name: string);
    { Selects the first entry from I on, wrapping, that is not hidden (an
      empty name or one starting with '-'). }
    procedure SelectWeapon(I: Integer);
    { The D key: uses the selected weapon. }
    procedure UseWeapon;
    { Fires a shot of Kind the way the player faces. }
    procedure Shoot(Kind: Integer);
    procedure AddShot(X, Y: Double; Dir, Sprite, Kind: Integer; Mine: Boolean);
    procedure TickShots;
    procedure DrawShots(CamX, CamY: Integer);
    procedure DrawItemList;
    { The lay mode (graal_analysis client-internals/
      laying-items-and-hiding.md): whether the player owns Item to lay,
      the next owned one after From in the lay order (-1 for none), and
      laying the chosen one in front. }
    function CanLay(Item: Integer): Boolean;
    function NextLayItem(From: Integer): Integer;
    procedure LayDown;
    { D with a bush or stone carried: hide under it, or come out again. }
    procedure ToggleHide;
    procedure SendStatus;
    property Others[I: Integer]: TServerPlayer read GetOther;
    property OtherCount: Integer read GetOtherCount;
    property Client: TAdventureClient read FClient;
    property LogLines: TStrings read FLog;
    property Current: TCachedLevel read GetCurrent;
  end;

{ Wall-clock milliseconds, for login and warp timings. }
function NowMs: Int64;
const
  ModeFree = 0;
  ModeSword = 1;
  ModeLift = 2;
  ModeCarry = 3;
  { the charged spin (2.05's mode 13), here its own mode }
  ModeSpin = 4;
  ModeDead = 5;
  { hiding under a carried bush or stone (2.05's mode 14) }
  ModeHide = 6;
  { choosing an item to lay down (2.05's mode 9) }
  ModeLay = 7;
  { STATUS bit: hidden (protocol/player-props.md) }
  StatusHidden = $02;
  { walking while hidden: a fifth of the speed }
  HideWalkFactor = 0.2;
  { STATUS bit: has the spin attack (protocol/player-props.md) }
  StatusHasSpin = $40;
  { spin.gani: 13 frames of one tick (player-mannerisms-live.md) }
  SpinTicks = 13;
  { The sprite of each item (arrays.dat array 24), by item number. }
  ItemSprites: array[0..24] of Integer = (136, 137, 138, 67, 143, 139, 145,
    351, 65, 350, 314, 315, 321, 323, 322, 324, 325, 328, 329, 330, 331, 332,
    333, 334, 349);
  ItemShadowSprite = 42;
  { the carry sprite of each lift table entry }
  CarrySprites: array[0..4] of Integer = (261, 267, 265, 263, 239);
  ItemLife = 164;
{ The items that can lie on the floor (PLO_ITEMADD makes only these). }
function FloorItem(Item: Integer): Boolean;
{ Fallback tile sheet when pics1 is not available: each tile gets a flat
  colour derived from its index, so a frame still shows the board layout. }
procedure MakeIndexSheet(Sheet: TGSurface);
{ Old-style sprite prop -> pose (servers that send no GANI). }
function SpriteWalkStep(Sprite: Integer): Integer;

implementation

uses
  SysUtils, Math, GFont;

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
  { the 3.04 install keeps its offline tutorial in levels/tutorial/; 3.151
    is taken to do the same (no 3.151 install in graal-assets yet) }
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
  SwordImage := 'sword1.png';
  ShieldImage := 'shield1.png';
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
    { the ids each 2.22 parser accepts (protocol/player-props.md) }
    if Other then
    begin
      if (P = 1) or ((P >= 3) and (P <= 7)) or (P = 14) or (P = 22) or
        ((P >= 25) and (P <= 29)) or (P > 76) then Exit;
    end
    else if (P = 50) or (P = 51) or (P = 53) or (P > 74) then Exit;
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
  FTileDefTypes := TStringList.Create;
  { a new 2.05 account, as the 2.22 rebuild starts offline: 3 of 3
    hearts, 10 bombs, 5 arrows, glove and sword 1, and the client's own
    bomb; online the server sends the props and the weapon list }
  Player.MaxPower := 3;
  Player.Power := 6;      { half hearts, as PLPROP_CURPOWER }
  Player.Bombs := 10;
  Player.Arrows := 5;
  Player.GlovePower := 1;
  Player.SwordPower := 1;
  CarryKind := -1;
  LayItem := -1;
  AP := 50;
  WeaponsOn := True;
  Selected := -1;
  AddDefaultWeapon(8);
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
  FTileDefTypes.Free;
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
  if Assigned(OnLine) then OnLine(Line);
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
    { 3.04 keeps its tile sheets in levels/tiles/ }
    P := FirstAssetPath(['pics1.png', 'pics1.gif', 'levels/tiles/pics1.png',
      'levels/tiles/pics1.gif']);
    if (P <> '') and LoadImageFile(P, Sheet) then SheetBuiltin := False;
  end;
  LoadTileDefsFile(AssetPath('levels/tiledefs/tiledefsOffline.txt'));
  P := AssetPath('arrays.dat');
  if (P <> '') and Arrays.LoadFromFile(P) then
  begin
    { 3.04's own lists are 2.22's arrays.dat without water tiles 1824 and
      1825 (Graal_analysis torque/304-tile-types.md) }
    Arrays.SetPassable(1824, False);
    Arrays.SetPassable(1825, False);
    Log('arrays.dat loaded');
  end
  else
    Log('arrays.dat not found in ' + Dir + ': using the built-in stand-in tile types; ' +
      'put 2.22''s arrays.dat here for real levels (3.04 has the same lists built in)');
end;

{ 3.04's tile definitions file (levels/tiledefs/tiledefsOffline.txt, read
  for offline play; lab-304-linux-2026-10-30.md): one line per sheet,
  IMAGE,PREFIX,... (the shipped one is picso.png,offlinetutorial,1,0,0).
  Each line is taken as an addtiledef. }
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
      if Parts.Count >= 3 then
        FTileDefTypes.Values[Prefix + #9 + Img] := IntToStr(StrToIntDef(Trim(Parts[2]), 0));
    end;
    Log(Format('%d tile definitions from %s', [FTileDefs.Count, ExtractFileName(Path)]));
  finally
    Parts.Free;
    L.Free;
  end;
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
  SetLength(Weapons, 0);
  Selected := -1;
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
  NoteLevelTileDefs;
  if Gmap = nil then
  begin
    { off a gmap the edge is open, so level links can be reached (as in
      2.05; run-222d: the player reaches x = -0.5 on the level's left
      edge) }
    if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
    Result := TileBlocks(Level.Tile(TX, TY));
    Exit;
  end;
  { on a gmap the neighbours' boards decide; the outer edge of the map
    and cells whose level has not arrived are walls (not measured) }
  T := WorldTile(TX + Player.GmapX * BoardW, TY + Player.GmapY * BoardH);
  if T < 0 then Result := True
  else Result := TileBlocks(T);
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
var
  Speed, NX, NY, F: Double;
  B: array[0..5] of Boolean;
  I: Integer;
begin
  { on foot; hidden under a bush or stone, a fifth of that }
  Speed := 1.0;
  if Mode = ModeHide then Speed := HideWalkFactor;
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

{ ---- actions: sword and spin, lift and throw, chests, floor items,
  combat, bombs, weapons and shots, the item list. Carried over from the
  2.22 rebuild (graal-2.22-GNW03014), whose notes it follows:
  client-internals/decomp-findings-2026-10-25-l/03-cut-lift-chest.md,
  item-drops.md, decomp-findings-2026-10-24-d/01-sword-damage.md,
  damage-sources.md, status-display.md, decomp-findings-2026-10-28/
  01-sword-while-carrying.md and 02-item-list.md. 3.04 keeps 2.22's game
  (torque/304-adventure.md); the rebuilt 3.04 has no sound, NPCs,
  baddies or sign panel yet, so those calls are left out. ---- }

function FloorItem(Item: Integer): Boolean;
begin
  Result := ((Item >= 0) and (Item <= 5)) or (Item = 7) or (Item = 8) or
    (Item = 19) or (Item = 24);
end;

procedure TAdventure.ProbePoint(out PX, PY: Double);
begin
  case Player.Dir and 3 of
    DirUp: begin PX := Player.X + 1.5; PY := Player.Y; end;
    DirLeft: begin PX := Player.X - 0.5; PY := Player.Y + 2; end;
    DirDown: begin PX := Player.X + 1.5; PY := Player.Y + 4; end;
  else
    begin PX := Player.X + 3.5; PY := Player.Y + 2; end;
  end;
end;

function TAdventure.MatchObject(List, MaxCount: Integer; PX, PY: Double;
  out OX, OY: Integer): Integer;
var
  TX, TY, T, E, C, R, C2, R2: Integer;
  Ok: Boolean;
begin
  Result := -1;
  OX := 0;
  OY := 0;
  TX := TileOf(PX);
  TY := TileOf(PY);
  if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
  T := Level.Tile(TX, TY);
  if MaxCount > Arrays.ObjectCount(List) then MaxCount := Arrays.ObjectCount(List);
  { each entry in order; for each of its tiles equal to the one under the
    point, the object's corner is the point less that tile's place; the
    first whole match wins }
  for E := 0 to MaxCount - 1 do
    for C := 0 to 1 do
      for R := 0 to 1 do
        if Arrays.ObjectTile(List, E, C, R) = T then
        begin
          Ok := (TX - C >= 0) and (TY - R >= 0) and (TX - C + 1 < BoardW) and
            (TY - R + 1 < BoardH);
          if Ok then
            for C2 := 0 to 1 do
              for R2 := 0 to 1 do
                if Level.Tile(TX - C + C2, TY - R + R2) <>
                  Arrays.ObjectTile(List, E, C2, R2) then Ok := False;
          if Ok then
          begin
            OX := TX - C;
            OY := TY - R;
            Result := E;
            Exit;
          end;
        end;
end;

procedure TAdventure.PutObject(X, Y, List, I: Integer; Send: Boolean);
var
  C, R, T: Integer;
  Changed: Boolean;
  S: string;
begin
  Changed := False;
  S := GChar(X) + GChar(Y) + GChar(2) + GChar(2);
  for R := 0 to 1 do
    for C := 0 to 1 do
    begin
      if List = 14 then
      begin
        { the open chest is one object, not a list of them }
        T := -1;
        if (Arrays.Lists[14] <> nil) and (C <= High(Arrays.Lists[14].Items)) and
          (R <= High(Arrays.Lists[14].Items[C].Values)) then
          T := Arrays.Lists[14].Items[C].Values[R];
      end
      else
        T := Arrays.ObjectTile(List, I, C, R);
      if (T < 0) or (X + C < 0) or (Y + R < 0) or (X + C >= BoardW) or
        (Y + R >= BoardH) then Exit;
      if Level.Tiles[X + C + (Y + R) * BoardW] <> T then Changed := True;
      Level.Tiles[X + C + (Y + R) * BoardW] := T;
      S := S + GShort(T);
    end;
  { 2.05 sends one run, and nothing when the tiles were already so }
  if Send and Changed and FClient.Connected then
    FClient.SendPacket(PLI_BOARDMODIFY, S);
end;

procedure TAdventure.Attack;
var
  A: TGraalAni;
  PX, PY: Double;
  OX, OY, E: Integer;
begin
  if (Mode = ModeCarry) or (Mode = ModeHide) then
  begin
    Throw;
    Exit;
  end;
  { a second press while the sword still swings, with the has-spin status,
    cuts the swing off and spins: 13 ticks of spin.gani, then idle; a
    press during the spin is ignored (graal_analysis
    client-internals/player-mannerisms-live.md "Spin attack", 2.05 and
    2.22 live; 04-sword-hitbox.md: swing mode 6, spin mode 13). What the
    spin cuts or hits was not read: online the server sends the hits
    (feature-specs/02-weapons-combat.md), offline it cuts nothing here. }
  if (Mode = ModeSword) and (Player.Status and StatusHasSpin <> 0) then
  begin
    Mode := ModeSpin;
    Player.AniName := '';
    Player.SetAni('spin', Frame);
    A := Assets.Ani('spin');
    if A <> nil then FModeUntil := Frame + A.TotalTicks else FModeUntil := Frame + SpinTicks;
    Exit;
  end;
  if (Mode <> ModeFree) or not WeaponsOn or (Player.SwordPower <= 0) then Exit;
  Mode := ModeSword;
  Player.AniName := '';
  Player.SetAni('sword', Frame);
  A := Assets.Ani('sword');
  if A <> nil then FModeUntil := Frame + A.TotalTicks else FModeUntil := Frame + 5;
  { a bush or tall grass at the tip is cut at the start of the swing }
  ProbePoint(PX, PY);
  E := MatchObject(9, MaxInt, PX, PY, OX, OY);
  if E >= 0 then PutObject(OX, OY, 10, E, True);
end;

procedure TAdventure.Action;
var
  A: TGraalAni;
  PX, PY: Double;
  OX, OY, E, I: Integer;
begin
  if Mode = ModeHide then
  begin
    ToggleHide;
    Exit;
  end;
  if Mode = ModeCarry then
  begin
    Throw;
    Exit;
  end;
  if Mode <> ModeFree then Exit;
  ProbePoint(PX, PY);
  { lift first: glove power g allows the first g + 2 entries }
  E := MatchObject(11, Player.GlovePower + 2, PX, PY, OX, OY);
  if E >= 0 then
  begin
    PutObject(OX, OY, 12, E, True);
    CarryKind := E;
    Mode := ModeLift;
    Player.SetAni('lift', Frame);
    A := Assets.Ani('lift');
    if A <> nil then FModeUntil := Frame + A.TotalTicks else FModeUntil := Frame + 4;
    Exit;
  end;
  { a chest record at the probe, not yet opened }
  for I := 0 to High(Level.Chests) do
    if not Level.Chests[I].Opened and (PX >= Level.Chests[I].X) and
      (PX <= Level.Chests[I].X + 2) and (PY >= Level.Chests[I].Y) and
      (PY <= Level.Chests[I].Y + 2) then
    begin
      Level.Chests[I].Opened := True;
      PutObject(Level.Chests[I].X, Level.Chests[I].Y, 14, 0, False);
      { the item shows over the chest (a life below 100: not taken) and is
        given at once }
      if (Level.Chests[I].Item >= 0) and (Level.Chests[I].Item <= High(ItemNames)) then
      begin
        AddItem(Level.Chests[I].X, Level.Chests[I].Y - 1, Level.Chests[I].Item, 24);
        GiveItem(Level.Chests[I].Item);
      end;
      if (Level.Chests[I].Sign >= 0) and (Level.Chests[I].Sign <= High(Level.Signs)) then
        { no sign panel in the rebuilt 3.04 yet: the text goes to the log }
        Log('chest sign: ' + Level.Signs[Level.Chests[I].Sign].Text);
      if FClient.Connected then
        FClient.SendPacket(PLI_OPENCHEST, GChar(Level.Chests[I].X) + GChar(Level.Chests[I].Y));
      Exit;
    end;
  { nothing to lift or open: S held with A starts the lay mode on the
    first item owned, when the point in front is free }
  if AttackHeld and not PointBlocked(PX, PY) then
  begin
    LayItem := NextLayItem(-1);
    if LayItem >= 0 then
    begin
      Mode := ModeLay;
      Player.SetAni('idle', Frame);
    end;
  end;
end;

{ ---- laying items and hiding (graal_analysis client-internals/
  laying-items-and-hiding.md, read from 3.04 and 2.05; the tables are the
  same in 2.22 and 3.153). The 3.x enablefeatures bits 0x10 (laying) and
  0x20 (S + D) are taken as on, their default. Not modelled: the
  water test on the point in front, the bush's break effect, the sounds,
  and an NPC carried (no NPCs yet). ---- }

const
  { the order the lay mode offers the items in }
  LayOrder: array[0..23] of Integer = (0, 1, 2, 19, 3, 4, 5, 6, 16, 8, 12, 23, 7,
    20, 21, 22, 9, 15, 17, 10, 13, 18, 14, 24);

function TAdventure.CanLay(Item: Integer): Boolean;
begin
  case Item of
    0: Result := Player.Rupees >= 1;
    1: Result := Player.Rupees >= 5;
    2: Result := Player.Rupees >= 30;
    19: Result := Player.Rupees >= 100;
    3: Result := Player.Bombs >= 5;
    4: Result := Player.Arrows >= 5;
    5: Result := Player.Power >= 3; { at least a heart and a half }
    { glove, shield and sword by their power: laying one steps it down }
    6: Result := Player.GlovePower = 2;
    16: Result := Player.GlovePower = 3;
    9: Result := Player.ShieldPower = 1;
    15: Result := Player.ShieldPower = 2;
    17: Result := Player.ShieldPower = 3;
    10: Result := Player.SwordPower = 1;
    13: Result := Player.SwordPower = 2;
    18: Result := Player.SwordPower = 3;
    14: Result := Player.SwordPower = 4;
    24: Result := Player.Status and StatusHasSpin <> 0;
  else
    { 7, 8, 11, 12 and 20 to 23 are never laid }
    Result := False;
  end;
end;

function TAdventure.NextLayItem(From: Integer): Integer;
var
  I, K, Start: Integer;
begin
  Result := -1;
  Start := 0;
  for I := 0 to High(LayOrder) do
    if LayOrder[I] = From then Start := I + 1;
  for K := 0 to High(LayOrder) do
  begin
    I := (Start + K) mod Length(LayOrder);
    if CanLay(LayOrder[I]) then
    begin
      Result := LayOrder[I];
      Exit;
    end;
  end;
end;

procedure TAdventure.LayDown;
const
  DX: array[0..3] of Double = (0, -2, 0, 2);
  DY: array[0..3] of Double = (-3, 0, 2, 0);
var
  X, Y: Double;
  It: Integer;
begin
  It := LayItem;
  Mode := ModeFree;
  LayItem := -1;
  if not CanLay(It) then Exit;
  X := Player.X + 0.5 + DX[Player.Dir and 3];
  Y := Player.Y + 1 + DY[Player.Dir and 3];
  AddItem(X, Y, It, ItemLife);
  { the cost }
  case It of
    0: Dec(Player.Rupees, 1);
    1: Dec(Player.Rupees, 5);
    2: Dec(Player.Rupees, 30);
    19: Dec(Player.Rupees, 100);
    3: Dec(Player.Bombs, 5);
    4: Dec(Player.Arrows, 5);
    5: Dec(Player.Power, 2);
    6, 16: Dec(Player.GlovePower);
    9, 15, 17: Dec(Player.ShieldPower);
    10, 13, 18, 14: Dec(Player.SwordPower);
    { the spin attack: assumed to take the has-spin status (not read) }
    24: Player.Status := Player.Status and not StatusHasSpin;
  end;
  if FloorItem(It) and FClient.Connected then
    FClient.SendPacket(PLI_ITEMADD, GChar(Round(X * 2)) + GChar(Round(Y * 2)) + GChar(It));
end;

procedure TAdventure.SendStatus;
begin
  if FClient.Connected then
    FClient.SendPacket(PLI_PLAYERPROPS, GChar(PLPROP_STATUS) + GChar(Player.Status));
end;

procedure TAdventure.ToggleHide;
begin
  if Mode = ModeHide then
  begin
    { out again, still carrying }
    Mode := ModeCarry;
    Player.Status := Player.Status and not StatusHidden;
    Player.SetAni('carrystill', Frame);
    SendStatus;
  end
  else if (Mode = ModeCarry) and (CarryKind >= 0) and (CarryKind <= High(CarrySprites)) and
    ((CarrySprites[CarryKind] = 261) or (CarrySprites[CarryKind] = 263) or
    (CarrySprites[CarryKind] = 239)) then
  begin
    { a bush or a stone (not a pot or a sign) }
    Mode := ModeHide;
    Player.Status := Player.Status or StatusHidden;
    Player.SetAni('hiddenstill', Frame);
    SendStatus;
  end;
end;

procedure TAdventure.Throw;
const
  DX: array[0..3] of Double = (0, -1, 0, 1);
  DY: array[0..3] of Double = (-1, 0, 1, 0);
var
  N: Integer;
begin
  if CarryKind < 0 then Exit;
  { it leaves from above the head; the flight itself was not read from
    2.05: here it travels 0.5 tile a tick for 8 ticks and breaks }
  N := Length(Thrown);
  SetLength(Thrown, N + 1);
  Thrown[N].X := Player.X + 0.5;
  Thrown[N].Y := Player.Y;
  Thrown[N].DX := DX[Player.Dir and 3] * 0.5;
  Thrown[N].DY := DY[Player.Dir and 3] * 0.5;
  Thrown[N].Kind := CarryKind;
  Thrown[N].Age := 0;
  CarryKind := -1;
  if Player.Status and StatusHidden <> 0 then
  begin
    Player.Status := Player.Status and not StatusHidden;
    SendStatus;
  end;
  Mode := ModeFree;
  Player.SetAni('idle', Frame);
end;

procedure TAdventure.AddItem(X, Y: Double; Item, Life: Integer);
var
  N: Integer;
begin
  N := Length(Items);
  SetLength(Items, N + 1);
  Items[N].X := X;
  Items[N].Y := Y;
  Items[N].Item := Item;
  Items[N].Life := Life;
  Items[N].Permanent := Life < 100;
end;

procedure TAdventure.RemoveItem(I: Integer);
var
  J: Integer;
begin
  if (I < 0) or (I > High(Items)) then Exit;
  for J := I to High(Items) - 1 do Items[J] := Items[J + 1];
  SetLength(Items, Length(Items) - 1);
end;

procedure TAdventure.GiveItem(Item: Integer);

  procedure Rupees(N: Integer);
  begin
    Player.Rupees := Min(Player.Rupees + N, 9999999);
  end;

begin
  case Item of
    0: Rupees(1);
    1: Rupees(5);
    2: Rupees(30);
    19: Rupees(100);
    3: Player.Bombs := Min(Player.Bombs + 5, 99);
    4: Player.Arrows := Min(Player.Arrows + 5, 99);
    7, 8, 12, 20, 21, 22, 23: AddDefaultWeapon(Item);
    5: Player.Power := Min(Player.Power + 2, Player.MaxPower * 2);
    6: Player.GlovePower := Max(Player.GlovePower, 2);
    16: Player.GlovePower := Max(Player.GlovePower, 3);
    9: Player.ShieldPower := Max(Player.ShieldPower, 1);
    15: Player.ShieldPower := Max(Player.ShieldPower, 2);
    17: Player.ShieldPower := Max(Player.ShieldPower, 3);
    10: Player.SwordPower := Max(Player.SwordPower, 1);
    13: Player.SwordPower := Max(Player.SwordPower, 2);
    18: Player.SwordPower := Max(Player.SwordPower, 3);
    14: Player.SwordPower := Max(Player.SwordPower, 4);
    11:
      begin
        Player.MaxPower := Min(Player.MaxPower + 1, 20);
        Player.Power := Player.MaxPower * 2;
      end;
  end;
end;

{ The per-tick work of items and thrown objects. }
procedure TAdventure.TickItems;
var
  I: Integer;
  It: TFloorItem;
begin
  I := 0;
  while I <= High(Items) do
  begin
    Dec(Items[I].Life);
    It := Items[I];
    if It.Life < 0 then
    begin
      if not It.Permanent and FClient.Connected then
        FClient.SendPacket(PLI_ITEMDEL, GChar(Round(It.X * 2)) + GChar(Round(It.Y * 2)));
      RemoveItem(I);
      Continue;
    end;
    if not It.Permanent and (It.Life < ItemLife - 4) and
      (Abs(Player.X + 1.5 - (It.X + 1)) < 2) and (Abs(Player.Y + 2 - (It.Y + 1)) < 2) then
    begin
      { online the server gives the item with props; offline it is ours }
      if FClient.Connected then
        FClient.SendPacket(PLI_ITEMTAKE, GChar(Round(It.X * 2)) + GChar(Round(It.Y * 2)) +
          GChar(It.Item))
      else
        GiveItem(It.Item);
      RemoveItem(I);
      Continue;
    end;
    Inc(I);
  end;
  I := 0;
  while I <= High(Thrown) do
  begin
    Thrown[I].X := Thrown[I].X + Thrown[I].DX;
    Thrown[I].Y := Thrown[I].Y + Thrown[I].DY;
    Inc(Thrown[I].Age);
    if Thrown[I].Age >= 8 then
    begin
      Thrown[I] := Thrown[High(Thrown)];
      SetLength(Thrown, Length(Thrown) - 1);
      Continue;
    end;
    Inc(I);
  end;
end;

{ ---- combat: being hurt, knockback, dying, other players' swings,
  bombs (decomp-findings-2026-10-24-d/01-sword-damage.md,
  decomp-findings-2026-10-25-k/01-knockback-and-packet-hits.md,
  damage-sources.md, lab-captures-2026-10-25/01-...md) ---- }

function TAdventure.Hurtable: Boolean;
begin
  Result := (FHurtCount = 0) and (Mode <> ModeDead);
end;

procedure TAdventure.HurtPlayer(Hearts, KX, KY: Double);
var
  L: Double;
begin
  if not Hurtable then Exit;
  { CURPOWER is in half hearts, clamped to the maximum before the hit }
  Player.Power := Min(Player.Power, Player.MaxPower * 2) - Round(Hearts * 2);
  if Player.Power > Player.MaxPower * 2 then Player.Power := Player.MaxPower * 2;
  { hurt mode: 40 ticks; the first five push the player a tile each along
    the knockback, scaled to one tile (a zero vector pushes east) }
  L := Sqrt(KX * KX + KY * KY);
  if L < 0.0001 then
  begin
    FKnockX := 1;
    FKnockY := 0;
  end
  else
  begin
    FKnockX := KX / L;
    FKnockY := KY / L;
  end;
  FHurtCount := 40;
  if Mode in [ModeSword, ModeLift, ModeCarry, ModeHide, ModeLay] then
  begin
    { what happens to a carried object on a hit was not read: it is lost }
    CarryKind := -1;
    LayItem := -1;
    Player.Status := Player.Status and not StatusHidden;
    Mode := ModeFree;
  end;
  if Player.Power <= 0 then
  begin
    Player.Power := 0;
    Mode := ModeDead;
    FHurtCount := 0;
    Player.SetAni('dead', Frame);
  end
  else
    Player.SetAni('hurt', Frame);
  if FClient.Connected then
    FClient.SendPacket(PLI_PLAYERPROPS, GChar(PLPROP_CURPOWER) + GChar(Player.Power));
end;

procedure TAdventure.Respawn;
begin
  { hearts by alignment (measured on 2.22): AP below 20 three, below 40
    five, else all; back at the point the level was entered }
  if AP < 20 then Player.Power := 6
  else if AP < 40 then Player.Power := 10
  else Player.Power := Player.MaxPower * 2;
  if Player.Power > Player.MaxPower * 2 then Player.Power := Player.MaxPower * 2;
  Player.X := FEntryX;
  Player.Y := FEntryY;
  Mode := ModeFree;
  Player.SetAni('idle', Frame);
  if FClient.Connected then
  begin
    FClient.SendPacket(PLI_PLAYERPROPS, GChar(PLPROP_CURPOWER) + GChar(Player.Power));
    FClient.SendPacket(PLI_LEVELWARP, GChar(Round(Player.X * 2)) + GChar(Round(Player.Y * 2)) +
      Level.Name);
  end;
end;

{ One tick of knockback: a tile along the stored vector, undone when any of
  the twelve body points (0.6 to 2.4 across, 1.1 to 2.9 down) is blocked. }
procedure TAdventure.KnockStep;
const
  PX: array[0..11] of Double = (0.6, 1.5, 2.4, 0.6, 0.6, 0.6, 0.6, 1.5, 2.4, 2.4, 2.4, 2.4);
  PY: array[0..11] of Double = (1.1, 1.1, 1.1, 1.1, 2.0, 2.9, 2.9, 2.9, 2.9, 1.1, 2.0, 2.9);
var
  NX, NY: Double;
  I: Integer;
begin
  NX := Player.X + FKnockX;
  NY := Player.Y + FKnockY;
  for I := 0 to 11 do
    if PointBlocked(NX + PX[I], NY + PY[I]) then Exit;
  Player.X := NX;
  Player.Y := NY;
end;

{ Others' swings, judged here as 2.05 does on the victim's side: the
  attacker on swing sprites 6 to 10, the victim 0 to 4 tiles ahead and
  under 2 tiles to the side, AP not 100, once a second per attacker. }
procedure TAdventure.CheckSwordHits;
var
  I, S, Sec: Integer;
  P: TServerPlayer;
  DX, DY, Ahead, Side: Double;
begin
  if not Hurtable or (AP = 100) or (Mode = ModeDead) then Exit;
  Sec := Round(Frac(Now) * 86400);
  for I := 0 to FOthers.Count - 1 do
  begin
    P := Others[I];
    { a swing: the sword gani (2.1 and later send GANI), or the classic
      sword sprites from a server that sends only SPRITE }
    S := P.Sprite div 4;
    if (LowerCase(P.AniName) <> 'sword') and ((S < 6) or (S > 10)) then Continue;
    DX := Player.X - P.X;
    DY := Player.Y - P.Y;
    case P.Dir and 3 of
      DirUp: begin Ahead := -DY; Side := DX; end;
      DirLeft: begin Ahead := -DX; Side := DY; end;
      DirDown: begin Ahead := DY; Side := DX; end;
    else
      begin Ahead := DX; Side := DY; end;
    end;
    if (Ahead < 0) or (Ahead > 4) or (Abs(Side) >= 2) then Continue;
    if P.HitSecond = Sec then Continue;
    P.HitSecond := Sec;
    HurtPlayer(Max(-20, Min(20, P.SwordPower)) / 2, DX, DY);
    Exit;
  end;
end;

procedure TAdventure.LayBombOf(Power: Integer);
const
  DX: array[0..3] of Double = (0, -1.5, 0, 1.5);
  DY: array[0..3] of Double = (-1.5, 0, 1.5, 0);
var
  N: Integer;
begin
  if (Mode <> ModeFree) or not WeaponsOn or (Player.Bombs <= 0) then Exit;
  Dec(Player.Bombs);
  N := Length(Bombs);
  SetLength(Bombs, N + 1);
  { where 2.05 puts the bomb was not read: a tile and a half ahead of the
    body }
  Bombs[N].X := Round((Player.X + 0.5 + DX[Player.Dir and 3]) * 2) / 2;
  Bombs[N].Y := Round((Player.Y + 1 + DY[Player.Dir and 3]) * 2) / 2;
  Bombs[N].Power := Power;
  Bombs[N].Fuse := 60;
  Bombs[N].Mine := True;
  if FClient.Connected then
    FClient.SendPacket(PLI_BOMBADD, GChar(Round(Bombs[N].X * 2)) + GChar(Round(Bombs[N].Y * 2)) +
      GChar(Power + 8) + GChar(60));
end;

procedure TAdventure.AddBlast(X, Y: Double; Reach, Kind: Integer; Mine: Boolean);
var
  N, D, K, E, OX, OY, C: Integer;
  PX, PY, QX, QY: Double;
const
  DX: array[0..4] of Integer = (0, 0, -1, 0, 1);
  DY: array[0..4] of Integer = (0, -1, 0, 1, 0);
begin
  if Reach > 15 then Reach := 15;
  N := Length(Blasts);
  SetLength(Blasts, N + 1);
  Blasts[N].X := X;
  Blasts[N].Y := Y;
  Blasts[N].Reach := Reach;
  Blasts[N].Kind := Kind;
  Blasts[N].Age := 0;
  Blasts[N].Mine := Mine;
  { only the owner changes the board: bushes (cut entry 0) and the sign,
    pot and stone (lift entries 1 to 3) under each piece, at four points }
  if not Mine then Exit;
  for D := 0 to 4 do
    for K := 0 to Reach do
    begin
      if (D = 0) and (K > 0) then Break;
      if (D > 0) and (K = 0) then Continue;
      PX := X + DX[D] * 2 * K;
      PY := Y + DY[D] * 2 * K;
      for C := 0 to 3 do
      begin
        QX := PX + 0.5 + (C and 1);
        QY := PY + 0.5 + (C shr 1);
        E := MatchObject(9, 1, QX, QY, OX, OY);
        if E = 0 then PutObject(OX, OY, 10, 0, True)
        else
        begin
          E := MatchObject(11, 4, QX, QY, OX, OY);
          if E >= 1 then PutObject(OX, OY, 12, E, True);
        end;
      end;
    end;
end;

procedure TAdventure.TickCombat;
var
  I, D, K: Integer;
  PX, PY: Double;
const
  DX: array[0..4] of Integer = (0, 0, -1, 0, 1);
  DY: array[0..4] of Integer = (0, -1, 0, 1, 0);
  KX: array[0..4] of Double = (0, 0, -1, 0, 1);
  KY: array[0..4] of Double = (0, -1, 0, 1, 0);
begin
  if FHurtCount > 0 then
  begin
    Dec(FHurtCount);
    if FHurtCount >= 35 then KnockStep;
    if (FHurtCount = 0) and (Mode = ModeFree) then Player.SetAni('idle', Frame);
  end;
  CheckSwordHits;
  { bombs burn down and go off as a blast of reach 2 }
  I := 0;
  while I <= High(Bombs) do
  begin
    Dec(Bombs[I].Fuse);
    if Bombs[I].Fuse <= 0 then
    begin
      if Bombs[I].Mine and FClient.Connected then
        FClient.SendPacket(PLI_EXPLOSION, GChar(2) + GChar(Round(Bombs[I].X * 2)) +
          GChar(Round(Bombs[I].Y * 2)) + GChar(Bombs[I].Power + 8));
      AddBlast(Bombs[I].X, Bombs[I].Y, 2, Bombs[I].Power, Bombs[I].Mine);
      Bombs[I] := Bombs[High(Bombs)];
      SetLength(Bombs, Length(Bombs) - 1);
      Continue;
    end;
    Inc(I);
  end;
  { each blast lives 11 ticks; a piece hurts when its centre (one tile in)
    is under a tile from the player's centre on both axes }
  I := 0;
  while I <= High(Blasts) do
  begin
    Inc(Blasts[I].Age);
    if Blasts[I].Age > 11 then
    begin
      Blasts[I] := Blasts[High(Blasts)];
      SetLength(Blasts, Length(Blasts) - 1);
      Continue;
    end;
    for D := 0 to 4 do
      for K := 0 to Blasts[I].Reach do
      begin
        if (D = 0) and (K > 0) then Break;
        if (D > 0) and (K = 0) then Continue;
        PX := Blasts[I].X + DX[D] * 2 * K + 1;
        PY := Blasts[I].Y + DY[D] * 2 * K + 1;
        if Hurtable and (Abs(PX - (Player.X + 1.5)) < 1) and (Abs(PY - (Player.Y + 2)) < 1) then
        begin
          if Blasts[I].Kind = 3 then HurtPlayer(1, KX[D], KY[D])
          else HurtPlayer(0.5, KX[D], KY[D]);
        end;
      end;
    Inc(I);
  end;
end;

{ ---- weapons and shots (status-display.md "The selected weapon",
  decomp-findings-2026-10-28/02-item-list.md, damage-sources.md) ---- }

procedure TAdventure.AddWeapon(const Name, Image: string; Item: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Weapons) do
    if Weapons[I].Name = Name then Exit;
  I := Length(Weapons);
  SetLength(Weapons, I + 1);
  Weapons[I].Name := Name;
  Weapons[I].Image := Image;
  Weapons[I].Item := Item;
  SelectWeapon(I);
end;

procedure TAdventure.AddDefaultWeapon(Item: Integer);
var
  Img, N: string;
begin
  case Item of
    7: Img := 'wbowi1.gif';
    8: Img := 'wbomb1.gif';
    12: Img := 'wbomb2.gif';
    20: Img := 'wbowi2.gif';
    21: Img := 'wbowi3.gif';
    22: Img := 'wbowi4.gif';
    23: Img := 'wbomb3.gif';
  else
    Exit;
  end;
  N := ItemNames[Item];
  N[1] := UpCase(N[1]);
  AddWeapon(N, Img, Item);
end;

procedure TAdventure.RemoveWeapon(const Name: string);
var
  I, J: Integer;
begin
  for I := 0 to High(Weapons) do
    if Weapons[I].Name = Name then
    begin
      for J := I to High(Weapons) - 1 do Weapons[J] := Weapons[J + 1];
      SetLength(Weapons, Length(Weapons) - 1);
      { the selection keeps its index if it still exists, else the last }
      if Selected > High(Weapons) then Selected := High(Weapons);
      Exit;
    end;
end;

procedure TAdventure.SelectWeapon(I: Integer);
var
  K, J: Integer;
begin
  if Length(Weapons) = 0 then
  begin
    Selected := -1;
    Exit;
  end;
  if (I < 0) or (I > High(Weapons)) then I := 0;
  for K := 0 to High(Weapons) do
  begin
    J := (I + K) mod Length(Weapons);
    if (Weapons[J].Name <> '') and (Weapons[J].Name[1] <> '-') then
    begin
      Selected := J;
      Exit;
    end;
  end;
  Selected := I;
end;

procedure TAdventure.UseWeapon;
begin
  if (Mode = ModeCarry) or (Mode = ModeHide) then
  begin
    ToggleHide;
    Exit;
  end;
  { S held with D picks the next weapon instead of using one }
  if AttackHeld and (Mode = ModeFree) then
  begin
    if Length(Weapons) > 0 then SelectWeapon(Selected + 1);
    Exit;
  end;
  if (Selected < 0) or (Selected > High(Weapons)) or (Mode <> ModeFree) or not WeaponsOn then Exit;
  case Weapons[Selected].Item of
    8: LayBombOf(1);
    12: LayBombOf(2);
    23: LayBombOf(3);
    7:
      if Player.Arrows > 0 then
      begin
        Dec(Player.Arrows);
        Shoot(0);
      end;
    20: Shoot(1);
    21: Shoot(2);
    22: Shoot(3);
  end;
  { NPC weapons run their script; that is the NPC code's part }
end;

procedure TAdventure.Shoot(Kind: Integer);
const
  { where 2.05 starts a shot was not read: just ahead of the body's middle }
  SX: array[0..3] of Double = (1.25, -0.5, 1.25, 2.5);
  SY: array[0..3] of Double = (0, 1.75, 2.5, 1.75);
var
  D, N: Integer;
begin
  D := Player.Dir and 3;
  AddShot(Player.X + SX[D], Player.Y + SY[D], D, 107 + D, Kind, True);
  N := High(Shots);
  if FClient.Connected then
    FClient.SendPacket(PLI_ARROWADD, GChar(Round(Shots[N].X * 2)) + GChar(Round(Shots[N].Y * 2)) +
      GChar(D) + GChar(107 + D) + GChar(Kind + 1));
end;

procedure TAdventure.AddShot(X, Y: Double; Dir, Sprite, Kind: Integer; Mine: Boolean);
var
  N: Integer;
begin
  N := Length(Shots);
  SetLength(Shots, N + 1);
  Shots[N].X := X;
  Shots[N].Y := Y;
  Shots[N].Dir := Dir and 3;
  Shots[N].Sprite := Sprite;
  Shots[N].Kind := Kind;
  Shots[N].Mine := Mine;
  Shots[N].Back := 0;
end;

procedure TAdventure.TickShots;
const
  DX: array[0..3] of Integer = (0, -1, 0, 1);
  DY: array[0..3] of Integer = (-1, 0, 1, 0);
var
  I: Integer;
  V: Cardinal;
  W, H: Double;
  Gone, Hit: Boolean;
  Sh: TShot;
begin
  I := 0;
  while I <= High(Shots) do
  begin
    Sh := Shots[I];
    { one tile a tick along its direction }
    Sh.X := Sh.X + DX[Sh.Dir];
    Sh.Y := Sh.Y + DY[Sh.Dir];
    { the size from the sprite table: ((v >> 6) & 63) / 16 by (v & 63) / 16 }
    W := 0.5;
    H := 0.5;
    if (Arrays.Lists[24] <> nil) and (Sh.Sprite >= 0) and (Sh.Sprite <= High(Arrays.Lists[24].Values)) then
    begin
      V := Cardinal(Arrays.Lists[24].Values[Sh.Sprite]);
      W := ((V shr 6) and 63) / 16;
      H := (V and 63) / 16;
    end;
    Gone := (Sh.X < -2) or (Sh.Y < -2) or (Sh.X >= 64) or (Sh.Y >= 64);
    Hit := False;
    if Sh.Back > 0 then
    begin
      Dec(Sh.Back);
      Gone := Gone or (Sh.Back = 0);
    end
    else if not Gone then
    begin
      { walls: 2.05's blocking test for arrows and fireballs lost its
        arguments in the decompile; here every shot stops at a wall }
      if PointBlocked(Sh.X + W / 2, Sh.Y + H / 2) then
      begin
        Gone := True;
        Hit := True;
      end
      else if Sh.Mine then
        { no NPCs or baddies in the rebuilt 3.04 yet: an own shot flies on }
      else if Hurtable and (AP <> 100) and (Sh.X + W > Player.X + 0.5) and (Sh.X < Player.X + 2.5) and
        (Sh.Y + H > Player.Y + 1) and (Sh.Y < Player.Y + 3) then
      begin
        if ((Player.Dir and 3) = (Sh.Dir xor 2)) and (Player.ShieldPower > 0) and
          (Sh.Kind <= 1) and ((Player.AniName = 'idle') or (Player.AniName = 'walk')) then
        begin
          { the shield: power 1 knocks an arrow back for three ticks;
            2 and up send the shot back as this player's own }
          Sh.Dir := Sh.Dir xor 2;
          if Player.ShieldPower >= 2 then
          begin
            if Sh.Sprite in [107..110] then Sh.Sprite := 107 + Sh.Dir;
            Sh.Mine := True;
            if FClient.Connected then
              FClient.SendPacket(PLI_ARROWADD, GChar(Round(Sh.X * 2)) + GChar(Round(Sh.Y * 2)) +
                GChar(Sh.Dir + 4) + GChar(Sh.Sprite) + GChar(Sh.Kind + 1));
          end
          else if Sh.Sprite in [107..110] then
            Sh.Back := 3
          else
            Gone := True;
        end
        else
        begin
          if Sh.Kind in [1, 3] then HurtPlayer(1, DX[Sh.Dir], DY[Sh.Dir])
          else HurtPlayer(0.5, DX[Sh.Dir], DY[Sh.Dir]);
          Gone := True;
          Hit := True;
        end;
      end;
    end;
    { a fireblast or nuke leaves a blast of reach 2 where it stops }
    if Hit and (Sh.Kind >= 2) then AddBlast(Sh.X - 0.5, Sh.Y - 0.5, 2, 1, Sh.Mine);
    if Gone then
    begin
      Shots[I] := Shots[High(Shots)];
      SetLength(Shots, Length(Shots) - 1);
      Continue;
    end;
    Shots[I] := Sh;
    Inc(I);
  end;
end;

procedure TAdventure.DrawShots(CamX, CamY: Integer);
var
  I, SX, SY, SW, SH: Integer;
  Img: TGSurface;
begin
  Img := Assets.Image('sprites.png', '');
  for I := 0 to High(Shots) do
    if (Img <> nil) and Arrays.SpriteRect(Shots[I].Sprite, SX, SY, SW, SH) then
      Screen.Blit(Img, SX, SY, SW, SH, Round(Shots[I].X * TileSize) - CamX,
        Round(Shots[I].Y * TileSize) - CamY)
    else
      Screen.FillRect(Round(Shots[I].X * TileSize) - CamX, Round(Shots[I].Y * TileSize) - CamY,
        8, 8, $FFFFFFFF);
end;

{ The item list window: from (16, 80) to 16 pixels from the right and
  bottom edges, cells from (48, 112), packed left to right then down;
  each cell is the image (or a 32 x 32 place) over its name. }
{ A weapon whose name starts with '-' is a system weapon: it runs but is
  left out of the item list. }
function HiddenWeapon(const Name: string): Boolean;
begin
  Result := (Name = '') or (Name[1] = '-');
end;

procedure ListCells(G: TAdventure; out CX, CY, CW, CH: array of Integer);
var
  I, X, Y, RowH, W, H: Integer;
  Img: TGSurface;
begin
  X := 48;
  Y := 112;
  RowH := 0;
  for I := 0 to High(G.Weapons) do
  begin
    if I > High(CX) then Break;
    if HiddenWeapon(G.Weapons[I].Name) then
    begin
      CX[I] := 0;
      CY[I] := 0;
      CW[I] := 0;
      CH[I] := 0;
      Continue;
    end;
    Img := nil;
    if G.Weapons[I].Image <> '' then Img := G.Assets.Image(G.Weapons[I].Image, 'weapon');
    if Img <> nil then
    begin
      W := Img.Width;
      H := Img.Height;
    end
    else
    begin
      W := 32;
      H := 32;
    end;
    W := Max(W, TextWidth(G.Weapons[I].Name, 1)) + 10;
    H := H + GlyphH + 15;
    if (X + W > ScreenW - 48) and (X > 48) then
    begin
      X := 48;
      Inc(Y, RowH);
      RowH := 0;
    end;
    CX[I] := X;
    CY[I] := Y;
    CW[I] := W;
    CH[I] := H;
    Inc(X, W);
    if H > RowH then RowH := H;
  end;
end;

procedure TAdventure.ItemListKeys;
var
  CX, CY, CW, CH: array[0..63] of Integer;
  Down: Boolean;
  I, Best, BestD, D, Dir, MX, MY: Integer;
begin
  Down := Keys[0] or Keys[1] or Keys[2] or Keys[3] or ActionKey or AttackKey or ItemKey or ItemListKey;
  if Down and not FListWasDown then
  begin
    Dir := -1;
    for I := 3 downto 0 do
      if Keys[I] then Dir := I;
    if Dir >= 0 then
    begin
      { an arrow key takes the nearest cell that way }
      ListCells(Self, CX, CY, CW, CH);
      if (Selected >= 0) and (Selected <= High(Weapons)) and (Selected <= 63) then
      begin
        MX := CX[Selected] + CW[Selected] div 2;
        MY := CY[Selected] + CH[Selected] div 2;
        Best := -1;
        BestD := MaxInt;
        for I := 0 to Min(High(Weapons), 63) do
        begin
          if (I = Selected) or (Weapons[I].Name = '') or (Weapons[I].Name[1] = '-') then Continue;
          case Dir of
            DirUp: if CY[I] + CH[I] > CY[Selected] then Continue;
            DirDown: if CY[I] < CY[Selected] + CH[Selected] then Continue;
            DirLeft: if (CY[I] <> CY[Selected]) or (CX[I] >= CX[Selected]) then Continue;
            DirRight: if (CY[I] <> CY[Selected]) or (CX[I] <= CX[Selected]) then Continue;
          end;
          D := Sqr(CX[I] + CW[I] div 2 - MX) + Sqr(CY[I] + CH[I] div 2 - MY);
          if D < BestD then
          begin
            BestD := D;
            Best := I;
          end;
        end;
        if Best >= 0 then Selected := Best;
      end;
    end
    else
      { the list key again, or any other game key, closes it }
      ItemListOpen := False;
  end;
  FListWasDown := Down;
  for I := 0 to 3 do Keys[I] := False;
  ActionKey := False;
  AttackKey := False;
  ItemKey := False;
  ItemListKey := False;
end;

procedure TAdventure.DrawItemList;
var
  CX, CY, CW, CH: array[0..63] of Integer;
  I, W, H: Integer;
  Img: TGSurface;
begin
  W := ScreenW - 32;
  H := ScreenH - 96;
  Screen.FillRect(16, 80, W, H, $FF302010);
  Screen.FillRect(18, 82, W - 4, H - 4, $FFFFF0C8);
  DrawText(Screen, 48, 92, 'Weapons', $FF302010, 2);
  ListCells(Self, CX, CY, CW, CH);
  for I := 0 to Min(High(Weapons), 63) do
  begin
    if HiddenWeapon(Weapons[I].Name) then Continue;
    if CY[I] + CH[I] > ScreenH - 64 then Break;
    if I = Selected then Screen.FillRect(CX[I], CY[I], CW[I], CH[I], $FFFFD480);
    Img := nil;
    if Weapons[I].Image <> '' then Img := Assets.Image(Weapons[I].Image, 'weapon');
    if Img <> nil then
      Screen.Blit(Img, 0, 0, Img.Width, Img.Height, CX[I] + (CW[I] - Img.Width) div 2, CY[I] + 5)
    else
      Screen.FillRect(CX[I] + (CW[I] - 32) div 2, CY[I] + 5, 32, 32, $FFB0A080);
    DrawText(Screen, CX[I] + (CW[I] - TextWidth(Weapons[I].Name, 1)) div 2,
      CY[I] + CH[I] - GlyphH - 5, Weapons[I].Name, $FF302010, 1);
  end;
end;


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
      first), else with LEVELWARP; 3.151 is taken to do the same, with no
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

{ The first client frame after the login burst, as 3.151 sent it in the lab
  run: the props 0, 18, 31, 33, 52, 75 and 76, then UPDATEFILE for the
  player's head (the real client also asks for its two default weapon
  icons, and WANTFILE for the list icons named by 180; not yet), and
  ADJACENTLEVEL on a gmap. }
procedure TAdventure.SendLoginFrame;
var
  F: string;
  MT: Cardinal;
begin
  FClient.SendPacket(PLI_PLAYERPROPS,
    GChar(PLPROP_NICKNAME) + GString(Player.Nickname) +
    GChar(PLPROP_STATUS) + GChar(Player.Status) +
    GChar(PLPROP_UDPPORT) + GInt3(0) +   { no UDP peer channel yet }
    GChar(PLPROP_ADDITFLAGS) + GChar(0) +
    GChar(PLPROP_PLANGUAGE) + GString(Player.Language) +
    GChar(PLPROP_OSTYPE) + GString(OsType) +
    GChar(PLPROP_TEXTCODEPAGE) + GInt3(TextCodePage));
  if Player.HeadImage <> '' then
  begin
    MT := 0;
    F := Assets.FindFile(Player.HeadImage, ['', 'levels/', 'levels/heads/']);
    if F <> '' then
      MT := Cardinal(Round((FileDateToDateTime(FileAge(F)) - 25569.0) * 86400.0));
    FClient.SendPacket(PLI_UPDATEFILE, GInt5(MT) + Player.HeadImage);
  end;
  AskAdjacent;
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentDir := Player.Dir;
  FSentGani := OwnGani;
  FSentGmapX := Player.GmapX;
  FSentGmapY := Player.GmapY;
  FPropsSent := True;
end;

procedure TAdventure.Say(const Text: string);
begin
  Player.Chat := Text;
  if FClient.Connected and LoggedIn then
  begin
    FClient.SendPacket(PLI_PLAYERPROPS, GChar(PLPROP_CURCHAT) + GString(Text));
    FClient.Flush;
  end;
end;

procedure TAdventure.SendMovedProps;
var
  S, G: string;
begin
  { a diff of the changed props, in id order, at most every other tick
    (100 ms); X and Y as c(x * 2) (run-222d, b4_222) }
  if not FPropsSent or (Frame mod 2 <> 0) then Exit;
  S := '';
  G := OwnGani;
  if G <> FSentGani then S := S + GChar(PLPROP_GANI) + GString(G);
  if Player.X <> FSentX then S := S + GChar(PLPROP_X) + GChar(Round(Player.X * 2));
  if Player.Y <> FSentY then S := S + GChar(PLPROP_Y) + GChar(Round(Player.Y * 2));
  if Player.Dir <> FSentDir then S := S + GChar(PLPROP_SPRITE) + GChar(Player.Dir);
  if Player.GmapX <> FSentGmapX then S := S + GChar(PLPROP_GMAPLEVELX) + GChar(Player.GmapX);
  if Player.GmapY <> FSentGmapY then S := S + GChar(PLPROP_GMAPLEVELY) + GChar(Player.GmapY);
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
procedure TAdventure.ServerWarp(const Data: string);
var
  F: TStringList;
  Port: Integer;
begin
  F := TStringList.Create;
  try
    F.CommaText := Data;
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
    while FOthers.Count > 0 do RemoveOther(Others[0].Id);
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
  J, BX, BY: Integer;
  FX, FY: Double;
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
      PLO_LEVELCHEST: { c opened, c x, c y; if not opened, c item, c sign }
        begin
          if Length(Data) < 3 then Exit;
          T := FCurrentData;
          if T = nil then T := Level;
          CH.Opened := R.ReadGChar <> 0;
          CH.X := R.ReadGChar;
          CH.Y := R.ReadGChar;
          CH.Item := -1;
          CH.Sign := -1;
          if Length(Data) >= 5 then
          begin
            CH.Item := R.ReadGChar;
            CH.Sign := R.ReadGChar;
          end;
          { a chest is sent on every visit: one per position; an opened one
            stays opened }
          V := -1;
          for I := 0 to High(T.Chests) do
            if (T.Chests[I].X = CH.X) and (T.Chests[I].Y = CH.Y) then V := I;
          if V < 0 then
          begin
            SetLength(T.Chests, Length(T.Chests) + 1);
            T.Chests[High(T.Chests)] := CH;
          end
          else
          begin
            if T.Chests[V].Opened then CH.Opened := True;
            T.Chests[V] := CH;
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
      PLO_ITEMADD: { c x*2, c y*2, c item; only floor items are made }
        begin
          if Length(Data) < 3 then Exit;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          V := R.ReadGChar;
          if FloorItem(V) then AddItem(FX, FY, V, ItemLife);
        end;
      PLO_BOMBADD: { s player, c x*2, c y*2, c power (+8 theirs), c fuse }
        begin
          if Length(Data) < 6 then Exit;
          R.ReadGShort;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          V := R.ReadGChar and 7;
          I := R.ReadGChar;
          J := Length(Bombs);
          SetLength(Bombs, J + 1);
          Bombs[J].X := FX;
          Bombs[J].Y := FY;
          Bombs[J].Power := Max(1, Min(3, V));
          { the sender's copy burns five ticks shorter }
          Bombs[J].Fuse := Max(1, I - 5);
          Bombs[J].Mine := False;
        end;
      PLO_BOMBDEL: { c x*2, c y*2, no player id }
        begin
          if Length(Data) < 2 then Exit;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          for I := High(Bombs) downto 0 do
            if (Bombs[I].X = FX) and (Bombs[I].Y = FY) then
            begin
              Bombs[I] := Bombs[High(Bombs)];
              SetLength(Bombs, Length(Bombs) - 1);
            end;
        end;
      PLO_EXPLOSION: { s player, c reach, c x*2, c y*2, c power }
        begin
          if Length(Data) < 6 then Exit;
          R.ReadGShort;
          I := R.ReadGChar;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          V := R.ReadGChar and 7;
          if V = 0 then V := 1;
          if V > 3 then V := 3;
          AddBlast(FX, FY, I, V, False);
        end;
      PLO_HURTPLAYER: { s attacker, c dx, c dy, c power [+ i3 npc] }
        begin
          if Length(Data) < 5 then Exit;
          V := R.ReadGShort;
          OP := FindOther(V, False);
          { a hit from an NPC (six or more bytes after the id) or from an
            unknown player is refused, as are attackers over 10 tiles off }
          if (OP = nil) or (Length(Data) - 2 >= 6) or not Hurtable or (AP = 100) then Exit;
          if Sqr(OP.X - Player.X) + Sqr(OP.Y - Player.Y) > 100 then Exit;
          FX := (R.ReadGChar + 32 - $60) / 16;
          FY := (R.ReadGChar + 32 - $60) / 16;
          I := Min(2, Max(0, R.ReadGChar));
          HurtPlayer(I / 2, FX, FY);
        end;
      PLO_ITEMDEL: { c x*2, c y*2: the item at exactly that point }
        begin
          if Length(Data) < 2 then Exit;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          for I := High(Items) downto 0 do
            if (Items[I].X = FX) and (Items[I].Y = FY) then RemoveItem(I);
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
      PLO_TOALL: Log('TOALL ' + Data);
      PLO_DEFAULTWEAPON: { c item number }
        if Length(Data) >= 1 then AddDefaultWeapon(R.ReadGChar);
      PLO_NPCWEAPONADD: { name, then the weapon NPC's props (image, script) }
        begin
          S := R.ReadGString;
          if S <> '' then AddWeapon(S, '', -1);
        end;
      PLO_NPCWEAPONDEL: RemoveWeapon(Data);
      PLO_ARROWADD: { s player, c x*2, c y*2, c flags, c sprite, c type + 1 }
        begin
          if Length(Data) < 7 then Exit;
          R.ReadGShort;
          FX := R.ReadGChar / 2;
          FY := R.ReadGChar / 2;
          V := R.ReadGChar;
          BX := R.ReadGChar;
          BY := R.ReadGChar - 1;
          if V and 4 <> 0 then
            { a shot sent back: first the copy flying the other way on the
              same line goes }
            for I := High(Shots) downto 0 do
              if ((Shots[I].Dir xor 2) = (V and 3)) and
                (((Shots[I].Dir and 1 = 0) and (Abs(Shots[I].X - FX) < 0.01)) or
                 ((Shots[I].Dir and 1 = 1) and (Abs(Shots[I].Y - FY) < 0.01))) then
              begin
                Shots[I] := Shots[High(Shots)];
                SetLength(Shots, Length(Shots) - 1);
              end;
          AddShot(FX, FY, V and 3, BX, Max(0, Min(3, BY)), False);
        end;
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
    if not FClient.Connected then
      Log('link closed: ' + FClient.LastError);
  end;
  { the first frame after the login burst }
  if LoggedIn and not FPropsSent and FClient.Connected then SendLoginFrame;
  { a new level: its entry point is where a death sends the player back }
  if Level.Name <> FEntryLevel then
  begin
    FEntryLevel := Level.Name;
    FEntryX := Player.X;
    FEntryY := Player.Y;
    SetLength(Bombs, 0);
    SetLength(Blasts, 0);
  end;
  if Mode = ModeDead then
  begin
    if Keys[0] or Keys[1] or Keys[2] or Keys[3] then Respawn;
    for D := 0 to 3 do Keys[D] := False;
    AttackKey := False;
    ActionKey := False;
    ItemKey := False;
  end;
  { the item list (Q) takes the keys while it is open }
  if ItemListOpen then ItemListKeys
  else if ItemListKey and (Mode = ModeFree) then
  begin
    ItemListOpen := True;
    FListWasDown := True;
  end;
  ItemListKey := False;
  { the lay mode: S held with A takes the next item, A alone lays it, any
    other game key leaves the mode }
  if Mode = ModeLay then
  begin
    if ActionKey and AttackHeld then LayItem := NextLayItem(LayItem)
    else if ActionKey then LayDown
    else if AttackKey or ItemKey or Keys[0] or Keys[1] or Keys[2] or Keys[3] then
    begin
      Mode := ModeFree;
      LayItem := -1;
    end;
    AttackKey := False;
    ActionKey := False;
    ItemKey := False;
    for D := 0 to 3 do Keys[D] := False;
  end;
  { the game keys first: a swing, a spin or a lift holds the player still }
  if AttackKey then Attack;
  if ActionKey then Action;
  if ItemKey then UseWeapon;
  AttackKey := False;
  ActionKey := False;
  ItemKey := False;
  if (Mode in [ModeSword, ModeSpin, ModeLift]) and (Frame >= FModeUntil) then
    if Mode = ModeLift then Mode := ModeCarry else Mode := ModeFree;
  { keys run in the order up, left, down, right, each from where the
    earlier ones left the player }
  Moved := False;
  AX := 0;
  AY := 0;
  for D := 0 to 3 do
    if Keys[D] and not Frozen and (Mode in [ModeFree, ModeCarry, ModeHide]) and
      (FHurtCount < 35) then
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
  case Mode of
    ModeFree:
      if FHurtCount > 0 then
        { the hurt pose holds while the hurt mode runs }
      else if Moved then Player.SetAni('walk', Frame) else Player.SetAni('idle', Frame);
    ModeCarry: if Moved then Player.SetAni('carry', Frame) else Player.SetAni('carrystill', Frame);
    ModeHide: if Moved then Player.SetAni('hidden', Frame) else Player.SetAni('hiddenstill', Frame);
  end;
  if Moved then CrossEdges;
  TickItems;
  TickShots;
  TickCombat;
  { links are tested on the player's own walk, at one point: the body's
    centre pushed ahead in the walking direction }
  if Moved then FollowLink(LinkAt(Player.X + 1.5 + AX, Player.Y + 2 + AY));
  SendMovedProps;
  { 3.151 sends no periodic 24 over TCP (3.04 lab run, assumed) }
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
    if Parts[I].Sprite = ParamSprite - 1 then
    begin
      { PARAM1 of the lift and carry ganis: the carried object, drawn with
        its carry sprite (bush 261, sign 267, pot 265, stone 263, black
        stone 239), or from its board tiles when there is no table }
      if (P = Player) and (CarryKind >= 0) then
        DrawCarried(CarryKind, BX + Parts[I].X, BY + Parts[I].Y);
      Continue;
    end;
    if not A.FindSprite(Parts[I].Sprite, Spr) then Continue;
    SheetName := UpperCase(Spr.Sheet);
    if SheetName = 'SPRITES' then Img := Assets.Image('sprites.png', '')
    else if SheetName = 'HEAD' then Img := Assets.Image(P.HeadImage, 'head')
    else if SheetName = 'BODY' then Img := BodyFor(P)
    else if SheetName = 'SWORD' then Img := Assets.Image(P.SwordImage, 'sword')
    else if SheetName = 'SHIELD' then Img := Assets.Image(P.ShieldImage, 'shield')
    { a PARAM1 sheet is the player's sword, as in 2.22 }
    else if SheetName = 'PARAM1' then Img := Assets.Image(P.SwordImage, 'sword')
    else if SheetName = 'PICS' then Img := Sheet
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
            if Parts.Count >= 3 then
              FTileDefTypes.Values[Prefix + #9 + Img] := IntToStr(StrToIntDef(Trim(Parts[2]), 0))
            else
              FTileDefTypes.Values[Prefix + #9 + Img] := '';
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

{ The FTileDefs entry for a level: the first whose prefix starts its
  name, else -1. }
function TAdventure.TileDefFor(const LevelName: string): Integer;
var
  I, T: Integer;
  N: string;
begin
  Result := -1;
  N := LowerCase(LevelName);
  for I := 0 to FTileDefs.Count - 1 do
  begin
    T := Pos(#9, FTileDefs[I]);
    if Copy(N, 1, T - 1) = Copy(FTileDefs[I], 1, T - 1) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

function TAdventure.TileSheetFor(const LevelName: string): TGSurface;
var
  I: Integer;
  S: TGSurface;
begin
  Result := Sheet;
  I := TileDefFor(LevelName);
  if I < 0 then Exit;
  S := Assets.Image(Copy(FTileDefs[I], Pos(#9, FTileDefs[I]) + 1, MaxInt), '');
  if (S <> nil) and (S.Width > 0) then Result := S;
end;

{ The sheet type a level's tiles are tested with: the tiledef's third
  field, 0 (the default pics1.png) without one (Graal_analysis
  torque/304-tile-types.md). }
function TAdventure.SheetTypeFor(const LevelName: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := TileDefFor(LevelName);
  if I >= 0 then Result := StrToIntDef(FTileDefTypes.Values[FTileDefs[I]], 0);
end;

{ the level's own addtiledef lines, once per level, drawn or not }
procedure TAdventure.NoteLevelTileDefs;
begin
  if Level.Name <> FTileDefLevel then
  begin
    NoteTileDefs(Level);
    FTileDefLevel := Level.Name;
  end;
end;

{ 3.04's walking test for one tile (Graal_analysis torque/304-tile-types.md).
  Sheet type 0: free only when the id is in array 0 or array 1. Types 1 and
  2 (picso.png): by row (id div 16) and column (id mod 16); a wall when
  id = 32, rows 26-27 from column 2, rows 30-47, 84-95 or 116-127, or a row
  from 128 with bit 16 set. }
function TAdventure.TileBlocks(T: Integer): Boolean;
var
  Row, Col: Integer;
begin
  case SheetTypeFor(Level.Name) of
    1, 2:
      begin
        Row := T div 16;
        Col := T mod 16;
        Result := (T = 32) or ((Row >= 26) and (Row <= 27) and (Col >= 2)) or
          ((Row >= 30) and (Row <= 47)) or ((Row >= 84) and (Row <= 95)) or
          ((Row >= 116) and (Row <= 127)) or ((Row >= 128) and (Row and 16 <> 0));
      end;
  else
    Result := not Arrays.TilePassable(T);
  end;
end;

procedure TAdventure.DrawCombat(CamX, CamY: Integer);
var
  I, Stage, SX, SY: Integer;
  Img: TGSurface;
begin
  Img := Assets.Image('bomb1.png', '');
  if Img = nil then Exit;
  for I := 0 to High(Bombs) do
  begin
    { blue, white, red for powers 1 to 3; it flashes near the end }
    if (Bombs[I].Fuse < 15) and Odd(Bombs[I].Fuse div 2) then Continue;
    Screen.Blit(Img, 32 * ((Bombs[I].Power - 1) mod 3), 0, 32, 32,
      Round(Bombs[I].X * TileSize) - CamX, Round(Bombs[I].Y * TileSize) - CamY);
  end;
  for I := 0 to High(Blasts) do
  begin
    { the explosion pictures in bomb1.png: four vertical arms (32 x 160 at
      x 0, 32, 64, 96) and four horizontal (128 x 32 from y 192), from
      fat to thin as the blast dies; which part 2.05 cuts for each piece
      was not read, so the arms are drawn whole for a reach-2 blast }
    Stage := Min(3, Blasts[I].Age div 3);
    SX := Round((Blasts[I].X + 1) * TileSize) - CamX;
    SY := Round((Blasts[I].Y + 1) * TileSize) - CamY;
    Screen.Blit(Img, 32 * Stage, 32, 32, 160, SX - 16, SY - 80);
    Screen.Blit(Img, 0, 192 + 32 * Stage, 128, 32, SX - 64, SY - 16);
  end;
end;


procedure TAdventure.DrawObjectTiles(List, I, X, Y: Integer);
var
  C, R, T: Integer;
begin
  for C := 0 to 1 do
    for R := 0 to 1 do
    begin
      T := Arrays.ObjectTile(List, I, C, R);
      if T >= 0 then DrawTile(Screen, Sheet, T, X + C * TileSize, Y + R * TileSize);
    end;
end;

procedure TAdventure.DrawCarried(Kind, X, Y: Integer);
var
  Img: TGSurface;
  SX, SY, SW, SH: Integer;
begin
  if (Kind < 0) or (Kind > High(CarrySprites)) then Exit;
  Img := Assets.Image('sprites.png', '');
  if (Img <> nil) and Arrays.SpriteRect(CarrySprites[Kind], SX, SY, SW, SH) then
    Screen.Blit(Img, SX, SY, SW, SH, X, Y)
  else
    DrawObjectTiles(11, Kind, X, Y);
end;

{ The level's chests, from its CHEST records or PLO_LEVELCHEST (4): each
  a 2 x 2 block at its x, y drawn over the board, closed (arrays.dat list
  13) or opened (list 14), whatever the board holds there. The real 2.22,
  2.31 and 2.17.1 draw a chest the server sends on a board without chest
  tiles, and an opened one as opened (graal_analysis
  client-internals/lab-captures-2026-10-25/01-damage-chest-respawn-weapons.md,
  and the 2026-11-12 lab run). }
procedure TAdventure.DrawChests(Tiles: TGSurface; CamX, CamY: Integer);
const
  Closed: array[0..3] of Integer = (1784, 1785, 1800, 1801);
  Opened: array[0..3] of Integer = (829, 830, 845, 846);
var
  I, K, T: Integer;
begin
  for I := 0 to High(Level.Chests) do
    for K := 0 to 3 do
    begin
      if Level.Chests[I].Opened then
      begin
        T := -1;
        { the open chest is one object: column, then row }
        if (Arrays.Lists[14] <> nil) and (K mod 2 <= High(Arrays.Lists[14].Items)) and
          (K div 2 <= High(Arrays.Lists[14].Items[K mod 2].Values)) then
          T := Arrays.Lists[14].Items[K mod 2].Values[K div 2];
        if T < 0 then T := Opened[K];
      end
      else
      begin
        T := -1;
        if (Arrays.Lists[13] <> nil) and (High(Arrays.Lists[13].Values) >= 3) then
          T := Arrays.Lists[13].Values[K];
        if T < 0 then T := Closed[K];
      end;
      DrawTile(Screen, Tiles, T, (Level.Chests[I].X + K mod 2) * TileSize - CamX,
        (Level.Chests[I].Y + K div 2) * TileSize - CamY);
    end;
end;

procedure TAdventure.DrawItems(CamX, CamY: Integer);
var
  I, SX, SY, SW, SH, HX, HY, HW, HH: Integer;
  Img: TGSurface;
  It: TFloorItem;
  Lift: Double;
begin
  Img := Assets.Image('sprites.png', '');
  for I := 0 to High(Items) do
  begin
    It := Items[I];
    { blinks out in its last moments }
    if (It.Life < 37) and Odd(It.Life) then Continue;
    if (Img = nil) or not Arrays.SpriteRect(ItemSprites[It.Item], SX, SY, SW, SH) then
    begin
      { no sprite table: a marker the size of a rupee }
      Screen.FillRect(Round((It.X + 1) * TileSize) - CamX - 4,
        Round((It.Y + 1) * TileSize) - CamY - 8, 8, 16, $FFFFE060);
      Continue;
    end;
    { bounces as it lands: |sin(life / 3)| (life / 164)^16 3 tiles }
    Lift := 0;
    if It.Life >= ItemLife - 7 * Pi then
      Lift := Abs(Sin(It.Life / 3)) * Power(It.Life / ItemLife, 16) * 3;
    { the shadow at (x + 0.5, y + 1 + h / 2 - 0.5), h the item's height in
      tiles; the item centred on (x + 1, y + 1) }
    if Arrays.SpriteRect(ItemShadowSprite, HX, HY, HW, HH) then
      Screen.Blit(Img, HX, HY, HW, HH, Round((It.X + 0.5) * TileSize) - CamX,
        Round((It.Y + 1 + SH / TileSize / 2 - 0.5) * TileSize) - CamY);
    Screen.Blit(Img, SX, SY, SW, SH, Round((It.X + 1) * TileSize) - SW div 2 - CamX,
      Round((It.Y + 1 - Lift) * TileSize) - SH div 2 - CamY);
  end;
end;


procedure TAdventure.Draw;
var
  LCamX, LCamY, CamX, CamY, TX, TY, X0, Y0, I, T, WorldW, WorldH, PX, PY: Integer;
  Tiles: TGSurface;
begin
  Screen.Fill($FF000000);
  if Sheet.Width = 0 then MakeIndexSheet(Sheet);
  NoteLevelTileDefs;
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
  { what lives in the player's level (items, shots, things thrown) is in
    that level's tiles: on a gmap its cell is offset }
  LCamX := CamX - PX * TileSize;
  LCamY := CamY - PY * TileSize;
  { items under the players, others, then the player on top, then
    anything in the air }
  DrawChests(Tiles, LCamX, LCamY);
  DrawItems(LCamX, LCamY);
  for I := 0 to FOthers.Count - 1 do
    DrawPlayer(Others[I], CamX, CamY);
  DrawPlayer(Player, CamX, CamY);
  DrawCombat(LCamX, LCamY);
  DrawShots(LCamX, LCamY);
  for I := 0 to High(Thrown) do
    DrawCarried(Thrown[I].Kind, Round(Thrown[I].X * TileSize) - LCamX,
      Round(Thrown[I].Y * TileSize) - LCamY);
  { the item chosen in the lay mode, centred on (x + 1.5, y) }
  if (Mode = ModeLay) and (LayItem >= 0) then
  begin
    Tiles := Assets.Image('sprites.png', '');
    if (Tiles <> nil) and Arrays.SpriteRect(ItemSprites[LayItem], TX, TY, X0, Y0) then
      Screen.Blit(Tiles, TX, TY, X0, Y0, Round((Player.X + 1.5) * TileSize) - LCamX - X0 div 2,
        Round(Player.Y * TileSize) - LCamY - Y0 div 2);
  end;
  if ItemListOpen then DrawItemList;
end;

end.
