{ World3D: the Graal3D level, the local player's movement, the follow
  camera, other players and the chat log.

  Numbers from graal_analysis graal3d/client-behaviour.md, collision.md and
  camera.md (static reads of the February 2000 client). One tick is the
  original's 50 ms timer. Where those notes leave a choice open, the
  choice made here is marked "this build" in the comments.

  Walking: 8 units a tick, x1.5 after 25 ticks without stopping. Forward
  and back follow the camera's view, the side keys step at right angles to
  it. Back alone walks backwards along the facing the player had when the
  key went down. The world is +-4000 on x and z; a step that would leave
  it is dropped.

  Jumping: up by 10, 10, 9, 8, 6, 3, 1, then down by 1, 3, 6, 8, 9, 10 and
  10 a tick until landing. Letting go early starts the fall at once.

  Collision: four feet probes (+-5 along the facing and the side axis) and
  three upper probes 35 up (0 and +-10 on the side axis). Faces whose
  normal points up are floors: a floor up to 30 above the feet is stepped
  onto. Other faces are walls: a probe less than 3 in front of one, that
  was not more than 5 behind it before the step, is slid back onto its
  plane.

  Camera: stays about 220 behind and 80 above, closing the gap by
  ((d - 220) / 220)^2 / 10 a tick, y by a tenth of the difference, looks
  at the player and pitches 0.15 rad. Numpad 0 turns the follow off and
  on.

  Chat: a log of "nickname: text" lines at the bottom left, each kept 200
  ticks (10 s); there are no chat bubbles in Graal3D. }
unit World3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Math3D, XFile3D, Render3D, Codec3D, GSurface;

const
  WalkSpeed = 8;
  RunAfter = 25;
  RunFactor = 1.5;
  WorldLimit = 4000;
  StepHeight = 30;
  ProbeRadius = 5;
  UpperProbeY = 35;
  UpperProbeSpan = 10;
  WallClear = 3;
  WallInside = 5;
  BodyHeight = 49; { top of the stand-in and original heads; this build }
  CamDistance = 220;
  CamHeight = 80;
  CamPitch = 0.15;
  ChatTicks = 200;
  ViewW = 640;
  ViewH = 456;
  JumpUp: array[0..6] of Integer = (10, 10, 9, 8, 6, 3, 1);
  JumpDown: array[0..5] of Integer = (1, 3, 6, 8, 9, 10);

type
  TColFace = record
    P: array of TVec3;
    N: TVec3;
    Floor: Boolean;
  end;

  TLevel3D = class
  public
    Name: string;
    Scene: TXScene;
    Faces: array of TColFace;
    constructor Create;
    destructor Destroy; override;
    { Loads the .x text; False (and an empty level) if it does not parse. }
    function Load(const AName, Text: string): Boolean;
    { The highest floor under (X, Z) that is at most MaxY, or False. }
    function FloorAt(X, Z, MaxY: Double; out H: Double): Boolean;
  end;

  TInput3D = record
    Fwd, Back, Left, Right, Jump: Boolean;
    CameraToggle: Boolean; { pressed this tick }
  end;

  { The eight model files and their textures, loaded once. }
  TFindPath = function(const Name: string): string of object;

  TModels3D = class
  private
    FNames: array of string;
    FScenes: array of TXScene;
  public
    Find: TFindPath;
    UsedBuiltin: Boolean;
    destructor Destroy; override;
    function Get(const Name: string): TMesh3D;
  end;

  TPlayer3D = class
  public
    P: TProps3D;
    LastChat: string;
    constructor Create;
  end;

  TChatLine = record
    Text: string;
    Until_: Integer;
  end;

  TWorld3D = class
  private
    FWalking: Boolean;
    FWalkTicks: Integer;
    FJumpPhase: Integer; { 0 on the ground or idle, 1 rising, 2 falling }
    FJumpIdx: Integer;
    FJumpLatch: Boolean; { the jump key must be let go between jumps }
    FBackDir: TVec3;
    FBackHeld: Boolean;
    function Blocked(const Old: TVec3; var Cand: TVec3; const Fwd, Side: TVec3): Boolean;
  public
    Level: TLevel3D;
    Me: TProps3D;
    OnGround: Boolean;
    Cam: TVec3;
    CamFollow: Boolean;
    Others: array of TPlayer3D;
    Chat: array of TChatLine;
    Tick: Integer;
    Models: TModels3D;
    constructor Create;
    destructor Destroy; override;
    { Puts the camera behind the player (after a level load or a move from
      the server). }
    procedure ResetCamera;
    procedure Step(const I: TInput3D);
    procedure AddChat(const Line: string);
    function FindPlayer(Id: Integer): TPlayer3D;
    function AddPlayer(Id: Integer): TPlayer3D;
    procedure RemovePlayer(Id: Integer);
    procedure Draw(R: TRenderer3D);
  end;

implementation

uses
  SysUtils, Builtin3D;

{ TLevel3D }

constructor TLevel3D.Create;
begin
  inherited Create;
  Scene := TXScene.Create;
end;

destructor TLevel3D.Destroy;
begin
  Scene.Free;
  inherited Destroy;
end;

function TLevel3D.Load(const AName, Text: string): Boolean;
var
  M, F, I, N: Integer;
  Mesh: TMesh3D;
begin
  Name := AName;
  SetLength(Faces, 0);
  Result := Scene.LoadFromString(Text);
  if not Result then Exit;
  N := 0;
  for M := 0 to Scene.Count - 1 do Inc(N, Scene.Mesh(M).FaceCount);
  SetLength(Faces, N);
  N := 0;
  for M := 0 to Scene.Count - 1 do
  begin
    Mesh := Scene.Mesh(M);
    for F := 0 to Mesh.FaceCount - 1 do
    begin
      SetLength(Faces[N].P, Length(Mesh.Faces[F].Idx));
      for I := 0 to High(Mesh.Faces[F].Idx) do
        Faces[N].P[I] := Mesh.Verts[Mesh.Faces[F].Idx[I]];
      Faces[N].N := Mesh.FaceNormal(F);
      Faces[N].Floor := Faces[N].N.Y > 0;
      if VLen(Faces[N].N) > 0.5 then Inc(N);
    end;
  end;
  SetLength(Faces, N);
end;

{ The over-face test: (X, Z) inside the face seen from above. Both
  windings are accepted. }
function OverFace(const F: TColFace; X, Z: Double): Boolean;
var
  I, J: Integer;
  C: Double;
  Pos, Neg: Boolean;
begin
  Pos := False;
  Neg := False;
  for I := 0 to High(F.P) do
  begin
    J := (I + 1) mod Length(F.P);
    C := (F.P[J].X - F.P[I].X) * (Z - F.P[I].Z) - (F.P[J].Z - F.P[I].Z) * (X - F.P[I].X);
    if C > 0 then Pos := True else if C < 0 then Neg := True;
    if Pos and Neg then
    begin
      Result := False;
      Exit;
    end;
  end;
  Result := True;
end;

function PlaneY(const F: TColFace; X, Z: Double): Double;
begin
  Result := F.P[0].Y - (F.N.X * (X - F.P[0].X) + F.N.Z * (Z - F.P[0].Z)) / F.N.Y;
end;

function TLevel3D.FloorAt(X, Z, MaxY: Double; out H: Double): Boolean;
var
  I: Integer;
  Y: Double;
begin
  Result := False;
  H := 0;
  for I := 0 to High(Faces) do
    if Faces[I].Floor and (Faces[I].N.Y > 1E-6) and OverFace(Faces[I], X, Z) then
    begin
      Y := PlaneY(Faces[I], X, Z);
      if (Y <= MaxY) and (not Result or (Y > H)) then
      begin
        H := Y;
        Result := True;
      end;
    end;
end;

{ A wall is hit only where the probe, pushed onto the wall's plane, falls
  inside the face (with a probe radius of slack). The notes give the
  over-face test from above for floors; for an upright wall that test has
  no area, so this build tests on the plane itself. }
function OnWall(const F: TColFace; const Q: TVec3): Boolean;
var
  I, J: Integer;
  E, W, C: TVec3;
  D: Double;
begin
  Result := True;
  for I := 0 to High(F.P) do
  begin
    J := (I + 1) mod Length(F.P);
    E := VSub(F.P[J], F.P[I]);
    W := VSub(Q, F.P[I]);
    C := VCross(E, W);
    D := VDot(C, F.N);
    if VLen(E) > 1E-9 then D := D / VLen(E);
    if D < -ProbeRadius then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ TModels3D }

destructor TModels3D.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FScenes) do FScenes[I].Free;
  inherited Destroy;
end;

function TModels3D.Get(const Name: string): TMesh3D;
var
  I: Integer;
  Key, Path: string;
  S: TXScene;
begin
  Result := nil;
  Key := LowerCase(Name);
  for I := 0 to High(FNames) do
    if FNames[I] = Key then
    begin
      if FScenes[I].Count > 0 then Result := FScenes[I].Mesh(0);
      Exit;
    end;
  S := TXScene.Create;
  if Assigned(Find) then Path := Find(Name) else Path := '';
  if (Path = '') or not S.LoadFromFile(Path) then
  begin
    if S.LoadFromString(BuiltinModel(Name)) then UsedBuiltin := True;
  end;
  SetLength(FNames, Length(FNames) + 1);
  SetLength(FScenes, Length(FScenes) + 1);
  FNames[High(FNames)] := Key;
  FScenes[High(FScenes)] := S;
  if S.Count > 0 then Result := S.Mesh(0);
end;

{ TPlayer3D }

constructor TPlayer3D.Create;
begin
  inherited Create;
  DefaultProps(P);
end;

{ TWorld3D }

constructor TWorld3D.Create;
begin
  inherited Create;
  Level := TLevel3D.Create;
  Models := TModels3D.Create;
  DefaultProps(Me);
  CamFollow := True;
  OnGround := True;
  ResetCamera;
end;

destructor TWorld3D.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Others) do Others[I].Free;
  Models.Free;
  Level.Free;
  inherited Destroy;
end;

procedure TWorld3D.ResetCamera;
var
  D: TVec3;
begin
  D := DirOf(Me.Angle);
  Cam := V3(Me.X - D.X * CamDistance, Me.Y + CamHeight, Me.Z - D.Z * CamDistance);
end;

procedure TWorld3D.AddChat(const Line: string);
var
  I: Integer;
begin
  { the oldest go first when the log is full; 24 lines fill the view }
  if Length(Chat) >= 24 then
  begin
    for I := 1 to High(Chat) do Chat[I - 1] := Chat[I];
    SetLength(Chat, Length(Chat) - 1);
  end;
  SetLength(Chat, Length(Chat) + 1);
  Chat[High(Chat)].Text := Line;
  Chat[High(Chat)].Until_ := Tick + ChatTicks;
end;

function TWorld3D.FindPlayer(Id: Integer): TPlayer3D;
var
  I: Integer;
begin
  for I := 0 to High(Others) do
    if Others[I].P.Id = Id then
    begin
      Result := Others[I];
      Exit;
    end;
  Result := nil;
end;

function TWorld3D.AddPlayer(Id: Integer): TPlayer3D;
begin
  Result := FindPlayer(Id);
  if Result <> nil then Exit;
  Result := TPlayer3D.Create;
  Result.P.Id := Id;
  SetLength(Others, Length(Others) + 1);
  Others[High(Others)] := Result;
end;

procedure TWorld3D.RemovePlayer(Id: Integer);
var
  I, J: Integer;
begin
  for I := 0 to High(Others) do
    if Others[I].P.Id = Id then
    begin
      Others[I].Free;
      for J := I + 1 to High(Others) do Others[J - 1] := Others[J];
      SetLength(Others, Length(Others) - 1);
      Exit;
    end;
end;

function TWorld3D.Blocked(const Old: TVec3; var Cand: TVec3; const Fwd, Side: TVec3): Boolean;
var
  Offs: array[0..6] of TVec3;
  K, F: Integer;
  Q, QOld, Move, Lift: TVec3;
  D1, D0, H: Double;
begin
  Result := False;
  Offs[0] := VScale(Fwd, ProbeRadius);
  Offs[1] := VScale(Fwd, -ProbeRadius);
  Offs[2] := VScale(Side, ProbeRadius);
  Offs[3] := VScale(Side, -ProbeRadius);
  Offs[4] := V3(0, UpperProbeY, 0);
  Offs[5] := VAdd(V3(0, UpperProbeY, 0), VScale(Side, UpperProbeSpan));
  Offs[6] := VAdd(V3(0, UpperProbeY, 0), VScale(Side, -UpperProbeSpan));
  Move := VSub(Cand, Old);
  if VDot(Move, Move) <= 0 then Exit;
  { walls, every probe. The feet probes test walls a step above the feet,
    so the side of a step up to 30 high is climbed rather than slid along
    (this build: the notes give the step height, not where the feet
    probes meet walls) }
  for K := 0 to 6 do
    for F := 0 to High(Level.Faces) do
    begin
      if Level.Faces[F].Floor then Continue;
      if K < 4 then Lift := V3(0, StepHeight + 1, 0) else Lift := V3(0, 0, 0);
      Q := VAdd(VAdd(Cand, Offs[K]), Lift);
      QOld := VAdd(VAdd(Old, Offs[K]), Lift);
      D1 := VDot(VSub(Q, Level.Faces[F].P[0]), Level.Faces[F].N);
      if D1 >= WallClear then Continue;
      D0 := VDot(VSub(QOld, Level.Faces[F].P[0]), Level.Faces[F].N);
      if D0 < -WallInside then Continue;
      if not OnWall(Level.Faces[F], VSub(Q, VScale(Level.Faces[F].N, D1))) then Continue;
      { slide onto the plane }
      Cand := VSub(Cand, VScale(Level.Faces[F].N, D1));
    end;
  { a floor more than a step above the feet but below the head is a ledge
    that cannot be climbed (this build's reading of the step rule) }
  for K := 0 to 3 do
  begin
    Q := VAdd(Cand, Offs[K]);
    if Level.FloorAt(Q.X, Q.Z, Old.Y + BodyHeight, H) and (H > Old.Y + StepHeight) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TWorld3D.Step(const I: TInput3D);
var
  Fwd, Side, Move, Old, Cand: TVec3;
  Moving, WasWalking: Boolean;
  Speed, DY, H, Best, D, Fac: Double;
  K: Integer;
  Found: Boolean;
  Pos, Q: TVec3;
begin
  Inc(Tick);
  { view direction on the ground plane }
  Fwd := VNorm(V3(Me.X - Cam.X, 0, Me.Z - Cam.Z));
  if VLen(Fwd) < 0.5 then Fwd := DirOf(Me.Angle);
  Side := V3(Fwd.Z, 0, -Fwd.X); { to the right of Fwd }
  { back alone: the facing when the key went down }
  if I.Back and not FBackHeld then FBackDir := DirOf(Me.Angle);
  FBackHeld := I.Back;
  Move := V3(0, 0, 0);
  if I.Fwd then Move := VAdd(Move, Fwd);
  if I.Back then
  begin
    if I.Fwd or I.Left or I.Right then Move := VSub(Move, Fwd)
    else Move := VScale(FBackDir, -1);
  end;
  if I.Left then Move := VSub(Move, Side);
  if I.Right then Move := VAdd(Move, Side);
  Moving := VLen(Move) > 0.01;
  WasWalking := FWalking;
  FWalking := Moving;
  if Moving then
  begin
    if not WasWalking then
    begin
      FWalkTicks := 0;
      { start at 0 or 20, so two players do not step in time }
      if Random(2) = 0 then Me.Anim := 0 else Me.Anim := 20;
    end;
    Inc(FWalkTicks);
    Speed := WalkSpeed;
    if FWalkTicks > RunAfter then Speed := WalkSpeed * RunFactor;
    Move := VScale(VNorm(Move), Speed);
    if OnGround then Me.Anim := (Me.Anim + 1) mod 40;
  end
  else
    FWalkTicks := 0;
  { jump }
  if not I.Jump then FJumpLatch := False;
  if I.Jump and not FJumpLatch and OnGround and (FJumpPhase = 0) then
  begin
    FJumpLatch := True;
    FJumpPhase := 1;
    FJumpIdx := 0;
    OnGround := False;
    Me.Anim := 40;
  end;
  DY := 0;
  if FJumpPhase = 1 then
  begin
    DY := JumpUp[FJumpIdx];
    Inc(FJumpIdx);
    if (FJumpIdx > High(JumpUp)) or not I.Jump then
    begin
      FJumpPhase := 2;
      FJumpIdx := 0;
    end;
  end
  else if FJumpPhase = 2 then
  begin
    if FJumpIdx <= High(JumpDown) then DY := -JumpDown[FJumpIdx] else DY := -10;
    Inc(FJumpIdx);
  end;
  if (FJumpPhase <> 0) and (Me.Anim >= 40) and (Me.Anim < 60) then Inc(Me.Anim);
  { the step }
  Old := V3(Me.X, Me.Y, Me.Z);
  Cand := V3(Old.X + Move.X, Old.Y + DY, Old.Z + Move.Z);
  if Blocked(Old, Cand, Fwd, Side) then
    Cand := V3(Old.X, Cand.Y, Old.Z);
  if (Abs(Cand.X) > WorldLimit) or (Abs(Cand.Z) > WorldLimit) then
    Cand := V3(Old.X, Cand.Y, Old.Z);
  { floors under the feet probes: the highest that is no more than a step
    above the feet }
  Found := False;
  Best := 0;
  for K := 0 to 4 do
  begin
    case K of
      0: Q := VAdd(Cand, VScale(Fwd, ProbeRadius));
      1: Q := VAdd(Cand, VScale(Fwd, -ProbeRadius));
      2: Q := VAdd(Cand, VScale(Side, ProbeRadius));
      3: Q := VAdd(Cand, VScale(Side, -ProbeRadius));
    else
      Q := Cand;
    end;
    if Level.FloorAt(Q.X, Q.Z, Old.Y + StepHeight, H) and (not Found or (H > Best)) then
    begin
      Best := H;
      Found := True;
    end;
  end;
  if FJumpPhase = 1 then
  begin
    if Found and (Cand.Y < Best) then Cand.Y := Best;
  end
  else if Found and (Cand.Y <= Best) then
  begin
    { landed, or walked up a step }
    Cand.Y := Best;
    OnGround := True;
    FJumpPhase := 0;
    if Me.Anim >= 40 then Me.Anim := 0;
  end
  else if Found and OnGround and (Cand.Y - Best <= StepHeight) then
    Cand.Y := Best { down a step or a slope, still on the ground }
  else
  begin
    if OnGround then
    begin
      { walked off an edge: the fall table from its top (this build) }
      OnGround := False;
      FJumpPhase := 2;
      FJumpIdx := 0;
    end;
    if Cand.Y < -WorldLimit then
    begin
      Cand.Y := -WorldLimit;
      OnGround := True;
      FJumpPhase := 0;
    end;
  end;
  Me.X := Cand.X;
  Me.Y := Cand.Y;
  Me.Z := Cand.Z;
  { the camera }
  if I.CameraToggle then CamFollow := not CamFollow;
  if CamFollow then
  begin
    D := Sqrt(Sqr(Me.X - Cam.X) + Sqr(Me.Z - Cam.Z));
    if D > 1E-6 then
    begin
      Fac := Sqr((D - CamDistance) / CamDistance) / 10;
      if D < CamDistance then Fac := -Fac;
      if (Fac <> 0) and (Abs(Fac) < 100) then
      begin
        Cam.X := Cam.X + (Me.X - Cam.X) * Fac;
        Cam.Z := Cam.Z + (Me.Z - Cam.Z) * Fac;
      end;
    end;
    Cam.Y := Cam.Y + (Me.Y + CamHeight - Cam.Y) / 10;
  end;
  { facing: the camera-to-player direction, sent as degrees / 2 }
  Pos := V3(Me.X - Cam.X, 0, Me.Z - Cam.Z);
  if VLen(Pos) > 1E-6 then Me.Angle := (Round(AngleOf(Pos.X, Pos.Z)) div 2) * 2;
  { the chat log }
  K := 0;
  while K < Length(Chat) do
    if Chat[K].Until_ <= Tick then
    begin
      Chat[K] := Chat[High(Chat)];
      SetLength(Chat, Length(Chat) - 1);
    end
    else
      Inc(K);
end;

procedure DrawPlayer(W: TWorld3D; R: TRenderer3D; const P: TProps3D; Walking: Boolean);
var
  Base: TVec3;
  Yaw, Bob: Double;
begin
  { the model's front is -z (the toes and the face point that way), so it
    is turned half a turn more than the facing; the part offsets are this
    build's, the eight files hold no frame layout }
  Yaw := P.Angle + 180;
  Bob := 0;
  if Walking then
    Bob := Abs(Sin(3.14 * 2 * (P.Anim - 1) / 40)) * 3;
  Base := V3(P.X, P.Y + Bob, P.Z);
  R.DrawMesh(W.Models.Get(P.BodyX), Base, Yaw, $FFFFFFFF, P.BodyTex);
  R.DrawMesh(W.Models.Get(P.HeadX), VAdd(Base, RotY(V3(0, 29, 0), Yaw)), Yaw, $FFFFFFFF, P.HeadTex);
  R.DrawMesh(W.Models.Get('armleft.x'), VAdd(Base, RotY(V3(0, 27, 0), Yaw)), Yaw, P.ArmColor, '');
  R.DrawMesh(W.Models.Get('armright.x'), VAdd(Base, RotY(V3(0, 27, 0), Yaw)), Yaw, P.ArmColor, '');
  R.DrawMesh(W.Models.Get('handleft.x'), VAdd(Base, RotY(V3(0, 27, 0), Yaw)), Yaw, P.HandColor, '');
  R.DrawMesh(W.Models.Get('handright.x'), VAdd(Base, RotY(V3(0, 27, 0), Yaw)), Yaw, P.HandColor, '');
  R.DrawMesh(W.Models.Get('footleft.x'), VAdd(Base, RotY(V3(5, 8, 0), Yaw)), Yaw, P.ShoeColor, '');
  R.DrawMesh(W.Models.Get('footright.x'), VAdd(Base, RotY(V3(-5, 8, 0), Yaw)), Yaw, P.ShoeColor, '');
end;

procedure TWorld3D.Draw(R: TRenderer3D);
var
  I: Integer;
  Dir: TVec3;
  E, HL: Double;
begin
  R.CamPos := Cam;
  { look at the player, then pitch up by 0.15 rad }
  Dir := VSub(V3(Me.X, Me.Y, Me.Z), Cam);
  HL := Sqrt(Sqr(Dir.X) + Sqr(Dir.Z));
  if HL < 1E-6 then
  begin
    Dir := DirOf(Me.Angle);
    HL := 1;
  end;
  E := ArcTan(Dir.Y / HL) + CamPitch;
  R.LookAlong(V3(Dir.X / HL * Cos(E), Sin(E), Dir.Z / HL * Cos(E)));
  R.Clear;
  for I := 0 to Level.Scene.Count - 1 do
    R.DrawMesh(Level.Scene.Mesh(I), V3(0, 0, 0), 0, $FFFFFFFF, '');
  DrawPlayer(Self, R, Me, FWalking and OnGround);
  for I := 0 to High(Others) do
    if Others[I].P.InLevel then
      DrawPlayer(Self, R, Others[I].P, False);
end;

end.
