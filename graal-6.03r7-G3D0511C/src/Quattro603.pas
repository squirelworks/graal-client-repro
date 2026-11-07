{ Quattro603: the 6.037 facts a repro can check without a script VM.

  This folder's wire token stays Protocol603.ClientVersionToken
  (G3D0511C, the Linux build). The Windows 6.037 image stores a different
  string and sends it upper-cased. That string is not this folder's token.

  6.037 stays on the generation-5 framer. It has no setprotocol, sendraw
  or senddata, and none of the tclient property-script names.

  The GS2 note names 152 dispatch cases from 11 through 242, says 48, 49
  and 200 are absent, and says 54, 121 and 201 through 242 are present.
  The other numbers in that span are not listed, so this unit does not
  mark them present or absent. No opcode body is implemented. No packet
  id is added.

  6.1.1.3 rows (connector framing, UDP, chat events, package file names)
  are not this folder. They stay in docs/v6-repro.md.

  Sources: docs/v6-repro.md. The engine is quattro_lib, not Torque. }
unit Quattro603;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { Not the Linux token. Upper-case is what the Windows image sends. }
  WindowsStoredToken = 'g3d0311c';

  LinksTorque = False;
  UsesGeneration5 = True;
  HasSetProtocol = False;
  HasSendRaw = False;
  HasSendData = False;
  HasTclientPropertyScripts = False;

  GrescrMagic = 'GRESCR01';
  Gs2CaseTotal = 152;
  Gs2SpanLow = 11;
  Gs2SpanHigh = 242;

type
  TGs2Case = (
    gscOutside,  { not in 11..242 }
    gscAbsent,   { the note says this number is missing }
    gscPresent,  { the note says this number is dispatched }
    gscUnlisted  { inside the span, and not named either way }
  );

function GrescrAccepted(const Buf: string): Boolean;
{ 1-based index of the first byte the CRC covers. The CRC itself is not
  computed here. }
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
