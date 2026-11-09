{ Public variable-store lifetime checks. The checked build's heap tracer
  also verifies that Clear and destruction release every variable box. }
program TestGs1Vars;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  GGs1 in '../../common/GGs1.pas';

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

procedure TestLifetime;
var
  Vars: TGsVars;
  Values: TGsValues;
  I, Cycle: Integer;
  Name: string;
  OK: Boolean;
begin
  Vars := TGsVars.Create;
  try
    Vars.Clear;
    Vars.Clear;
    Check(not Vars.Exists('empty'), 'empty store tolerates repeated clear');
    SetLength(Values, 3);
    Values[0] := 1;
    Values[1] := 2;
    Values[2] := 3;
    Vars.SetArray('array', Values);
    Values[1] := 99;
    Check((Vars.Len('array') = 3) and (Vars.Get('array', 1) = 2),
      'array storage owns an independent copy');
    Vars.SetValue('scalar', 0, 7);
    Vars.SetValue('scalar', 0, 8);
    Check((Vars.Len('scalar') = 1) and (Vars.Get('scalar', 0) = 8),
      'scalar overwrite retains its value');
    Vars.Resize('array', 5);
    Check((Vars.Get('array', 1) = 2) and (Vars.Get('array', 4) = 0),
      'resizing preserves values and initializes new elements');
    Vars.Clear;
    Check(not Vars.Exists('scalar') and not Vars.Exists('array') and
      (Vars.Len('array') = 0) and (Vars.Get('scalar', 0) = 0),
      'clear removes scalar and array contents');
    OK := True;
    for Cycle := 1 to 50 do
    begin
      for I := 1 to 100 do
      begin
        Name := 'value' + IntToStr(I);
        Vars.SetArray(Name, Values);
        Vars.SetValue(Name, 0, Cycle + I);
        if Vars.Get(Name, 0) <> Cycle + I then OK := False;
      end;
      Vars.Clear;
      if Vars.Exists('value1') or Vars.Exists('value100') then OK := False;
    end;
    Check(OK, 'store can repeatedly create, overwrite, clear and reuse values');
    Vars.SetValue('scalar', 0, 42);
    Vars.SetArray('array', Values);
    Check((Vars.Get('scalar', 0) = 42) and (Vars.Get('array', 1) = 99),
      'cleared names can be reused with new values');
    { Deliberately leave live scalar/array entries for destruction. }
  finally
    Vars.Free;
  end;
end;

begin
  TestLifetime;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
