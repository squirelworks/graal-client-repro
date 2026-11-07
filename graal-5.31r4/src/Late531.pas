{ Late531: the 5.30r3 / 5.31r4 cut.

  Both images are one executable. FileVersion is 5.303 and 5.314. The
  company string is Linux Cyberjoueurs. The engine name in the image is
  quattro_lib. Torque class names are absent, so this folder does not
  link a Torque unit and does not load the earlier 5.0.0.7 engine DLLs.

  The login line sends ClientVersionToken.

  Outbound lines are the classic GCHAR form: opcode plus 32, the body,
  then a newline. A newline inside the body is rejected, except the two
  internal opcodes whose length-wrap bytes were not recovered. Those two
  are recognised and not written, because a guessed header would be a
  new layout.   The outbound buffer is flushed once it is longer than
  4095 bytes. The line that crossed that length is included in the flush.

  Inbound frames are a 2-byte big-endian length. A length of 65535 is
  the long form already used by the classic framer: four more bytes, a
  big-endian length, six bytes of header in all. A length below 1 is
  the "illegal data (1)" failure and the socket is killed. The byte
  pattern for "illegal data (2)" was not recovered, so this reader does
  not raise it. Bytes inside a frame are returned as they stand. No
  cipher and no compression byte is stripped.

  ScaffoldOnly tells scripts/loopback.sh and scripts/stress.sh that this
  folder has no wire client. }
unit Late531;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { No socket, no board, no server. LoginPlain still builds the line. }
  ScaffoldOnly = True;

  FileVersion530 = '5.303';
  FileVersion531 = '5.314';
  BuildLabel530 = '5.30r3';
  BuildLabel531 = '5.31r4';
  { Provisional: 5.31r4 has no exact row. Neighbour is Linux 6.037. }
  ClientVersionToken = 'G3D0511C';
  { After the password: platform, three empty machine hashes, and an
    empty quoted OS field. The original fills the hashes and the OS
    string. This rebuild reads no machine values. }
  LoginTail = 'win,"","","",""';
  CompanyName = 'Linux Cyberjoueurs';
  ProductName = 'Graal';
  EngineLibrary = 'quattro_lib';

  { One program. Not the 5.0.0.7 host plus two DLLs. }
  ProcessCount = 1;
  LinksTorque = False;
  HasSimObject = False;

  StoresEightCharToken = False;
  { The images bake a login host beside this port. The host name is not
    copied into this repo. }
  BakesLoginHost = True;
  BakedLoginPort = 14900;

  GcharBias = 32;
  { Internal opcodes. They skip the newline check. Their wrap is open. }
  OpcodeLengthWrap1 = $5D;
  OpcodeLengthWrap2 = $A3;
  { Flush when the pending buffer is longer than this. }
  OutboundFlushAbove = $FFF;

  InboundHeaderBytes = 2;
  ExtendedMarker = $FFFF;
  ExtendedHeaderBytes = 6;

  MsgIllegalOutgoing = 'Illegal characters in the outgoing data';
  MsgIllegalInbound1 = 'Received illegal data (1)';
  MsgIllegalInbound2 = 'Received illegal data (2)';

  { Wording on these images. The later "invalid data (3)" line is absent,
    and so is the "socket is not initialized" line. }
  HasIllegalWording = True;
  HasInvalidData3 = False;
  HasSocketNotInitialized = False;
  HasOnSend = False;
  HasConnector = False;
  HasArc4Process = False;
  HasAesSelector = False;
  HasScriptUdp = True;

type
  TSendStatus = (
    ssQueued,             { line is in the pending buffer }
    ssFlushed,            { the line crossed the flush line and went out }
    ssIllegalCharacters,  { newline in a normal body; nothing was written }
    ssLengthWrapOpen,     { internal opcode; wrap bytes are not known }
    ssClosed,             { the sender is not open }
    ssRejected            { opcode is not a byte; nothing was written }
  );

  TRecvStatus = (
    rsNeedMore,   { header or body is not all here yet }
    rsFrame,      { one frame was taken }
    rsIllegal1    { length below 1; the reader stays killed }
  );

  TLate5Out = record
    Pending: string;
    Flushed: string;
    Opened: Boolean;
  end;

  TLate5In = record
    Buf: string;
    Killed: Boolean;
  end;

{ Always empty. Neither image stores an eight-character literal. }
function TokenLiteral: string;
{ Login line for both builds: id 5, key, ClientVersionToken, account,
  password, LoginTail, and a newline. Empty when a field contains a
  newline. }
function LoginPlain(Key: Integer; const Account, Password: string): string;
function IsLengthWrapOpcode(Op: Integer): Boolean;
{ '' for a kind these images do not say. }
function KnownReject(const Kind: string): string;

procedure ResetOut(var O: TLate5Out);
function SendLine(var O: TLate5Out; Op: Integer; const Body: string): TSendStatus;

procedure ResetIn(var R: TLate5In);
{ Append Chunk (empty reads what is already buffered) and take one frame. }
function PushInbound(var R: TLate5In; const Chunk: string;
  out Payload: string): TRecvStatus;

implementation

uses
  GTypes;

function TokenLiteral: string;
begin
  Result := '';
end;

function LoginPlain(Key: Integer; const Account, Password: string): string;
begin
  if (Pos(#10, Account) > 0) or (Pos(#10, Password) > 0) then
  begin
    Result := '';
    Exit;
  end;
  Result := GChar(5) + GChar(Key) + ClientVersionToken + GString(Account) +
    GString(Password) + LoginTail + #10;
end;

function IsLengthWrapOpcode(Op: Integer): Boolean;
begin
  Result := (Op = OpcodeLengthWrap1) or (Op = OpcodeLengthWrap2);
end;

function KnownReject(const Kind: string): string;
begin
  if Kind = 'outgoing-newline' then Result := MsgIllegalOutgoing
  else if Kind = 'inbound-1' then Result := MsgIllegalInbound1
  else if Kind = 'inbound-2' then Result := MsgIllegalInbound2
  else Result := '';
end;

procedure ResetOut(var O: TLate5Out);
begin
  O.Pending := '';
  O.Flushed := '';
  O.Opened := True;
end;

function SendLine(var O: TLate5Out; Op: Integer; const Body: string): TSendStatus;
var
  Line: string;
begin
  if not O.Opened then
  begin
    Result := ssClosed;
    Exit;
  end;
  if (Op < 0) or (Op > 255) then
  begin
    Result := ssRejected;
    Exit;
  end;
  { The wrap that lets these two carry a newline was not recovered. }
  if IsLengthWrapOpcode(Op) then
  begin
    Result := ssLengthWrapOpen;
    Exit;
  end;
  if Pos(#10, Body) > 0 then
  begin
    Result := ssIllegalCharacters;
    Exit;
  end;
  Line := Chr(Op + GcharBias) + Body + #10;
  O.Pending := O.Pending + Line;
  if Length(O.Pending) > OutboundFlushAbove then
  begin
    O.Flushed := O.Flushed + O.Pending;
    O.Pending := '';
    Result := ssFlushed;
  end
  else
    Result := ssQueued;
end;

procedure ResetIn(var R: TLate5In);
begin
  R.Buf := '';
  R.Killed := False;
end;

function PushInbound(var R: TLate5In; const Chunk: string;
  out Payload: string): TRecvStatus;
var
  Len: Int64;
  Head, Have: Integer;
begin
  Payload := '';
  if R.Killed then
  begin
    Result := rsIllegal1;
    Exit;
  end;
  if Chunk <> '' then R.Buf := R.Buf + Chunk;
  Have := Length(R.Buf);
  if Have < InboundHeaderBytes then
  begin
    Result := rsNeedMore;
    Exit;
  end;
  Len := (Int64(Ord(R.Buf[1])) shl 8) or Ord(R.Buf[2]);
  Head := InboundHeaderBytes;
  if Len = ExtendedMarker then
  begin
    if Have < ExtendedHeaderBytes then
    begin
      Result := rsNeedMore;
      Exit;
    end;
    Len := (Int64(Ord(R.Buf[3])) shl 24) or (Int64(Ord(R.Buf[4])) shl 16) or
      (Int64(Ord(R.Buf[5])) shl 8) or Ord(R.Buf[6]);
    Head := ExtendedHeaderBytes;
  end;
  if Len < 1 then
  begin
    R.Killed := True;
    Result := rsIllegal1;
    Exit;
  end;
  if Int64(Have) < Int64(Head) + Len then
  begin
    Result := rsNeedMore;
    Exit;
  end;
  Payload := Copy(R.Buf, Head + 1, Integer(Len));
  Delete(R.Buf, 1, Head + Integer(Len));
  Result := rsFrame;
end;

end.
