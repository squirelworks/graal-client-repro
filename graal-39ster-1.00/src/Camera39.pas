{ Camera39: where 39ster's view sits over a level.

  From Graal_analysis client-internals/precursor-mechanics-2026-11-09.md
  ("Start and drawing"): the camera centres on a 16-pixel anchor and is
  clamped to the level; a level smaller than the window is centred. }
unit Camera39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ The level pixel at the view's top-left (may be negative when the level is
  smaller than the view and is centred) for an anchor at (AX, AY), a level
  of LevelW x LevelH pixels and a view of ViewW x ViewH. The anchor is the
  top-left of a 16-pixel box; its centre is put at the view's centre. }
procedure CameraOrigin(AX, AY, LevelW, LevelH, ViewW, ViewH: Integer;
  out OX, OY: Integer);

implementation

function Axis(A, LevelSize, ViewSize: Integer): Integer;
begin
  if LevelSize <= ViewSize then
  begin
    { smaller than the view: centred }
    Result := -((ViewSize - LevelSize) div 2);
    Exit;
  end;
  Result := A + 8 - ViewSize div 2;
  if Result < 0 then Result := 0;
  if Result > LevelSize - ViewSize then Result := LevelSize - ViewSize;
end;

procedure CameraOrigin(AX, AY, LevelW, LevelH, ViewW, ViewH: Integer;
  out OX, OY: Integer);
begin
  OX := Axis(AX, LevelW, ViewW);
  OY := Axis(AY, LevelH, ViewH);
end;

end.
