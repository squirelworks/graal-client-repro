{ BaddyNwb2: the baddies of 2.05 rev 2 (TComputer in the original).

  Read from the 2.05 client's baddy class in the decompile, not copied
  from it:
  - create: the power and image by type, the first direction
    (facing the player when near, else up or down), the mode by type
    (4 rises from the ground, 5 hops about its start, 6 shoots ink);
  - one step, every second game tick, the AI only offline or
    on the level leader (PLO_ISLEADER):
      0 walk 0.25 tile (x2 for types 6 and 8), turn at a wall, look
        about when the counter runs out, hunt on sight;
      1 look about (the head turns by a fixed table), then walk a random way;
      2 hunt 0.5 tile (x1.5 for type 8) toward the player's middle,
        along the main axis plus the other in proportion; archers (3, 9)
        go to a spot 11 tiles off the player's line and shoot;
      3 hurt and 4 bumped by a shield: knocked back, then hunt or die;
      5 dying (14 ticks), then gone; 6 type 4's 43-tick cycle; 7 type 5's
        46-tick hop; 8 type 6's ink shot;
  - sight: the player inside the 90-degree cone the head
    faces, within 20 tiles, nothing blocking on the straight line;
  - touch: the player's middle within a tile of the baddy's
    middle on both axes hurts the player;
  - sword: a shield block for types 0, 1, 2 and 7
    facing the swing, else a hit of the sword's power;
  - drawing: arrays.dat list 20 by ani * 4 + dir,
    list 23 for type 4, list 22 for the death puff; sprites 48 to 63,
    104 to 106 and 117 to 130 from the baddy's image, 111 to 114 from
    wbow1.gif, the rest from sprites.png;
  - BDPROP 0 to 10 (written and read by the client), PLO_BADDYPROPS (2), PLO_BADDYHURT
    (27), PLI_BADDYPROPS (15) and PLI_BADDYHURT (16).

  Not reproduced: the sounds, hunting other players (only this player is
  a target), water and other special tiles (the blocking test is the
  game's own), and the shield's push on the player. }
unit BaddyNwb2;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils, Math, GTypes, GLevel, GSurface, GArrays;

const
  BdWalk = 0;
  BdLook = 1;
  BdHunt = 2;
  BdHurt = 3;
  BdBumped = 4;
  BdDying = 5;
  BdRise = 6;
  BdHop = 7;
  BdInk = 8;
  BdDead = 9;

  PLO_BADDYPROPS_ID = 2;
  PLO_BADDYHURT_ID = 27;
  PLI_BADDYPROPS_ID = 15;
  PLI_BADDYHURT_ID = 16;

  BaddyImages: array[0..9] of string = ('baddygray.gif', 'baddyblue.gif',
    'baddyred.gif', 'baddyblue.gif', 'baddygray.gif', 'baddyhare.gif',
    'baddyoctopus.gif', 'baddygold.gif', 'baddylizardon.gif', 'baddydragon.gif');
  BaddyPowers: array[0..9] of Integer = (2, 3, 4, 3, 2, 1, 1, 6, 12, 8);

type
  { What a baddy needs from the game. The defaults do nothing (no walls,
    the player far away), so tests can use it as is. }
  TBaddyWorld = class
  public
    function Online: Boolean; virtual;
    function Leader: Boolean; virtual;
    function PlayerX: Double; virtual;   { top-left of the player's box }
    function PlayerY: Double; virtual;
    function PlayerDir: Integer; virtual;
    function PlayerHere: Boolean; virtual; { alive and in this level }
    function Blocked(X, Y: Double): Boolean; virtual;
    procedure HurtPlayer(Hearts, FromX, FromY: Double); virtual;
    procedure Shoot(X, Y: Double; Dir, Sprite, Kind: Integer); virtual;
    procedure Send(Id: Integer; const Data: string); virtual;
    function Image(const Name: string): TGSurface; virtual;
    function Arrays: TGArrays; virtual;
    procedure DrawVerse(Screen: TGSurface; CX, Y: Integer; const Text: string); virtual;
    procedure AllDied; virtual; { the last baddy of the level died }
  end;

  TBaddy = class
  public
    Id, Kind, Power, Mode, Ani, Dir, Head, Counter, Lost, Steps: Integer;
    X, Y, StartX, StartY, KnockX, KnockY, Dist: Double;
    Hurt, Aiming, Pending, Gone: Boolean;
    Image: string;
    Verses: array[0..2] of string;   { sight, hurt, attack }
    VerseFresh: array[0..2] of Boolean;
    Verse: string;
    VerseTime: Integer;
    Sent: array[0..10] of string;    { props as last sent (leader) }
    HasSent: Boolean;
    procedure ShowVerse(I: Integer);
  end;

  TBaddyManager = class
  private
    FRand: Cardinal;
    FTick: Integer;
    function Rand(N: Integer): Integer;
    function BlockedAhead(B: TBaddy; D: Integer): Boolean;
    function BlockedAround(B: TBaddy): Boolean;
    function DirToPlayer(B: TBaddy): Integer;
    function Sees(B: TBaddy; D: Integer): Boolean;
    function Active(B: TBaddy): Boolean;
    procedure Move(B: TBaddy; D: Integer; Speed: Double);
    procedure Unstick(B: TBaddy);
    procedure SightCheck(B: TBaddy);
    procedure Think(B: TBaddy);
    procedure Hunt(B: TBaddy);
    procedure ArcherHunt(B: TBaddy);
    procedure ShootArrow(B: TBaddy);
    procedure Knocked(B: TBaddy);
    procedure Touch(B: TBaddy);
    procedure Die(B: TBaddy);
    procedure SendChanges(B: TBaddy);
  public
    World: TBaddyWorld;
    Baddies: TList;
    constructor Create(AWorld: TBaddyWorld);
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    function Baddy(I: Integer): TBaddy;
    function Find(Id: Integer): TBaddy;
    procedure Seed(S: Cardinal);
    { A new baddy at (X, Y) tiles; Verses is the level file's text, the
      three lines split by '\'. }
    function Add(Kind: Integer; X, Y: Double; const Verses: string): TBaddy;
    { The level's baddies (offline: online the server sends them). }
    procedure LoadLevel(Level: TAdventureLevel);
    function Receive(Id: Integer; const Data: string): Boolean;
    procedure ApplyProps(B: TBaddy; const Data: string);
    function Prop(B: TBaddy; P: Integer): string;
    procedure Tick;
    { A hit: Hit (else a shield block), DX/DY from the baddy's middle to
      the hitter's. }
    procedure Hurt(B: TBaddy; Hit, Shield: Boolean; Power: Integer; DX, DY: Double);
    { The player's sword swing (2.05 tests it at the player's position
      and direction). }
    procedure SwordHit(Power: Integer);
    { A thrown object, arrow or blast at (X, Y): True when a baddy took it. }
    function PointHit(X, Y: Double; Power: Integer): Boolean;
    procedure Draw(Screen: TGSurface; CamX, CamY: Integer);
  end;

implementation

const
  VecX: array[0..3] of Double = (0, -0.25, 0, 0.25);
  VecY: array[0..3] of Double = (-0.25, 0, 0.25, 0);
  { three points 0.5 tile ahead of the 2 x 2 body, by direction }
  AheadX: array[0..3, 0..2] of Double = ((0.1, 1.0, 1.9), (-0.5, -0.5, -0.5),
    (0.1, 1.0, 1.9), (2.5, 2.5, 2.5));
  AheadY: array[0..3, 0..2] of Double = ((-0.5, -0.5, -0.5), (0.1, 1.0, 1.9),
    (2.5, 2.5, 2.5), (0.1, 1.0, 1.9));
  { head turns while looking about, by counter div 4 }
  LookTurn: array[0..10] of Integer = (1, 1, 0, -1, -1, 0, 1, 1, 0, -1, -1);
  { where an archer stands, from the player's middle }
  AimX: array[0..3] of Integer = (-1, 11, 0, 11);
  AimY: array[0..3] of Integer = (11, 1, -11, 1);
  { where an arrow starts, eighths of a tile }
  ArrowX: array[0..3] of Integer = (12, -10, 4, 11);
  ArrowY: array[0..3] of Integer = (-12, 0, 3, 0);
  { where the ink starts, eighths of a tile }
  InkX: array[0..3] of Integer = (4, -8, 4, 17);
  InkY: array[0..3] of Integer = (-3, 5, 12, 5);

{ ---- TBaddyWorld ---- }

function TBaddyWorld.Online: Boolean; begin Result := False; end;
function TBaddyWorld.Leader: Boolean; begin Result := False; end;
function TBaddyWorld.PlayerX: Double; begin Result := -100; end;
function TBaddyWorld.PlayerY: Double; begin Result := -100; end;
function TBaddyWorld.PlayerDir: Integer; begin Result := 2; end;
function TBaddyWorld.PlayerHere: Boolean; begin Result := True; end;
function TBaddyWorld.Blocked(X, Y: Double): Boolean;
begin
  Result := (X < 0) or (Y < 0) or (X >= 64) or (Y >= 64);
end;
procedure TBaddyWorld.HurtPlayer(Hearts, FromX, FromY: Double); begin end;
procedure TBaddyWorld.Shoot(X, Y: Double; Dir, Sprite, Kind: Integer); begin end;
procedure TBaddyWorld.Send(Id: Integer; const Data: string); begin end;
function TBaddyWorld.Image(const Name: string): TGSurface; begin Result := nil; end;
function TBaddyWorld.Arrays: TGArrays; begin Result := nil; end;
procedure TBaddyWorld.DrawVerse(Screen: TGSurface; CX, Y: Integer; const Text: string); begin end;
procedure TBaddyWorld.AllDied; begin end;

{ ---- TBaddy ---- }

procedure TBaddy.ShowVerse(I: Integer);
begin
  Verse := Verses[I];
  VerseTime := 20;
end;

{ ---- TBaddyManager ---- }

constructor TBaddyManager.Create(AWorld: TBaddyWorld);
begin
  World := AWorld;
  Baddies := TList.Create;
  FRand := Cardinal(GetTickCount64 and $FFFFFFFF);
end;

destructor TBaddyManager.Destroy;
begin
  Clear;
  Baddies.Free;
  World.Free;
  inherited;
end;

procedure TBaddyManager.Clear;
var
  I: Integer;
begin
  for I := 0 to Baddies.Count - 1 do TBaddy(Baddies[I]).Free;
  Baddies.Clear;
end;

function TBaddyManager.Count: Integer;
begin
  Result := Baddies.Count;
end;

function TBaddyManager.Baddy(I: Integer): TBaddy;
begin
  Result := TBaddy(Baddies[I]);
end;

function TBaddyManager.Find(Id: Integer): TBaddy;
var
  I: Integer;
begin
  for I := 0 to Baddies.Count - 1 do
  begin
    Result := Baddy(I);
    if Result.Id = Id then Exit;
  end;
  Result := nil;
end;

procedure TBaddyManager.Seed(S: Cardinal);
begin
  FRand := S;
end;

{ Delphi's Random: the same generator the original draws from }
function TBaddyManager.Rand(N: Integer): Integer;
begin
  FRand := Cardinal((UInt64(FRand) * 134775813 + 1) and $FFFFFFFF);
  Result := Integer((UInt64(FRand) * UInt64(Cardinal(N))) shr 32);
end;

function TBaddyManager.Add(Kind: Integer; X, Y: Double; const Verses: string): TBaddy;
var
  B: TBaddy;
  I, P, R: Integer;
  S: string;
begin
  B := TBaddy.Create;
  if (Kind < 0) or (Kind > 9) then Kind := 0;
  B.Kind := Kind;
  B.Id := Baddies.Count;
  B.X := X;
  B.Y := Y;
  B.StartX := X;
  B.StartY := Y;
  B.Image := BaddyImages[Kind];
  B.Power := BaddyPowers[Kind];
  S := Verses;
  for I := 0 to 2 do
  begin
    P := Pos('\', S);
    if P = 0 then P := Length(S) + 1;
    B.Verses[I] := Copy(S, 1, P - 1);
    Delete(S, 1, P);
    B.VerseFresh[I] := True;
  end;
  B.VerseTime := -1;
  { facing the player when near (30 tiles, x plus y) or type 1, else up
    when the player is above }
  if (Abs(X - World.PlayerX) + Abs(Y - World.PlayerY) <= 30) or (Kind = 1) then
    B.Dir := (World.PlayerDir + 2) and 3
  else if World.PlayerY <= Y then B.Dir := 0
  else B.Dir := 2;
  B.Head := B.Dir;
  case Kind of
    4:
      begin
        B.Mode := BdRise;
        B.Ani := 2;
      end;
    5:
      begin
        B.Mode := BdHop;
        R := Rand(4);
        case R of
          0: B.Y := B.Y - 4;
          1: B.X := B.X - 4;
        else B.X := B.X + 4; { 2 and 3 both, as the original }
        end;
      end;
    6:
      begin
        B.Dir := 3;
        B.Head := 3;
        B.Ani := 4;
        B.Counter := Rand(10) + 20;
      end;
  else
    B.Counter := Rand(20) + 40;
  end;
  Baddies.Add(B);
  Result := B;
end;

procedure TBaddyManager.LoadLevel(Level: TAdventureLevel);
var
  I: Integer;
begin
  Clear;
  if World.Online then Exit;
  for I := 0 to High(Level.Baddies) do
    Add(Level.Baddies[I].Kind, Level.Baddies[I].X, Level.Baddies[I].Y,
      Level.Baddies[I].Verses);
end;

{ ---- props ---- }

function TBaddyManager.Prop(B: TBaddy; P: Integer): string;
var
  Img: string;

  { one byte: kept to what the wire can carry }
  function GChar(V: Integer): Char;
  begin
    Result := GTypes.GChar(EnsureRange(V, 0, 223));
  end;

begin
  case P of
    0: Result := GChar(B.Id);
    1: Result := GChar(Round(B.X * 2));
    2: Result := GChar(Round(B.Y * 2));
    3: Result := GChar(B.Kind);
    4:
      begin
        Img := B.Image;
        if SameText(Img, BaddyImages[B.Kind]) then Img := '';
        Result := GChar(B.Power) + GChar(Length(Img)) + Img;
      end;
    5: Result := GChar(B.Mode);
    6: Result := GChar(B.Counter);
    7: Result := GChar(B.Dir * 4 + B.Head);
    8..10: Result := GChar(Length(B.Verses[P - 8])) + B.Verses[P - 8];
  else
    Result := '';
  end;
end;

procedure TBaddyManager.ApplyProps(B: TBaddy; const Data: string);
var
  P, Id, V, L: Integer;
begin
  P := 1;
  while P < Length(Data) do
  begin
    Id := Ord(Data[P]) - 32;
    V := Ord(Data[P + 1]) - 32;
    L := 1;
    case Id of
      0: B.Id := V;
      1:
        begin
          B.X := EnsureRange(V / 2, 0, 63);
          B.StartX := B.X;
        end;
      2:
        begin
          B.Y := EnsureRange(V / 2, 0, 63);
          B.StartY := B.Y;
        end;
      3:
        begin
          if (V >= 0) and (V <= 9) then B.Kind := V;
          if V = 4 then B.Ani := 2;
          if V = 6 then B.Ani := 4;
        end;
      4:
        begin
          B.Power := V;
          if P + 2 > Length(Data) then Break;
          L := Max(2, Ord(Data[P + 2]) - 30);
          if L <= 2 then B.Image := BaddyImages[B.Kind]
          else B.Image := Copy(Data, P + 3, L - 2);
        end;
      5:
        begin
          B.Hurt := V = BdHurt;
          if V = BdHurt then B.Pending := False;
          if not B.Pending then B.Mode := V;
          if (V = BdHunt) and B.VerseFresh[0] then
          begin
            B.VerseFresh[0] := False;
            B.ShowVerse(0);
          end;
          if (V = BdHurt) and B.VerseFresh[1] then
          begin
            B.VerseFresh[1] := False;
            B.VerseFresh[0] := False;
            B.ShowVerse(1);
          end;
          if V = BdDead then B.Gone := True;
        end;
      6: B.Counter := V;
      7:
        begin
          B.Dir := (V shr 2) and 3;
          B.Head := V and 3;
        end;
      8..10:
        begin
          V := Max(0, V);
          B.Verses[Id - 8] := Copy(Data, P + 2, V);
          L := V + 1;
        end;
    else
      Break;
    end;
    Inc(P, L + 1);
  end;
end;

function TBaddyManager.Receive(Id: Integer; const Data: string): Boolean;
var
  B: TBaddy;
  N: Integer;
  DX, DY: Double;
begin
  Result := False;
  case Id of
    PLO_BADDYPROPS_ID:
      begin
        Result := True;
        if Length(Data) < 1 then Exit;
        N := Ord(Data[1]) - 32;
        B := Find(N);
        if B = nil then
        begin
          B := Add(0, 0, 0, '');
          B.Id := N;
        end;
        ApplyProps(B, Copy(Data, 2, MaxInt));
        if B.Gone then
        begin
          Baddies.Remove(B);
          B.Free;
        end;
      end;
    PLO_BADDYHURT_ID:
      begin
        Result := True;
        if (Length(Data) < 4) or not World.Leader then Exit;
        B := Find(Ord(Data[1]) - 32);
        if B = nil then Exit;
        DX := (Ord(Data[2]) - 96) / 16;
        DY := (Ord(Data[3]) - 96) / 16;
        { the leader runs the hit as its own }
        if Active(B) then Hurt(B, True, False, Ord(Data[4]) - 32, DX, DY);
      end;
  end;
end;

procedure TBaddyManager.SendChanges(B: TBaddy);
var
  P: Integer;
  S, V: string;
begin
  S := '';
  for P := 1 to 10 do
  begin
    V := Prop(B, P);
    if B.HasSent and (V <> B.Sent[P]) then S := S + GChar(P) + V;
    B.Sent[P] := V;
  end;
  B.HasSent := True;
  if S <> '' then World.Send(PLI_BADDYPROPS_ID, Prop(B, 0) + S);
end;

{ ---- the rules ---- }

function TBaddyManager.BlockedAhead(B: TBaddy; D: Integer): Boolean;
var
  I: Integer;
begin
  D := D and 3;
  for I := 0 to 2 do
    if World.Blocked(B.X + AheadX[D, I], B.Y + AheadY[D, I]) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function TBaddyManager.BlockedAround(B: TBaddy): Boolean;
var
  D: Integer;
begin
  for D := 0 to 3 do
    if BlockedAhead(B, D) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function TBaddyManager.DirToPlayer(B: TBaddy): Integer;
var
  DX, DY: Double;
begin
  DX := World.PlayerX + 1.5 - (B.X + 1);
  DY := World.PlayerY + 2 - (B.Y + 1);
  B.Dist := Max(Abs(DX), Abs(DY));
  if Abs(DY) <= Abs(DX) then
  begin
    if DX <= 0 then Result := 1 else Result := 3;
  end
  else if DY <= 0 then Result := 0
  else Result := 2;
end;

{ sight: the player in the cone D faces, within 20, nothing in between }
function TBaddyManager.Sees(B: TBaddy; D: Integer): Boolean;
var
  BX, BY, PX, PY, ADX, ADY, L: Double;
  I: Integer;
begin
  Result := False;
  if not World.PlayerHere then Exit;
  BX := B.X + 1;
  BY := B.Y + 1;
  PX := World.PlayerX + 1.5;
  PY := World.PlayerY + 2;
  ADX := Abs(BX - PX);
  ADY := Abs(BY - PY);
  case D and 3 of
    0: if (BY <= PY) or (ADY < ADX) then Exit;
    1: if (BX <= PX) or (ADX < ADY) then Exit;
    2: if (PY <= BY) or (ADY < ADX) then Exit;
    3: if (PX <= BX) or (ADX < ADY) then Exit;
  end;
  L := Max(ADX, ADY);
  if L = 0 then
  begin
    Result := True;
    Exit;
  end;
  if L > 20 then Exit;
  I := 0;
  while I < L do
  begin
    if World.Blocked(BX + (PX - BX) * I / L, BY + (PY - BY) * I / L) then Exit;
    Inc(I);
  end;
  Result := True;
end;

{ can be hit and can hurt }
function TBaddyManager.Active(B: TBaddy): Boolean;
begin
  case B.Mode of
    BdHurt, BdBumped, BdDying, BdDead: Result := False;
    BdRise: Result := (B.Lost < 1) and (B.Counter > 21) and (B.Counter < 37);
    BdHop: Result := (B.Counter > 16) and (B.Counter < 38);
  else
    Result := True;
  end;
end;

procedure TBaddyManager.Move(B: TBaddy; D: Integer; Speed: Double);
begin
  B.X := B.X + VecX[D and 3] * Speed;
  B.Y := B.Y + VecY[D and 3] * Speed;
end;

{ against a wall: onto the half-tile grid, then half a tile off each side
  that is blocked }
procedure TBaddyManager.Unstick(B: TBaddy);
var
  D: Integer;
begin
  B.X := Round(B.X * 2) / 2;
  B.Y := Round(B.Y * 2) / 2;
  for D := 0 to 3 do
    if BlockedAhead(B, D) then
      case D of
        0: B.Y := B.Y + 0.5;
        1: B.X := B.X + 0.5;
        2: B.Y := B.Y - 0.5;
        3: B.X := B.X - 0.5;
      end;
end;

procedure TBaddyManager.SightCheck(B: TBaddy);
var
  D: Integer;
begin
  D := DirToPlayer(B);
  if Sees(B, B.Head) and (B.Dist < 20) then
  begin
    B.Mode := BdHunt;
    B.Counter := 16;
    B.Dir := D;
    B.Head := D;
    B.Lost := 0;
    B.Steps := 0;
    if B.VerseFresh[0] then
    begin
      B.VerseFresh[0] := False;
      B.ShowVerse(0);
    end;
  end;
end;

procedure TBaddyManager.Hunt(B: TBaddy);
var
  DX, DY, ADX, ADY, Ratio, Speed: Double;
  Main, Want, Side: Integer;
  See, MainB, SideB: Boolean;
begin
  B.Counter := (B.Counter + 3) and 3;
  B.Ani := B.Counter div 2;
  DirToPlayer(B);
  if not World.PlayerHere then Exit;
  DX := World.PlayerX + 1.5 - (B.X + 1);
  DY := World.PlayerY + 2 - (B.Y + 1);
  ADX := Abs(DX);
  ADY := Abs(DY);
  See := Sees(B, B.Dir);
  if See then B.Lost := 0
  else
  begin
    Inc(B.Lost);
    if B.Lost > 40 then
    begin
      B.Mode := BdLook;
      B.Counter := 44;
    end;
  end;
  if B.Mode <> BdHunt then Exit;
  if ADY <= ADX then
  begin
    if DX <= 0 then Main := 1 else Main := 3;
    if DY <= 0 then Side := 0 else Side := 2;
    if ADX > 0 then Ratio := ADY / ADX else Ratio := 0;
  end
  else
  begin
    if DY <= 0 then Main := 0 else Main := 2;
    if DX <= 0 then Side := 1 else Side := 3;
    Ratio := ADX / ADY;
  end;
  Want := Main;
  { close and out of sight: keep going the same way }
  if (ADY < 2) and (ADX < 2) and not See then Main := B.Dir;
  MainB := BlockedAhead(B, Main);
  SideB := BlockedAhead(B, Side);
  if (Want <> Main) and MainB then
  begin
    Main := Want;
    MainB := BlockedAhead(B, Main);
    SideB := BlockedAhead(B, Side);
  end;
  B.Dir := Main;
  B.Head := Main;
  if B.Kind = 8 then Speed := 3 else Speed := 2;
  if not MainB and SideB then Move(B, Main, Speed)
  else if not MainB and not SideB then
  begin
    Move(B, Main, Speed);
    Move(B, Side, Speed * Ratio);
  end
  else if MainB and not SideB then Move(B, Side, Speed);
  if MainB then Unstick(B);
end;

procedure TBaddyManager.ShootArrow(B: TBaddy);
var
  K: Integer;
begin
  B.Lost := 15;
  B.Aiming := True;
  if B.Kind = 9 then K := 2 else K := 0;
  World.Shoot(B.X + ArrowX[B.Dir] / 8, B.Y + ArrowY[B.Dir] / 8, B.Dir, 107 + B.Dir, K);
  B.Steps := 0;
end;

procedure TBaddyManager.ArcherHunt(B: TBaddy);
var
  D, Main, Side: Integer;
  TX, TY, DX, DY, ADX, ADY, OX, OY: Double;
  MainB, SideB: Boolean;
begin
  if B.Kind = 9 then
  begin
    B.Counter := (B.Counter + 3) and 3;
    B.Ani := B.Counter div 2;
  end
  else B.Ani := 2;
  if B.Lost >= 1 then
  begin
    Dec(B.Lost);
    if B.Lost = 0 then B.Counter := 12;
    Exit;
  end;
  if not World.PlayerHere then Exit;
  D := DirToPlayer(B);
  B.Dir := D;
  B.Head := D;
  TX := World.PlayerX + 1.5 + AimX[D];
  TY := World.PlayerY + 2 + AimY[D];
  if B.Aiming then
  begin
    B.Aiming := False;
    if Sees(B, B.Dir) then
    begin
      B.Mode := BdLook;
      B.Counter := 44;
      Exit;
    end;
  end;
  DX := TX - (B.X + 1);
  DY := TY - (B.Y + 1);
  ADX := Abs(DX);
  ADY := Abs(DY);
  if ((ADX < 1) and (ADY < 1)) or (B.Steps > 40) then
  begin
    ShootArrow(B);
    Exit;
  end;
  Inc(B.Steps);
  if ADY <= ADX then
  begin
    if DX <= 0 then Main := 1 else Main := 3;
    if DY <= 0 then Side := 0 else Side := 2;
  end
  else
  begin
    if DY <= 0 then Main := 0 else Main := 2;
    if DX <= 0 then Side := 1 else Side := 3;
  end;
  MainB := BlockedAhead(B, Main);
  SideB := BlockedAhead(B, Side);
  OX := B.X;
  OY := B.Y;
  if not MainB then
  begin
    if ADX >= 1 then B.X := B.X + VecX[Main] * 2;
    if ADY >= 1 then B.Y := B.Y + VecY[Main] * 2;
  end;
  if not SideB then
  begin
    if ADX >= 1 then B.X := B.X + VecX[Side] * 2;
    if ADY >= 1 then B.Y := B.Y + VecY[Side] * 2;
  end;
  if MainB then Unstick(B);
  { stuck, or in line with the player: shoot }
  if ((B.X = OX) and (B.Y = OY)) or
    ((B.Dir in [1, 3]) and (ADY < 1) and (ADX >= 11)) or
    ((B.Dir in [0, 2]) and (ADX < 1) and (ADY >= 11)) then
    ShootArrow(B);
end;

{ modes 3 and 4: knocked back, then hunt again or die }
procedure TBaddyManager.Knocked(B: TBaddy);
begin
  if B.Counter > 2 then
  begin
    B.X := B.X + B.KnockX;
    B.Y := B.Y + B.KnockY;
    if BlockedAround(B) then
    begin
      B.X := B.X - B.KnockX;
      B.Y := B.Y - B.KnockY;
    end;
  end;
  Dec(B.Counter);
  if B.Counter < 1 then
  begin
    if B.Power < 1 then
    begin
      B.Mode := BdDying;
      B.Counter := 14;
    end
    else
    begin
      if (B.Mode = BdHurt) and B.VerseFresh[1] then
      begin
        B.VerseFresh[1] := False;
        B.VerseFresh[0] := False;
        B.ShowVerse(1);
      end;
      B.Mode := BdHunt;
      B.Counter := 12;
      B.Head := DirToPlayer(B);
      B.Lost := 0;
    end;
  end
  else if (B.Counter < 4) and (B.Kind = 6) then
  begin
    B.Mode := BdDying;
    B.Counter := 9;
  end;
end;

{ the AI step, by mode }
procedure TBaddyManager.Think(B: TBaddy);
var
  R: Integer;
begin
  case B.Mode of
    BdWalk:
      begin
        if B.Head = B.Dir then
        begin
          Dec(B.Counter);
          if B.Counter < 0 then
          begin
            if B.Kind = 6 then
            begin
              B.Mode := BdInk;
              B.Counter := 13;
            end
            else
            begin
              B.Mode := BdLook;
              B.Counter := 44;
            end;
          end
          else
          begin
            B.Ani := (B.Counter and 3) div 2;
            if B.Kind = 6 then Inc(B.Ani, 4);
          end;
          if B.Mode = BdWalk then
          begin
            if not BlockedAhead(B, B.Dir) then
            begin
              if B.Kind in [6, 8] then Move(B, B.Dir, 2) else Move(B, B.Dir, 1);
            end
            else
            begin
              B.Head := (B.Dir + 2) and 3;
              if B.Kind = 6 then B.Dir := B.Head
              else B.Dir := (B.Dir + 3) and 3;
              if not Odd(B.Counter) then Dec(B.Counter);
            end;
          end;
        end
        else if not Odd(B.Counter) then B.Dir := B.Head
        else Dec(B.Counter);
        if B.Kind <> 6 then SightCheck(B);
      end;
    BdLook:
      begin
        Dec(B.Counter);
        if B.Counter < 0 then
        begin
          R := Rand(4);
          B.Dir := R;
          B.Head := R;
          B.Mode := BdWalk;
          B.Counter := Rand(20) + 40;
        end
        else
          B.Head := (LookTurn[Min(10, B.Counter div 4)] + B.Dir + 4) and 3;
        SightCheck(B);
      end;
    BdHunt:
      if B.Counter < 6 then
      begin
        B.Hurt := False;
        if B.Kind in [3, 9] then ArcherHunt(B) else Hunt(B);
      end
      else
      begin
        Dec(B.Counter);
        if not B.Hurt then B.Ani := B.Counter and 1;
      end;
    BdHurt, BdBumped: Knocked(B);
    BdDying: if B.Counter >= 0 then Dec(B.Counter);
    BdRise:
      begin
        B.Counter := (B.Counter + 1) mod 43;
        case B.Counter of
          11: B.Dir := 2;
          22: B.Dir := DirToPlayer(B);
          25: ShootArrow(B);
          33:
            begin
              B.Dir := 2;
              B.Aiming := False;
            end;
        end;
        B.Head := B.Dir;
        if B.Lost > 0 then
        begin
          Dec(B.Lost);
          if B.Lost < 1 then
          begin
            B.Hurt := False;
            if B.Power < 1 then
            begin
              B.Mode := BdDying;
              B.Counter := 14;
            end;
          end;
        end;
      end;
    BdHop:
      begin
        B.Counter := (B.Counter + 1) mod 46;
        if B.Counter = 0 then
        begin
          Inc(B.Lost);
          if not Odd(B.Lost) then
          begin
            B.X := B.StartX;
            B.Y := B.StartY;
            case Rand(4) of
              0: B.Y := B.Y - 4;
              1: B.X := B.X - 4;
              2: B.Y := B.Y + 4;
              3: B.X := B.X + 4;
            end;
          end;
        end;
      end;
    BdInk:
      begin
        Dec(B.Counter);
        case B.Counter of
          0:
            begin
              R := Rand(4);
              B.Dir := R;
              B.Head := R;
              B.Mode := BdWalk;
              B.Counter := Rand(10) + 20;
            end;
          2: B.Ani := 4;
          6:
            begin
              B.Ani := 7;
              World.Shoot(B.X + InkX[B.Dir] / 8, B.Y + InkY[B.Dir] / 8, B.Dir, 131, 0);
            end;
          10: B.Ani := 6;
        end;
      end;
  end;
end;

{ touching the player hurts it }
procedure TBaddyManager.Touch(B: TBaddy);
var
  Hearts: Double;
begin
  if not Active(B) or not World.PlayerHere then Exit;
  if (Abs(World.PlayerX + 1.5 - (B.X + 1)) <= 1) and
    (Abs(World.PlayerY + 2 - (B.Y + 1)) <= 1) then
  begin
    if B.Kind = 7 then Hearts := 1 else Hearts := 0.5;
    World.HurtPlayer(Hearts, B.X + 1, B.Y + 1);
    if not B.VerseFresh[0] and B.VerseFresh[2] then
    begin
      B.VerseFresh[2] := False;
      B.ShowVerse(2);
    end;
  end;
end;

procedure TBaddyManager.Die(B: TBaddy);
begin
  B.Mode := BdDead;
  Baddies.Remove(B);
  B.Free;
  if Baddies.Count = 0 then World.AllDied;
end;

{ one step of every baddy, every second tick }
procedure TBaddyManager.Tick;
var
  I: Integer;
  B: TBaddy;
  Runs: Boolean;
begin
  Inc(FTick);
  if Odd(FTick) then Exit;
  Runs := not World.Online or World.Leader;
  I := 0;
  while I < Baddies.Count do
  begin
    B := Baddy(I);
    if Runs then Think(B);
    Touch(B);
    if B.Kind = 3 then B.Ani := (B.Ani and 1) + 2;
    if (B.Kind = 6) and (B.Ani < 2) then B.Ani := (B.Ani and 1) + 4;
    if B.VerseTime >= 0 then Dec(B.VerseTime);
    if (B.Mode = BdDying) and (B.Counter < 0) then
    begin
      Die(B);
      Continue;
    end;
    if World.Online and World.Leader then SendChanges(B);
    Inc(I);
  end;
end;

{ a hit or a shield block: power, mode and knockback }
procedure TBaddyManager.Hurt(B: TBaddy; Hit, Shield: Boolean; Power: Integer; DX, DY: Double);
var
  L, N: Double;
begin
  if World.Online and not World.Leader then
  begin
    if Hit then
    begin
      B.Power := B.Power - Power;
      B.Mode := BdHurt;
      B.Pending := True;
      World.Send(PLI_BADDYHURT_ID, GChar(B.Id) + GChar(Round(DX * 16) + 64) +
        GChar(Round(DY * 16) + 64) + GChar(Power));
    end;
    Exit;
  end;
  if not Shield then
  begin
    B.Hurt := True;
    B.Power := B.Power - Power;
    if B.Kind = 4 then
    begin
      B.Lost := 8;
      Exit;
    end;
    if B.Kind = 5 then
    begin
      B.Mode := BdDying;
      B.Counter := 9;
      Exit;
    end;
    B.Mode := BdHurt;
    L := 2.0;
  end
  else
  begin
    B.Mode := BdBumped;
    L := 0.8;
    B.Hurt := False;
  end;
  B.Counter := 8;
  B.KnockX := -DX * 2;
  B.KnockY := -DY * 2;
  N := Sqrt(Sqr(B.KnockX) + Sqr(B.KnockY));
  if N <= 0 then B.KnockX := -L
  else
  begin
    B.KnockX := B.KnockX * L / N;
    B.KnockY := B.KnockY * L / N;
  end;
end;

{ the sword: the swing's reach by the player's direction }
procedure TBaddyManager.SwordHit(Power: Integer);
var
  I, D: Integer;
  B: TBaddy;
  PX, PY, BX, BY, ADX, ADY: Double;
  Block, Hit: Boolean;
begin
  if not World.PlayerHere then Exit;
  PX := World.PlayerX + 1.5;
  PY := World.PlayerY + 2;
  D := World.PlayerDir and 3;
  for I := Baddies.Count - 1 downto 0 do
  begin
    B := Baddy(I);
    if not Active(B) then Continue;
    BX := B.X + 1;
    BY := B.Y + 1;
    ADX := Abs(PX - BX);
    ADY := Abs(PY - BY);
    Block := False;
    if (((D + 2) and 3) = B.Dir) and (B.Kind in [0, 1, 2, 7]) then
      case D of
        0: Block := not ((BY + 5 < PY) or (PY <= BY + 2) or (ADX > 2) or (BX + 0.5 <= PX));
        1: Block := not ((BX + 5 < PX) or (PX <= BX + 2) or (ADY > 2) or (PY <= BY - 0.5));
        2: Block := not ((PY < BY - 5) or (BY - 2 <= PY) or (ADX > 2) or (PX <= BX - 0.5));
        3: Block := not ((PX < BX - 5) or (BX - 2 <= PX) or (ADY > 2) or (PY <= BY - 0.5));
      end;
    Hit := False;
    if not Block then
      case D of
        0: Hit := not ((BY + 4 < PY) or (PY < BY) or (ADX >= 2));
        1: Hit := not ((BX + 4 < PX) or (PX < BX) or (ADY >= 2));
        2: Hit := not ((PY < BY - 4) or (BY < PY) or (ADX > 2));
        3: Hit := not ((PX < BX - 4) or (BX < PX) or (ADY > 2));
      end;
    if Hit or Block then Hurt(B, Hit, Block, Power, PX - BX, PY - BY);
  end;
end;

{ a point over the baddy's body (a tile each side of its middle,
  two above and one below) }
function TBaddyManager.PointHit(X, Y: Double; Power: Integer): Boolean;
var
  I: Integer;
  B: TBaddy;
  BX, BY: Double;
begin
  Result := False;
  for I := Baddies.Count - 1 downto 0 do
  begin
    B := Baddy(I);
    if not Active(B) then Continue;
    BX := B.X + 1;
    BY := B.Y + 1;
    if (X < BX - 1) or (X > BX + 1) or (Y < BY - 2) or (Y > BY + 1) then Continue;
    Hurt(B, True, False, Power, X - BX, Y - BY);
    Result := True;
    Exit;
  end;
end;

{ ---- drawing ---- }

procedure TBaddyManager.Draw(Screen: TGSurface; CamX, CamY: Integer);
var
  I, K, N, S, SX, SY, SW, SH, C: Integer;
  B: TBaddy;
  A: TGArrays;
  Entries: array of Integer;
  Img, Spr, Bow, Src: TGSurface;

  procedure Use(L: TGArray);
  var
    J: Integer;
  begin
    if L = nil then Exit;
    SetLength(Entries, Length(L.Values));
    for J := 0 to High(L.Values) do Entries[J] := L.Values[J];
  end;

  function Item(List, Index: Integer): TGArray;
  begin
    Result := nil;
    if (A.Lists[List] <> nil) and (Index >= 0) and (Index <= High(A.Lists[List].Items)) then
      Result := A.Lists[List].Items[Index];
  end;

  function Pack(Sprite, DX, DY: Integer): Integer;
  begin
    Result := (Sprite shl 16) or ((DX and 255) shl 8) or (DY and 255);
  end;

begin
  A := World.Arrays;
  if A = nil then Exit;
  Spr := World.Image('sprites.png');
  Bow := World.Image('wbow1.gif');
  for I := 0 to Baddies.Count - 1 do
  begin
    B := Baddy(I);
    Img := World.Image(B.Image);
    C := B.Counter;
    SetLength(Entries, 0);
    if (B.Mode <> BdDying) or (C > 3) then
    begin
      if B.Kind = 4 then
      begin
        if C > 10 then
          if (C < 17) or (C > 44) then Use(Item(23, (C - 11) and 1))
          else if C < 22 then Use(Item(23, 2))
          else if C < 33 then
          begin
            { the body over the mound instead of its shadow }
            Use(Item(20, B.Ani * 4 + B.Dir));
            if (Length(Entries) > 0) and (Item(23, 0) <> nil) and
              (Length(Item(23, 0).Values) > 0) then
            begin
              for K := 0 to High(Entries) - 1 do Entries[K] := Entries[K + 1];
              Entries[High(Entries)] := Item(23, 0).Values[0];
            end;
          end
          else if C < 35 then Use(Item(23, 2))
          else if C < 37 then Use(Item(23, 3));
      end
      else if B.Kind = 5 then
      begin
        if (B.Mode <> BdDying) and (C > 10) then
          if (C < 17) or (C > 37) then
          begin
            SetLength(Entries, 1);
            Entries[0] := Pack(22 + (C and 1), 0, 8);
          end
          else
          begin
            { the hop: up and down over its shadow (the height curve is a
              guess: the original's call lost its arguments) }
            SetLength(Entries, 2);
            Entries[0] := Pack(48, 0, -Round(Sin((C - 17) * Pi / 21) * 24));
            Entries[1] := Pack(22, 0, 8);
          end;
      end
      else
        Use(Item(20, B.Ani * 4 + B.Dir));
      for K := 0 to High(Entries) do
      begin
        S := Entries[K] shr 16;
        if (S >= 48) and (S <= 51) and (B.Kind <> 5) then S := 48 + B.Head;
        if B.Aiming and (S >= 107) and (S <= 110) then Continue;
        if (B.Kind = 9) and (S >= 64) then Continue; { the dragon has no weapon }
        if B.Hurt and (S >= 1) and (S <= 106) and Odd(FTick div 2) then Continue;
        if ((S >= 48) and (S <= 63)) or ((S >= 117) and (S <= 130)) or
          ((S >= 104) and (S <= 106)) then Src := Img
        else if (S >= 111) and (S <= 114) then Src := Bow
        else Src := Spr;
        if (Src = nil) or not A.SpriteRect(S, SX, SY, SW, SH) then Continue;
        Screen.Blit(Src, SX, SY, SW, SH,
          Round((B.X + ShortInt((Entries[K] shr 8) and 255) / 8) * 16) - CamX,
          Round((B.Y + ShortInt(Entries[K] and 255) / 8) * 16) - CamY);
      end;
      if (B.VerseTime >= 0) and (B.Verse <> '') then
        World.DrawVerse(Screen, Round((B.X + 1) * 16) - CamX, Round((B.Y - 2) * 16) - CamY, B.Verse);
    end;
    { the puff of smoke at the end }
    if (B.Mode = BdDying) and (C < 10) and (C >= 0) then
    begin
      SetLength(Entries, 0);
      Use(Item(22, 4 - C div 2));
      if Spr <> nil then
        for K := 0 to High(Entries) do
        begin
          N := Entries[K] shr 16;
          if A.SpriteRect(N, SX, SY, SW, SH) then
            Screen.Blit(Spr, SX, SY, SW, SH,
              Round((B.X + ShortInt((Entries[K] shr 8) and 255) / 8) * 16) - CamX,
              Round((B.Y + ShortInt(Entries[K] and 255) / 8) * 16) - CamY);
        end;
    end;
  end;
end;

end.
