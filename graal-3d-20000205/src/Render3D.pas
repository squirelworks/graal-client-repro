{ Render3D: draws .x meshes into a GSurface.

  Graal3D draws with Direct3D Retained Mode through DelphiX (TDXDraw with
  do3D, doRetainedMode, doZBuffer, doTexture). Neither builds outside
  Windows or under Free Pascal, so this build has a small software
  renderer of its own with the same viewing rules:

  - The viewport is the library's initial one: field 0.5, front clipping
    plane 1, perspective, one scale on x and y taken from the longer pixel
    side (graal_analysis graal3d/camera.md). On the 640x456 view that is
    640 pixels per unit at distance 1.
  - Back plane: the February 2000 client was not read for it; 5000 is the
    figure a later DelphiX sets at retained-mode start. The shipped level
    is far larger than the library's 100, so 5000 is used.
  - A z-buffer, textures wrapped (the level's coordinates run past 1),
    nearest texel, perspective-correct.
  - Light: flat per face, an ambient part and one directional part. The
    lights the original sets up were not traced; these values are this
    build's own.

  Faces are drawn from both sides. }
unit Render3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, Math3D, XFile3D;

type
  { Gives the full path of a texture file name, or ''. }
  TFindFile = function(const Name: string): string of object;

  TTextureCache = class
  private
    FNames: array of string;
    FSurfaces: array of TGSurface;
  public
    Find: TFindFile;
    destructor Destroy; override;
    procedure Clear;
    { The texture, loaded on first use; nil if it cannot be found. }
    function Get(const Name: string): TGSurface;
  end;

  TRenderer3D = class
  private
    FZ: array of Single; { 1/z per pixel; 0 = nothing drawn }
    FScale, FCX, FCY: Double;
    FRight, FUp, FFwd: TVec3;
  public
    Surface: TGSurface;
    Textures: TTextureCache;
    CamPos: TVec3;
    Front, Back: Double;
    Ambient, Diffuse: Double;
    LightDir: TVec3; { towards the light }
    Background: Cardinal;
    FacesDrawn: Integer;
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;
    { Points the camera along Dir (any length), with y up. }
    procedure LookAlong(const Dir: TVec3);
    procedure Clear;
    { Draws a mesh turned by Yaw degrees about y and moved to Pos. Color,
      when not $FFFFFFFF, replaces the material colour (the arm, hand and
      shoe props); Texture, when not '', replaces the material texture
      (the body and head texture props). }
    procedure DrawMesh(M: TMesh3D; const Pos: TVec3; Yaw: Double;
      Color: Cardinal; const Texture: string);
    { The screen point of a world point; False when it is behind the front
      plane. }
    function Project(const P: TVec3; out SX, SY: Double): Boolean;
  end;

implementation

uses
  SysUtils;

{ TTextureCache }

destructor TTextureCache.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TTextureCache.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FSurfaces) do FSurfaces[I].Free;
  SetLength(FSurfaces, 0);
  SetLength(FNames, 0);
end;

function TTextureCache.Get(const Name: string): TGSurface;
var
  I: Integer;
  Key, Path: string;
  S: TGSurface;
begin
  Result := nil;
  if Name = '' then Exit;
  Key := LowerCase(Name);
  for I := 0 to High(FNames) do
    if FNames[I] = Key then
    begin
      Result := FSurfaces[I];
      Exit;
    end;
  S := nil;
  if Assigned(Find) then Path := Find(Name) else Path := '';
  if Path <> '' then
  begin
    S := TGSurface.Create(0, 0);
    if not LoadImageFile(Path, S) or (S.Width <= 0) or (S.Height <= 0) then
      FreeAndNil(S);
  end;
  SetLength(FNames, Length(FNames) + 1);
  SetLength(FSurfaces, Length(FSurfaces) + 1);
  FNames[High(FNames)] := Key;
  FSurfaces[High(FSurfaces)] := S;
  Result := S;
end;

{ TRenderer3D }

type
  TCV = record
    X, Y, Z: Double; { camera space }
    U, V: Double;
  end;
  TPoly = array[0..71] of TCV;

constructor TRenderer3D.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Surface := TGSurface.Create(AWidth, AHeight);
  Textures := TTextureCache.Create;
  SetLength(FZ, AWidth * AHeight);
  if AWidth > AHeight then FScale := AWidth else FScale := AHeight;
  FCX := AWidth / 2;
  FCY := AHeight / 2;
  Front := 1;
  Back := 5000;
  Ambient := 0.55;
  Diffuse := 0.55;
  LightDir := VNorm(V3(0.4, 1.0, -0.6));
  Background := $FF000000;
  LookAlong(V3(0, 0, 1));
end;

destructor TRenderer3D.Destroy;
begin
  Textures.Free;
  Surface.Free;
  inherited Destroy;
end;

procedure TRenderer3D.LookAlong(const Dir: TVec3);
var
  F: TVec3;
begin
  F := VNorm(Dir);
  if VLen(F) < 0.5 then F := V3(0, 0, 1);
  { left-handed: right = up x forward }
  FRight := VNorm(VCross(V3(0, 1, 0), F));
  if VLen(FRight) < 0.5 then FRight := V3(1, 0, 0);
  FUp := VCross(F, FRight);
  FFwd := F;
end;

procedure TRenderer3D.Clear;
var
  I: Integer;
begin
  Surface.Fill(Background);
  for I := 0 to High(FZ) do FZ[I] := 0;
  FacesDrawn := 0;
end;

function TRenderer3D.Project(const P: TVec3; out SX, SY: Double): Boolean;
var
  D: TVec3;
  Z: Double;
begin
  D := VSub(P, CamPos);
  Z := VDot(D, FFwd);
  Result := Z >= Front;
  if not Result then
  begin
    SX := 0;
    SY := 0;
    Exit;
  end;
  SX := FCX + VDot(D, FRight) / Z * FScale;
  SY := FCY - VDot(D, FUp) / Z * FScale;
end;

function Floor0(D: Double): Double;
begin
  Result := Int(D);
  if D < Result then Result := Result - 1;
end;

function Shade(C: Cardinal; L, ER, EG, EB, MR, MG, MB: Double): Cardinal;
var
  R, G, B: Integer;
begin
  R := Round(((C shr 16) and $FF) * MR * L + ER * 255);
  G := Round(((C shr 8) and $FF) * MG * L + EG * 255);
  B := Round((C and $FF) * MB * L + EB * 255);
  if R > 255 then R := 255;
  if G > 255 then G := 255;
  if B > 255 then B := 255;
  if R < 0 then R := 0;
  if G < 0 then G := 0;
  if B < 0 then B := 0;
  Result := $FF000000 or Cardinal(R shl 16) or Cardinal(G shl 8) or Cardinal(B);
end;

procedure TRenderer3D.DrawMesh(M: TMesh3D; const Pos: TVec3; Yaw: Double;
  Color: Cardinal; const Texture: string);
var
  F, I, J, N, NC, X, Y, X0, X1, Y0, Y1, W, H: Integer;
  Poly, Clip: TPoly;
  P, Nrm, A, B, C: TVec3;
  Mat: TMaterial3D;
  Tex: TGSurface;
  L, MR, MG, MB, T: Double;
  SX, SY, SW, SU, SV: array[0..2] of Double;
  Area, W0, W1, W2, IW, IU, IV, PX, PY, U, V, MinW: Double;
  Flat: Cardinal;
  TX, TY, Idx: Integer;
begin
  if M = nil then Exit;
  W := Surface.Width;
  H := Surface.Height;
  MinW := 1 / Back;
  for F := 0 to M.FaceCount - 1 do
  begin
    N := Length(M.Faces[F].Idx);
    if (N < 3) or (N > 64) then Continue;
    { world corners -> camera space }
    for I := 0 to N - 1 do
    begin
      P := VAdd(RotY(M.Verts[M.Faces[F].Idx[I]], Yaw), Pos);
      if I = 0 then A := P else if I = 1 then B := P else if I = 2 then C := P;
      P := VSub(P, CamPos);
      Poly[I].X := VDot(P, FRight);
      Poly[I].Y := VDot(P, FUp);
      Poly[I].Z := VDot(P, FFwd);
      Poly[I].U := M.U[M.Faces[F].Idx[I]];
      Poly[I].V := M.V[M.Faces[F].Idx[I]];
    end;
    { clip against the front plane }
    NC := 0;
    for I := 0 to N - 1 do
    begin
      J := (I + 1) mod N;
      if Poly[I].Z >= Front then
      begin
        Clip[NC] := Poly[I];
        Inc(NC);
      end;
      if (Poly[I].Z >= Front) <> (Poly[J].Z >= Front) then
      begin
        T := (Front - Poly[I].Z) / (Poly[J].Z - Poly[I].Z);
        Clip[NC].X := Poly[I].X + (Poly[J].X - Poly[I].X) * T;
        Clip[NC].Y := Poly[I].Y + (Poly[J].Y - Poly[I].Y) * T;
        Clip[NC].Z := Front;
        Clip[NC].U := Poly[I].U + (Poly[J].U - Poly[I].U) * T;
        Clip[NC].V := Poly[I].V + (Poly[J].V - Poly[I].V) * T;
        Inc(NC);
      end;
    end;
    if NC < 3 then Continue;
    { light and material }
    Nrm := VNorm(VCross(VSub(B, A), VSub(C, A)));
    L := Abs(VDot(Nrm, LightDir));
    L := Ambient + Diffuse * L;
    Mat := M.Materials[M.Faces[F].Mat];
    if Color <> $FFFFFFFF then
    begin
      MR := ((Color shr 16) and $FF) / 255;
      MG := ((Color shr 8) and $FF) / 255;
      MB := (Color and $FF) / 255;
    end
    else
    begin
      MR := Mat.R;
      MG := Mat.G;
      MB := Mat.B;
    end;
    if (Texture <> '') and (Mat.Texture <> '') then Tex := Textures.Get(Texture)
    else Tex := Textures.Get(Mat.Texture);
    { a textured face whose texture file is missing is drawn in a light
      grey rather than white, so its shape still shows (this build) }
    if (Tex = nil) and (Mat.Texture <> '') then Flat := Shade($B0B0B0, L, Mat.ER, Mat.EG, Mat.EB, MR, MG, MB)
    else Flat := Shade($FFFFFF, L, Mat.ER, Mat.EG, Mat.EB, MR, MG, MB);
    Inc(FacesDrawn);
    { fan of triangles }
    for I := 1 to NC - 2 do
    begin
      for J := 0 to 2 do
      begin
        if J = 0 then Idx := 0 else Idx := I + J - 1;
        SW[J] := 1 / Clip[Idx].Z;
        SX[J] := FCX + Clip[Idx].X * SW[J] * FScale;
        SY[J] := FCY - Clip[Idx].Y * SW[J] * FScale;
        SU[J] := Clip[Idx].U * SW[J];
        SV[J] := Clip[Idx].V * SW[J];
      end;
      Area := (SX[1] - SX[0]) * (SY[2] - SY[0]) - (SX[2] - SX[0]) * (SY[1] - SY[0]);
      if Abs(Area) < 1E-9 then Continue;
      X0 := Trunc(SX[0]); X1 := X0; Y0 := Trunc(SY[0]); Y1 := Y0;
      for J := 1 to 2 do
      begin
        if SX[J] < X0 then X0 := Trunc(SX[J]) - 1;
        if SX[J] > X1 then X1 := Trunc(SX[J]) + 1;
        if SY[J] < Y0 then Y0 := Trunc(SY[J]) - 1;
        if SY[J] > Y1 then Y1 := Trunc(SY[J]) + 1;
      end;
      if X0 < 0 then X0 := 0;
      if Y0 < 0 then Y0 := 0;
      if X1 > W - 1 then X1 := W - 1;
      if Y1 > H - 1 then Y1 := H - 1;
      for Y := Y0 to Y1 do
      begin
        PY := Y + 0.5;
        for X := X0 to X1 do
        begin
          PX := X + 0.5;
          W0 := ((SX[1] - PX) * (SY[2] - PY) - (SX[2] - PX) * (SY[1] - PY)) / Area;
          W1 := ((SX[2] - PX) * (SY[0] - PY) - (SX[0] - PX) * (SY[2] - PY)) / Area;
          W2 := 1 - W0 - W1;
          if (W0 < 0) or (W1 < 0) or (W2 < 0) then Continue;
          IW := W0 * SW[0] + W1 * SW[1] + W2 * SW[2];
          if (IW < MinW) or (IW <= FZ[X + Y * W]) then Continue;
          FZ[X + Y * W] := IW;
          if Tex = nil then
            Surface.Pixels[X + Y * W] := Flat
          else
          begin
            IU := W0 * SU[0] + W1 * SU[1] + W2 * SU[2];
            IV := W0 * SV[0] + W1 * SV[1] + W2 * SV[2];
            U := IU / IW;
            V := IV / IW;
            TX := Trunc((U - Floor0(U)) * Tex.Width);
            TY := Trunc((V - Floor0(V)) * Tex.Height);
            if TX >= Tex.Width then TX := Tex.Width - 1;
            if TY >= Tex.Height then TY := Tex.Height - 1;
            if TX < 0 then TX := 0;
            if TY < 0 then TY := 0;
            Surface.Pixels[X + Y * W] := Shade(Tex.Pixels[TX + TY * Tex.Width], L,
              Mat.ER, Mat.EG, Mat.EB, MR, MG, MB);
          end;
        end;
      end;
    end;
  end;
end;

end.
