{ Adventure: TAdventure, the game state and frame loop of 2.17.1.

  Copied from the 2.05 rev 2 rebuild and changed where 2.17.1 differs:
  the GANI prop (10) in place of the bow, the direction-only sprite prop,
  the wider prop streams, PLANGUAGE at session start, PLAYERWARP2 and the
  ids 169 to 185. The frame loop, walking, items, combat and the board are
  2.05's until a difference is found.

  In 2.05 TAdventure is the main TDXForm: it owns the level, the local
  player, the link to the server, and the frame function that the idle
  handler calls on a 50 ms gate (graal_analysis client-internals/
  rendering-observations.md). A stall is one frame; there is no catch-up.

  This rebuild keeps that split. TAdventure draws each frame into a
  TGSurface; a front end shows it in a window or writes it to a file, and
  feeds the held keys in. }
unit Adventure;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GTypes, GLevel, GSurface, GArrays, GAni, GBuiltin, GAssetDirs, GraalClient, Protocol217,
  Npc217, Baddy217;

const
  { The game view. 2.05's window size is not yet read from the binary;
    640x480 is the classic default and is marked as an assumption. }
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
  end;

  TServerPlayer = class
  public
    Id: Integer;
    Nickname, Account, Level, HeadImage, BodyImage, SwordImage, ShieldImage,
    Chat: string;
    Attr: array[1..30] of string; { #P1 to #P30 }
    X, Y: Double;       { tiles, top-left of the 3x3-tile sprite box }
    Sprite, Status, MaxPower, Power, Rupees, Arrows, Bombs: Integer;
    SwordPower, ShieldPower, GlovePower, BombPower: Integer;
    Colors: array[0..4] of Integer;
    Dir: Integer;
    AniName: string;
    AniStart: Integer;  { frame the animation started on }
    { -1: the animation runs with time. Otherwise the step to draw. }
    FixedStep: Integer;
    { the frame the props are applied on, so a new gani starts there }
    NowFrame: Integer;
    Gone: Boolean;      { PCONNECTED or a level leave seen }
    HitSecond: Integer; { second of the day this player's swing last hit us }
    BodyCache: TGSurface; { the body recoloured for this player }
    SoundKey: string;   { the gani step whose sound was played (Sound217) }
    BodyKey: string;
    constructor Create;
    destructor Destroy; override;
    { Parses a prop stream. Stops at the first id the stream does not
      accept, the way 2.17.1 does, and returns the ids applied. Other is the
      OTHERPLPROPS stream. }
    function ApplyProps(R: TGReader; Other: Boolean): string;
    procedure SetAni(const Name: string; Frame: Integer);
  end;

  { An item lying on the board (2.05's TAdventureExtra; see
    client-internals/item-drops.md). }
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

  { Hooks for what the NPC and baddy code answers to, in tiles: a sword
    swing's hit box, a bomb blast's centre and reach, an arrow's middle
    (True when something took the shot, which then goes). }
  TSwordHitEvent = procedure(X, Y, W, H: Double; Power: Integer) of object;
  TBombBlastEvent = procedure(X, Y: Double; Radius: Integer) of object;
  TArrowHitEvent = function(X, Y: Double; Power: Integer): Boolean of object;

  TAdventure = class
  private
    FModeUntil: Integer;   { frame the sword swing or lift ends }
    FSignWasDown: Boolean; { a game key was down on the tick before }
    FListWasDown: Boolean;
    FHurtCount: Integer;   { hurt mode: ticks left of 40 }
    FKnockX, FKnockY: Double;
    FEntryX, FEntryY: Double; { where the player came into this level }
    FEntryLevel: string;
    FClient: TAdventureClient;
    FLog: TStrings;
    FSentX, FSentY: Double;
    FSentSprite: Integer;
    FSentAni: string;
    FPropsSent: Boolean;
    FOthers: TList;
    FLevelDir: string;     { folder of the level file played offline }
    FWarpPending: Boolean; { a link warp was asked of the server }
    FWarpX, FWarpY: Double;
    FWarpLevel: string;
    FWarpTimed: string;    { the level a timed warp waits for }
    FWarpT0: Int64;
    procedure KnockStep;
    procedure CheckSwordHits;
    procedure ItemListKeys;
    procedure TickCombat;
    procedure DrawCombat(CamX, CamY: Integer);
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure ClientLog(const Line: string);
    procedure SendInitialProps;
    procedure SendMovedProps;
    function BodyFor(P: TServerPlayer): TGSurface;
    function GetOther(I: Integer): TServerPlayer;
    function GetOtherCount: Integer;
  public
    Level: TAdventureLevel;
    Player: TServerPlayer;
    Screen: TGSurface;
    Sheet: TGSurface;    { pics1 }
    SheetBuiltin: Boolean; { Sheet is the built-in default }
    { GS1 addtiledef: 'prefix'#9'image', newest first, the sheet type in
      Objects. A level whose name starts with the prefix is drawn from that
      image instead of pics1. }
    TileDefs: TStringList;
    { GS1 replaceani OLD,NEW: the player's own OLD gani is played and sent
      as NEW (old=new pairs) }
    AniReplace: TStringList;
    { the sheet the current level is drawn with (set by Draw) }
    Tiles: TGSurface;
    Arrays: TGArrays;
    Assets: TAssets;
    Frame: Integer;
    WorldTime: Cardinal;
    ServerMessage, DisconnectReason: string;
    LoggedIn, BoardLoaded: Boolean;
    { No drawing in the tick: for stress runs. }
    Headless: Boolean;
    { Log lines also go to stderr as they happen. The in-memory log keeps
      the last LogKeep lines either way. }
    Echo: Boolean;
    { The status display (HUD): which parts show, as 2.05's showstats bits
      (0x01 buttons, 0x02 icons, 0x04 rupees, 0x08 bombs, 0x10 arrows,
      0x20 hearts, 0x40 alignment, 0x80 magic, 0x100 the minimap and its
      player heads: Map217), and whether weapons are on
      (off: only the first button and the alignment bar). }
    ShowStats: Integer;
    WeaponsOn: Boolean;
    { alignment points, 0 to 100 }
    AP: Integer;
    { Timings, in ms: connect to the first board (-1 until then), and
      each link warp from the request to the new board. }
    ConnectAtMs: Int64;
    LoginMs: Integer;
    WarpsSent: Integer;
    WarpTimes: array of Integer; { the first WarpCount entries are used }
    WarpCount: Integer;
    Handled, Ignored: array[0..255] of Integer;
    { Held direction keys for this tick: up, left, down, right. }
    Keys: array[0..3] of Boolean;
    { Game keys pressed this tick (down edges): A action (lift, throw,
      open), S attack (sword, throw), D item. }
    ActionKey, AttackKey, ItemKey: Boolean;
    { The map key (M) pressed this tick: opens or closes the big map. }
    MapKey: Boolean;
    { What the player is doing: ModeFree, ModeSword, ModeLift, ModeCarry. }
    Mode: Integer;
    { The lift table entry carried (0 bush, 1 sign, 2 pot, 3 stone,
      4 black stone), or -1. }
    CarryKind: Integer;
    Items: array of TFloorItem;
    Thrown: array of TThrownObject;
    Bombs: array of TBomb;
    Blasts: array of TBlast;
    { Reading a sign: its lines and the first line of the page shown. }
    Reading: Boolean;
    SignLines: array of string;
    SignLine: Integer;
    { The weapon list (2.05 keeps one, in arrival order) and the selected
      entry, shown beside the D button. }
    Weapons: array of TWeapon;
    Selected: Integer;
    Shots: array of TShot;
    { The item list window (Q); ItemListKey is its key's press this tick. }
    ItemListOpen, ItemListKey: Boolean;
    OnSwordHit: TSwordHitEvent;
    OnBombBlast: TBombBlastEvent;
    OnArrowHit: TArrowHitEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Log(const S: string);
    { Points pics1, arrays.dat and the image folders at an install. }
    procedure UseInstall(const Dir: string);
    { Draws P with the camera at (CamX, CamY) pixels; also used for the
      character on the start screen. }
    procedure DrawPlayer(P: TServerPlayer; CamX, CamY: Integer);
    procedure DrawNames(CamX, CamY: Integer);
    { The status display over the board: buttons, counts, hearts, bars. }
    procedure DrawStatus;
    { The built-in tile sheet and tile types (done by Create). }
    procedure UseBuiltins;
    function ConnectServer(const Host: string; Port: Word;
      const Account, Password: string): Boolean;
    { The walking routine for one direction key (one step). }
    procedure WalkStep(Dir: Integer);
    { One frame: network in, game step, network out, draw. }
    procedure Tick;
    procedure Draw;
    { Loads a level from disk for offline play; links then look for their
      levels next to it, then in the install. }
    function LoadLevelFile(const FileName: string): Boolean;
    { The folder the current level was read from ('' for a built-in one). }
    property LevelDir: string read FLevelDir;
    { The link under the player, or -1. }
    function LinkAt(PX, PY: Double): Integer;
    { Takes link I: online, asks the server for the level; offline, loads
      it. Returns False when the level cannot be had. }
    function FollowLink(I: Integer): Boolean;
    { One message from the server, as the client's dispatcher hands it on. }
    procedure Receive(Id: Integer; const Data: string);
    { The player's own wire sprite: the direction (2.17.1 sends the pose
      as the GANI prop). }
    function OwnSprite: Integer;
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
    { The S key: throws what is carried, or swings the sword and cuts. }
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
    { The 2 x 2 tiles of object I of table List at screen point X, Y. }
    procedure DrawObjectTiles(List, I, X, Y: Integer);
    { GS1 addtiledef IMAGE,PREFIX,TYPE: levels starting with PREFIX use
      IMAGE, of sheet type TYPE (0 the old tile order, 1 and 2 the new). }
    procedure AddTileDef(const Img, Prefix: string; Kind: Integer);
    { The sheet type of the level's tile definition: 0 for pics1. }
    function TileDefKind(const LevelName: string): Integer;
    procedure ReplaceAni(const OldName, NewName: string);
    { The player's gani after replaceani. }
    function OwnAniName: string;
    { The tile sheet for a level: the newest addtiledef whose prefix starts
      the name and whose image loads, else pics1. }
    function TileSheetFor(const LevelName: string): TGSurface;
    { The index of that tile definition in TileDefs, or -1. }
    function TileDefIndex(const LevelName: string): Integer;
    { A carried or thrown object (lift table entry Kind) at X, Y. }
    procedure DrawCarried(Kind, X, Y: Integer);
    { Not in hurt mode and not dead. }
    function Hurtable: Boolean;
    { The shared hurt routine: Hearts off (clamped to the maximum first),
      hurt mode with a five-tile knockback along (KX, KY), or death. }
    procedure HurtPlayer(Hearts, KX, KY: Double);
    { HurtPlayer with the knockback pointing away from (FromX, FromY). }
    procedure HurtFrom(Hearts, FromX, FromY: Double);
    { After death, on a direction key: hearts by AP, at the level's entry. }
    procedure Respawn;
    { The D key with the bomb: a bomb with a 60-tick fuse. }
    procedure LayBomb;
    procedure AddBlast(X, Y: Double; Reach, Kind: Integer; Mine: Boolean);
    { Adds a weapon unless the list has its name, and selects it. }
    procedure AddWeapon(const Name, Image: string; Item: Integer);
    { A built-in weapon by item number (7 bow, 8 bomb, 12 superbomb, 20 to
      23); other numbers are pickups and add nothing. }
    procedure AddDefaultWeapon(Item: Integer);
    procedure RemoveWeapon(const Name: string);
    { Selects the first entry from I on, wrapping, that is not hidden (an
      empty name or one starting with '-'). }
    procedure SelectWeapon(I: Integer);
    { The D key: uses the selected weapon. }
    procedure UseWeapon;
    procedure LayBombOf(Power: Integer);
    { Fires a shot of Kind the way the player faces. }
    procedure Shoot(Kind: Integer);
    procedure AddShot(X, Y: Double; Dir, Sprite, Kind: Integer; Mine: Boolean);
    procedure TickShots;
    procedure DrawShots(CamX, CamY: Integer);
    procedure DrawItemList;
    { The level sign whose 2 x 2 holds (PX, PY), or -1. }
    function SignAt(PX, PY: Double): Integer;
    { Opens the sign panel on Text (lines split at newlines). }
    procedure ReadSign(const Text: string);
    { The keys while reading: Up turns back a page, any other game key
      turns on, or ends reading on a page that is not full. }
    procedure SignKeys;
    procedure DrawSign(CamTop: Integer);
    property Others[I: Integer]: TServerPlayer read GetOther;
    property OtherCount: Integer read GetOtherCount;
  public
    { NPCs and their scripts (Npc217, NpcBridge217) }
    Npcs: TNpcManager;
    { baddies (Baddy217): from the level offline, from the server online }
    Baddies: TBaddyManager;
    { walls, chests and blocking NPCs at a point, in tiles }
    function PointBlocked(PX, PY: Double): Boolean;
    function IsOnline: Boolean;
    procedure SendPacket(Id: Integer; const Data: string);
    property Client: TAdventureClient read FClient;
    property LogLines: TStrings read FLog;
  end;

{ Fallback tile sheet when pics1 is not available: each tile gets a flat
  colour derived from its index, so a frame still shows the board layout. }
{ Wall-clock milliseconds, for login and warp timings. }
function NowMs: Int64;
const
  ModeFree = 0;
  ModeSword = 1;
  ModeLift = 2;
  ModeCarry = 3;
  ModeDead = 5;
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
procedure MakeIndexSheet(Sheet: TGSurface);

implementation

uses
  SysUtils, Math, GPeRes, GFont, GSound, Sound217, Map217, NpcBridge217;

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
        if FileExists(Cand) then
        begin
          Result := Cand;
          Exit;
        end;
      end;
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
  Key := 'img:' + LowerCase(Name);
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
  else if Kind = 'weapon' then F := FindFile(Name, ['levels/weapons/', 'levels/', ''])
  else F := FindFile(Name, ['', 'levels/', 'levels/images/']);
  { a gani attribute can name any player picture, and the 2.2-era install
    keeps many in levels/webgifs (the tutorial's hair, arms and legs) or in
    another kind's folder (its shield, as #P4) }
  if F = '' then
    F := FindFile(Name, ['levels/webgifs/', 'levels/images/', 'levels/shields/',
      'levels/swords/', 'levels/hats/', 'levels/heads/', 'levels/bodies/']);
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
  Key, F: string;
  I: Integer;
  A: TGraalAni;
begin
  Key := 'ani:' + LowerCase(Name);
  I := FNames.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGraalAni(FNames.Objects[I]);
    Exit;
  end;
  A := nil;
  { the install's ganis, through the asset folders (graal-assets/<version>
    and common), as the images are found }
  F := AssetPath('levels/ganis/' + Name + '.gani');
  if F = '' then F := AssetPath('ganis/' + Name + '.gani');
  if (F = '') and (Dir <> '') then
  begin
    F := IncludeTrailingPathDelimiter(Dir) + 'levels/ganis/' + Name + '.gani';
    if not FileExists(F) then
      F := IncludeTrailingPathDelimiter(Dir) + 'ganis/' + Name + '.gani';
  end;
  begin
    if (F <> '') and FileExists(F) then
    begin
      A := TGraalAni.Create;
      if not A.LoadFromFile(F) then FreeAndNil(A);
    end;
  end;
  if (A = nil) and BuiltinFile(Name + '.gani', F) then
  begin
    A := TGraalAni.Create;
    if not A.LoadFromString(F) then FreeAndNil(A);
  end;
  if A = nil then Missing.Add(Name + '.gani');
  FNames.AddObject(Key, A);
  Result := A;
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
  HeadImage := 'head0.gif';
  SwordImage := 'sword1.gif';
  ShieldImage := 'shield1.gif';
  Dir := DirDown;
  AniName := 'idle';
  FixedStep := -1;
end;

destructor TServerPlayer.Destroy;
begin
  BodyCache.Free;
  inherited Destroy;
end;

procedure TServerPlayer.SetAni(const Name: string; Frame: Integer);
begin
  if Name <> AniName then
  begin
    AniName := Name;
    AniStart := Frame;
  end;
end;

function TServerPlayer.ApplyProps(R: TGReader; Other: Boolean): string;
var
  P, V, I: Integer;
begin
  Result := '';
  while not R.Eof do
  begin
    P := R.ReadGChar;
    { the ids 2.17.1's parsers accept (version-profiles/
      plo-playerprops-layouts.tsv): its own stream takes ids up to 74 and
      stops at 50, 51 and 53. The other-player switch was not isolated;
      here it takes the same range, with 50 and 51 still read so a player
      can leave [inf]. }
    if P > 74 then Exit;
    if not Other and ((P = 50) or (P = 51) or (P = 53)) then Exit;
    case P of
      PLPROP_NICKNAME: Nickname := R.ReadGString;
      PLPROP_MAXPOWER: MaxPower := R.ReadGChar;
      PLPROP_CURPOWER: Power := R.ReadGChar;
      PLPROP_RUPEESCOUNT: Rupees := R.ReadGInt3;
      PLPROP_ARROWSCOUNT: Arrows := R.ReadGChar;
      PLPROP_BOMBSCOUNT: Bombs := R.ReadGChar;
      PLPROP_GLOVEPOWER: GlovePower := R.ReadGChar;
      PLPROP_BOMBPOWER: BombPower := R.ReadGChar;
      PLPROP_SWORDPOWER:
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
      PLPROP_SHIELDPOWER:
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
      PLPROP_GANI: { 2.1+: the gani name as a string }
        begin
          SetAni(R.ReadGString, NowFrame);
          FixedStep := -1;
        end;
      PLPROP_HEADGIF:
        begin
          V := R.ReadGChar;
          if V >= 100 then
            HeadImage := R.ReadChars(V - 100)
          else
            HeadImage := 'head' + IntToStr(V) + '.gif';
        end;
      PLPROP_CURCHAT: Chat := R.ReadGString;
      PLPROP_COLORS: for I := 0 to 4 do Colors[I] := R.ReadGChar;
      PLPROP_ID: Id := R.ReadGShort;
      PLPROP_X: X := R.ReadGChar / 2;
      PLPROP_Y: Y := R.ReadGChar / 2;
      PLPROP_SPRITE:
        begin
          Sprite := R.ReadGChar;
          { 2.17.1 sends the direction alone here; the pose travels as the
            gani (lab capture: GANI=walk, X, SPRITE=3) }
          Dir := Sprite mod 4;
        end;
      PLPROP_STATUS: Status := R.ReadGChar;
      PLPROP_CARRYSPRITE, PLPROP_HORSEBUSHES, PLPROP_EFFECTCOLORS,
      PLPROP_MAGICPOINTS, PLPROP_ALIGNMENT, PLPROP_ADDITFLAGS,
      PLPROP_GMAPLEVELX, PLPROP_GMAPLEVELY, PLPROP_Z, PLPROP_PSTATUSMSG:
        R.ReadGChar;
      PLPROP_JOINLEAVELVL: if R.ReadGChar = 0 then Gone := True;
      PLPROP_CURLEVEL: Level := R.ReadGString;
      PLPROP_GATTRIB1..PLPROP_GATTRIB5:
        Attr[P - PLPROP_GATTRIB1 + 1] := R.ReadGString;
      PLPROP_ACCOUNTNAME: Account := R.ReadGString;
      PLPROP_BODYIMG: BodyImage := R.ReadGString;
      PLPROP_GATTRIB6..PLPROP_GATTRIB9:
        Attr[P - PLPROP_GATTRIB6 + 6] := R.ReadGString;
      PLPROP_GATTRIB10..PLPROP_GATTRIB30:
        Attr[P - PLPROP_GATTRIB10 + 10] := R.ReadGString;
      PLPROP_HORSEGIF, PLPROP_PLANGUAGE:
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
          if not R.Eof then R.ReadByte; { 2.05 skips one byte after it [inf for 2.17] }
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
  FClient := TAdventureClient.Create;
  FClient.OnMessage := HandleMessage;
  FClient.OnLog := ClientLog;
  Level := TAdventureLevel.Create;
  Player := TServerPlayer.Create;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Sheet := TGSurface.Create(0, 0);
  Tiles := Sheet;
  TileDefs := TStringList.Create;
  AniReplace := TStringList.Create;
  Arrays := TGArrays.Create;
  Assets := TAssets.Create;
  FOthers := TList.Create;
  { a new 2.05 account: 3 of 3 hearts, no rupees, 10 bombs, 5 arrows }
  Player.MaxPower := 3;
  Player.Power := 6;      { half hearts, as PLPROP_CURPOWER }
  Player.Bombs := 10;
  Player.Arrows := 5;
  Player.GlovePower := 1;
  Player.SwordPower := 1;
  CarryKind := -1;
  AP := 50;
  ShowStats := $1FF;
  WeaponsOn := True;
  { offline the player has the client's own bomb; online the server sends
    the list }
  Selected := -1;
  AddDefaultWeapon(8);
  UseBuiltins;
  Npcs := CreateNpcManager(Self);
  Baddies := CreateBaddyManager(Self);
end;

function TAdventure.IsOnline: Boolean;
begin
  Result := FClient.Connected;
end;

procedure TAdventure.SendPacket(Id: Integer; const Data: string);
begin
  if FClient.Connected then FClient.SendPacket(Id, Data);
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
  FreeAndNil(Baddies);
  FreeAndNil(Npcs);
  FClient.Free;
  Level.Free;
  Player.Free;
  Screen.Free;
  Sheet.Free;
  TileDefs.Free;
  AniReplace.Free;
  Arrays.Free;
  Assets.Free;
  for I := 0 to FOthers.Count - 1 do TServerPlayer(FOthers[I]).Free;
  FOthers.Free;
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

procedure TAdventure.UseInstall(const Dir: string);
var
  P: string;
begin
  Assets.Dir := Dir;
  { the folder itself, then graal-assets/<version>/ and graal-assets/common/ }
  SetAssetRoots(Dir, ClientAssetFolders);
  if AssetsFolder <> '' then Log('assets: ' + AssetsFolder);
  { the install's tile sheet and tile types replace the built-in ones, but
    not a sheet given with --sheet }
  if (Sheet.Width = 0) or SheetBuiltin then
  begin
    P := AssetPath('pics1.png');
    if P = '' then P := AssetPath('pics1.gif');
    if (P <> '') and LoadImageFile(P, Sheet) then SheetBuiltin := False;
  end;
  P := AssetPath('arrays.dat');
  if (P <> '') and Arrays.LoadFromFile(P) then
    Log('arrays.dat loaded')
  else
    Log('arrays.dat not found in ' + Dir + ': using the built-in tile types');
end;

function TAdventure.ConnectServer(const Host: string; Port: Word;
  const Account, Password: string): Boolean;
begin
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

{ ---- walking (client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md) ---- }

function TileOf(V: Double): Integer;
begin
  Result := Floor(V + 0.0001);
end;

{ The wall test of the new tile order (sheet types 1 and 2), from the tile
  id alone (client-internals/decomp-findings-2026-10-28-b/01-tile-type-tests.md). }
function NewSheetWall(Tile: Integer): Boolean;
var
  Row, Col: Integer;
begin
  Row := Tile div 16;
  Col := Tile mod 16;
  Result := (Tile = 32) or
    (((Row = 26) or (Row = 27)) and (Col >= 2)) or
    ((Row >= 30) and (Row <= 47)) or ((Row >= 84) and (Row <= 95)) or
    ((Row >= 116) and (Row <= 127)) or
    ((Row >= 128) and Odd(Row div 16));
end;

function TAdventure.PointBlocked(PX, PY: Double): Boolean;
var
  TX, TY, I: Integer;
begin
  Result := Npcs.PointBlocked(PX, PY);
  if Result then Exit;
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
  { outside 0..63 is a gmap neighbour or a fixed tile; neither is modelled
    yet, so the edge is open and level links can be reached }
  if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
  case TileDefKind(Level.Name) of
    1, 2: Result := NewSheetWall(Level.Tile(TX, TY));
    5: Result := False; { no board rule: only NPC shapes have types }
  else
    Result := not Arrays.TilePassable(Level.Tile(TX, TY));
  end;
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

{ ---- actions: sword cut, lift and throw, chests, floor items
  (client-internals/decomp-findings-2026-10-25-l/03-cut-lift-chest.md,
  board-respawn.md, item-drops.md, carry-hide-and-glove.md) ---- }

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
  if Mode = ModeCarry then
  begin
    Throw;
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
  { NPCs and baddies hit by the blade: a 2 x 2 box centred on the tip }
  if Assigned(OnSwordHit) then OnSwordHit(PX - 1, PY - 1, 2, 2, Player.SwordPower);
end;

procedure TAdventure.Action;
var
  A: TGraalAni;
  PX, PY: Double;
  OX, OY, E, I: Integer;
begin
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
      PlaySound('chest.wav');
      PutObject(Level.Chests[I].X, Level.Chests[I].Y, 14, 0, False);
      { the item shows over the chest (a life below 100: not taken) and is
        given at once }
      if (Level.Chests[I].Item >= 0) and (Level.Chests[I].Item <= High(ItemNames)) then
      begin
        AddItem(Level.Chests[I].X, Level.Chests[I].Y - 1, Level.Chests[I].Item, 24);
        GiveItem(Level.Chests[I].Item);
      end;
      if (Level.Chests[I].Sign >= 0) and (Level.Chests[I].Sign <= High(Level.Signs)) then
        ReadSign(Level.Signs[Level.Chests[I].Sign].Text);
      if FClient.Connected then
        FClient.SendPacket(PLI_OPENCHEST, GChar(Level.Chests[I].X) + GChar(Level.Chests[I].Y));
      Exit;
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
      PlaySound('extra.wav');
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
      PlaySoundAt('crush.wav', Thrown[I].X + 1, Thrown[I].Y + 1);
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
  if (Mode = ModeSword) or (Mode = ModeLift) or (Mode = ModeCarry) then
  begin
    { what happens to a carried object on a hit was not read: it is lost }
    CarryKind := -1;
    Mode := ModeFree;
  end;
  if Player.Power <= 0 then
  begin
    Player.Power := 0;
    Mode := ModeDead;
    FHurtCount := 0;
    PlaySound('dead.wav');
    Player.SetAni('dead', Frame);
  end
  else
    Player.SetAni('hurt', Frame);
  if FClient.Connected then
    FClient.SendPacket(PLI_PLAYERPROPS, GChar(PLPROP_CURPOWER) + GChar(Player.Power));
end;

procedure TAdventure.HurtFrom(Hearts, FromX, FromY: Double);
begin
  HurtPlayer(Hearts, Player.X + 1.5 - FromX, Player.Y + 2 - FromY);
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
  attacker in the sword gani (2.05 looks at swing sprites 6 to 10; 2.17.1
  sends the pose as the gani, so the gani name stands in for them [inf]), the victim 0 to 4 tiles ahead and
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
    if LowerCase(P.AniName) <> 'sword' then Continue;
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

procedure TAdventure.LayBomb;
begin
  LayBombOf(1);
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
  PlaySound('put.wav');
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
  PlaySoundAt('bomb.wav', X + 1, Y + 1);
  if Assigned(OnBombBlast) then OnBombBlast(X + 1, Y + 1, Reach);
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
      begin
        if Assigned(OnArrowHit) and OnArrowHit(Sh.X + W / 2, Sh.Y + H / 2, 1 + Ord(Sh.Kind in [1, 3])) then
        begin
          Gone := True;
          Hit := True;
        end;
      end
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

{ ---- signs (sign-panel.md) ---- }

const
  { a character's glyph is its place in this string; '#' places are glyphs
    with no plain character }
  GlyphOrder = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
    '!?-.,#>()#####"####'':/~&### <####;';

function GlyphOf(C: Char): Integer;
begin
  if C = '#' then Result := -1 else Result := Pos(C, GlyphOrder) - 1;
end;

{ The advance of a glyph. The client keeps a table of half widths; only I
  (6), space (8) and most letters (12) are noted, so the other narrow ones
  here are a guess. }
function GlyphAdvance(C: Char): Integer;
begin
  case C of
    ' ': Result := 8;
    'I', 'i', 'l', 'j', '!', '.', ',', ':', ';', '''': Result := 6;
  else
    Result := 12;
  end;
end;

{ The picture glyph for '#' and a letter, or -1. #A, #B, #X, #Y and the
  arrows are as read; which of 71 to 75 and 87 the other six take is a
  guess. }
function ButtonGlyph(C: Char): Integer;
begin
  case C of
    'A': Result := 91;
    'B': Result := 92;
    'X': Result := 93;
    'Y': Result := 94;
    'u': Result := 77;
    'd': Result := 78;
    'l': Result := 79;
    'r': Result := 80;
    'h': Result := 71;
    'x': Result := 72;
    'y': Result := 73;
    'z': Result := 74;
    '4': Result := 75;
    '.': Result := 87;
  else
    Result := -1;
  end;
end;

function TAdventure.SignAt(PX, PY: Double): Integer;
var
  I, TX, TY: Integer;
begin
  Result := -1;
  TX := Floor(PX);
  TY := Floor(PY);
  for I := 0 to High(Level.Signs) do
    if (TX >= Level.Signs[I].X) and (TX <= Level.Signs[I].X + 1) and
      (TY >= Level.Signs[I].Y) and (TY <= Level.Signs[I].Y + 1) then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TAdventure.ReadSign(const Text: string);
var
  I, St: Integer;
  T: string;
begin
  SetLength(SignLines, 0);
  T := Text;
  while (T <> '') and ((T[Length(T)] = #10) or (T[Length(T)] = #13)) do
    SetLength(T, Length(T) - 1);
  St := 1;
  for I := 1 to Length(T) + 1 do
    if (I > Length(T)) or (T[I] = #10) then
    begin
      SetLength(SignLines, Length(SignLines) + 1);
      SignLines[High(SignLines)] := Copy(T, St, I - St);
      if (SignLines[High(SignLines)] <> '') and
        (SignLines[High(SignLines)][Length(SignLines[High(SignLines)])] = #13) then
        SetLength(SignLines[High(SignLines)], Length(SignLines[High(SignLines)]) - 1);
      St := I + 1;
    end;
  SignLine := 0;
  Reading := True;
  { the key that opened the sign does nothing until it is let go }
  FSignWasDown := True;
end;

procedure TAdventure.SignKeys;
var
  Down: Boolean;
  D: Integer;
begin
  Down := Keys[0] or Keys[1] or Keys[2] or Keys[3] or ActionKey or AttackKey or ItemKey;
  if Down and not FSignWasDown then
  begin
    if Keys[DirUp] then
    begin
      if SignLine > 0 then Dec(SignLine, 3);
    end
    else if Length(SignLines) < SignLine + 3 then
      Reading := False
    else
      Inc(SignLine, 3);
  end;
  FSignWasDown := Down;
  for D := 0 to 3 do Keys[D] := False;
  ActionKey := False;
  AttackKey := False;
  ItemKey := False;
end;

procedure TAdventure.DrawSign(CamTop: Integer);
const
  CellsW = 24;
  CellsH = 9;
var
  L: TGSurface;
  X, Y, W, H, I, K, CX, G: Integer;
  S: string;
  Fill: Cardinal;

  procedure Glyph(N, DX, DY: Integer);
  begin
    Screen.Blit(L, (N mod 16) * 16, (N div 16) * 32, 16, 32, DX, DY);
  end;

begin
  L := Assets.Image('letters.png', '');
  W := CellsW * 16;
  H := CellsH * 16;
  X := (ScreenW - W) div 2;
  { low on the view, or high when the player is far down it }
  { (on the 640 x 480 view: y 256, or 128 past 14 tiles down) }
  if Player.Y - CamTop / TileSize > 14 then Y := 128 else Y := 256;
  if L = nil then
  begin
    Screen.FillRect(X, Y, W, H, $FF000000);
    Screen.FillRect(X + 2, Y + 2, W - 4, H - 4, $FFFFE7A5);
  end
  else
  begin
    for I := 0 to CellsW - 1 do
    begin
      Glyph(100, X + I * 16, Y);
      Glyph(101, X + I * 16, Y + H - 32);
    end;
    I := 0;
    while I * 32 < H do
    begin
      Glyph(102, X, Y + I * 32);
      Glyph(103, X + W - 16, Y + I * 32);
      Inc(I);
    end;
    Glyph(96, X, Y);
    Glyph(97, X + W - 16, Y);
    Glyph(98, X, Y + H - 32);
    Glyph(99, X + W - 16, Y + H - 32);
    { the two fills, from the colours at (254, 223) and (255, 223), each
      skipped when it is the sheet's clear colour }
    Fill := L.GetPixel(254, 223);
    if Fill shr 24 <> 0 then Screen.FillRect(X + 16, Y + 24, W - 32, H - 48, Fill);
    Fill := L.GetPixel(255, 223);
    if Fill shr 24 <> 0 then Screen.FillRect(X + 24, Y + 32, W - 48, H - 64, Fill);
  end;
  { three lines a page, 32 pixels apart }
  for K := 0 to 2 do
  begin
    if SignLine + K > High(SignLines) then Break;
    S := SignLines[SignLine + K];
    CX := X + 16;
    I := 1;
    while I <= Length(S) do
    begin
      if (S[I] = '#') and (I < Length(S)) then
      begin
        Inc(I);
        if S[I] = 'i' then
        begin
          Inc(I, 2); { #i and a character: an image from the level's list, not drawn }
          Continue;
        end;
        G := ButtonGlyph(S[I]);
        if G < 0 then G := 86;
        if L <> nil then Glyph(G, CX, Y + 16 + K * 32);
        Inc(CX, 16);
      end
      else
      begin
        G := GlyphOf(S[I]);
        if (G >= 0) and (L <> nil) then
        begin
          Glyph(G, CX, Y + 16 + K * 32);
          Inc(CX, GlyphAdvance(S[I]));
        end
        else
        begin
          { outside the glyph order: the system font, in the colour at (253, 223) }
          if L <> nil then Fill := L.GetPixel(253, 223) else Fill := $FF000000;
          DrawText(Screen, CX, Y + 16 + K * 32 + 8, S[I], Fill or $FF000000, 2);
          Inc(CX, 12);
        end;
      end;
      Inc(I);
    end;
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

{ ---- level links ---- }

{ An offline tutorial level the real program carried in its resources
  (offlinetutorial_a-1.graal .. offlinetutorial_c-3.graal as RCDATA
  TUTORIALA1 .. TUTORIALC3), linked into this one (src/res/); False for
  other names. }
function ExeTutorial(const Name: string; out Data: string): Boolean;
var
  N: string;
begin
  Result := False;
  Data := '';
  N := LowerCase(ExtractFileName(Name));
  if (Length(N) <> 25) or (Copy(N, 1, 16) <> 'offlinetutorial_') or
    (Copy(N, 20, 6) <> '.graal') or (N[18] <> '-') or not (N[17] in ['a'..'c']) or
    not (N[19] in ['1'..'3']) then Exit;
  Result := OwnResource('TUTORIAL' + UpperCase(N[17]) + N[19], Data) and
    (Copy(Data, 1, 3) = 'GR-');
end;

function TAdventure.LoadLevelFile(const FileName: string): Boolean;
var
  D: string;
begin
  SetLength(Items, 0);
  SetLength(Thrown, 0);
  if not FileExists(FileName) and ExeTutorial(FileName, D) then
  begin
    { the real program's own tutorial level: links from it look in the
      install, then here }
    Result := Level.LoadFromString(D);
    Level.Name := ExtractFileName(FileName);
    if Result then FLevelDir := '';
    if Result then Npcs.LoadLevel(Level);
    if Result then Baddies.LoadLevel(Level);
    Exit;
  end;
  if not FileExists(FileName) and BuiltinFile(ExtractFileName(FileName), D) and
    (LowerCase(ExtractFileExt(FileName)) <> '.png') then
  begin
    { a built-in level: links from it look in the install, then here }
    Result := Level.LoadFromString(D);
    Level.Name := ExtractFileName(FileName);
    if Result then FLevelDir := '';
    if Result then Npcs.LoadLevel(Level);
    if Result then Baddies.LoadLevel(Level);
    Exit;
  end;
  Result := Level.LoadFromFile(FileName);
  if Result then FLevelDir := ExtractFilePath(FileName);
  if Result then Npcs.LoadLevel(Level);
  if Result then Baddies.LoadLevel(Level);
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

{ An arrival is a number, or playerx / playery (or a negative number) for
  "keep the player's coordinate". }
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
begin
  Result := False;
  if (I < 0) or (I > High(Level.Links)) then Exit;
  L := Level.Links[I];
  NX := Arrival(L.NewX, Player.X);
  NY := Arrival(L.NewY, Player.Y);
  if FClient.Connected then
  begin
    if FWarpPending then Exit;
    { c x*2, c y*2, then the level name; the server answers with the
      warp, the level name and the board }
    FClient.SendPacket(PLI_LEVELWARP, GChar(Round(NX * 2)) + GChar(Round(NY * 2)) + L.Dest);
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
  if (FLevelDir <> '') and FileExists(FLevelDir + L.Dest) then
    Path := FLevelDir + L.Dest
  else if AssetPath('levels/' + L.Dest) <> '' then
    Path := AssetPath('levels/' + L.Dest)
  else if AssetPath(L.Dest) <> '' then
    Path := AssetPath(L.Dest);
  if Path = '' then Path := L.Dest; { LoadLevelFile tries the built-in ones }
  if not LoadLevelFile(Path) then
  begin
    Log('link to ' + L.Dest + ': ' + Level.LastError);
    Exit;
  end;
  Player.X := NX;
  Player.Y := NY;
  Player.Level := Level.Name;
  Log(Format('link to %s at %.1f,%.1f', [Level.Name, NX, NY]));
  Result := True;
end;

{ ---- props to the server ---- }

function TAdventure.OwnSprite: Integer;
begin
  { 2.17.1 sends the direction alone (lab capture: SPRITE=3 while the gani
    is walk); the pose goes as the GANI prop }
  Result := Player.Dir and 3;
end;

procedure TAdventure.SendInitialProps;
begin
  { 2.17.1 sends props 0, 11, 13, 18, 31, 33 and 52 together at session
    start (lab capture of the real client) }
  FClient.SendPacket(PLI_PLAYERPROPS,
    GChar(PLPROP_NICKNAME) + GString(Player.Nickname) +
    GChar(PLPROP_HEADGIF) + GChar(Length(Player.HeadImage) + 100) + Player.HeadImage +
    GChar(PLPROP_COLORS) + GChar(Player.Colors[0]) + GChar(Player.Colors[1]) +
      GChar(Player.Colors[2]) + GChar(Player.Colors[3]) + GChar(Player.Colors[4]) +
    GChar(PLPROP_STATUS) + GChar(Player.Status) +
    GChar(PLPROP_UDPPORT) + GInt3(0) +   { no UDP peer channel yet }
    GChar(PLPROP_ADDITFLAGS) + GChar(0) +
    GChar(PLPROP_PLANGUAGE) + GString('English'));
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentSprite := OwnSprite;
  FSentAni := OwnAniName;
  FPropsSent := True;
end;

procedure TAdventure.SendMovedProps;
var
  S: string;
  Spr: Integer;
begin
  { a diff of the changed props, sent at most every other tick (100 ms) }
  if not FPropsSent or (Frame mod 2 <> 0) then Exit;
  { in the order the real client sends them: GANI, X, Y, SPRITE }
  S := '';
  if OwnAniName <> FSentAni then
    S := S + GChar(PLPROP_GANI) + GString(OwnAniName);
  if Player.X <> FSentX then S := S + GChar(PLPROP_X) + GChar(Round(Player.X * 2));
  if Player.Y <> FSentY then S := S + GChar(PLPROP_Y) + GChar(Round(Player.Y * 2));
  Spr := OwnSprite;
  if Spr <> FSentSprite then S := S + GChar(PLPROP_SPRITE) + GChar(Spr);
  if S = '' then Exit;
  FClient.SendPacket(PLI_PLAYERPROPS, S);
  FSentAni := OwnAniName;
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentSprite := Spr;
end;

{ ---- messages from the server ---- }

procedure TAdventure.Receive(Id: Integer; const Data: string);
begin
  HandleMessage(Id, Data);
end;

procedure TAdventure.HandleMessage(Id: Integer; const Data: string);
var
  R: TGReader;
  S: string;
  V: Integer;
  L: TLevelLink;
  SG: TLevelSign;
  CH: TLevelChest;
  W: TStringList;
  OP: TServerPlayer;
  I, J, BX, BY, BW, BH: Integer;
  FX, FY: Double;
begin
  if Npcs.Receive(Id, Data) or Baddies.Receive(Id, Data) then
  begin
    if (Id >= 0) and (Id <= 255) then Inc(Handled[Id]);
    Exit;
  end;
  R := TGReader.Create(Data);
  try
    case Id of
      PLO_PLAYERPROPS:
        begin
          Player.NowFrame := Frame;
          S := Player.ApplyProps(R, False);
          Log('PLAYERPROPS ' + S);
          if not LoggedIn then
          begin
            LoggedIn := True;
            SendInitialProps;
          end;
        end;
      PLO_OTHERPLPROPS: { s id + prop stream; an unknown id adds the player }
        begin
          if Length(Data) < 2 then Exit;
          V := R.ReadGShort;
          OP := FindOther(V, True);
          OP.NowFrame := Frame;
          OP.ApplyProps(R, True);
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
          Log(Format('PLAYERWARP %s %.1f,%.1f', [Player.Level, Player.X, Player.Y]));
        end;
      PLO_PLAYERWARP2: { c x*2, c y*2, c z, c gmap x, c gmap y, level }
        begin
          { gmaps are not drawn yet: the level name (a .gmap) is kept and
            the position taken as it comes }
          Player.X := R.ReadGChar / 2;
          Player.Y := R.ReadGChar / 2;
          R.ReadGChar;
          R.ReadGChar;
          R.ReadGChar;
          Player.Level := R.ReadRest;
          FWarpPending := False;
          FSentX := Player.X;
          FSentY := Player.Y;
          Log(Format('PLAYERWARP2 %s %.1f,%.1f', [Player.Level, Player.X, Player.Y]));
        end;
      PLO_LEVELNAME:
        begin
          Npcs.Clear;
          Baddies.Clear;
          while FOthers.Count > 0 do RemoveOther(Others[0].Id);
          SetLength(Items, 0);
          SetLength(Thrown, 0);
          if FWarpPending and (Data = FWarpLevel) then
          begin
            { the server sends no PLAYERWARP for a link: the client
              completes its own pending warp when the level arrives }
            Player.X := FWarpX;
            Player.Y := FWarpY;
            Player.Level := Data;
          end;
          FWarpPending := False;
          Level.Clear;
          Level.Name := Data;
          BoardLoaded := False;
          Log('LEVELNAME ' + Data);
        end;
      PLO_BOARDPACKET:
        begin
          BoardLoaded := Level.LoadBoardPacket(Data);
          if BoardLoaded and LoggedIn and (LoginMs < 0) and (ConnectAtMs > 0) then
            LoginMs := ClampMs(NowMs - ConnectAtMs);
          if BoardLoaded and (FWarpTimed <> '') and (Level.Name = FWarpTimed) then
          begin
            if WarpCount = Length(WarpTimes) then
              SetLength(WarpTimes, 2 * WarpCount + 16);
            WarpTimes[WarpCount] := ClampMs(NowMs - FWarpT0);
            Inc(WarpCount);
            FWarpTimed := '';
          end;
          if BoardLoaded then
            Log('BOARDPACKET ' + Level.Name + ' loaded')
          else
            Log('BOARDPACKET rejected: ' + Level.LastError);
        end;
      PLO_LEVELLINK: { "dest x y w h newx newy" as text }
        begin
          W := TStringList.Create;
          try
            SplitSpaces(Data, W);
            if W.Count >= 7 then
            begin
              L.Dest := W[0];
              L.X := StrToIntDef(W[1], 0);
              L.Y := StrToIntDef(W[2], 0);
              L.W := StrToIntDef(W[3], 0);
              L.H := StrToIntDef(W[4], 0);
              L.NewX := W[5];
              L.NewY := W[6];
              SetLength(Level.Links, Length(Level.Links) + 1);
              Level.Links[High(Level.Links)] := L;
            end;
          finally
            W.Free;
          end;
        end;
      PLO_LEVELSIGN:
        begin
          SG.X := R.ReadGChar;
          SG.Y := R.ReadGChar;
          SG.Text := DecodeSignText(R.ReadRest);
          SetLength(Level.Signs, Length(Level.Signs) + 1);
          Level.Signs[High(Level.Signs)] := SG;
        end;
      PLO_LEVELCHEST: { c opened, c x, c y; if not opened, c item, c sign }
        begin
          if Length(Data) < 3 then Exit;
          CH.Opened := R.ReadGChar <> 0;
          CH.X := R.ReadGChar;
          CH.Y := R.ReadGChar;
          CH.Item := -1;
          CH.Sign := -1;
          if not CH.Opened then
          begin
            if Length(Data) < 5 then Exit;
            CH.Item := R.ReadGChar;
            CH.Sign := R.ReadGChar;
          end;
          { the server's answer to an open, or a chest already opened }
          V := -1;
          for I := 0 to High(Level.Chests) do
            if (Level.Chests[I].X = CH.X) and (Level.Chests[I].Y = CH.Y) then V := I;
          if V < 0 then
          begin
            SetLength(Level.Chests, Length(Level.Chests) + 1);
            V := High(Level.Chests);
            Level.Chests[V] := CH;
          end
          else if CH.Opened then
            Level.Chests[V].Opened := True;
        end;
      PLO_BOARDMODIFY: { c x, c y, c w, c h, then w x h s tiles, row-major }
        begin
          if Length(Data) < 4 then Exit;
          BX := R.ReadGChar;
          BY := R.ReadGChar;
          BW := R.ReadGChar;
          BH := R.ReadGChar;
          if Length(Data) < 4 + 2 * BW * BH then Exit;
          for J := 0 to BH - 1 do
            for I := 0 to BW - 1 do
            begin
              V := R.ReadGShort;
              if (BX + I >= 0) and (BX + I < BoardW) and (BY + J >= 0) and (BY + J < BoardH) then
                Level.Tiles[BX + I + (BY + J) * BoardW] := V and 4095;
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
      PLO_TOALL: Log('TOALL ' + Data);
      PLO_SETACTIVELEVEL: Log('SETACTIVELEVEL ' + Data);
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
      PLO_LEVELMODTIME, PLO_ISLEADER, PLO_UNKNOWN168,
      PLO_STAFFGUILDS, PLO_HASNPCSERVER, PLO_FILEUPTODATE, PLO_FILESENDFAILED,
      PLO_LARGEFILESTART, PLO_LARGEFILEEND, PLO_UPGRADEURL..PLO_BOARDHEIGHTS:
        ; { accepted; their effects belong to later stages }
    else
      if (Id >= 0) and (Id <= 255) then Inc(Ignored[Id]);
      Exit;
    end;
    if (Id >= 0) and (Id <= 255) then Inc(Handled[Id]);
  finally
    R.Free;
  end;
end;

{ ---- the frame ---- }

{ How far ahead of the body's centre the client tests for a link. Measured
  against the real 2.05 (2.17.1 is assumed the same until measured): the point lies 1 to 1.5 tiles ahead (it moves in
  half tiles, so each test is a 0.5 tile range), and across the walk it
  stays on the centre line, so a 1x1 link off that line is walked past.
  1.25 falls inside every measured range. Diagonal walking was not
  measured; here the two offsets add. }
const
  LinkAhead = 1.25;

procedure TAdventure.Tick;
var
  D: Integer;
  Moved: Boolean;
  AX, AY: Double;
begin
  Inc(Frame);
  if FClient.Connected then
  begin
    FClient.Poll;
    if not FClient.Connected then
      Log('link closed: ' + FClient.LastError);
  end;
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
  { the big map, when open, takes the keys (Map217) }
  MapTick(Self);
  { reading a sign is its own input state: nothing walks or acts }
  if Reading then SignKeys
  else FSignWasDown := False;
  { the item list (Q) takes the keys while it is open }
  if ItemListOpen then ItemListKeys
  else if ItemListKey and (Mode = ModeFree) and not Reading then
  begin
    ItemListOpen := True;
    FListWasDown := True;
  end;
  ItemListKey := False;
  { the game keys first: a swing or a lift holds the player still }
  if AttackKey then Attack;
  if ActionKey then Action;
  if ItemKey then UseWeapon;
  AttackKey := False;
  ActionKey := False;
  ItemKey := False;
  if ((Mode = ModeSword) or (Mode = ModeLift)) and (Frame >= FModeUntil) then
    if Mode = ModeLift then Mode := ModeCarry else Mode := ModeFree;
  { keys run in the order up, left, down, right, each from where the
    earlier ones left the player }
  Moved := False;
  AX := 0;
  AY := 0;
  for D := 0 to 3 do
    if Keys[D] and ((Mode = ModeFree) or (Mode = ModeCarry)) and (FHurtCount < 35) then
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
  end;
  TickItems;
  TickShots;
  TickCombat;
  { NPCs: pushing into one, walking over one, then timeouts }
  for D := 0 to 3 do
    if Keys[D] and ((Mode = ModeFree) or (Mode = ModeCarry)) then
      Npcs.PlayerPush(D, Player.X, Player.Y);
  if Moved then Npcs.PlayerMoved(Player.X, Player.Y);
  Npcs.Tick;
  Baddies.Tick;
  { links are tested on the player's own walk, at one point: the body's
    centre pushed ahead in the walking direction (measured on the real
    client, see LinkAhead) }
  if Moved then FollowLink(LinkAt(Player.X + 1.5 + AX, Player.Y + 2 + AY));
  { walking up against a sign opens it (the probe over the sign's 2 x 2) }
  if Moved and Keys[DirUp] and (Mode = ModeFree) and not Reading then
  begin
    ProbePoint(AX, AY);
    D := SignAt(Player.X + 1.5, AY);
    if (D >= 0) and ((Player.Dir and 3) = DirUp) then ReadSign(Level.Signs[D].Text);
  end;
  SendMovedProps;
  FClient.Flush;
  TickSounds(Self);
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

{ The names under characters: an NPC that shows a character with a #n
  name, and the other players. The player's own is not drawn (2.05 shows
  none offline). White on a blue shadow, as 2.05 draws them; the font is
  the built-in one. }
procedure TAdventure.DrawNames(CamX, CamY: Integer);

  procedure One(const Name: string; X, Y: Double);
  var
    TX, TY: Integer;
  begin
    if Name = '' then Exit;
    TX := Round(X * TileSize) - CamX + 24 - TextWidth(Name, 2) div 2;
    TY := Round(Y * TileSize) - CamY + 44;
    DrawText(Screen, TX + 1, TY + 1, Name, $FF0000FF, 2);
    DrawText(Screen, TX, TY, Name, $FFFFFFFF, 2);
  end;

var
  I: Integer;
  N: TNpc;
begin
  for I := 0 to Npcs.Count - 1 do
  begin
    N := Npcs.Npc(I);
    if N.Gone or not N.Visible or not N.Character then Continue;
    One(N.Nickname, N.X, N.Y);
  end;
  for I := 0 to FOthers.Count - 1 do
    One(Others[I].Nickname, Others[I].X, Others[I].Y);
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
  BX := Round(P.X * TileSize) - CamX;
  BY := Round(P.Y * TileSize) - CamY;
  if P = Player then A := Assets.Ani(OwnAniName) else A := Assets.Ani(P.AniName);
  if (A = nil) and (Assets.Ani('idle') <> nil) then Exit; { not downloaded: not drawn }
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
  if St > High(A.Steps) then Exit;
  Parts := A.Steps[St].Dirs[P.Dir and 3];
  for I := 0 to High(Parts) do
  begin
    if Parts[I].Sprite = ParamSprite - 1 then
    begin
      { PARAM1 of the lift and carry ganis: the carried object, drawn with
        its carry sprite from the sprite table (bush 261, sign 267, pot
        265, stone 263, black stone 239: carry-hide-and-glove.md), or from
        its board tiles when there is no table }
      if (P = Player) and (CarryKind >= 0) then
        DrawCarried(CarryKind, BX + Parts[I].X, BY + Parts[I].Y);
      Continue;
    end;
    if not A.FindSprite(Parts[I].Sprite, Spr) then Continue;
    SheetName := UpperCase(Spr.Sheet);
    if SheetName = 'SPRITES' then Img := Assets.Image('sprites.png', '')
    else if SheetName = 'HEAD' then
    begin
      Img := Assets.Image(P.HeadImage, 'head');
      { a short head picture (2.05's are 560 high) has no row for the
        later poses: the plain head of that direction stands in }
      if (Img <> nil) and (Spr.Y + Spr.H > Img.Height) then
      begin
        Spr.X := 0;
        Spr.Y := (P.Dir and 3) * 32;
      end;
    end
    else if SheetName = 'PARAM1' then Img := Assets.Image(P.SwordImage, 'sword')
    else if SheetName = 'BODY' then Img := BodyFor(P)
    else if SheetName = 'SWORD' then Img := Assets.Image(P.SwordImage, 'sword')
    else if SheetName = 'SHIELD' then Img := Assets.Image(P.ShieldImage, 'shield')
    else if SheetName = 'PICS' then Img := Tiles
    else if Copy(SheetName, 1, 4) = 'ATTR' then
    begin
      K := StrToIntDef(Copy(SheetName, 5, 2), 0);
      AttrName := '';
      if (K >= 1) and (K <= 30) then
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

procedure TAdventure.DrawObjectTiles(List, I, X, Y: Integer);
var
  C, R, T: Integer;
begin
  for C := 0 to 1 do
    for R := 0 to 1 do
    begin
      T := Arrays.ObjectTile(List, I, C, R);
      if T >= 0 then DrawTile(Screen, Tiles, T, X + C * TileSize, Y + R * TileSize);
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

{ ---- status display (client-internals/status-display.md) ---- }

procedure TAdventure.DrawStatus;
const
  RowStart: array[0..5] of Integer = (0, 5, 11, 16, 22, 27);
var
  St: TGSurface;
  I, N, Row, Col, X, Half, HX, HY, Hearts2, Down: Integer;

  procedure Part(SX, SY, W, H, DX, DY: Integer);
  begin
    Screen.Blit(St, SX, SY, W, H, DX, DY);
  end;

  procedure Digits(V, CX, Y: Integer; Centred: Boolean);
  var
    D: string;
    J, X0: Integer;
  begin
    D := IntToStr(V);
    if Centred then X0 := CX - (Length(D) * 12) div 2 else X0 := CX;
    for J := 1 to Length(D) do
      Part(14 * (Ord(D[J]) - Ord('0')), 81, 14, 16, X0 + (J - 1) * 12, Y);
  end;

  procedure KeyName(const K: string; BX, BY: Integer);
  var
    TX: Integer;
  begin
    TX := BX + (22 - TextWidth(K, 2)) div 2;
    DrawText(Screen, TX + 1, BY + 9 + 1, K, $FF000000, 2);
    DrawText(Screen, TX, BY + 9, K, $FFFFFFFF, 2);
  end;

begin
  St := Assets.Image('state.png', '');
  if St = nil then Exit;
  { buttons with their keys; with weapons off only the first }
  if ShowStats and $01 <> 0 then
  begin
    Part(202, 0, 22, 33, 15, 30);
    KeyName('A', 15, 30);
    if WeaponsOn then
    begin
      Part(202, 0, 22, 33, 80, 30);
      KeyName('S', 80, 30);
      Part(202, 0, 22, 33, 145, 30);
      KeyName('D', 145, 30);
      if Player.GlovePower >= 2 then
        DrawText(Screen, 60, 31, IntToStr(Player.GlovePower), $FFFFFFFF, 1);
      DrawText(Screen, 125, 31, IntToStr(Player.SwordPower), $FFFFFFFF, 1);
    end;
  end;
  if WeaponsOn then
  begin
    if ShowStats and $02 <> 0 then Part(80, 33, 120, 16, 274, 30);
    if ShowStats and $04 <> 0 then Digits(Player.Rupees, 280, 48, True);
    if ShowStats and $08 <> 0 then
    begin
      Part(14 * ((Player.Bombs div 10) mod 10), 81, 14, 16, 326, 48);
      Part(14 * (Player.Bombs mod 10), 81, 14, 16, 338, 48);
    end;
    if ShowStats and $10 <> 0 then
    begin
      Part(14 * ((Player.Arrows div 10) mod 10), 81, 14, 16, 374, 48);
      Part(14 * (Player.Arrows mod 10), 81, 14, 16, 386, 48);
    end;
  end;
  { the selected weapon's whole image beside the D button: x 170, centred
    on y 45 }
  if (ShowStats and $01 <> 0) and WeaponsOn and (Selected >= 0) and (Selected <= High(Weapons)) and
    (Weapons[Selected].Image <> '') then
  begin
    St := Assets.Image(Weapons[Selected].Image, 'weapon');
    if St <> nil then Screen.Blit(St, 0, 0, St.Width, St.Height, 170, 45 - St.Height div 2);
    St := Assets.Image('state.png', '');
  end;
  { hearts: one per container while power remains }
  if ShowStats and $20 <> 0 then
  begin
    Hearts2 := Player.Power;  { half hearts }
    N := Min(Player.MaxPower, 30);
    if N <= 4 then
    begin
      for I := 0 to N - 1 do
      begin
        if Hearts2 <= 2 * I then Break;
        if Hearts2 >= 2 * I + 2 then Half := 0 else Half := 1;
        Part(40 * Half, 0, 40, 44, ScreenW - 198 + 45 * I, 24);
      end;
    end
    else
    begin
      if Hearts2 < 12 then Down := 10 else Down := 0;
      for I := 0 to N - 1 do
      begin
        if Hearts2 <= 2 * I then Break;
        if Hearts2 >= 2 * I + 2 then Half := 0 else Half := 1;
        Row := 0;
        while (Row < 5) and (I >= RowStart[Row + 1]) do Inc(Row);
        Col := I - RowStart[Row];
        HX := ScreenW - 198 + 35 * Col;
        HY := 24 + Down;
        if Row > 0 then
        begin
          Inc(HX, Round(17.5 * Row) - 35);
          Inc(HY, 20 * Row);
        end;
        Part(80 + 31 * Half, 0, 31, 33, HX, HY);
      end;
    end;
  end;
  { alignment bar }
  if ShowStats and $40 <> 0 then
  begin
    Part(0, 97, 130, 22, 15, 65);
    X := Max(0, Min(AP, 100));
    if X > 0 then Part(0, 119, X, 10, 15 + 22, 65 + 6);
  end;
end;

procedure TAdventure.ReplaceAni(const OldName, NewName: string);
var
  I: Integer;
begin
  if Trim(OldName) = '' then Exit;
  I := AniReplace.IndexOfName(LowerCase(Trim(OldName)));
  if I >= 0 then AniReplace.Delete(I);
  if Trim(NewName) <> '' then
    AniReplace.Add(LowerCase(Trim(OldName)) + '=' + Trim(NewName));
end;

function TAdventure.OwnAniName: string;
begin
  Result := AniReplace.Values[LowerCase(Player.AniName)];
  if Result = '' then Result := Player.AniName;
end;

procedure TAdventure.AddTileDef(const Img, Prefix: string; Kind: Integer);
var
  E: string;
  I: Integer;
begin
  if (Trim(Img) = '') or (Pos('..', Img) > 0) then Exit;
  E := LowerCase(Trim(Prefix)) + #9 + Trim(Img);
  I := TileDefs.IndexOf(E);
  if I >= 0 then TileDefs.Delete(I);
  TileDefs.InsertObject(0, E, TObject(PtrInt(Kind)));
end;

function TAdventure.TileDefIndex(const LevelName: string): Integer;
var
  I, T: Integer;
  N, Prefix: string;
  S: TGSurface;
begin
  Result := -1;
  N := LowerCase(LevelName);
  for I := 0 to TileDefs.Count - 1 do
  begin
    T := Pos(#9, TileDefs[I]);
    Prefix := Copy(TileDefs[I], 1, T - 1);
    if Copy(N, 1, Length(Prefix)) = Prefix then
    begin
      S := Assets.Image(Copy(TileDefs[I], T + 1, MaxInt), '');
      if (S <> nil) and (S.Width > 0) then
      begin
        Result := I;
        Exit;
      end;
    end;
  end;
end;

function TAdventure.TileSheetFor(const LevelName: string): TGSurface;
var
  I: Integer;
begin
  Result := Sheet;
  I := TileDefIndex(LevelName);
  if I >= 0 then
    Result := Assets.Image(Copy(TileDefs[I], Pos(#9, TileDefs[I]) + 1, MaxInt), '');
end;

function TAdventure.TileDefKind(const LevelName: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  I := TileDefIndex(LevelName);
  if I >= 0 then Result := Integer(PtrInt(TileDefs.Objects[I]));
end;

procedure TAdventure.Draw;
var
  CamX, CamY, TX, TY, X0, Y0, I: Integer;
begin
  Screen.Fill($FF000000);
  if Sheet.Width = 0 then MakeIndexSheet(Sheet);
  Tiles := TileSheetFor(Level.Name);
  { centre on the player's body (the sprite box is 3 tiles wide) }
  CamX := Round((Player.X + 1.5) * TileSize) - ScreenW div 2;
  CamY := Round((Player.Y + 2) * TileSize) - ScreenH div 2;
  if CamX > BoardW * TileSize - ScreenW then CamX := BoardW * TileSize - ScreenW;
  if CamY > BoardH * TileSize - ScreenH then CamY := BoardH * TileSize - ScreenH;
  if CamX < 0 then CamX := 0;
  if CamY < 0 then CamY := 0;
  X0 := CamX div TileSize;
  Y0 := CamY div TileSize;
  for TY := Y0 to Y0 + ScreenH div TileSize + 1 do
    for TX := X0 to X0 + ScreenW div TileSize + 1 do
      if (TX < BoardW) and (TY < BoardH) then
        DrawTile(Screen, Tiles, Level.Tile(TX, TY), TX * TileSize - CamX,
          TY * TileSize - CamY);
  { items under the players (2.05's order is not known), others, then the
    player, then anything in the air }
  DrawItems(CamX, CamY);
  Npcs.Draw(Screen, CamX, CamY, False);
  Baddies.Draw(Screen, CamX, CamY);
  for I := 0 to FOthers.Count - 1 do
    DrawPlayer(Others[I], CamX, CamY);
  DrawPlayer(Player, CamX, CamY);
  DrawCombat(CamX, CamY);
  DrawShots(CamX, CamY);
  Npcs.Draw(Screen, CamX, CamY, True);
  DrawNames(CamX, CamY);
  for I := 0 to High(Thrown) do
    DrawCarried(Thrown[I].Kind, Round(Thrown[I].X * TileSize) - CamX,
      Round(Thrown[I].Y * TileSize) - CamY);
  DrawStatus;
  DrawMaps(Self);
  if Reading then DrawSign(CamY);
  if ItemListOpen then DrawItemList;
end;

end.
