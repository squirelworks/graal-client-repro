{ GClamp: Math.EnsureRange for Delphi 5.

  The folder sources clamped values with Math.EnsureRange, which came in
  Delphi 6. These two functions do the same: a value below Lo gives Lo,
  above Hi gives Hi, anything else (a NaN too) comes back unchanged.
  Issue #114. }
unit GClamp;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

function ClampInt(V, Lo, Hi: Integer): Integer;
function ClampNum(V, Lo, Hi: Double): Double;

implementation

function ClampInt(V, Lo, Hi: Integer): Integer;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

function ClampNum(V, Lo, Hi: Double): Double;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

end.
