{ GCompat: pointer-sized integer types for historical Delphi.

  Free Pascal's System unit declares PtrInt, PtrUInt and PPtrUInt, sized to
  the target (32 bits on Win32, 64 bits on 64-bit targets). Delphi 5 and 7
  have none of them. On a period Win32 Delphi a pointer is 32 bits, so the
  same names map to Integer and Cardinal there.

  Under Free Pascal this unit declares none of these, so the 64-bit builds
  keep the compiler's own types unchanged. Add it to the uses clause of any unit
  that names one of these types.

  Delphi 7's Windows unit also predates the *Ptr window calls and the LONG
  and LONG_PTR names. On Win32 they are the plain 32-bit calls, so this
  unit declares them there for period Delphi. Issue #114.

  Delphi 4 (VER120), 5 (VER130) and 6 (VER140) lack a few more RTL names
  the shared units use; this unit declares them for those versions only:
  Delphi 4 has no FreeAndNil, SameText or AnsiSameText; Delphi 4 and 5
  have no PCardinal, PSingle, PDouble, THandle in System, ErrOutput,
  SysUtils' Sleep and GetEnvironmentVariable, Math's IsNan and IsInfinite
  or AnsiDequotedStr; Delphi 4 to 6 have no UInt64 and no
  TStrings.ValueFromIndex. ValueAtIndex and EnvVar stand in for the last
  and for GetEnvironmentVariable on every compiler. }
unit GCompat;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

{$I GVer.inc}

interface

uses
{$IFNDEF FPC}{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}{$ENDIF}
  Classes;

{$IFNDEF FPC}
type
  PtrInt = Integer;
  PtrUInt = Cardinal;
  PPtrUInt = ^PtrUInt;
{$ENDIF}

{$IFDEF GC_D4}
procedure FreeAndNil(var Obj);
function SameText(const S1, S2: string): Boolean;
function AnsiSameText(const S1, S2: string): Boolean;
{$ENDIF}

{$IFDEF GC_D5DOWN}
type
  PCardinal = ^Cardinal;
  PSingle = ^Single;
  PDouble = ^Double;
{$IFDEF MSWINDOWS}
  { System has it from Delphi 6; before, only Windows did }
  THandle = Windows.THandle;
{$ENDIF}

var
  { System's standard error file, from Delphi 6: open on the process's
    standard error in a console program, closed in a GUI one, as there }
  ErrOutput: Text;

function AnsiDequotedStr(const S: string; AQuote: Char): string;
{ SysUtils' from Delphi 6 (Windows' before) }
procedure Sleep(Milliseconds: Cardinal); stdcall;
{ Math's, from Delphi 6 }
function IsNan(const AValue: Double): Boolean;
function IsInfinite(const AValue: Double): Boolean;
{$ENDIF}

{$IFDEF GC_D6DOWN}
type
  { the bits are the same; the shared units only multiply values below
    2^32 and shift the product right }
  UInt64 = Int64;
{$ENDIF}

{ L.ValueFromIndex[I] }
function ValueAtIndex(L: TStrings; I: Integer): string;
{ SysUtils.GetEnvironmentVariable(Name) (Delphi 6 and later, Free Pascal) }
function EnvVar(const Name: string): string;

{$IFNDEF FPC}{$IFDEF MSWINDOWS}
type
  LONG = Longint;
  LONG_PTR = Longint;

const
  GWLP_USERDATA = GWL_USERDATA;

function GetWindowLongPtr(Wnd: HWND; Index: Integer): LONG_PTR; stdcall;
function SetWindowLongPtr(Wnd: HWND; Index: Integer; NewLong: LONG_PTR): LONG_PTR;
  stdcall;
function SetClassLongPtr(Wnd: HWND; Index: Integer; NewLong: LONG_PTR): LONG_PTR;
  stdcall;
{$ENDIF}{$ENDIF}

implementation

uses
  SysUtils;

{$IFNDEF FPC}{$IFDEF MSWINDOWS}
function GetWindowLongPtr; external user32 name 'GetWindowLongA';
function SetWindowLongPtr; external user32 name 'SetWindowLongA';
function SetClassLongPtr; external user32 name 'SetClassLongA';
{$ENDIF}{$ENDIF}

{$IFDEF GC_D4}
procedure FreeAndNil(var Obj);
var
  P: TObject;
begin
  P := TObject(Obj);
  TObject(Obj) := nil;
  P.Free;
end;

function SameText(const S1, S2: string): Boolean;
begin
  Result := CompareText(S1, S2) = 0;
end;

function AnsiSameText(const S1, S2: string): Boolean;
begin
  Result := AnsiCompareText(S1, S2) = 0;
end;
{$ENDIF}

{$IFDEF GC_D5DOWN}
function AnsiDequotedStr(const S: string; AQuote: Char): string;
var
  P: PChar;
begin
  P := PChar(S);
  Result := AnsiExtractQuotedStr(P, AQuote);
  if Result = '' then Result := S;
end;

procedure Sleep; external kernel32 name 'Sleep';

{ IEEE double: exponent bits all set; NaN has a non-zero fraction }
function IsNan(const AValue: Double): Boolean;
var
  W: array[0..1] of Cardinal absolute AValue;
begin
  Result := ((W[1] and $7FF00000) = $7FF00000) and
    (((W[1] and $000FFFFF) <> 0) or (W[0] <> 0));
end;

function IsInfinite(const AValue: Double): Boolean;
var
  W: array[0..1] of Cardinal absolute AValue;
begin
  Result := ((W[1] and $7FFFFFFF) = $7FF00000) and (W[0] = 0);
end;
{$ENDIF}

function EnvVar(const Name: string): string;
{$IFDEF GC_D5DOWN}
var
  N: Integer;
begin
  N := Windows.GetEnvironmentVariable(PChar(Name), nil, 0);
  if N <= 0 then
  begin
    Result := '';
    Exit;
  end;
  SetLength(Result, N);
  N := Windows.GetEnvironmentVariable(PChar(Name), PChar(Result), N);
  SetLength(Result, N);
end;
{$ELSE}
begin
  Result := SysUtils.GetEnvironmentVariable(Name);
end;
{$ENDIF}

function ValueAtIndex(L: TStrings; I: Integer): string;
begin
{$IFDEF GC_D6DOWN}
  if I >= 0 then
    Result := Copy(L[I], Length(L.Names[I]) + 2, MaxInt)
  else
    Result := '';
{$ELSE}
  Result := L.ValueFromIndex[I];
{$ENDIF}
end;

{$IFDEF GC_D5DOWN}
initialization
  AssignFile(ErrOutput, '');
  if IsConsole then
  begin
    Rewrite(ErrOutput);
{$IFDEF MSWINDOWS}
    TTextRec(ErrOutput).Handle := GetStdHandle(STD_ERROR_HANDLE);
{$ENDIF}
  end;
{$ENDIF}

end.
