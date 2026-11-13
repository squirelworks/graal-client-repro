{ Tests for the Seihai secure login (SEI00001) on the 2.22 wire: the game
  and list links against a server side written here from the spec. The
  primitives, the handshake checks, the pins and the modes are tested in
  graal-2.31-GNW28015/tests/TestSecLogin231.dpr (the units are shared). }
program TestSecLogin222;

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
  Protocol222 in '../src/Protocol222.pas',
  GraalClient in '../src/GraalClient.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  ListServer222 in '../src/ListServer222.pas';

type
  TClientAccess = class(TAdventureClient);
  TListAccess = class(TListServerClient);

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

{ ---- the 2.22 wire ---- }

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
    C.SecMode := smRequired;
    C.ServerKey := B64Encode(Ed25519PublicKey(UnHex(ServerSeed)));
    C.SendLogin('loop1', 'labpw123', 'English');
    F := SplitFrames(C.Sent);
    Check(F.Count = 1, 'secure: one frame before S1 (C1 alone)');
    Check(ZDecompress(F[0], Line), 'C1 is a plain zlib frame');
    Check(Copy(Line, 1, 18) = Chr($20 + ClientType) + Chr($20 + 64) + 'SEI00001' + ClientVersionToken,
      'C1: type 5, key, SEI00001, GNW28015');
    Check((Pos('labpw123', Line) = 0) and (Pos('loop1', Line) = 0), 'C1 has no account or password');
    Check(C.SecState = ssAwaitS1, 'waiting for S1');
    SetLength(Line, Length(Line) - 1);
    S1 := ServerHello(Line, 2);
    C.Sent := '';
    C.FeedRaw(Frame(ZCompress(S1 + #10)));
    Check(C.SecState = ssDone, 'S1 checked out: ' + C.SecWhy);
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
    C.SecMode := smRequired;
    C.SendLogin('loop1', 'labpw123', 'English');
    C.FeedRaw(Frame(ZCompress(Chr($20 + 16) + 'Secure login is turned off on this server.'#10)));
    Check((C.SecState = ssRefused) and (C.SecWhy = 'Secure login is turned off on this server.'),
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
    C.SecMode := smOff;
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
    C.SecMode := smRequired;
    C.ServerKey := B64Encode(Ed25519PublicKey(UnHex(ServerSeed)));
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
    Check((C.SecState = ssDone) and (F.Count = 1), 'list: S1 checks out, C2 alone');
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
  TestGameWire;
  TestListWire;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then Halt(1);
end.
