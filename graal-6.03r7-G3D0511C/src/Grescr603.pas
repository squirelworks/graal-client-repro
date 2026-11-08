{ Grescr603: provisional standalone GRESCR01 header probe.
  No client call site, CRC/cache validation or VM execution.
  Passing this probe is not script acceptance.
  Observed magic: docs/v6-repro.md, GS2.

  The original Windows engine is identified as quattro_lib. The Linux token stays
  Protocol603.ClientVersionToken (G3D0511C). This unit does not restate
  the 6.037 rows of docs/v6-repro.md, and it does not invent an outgoing
  packet id.

  A buffer shorter than eight bytes is rejected. A buffer of at least
  eight bytes that starts with GRESCR01 is accepted and the payload
  length is logged. The CRC and the script body are not read. }
unit Grescr603;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  LinksTorque = False;

  GrescrMagic = 'GRESCR01';

function GrescrAccepted(const Buf: AnsiString): Boolean;
{ Probes a minimal GRESCR01 header. Sets GrescrPayloadLen and GrescrLog
  on the accept path. A buffer shorter than eight bytes is rejected. }
function GrescrLoad(const Buf: AnsiString): Boolean;
{ 1-based index of the first byte the CRC covers. The CRC itself is not
  computed here. }
function GrescrCrcStart: Integer;

{ Outgoing load events named in docs/v6-repro.md. The numeric wire id
  is not in that note's outgoing table, so these write the name and the
  payload length. They do not invent an id number. }
function SendWantClassScript(const Payload: AnsiString): string;
function SendWantWeaponScript(const Payload: AnsiString): string;
function SendWantGaniScript(const Payload: AnsiString): string;

var
  { -1 after a reject. The byte count after the eight-byte magic after
    an accept. }
  GrescrPayloadLen: Integer = -1;
  GrescrLog: string = '';

implementation

uses
  SysUtils;

function GrescrLoad(const Buf: AnsiString): Boolean;
begin
  GrescrPayloadLen := -1;
  GrescrLog := '';
  if Length(Buf) < 8 then
  begin
    Result := False;
    Exit;
  end;
  if Copy(Buf, 1, 8) <> GrescrMagic then
  begin
    Result := False;
    Exit;
  end;
  GrescrPayloadLen := Length(Buf) - 8;
  GrescrLog := 'GRESCR01 payload ' + IntToStr(GrescrPayloadLen);
  Result := True;
end;

function GrescrAccepted(const Buf: AnsiString): Boolean;
begin
  Result := GrescrLoad(Buf);
end;

function SendNamed(const EventName: string; const Payload: AnsiString): string;
begin
  Result := EventName + ' id=unknown len=' + IntToStr(Length(Payload));
end;

function SendWantClassScript(const Payload: AnsiString): string;
begin
  Result := SendNamed('onSendWantClassScript', Payload);
end;

function SendWantWeaponScript(const Payload: AnsiString): string;
begin
  Result := SendNamed('onSendWantWeaponScript', Payload);
end;

function SendWantGaniScript(const Payload: AnsiString): string;
begin
  Result := SendNamed('onSendWantGaniScript', Payload);
end;

function GrescrCrcStart: Integer;
begin
  Result := 9;
end;

end.
