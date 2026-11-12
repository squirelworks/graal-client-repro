{ GNumText checks (#114): the Delphi 5 helpers that replaced TryStrToInt,
  TryStrToFloat, StrToFloatDef, the TFormatSettings overloads and PosEx in
  the shared units. Under Free Pascal each helper must give what the
  replaced call gave with '.' as the decimal point, so the replaced calls
  are the reference here. The GS1 number format and function lookup that
  use the helpers are checked through GGs1. }
program TestNumText;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, StrUtils, Math,
  GNumText in '../../common/GNumText.pas',
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

function SameDouble(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then
    Result := IsNan(A) and IsNan(B)
  else
    Result := (A = B) and (Sign(A) = Sign(B));
end;

const
  FloatCases: array[0..27] of string = (
    '1.5', ' 1.5', '1.5 ', #9'1.5'#9, '1,5', '1e3', '1E-2', '.5', '5.', '-.5',
    '+1', '-0', '0.1', '0.30000000000000004', '1.5e', '1.5x', '', '  ', '$10',
    '0x10', '1_0', '12345678901234567890', '1e308', '1e309', '-1e309', '-inf',
    'nan', '1..5');
  IntCases: array[0..15] of string = (
    '0', '15', ' 15', '15 ', '-7', '+7', '$ff', '0x1F', '-2147483648',
    '2147483647', '1.5', '', 'abc', '07', '1e3', '--1');

procedure TestFloats;
var
  FS: TFormatSettings;
  I: Integer;
  A, B: Boolean;
  V, W: Double;
  Ref: Extended;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  for I := 0 to High(FloatCases) do
  begin
    V := -1;
    W := -1;
    A := TryStrToFloat(FloatCases[I], V, FS);
    B := TryDotTextToFloat(FloatCases[I], W);
    Check((A = B) and (not A or SameDouble(V, W)),
      'float [' + FloatCases[I] + '] matches TryStrToFloat');
    { StrToFloatDef returns Extended; the replaced calls stored it in a
      Double, which raised EOverflow past Double's range (TestRangeEdge). }
    Ref := StrToFloatDef(FloatCases[I], 7, FS);
    if IsNan(Ref) or IsInfinite(Ref) or (Abs(Ref) <= 1.7976931348623157E308) then
      Check(SameDouble(DotTextToFloatDef(FloatCases[I], 7), Ref),
        'float [' + FloatCases[I] + '] default matches StrToFloatDef');
  end;
end;

{ Where Free Pascal 3.2.2's TryStrToFloat is uneven at Double's edge
  ('inf' and the largest Double rejected, '-inf' accepted), the helper
  accepts both infinities and every finite Double. }
procedure TestRangeEdge;
var
  V: Double;
begin
  Check(TryDotTextToFloat('inf', V) and IsInfinite(V) and (V > 0), 'inf reads as +infinity');
  Check(TryDotTextToFloat('-inf', V) and IsInfinite(V) and (V < 0), '-inf reads as -infinity');
  Check(TryDotTextToFloat('1.7976931348623157e308', V) and (V > 1.7E308), 'largest Double reads');
  Check(not TryDotTextToFloat('1e309', V) and not TryDotTextToFloat('-1e309', V),
    'finite values past Double are rejected');
  Check(DotTextToFloatDef('1e999', 4) = 4, 'past Double falls back to the default');
end;

procedure TestInts;
var
  I, V, W: Integer;
  A, B: Boolean;
begin
  for I := 0 to High(IntCases) do
  begin
    V := -1;
    W := -1;
    A := TryStrToInt(IntCases[I], V);
    B := TryTextToInt(IntCases[I], W);
    Check((A = B) and (not A or (V = W)),
      'int [' + IntCases[I] + '] matches TryStrToInt');
  end;
end;

const
  FormatCases: array[0..11] of Double = (
    0.5, -0.5, 1.25, 1 / 3, 2 / 3, 1E15, 1E-7, 123456.789, -98765.4321,
    0.1, 1E300, 3.141592653589793);

procedure TestFormatsAndLocale;
var
  FS: TFormatSettings;
  Saved: Char;
  I: Integer;
  V: Double;
  Ref: string;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  for I := 0 to High(FormatCases) do
  begin
    Ref := FloatToStrF(FormatCases[I], ffGeneral, 15, 0, FS);
    Check(DotFloatToText(FormatCases[I], 15) = Ref,
      'format ' + Ref + ' matches FloatToStrF with ''.''');
    { the NPC bridges' setlevel2 warps used FloatToStr(V, FS) }
    Check(DotFloatToText(FormatCases[I], 15) = FloatToStr(FormatCases[I], FS),
      'format ' + Ref + ' matches FloatToStr with ''.''');
  end;
  Check(GsFormatNum(3) = '3', 'GS1 whole number has no point');
  Check(GsFormatNum(-0.5) = '-0.5', 'GS1 fraction');
  Check(GsFormatNum(1 / 3) = '0.333333333333333', 'GS1 keeps 15 digits');
  Check(GsFormatNum(1E15) = '1E15', 'GS1 large whole number');
  Check(GsFormatNum(Infinity) = '+Inf', 'GS1 infinity');

  { A comma locale: Graal's numbers still read and print with '.' }
  Saved := DefaultFormatSettings.DecimalSeparator;
  DefaultFormatSettings.DecimalSeparator := ',';
  try
    Check(TryDotTextToFloat('1.5', V) and (V = 1.5), 'comma locale reads 1.5');
    Check(not TryDotTextToFloat('1,5', V), 'comma locale still rejects 1,5');
    Check(DotTextToFloatDef('2.25', 0) = 2.25, 'comma locale default reads 2.25');
    Check(DotFloatToText(1.5, 15) = '1.5', 'comma locale prints 1.5');
    Check(GsFormatNum(-2.75) = '-2.75', 'comma locale GS1 prints -2.75');
  finally
    DefaultFormatSettings.DecimalSeparator := Saved;
  end;
end;

procedure TestPosFrom;
const
  Subs: array[0..3] of string = ('ab', 'b', 'xab', 'zz');
var
  S: string;
  I, Off: Integer;
  OK: Boolean;
begin
  S := 'xabxab';
  OK := True;
  for I := 0 to High(Subs) do
    for Off := 1 to Length(S) + 2 do
      if PosFrom(Subs[I], S, Off) <> PosEx(Subs[I], S, Off) then
      begin
        OK := False;
        WriteLn('      PosFrom(', Subs[I], ', ', S, ', ', Off, ') = ',
          PosFrom(Subs[I], S, Off), ', PosEx ', PosEx(Subs[I], S, Off));
      end;
  Check(OK, 'PosFrom matches PosEx for every offset');
  { PosEx takes an unsigned offset; below 1 the helper finds nothing }
  Check((PosFrom('ab', S, 0) = 0) and (PosFrom('ab', S, -1) = 0), 'PosFrom offset below 1');
  Check((PosFrom('', 'abc', 1) = PosEx('', 'abc', 1)) and
    (PosFrom('a', '', 1) = PosEx('a', '', 1)), 'PosFrom empty strings');
end;

procedure TestGs1Functions;
var
  S: TGsScript;
begin
  S := TGsScript.Create;
  try
    Check(S.Compile('function first() { x = 1.5; }' + #10 +
      'function   second() { y = .25; }' + #10 +
      'if (playerenters) { first(); second(); }'),
      'GS1 script with two functions compiles');
    Check((S.FunctionStart('first') >= 0) and (S.FunctionStart('second') >= 0),
      'GS1 finds every declared function');
    Check(S.FunctionStart('third') < 0, 'GS1 has no undeclared function');
  finally
    S.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestFloats;
  TestRangeEdge;
  TestInts;
  TestFormatsAndLocale;
  TestPosFrom;
  TestGs1Functions;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
