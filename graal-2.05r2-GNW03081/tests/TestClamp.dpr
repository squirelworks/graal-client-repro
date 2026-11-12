{ GClamp checks (#114): ClampInt and ClampNum must give what
  Math.EnsureRange gives for the ranges the folder sources clamp to. }
program TestClamp;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Math,
  GClamp in '../../common/GClamp.pas';

var
  Passed, Failed: Integer;

procedure Check(OK: Boolean; const Name: string);
begin
  if OK then
  begin
    Inc(Passed);
    WriteLn('ok    ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name);
  end;
end;

procedure TestInts;
var
  V: Integer;
  Same: Boolean;
begin
  Same := True;
  for V := -300 to 300 do
    if ClampInt(V, 0, 223) <> EnsureRange(V, 0, 223) then Same := False;
  Check(Same, 'ClampInt matches EnsureRange on 0..223 for -300..300');
  Check(ClampInt(Low(Integer), 0, 223) = 0, 'ClampInt: the lowest Integer gives Lo');
  Check(ClampInt(High(Integer), 0, 223) = 223, 'ClampInt: the highest Integer gives Hi');
  Check(ClampInt(5, 5, 5) = 5, 'ClampInt: Lo = Hi');
end;

procedure TestNums;
const
  Ranges: array[0..3, 0..1] of Double = ((0, 63), (0, 1), (0.05, 8), (-4, 4));
var
  R, I: Integer;
  V, Lo: Double;
  Same: Boolean;
begin
  for R := 0 to High(Ranges) do
  begin
    Same := True;
    for I := -2000 to 2000 do
    begin
      V := I / 16;
      if ClampNum(V, Ranges[R, 0], Ranges[R, 1]) <>
         EnsureRange(V, Ranges[R, 0], Ranges[R, 1]) then Same := False;
    end;
    Check(Same, Format('ClampNum matches EnsureRange on %g..%g',
      [Ranges[R, 0], Ranges[R, 1]]));
  end;
  Lo := 0.05;
  Check(ClampNum(Lo, Lo, 8) = Lo, 'ClampNum: Lo itself stays');
  Check(ClampNum(8, 0.05, 8) = 8, 'ClampNum: Hi itself stays');
  Check(ClampNum(-0.0001, 0, 1) = 0, 'ClampNum: just below Lo gives Lo');
end;

begin
  Passed := 0;
  Failed := 0;
  TestInts;
  TestNums;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
