{ GCompat: pointer-sized integer types for historical Delphi.

  Free Pascal's System unit declares PtrInt, PtrUInt and PPtrUInt, sized to
  the target (32 bits on Win32, 64 bits on 64-bit targets). Delphi 5 and 7
  have none of them. On a period Win32 Delphi a pointer is 32 bits, so the
  same names map to Integer and Cardinal there.

  Under Free Pascal this unit declares nothing, so the 64-bit builds keep
  the compiler's own types unchanged. Add it to the uses clause of any unit
  that names one of these types. Issue #114. }
unit GCompat;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{$IFNDEF FPC}
type
  PtrInt = Integer;
  PtrUInt = Cardinal;
  PPtrUInt = ^PtrUInt;
{$ENDIF}

implementation

end.
