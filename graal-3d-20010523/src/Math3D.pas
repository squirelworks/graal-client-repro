{ Math3D: vectors for the Graal3D world.

  Direct3D's frame of reference: x to the right, y up, z into the screen
  (left-handed). One unit is one Direct3D Retained Mode world unit. }
unit Math3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TVec3 = record
    X, Y, Z: Double;
  end;

function V3(X, Y, Z: Double): TVec3;
function VAdd(const A, B: TVec3): TVec3;
function VSub(const A, B: TVec3): TVec3;
function VScale(const A: TVec3; S: Double): TVec3;
function VDot(const A, B: TVec3): Double;
function VCross(const A, B: TVec3): TVec3;
function VLen(const A: TVec3): Double;
function VNorm(const A: TVec3): TVec3;
{ A horizontal direction for an angle in degrees: 0 is +z, 90 is +x. }
function DirOf(Degrees: Double): TVec3;
{ The angle (degrees, 0..360) of a horizontal direction, as DirOf. }
function AngleOf(DX, DZ: Double): Double;
{ Turns P about the y axis by Degrees, the same sense as DirOf. }
function RotY(const P: TVec3; Degrees: Double): TVec3;

implementation

function V3(X, Y, Z: Double): TVec3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function VAdd(const A, B: TVec3): TVec3;
begin
  Result := V3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function VSub(const A, B: TVec3): TVec3;
begin
  Result := V3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function VScale(const A: TVec3; S: Double): TVec3;
begin
  Result := V3(A.X * S, A.Y * S, A.Z * S);
end;

function VDot(const A, B: TVec3): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function VCross(const A, B: TVec3): TVec3;
begin
  Result := V3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
end;

function VLen(const A: TVec3): Double;
begin
  Result := Sqrt(VDot(A, A));
end;

function VNorm(const A: TVec3): TVec3;
var
  L: Double;
begin
  L := VLen(A);
  if L < 1E-9 then Result := V3(0, 0, 0)
  else Result := VScale(A, 1 / L);
end;

function DirOf(Degrees: Double): TVec3;
var
  R: Double;
begin
  R := Degrees * Pi / 180;
  Result := V3(Sin(R), 0, Cos(R));
end;

function AngleOf(DX, DZ: Double): Double;
begin
  if (Abs(DX) < 1E-12) and (Abs(DZ) < 1E-12) then
  begin
    Result := 0;
    Exit;
  end;
  { ArcTan2 is in Math; this keeps the unit to System only }
  if Abs(DZ) > Abs(DX) then
  begin
    Result := ArcTan(DX / DZ) * 180 / Pi;
    if DZ < 0 then Result := Result + 180;
  end
  else
  begin
    Result := 90 - ArcTan(DZ / DX) * 180 / Pi;
    if DX < 0 then Result := Result + 180;
  end;
  while Result < 0 do Result := Result + 360;
  while Result >= 360 do Result := Result - 360;
end;

function RotY(const P: TVec3; Degrees: Double): TVec3;
var
  R, C, S: Double;
begin
  R := Degrees * Pi / 180;
  C := Cos(R);
  S := Sin(R);
  { (0,0,1) goes to DirOf(Degrees); (1,0,0) goes to (cos, 0, -sin) }
  Result.X := P.X * C + P.Z * S;
  Result.Y := P.Y;
  Result.Z := -P.X * S + P.Z * C;
end;

end.
