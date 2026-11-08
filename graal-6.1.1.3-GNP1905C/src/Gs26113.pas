{ Gs26113: the GS2 facts this slice can check. No opcode is executed.

  verified-from-evidence:
    a buffer shorter than eight bytes is rejected. The magic is GRESCR01.
    The CRC32 covers the bytes after those eight. Where that CRC is stored
    was not recovered, so it is not checked. The dispatcher span is 11
    through 242. Cases 48, 49 and 200 are absent. Cases 54, 121 and 201
    through 242 are present. The other numbers in the span are not named.
  provisional adapter:
    none.
  lab-only fixture:
    none.

  Source: client-internals/gs2-6113.md, manual section 8.4.4. }
unit Gs26113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  GrescrMagic = 'GRESCR01';
  Gs2CaseTotal = 152;
  Gs2SpanLow = 11;
  Gs2SpanHigh = 242;

type
  TGs2Case = (gscOutside, gscAbsent, gscPresent, gscUnlisted);

function GrescrAccepted(const Buf: string): Boolean;
function GrescrCrcStart: Integer;
function Gs2CaseOf(Op: Integer): TGs2Case;

implementation

function GrescrAccepted(const Buf: string): Boolean;
begin
  Result := (Length(Buf) >= 8) and (Copy(Buf, 1, 8) = GrescrMagic);
end;

function GrescrCrcStart: Integer;
begin
  Result := 9;
end;

function Gs2CaseOf(Op: Integer): TGs2Case;
begin
  if (Op < Gs2SpanLow) or (Op > Gs2SpanHigh) then Result := gscOutside
  else if (Op = 48) or (Op = 49) or (Op = 200) then Result := gscAbsent
  else if (Op = 54) or (Op = 121) or ((Op >= 201) and (Op <= 242)) then
    Result := gscPresent
  else
    Result := gscUnlisted;
end;

end.
