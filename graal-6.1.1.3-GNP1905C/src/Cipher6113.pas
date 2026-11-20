{ Cipher6113: the 6.1x key frames for the project session cipher.

  connector/CIPHER.md chose the stock 6.11 shape for both directions
  (Graal_analysis protocol/v611-outgoing-cipher.md,
  protocol/connector-script.md section 4c):

  - The key frame is one clear outer EILLLT packet, id 0xfd, E 1 (zlib),
    whose inflated body is one inner EILLLT packet, id 0xfc, E 0, with a
    256-byte RSA-2048 block. The inner packet takes the counter first and
    the outer one next (1 and 2 on a fresh connection). LLL counts the
    six header bytes plus the body.
  - The server's block unwraps (PKCS #1 v1.5 type 2) to the cipher type
    (1 RC4, 2 AES), then the key and the IV, each after a length byte
    stored as the length plus 32.
  - The project client's block wraps its raw 16-byte RC4 key. (The stock
    client's plaintext layout is not known; this project defines its own.)

  Written from those notes and RFC 8017; nothing here comes from a Graal
  image. }
unit Cipher6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  KeyFrameInner = $fc;
  KeyFrameOuter = $fd;
  KeyTypeRc4 = 1;
  KeyTypeAes = 2;

{ Cipher type, then key and IV each after a length byte plus 32. Empty when
  the key or IV is longer than 223 bytes. }
function BuildServerKeyPlain(CipherType: Integer; const Key, IV: string): string;
function ParseServerKeyPlain(const Plain: string; out CipherType: Integer;
  out Key, IV: string): Boolean;

{ The clear 0xfd(zlib) packet wrapping the 0xfc packet with Block. Counter
  is the next packet counter; it goes up by two. }
function BuildKeyFrame(var Counter: Integer; const Block: string): string;
{ Read one key frame from the front of Wire. Block is the 0xfc body, Used
  the bytes taken. False when Wire does not start with a whole key frame. }
function ReadKeyFrame(const Wire: string; out Block: string; out Used: Integer): Boolean;

implementation

uses
  GZlib;

function U24(N: Integer): string;
begin
  Result := Chr((N shr 16) and 255) + Chr((N shr 8) and 255) + Chr(N and 255);
end;

function RdU24(const S: string; At: Integer): Integer;
begin
  Result := (Ord(S[At]) shl 16) or (Ord(S[At + 1]) shl 8) or Ord(S[At + 2]);
end;

function BuildServerKeyPlain(CipherType: Integer; const Key, IV: string): string;
begin
  Result := '';
  if (Length(Key) > 223) or (Length(IV) > 223) or (CipherType < 0) or (CipherType > 255) then Exit;
  Result := Chr(CipherType) + Chr(Length(Key) + 32) + Key + Chr(Length(IV) + 32) + IV;
end;

function ParseServerKeyPlain(const Plain: string; out CipherType: Integer;
  out Key, IV: string): Boolean;
var
  At, N: Integer;
begin
  Result := False;
  CipherType := 0;
  Key := '';
  IV := '';
  if Length(Plain) < 3 then Exit;
  CipherType := Ord(Plain[1]);
  N := Ord(Plain[2]) - 32;
  if (N < 0) or (2 + N + 1 > Length(Plain)) then Exit;
  Key := Copy(Plain, 3, N);
  At := 3 + N;
  N := Ord(Plain[At]) - 32;
  if (N < 0) or (At + N <> Length(Plain)) then Exit;
  IV := Copy(Plain, At + 1, N);
  Result := True;
end;

function BuildKeyFrame(var Counter: Integer; const Block: string): string;
var
  Inner, Z: string;
begin
  Inner := #0 + Chr(Counter and 255) + U24(6 + Length(Block)) + Chr(KeyFrameInner) + Block;
  Z := ZCompress(Inner);
  Result := #1 + Chr((Counter + 1) and 255) + U24(6 + Length(Z)) + Chr(KeyFrameOuter) + Z;
  Inc(Counter, 2);
end;

function ReadKeyFrame(const Wire: string; out Block: string; out Used: Integer): Boolean;
var
  Len: Integer;
  Inner: string;
begin
  Result := False;
  Block := '';
  Used := 0;
  if Length(Wire) < 6 then Exit;
  Len := RdU24(Wire, 3);
  if (Wire[1] <> #1) or (Ord(Wire[6]) <> KeyFrameOuter) or (Len < 6) or (Len > Length(Wire)) then Exit;
  if not ZDecompress(Copy(Wire, 7, Len - 6), Inner) then Exit;
  if (Length(Inner) < 6) or (Inner[1] <> #0) or (Ord(Inner[6]) <> KeyFrameInner) or
    (RdU24(Inner, 3) <> Length(Inner)) then Exit;
  Block := Copy(Inner, 7, MaxInt);
  Used := Len;
  Result := True;
end;

end.
