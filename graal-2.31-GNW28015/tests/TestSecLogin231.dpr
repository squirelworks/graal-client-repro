{ Tests for the Seihai secure login (SEI00001) in 2.31: the primitives
  against their RFC vectors, the handshake against a server side written
  here from the spec, the pins and modes, and the wire of the 2.31 game and
  list links. No framework: each check prints a line and the run exits 1
  if any failed. The loopback run against seihai-gserver is in the README. }
program TestSecLogin231;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GBzip2 in '../../common/GBzip2.pas',
  GSocket in '../../common/GSocket.pas',
  GSecCrypto in '../../common/GSecCrypto.pas',
  GSecLogin in '../../common/GSecLogin.pas',
  Protocol231 in '../src/Protocol231.pas',
  GraalClient in '../src/GraalClient.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  ListServer231 in '../src/ListServer231.pas';

type
  TClientAccess = class(TAdventureClient);
  TListAccess = class(TListServerClient);
  TNotes = class
    Text: string;
    procedure Note(const Line: string);
  end;

var
  Passed, Failed: Integer;

procedure TNotes.Note(const Line: string);
begin
  Text := Text + Line + #10;
end;

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

function Hex(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do Result := Result + LowerCase(IntToHex(Ord(S[I]), 2));
end;

function UnHex(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I < Length(S) do
  begin
    Result := Result + Chr(StrToInt('$' + Copy(S, I, 2)));
    Inc(I, 2);
  end;
end;

{ ---- primitives ---- }

procedure TestVectors;
const
  { RFC 8032 7.1 tests 1 and 2 }
  Sk1 = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
  Pk1 = 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
  Sig1 = 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';
  Sk2 = '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb';
  Pk2 = '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c';
  Sig2 = '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00';
  { RFC 8439 2.8.2 }
  AeadKey = '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f';
  AeadNonce = '070000004041424344454647';
  AeadAad = '50515253c0c1c2c3c4c5c6c7';
  AeadText = 'Ladies and Gentlemen of the class of ''99: If I could offer you only one tip for the future, sunscreen would be it.';
var
  S, Plain, BadS: string;
  I, Carry: Integer;
begin
  Check(Hex(Sha256('abc')) = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'SHA-256 "abc" (FIPS 180-4)');
  Check(Hex(Sha256('')) = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'SHA-256 of nothing');
  Check(Hex(Sha512('abc')) = 'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a' +
    '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f', 'SHA-512 "abc" (FIPS 180-4)');
  Check(Hex(HmacSha256(StringOfChar(#$0b, 20), 'Hi There')) =
    'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7', 'HMAC-SHA256 (RFC 4231 case 1)');
  Check(Hex(HkdfSha256(UnHex('000102030405060708090a0b0c'), StringOfChar(#$0b, 22),
    UnHex('f0f1f2f3f4f5f6f7f8f9'), 42)) =
    '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
    'HKDF-SHA256 (RFC 5869 case 1)');
  Check(Hex(X25519(UnHex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'),
    UnHex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'))) =
    'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552', 'X25519 (RFC 7748 5.2, first)');
  Check(Hex(X25519Base(UnHex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'))) =
    '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a', 'X25519 public key (RFC 7748 6.1, Alice)');
  Check(Hex(X25519(UnHex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
    UnHex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f'))) =
    '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742', 'X25519 shared secret (RFC 7748 6.1)');
  Check(IsZero32(X25519(UnHex(Sk1), StringOfChar(#0, 32))), 'X25519 with a zero peer key gives zero (abort case)');
  Check(Hex(Ed25519PublicKey(UnHex(Sk1))) = Pk1, 'Ed25519 public key (RFC 8032 test 1)');
  Check(Hex(Ed25519Sign('', UnHex(Sk1))) = Sig1, 'Ed25519 signature (RFC 8032 test 1)');
  Check(Ed25519Verify(UnHex(Sig1), '', UnHex(Pk1)), 'Ed25519 verify (RFC 8032 test 1)');
  Check(Hex(Ed25519PublicKey(UnHex(Sk2))) = Pk2, 'Ed25519 public key (RFC 8032 test 2)');
  Check(Ed25519Verify(UnHex(Sig2), #$72, UnHex(Pk2)), 'Ed25519 verify (RFC 8032 test 2)');
  Check(not Ed25519Verify(UnHex(Sig2), #$73, UnHex(Pk2)), 'Ed25519: another message fails');
  Check(not Ed25519Verify(UnHex(Sig1), '', UnHex(Pk2)), 'Ed25519: another key fails');
  { S + L: the same point equation, but S is not reduced }
  S := UnHex(Sig1);
  BadS := Copy(S, 33, 32);
  Carry := 0;
  for I := 1 to 32 do
  begin
    Carry := Carry + Ord(BadS[I]) + Ord(UnHex('edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010')[I]);
    BadS[I] := Chr(Carry and $FF);
    Carry := Carry shr 8;
  end;
  Check(not Ed25519Verify(Copy(S, 1, 32) + BadS, '', UnHex(Pk1)), 'Ed25519 strict: S at or above L is refused');
  Check(not Ed25519Verify(UnHex(Sig1), '', #1 + StringOfChar(#0, 31)), 'Ed25519 strict: a small-order key is refused');
  Check(Hex(Poly1305Mac(UnHex('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b'),
    'Cryptographic Forum Research Group')) = 'a8061dc1305136c6c22b8baf0c0127a9', 'Poly1305 (RFC 8439 2.5.2)');
  S := AeadSeal(UnHex(AeadKey), UnHex(AeadNonce), UnHex(AeadAad), AeadText);
  Check(Copy(Hex(S), 1, 32) = 'd31a8d34648e60db7b86afbc53ef7ec2', 'ChaCha20-Poly1305 ciphertext (RFC 8439 2.8.2)');
  Check(Copy(Hex(S), Length(Hex(S)) - 31, 32) = '1ae10b594f09e26a7e902ecbd0600691', 'ChaCha20-Poly1305 tag (RFC 8439 2.8.2)');
  Check(AeadOpen(UnHex(AeadKey), UnHex(AeadNonce), UnHex(AeadAad), S, Plain) and (Plain = AeadText),
    'ChaCha20-Poly1305 opens');
  S[5] := Chr(Ord(S[5]) xor 1);
  Check(not AeadOpen(UnHex(AeadKey), UnHex(AeadNonce), UnHex(AeadAad), S, Plain), 'ChaCha20-Poly1305: a changed byte fails');
  Check((B64Encode('') = '') and (B64Encode('f') = 'Zg') and (B64Encode('fo') = 'Zm8') and
    (B64Encode('foo') = 'Zm9v') and (B64Encode('foob') = 'Zm9vYg'), 'base64 without padding (RFC 4648 vectors)');
  Check(B64Decode('Zm9vYmE', S) and (S = 'fooba') and B64Decode('Zm9vYmE=', S) and (S = 'fooba'),
    'base64 decode, padding optional');
  Check(not B64Decode('Zm9v!', S) and not B64Decode('Zh', S), 'base64: bad characters and non-zero spare bits fail');
  Check(RandomBytes(32, S) and (Length(S) = 32), 'random bytes from the system');
end;

{ ---- a server side, from the spec ---- }

const
  ServerSeed = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
  ServerEph = 'a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf';

var
  SrvTh, SrvKey: string;

function U16(N: Integer): string;
begin
  Result := Chr(N and $FF) + Chr(N shr 8);
end;

{ S1 for C1 (without its line feed); PrefixLen bytes come before the token. }
function ServerHello(const C1: string; PrefixLen: Integer): string;
var
  ClientPub, Eph, Id, Signed, Sig: string;
begin
  B64Decode(Copy(C1, PrefixLen + 17, 43), ClientPub);
  Eph := X25519Base(UnHex(ServerEph));
  Id := Ed25519PublicKey(UnHex(ServerSeed));
  Signed := 'seihai-login-v1/server-hello'#0 + U16(Length(C1)) + C1 + Eph + Id;
  Sig := Ed25519Sign(Signed, UnHex(ServerSeed));
  SrvTh := Sha256(Signed + Sig);
  SrvKey := HkdfSha256(SrvTh, X25519(UnHex(ServerEph), ClientPub), 'seihai-login-v1/c2s key', 32);
  Result := 'SEI00001' + B64Encode(Eph) + B64Encode(Id) + B64Encode(Sig);
end;

function ServerOpen(const C2: string; out Tail: string): Boolean;
var
  Ct, P: string;
  N, I: Integer;
begin
  Result := False;
  Tail := '';
  if Copy(C2, 1, 8) <> 'SEI00001' then Exit;
  if not B64Decode(Copy(C2, 9, MaxInt), Ct) then Exit;
  if not AeadOpen(SrvKey, StringOfChar(#0, 12), SrvTh, Ct, P) then Exit;
  if Length(P) mod 64 <> 0 then Exit;
  N := Ord(P[1]) or (Ord(P[2]) shl 8);
  for I := N + 3 to Length(P) do
    if P[I] <> #0 then Exit;
  Tail := Copy(P, 3, N);
  Result := True;
end;

procedure TestHandshake;
var
  H: TSecHandshake;
  S1, C2, Tail, Bad: string;
begin
  H := TSecHandshake.Create;
  try
    Check(H.StartWith(#$25#$40, 'GNW28015', '', StringOfChar(#7, 32)), 'C1 builds');
    Check((Copy(H.Hello, 1, 18) = #$25#$40'SEI00001GNW28015') and (Length(H.Hello) = 2 + 16 + 43),
      'C1 is prefix, SEI00001, the inner token and a 43-character key');
    S1 := ServerHello(H.Hello, 2);
    Bad := S1;
    Bad[60] := Chr(Ord(Bad[60]) xor 1);
    Check(not H.Finish(Bad), 'a changed S1 fails: ' + H.Error);
    Check(not H.Finish('GNW28015' + Copy(S1, 9, MaxInt)), 'an S1 without the token fails');
    Check(not H.Finish(Copy(S1, 1, Length(S1) - 1)), 'a short S1 fails');
    Check(H.Finish(S1 + #10), 'S1 verifies');
    Check(H.ServerKey = Ed25519PublicKey(UnHex(ServerSeed)), 'the server key is the signer''s');
    C2 := H.Seal(#$25'loop1'#$28'labpw123');
    Check((Copy(C2, 1, 8) = 'SEI00001') and (Pos('labpw123', C2) = 0), 'C2: the token and base64 only');
    Check(ServerOpen(C2, Tail) and (Tail = #$25'loop1'#$28'labpw123'), 'the server opens C2 to the tail');
    Check(H.Seal('again') = '', 'the key is used once');
    { a C1 changed on the way: the signature no longer covers it }
    Check(H.StartWith(#$25#$40, 'GNW28015', '', StringOfChar(#7, 32)), 'C1 again');
    S1 := ServerHello(#$25#$40'SEI00001GNW03014' + Copy(H.Hello, 19, MaxInt), 2);
    Check(not H.Finish(S1), 'an inner token changed in transit fails the signature');
    Check(not H.StartWith(#$25#$40, 'GNW2801', '', StringOfChar(#7, 32)), 'an inner token not 8 bytes is refused');
  finally
    H.Free;
  end;
end;

{ ---- pins and modes ---- }

procedure TestPins;
var
  Dir, Pinned, K1, K2: string;
  M: TSecMode;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'seclogin-test-' + IntToStr(GetProcessID);
  PinDirOverride := Dir;
  try
    K1 := StringOfChar('a', 32);
    K2 := StringOfChar('b', 32);
    Check(PinCheck('h:1', K1, Pinned) = prUnknown, 'no pin file: unknown');
    Check(PinAppend('h:1', K1), 'pin append reports successful persistence');
    Check(PinCheck('h:1', K1, Pinned) = prMatches, 'pinned key matches');
    Check((PinCheck('h:1', K2, Pinned) = prMismatch) and (Pinned = K1), 'another key: mismatch, names the pinned one');
    Check(PinCheck('h:2', K1, Pinned) = prUnknown, 'pins are per host:port');
    Check(not WasRefused('h:3'), 'nothing refused yet');
    RememberRefused('h:3');
    RememberRefused('h:3');
    Check(WasRefused('h:3'), 'a refusal is remembered');
    Check(not ShouldProbe(smOff, 'h:1'), 'off never probes');
    Check(ShouldProbe(smAuto, 'h:2') and not ShouldProbe(smAuto, 'h:3'), 'auto skips a server that refused');
    RememberRefused('h:1');
    Check(ShouldProbe(smAuto, 'h:1'), 'auto always probes a pinned server');
    Check(ShouldProbe(smRequired, 'h:3'), 'required always probes');
    Check(MayFallBack(smAuto, 'h:2') and not MayFallBack(smAuto, 'h:1'), 'sticky rule: no fallback once pinned');
    Check(not MayFallBack(smRequired, 'h:2') and not MayFallBack(smOff, 'h:2'), 'only auto falls back');
    Check(ParseSecMode(' Required ', M) and (M = smRequired) and not ParseSecMode('yes', M), 'mode names');
    if GetEnvironmentVariable('GRAAL_SECURE_LOGIN') = '' then
      Check(ConfiguredSecMode = smOff, 'the default is off (the original login)');
    with TStringList.Create do
    try
      Add('auto');
      SaveToFile(IncludeTrailingPathDelimiter(Dir) + 'secure_login.txt');
    finally
      Free;
    end;
    if GetEnvironmentVariable('GRAAL_SECURE_LOGIN') = '' then
      Check(ConfiguredSecMode = smAuto, 'secure_login.txt in the settings folder sets the mode');
    SetSecure(smRequired, 'k');
    Check((ConfiguredSecMode = smRequired) and (ConfiguredServerKey = 'k'), '--secure-login overrides it');
    ClearSecure;
    DeleteFile(IncludeTrailingPathDelimiter(Dir) + 'secure_login.txt');
    Check(KeyFingerprint(K1) = 'SHA256:' + B64Encode(Sha256(K1)), 'fingerprint: SHA256: and base64');
  finally
    DeleteFile(PinFile);
    DeleteFile(RefusedFile);
    RemoveDir(Dir);
    PinDirOverride := '';
  end;
end;

{ ---- the 2.31 wire ---- }

{ the frames in Sent, bodies only }
function SplitFrames(const S: string): TStringList;
var
  P, N: Integer;
begin
  Result := TStringList.Create;
  P := 1;
  while P + 1 <= Length(S) do
  begin
    N := (Ord(S[P]) shl 8) or Ord(S[P + 1]);
    Result.Add(Copy(S, P + 2, N));
    Inc(P, N + 2);
  end;
end;

function Frame(const Body: string): string;
begin
  Result := Chr(Length(Body) shr 8) + Chr(Length(Body) and $FF) + Body;
end;

procedure TestPinPersistence;
var
  Dir: string;
  Notes: TNotes;
  FileText: TStringList;

  procedure Login(ExpectSuccess: Boolean; const What: string);
  var
    C: TClientAccess;
    F: TStringList;
    Line, Tail, Pinned: string;
  begin
    Notes.Text := '';
    C := TClientAccess.Create;
    F := nil;
    try
      C.StartOffline(64);
      C.Sink := True;
      C.Sec.Reset('h:1');
      C.Sec.Mode := smAuto;
      C.Sec.OnNote := Notes.Note;
      C.SendLogin('loop1', 'labpw123', 'English');
      F := SplitFrames(C.Sent);
      Check((F.Count = 1) and ZDecompress(F[0], Line), What + ': C1 only before S1');
      SetLength(Line, Length(Line) - 1);
      C.Sent := '';
      C.FeedRaw(Frame(ZCompress(ServerHello(Line, 2) + #10)));
      if ExpectSuccess then
      begin
        Check(C.Sec.State = ssDone, What + ': handshake accepted');
        Check(PinCheck('h:1', Ed25519PublicKey(UnHex(ServerSeed)), Pinned) = prMatches,
          What + ': key readable from pin file');
        F.Free;
        F := SplitFrames(C.Sent);
        Check((F.Count = 2) and ZDecompress(F[0], Line), What + ': C2 and language sent');
        SetLength(Line, Length(Line) - 1);
        Check(ServerOpen(Line, Tail) and (Tail = GString('loop1') + GString('labpw123')),
          What + ': C2 opens after pin was saved');
        Check(Pos('(saved in ', Notes.Text) > 0, What + ': save message is truthful');
        Check(not MayFallBack(smAuto, 'h:1'), What + ': persisted pin prevents fallback');
      end
      else
      begin
        Check((C.Sec.State = ssFailed) and (C.Sent = ''), What + ': no C2 or password sent');
        Check(Pos('cannot read the server key file', C.Sec.Why) > 0, What + ': useful trust-store error');
        Check(Pos('(saved in ', Notes.Text) = 0, What + ': no false save message');
      end;
    finally
      F.Free;
      C.Free;
    end;
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'seclogin-persist-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  Notes := TNotes.Create;
  FileText := TStringList.Create;
  try
    PinDirOverride := Dir;
    ForceDirectories(PinFile);  { deterministic open failure even as root }
    Check(not PinAppend('h:1', StringOfChar('a', 32)), 'non-file pin path cannot be written');
    RememberRefused('h:1');
    Check(WasRefused('h:1') and ShouldProbe(smAuto, 'h:1'),
      'unavailable trust store overrides a cached refusal');
    Check(not MayFallBack(smAuto, 'h:1'), 'unavailable trust store forbids classic fallback');
    Check(not ShouldProbe(smOff, 'h:1'), 'explicit off ignores the unavailable trust store');
    Login(False, 'pin path is a directory');
    RemoveDir(PinFile);
    DeleteFile(RefusedFile);
    FileText.Add('not a folder');
    FileText.SaveToFile(IncludeTrailingPathDelimiter(Dir) + 'blocked');
    PinDirOverride := IncludeTrailingPathDelimiter(Dir) + 'blocked';
    Check(not PinAppend('h:1', StringOfChar('a', 32)), 'regular-file parent cannot hold a pin');
    Check(not MayFallBack(smAuto, 'h:1'), 'regular-file parent forbids classic fallback');
    Login(False, 'pin parent is a regular file');
    PinDirOverride := Dir;
    Login(True, 'writable pin file');
  finally
    PinDirOverride := Dir;
    DeleteFile(PinFile);
    DeleteFile(RefusedFile);
    RemoveDir(PinFile);
    DeleteFile(IncludeTrailingPathDelimiter(Dir) + 'blocked');
    PinDirOverride := '';
    FileText.Free;
    Notes.Free;
    RemoveDir(Dir);
  end;
end;

procedure TestGameWire;
var
  C: TClientAccess;
  F: TStringList;
  Line, S1, Tail: string;
begin
  C := TClientAccess.Create;
  F := nil;
  try
    C.StartOffline(64);
    C.Sink := True;
    C.Sec.Mode := smRequired;
    C.Sec.ServerKey := B64Encode(Ed25519PublicKey(UnHex(ServerSeed)));
    C.SendLogin('loop1', 'labpw123', 'English');
    F := SplitFrames(C.Sent);
    Check(F.Count = 1, 'secure: one frame before S1 (C1 alone)');
    Check(ZDecompress(F[0], Line), 'C1 is a plain zlib frame');
    Check(Copy(Line, 1, 18) = Chr($20 + ClientType) + Chr($20 + 64) + 'SEI00001' + ClientVersionToken,
      'C1: type 5, key, SEI00001, GNW28015');
    Check((Pos('labpw123', Line) = 0) and (Pos('loop1', Line) = 0), 'C1 has no account or password');
    Check(C.Sec.State = ssAwaitS1, 'waiting for S1');
    SetLength(Line, Length(Line) - 1);
    S1 := ServerHello(Line, 2);
    C.Sent := '';
    C.FeedRaw(Frame(ZCompress(S1 + #10)));
    Check(C.Sec.State = ssDone, 'S1 checked out: ' + C.Sec.Why);
    F.Free;
    F := SplitFrames(C.Sent);
    Check(F.Count = 2, 'then C2 and the language frame');
    Check(ZDecompress(F[0], Line) and (Copy(Line, 1, 8) = 'SEI00001'), 'C2 in a plain zlib frame');
    SetLength(Line, Length(Line) - 1);
    Check(ServerOpen(Line, Tail) and (Tail = GString('loop1') + GString('labpw123')),
      'C2 seals the classic tail: account and password');
    Check((F[1] <> '') and (Ord(F[1][1]) in [2, 4]), 'the language and tamper check follow in gen 5');
  finally
    F.Free;
    C.Free;
  end;
  { a refusal in place of S1 }
  C := TClientAccess.Create;
  try
    C.StartOffline(64);
    C.Sink := True;
    C.Sec.Mode := smRequired;
    C.SendLogin('loop1', 'labpw123', 'English');
    C.FeedRaw(Frame(ZCompress(Chr($20 + 16) + 'Secure login is turned off on this server.'#10)));
    Check((C.Sec.State = ssRefused) and (C.Sec.Why = 'Secure login is turned off on this server.'),
      'a refusal ends the handshake with its text');
  finally
    C.Free;
  end;
  { off: the original login, byte for byte }
  C := TClientAccess.Create;
  F := nil;
  try
    C.StartOffline(64);
    C.Sink := True;
    C.Sec.Mode := smOff;
    C.SendLogin('loop1', 'labpw123', 'English');
    C.Flush;
    F := SplitFrames(C.Sent);
    Check(ZDecompress(F[0], Line) and (Line = Chr($20 + ClientType) + Chr($20 + 64) + ClientVersionToken +
      GString('loop1') + GString('labpw123') + #10), 'off: the classic login line');
  finally
    F.Free;
    C.Free;
  end;
end;

procedure TestListWire;
var
  C: TListAccess;
  F: TStringList;
  Line, Tail: string;
begin
  C := TListAccess.Create;
  F := nil;
  try
    C.StartOffline(33);
    C.Sink := True;
    C.Sec.Mode := smRequired;
    C.Sec.ServerKey := B64Encode(Ed25519PublicKey(UnHex(ServerSeed)));
    C.SendRequest('loop1', 'labpw123');
    F := SplitFrames(C.Sent);
    Check((F.Count = 1) and ZDecompress(F[0], Line), 'list: C1 alone, plain zlib');
    Check((Copy(Line, 1, 18) = Chr($20 + 7) + Chr($20 + 33) + 'SEI00001' + ListToken) and
      (Copy(Line, Length(Line) - 7, 8) = ListVersion + #10), 'list C1: id 7, key, SEI00001, GNW30123, key, newmain');
    SetLength(Line, Length(Line) - 1);
    C.Sent := '';
    C.FeedRaw(Frame(ZCompress(ServerHello(Line, 2) + #10)));
    F.Free;
    F := SplitFrames(C.Sent);
    Check((C.Sec.State = ssDone) and (F.Count = 1), 'list: S1 checks out, C2 alone');
    Check(ZDecompress(F[0], Line), 'list C2 in a plain zlib frame');
    SetLength(Line, Length(Line) - 1);
    Check(ServerOpen(Line, Tail) and (Tail = GString('loop1') + GString('labpw123')), 'list C2 seals id 1''s payload');
  finally
    F.Free;
    C.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestVectors;
  TestHandshake;
  TestPins;
  TestPinPersistence;
  TestGameWire;
  TestListWire;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
