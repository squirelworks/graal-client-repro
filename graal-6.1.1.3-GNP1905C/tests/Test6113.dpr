{ Tests for the 6.1.1.3 rebuild. Framing, login state, property storage,
  and a lab-only movement round trip on 127.0.0.1. No window. }
program Test6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GSocket in '../../common/GSocket.pas',
  GZlib in '../../common/GZlib.pas',
  GBzip2 in '../../common/GBzip2.pas',
  Frame6113 in '../src/Frame6113.pas',
  Props6113 in '../src/Props6113.pas',
  Gs26113 in '../src/Gs26113.pas',
  Level6113 in '../src/Level6113.pas',
  Sha6113 in '../src/Sha6113.pas',
  Rsa6113 in '../src/Rsa6113.pas',
  Rc46113 in '../src/Rc46113.pas',
  Cipher6113 in '../src/Cipher6113.pas',
  Project6113 in '../src/Project6113.pas',
  GTypes in '../../common/GTypes.pas',
  GSecCrypto in '../../common/GSecCrypto.pas',
  GSecLogin in '../../common/GSecLogin.pas',
  Secure6113 in '../src/Secure6113.pas',
  SecureNet6113 in '../src/SecureNet6113.pas',
  Connector6113 in '../src/Connector6113.pas',
  Lab6113 in '../src/Lab6113.pas',
  Play6113 in '../src/Play6113.pas',
  Controls6113 in '../src/Controls6113.pas';

var
  Passed, Failed: Integer;
  Logs: TStringList;

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

procedure Capture(const S: string);
begin
  if Logs <> nil then Logs.Add(S);
end;

procedure TestHelloAndRaw;
var
  P: TProtocol;
  Wire: string;
begin
  P := TProtocol.Create;
  try
    Check(P.OnGen5 and (P.Mode = 3) and (P.Enc = eoDefaultLcg), 'starts on generation-5, mode 3');
    Check(P.LcgState = Gen5Seed, 'LCG state is the documented seed');
    Check(P.SendRaw(ClearHello, Wire) and (Wire = 'GNP1905C') and (Length(Wire) = 8),
      'sendraw writes GNP1905C with no header');
    Check(P.Counter = 1, 'sendraw does not advance the counter');
    Check(P.Flushes = 0, 'eight hello bytes do not flush');
    Check(P.SendRaw(StringOfChar('A', 4096), Wire) and (Length(Wire) = 4096) and (P.Flushes = 1),
      'a 4096-byte generation-5 buffer flushes');
  finally
    P.Free;
  end;
end;

procedure TestRefusals;
var
  P: TProtocol;
  Wire, Err: string;
begin
  P := TProtocol.Create;
  try
    Check(P.Gen5Reject(1, 'a' + #10 + 'b') = IllegalChars, 'newline is refused');
    Check(P.Gen5Reject(93, 'a' + #10 + 'b') = Id50Gap, 'id 93 skips the newline refusal');
    Check(P.Gen5Reject(163, 'ok') = Id50Gap, 'id 163 needs the unrecovered id 50 prefix');
    Check(not P.SendData(1, 'a' + #10 + 'b', Wire, Err) and (Err = IllegalChars),
      'numbered generation-5 send with a newline is refused');
    Check(not P.SendData(1, 'hi', Wire, Err) and
      (Err = 'generation-5 numbered send is not used after the clear hello'),
      'a clear generation-5 numbered send is not invented as the hello');
    P.SetProtocol('T');
    Check(not P.SendData(1, 'hi', Wire, Err) and (Err = CannotSend),
      'numbered send without L is refused');
  finally
    P.Free;
  end;
end;

procedure TestHeaderOrder;
var
  P: TProtocol;
  Wire, Err, Body: string;
begin
  P := TProtocol.Create;
  try
    P.SetProtocol('TIEL');
    Check(P.SendData(4, 'ab', Wire, Err) and (Err = ''), 'first numbered send');
    Check(Wire = #4 + #1 + #0 + #6 + 'ab', 'T then I then E then L, then the body');
    Check(P.SendData(4, 'ab', Wire, Err) and (Wire[2] = #2), 'I increases by one');
    P.SetProtocol('T.L');
    Check(P.SendData(4, 'Z', Wire, Err) and (Wire = #4 + #0 + #4 + 'Z'),
      'a template byte that is not I L T or E stays zero');
    P.SetProtocol('TIELLL');
    SetLength(Body, 273);
    FillChar(Body[1], 273, Ord('x'));
    Check(P.SendData(1, Body, Wire, Err), 'six-byte test template send');
    Check(HeaderPlusBody(6, 273) = 279, 'L value is header length plus body length');
    Check((Ord(Wire[4]) = 0) and (Ord(Wire[5]) = 1) and (Ord(Wire[6]) = $17),
      'that 279 is written big-endian in L');
    Check(Copy(Wire, 1, 6) <> #$01#$02#$00#$01#$17#$FD,
      'the test template is not the capture header');
  finally
    P.Free;
  end;
end;

procedure TestCompression;
var
  P: TProtocol;
  Wire, Err, Body, Plain: string;
begin
  P := TProtocol.Create;
  try
    P.SetProtocol('TIEL');
    P.CompressId := 7;
    Body := StringOfChar('A', 48);
    Check(P.SendData(7, Body, Wire, Err), 'zlib send');
    Check(Ord(Wire[3]) = 1, 'E is 1 at 48 bytes for the compression id');
    Check(ZDecompress(Copy(Wire, 5, MaxInt), Plain) and (Plain = Body), 'E 1 round-trips zlib');
    Check(not P.SendData(8, Body, Wire, Err) or (Ord(Wire[3]) = 0), 'a different id stays uncompressed');
    P.Free;
    P := TProtocol.Create;
    P.SetProtocol('TIELL');
    P.CompressId := 7;
    P.BzipGlobal := True;
    P.BzipConn := True;
    Body := StringOfChar('A', 4096);
    Check(P.SendData(7, Body, Wire, Err), 'bzip2 send');
    Check(Ord(Wire[3]) = 2, 'E is 2 at 4096 bytes when both flags are set');
    Check(Copy(Wire, 6, 4) = 'BZh5', 'E 2 is bzip2 with block-size digit 5');
    Check(BZ2Decompress(Copy(Wire, 6, MaxInt), Plain, 20000) and (Plain = Body),
      'E 2 round-trips');
    P.BzipGlobal := False;
    Check(P.SendData(7, Body, Wire, Err) and (Ord(Wire[3]) = 1),
      '4096 bytes without the bzip flag still use zlib');
    Check(P.SendData(9, Body, Wire, Err) and (Ord(Wire[3]) = 0),
      'a different id at 4096 bytes stays uncompressed');
    P.BzipGlobal := True;
    P.ForceCompressFail := True;
    Check(P.SendData(7, Body, Wire, Err) and (Ord(Wire[3]) = 0) and
      (Copy(Wire, 6, 4) = 'AAAA'), 'a failed compressor is sent as E 0');
  finally
    P.Free;
  end;
end;

procedure TestCipherChoice;
var
  P, Q: TProtocol;
  Wire: string;
  Step: Cardinal;
begin
  P := TProtocol.Create;
  try
    Step := P.LcgStepPlusOne;
    Check(Gen5Seed = 78121784, 'the generation-5 seed is the noted 6.x seed');
    Check(Step = 388683801, 'LCG step is state times the multiplier plus 1');
    P.SetEncryptionOut('AES', 'k', 'iv');
    Check((P.Enc = eoNamedUnused) and (P.EncName = 'AES'), 'AES is named and not applied');
    Check(P.SendRaw('GNP1905C', Wire) and (Wire = 'GNP1905C'),
      'a named cipher does not change sendraw');
    P.SetEncryptionOut('nope', '', '');
    Check((P.Enc = eoCleared) and (P.LcgState = Gen5Seed) and (P.Mode = 3),
      'any other name clears back to the LCG default');
  finally
    P.Free;
  end;
  P := TProtocol.Create;
  Q := TProtocol.Create;
  try
    P.LcgStepPlusOne;
    Q.LcgStepPlusKey(3);
    Check(P.LcgState <> Q.LcgState, 'the hello note adds the key; the wire note adds 1');
  finally
    Q.Free;
    P.Free;
  end;
end;

const
  { A throwaway RSA-2048 pair made for these tests only. }
  TestN =
    'a166a428a9803f30f36ccb00dc8e4875054dba0be5fcc10ad5e0095615663c66' +
    '0a1d4d260553b6306fd01a9bded5329ae83cc153b762f4c4e5e900f88c301149' +
    'd16239e250652a2916f272d517affeea4d04d53c49172ceae531e5a30fd2ae21' +
    '1dbc35802498a00bc611b044d5eaf97342e2f15e9d55e6a4cb5127d99f1b5b32' +
    'b26e792de55e70599356d49262d35b8c355e59f0633503d037290ee153ae4f1b' +
    '08e57c141d4740eec4cc5c064d310d8d1dc3d207646990297cef0ea8b1da7ce9' +
    'd85f4fd08fb69ace36ff84cb8120e205b433fae5ebd93068f42cce9a01b23773' +
    '0fa290e48e3ef20cb83188354eca5defadb2c864c4bb1d5aa20a31fa7e75150d';
  TestD =
    '2b9873e2dfd5da3bb8a4bc38a15a754bd680e62dec9356f93c47e57db10e0a66' +
    '6d78f8abba68a01f793436dbbf56caf278a4607be25f024a64e788f199bc2a0f' +
    '4c5541d95569ddf77751499f3164c2703b198117658eb2fd47a730a5d8d24962' +
    '7c8ba7cfd312beb82f69fbb8bc2759f5be2d5a90f9e288081f3aee8ea3a15a02' +
    '6bc2372f3fbdcddb70d50268ca68f640ca74710bcaa0a12b555c9f7ab3a0d0b9' +
    '91a0e3a3f181aa5fb013a0596e1a1bc26860cd04accb712922a69ef0f6691618' +
    'b3a8b5eb4ccd93f77abde09711146b457850ae7efeb48f3bc3ec0037c88e66a2' +
    'fe4379375534b0b3ac063ce26c718136740419d0d6e674f7dd5fa263e957b6e9';

function HexOf(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do Result := Result + LowerCase(IntToHex(Ord(S[I]), 2));
end;

procedure TestSessionCipher;
var
  A, B: TRc4;
  P: TProtocol;
  Key, Pad, Block, Msg, Wire, Body: string;
  I: Integer;
begin
  A := TRc4.Create('Key');
  try
    Check(HexOf(A.Crypt('Plaintext')) = 'bbf316e8d940af0ad3', 'RC4 matches the Key/Plaintext vector');
  finally
    A.Free;
  end;
  A := TRc4.Create('Secret');
  B := TRc4.Create('Secret');
  try
    Check(HexOf(A.Crypt('Attack at dawn')) = '45a01f645fc35b383552544b9bf5', 'RC4 matches the Secret vector');
    Wire := B.Crypt('Attack');
    Wire := Wire + B.Crypt(' at dawn');
    Check(HexOf(Wire) = '45a01f645fc35b383552544b9bf5', 'RC4 goes on across calls');
  finally
    B.Free;
    A.Free;
  end;

  Key := '';
  for I := 1 to 16 do Key := Key + Chr(I * 13);
  Pad := '';
  for I := 1 to 256 do Pad := Pad + Chr((I * 7) and 255);
  Block := RsaWrapType2(TestN, Key, Pad);
  Check(Length(Block) = 256, 'a type-2 key block is 256 bytes');
  Check(RsaUnwrapType2(TestN, TestD, Block, Msg) and (Msg = Key),
    'the private key unwraps the session key');
  Block[100] := Chr(Ord(Block[100]) xor 1);
  Check(not RsaUnwrapType2(TestN, TestD, Block, Msg), 'a changed block does not unwrap');
  Check(RsaWrapType2(TestN, StringOfChar('x', 246), Pad) = '', 'a key past 245 bytes is refused');

  P := TProtocol.Create;
  A := TRc4.Create(Key);
  try
    P.SetEncryptionOut('RC4', Key, '');
    Check((P.Enc = eoRc4) and (P.EncName = 'RC4'), 'RC4 with a key is applied');
    Check(P.SendRaw('GNP1905C', Wire) and (Wire = A.Crypt('GNP1905C')),
      'the wire after the key frame is RC4 of the plain bytes');
    Check(P.SendRaw('GNP1905C', Body) and (Body = A.Crypt('GNP1905C')) and (Body <> Wire),
      'the key stream goes on across sends');
    P.SetEncryptionOut('RC4', '', '');
    Check(P.Enc = eoNamedUnused, 'RC4 with no key is named and not applied');
    Check(P.SendRaw('GNP1905C', Wire) and (Wire = 'GNP1905C'), 'and the wire is plain again');
  finally
    A.Free;
    P.Free;
  end;

  P := TProtocol.Create;
  A := TRc4.Create('server-to-client');
  try
    Check(P.DecryptIn('abc') = 'abc', 'incoming bytes are plain before a key');
    Check(not P.SetEncryptionIn(2, 'k'), 'an incoming AES key is refused');
    Check(P.SetEncryptionIn(1, 'server-to-client'), 'an incoming RC4 key is taken');
    Wire := A.Crypt('hello, client');
    Body := P.DecryptIn(Copy(Wire, 1, 5));
    Body := Body + P.DecryptIn(Copy(Wire, 6, MaxInt));
    Check(Body = 'hello, client',
      'incoming RC4 decrypts across reads');
  finally
    A.Free;
    P.Free;
  end;
end;

procedure TestKeyFrames;
var
  Server: TRc4;
  P: TProtocol;
  Counter, Used, CType: Integer;
  Pad, Key, IV, Plain, Block, Frame, Got, Inner, Wire: string;
  I: Integer;
begin
  Plain := BuildServerKeyPlain(KeyTypeRc4, 'sixteen-byte-key', '');
  Check(Plain = #1#48'sixteen-byte-key'#32, 'the server key plain is type, len+32, key, len+32, IV');
  Check(ParseServerKeyPlain(Plain, CType, Key, IV) and (CType = 1) and
    (Key = 'sixteen-byte-key') and (IV = ''), 'the server key plain parses back');
  Check(not ParseServerKeyPlain(#1#60'short', CType, Key, IV), 'a key past the end is refused');
  Check(not ParseServerKeyPlain(Plain + 'x', CType, Key, IV), 'bytes after the IV are refused');

  Block := StringOfChar('B', 256);
  Counter := 1;
  Frame := BuildKeyFrame(Counter, Block);
  Check((Counter = 3) and (Copy(Frame, 1, 2) = #1#2) and (Frame[6] = #$fd) and
    (((Ord(Frame[3]) shl 16) or (Ord(Frame[4]) shl 8) or Ord(Frame[5])) = Length(Frame)),
    'the key frame is a clear 0xfd, E 1, counter 2, LLL the whole packet');
  Check(ZDecompress(Copy(Frame, 7, MaxInt), Inner) and (Length(Inner) = 262) and
    (Copy(Inner, 1, 6) = #0#1#0#1#6#$fc), 'it inflates to the 262-byte 0xfc, counter 1');
  Check(ReadKeyFrame(Frame + 'rest', Got, Used) and (Got = Block) and (Used = Length(Frame)),
    'a key frame reads back from the front of the stream');
  Check(not ReadKeyFrame(Copy(Frame, 1, Length(Frame) - 1), Got, Used), 'a cut key frame is not read');

  { The server side end to end: key plain, type-2 wrap to the parse key,
    frame, then the stream under the new key. }
  Pad := '';
  for I := 1 to 256 do Pad := Pad + Chr((I * 11) and 255);
  Block := RsaWrapType2(TestN, BuildServerKeyPlain(KeyTypeRc4, 'server-session-k', ''), Pad);
  Counter := 1;
  Server := TRc4.Create('server-session-k');
  P := TProtocol.Create;
  try
    Wire := BuildKeyFrame(Counter, Block) + Server.Crypt('first bundle');
    Check(ReadKeyFrame(Wire, Got, Used) and RsaUnwrapType2(TestN, TestD, Got, Plain) and
      ParseServerKeyPlain(Plain, CType, Key, IV) and P.SetEncryptionIn(CType, Key),
      'the client unwraps the server key frame with the parse key and re-keys');
    Check(P.DecryptIn(Copy(Wire, Used + 1, MaxInt)) = 'first bundle',
      'the bytes after the key frame decrypt under the server key');
  finally
    P.Free;
    Server.Free;
  end;
end;

function ProjectOuter(const Z: string): string;
var N: Integer;
begin
  N := 6 + Length(Z);
  Result := #1#2 + Chr(N shr 16) + Chr((N shr 8) and 255) + Chr(N and 255) + #$fd + Z;
end;

type
  TFloodReader = class
    Calls, Available: Integer;
    function Read(var Chunk; Capacity: Integer): Integer;
  end;
function TFloodReader.Read(var Chunk; Capacity: Integer): Integer;
begin
  Inc(Calls);
  if Available = 0 then begin Result := SocketReadWouldBlock; Exit; end;
  Result := Capacity;
  if (Available > 0) and (Available < Result) then Result := Available;
  if Available > 0 then Dec(Available, Result);
  FillChar(Chunk, Result, 'x');
end;
procedure TestBoundedProjectSocket;
var R: TFloodReader; Buf, Err: string;
begin
  R := TFloodReader.Create;
  try
    R.Available := -1; Buf := '';
    Check(DrainSocketBounded(Buf, 1048576, 3, R.Read, Err) and
      (R.Calls = 3) and (Length(Buf) = 24576),
      'continuous peer yields after read budget so key deadline can run');
    R.Calls := 0; Buf := 'keep';
    Check(not DrainSocketBounded(Buf, 10, 8, R.Read, Err) and
      (Buf = 'keep') and (R.Calls = 1),
      'over-limit read fails before destination append/allocation');
    R.Calls := 0; R.Available := 8; Buf := '';
    Check(DrainSocketBounded(Buf, 8, 8, R.Read, Err) and (Length(Buf) = 8),
      'exact-cap input followed by would-block remains valid');
    R.Calls := 0; R.Available := 1;
    Check(not DrainSocketBounded(Buf, 8, 8, R.Read, Err) and (Length(Buf) = 8),
      'one byte after full buffer fails without growth');
    R.Calls := 0; R.Available := 2; Buf := '';
    Check(DrainSocketBounded(Buf, 8, 8, R.Read, Err) and (Length(Buf) = 2),
      'fresh buffer after failure has no lingering drain state');
    R.Calls := 0;
    Check(not DrainSocketBounded(Buf, 8, 0, R.Read, Err) and (R.Calls = 0),
      'invalid drain budget rejected before reading');
  finally R.Free; end;
end;

procedure TestProjectCipher;
var
  P: TProtocol;
  C: TProjectCipher;
  Server: TRc4;
  Pad, Block, Frame, Wire, Plain, Err, Acc, Z, Inner: string;
  Counter, I: Integer;
  procedure RejectCompressed(const Data, Why: string);
  begin
    C.Reset; C.SetParseKey(TestN, TestD);
    Check(not C.Feed(ProjectOuter(Data), Plain, Err), Why);
    Check(not C.Feed(Frame, Plain, Err), 'malformed compression failure is sticky');
  end;
begin
  Pad := StringOfChar('P', 237);
  Block := RsaWrapType2(TestN, BuildServerKeyPlain(1, '0123456789abcdef', ''), Pad);
  Counter := 1; Frame := BuildKeyFrame(Counter, Block);
  P := TProtocol.Create; C := TProjectCipher.Create(P);
  Server := TRc4.Create('0123456789abcdef');
  try
    C.SetParseKey(TestN, TestD);
    Wire := Frame + Server.Crypt('first payload');
    Acc := '';
    for I := 1 to Length(Frame) - 1 do
    begin
      Check(C.Feed(Wire[I], Plain, Err) and (Plain = '') and not C.Ready,
        'partial clear key byte does not advance RC4');
    end;
    Check(C.Feed(Copy(Wire, Length(Frame), MaxInt), Plain, Err) and C.Ready and
      (Plain = 'first payload'), 'last clear byte plus coalesced ciphertext switches at exact boundary');
    Wire := Server.Crypt('next fragmented payload');
    for I := 1 to Length(Wire) do
    begin
      Check(C.Feed(Wire[I], Plain, Err), 'RC4 accepts byte-granular later reads');
      Acc := Acc + Plain;
    end;
    Check(Acc = 'next fragmented payload', 'RC4 state continues exactly once per byte');
    P.SetEncryptionOut('RC4', 'client-key-12345', '');
    C.Reset;
    Check(not C.Ready and (P.RcIn = nil) and (P.RcOut = nil) and (P.Counter = 1),
      'reconnect reset drops both streams and partial key state');
    C.SetParseKey(TestN, TestD);
    Check(C.Feed(Copy(Frame, 1, 5), Plain, Err), 'partial header buffered before reset');
    C.Reset; C.SetParseKey(TestN, TestD);
    Check(C.Feed(Frame, Plain, Err) and C.Ready and (Plain = ''),
      'fresh complete frame succeeds after discarded partial prefix');
    C.Reset; C.SetParseKey(TestN, TestD);
    Wire := Frame; Wire[1] := #0;
    Check(not C.Feed(Wire, Plain, Err), 'wrong clear header is rejected without protocol fallback');
    Check(not C.Feed(Frame, Plain, Err), 'failed key parse remains closed until reset');
    C.Reset; C.SetParseKey(TestN, TestD);
    Counter := 1;
    Block := RsaWrapType2(TestN, BuildServerKeyPlain(2, '0123456789abcdef', ''), Pad);
    Check(not C.Feed(BuildKeyFrame(Counter, Block), Plain, Err), 'AES key reply is refused in RC4 project mode');
    C.Reset; C.SetParseKey(TestN, TestD);
    Counter := 1;
    Block := RsaWrapType2(TestN, BuildServerKeyPlain(1, 'short', ''), Pad);
    Check(not C.Feed(BuildKeyFrame(Counter, Block), Plain, Err), 'wrong-length session key is refused');
    Z := Copy(Frame, 7, MaxInt);
    Check(ZDecompress(Z, Inner), 'valid key fixture inflates for malformed variants');
    RejectCompressed(Z + 'x', 'trailing compressed garbage inside declared outer length is refused');
    RejectCompressed(Z + Z, 'concatenated zlib streams inside key frame are refused');
    RejectCompressed(ZCompress(Inner + 'x'), '263-byte inflated key body is refused');
    RejectCompressed(ZCompress(StringOfChar('A', 100000)), 'large expansion stops at fixed key-body budget');
    RejectCompressed(Copy(Z, 1, Length(Z) - 1), 'truncated compressed key body is refused');
    RejectCompressed(#120#187#0#0#0#0 + Copy(Z, 3, MaxInt), 'dictionary-requiring stream is refused');
    Z[Length(Z)] := Chr(Ord(Z[Length(Z)]) xor 1);
    RejectCompressed(Z, 'invalid Adler checksum is refused');
  finally Server.Free; C.Free; P.Free; end;
end;

procedure TestProps;
var
  Bag: TPropBag;
  Id: Integer;
  Wire: Byte;
  Err, Text: string;
  N: Integer;
begin
  Bag := TPropBag.Create;
  try
    Bag.SetPlayer('player-bytes');
    Bag.SetOther('other-bytes');
    Bag.SetNpc('npc-bytes');
    Bag.SetBaddy('baddy-bytes');
    Check((Bag.Player = 'player-bytes') and (Bag.Other = 'other-bytes') and
      (Bag.Npc = 'npc-bytes') and (Bag.Baddy = 'baddy-bytes'),
      'the four setters store the string and do not switch on an id');
  finally
    Bag.Free;
  end;
  N := 0;
  for Id := 0 to 83 do
    if PlayerIdHasCase(Id) then Inc(N);
  Check(N = 72, 'player encoder has 72 cases in 0..83');
  Check(not PlayerIdHasCase(3) and not PlayerIdHasCase(83) and PlayerIdHasCase(0),
    'the twelve missing player ids include 3 and 83');
  Check(PropIdPrefix(0, True, Wire, Err) and (Wire = 32) and (Err = ''),
    'a player id with a case is stored plus 32');
  Check(not PropIdPrefix(3, False, Wire, Err) and (Err = 'no encoder case'),
    'an id without a case does not invent a value');
  Check(BaddyIdHasCase(0) and BaddyIdHasCase(10) and not BaddyIdHasCase(11),
    'baddy ids 0 through 10 have cases');
  Check(not NpcIdHasCase(1), 'no numbered NPC property table');
  Check(ParseOnToall(Chr(33) + Chr(34) + Chr(35) + 'abc', Id, Text) and
    (Id = 130) and (Text = 'abc'), 'onToall reads the id and the text');
  Check(not ParseOnToall('ab', Id, Text), 'onToall ignores a body of two bytes');
  Check(not ParseOnToall(#32 + #32 + #31 + 'x', Id, Text),
    'onToall ignores a third byte below 32');
end;

procedure TestGs2;
var
  I, Present: Integer;
begin
  Check(not GrescrAccepted('GRESCR0'), 'a code buffer shorter than eight bytes is rejected');
  Check(not GrescrAccepted('XXXXXXXX'), 'the magic is GRESCR01');
  Check(GrescrAccepted('GRESCR01'), 'eight magic bytes are accepted');
  Check(GrescrCrcStart = 9, 'the CRC covers the bytes after the eight');
  Present := 0;
  for I := 11 to 242 do
    if Gs2CaseOf(I) = gscPresent then Inc(Present);
  Check(Present = 2 + 42, 'named present cases are 54, 121 and 201..242');
  Check(Gs2CaseOf(48) = gscAbsent, 'case 48 is absent');
  Check(Gs2CaseOf(49) = gscAbsent, 'case 49 is absent');
  Check(Gs2CaseOf(200) = gscAbsent, 'case 200 is absent');
  Check(Gs2CaseOf(11) = gscUnlisted, 'unnamed span cases stay unlisted');
  Check(Gs2CaseOf(10) = gscOutside, 'below 11 is outside the span');
  Check(Gs2CaseTotal = 152, 'the note''s case total is 152');
end;

procedure TestLevelAndCollision;
var
  S: TSession;
  Surf: TGSurface;
  Err: string;
  L: TLabLevel;
begin
  L := TLabLevel.Create;
  try
    Check(not L.LoadText('GR-V1.05' + #10 + 'no body', Err) and
      (Pos('not recovered', Err) > 0), 'GR-V1.05 body is not invented');
    Check(not L.LoadText('GLEVNW01' + #10, Err) and (Pos('not in the unpacked', Err) > 0),
      'GLEVNW01 is not this image''s level magic');
  finally
    L.Free;
  end;
  S := TSession.Create;
  Surf := TGSurface.Create(ViewW, ViewH);
  try
    Check(S.LoadLevelText('LABLVL1' + #10 + '5 1' + #10 + '.#@..'), 'adjacent-wall level');
    Check(S.MyX = 32, 'start is the @ cell');
    S.MoveBy(-LabStep, 0);
    Check(S.MyX = 32, 'a step into the wall does not move');
    S.MoveBy(LabStep, 0);
    Check(S.MyX = 36, 'a step onto floor moves');
    S.Free;
    S := TSession.Create;
    Check(S.LoadLevelText('LABLVL1' + #10 + '40 3' + #10 +
      StringOfChar('.', 30) + '@' + StringOfChar('.', 9) + #10 +
      StringOfChar('.', 40) + #10 + StringOfChar('.', 40)), 'wide level');
    Check(S.MyX = 30 * 16, 'wide start column');
    Check(S.CamX = 368, 'camera follows and stays inside the level');
    S.Free;
    S := TSession.Create;
    Check(S.LoadLevelText('LABLVL1' + #10 + '4 2' + #10 + '@.#.' + #10 + '....'),
      'render level');
    S.Render(Surf);
    Check(Surf.GetPixel(1, 1) = ColPlayer, 'the local player is drawn');
    Check(Surf.GetPixel(16, 0) = ColFloor, 'floor is drawn');
    Check(Surf.GetPixel(32, 0) = ColWall, 'a wall is drawn');
    Check(S.UdpOpens = 0, 'drawing does not open a datagram socket');
  finally
    Surf.Free;
    S.Free;
  end;
end;

function LocateYard: string;
var
  Dir: string;
  I: Integer;
  Cands: array[0..3] of string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Cands[0] := 'graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl';
  Cands[1] := 'levels/lab-yard.lvl';
  Cands[2] := Dir + '../../graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl';
  Cands[3] := Dir + '../levels/lab-yard.lvl';
  for I := 0 to 3 do
    if FileExists(Cands[I]) then
    begin
      Result := Cands[I];
      Exit;
    end;
  Result := '';
end;

procedure TestYardFile;
var
  S: TSession;
  Path: string;
begin
  Path := LocateYard;
  Check(Path <> '', 'lab-yard.lvl is in the repo');
  if Path = '' then Exit;
  S := TSession.Create;
  try
    Check(S.LoadLevelFile(Path), 'lab-yard.lvl loads: ' + Path);
    Check((S.MyX = 11 * 16) and (S.MyY = 6 * 16), 'yard start is the @ cell');
    Check(S.HasOther and (S.OtherX = 22 * 16), 'yard marker is lab-only local art');
  finally
    S.Free;
  end;
end;

procedure TestClearStop;
var
  Srv: TLabServer;
  S: TSession;
  I: Integer;
begin
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Check(Srv.Listen(0), 'lab listener on 127.0.0.1');
    S.Lab := False;
    Check(S.ConnectTo('127.0.0.1', Srv.Port), 'tcp connect');
    Check(S.Phase = phStoppedClear, 'without --lab the client stops at the clear hello');
    Check(S.UdpOpens = 0, 'connect path opens no datagram socket');
    for I := 1 to 30 do
    begin
      Srv.Pump;
      S.Pump;
      if S.BytesAfterHello > 0 then Break;
      Sleep(5);
    end;
    Check(Srv.GotHello, 'the server saw GNP1905C');
    Check(S.BytesAfterHello > 0, 'later server bytes were counted');
    Check(S.Props.Other = '', 'those bytes were not decoded as properties');
    Check(Pos('not decoded', Logs.Text) > 0, 'the log says the cipher was not identified');
    Check(Pos('GNP1905C', Logs.Text) = 0, 'the log does not echo a secret-looking token body');
  finally
    S.Free;
    Srv.Free;
  end;
end;

procedure TestLabRoundTrip;
var
  Srv: TLabServer;
  S: TSession;
  I: Integer;
  Body: string;
begin
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Check(S.LoadLevelText('LABLVL1' + #10 + '10 6' + #10 +
      '@.........' + #10 + '..........' + #10 + '..........' + #10 +
      '..........' + #10 + '..........' + #10 + '..........'), 'open yard');
    Check(Srv.Listen(0), 'second lab listener');
    S.Lab := True;
    Check(S.ConnectTo('127.0.0.1', Srv.Port), 'lab connect');
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if S.Phase = phLabWorld then Break;
      Sleep(5);
    end;
    Check(S.Phase = phLabWorld, 'lab fixture entered after the clear hello');
    Check(S.HasOther and (S.OtherId = LabOtherId), 'another entity was received');
    Check(LabDecodeProps(S.Props.Other, Body) and (Pos('name=other', Body) > 0),
      'that entity''s lab properties decoded');
    S.MoveBy(LabStep, 0);
    { The props frame follows the move echo. Loopback can deliver that
      second write on a later pump, so wait for step=2, not only Moves. }
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if (Srv.Moves > 0) and (S.MyX = LabStep) and
        (Pos('step=2', S.Props.Other) > 0) then Break;
      Sleep(5);
    end;
    Check(S.MovesSent = 1, 'a move was sent');
    Check((Srv.Moves = 1) and (Srv.PlayerX = LabStep), 'the lab server got the move');
    Check(S.MyX = LabStep, 'the echoed position is the position that was sent');
    Check(Pos('step=2', S.Props.Other) > 0, 'a later property update was stored');
    Check(S.UdpOpens = 0, 'the round trip stayed on TCP');
    Check(S.EndToken = 'clean', 'lab run ends clean');
  finally
    S.Free;
    Srv.Free;
  end;
end;


{ ---- connector login (6.11 method, SEI00001 scaffold) ---- }

function LocateConf: string;
var
  Dir: string;
  I: Integer;
  Cands: array[0..3] of string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Cands[0] := 'graal-6.1.1.3-GNP1905C/connector/sei00001-conf.gs';
  Cands[1] := 'connector/sei00001-conf.gs';
  Cands[2] := Dir + '../../graal-6.1.1.3-GNP1905C/connector/sei00001-conf.gs';
  Cands[3] := Dir + '../connector/sei00001-conf.gs';
  for I := 0 to 3 do
    if FileExists(Cands[I]) then
    begin
      Result := Cands[I];
      Exit;
    end;
  Result := '';
end;

function LoadConf: string;
var
  F: TFileStream;
  Path: string;
begin
  Result := '';
  Path := LocateConf;
  if Path = '' then Exit;
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TestSha256;
begin
  Check(Sha256Hex('') = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'SHA-256 of the empty string');
  Check(Sha256Hex('abc') = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'SHA-256 of abc');
  Check(Sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') =
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    'SHA-256 of the two-block FIPS vector');
end;

procedure TestConfReply;
var
  Reply, Sig, Payload, Err, Bad: string;
begin
  Reply := LoadConf;
  Check(Reply <> '', 'the signed SEI00001 conf.gs fixture is in the repo');
  if Reply = '' then Exit;
  Check(ParseConfReply(Reply, Sig, Payload, Err), 'conf.gs splits into signature and payload');
  Check(Length(Sig) = 256, 'the signature block is 256 bytes');
  Check(Length(Reply) = 4 + 256 + 4 + Length(Payload), 'reply is 4 + 256 + 4 + payload');
  Check(Payload = SeiConnectorScript, 'the fixture payload is the project connector script');
  Check(VerifyConfReply(Sig, Payload, Err), 'the project key verifies the fixture: ' + Err);
  Bad := Payload;
  Bad[Pos('SEI00001', Bad) + 7] := '2';
  Check(not VerifyConfReply(Sig, Bad, Err) and (Pos('digest', Err) > 0),
    'a changed token fails the digest check');
  Bad := Sig;
  Bad[100] := Chr(Ord(Bad[100]) xor 1);
  Check(not VerifyConfReply(Bad, Payload, Err), 'a changed signature is refused');
  Check(not ParseConfReply(Copy(Reply, 1, Length(Reply) - 1), Sig, Payload, Err),
    'a short reply is refused');
  Check(BuildConfReply(Copy(Reply, 5, 256), SeiConnectorScript) = Reply,
    'BuildConfReply writes big-endian lengths');
end;

type
  TConnectorRecorder = class
    Wire: string;
    Writes: Integer;
    function Send(const Data: string): Boolean;
  end;
function TConnectorRecorder.Send(const Data: string): Boolean;
begin Wire := Wire + Data; Inc(Writes); Result := True; end;

procedure TestProjectOutgoing;
var
  Steps: TConnectorSteps;
  P, Clear: TProtocol;
  Recorder: TConnectorRecorder;
  Peer: TRc4;
  Err, Token, Block, Key, PriorKey, Wire, Expected: string;
  Used, Run: Integer;
begin
  Check(ParseConnectorScript(SeiConnectorScript, Steps, Err), 'project script parses for outgoing boundary test');
  Steps[3].Args[1] := TestN; { existing test RSA pair, not a new committed private key }
  PriorKey := '';
  for Run := 1 to 2 do
  begin
    P := TProtocol.Create; Clear := TProtocol.Create;
    Recorder := TConnectorRecorder.Create;
    try
      Check(RunConnectorSteps(Steps, P, Recorder.Send, Token, Err, nil, TestD),
        'project script sends hello and complete clear key frame');
      Check((Recorder.Writes = 2) and (Copy(Recorder.Wire, 1, 8) = 'SEI00001'),
        'raw token precedes exactly one clear key-frame write');
      Check(ReadKeyFrame(Copy(Recorder.Wire, 9, MaxInt), Block, Used) and
        (Used = Length(Recorder.Wire) - 8), 'clear prefix has no encrypted or trailing bytes');
      Check(RsaUnwrapType2(TestN, TestD, Block, Key) and (Length(Key) = 16),
        'client RSA block contains exactly its fresh 16-byte key');
      if Run = 2 then Check(Key <> PriorKey, 'independent sessions generate different OS-random keys');
      PriorKey := Key;
      Peer := TRc4.Create(Key);
      try
        Clear.SetProtocol('EILLLT'); Clear.Counter := 3;
        Check(Clear.SendData(7, 'body', Expected, Err) and P.SendData(7, 'body', Wire, Err) and
          (Peer.Crypt(Wire) = Expected), 'first post-prefix frame encrypts header and body with stream byte zero');
      finally Peer.Free; end;
      Check(Steps[3].Args[0] = 'key', 'execution never rewrites parsed variable arguments');
    finally Recorder.Free; Clear.Free; P.Free; end;
  end;
end;

procedure TestConnectorScript;
var
  Steps: TConnectorSteps;
  Err, Token: string;
  P: TProtocol;
begin
  Check(SeiToken = 'SEI00001', 'the scaffold token is SEI00001');
  Check(not SeiTokenUsable, 'SEI00001 is marked not yet usable');
  Check(ParseConnectorScript(SeiConnectorScript, Steps, Err), 'the project script parses: ' + Err);
  Check((Length(Steps) = 7) and (Steps[0].Call = ccSetProtocol) and
    (Steps[1].Call = ccSendRaw) and (Steps[4].Call = ccSendKeyFrame),
    'project script emits clear key frame before selecting RC4');
  Check(Steps[0].Args[0] = 'EILLLT', 'the template is EILLLT');
  Check(Steps[1].Args[0] = SeiToken, 'sendRaw carries SEI00001');
  P := TProtocol.Create;
  try
    Check(RunConnectorSteps(Steps, P, nil, Token, Err, nil, '01'), 'the steps run: ' + Err);
    Check(Token = 'SEI00001', 'the token step reports SEI00001');
    Check(not P.OnGen5 and (P.HeaderLen = 6), 'EILLLT leaves generation-5 for a six-byte header');
    Check((P.FE.At = 0) and (P.FE.Width = 1) and (P.FI.At = 1) and (P.FI.Width = 1) and
      (P.FL.At = 2) and (P.FL.Width = 3) and (P.FT.At = 5) and (P.FT.Width = 1),
      'EILLLT is E at 0, I at 1, LLL at 2, T at 5');
    Check(P.Counter = 3, 'inner and outer key frames advance the counter twice');
    Check(P.Enc = eoRc4, 'project outgoing RC4 selected after clear key frame');
  finally
    P.Free;
  end;
  Check(not ParseConnectorScript('setProtocol("EILLLT"); exec("x");', Steps, Err) and
    (Pos('exec', Err) > 0), 'any other call is refused');
  Check(not ParseConnectorScript('sendRaw(SEI00001);', Steps, Err), 'arguments must be strings');
  Check(not ParseConnectorScript('function onCreated() { sendRaw("A");', Steps, Err),
    'an unclosed onCreated is refused');
end;

var
  ConnUnderTest: TLabConnector = nil;

procedure PumpConnector;
begin
  if ConnUnderTest <> nil then ConnUnderTest.Pump;
end;

procedure TestConnectorLogin;
var
  Con: TLabConnector;
  Srv: TLabServer;
  S: TSession;
  I, Counter, BeforeHeader: Integer;
  Started: QWord;
  Frame, KeyBlock: string;
  Peer: TRc4;
begin
  Con := TLabConnector.Create;
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Con.Reply := LoadConf;
    Check(Con.Listen(0) and Srv.Listen(0), 'connector and game listeners on 127.0.0.1');
    ConnUnderTest := Con;
    S.ConnectorIdle := PumpConnector;
    S.ParsePrivateExponent := '01'; { replaced with the test pair before synthetic reply }
    Check(S.ConnectViaConnector(Con.Port, Srv.Port), 'connector login runs: ' + S.Err);
    Check(Con.Requests = 1, 'one conf.gs request');
    Check(Pos('GET /conf.gs HTTP/1.0', Con.LastRequest) = 1, 'plain GET /conf.gs, no p= blob');
    Check(S.Phase = phProjectKey, 'project waits for server key without claiming account admission');
    Check(S.ConnectorToken = 'SEI00001', 'the token came from the connector script');
    Check(S.ConnectorSteps = 7, 'seven project connector steps ran');
    Check(S.UdpOpens = 0, 'the connector path opens no datagram socket');
    for I := 1 to 50 do
    begin
      Srv.Pump;
      if Srv.GotHello and (Length(Srv.AfterSei) > 6) then Break;
      Sleep(5);
    end;
    Check(Srv.GotHello and (Srv.Hello = 'SEI00001'), 'the game side saw SEI00001 first');
    Check(Length(Srv.AfterSei) > 6, 'a clear nested key frame follows the raw hello');
    Check(Pos('no account admission', Logs.Text) > 0, 'key exchange does not claim account admission');
    Check(Pos('signature verified', Logs.Text) > 0, 'the log shows the signature check');
    Check(S.EndToken = 'project-key-pending', 'the summary identifies pending project key');
    { This reproduction fixture supplies the existing test parse pair, not
      the shipped runtime pair and not a native/server admission oracle. }
    S.Project.SetParseKey(TestN, TestD);
    Counter := 1;
    KeyBlock := RsaWrapType2(TestN, BuildServerKeyPlain(1, '0123456789abcdef', ''), StringOfChar('P', 237));
    Frame := BuildKeyFrame(Counter, KeyBlock);
    Peer := TRc4.Create('0123456789abcdef');
    try
      BeforeHeader := S.BytesAfterHello;
      Check(Srv.SendProjectFixture(Copy(Frame, 1, 5)), 'CI socket fixture sends partial key header');
      Started := GetTickCount64;
      repeat
        S.Pump;
        if (S.BytesAfterHello - BeforeHeader >= 5) or (S.Phase = phError) or
          (GetTickCount64 - Started > 3000) then Break;
        Sleep(5);
      until False;
      Check((S.BytesAfterHello - BeforeHeader = 5) and (S.Phase = phProjectKey) and
        (S.ProjectReceived = ''), 'socket actually receives five clear bytes and buffers incomplete key');
      Check(Srv.SendProjectFixture(Copy(Frame, 6, MaxInt) + Peer.Crypt('first payload')),
        'CI socket fixture writes key tail and encrypted payload together');
      Started := GetTickCount64;
      repeat
        S.Pump;
        if ((S.Phase = phProjectTransport) and (S.ProjectReceived = 'first payload')) or
          (S.Phase = phError) or (GetTickCount64 - Started > 30000) then Break;
        Sleep(5);
      until False;
      Check((S.Phase = phProjectTransport) and (S.ProjectReceived = 'first payload'),
        'actual bounded socket path switches at complete key boundary');
      Check(Srv.SendProjectFixture(Peer.Crypt(' next')), 'CI socket fixture sends later ciphertext');
      Started := GetTickCount64;
      repeat
        S.Pump;
        if (S.ProjectReceived = 'first payload next') or (S.Phase = phError) or
          (GetTickCount64 - Started > 3000) then Break;
        Sleep(5);
      until False;
      Check((S.Phase = phProjectTransport) and (S.ProjectReceived = 'first payload next'),
        'actual socket path continues incoming RC4 without double decrypt');
    finally Peer.Free; end;
  finally
    ConnUnderTest := nil;
    S.Free;
    Srv.Free;
    Con.Free;
  end;
end;

procedure TestConnectorKey;
const
  Cands: array[0..2] of string = ('common/connector-lab-key/lab-signing-key.modulus',
    '../common/connector-lab-key/lab-signing-key.modulus',
    '../../common/connector-lab-key/lab-signing-key.modulus');
var
  Reply, Sig, Payload, Err, Tmp, LabFile: string;
  L: TStringList;
  I: Integer;
begin
  LabFile := '';
  for I := 0 to High(Cands) do
    if (LabFile = '') and FileExists(Cands[I]) then LabFile := Cands[I];
  Check(LabFile <> '', 'the open lab key modulus is in the repo');
  Check(ConnectorModulusHex = SeiPublicModulusHex, 'the lab key is trusted by default');
  Reply := LoadConf;
  Check(ParseConfReply(Reply, Sig, Payload, Err) and VerifyConfReply(Sig, Payload, Err),
    'the shipped conf.gs verifies under the lab key');
  if LabFile <> '' then
  begin
    Check(LoadConnectorKey(LabFile, Err) and (ConnectorModulusHex = SeiPublicModulusHex),
      'the lab key file is the compiled-in key: ' + Err);
  end;
  Tmp := GetTempDir + 'sei-operator-key.txt';
  L := TStringList.Create;
  try
    L.Text := 'Modulus=' + StringOfChar('D', 512);
    L.SaveToFile(Tmp);
    Check(LoadConnectorKey(Tmp, Err) and (ConnectorModulusHex = StringOfChar('D', 512)),
      'an operator key file in openssl -modulus form loads');
    Check(not VerifyConfReply(Sig, Payload, Err), 'the lab-signed conf.gs fails under another key');
    L.Text := 'ABCD';
    L.SaveToFile(Tmp);
    Check(not LoadConnectorKey(Tmp, Err) and (ConnectorModulusHex = StringOfChar('D', 512)),
      'a short key file is refused and changes nothing');
    Check(not LoadConnectorKey(Tmp + '.missing', Err), 'a missing key file is refused');
  finally
    L.Free;
    DeleteFile(Tmp);
    ConnectorModulusHex := SeiPublicModulusHex;
  end;
end;

procedure TestConnectorRefusesTamper;
var
  Con: TLabConnector;
  Srv: TLabServer;
  S: TSession;
  Reply: string;
begin
  Con := TLabConnector.Create;
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Reply := LoadConf;
    if Reply <> '' then
      Reply[Length(Reply) - 3] := 'X';
    Con.Reply := Reply;
    Check(Con.Listen(0) and Srv.Listen(0), 'tamper listeners on 127.0.0.1');
    ConnUnderTest := Con;
    S.ConnectorIdle := PumpConnector;
    Check(not S.ConnectViaConnector(Con.Port, Srv.Port), 'a tampered reply is refused');
    Check((S.Phase = phError) and (Pos('refused', S.Err) > 0), 'refused before any script runs');
    Check(S.ConnectorSteps = 0, 'no connector step ran');
    Srv.Pump;
    Check(not Srv.GotHello, 'the game side saw nothing');
  finally
    ConnUnderTest := nil;
    S.Free;
    Srv.Free;
    Con.Free;
  end;
end;

procedure TestRejectHost;
var
  S: TSession;
begin
  S := TSession.Create;
  try
    Check(not S.ConnectTo('other-host', 14900), 'a non-loopback host is refused');
    Check(S.Phase = phError, 'the refusal is an error state');
  finally
    S.Free;
  end;
end;

procedure TestControls;
var
  I: Integer;
  SawLevel, SawTiles, SawFont, Log: string;
  Bad: Boolean;
begin
  Check(ControlCount = 71, 'seventy-one 6.1.1.3 controls');
  Bad := False;
  SawLevel := '';
  SawTiles := '';
  SawFont := '';
  for I := 0 to ControlCount - 1 do
  begin
    if ControlName(I) = 'GuiGraalCtrl' then SawLevel := ControlName(I);
    if ControlName(I) = 'GuiTilesCtrl' then SawTiles := ControlName(I);
    if ControlName(I) = 'TFontData' then SawFont := ControlName(I);
    if (ControlName(I) = 'TDrawableObject') or (ControlName(I) = 'GuiTSCtrl') or
      (ControlName(I) = 'GuiBrowserCtrl') then
      Bad := True;
  end;
  Check(SawLevel = 'GuiGraalCtrl', 'GuiGraalCtrl is registered');
  Check(SawTiles = 'GuiTilesCtrl', 'GuiTilesCtrl is registered');
  Check(SawFont = 'TFontData', 'TFontData is the 6.1.1.3 font record');
  Check(not Bad, '6.037 drawable, browser and Torque scene view are absent');
  Log := LevelViewLog;
  Check(Pos('level view opened: GraalControl (GuiGraalCtrl)', Log) > 0,
    'the level view opens');
  Check(Pos('StartScript_Connector', Log) > 0, 'the connector script is named');
  Check(Pos('provisional', Log) = 0, 'the level-view log does not call the token provisional');
end;

function SecFromHex(const H: string): string;
  function Nib(C: Char): Integer;
  begin
    case C of
      '0'..'9': Nib := Ord(C) - Ord('0');
      'a'..'f': Nib := Ord(C) - Ord('a') + 10;
      'A'..'F': Nib := Ord(C) - Ord('A') + 10;
    else Nib := 0;
    end;
  end;
var I: Integer;
begin
  Result := '';
  I := 1;
  while I + 1 <= Length(H) do
  begin
    Result := Result + Chr((Nib(H[I]) shl 4) or Nib(H[I + 1]));
    Inc(I, 2);
  end;
end;

function SecToHex(const S: string): string;
const Hex = '0123456789abcdef';
var I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + Hex[(Ord(S[I]) shr 4) + 1] + Hex[(Ord(S[I]) and 15) + 1];
end;

function SecCounting(Start: Integer): string;
var I: Integer;
begin
  SetLength(Result, 32);
  for I := 0 to 31 do Result[I + 1] := Chr((Start + I) and 255);
end;

function SecU16le(N: Integer): string;
begin
  SetLength(Result, 2);
  Result[1] := Chr(N and 255);
  Result[2] := Chr((N shr 8) and 255);
end;

{ A minimal Seihai server responder, built from GSecCrypto, so the 6113
  client's handshake can be driven to C2 in-process without a live gserver.
  It mirrors seihai-gserver-v2's respond/open. }
procedure SecRespond(const C1, SxSecret, EdSeed: string; PrefixLen: Integer;
  out S1, Key, Th: string);
const
  SignContext = 'seihai-login-v1/server-hello'#0;
  C2SInfo = 'seihai-login-v1/c2s key';
var
  Sx, Ed, CxB64, Cx, Shared, Signed, Sig: string;
begin
  Sx := GSecCrypto.X25519Base(SxSecret);
  Ed := GSecCrypto.Ed25519PublicKey(EdSeed);
  CxB64 := Copy(C1, PrefixLen + 8 + 8 + 1, 43);
  GSecCrypto.B64Decode(CxB64, Cx);
  Shared := GSecCrypto.X25519(SxSecret, Cx);
  Signed := SignContext + SecU16le(Length(C1)) + C1 + Sx + Ed;
  Sig := GSecCrypto.Ed25519Sign(Signed, EdSeed);
  Th := GSecCrypto.Sha256(Signed + Sig);
  Key := GSecCrypto.HkdfSha256(Th, Shared, C2SInfo, 32);
  S1 := SeiToken + GSecCrypto.B64Encode(Sx) + GSecCrypto.B64Encode(Ed) +
    GSecCrypto.B64Encode(Sig);
end;

function SecOpenC2(const Key, Th, C2: string; out Tail: string): Boolean;
var
  BoxB64, Box, Plain, Nonce: string;
  TailLen: Integer;
begin
  Tail := '';
  Result := False;
  if Copy(C2, 1, Length(SeiToken)) <> SeiToken then Exit;
  BoxB64 := Copy(C2, Length(SeiToken) + 1, MaxInt);
  if not GSecCrypto.B64Decode(BoxB64, Box) then Exit;
  Nonce := StringOfChar(#0, 12);
  if not GSecCrypto.AeadOpen(Key, Nonce, Th, Box, Plain) then Exit;
  if Length(Plain) < 2 then Exit;
  TailLen := Ord(Plain[1]) or (Ord(Plain[2]) shl 8);
  if 2 + TailLen > Length(Plain) then Exit;
  Tail := Copy(Plain, 3, TailLen);
  Result := True;
end;

{ The SEI00001 secure login for the 6.1.1.3 build: the shared handshake with
  the 6113 inner token and login tail. Checked against seihai-gserver-v2's
  published client-side vector and an in-process round trip. }
procedure TestSecure6113;
const
  VEC_C1 = '%aSEI00001GNW28015ST6C/HRGSlkmiBdiPSBTxeuOLMSpiLT+4XnsawENUx0';
  VEC_S1 = 'SEI00001eaYx7t4b+cmPEgMs3q3Q56B5OY/HhriMyEbsia+FpRoA6EHv/POEL4dc' +
    'N0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg7zJvV7qQwbY7KXGIQCk96lPo4Yz5k+hwUWN7yoAwy' +
    'QvBbQYKvXjC95DPSXczo38vlSw7jgbWAVpcA8syQbicBw';
  VEC_C2 = 'SEI00001D9yUpUUI0R6VgG1QcRbQ5LtnZZDUOCJGnpXvFnAuE22eNVszliBIRzU' +
    'Llkn3lIeZLgFQLYiFyNuE5907zEQReQOFOsIkzAljPbqnfiME1Ok';
  VEC_EDPUB = '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
  VEC_FP = 'SHA256:Vkdap1RjR0wChd9dvyvKtz2mUTWIOem3dIGy6rEHcIw';
  VEC_TAIL = '%test1%labpw';
var
  HS: TSecHandshake;
  C1, S1, C2, Key, Th, Tail, Got: string;
begin
  { The 6113 login tail is GSTRING account then GSTRING password. }
  Check(Sei6113Tail('test1', 'labpw', '') = VEC_TAIL, '6113 tail is GSTRINGs');
  Check(Sei6113Inner = 'GNP1905C', 'the 6113 inner token is the build token');

  { Byte-for-byte against the server's published client-side vector. }
  HS := TSecHandshake.Create;
  try
    Check(HS.StartWith('%a', 'GNW28015', '', SecCounting($80)), 'vector C1 starts');
    Check(HS.Hello = VEC_C1, 'C1 matches the server vector');
    Check(HS.Finish(VEC_S1), 'S1 verifies against the server vector');
    Check(SecToHex(HS.ServerKey) = VEC_EDPUB, 'server key matches the vector');
    Check(KeyFingerprint(HS.ServerKey) = VEC_FP, 'fingerprint matches the vector');
    Check(HS.Seal(VEC_TAIL) = VEC_C2, 'C2 matches the server vector');
  finally
    HS.Free;
  end;

  { A full round trip with the 6113 inner token, against a conforming
    responder: the server opens C2 and reads back the sealed login tail. }
  HS := TSecHandshake.Create;
  try
    Check(HS.Start('%a', Sei6113Inner, ''), 'C1 starts with a fresh key');
    C1 := HS.Hello;
    Check(Copy(C1, 3, 8) = SeiToken, 'C1 carries the SEI00001 token after the prefix');
    Check(Copy(C1, 11, 8) = Sei6113Inner, 'C1 carries the 6113 inner token');
    SecRespond(C1, SecCounting($10), SecCounting($20), 2, S1, Key, Th);
    Check(HS.Finish(S1), 'the client accepts the responder S1');
    Check(HS.ServerKey = GSecCrypto.Ed25519PublicKey(SecCounting($20)),
      'the pinned server key is the responder key');
    Tail := Sei6113Tail('test1', 'labpw', '');
    C2 := HS.Seal(Tail);
    Check(SecOpenC2(Key, Th, C2, Got), 'the responder opens C2');
    Check(Got = Tail, 'the responder reads back the account and password');
  finally
    HS.Free;
  end;

  { A flipped S1 signature is refused. }
  HS := TSecHandshake.Create;
  try
    Check(HS.StartWith('%a', 'GNW28015', '', SecCounting($80)), 'tamper C1 starts');
    Check(not HS.Finish(Copy(VEC_S1, 1, Length(VEC_S1) - 1) + 'A'),
      'a changed S1 is refused');
  finally
    HS.Free;
  end;
end;

{ The plain zlib login-frame codec that carries the handshake lines over the
  game socket. }
procedure TestSecureNet;
var
  Enc, Line, Big: string;
  Bad, PoppedBig: Boolean;
begin
  { encode then pop recovers the line (short form) }
  Enc := SeiFrameEncode('SEI00001hello');
  Check(SeiFramePop(Enc, Line, Bad) and not Bad and (Line = 'SEI00001hello') and (Enc = ''),
    'frame codec round trip, short form');

  { a partial buffer pops nothing and is left intact }
  Enc := SeiFrameEncode('SEI00001abc');
  Line := Copy(Enc, 1, Length(Enc) - 1);
  Check(not SeiFramePop(Line, Line, Bad) and not Bad, 'a partial frame pops nothing');

  { the long-form length prefix (0xFFFF then a 32-bit length) is parsed.
    Built by hand so the branch runs without a 64 KB incompressible body. }
  Big := ZCompress('long-form payload' + #10);
  Enc := Chr($FF) + Chr($FF) +
    Chr((Length(Big) shr 24) and $FF) + Chr((Length(Big) shr 16) and $FF) +
    Chr((Length(Big) shr 8) and $FF) + Chr(Length(Big) and $FF) + Big;
  PoppedBig := SeiFramePop(Enc, Line, Bad);
  Check(PoppedBig and not Bad and (Line = 'long-form payload') and (Enc = ''),
    'frame codec pops the long-form length');

  { two frames in one buffer pop in order }
  Enc := SeiFrameEncode('one') + SeiFrameEncode('two');
  Check(SeiFramePop(Enc, Line, Bad) and (Line = 'one'), 'first of two frames');
  Check(SeiFramePop(Enc, Line, Bad) and (Line = 'two') and (Enc = ''), 'second of two frames');
end;

begin
  Passed := 0;
  Failed := 0;
  TestControls;
  Logs := TStringList.Create;
  SessionLog := Capture;
  try
    TestHelloAndRaw;
    TestRefusals;
    TestHeaderOrder;
    TestCompression;
    TestCipherChoice;
    TestSessionCipher;
    TestKeyFrames;
    TestProjectCipher;
    TestBoundedProjectSocket;
    TestProps;
    TestGs2;
    TestLevelAndCollision;
    TestYardFile;
    if ParamStr(1) <> '--offline' then
    begin TestClearStop; TestLabRoundTrip; end;
    TestRejectHost;
    TestSha256;
    TestSecure6113;
    if ParamStr(1) <> '--offline' then TestSecureNet;
    TestConfReply;
    TestConnectorScript;
    TestProjectOutgoing;
    if ParamStr(1) <> '--offline' then
    begin TestConnectorLogin; TestConnectorRefusesTamper; end;
    TestConnectorKey;
  finally
    SessionLog := nil;
    Logs.Free;
    Logs := nil;
  end;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then Halt(1);
end.
