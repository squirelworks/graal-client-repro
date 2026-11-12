{ Move39: 39ster's player movement and collision.

  From Graal_analysis client-internals/precursor-mechanics-2026-11-09.md
  ("Collision and movement", evidence GRAAL39STER-ENGINE-20261109-01). The
  notes read these rules from the original's script; none of the numbers
  was checked at run time on the original.

  - A rectangle outside the level is blocked.
  - Edge scan: the left and top edges truncate, the right and bottom edges
    round up, and the end is exclusive, so a zero-width edge that sits on a
    tile boundary covers no tile.
  - 3 pixels per nominal update (2 when getting up from sitting); each
    component of a diagonal move is multiplied by 0.75; everything is
    scaled by the time factor.
  - The vertical move is resolved before the horizontal one, and a blocked
    component shrinks 1 pixel at a time.
  - With one axis pressed, a fully blocked move slides along the other
    axis at 1.5 x the time factor, toward a 16-pixel boundary, and snaps to
    it.

  The notes do not say which way the slide prefers or how big the player's
  box is. This port prefers the nearer 16-pixel boundary on the other axis
  (ties go to the lower one), takes the farther one only when the nearer
  one would still be blocked, and does not slide when already on a
  boundary. The box is the 16-pixel anchor the camera centres on. Both are
  this port's reading and are marked as such in the README. }
unit Move39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { the player's collision box: the 16-pixel anchor }
  PlayerBox = 16;

type
  { True if board tile (TX, TY) is a wall. Only called for tiles inside
    the level. }
  TWallTest39 = function(TX, TY: Integer): Boolean of object;

{ True if the rectangle X, Y, W, H (level pixels) touches a wall tile or
  leaves a level of LevelW x LevelH pixels. }
function RectBlocked(Wall: TWallTest39; X, Y, W, H: Double;
  LevelW, LevelH: Integer): Boolean;

{ One update of movement for the box at (X, Y). DX and DY are the held
  directions (-1, 0 or 1), TF the time factor and Step the pixels per
  nominal update (MoveStep, or GetUpStep). Returns True if the box moved. }
function MovePlayer(Wall: TWallTest39; var X, Y: Double; DX, DY: Integer;
  TF, Step: Double; LevelW, LevelH: Integer): Boolean;

implementation

uses
  Math, Profile39;

function RectBlocked(Wall: TWallTest39; X, Y, W, H: Double;
  LevelW, LevelH: Integer): Boolean;
var
  TX0, TY0, TX1, TY1, TX, TY: Integer;
begin
  Result := True;
  if (X < 0) or (Y < 0) or (X + W > LevelW) or (Y + H > LevelH) then Exit;
  TX0 := Trunc(X / TilePx);
  TY0 := Trunc(Y / TilePx);
  TX1 := Ceil((X + W) / TilePx);   { exclusive }
  TY1 := Ceil((Y + H) / TilePx);
  for TY := TY0 to TY1 - 1 do
    for TX := TX0 to TX1 - 1 do
      if Wall(TX, TY) then Exit;
  Result := False;
end;

{ Shrinks D toward 0 one pixel at a time until the box moved by D along
  the axis is free. }
function Resolve(Wall: TWallTest39; X, Y, D: Double; Vertical: Boolean;
  LevelW, LevelH: Integer): Double;

  function Blocked(V: Double): Boolean;
  begin
    if Vertical then
      Result := RectBlocked(Wall, X, Y + V, PlayerBox, PlayerBox, LevelW, LevelH)
    else
      Result := RectBlocked(Wall, X + V, Y, PlayerBox, PlayerBox, LevelW, LevelH);
  end;

begin
  Result := D;
  while (Result <> 0) and Blocked(Result) do
    if Abs(Result) <= 1 then Result := 0
    else if Result > 0 then Result := Result - 1
    else Result := Result + 1;
end;

{ The slide for a single-axis move of Dir along one axis that was fully
  blocked, from the box at (X, Y). Returns the signed
  slide along the other axis, or 0. }
function Slide(Wall: TWallTest39; X, Y: Double; Dir: Integer; Vertical: Boolean;
  TF: Double; LevelW, LevelH: Integer): Double;
var
  P, Off, Lo, Hi, Speed: Double;
  Targets: array[0..1] of Double;
  I: Integer;

  { is the forward move free with the other axis at Q? }
  function ClearAt(Q: Double): Boolean;
  begin
    if Vertical then
      Result := not RectBlocked(Wall, Q, Y + Dir, PlayerBox, PlayerBox, LevelW, LevelH)
    else
      Result := not RectBlocked(Wall, X + Dir, Q, PlayerBox, PlayerBox, LevelW, LevelH);
  end;

  { can the box move along the other axis from P to Q? }
  function CanShift(Q: Double): Boolean;
  begin
    if Vertical then
      Result := not RectBlocked(Wall, Q, Y, PlayerBox, PlayerBox, LevelW, LevelH)
    else
      Result := not RectBlocked(Wall, X, Q, PlayerBox, PlayerBox, LevelW, LevelH);
  end;

begin
  Result := 0;
  if Vertical then P := X else P := Y;
  Off := P - Floor(P / TilePx) * TilePx;
  if Off = 0 then Exit;
  Lo := P - Off;
  Hi := Lo + TilePx;
  if Off <= TilePx / 2 then
  begin
    Targets[0] := Lo;
    Targets[1] := Hi;
  end
  else
  begin
    Targets[0] := Hi;
    Targets[1] := Lo;
  end;
  Speed := SlideScale * TF;
  for I := 0 to 1 do
    if ClearAt(Targets[I]) and CanShift(Targets[I]) then
    begin
      if Abs(Targets[I] - P) <= Speed then Result := Targets[I] - P   { snap }
      else if Targets[I] > P then Result := Speed
      else Result := -Speed;
      Exit;
    end;
end;

function MovePlayer(Wall: TWallTest39; var X, Y: Double; DX, DY: Integer;
  TF, Step: Double; LevelW, LevelH: Integer): Boolean;
var
  Speed, VX, VY, S: Double;
begin
  Result := False;
  if (DX = 0) and (DY = 0) then Exit;
  Speed := Step * TF;
  VX := DX * Speed;
  VY := DY * Speed;
  if (DX <> 0) and (DY <> 0) then
  begin
    VX := VX * DiagonalScale;
    VY := VY * DiagonalScale;
  end;
  { vertical first, then horizontal from the new row }
  VY := Resolve(Wall, X, Y, VY, True, LevelW, LevelH);
  Y := Y + VY;
  VX := Resolve(Wall, X, Y, VX, False, LevelW, LevelH);
  X := X + VX;
  Result := (VX <> 0) or (VY <> 0);
  if Result then Exit;
  { one axis held and fully blocked: slide along the other one }
  if (DX = 0) and (DY <> 0) then
  begin
    S := Slide(Wall, X, Y, DY, True, TF, LevelW, LevelH);
    X := X + S;
    Result := S <> 0;
  end
  else if (DY = 0) and (DX <> 0) then
  begin
    S := Slide(Wall, X, Y, DX, False, TF, LevelW, LevelH);
    Y := Y + S;
    Result := S <> 0;
  end;
end;

end.
