{ GNumText: number text and substring helpers that Delphi 5 has.

  The shared units used TryStrToInt, TryStrToFloat, StrToFloatDef,
  TFormatSettings, the FloatToStrF overload that takes one, and StrUtils'
  PosEx. Delphi 5 has none of them (Delphi 6 and 7 added them). These
  helpers are built on Val, Pos and the plain FloatToStrF, which every
  Delphi and Free Pascal has. Issue #114.

  Numbers in Graal's files and scripts always use '.' as the decimal
  point, so the float helpers read and write '.' whatever the user's
  locale says. Under Free Pascal the results match what the replaced calls
  gave with DecimalSeparator '.' (TryStrToFloat trims the text, reads it
  with Val and rejects a finite value too large for a Double; TryStrToInt
  is Val). The one difference is at the edge of Double's range, where Free
  Pascal 3.2.2's TryStrToFloat rejects 'inf' and the largest Double but
  accepts '-inf': here both infinities and every finite Double pass. Graal
  text never holds those. }
unit GNumText;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ Val's integer syntax: optional sign, decimal or $ / 0x hex. No spaces
  after the number. False leaves V undefined. }
function TryTextToInt(const S: string; out V: Integer): Boolean;
{ Leading and trailing spaces and control characters are ignored. '.' is
  the decimal point; an exponent is allowed; ',' is never accepted. A
  finite value outside Double's range is rejected. }
function TryDotTextToFloat(const S: string; out V: Double): Boolean;
function DotTextToFloatDef(const S: string; Default: Double): Double;
{ FloatToStrF(V, ffGeneral, Precision, 0) with '.' as the decimal point. }
function DotFloatToText(V: Double; Precision: Integer): string;
{ Pos of Sub in S from position Offset on; 0 when Offset < 1, Offset is
  past the end, Sub is empty or not found. }
function PosFrom(const Sub, S: string; Offset: Integer): Integer;

implementation

uses
  SysUtils;

function TryTextToInt(const S: string; out V: Integer): Boolean;
var
  Code: Integer;
begin
  Val(S, V, Code);
  Result := Code = 0;
end;

var
  MaxDoubleValue: Extended;

function TryDotTextToFloat(const S: string; out V: Double): Boolean;
var
  T: string;
  Code, I: Integer;
  E: Extended;
  Word: Boolean;
begin
  T := Trim(S);
  Result := False;
  if T = '' then Exit;
  { The range check reads the text as Extended, so a finite number past
    Double's range (1e309) is rejected instead of overflowing. Text with a
    letter other than the exponent's is Free Pascal's 'inf' or 'nan'; it
    skips the check, since comparing a NaN raises. }
  Val(T, E, Code);
  if Code <> 0 then Exit;
  Word := False;
  for I := 1 to Length(T) do
    if (T[I] in ['A'..'Z', 'a'..'z']) and not (T[I] in ['E', 'e']) then Word := True;
  if not Word and ((E > MaxDoubleValue) or (E < -MaxDoubleValue)) then Exit;
  Val(T, V, Code);
  Result := Code = 0;
end;

function DotTextToFloatDef(const S: string; Default: Double): Double;
begin
  if not TryDotTextToFloat(S, Result) then Result := Default;
end;

function LocaleDecimalSeparator: Char;
begin
{$IFDEF FPC}
  Result := DefaultFormatSettings.DecimalSeparator;
{$ELSE}
  Result := DecimalSeparator;
{$ENDIF}
end;

function DotFloatToText(V: Double; Precision: Integer): string;
var
  DS: Char;
  I: Integer;
begin
  Result := FloatToStrF(V, ffGeneral, Precision, 0);
  DS := LocaleDecimalSeparator;
  if DS <> '.' then
    for I := 1 to Length(Result) do
      if Result[I] = DS then Result[I] := '.';
end;

function PosFrom(const Sub, S: string; Offset: Integer): Integer;
begin
  Result := 0;
  if (Offset < 1) or (Offset > Length(S)) or (Sub = '') then Exit;
  Result := Pos(Sub, Copy(S, Offset, MaxInt));
  if Result > 0 then Inc(Result, Offset - 1);
end;

initialization
  MaxDoubleValue := 1.7976931348623157E308;
end.
