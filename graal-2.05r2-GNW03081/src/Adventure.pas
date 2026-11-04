{ Adventure: TAdventure, the game state and frame loop of 2.05 rev 2.

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
  Classes, GTypes, GLevel, GSurface, GArrays, GAni, GraalClient, Protocol205;

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
    BowImage, Chat: string;
    Attr: array[1..5] of string;
    X, Y: Double;       { tiles, top-left of the 3x3-tile sprite box }
    Sprite, Status, MaxPower, Power, Rupees, Arrows, Bombs: Integer;
    SwordPower, ShieldPower, GlovePower, BombPower: Integer;
    Colors: array[0..4] of Integer;
    Dir: Integer;
    AniName: string;
    AniStart: Integer;  { frame the animation started on }
    { -1: the animation runs with time. Otherwise the step to draw, for
      other players, whose pose comes from their sprite prop. }
    FixedStep: Integer;
    Gone: Boolean;      { PCONNECTED or a level leave seen }
    BodyCache: TGSurface; { the body recoloured for this player }
    BodyKey: string;
    constructor Create;
    destructor Destroy; override;
    { Parses a prop stream. Stops at the first id the stream does not
      accept, the way 2.05 does, and returns the ids applied. Other is the
      OTHERPLPROPS stream, which accepts fewer ids than the player's own. }
    function ApplyProps(R: TGReader; Other: Boolean): string;
    { Sets the pose of another player from the 2.05 sprite prop. }
    procedure PoseFromSprite;
    procedure SetAni(const Name: string; Frame: Integer);
  end;

  TAdventure = class
  private
    FClient: TAdventureClient;
    FLog: TStrings;
    FSentX, FSentY: Double;
    FSentSprite: Integer;
    FPropsSent: Boolean;
    FOthers: TList;
    FLevelDir: string;     { folder of the level file played offline }
    FWarpPending: Boolean; { a link warp was asked of the server }
    FWarpX, FWarpY: Double;
    FWarpLevel: string;
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure ClientLog(const Line: string);
    function PointBlocked(PX, PY: Double): Boolean;
    procedure SendInitialProps;
    procedure SendMovedProps;
    function BodyFor(P: TServerPlayer): TGSurface;
    procedure DrawPlayer(P: TServerPlayer; CamX, CamY: Integer);
    function GetOther(I: Integer): TServerPlayer;
    function GetOtherCount: Integer;
  public
    Level: TAdventureLevel;
    Player: TServerPlayer;
    Screen: TGSurface;
    Sheet: TGSurface;    { pics1 }
    Arrays: TGArrays;
    Assets: TAssets;
    Frame: Integer;
    WorldTime: Cardinal;
    ServerMessage, DisconnectReason: string;
    LoggedIn, BoardLoaded: Boolean;
    Handled, Ignored: array[0..255] of Integer;
    { Held direction keys for this tick: up, left, down, right. }
    Keys: array[0..3] of Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Log(const S: string);
    { Points pics1, arrays.dat and the image folders at an install. }
    procedure UseInstall(const Dir: string);
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
    { The link under the player, or -1. }
    function LinkAt(PX, PY: Double): Integer;
    { Takes link I: online, asks the server for the level; offline, loads
      it. Returns False when the level cannot be had. }
    function FollowLink(I: Integer): Boolean;
    { One message from the server, as the client's dispatcher hands it on. }
    procedure Receive(Id: Integer; const Data: string);
    { The player's own wire sprite: direction + 4 x the 2.05 sprite number
      for the current animation step. }
    function OwnSprite: Integer;
    { Another player by id; Make adds it when it is not known yet. }
    function FindOther(Id: Integer; Make: Boolean): TServerPlayer;
    procedure RemoveOther(Id: Integer);
    property Others[I: Integer]: TServerPlayer read GetOther;
    property OtherCount: Integer read GetOtherCount;
    property Client: TAdventureClient read FClient;
    property LogLines: TStrings read FLog;
  end;

{ Fallback tile sheet when pics1 is not available: each tile gets a flat
  colour derived from its index, so a frame still shows the board layout. }
{ The 2.05 animation step for a gani name and frame, and the sprite prop
  value (direction + 4 x sprite number) that goes with it. }
function AniStepNumber(const AniName: string; Frame: Integer): Integer;
function WireSprite(const AniName: string; Frame, Dir: Integer): Integer;
procedure MakeIndexSheet(Sheet: TGSurface);

implementation

uses
  SysUtils, Math;

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

{ ---- the 2.05 sprite prop (graal_analysis client-internals/
  feature-specs/11-emotes-ganis.md, decomp-findings-2026-10-24/
  sprite-step-table.tsv and gani-to-step.tsv) ---- }

const
  SpriteOfStep: array[0..38] of Byte = (
    0, 4, 5, 4, 3, 2, 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 11, 12, 14,
    15, 16, 17, 23, 18, 19, 20, 19, 18, 21, 22, 21, 18, 24, 25, 26, 27, 28, 29);

function AniStepNumber(const AniName: string; Frame: Integer): Integer;
var
  N: string;
begin
  N := LowerCase(AniName);
  if (N = 'idle') or (N = 'def') then Result := Frame
  else if (N = 'walk') or (N = 'walkslow') then Result := Frame + 1
  else if N = 'kick' then Result := 9
  else if (N = 'sword') or (N = 'ridesword') or (N = 'spin') then Result := 9 + Frame mod 5
  else if N = 'push' then Result := 14 + Frame
  else if N = 'grab' then Result := 19
  else if N = 'pull' then Result := 20 + Frame
  else if N = 'lift' then Result := 23
  else if (N = 'carrystill') or (N = 'hiddenstill') then Result := 24
  else if (N = 'carry') or (N = 'hidden') then Result := 25 + Frame
  else if N = 'shoot' then Result := 33
  else if N = 'ridestill' then Result := 34
  else if N = 'ridefire' then Result := 35
  else if N = 'rideeat' then Result := 36
  else if N = 'ride' then Result := 35 + Frame and 1
  else if N = 'sit' then Result := 37
  else if N = 'sleep' then Result := 38
  else Result := 0; { swim, lava and unknown names go out as idle }
end;

function WireSprite(const AniName: string; Frame, Dir: Integer): Integer;
var
  St: Integer;
begin
  St := AniStepNumber(AniName, Frame);
  if (St < 0) or (St > High(SpriteOfStep)) then St := 0;
  Result := (Dir and 3) + 4 * SpriteOfStep[St];
end;

function TAssets.FindFile(const Name: string; const Dirs: array of string): string;
var
  I, J: Integer;
  Base, Cand: string;
  Exts: array[0..2] of string;
begin
  Result := '';
  if (Dir = '') or (Name = '') then Exit;
  Base := ChangeFileExt(Name, '');
  Exts[0] := ExtractFileExt(Name);
  Exts[1] := '.png';
  Exts[2] := '.gif';
  for I := 0 to High(Dirs) do
    for J := 0 to 2 do
    begin
      if Exts[J] = '' then Continue;
      Cand := IncludeTrailingPathDelimiter(Dir) + Dirs[I] + Base + Exts[J];
      if FileExists(Cand) then
      begin
        Result := Cand;
        Exit;
      end;
    end;
end;

function TAssets.Image(const Name, Kind: string): TGSurface;
var
  Key, F: string;
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
  else F := FindFile(Name, ['', 'levels/', 'levels/images/']);
  S := nil;
  if F <> '' then
  begin
    S := TGSurface.Create(0, 0);
    if Kind = 'body' then Ok := LoadImageIndexed(F, S)
    else Ok := LoadImageFile(F, S);
    if not Ok then FreeAndNil(S);
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
  if Dir <> '' then
  begin
    F := IncludeTrailingPathDelimiter(Dir) + 'levels/ganis/' + Name + '.gani';
    if not FileExists(F) then
      F := IncludeTrailingPathDelimiter(Dir) + 'ganis/' + Name + '.gani';
    if FileExists(F) then
    begin
      A := TGraalAni.Create;
      if not A.LoadFromFile(F) then FreeAndNil(A);
    end;
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
  Dir := DirDown;
  AniName := 'idle';
  FixedStep := -1;
end;

destructor TServerPlayer.Destroy;
begin
  BodyCache.Free;
  inherited Destroy;
end;

procedure TServerPlayer.PoseFromSprite;
var
  S, F: Integer;
begin
  { invert the step table for the poses drawn so far: S 0 is idle, and the
    walk frames give S 1 to 5. Several frames share an S; the first wins. }
  S := Sprite div 4;
  AniName := 'idle';
  FixedStep := 0;
  if (S >= 1) and (S <= 5) then
    for F := 0 to 7 do
      if SpriteOfStep[F + 1] = S then
      begin
        AniName := 'walk';
        FixedStep := F;
        Exit;
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

function TServerPlayer.ApplyProps(R: TGReader; Other: Boolean): string;
var
  P, V, I: Integer;
begin
  Result := '';
  while not R.Eof do
  begin
    P := R.ReadGChar;
    { the ids each 2.05 parser accepts (protocol/player-props.md) }
    if Other then
    begin
      if (P = 1) or ((P >= 3) and (P <= 7)) or (P = 14) or (P = 22) or (P = 23) or
        ((P >= 25) and (P <= 29)) or ((P >= 43) and (P <= 49)) or (P > 51) then Exit;
    end
    else if P > 42 then Exit;
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
      PLPROP_BOWGIF: { pre-2.1: c(10 + len) + image, or c(bow power) }
        begin
          V := R.ReadGChar;
          if V > 10 then
            BowImage := R.ReadChars(V - 10);
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
          Dir := Sprite mod 4;
          if Other then PoseFromSprite;
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
      PLPROP_HORSEGIF, PLPROP_PLANGUAGE, PLPROP_GATTRIB6..PLPROP_GATTRIB9,
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
          if not R.Eof then R.ReadByte; { 2.05 skips one byte after it }
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
  FClient := TAdventureClient.Create;
  FClient.OnMessage := HandleMessage;
  FClient.OnLog := ClientLog;
  Level := TAdventureLevel.Create;
  Player := TServerPlayer.Create;
  Screen := TGSurface.Create(ScreenW, ScreenH);
  Sheet := TGSurface.Create(0, 0);
  Arrays := TGArrays.Create;
  Assets := TAssets.Create;
  FOthers := TList.Create;
end;

destructor TAdventure.Destroy;
var
  I: Integer;
begin
  FClient.Free;
  Level.Free;
  Player.Free;
  Screen.Free;
  Sheet.Free;
  Arrays.Free;
  Assets.Free;
  for I := 0 to FOthers.Count - 1 do TServerPlayer(FOthers[I]).Free;
  FOthers.Free;
  FLog.Free;
  inherited Destroy;
end;

procedure TAdventure.Log(const S: string);
begin
  FLog.Add(Format('[%5d] %s', [Frame, S]));
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
  P := IncludeTrailingPathDelimiter(Dir);
  if (Sheet.Width = 0) and not LoadImageFile(P + 'pics1.png', Sheet) then
    LoadImageFile(P + 'pics1.gif', Sheet);
  if Arrays.LoadFromFile(P + 'arrays.dat') then
    Log('arrays.dat loaded')
  else
    Log('arrays.dat not found in ' + Dir + ': walls do not block');
end;

function TAdventure.ConnectServer(const Host: string; Port: Word;
  const Account, Password: string): Boolean;
begin
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

function TAdventure.PointBlocked(PX, PY: Double): Boolean;
var
  TX, TY, I: Integer;
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
  { outside 0..63 is a gmap neighbour or a fixed tile; neither is modelled
    yet, so the edge is open and level links can be reached }
  if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then Exit;
  Result := not Arrays.TilePassable(Level.Tile(TX, TY));
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

{ ---- level links ---- }

function TAdventure.LoadLevelFile(const FileName: string): Boolean;
begin
  Result := Level.LoadFromFile(FileName);
  if Result then FLevelDir := ExtractFilePath(FileName);
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
    Log(Format('LEVELWARP %s %.1f,%.1f', [L.Dest, NX, NY]));
    Result := True;
    Exit;
  end;
  Path := '';
  if (FLevelDir <> '') and FileExists(FLevelDir + L.Dest) then
    Path := FLevelDir + L.Dest
  else if (Assets.Dir <> '') and FileExists(IncludeTrailingPathDelimiter(Assets.Dir) + 'levels' + PathDelim + L.Dest) then
    Path := IncludeTrailingPathDelimiter(Assets.Dir) + 'levels' + PathDelim + L.Dest
  else if (Assets.Dir <> '') and FileExists(IncludeTrailingPathDelimiter(Assets.Dir) + L.Dest) then
    Path := IncludeTrailingPathDelimiter(Assets.Dir) + L.Dest;
  if Path = '' then
  begin
    Log('link to ' + L.Dest + ': level not found');
    Exit;
  end;
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
var
  A: TGraalAni;
  F: Integer;
begin
  F := 0;
  A := Assets.Ani(Player.AniName);
  if A <> nil then F := A.StepAt(Frame - Player.AniStart);
  Result := WireSprite(Player.AniName, F, Player.Dir);
end;

procedure TAdventure.SendInitialProps;
begin
  { 2.05 sends props 0, 11, 13, 18, 31 and 33 together at session start }
  FClient.SendPacket(PLI_PLAYERPROPS,
    GChar(PLPROP_NICKNAME) + GString(Player.Nickname) +
    GChar(PLPROP_HEADGIF) + GChar(Length(Player.HeadImage) + 100) + Player.HeadImage +
    GChar(PLPROP_COLORS) + GChar(Player.Colors[0]) + GChar(Player.Colors[1]) +
      GChar(Player.Colors[2]) + GChar(Player.Colors[3]) + GChar(Player.Colors[4]) +
    GChar(PLPROP_STATUS) + GChar(Player.Status) +
    GChar(PLPROP_UDPPORT) + GInt3(0) +   { no UDP peer channel yet }
    GChar(PLPROP_ADDITFLAGS) + GChar(0));
  FSentX := Player.X;
  FSentY := Player.Y;
  FSentSprite := OwnSprite;
  FPropsSent := True;
end;

procedure TAdventure.SendMovedProps;
var
  S: string;
  Spr: Integer;
begin
  { a diff of the changed props, sent at most every other tick (100 ms) }
  if not FPropsSent or (Frame mod 2 <> 0) then Exit;
  S := '';
  if Player.X <> FSentX then S := S + GChar(PLPROP_X) + GChar(Round(Player.X * 2));
  if Player.Y <> FSentY then S := S + GChar(PLPROP_Y) + GChar(Round(Player.Y * 2));
  Spr := OwnSprite;
  if Spr <> FSentSprite then S := S + GChar(PLPROP_SPRITE) + GChar(Spr);
  if S = '' then Exit;
  FClient.SendPacket(PLI_PLAYERPROPS, S);
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
begin
  R := TGReader.Create(Data);
  try
    case Id of
      PLO_PLAYERPROPS:
        begin
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
      PLO_LEVELNAME:
        begin
          while FOthers.Count > 0 do RemoveOther(Others[0].Id);
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
      PLO_LEVELCHEST: { c opened, c x, c y, c item, c sign }
        begin
          R.ReadGChar;
          CH.X := R.ReadGChar;
          CH.Y := R.ReadGChar;
          CH.Item := R.ReadGChar;
          CH.Sign := R.ReadGChar;
          SetLength(Level.Chests, Length(Level.Chests) + 1);
          Level.Chests[High(Level.Chests)] := CH;
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
      PLO_LEVELMODTIME, PLO_ISLEADER, PLO_DEFAULTWEAPON, PLO_UNKNOWN168,
      PLO_STAFFGUILDS, PLO_HASNPCSERVER, PLO_FILEUPTODATE, PLO_FILESENDFAILED:
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

procedure TAdventure.Tick;
var
  D: Integer;
  Moved: Boolean;
begin
  Inc(Frame);
  if FClient.Connected then
  begin
    FClient.Poll;
    if not FClient.Connected then
      Log('link closed: ' + FClient.LastError);
  end;
  { keys run in the order up, left, down, right, each from where the
    earlier ones left the player }
  Moved := False;
  for D := 0 to 3 do
    if Keys[D] then
    begin
      WalkStep(D);
      Moved := True;
    end;
  if Moved then Player.SetAni('walk', Frame) else Player.SetAni('idle', Frame);
  { links are tested on the player's own walk, at the body's centre }
  if Moved then FollowLink(LinkAt(Player.X + 1.5, Player.Y + 2));
  SendMovedProps;
  FClient.Flush;
  Draw;
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
  BX := Round(P.X * TileSize) - CamX;
  BY := Round(P.Y * TileSize) - CamY;
  A := Assets.Ani(P.AniName);
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

procedure TAdventure.Draw;
var
  CamX, CamY, TX, TY, X0, Y0, I: Integer;
begin
  Screen.Fill($FF000000);
  if Sheet.Width = 0 then MakeIndexSheet(Sheet);
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
        DrawTile(Screen, Sheet, Level.Tile(TX, TY), TX * TileSize - CamX,
          TY * TileSize - CamY);
  { others first, then the player on top }
  for I := 0 to FOthers.Count - 1 do
    DrawPlayer(Others[I], CamX, CamY);
  DrawPlayer(Player, CamX, CamY);
end;

end.
