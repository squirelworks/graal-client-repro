{ GCompat: pointer-sized integer types for historical Delphi.

  Free Pascal's System unit declares PtrInt, PtrUInt and PPtrUInt, sized to
  the target (32 bits on Win32, 64 bits on 64-bit targets). Delphi 5 and 7
  have none of them. On a period Win32 Delphi a pointer is 32 bits, so the
  same names map to Integer and Cardinal there.

  Under Free Pascal this unit declares nothing, so the 64-bit builds keep
  the compiler's own types unchanged. Add it to the uses clause of any unit
  that names one of these types.

  Delphi 7's Windows unit also predates the *Ptr window calls and the LONG
  and LONG_PTR names. On Win32 they are the plain 32-bit calls, so this
  unit declares them there for period Delphi. Issue #114. }
unit GCompat;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{$IFNDEF FPC}{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}{$ENDIF}

{$IFNDEF FPC}
type
  PtrInt = Integer;
  PtrUInt = Cardinal;
  PPtrUInt = ^PtrUInt;
{$ENDIF}

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

{$IFNDEF FPC}{$IFDEF MSWINDOWS}
function GetWindowLongPtr; external user32 name 'GetWindowLongA';
function SetWindowLongPtr; external user32 name 'SetWindowLongA';
function SetClassLongPtr; external user32 name 'SetClassLongA';
{$ENDIF}{$ENDIF}

end.
