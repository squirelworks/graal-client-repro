{ Checks for the 5.303 / 5.314 scaffold in Late531.

  No login token is invented. The two length-wrap opcodes are not given
  a guessed header. "illegal data (2)" is named and not raised. }
program TestLate531;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Late531 in '../src/Late531.pas';

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

procedure TestCut;
begin
  Check(ScaffoldOnly, 'no wire client');
  Check(FileVersion530 = '5.303', '5.30r3 file version');
  Check(FileVersion531 = '5.314', '5.31r4 file version');
  Check(BuildLabel530 = '5.30r3', '5.30r3 label');
  Check(BuildLabel531 = '5.31r4', '5.31r4 label');
  Check(CompanyName = 'Linux Cyberjoueurs', 'company string');
  Check(ProductName = 'Graal', 'product name');
  Check(EngineLibrary = 'quattro_lib', 'engine is quattro_lib');
  Check(ProcessCount = 1, 'one executable');
  Check(not LinksTorque, 'Torque is not linked');
  Check(not HasSimObject, 'no SimObject');
  Check(not StoresEightCharToken, 'no stored eight-character token');
  Check(TokenLiteral = '', 'token literal stays empty');
  Check(BakesLoginHost, 'a login host is baked');
  Check(BakedLoginPort = 14900, 'baked login port');
  Check(HasScriptUdp, 'script UDP hook is present');
  Check(not HasOnSend, 'no onSend table');
  Check(not HasConnector, 'no connector script');
  Check(not HasArc4Process, 'no Arc4Process name');
  Check(not HasAesSelector, 'no AES selector');
  Check(HasIllegalWording, 'reject wording is illegal');
  Check(not HasInvalidData3, 'no invalid data (3)');
  Check(not HasSocketNotInitialized, 'no socket-not-initialized line');
  Check(KnownReject('outgoing-newline') = MsgIllegalOutgoing, 'outgoing text');
  Check(Pos('illegal', LowerCase(KnownReject('outgoing-newline'))) > 0,
    'outgoing text says illegal');
  Check(Pos('invalid', LowerCase(KnownReject('outgoing-newline'))) = 0,
    'outgoing text does not say invalid');
  Check(KnownReject('inbound-1') = MsgIllegalInbound1, 'inbound (1) text');
  Check(Pos('illegal', LowerCase(KnownReject('inbound-2'))) > 0,
    'inbound (2) text says illegal');
  Check(KnownReject('inbound-3') = '', 'no third reject text');
  Check(KnownReject('socket') = '', 'absent socket text is empty');
end;

procedure TestSend;
var
  O: TLate5Out;
  Big: string;
  Held: string;
begin
  ResetOut(O);
  Check(SendLine(O, 0, 'ab') = ssQueued, 'opcode 0 queues');
  Check(O.Pending = Chr(GcharBias) + 'ab' + #10, 'opcode 0 is bias, body, newline');
  Held := O.Pending;
  Check(SendLine(O, 1, 'a' + #10 + 'b') = ssIllegalCharacters, 'newline is rejected');
  Check(O.Pending = Held, 'a rejected line is not written');
  Check(SendLine(O, $5C, 'a' + #10) = ssIllegalCharacters, 'neighbour of the first wrap still rejects');
  Check(SendLine(O, OpcodeLengthWrap1, 'a' + #10 + 'b') = ssLengthWrapOpen,
    'first wrap opcode is not encoded');
  Check(SendLine(O, OpcodeLengthWrap2, 'x') = ssLengthWrapOpen,
    'second wrap opcode is not encoded');
  Check(SendLine(O, $A4, #10) = ssIllegalCharacters, 'neighbour of the second wrap still rejects');
  Check(O.Pending = Held, 'wrap opcodes write nothing');
  Check(IsLengthWrapOpcode(OpcodeLengthWrap1) and IsLengthWrapOpcode(OpcodeLengthWrap2),
    'only the two named opcodes are the wrap');
  Check(not IsLengthWrapOpcode($5C) and not IsLengthWrapOpcode($A4),
    'the neighbours are ordinary opcodes');
  O.Opened := False;
  Check(SendLine(O, 1, 'z') = ssClosed, 'a closed sender does not queue');
  Check(O.Pending = Held, 'a closed sender writes nothing');
  ResetOut(O);
  Check(SendLine(O, 256, 'z') = ssRejected, 'opcode 256 is not a byte');
  Check(SendLine(O, -1, 'z') = ssRejected, 'a negative opcode is rejected');
  Check(O.Pending = '', 'a rejected opcode writes nothing');

  { 4095 bytes stay pending. The next line is appended, then the whole
    buffer is flushed. A flush-before-append would leave the short line
    pending. }
  ResetOut(O);
  Big := StringOfChar('q', OutboundFlushAbove - 2);
  Check(Length(Chr(7 + GcharBias) + Big + #10) = OutboundFlushAbove,
    'the boundary line is 4095 bytes');
  Check(SendLine(O, 7, Big) = ssQueued, '4095 bytes stay pending');
  Check(Length(O.Pending) = OutboundFlushAbove, 'pending length is the threshold');
  Check(SendLine(O, 8, 'x') = ssFlushed, 'the next line flushes');
  Check(O.Pending = '', 'pending is empty after the flush');
  Check(O.Flushed = Chr(7 + GcharBias) + Big + #10 + Chr(8 + GcharBias) + 'x' + #10,
    'the flush includes the line that crossed');
end;

procedure TestRecv;
var
  R: TLate5In;
  Payload: string;
  Rest: string;
begin
  ResetIn(R);
  Check(PushInbound(R, '', Payload) = rsNeedMore, 'empty buffer waits');
  Check(PushInbound(R, #$00, Payload) = rsNeedMore, 'one byte waits');
  Check(not R.Killed, 'a short header does not kill');
  Check(PushInbound(R, #$02 + 'hi', Payload) = rsFrame, 'a 2-byte body is a frame');
  Check(Payload = 'hi', 'the payload is the body');
  Check(R.Buf = '', 'the frame is consumed');

  ResetIn(R);
  Check(PushInbound(R, #$00#$05 + 'abcd', Payload) = rsNeedMore, 'a short body waits');
  Check(not R.Killed, 'a short body does not kill');
  Check(PushInbound(R, 'e', Payload) = rsFrame, 'the last byte completes the frame');
  Check(Payload = 'abcde', 'the body is the five bytes');

  ResetIn(R);
  Check(PushInbound(R, #$00#$03 + 'abc' + #$00#$03 + 'def', Payload) = rsFrame,
    'first of two frames');
  Check(Payload = 'abc', 'first body');
  Check(PushInbound(R, '', Payload) = rsFrame, 'second frame from the remainder');
  Check(Payload = 'def', 'second body');
  Check(R.Buf = '', 'both frames consumed');

  ResetIn(R);
  Check(PushInbound(R, #$00#$00, Payload) = rsIllegal1, 'a zero length is illegal (1)');
  Check(R.Killed, 'illegal (1) kills the reader');
  Check(Payload = '', 'illegal (1) has no payload');
  Check(PushInbound(R, #$00#$01 + 'z', Payload) = rsIllegal1, 'a killed reader stays killed');

  ResetIn(R);
  Check(PushInbound(R, #$FF#$FF + #$00#$00#$01, Payload) = rsNeedMore,
    'a short long-header waits');
  Check(not R.Killed, 'a short long-header does not kill');
  ResetIn(R);
  Check(PushInbound(R, #$FF#$FF + #$00#$00#$00#$00, Payload) = rsIllegal1,
    'a zero long length is illegal (1)');
  Check(R.Killed, 'the long-header failure kills');

  ResetIn(R);
  Rest := #$FF#$FF + #$00#$00#$00#$02 + 'OK' + #$00#$01 + 'Z';
  Check(PushInbound(R, Rest, Payload) = rsFrame, 'long header is six bytes');
  Check(Payload = 'OK', 'long body follows the six-byte header');
  Check(PushInbound(R, '', Payload) = rsFrame, 'a short frame can follow a long one');
  Check(Payload = 'Z', 'the following body is intact');
end;

begin
  Passed := 0;
  Failed := 0;
  TestCut;
  TestSend;
  TestRecv;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
