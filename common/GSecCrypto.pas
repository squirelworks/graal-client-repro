{ GSecCrypto: the primitives of the Seihai secure login (SEI00001), in
  plain Pascal so no runtime library has to ship with any build.

  SHA-256 and SHA-512 (FIPS 180-4), HMAC-SHA256 (RFC 2104), HKDF-SHA256
  (RFC 5869), X25519 (RFC 7748), strict Ed25519 verification (RFC 8032),
  ChaCha20-Poly1305 (RFC 8439), base64 without padding, and a random source
  from the operating system.

  The field and group code follows the public-domain TweetNaCl layout
  (sixteen 16-bit limbs in Int64, constant-time selects). Nothing here is
  from a Graal client: no Graal build had any of this. The tests check every
  primitive against its RFC vectors.

  Byte strings are AnsiStrings, like the rest of the network code. }
unit GSecCrypto;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{ the hashes, the field limbs and the counters wrap on purpose }
{$Q-}{$R-}

interface

function Sha256(const Data: string): string;
function Sha512(const Data: string): string;
function HmacSha256(const Key, Data: string): string;
{ HKDF-SHA256 extract-and-expand; Len at most 255 * 32. }
function HkdfSha256(const Salt, Ikm, Info: string; Len: Integer): string;

{ X25519(scalar, u): both 32 bytes. }
function X25519(const Scalar, U: string): string;
{ X25519(scalar, 9): the public key of a secret. }
function X25519Base(const Scalar: string): string;
{ True when Shared is all zero (a small-order peer key: abort). }
function IsZero32(const Shared: string): Boolean;

{ Strict Ed25519 check of a 64-byte signature over Msg under a 32-byte key:
  S below the group order, both points canonical and not of small order,
  and the unbatched equation [S]B = R + [k]A. }
function Ed25519Verify(const Sig, Msg, PublicKey: string): Boolean;
{ Signing, for the tests' own server side only (Seed is 32 bytes). }
function Ed25519PublicKey(const Seed: string): string;
function Ed25519Sign(const Msg, Seed: string): string;

{ The ChaCha20 stream XORed over Data from block Counter. }
function ChaCha20Xor(const Key, Nonce: string; Counter: Cardinal; const Data: string): string;
function Poly1305Mac(const Key, Msg: string): string;
{ AEAD (RFC 8439 2.8): ciphertext with the 16-byte tag after it. }
function AeadSeal(const Key, Nonce, Aad, Plain: string): string;
{ False if the tag does not match (Plain is then empty). }
function AeadOpen(const Key, Nonce, Aad, Sealed: string; out Plain: string): Boolean;

{ Standard alphabet, no padding, no line breaks. }
function B64Encode(const Data: string): string;
{ False on a character outside the alphabet or an impossible length;
  trailing '=' are accepted and ignored. }
function B64Decode(const Text: string; out Data: string): Boolean;

{ N bytes from the operating system's generator. False if none could be
  read (the secure login then does not start). }
function RandomBytes(N: Integer; out Data: string): Boolean;

{ Equal length and bytes, in time that does not depend on where they differ. }
function SameBytes(const A, B: string): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  SysUtils;

{ ---- small helpers ---- }

function SameBytes(const A, B: string): Boolean;
var
  I: Integer;
  D: Byte;
begin
  Result := False;
  if Length(A) <> Length(B) then Exit;
  D := 0;
  for I := 1 to Length(A) do D := D or (Ord(A[I]) xor Ord(B[I]));
  Result := D = 0;
end;

function IsZero32(const Shared: string): Boolean;
var
  I: Integer;
  D: Byte;
begin
  D := 0;
  for I := 1 to Length(Shared) do D := D or Ord(Shared[I]);
  Result := D = 0;
end;

function Rol32(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shl N) or (X shr (32 - N));
end;

function Ror32(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

function Ror64(X: QWord; N: Integer): QWord; inline;
begin
  Result := (X shr N) or (X shl (64 - N));
end;

function LE32(const S: string; P: Integer): Cardinal; inline;
begin
  Result := Cardinal(Ord(S[P])) or (Cardinal(Ord(S[P + 1])) shl 8) or
    (Cardinal(Ord(S[P + 2])) shl 16) or (Cardinal(Ord(S[P + 3])) shl 24);
end;

function LE32Str(V: Cardinal): string;
begin
  Result := Chr(V and $FF) + Chr((V shr 8) and $FF) + Chr((V shr 16) and $FF) +
    Chr((V shr 24) and $FF);
end;

function LE64Str(V: QWord): string;
begin
  Result := LE32Str(Cardinal(V and $FFFFFFFF)) + LE32Str(Cardinal(V shr 32));
end;

{ ---- SHA-256 ---- }

const
  K256: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

function Sha256(const Data: string): string;
var
  H: array[0..7] of Cardinal;
  W: array[0..63] of Cardinal;
  M: string;
  A, B, C, D, E, F, G, HH, T1, T2: Cardinal;
  I, J, P: Integer;
  BitLen: QWord;
begin
  H[0] := $6a09e667; H[1] := $bb67ae85; H[2] := $3c6ef372; H[3] := $a54ff53a;
  H[4] := $510e527f; H[5] := $9b05688c; H[6] := $1f83d9ab; H[7] := $5be0cd19;
  BitLen := QWord(Length(Data)) * 8;
  M := Data + #$80;
  while Length(M) mod 64 <> 56 do M := M + #0;
  for I := 7 downto 0 do M := M + Chr((BitLen shr (8 * I)) and $FF);
  P := 1;
  while P <= Length(M) do
  begin
    for J := 0 to 15 do
      W[J] := (Cardinal(Ord(M[P + J * 4])) shl 24) or (Cardinal(Ord(M[P + J * 4 + 1])) shl 16) or
        (Cardinal(Ord(M[P + J * 4 + 2])) shl 8) or Cardinal(Ord(M[P + J * 4 + 3]));
    for J := 16 to 63 do
      W[J] := (Ror32(W[J - 2], 17) xor Ror32(W[J - 2], 19) xor (W[J - 2] shr 10)) + W[J - 7] +
        (Ror32(W[J - 15], 7) xor Ror32(W[J - 15], 18) xor (W[J - 15] shr 3)) + W[J - 16];
    A := H[0]; B := H[1]; C := H[2]; D := H[3];
    E := H[4]; F := H[5]; G := H[6]; HH := H[7];
    for J := 0 to 63 do
    begin
      T1 := HH + (Ror32(E, 6) xor Ror32(E, 11) xor Ror32(E, 25)) + ((E and F) xor ((not E) and G)) +
        K256[J] + W[J];
      T2 := (Ror32(A, 2) xor Ror32(A, 13) xor Ror32(A, 22)) + ((A and B) xor (A and C) xor (B and C));
      HH := G; G := F; F := E; E := D + T1;
      D := C; C := B; B := A; A := T1 + T2;
    end;
    Inc(H[0], A); Inc(H[1], B); Inc(H[2], C); Inc(H[3], D);
    Inc(H[4], E); Inc(H[5], F); Inc(H[6], G); Inc(H[7], HH);
    Inc(P, 64);
  end;
  Result := '';
  for I := 0 to 7 do
    Result := Result + Chr(H[I] shr 24) + Chr((H[I] shr 16) and $FF) +
      Chr((H[I] shr 8) and $FF) + Chr(H[I] and $FF);
end;

{ ---- SHA-512 ---- }

const
  K512: array[0..79] of QWord = (
    QWord($428a2f98d728ae22), QWord($7137449123ef65cd), QWord($b5c0fbcfec4d3b2f), QWord($e9b5dba58189dbbc),
    QWord($3956c25bf348b538), QWord($59f111f1b605d019), QWord($923f82a4af194f9b), QWord($ab1c5ed5da6d8118),
    QWord($d807aa98a3030242), QWord($12835b0145706fbe), QWord($243185be4ee4b28c), QWord($550c7dc3d5ffb4e2),
    QWord($72be5d74f27b896f), QWord($80deb1fe3b1696b1), QWord($9bdc06a725c71235), QWord($c19bf174cf692694),
    QWord($e49b69c19ef14ad2), QWord($efbe4786384f25e3), QWord($0fc19dc68b8cd5b5), QWord($240ca1cc77ac9c65),
    QWord($2de92c6f592b0275), QWord($4a7484aa6ea6e483), QWord($5cb0a9dcbd41fbd4), QWord($76f988da831153b5),
    QWord($983e5152ee66dfab), QWord($a831c66d2db43210), QWord($b00327c898fb213f), QWord($bf597fc7beef0ee4),
    QWord($c6e00bf33da88fc2), QWord($d5a79147930aa725), QWord($06ca6351e003826f), QWord($142929670a0e6e70),
    QWord($27b70a8546d22ffc), QWord($2e1b21385c26c926), QWord($4d2c6dfc5ac42aed), QWord($53380d139d95b3df),
    QWord($650a73548baf63de), QWord($766a0abb3c77b2a8), QWord($81c2c92e47edaee6), QWord($92722c851482353b),
    QWord($a2bfe8a14cf10364), QWord($a81a664bbc423001), QWord($c24b8b70d0f89791), QWord($c76c51a30654be30),
    QWord($d192e819d6ef5218), QWord($d69906245565a910), QWord($f40e35855771202a), QWord($106aa07032bbd1b8),
    QWord($19a4c116b8d2d0c8), QWord($1e376c085141ab53), QWord($2748774cdf8eeb99), QWord($34b0bcb5e19b48a8),
    QWord($391c0cb3c5c95a63), QWord($4ed8aa4ae3418acb), QWord($5b9cca4f7763e373), QWord($682e6ff3d6b2b8a3),
    QWord($748f82ee5defb2fc), QWord($78a5636f43172f60), QWord($84c87814a1f0ab72), QWord($8cc702081a6439ec),
    QWord($90befffa23631e28), QWord($a4506cebde82bde9), QWord($bef9a3f7b2c67915), QWord($c67178f2e372532b),
    QWord($ca273eceea26619c), QWord($d186b8c721c0c207), QWord($eada7dd6cde0eb1e), QWord($f57d4f7fee6ed178),
    QWord($06f067aa72176fba), QWord($0a637dc5a2c898a6), QWord($113f9804bef90dae), QWord($1b710b35131c471b),
    QWord($28db77f523047d84), QWord($32caab7b40c72493), QWord($3c9ebe0a15c9bebc), QWord($431d67c49c100d4c),
    QWord($4cc5d4becb3e42b6), QWord($597f299cfc657e2a), QWord($5fcb6fab3ad6faec), QWord($6c44198c4a475817));

function Sha512(const Data: string): string;
var
  H: array[0..7] of QWord;
  W: array[0..79] of QWord;
  M: string;
  A, B, C, D, E, F, G, HH, T1, T2: QWord;
  I, J, K, P: Integer;
  BitLen: QWord;
begin
  H[0] := QWord($6a09e667f3bcc908); H[1] := QWord($bb67ae8584caa73b);
  H[2] := QWord($3c6ef372fe94f82b); H[3] := QWord($a54ff53a5f1d36f1);
  H[4] := QWord($510e527fade682d1); H[5] := QWord($9b05688c2b3e6c1f);
  H[6] := QWord($1f83d9abfb41bd6b); H[7] := QWord($5be0cd19137e2179);
  BitLen := QWord(Length(Data)) * 8;
  M := Data + #$80;
  while Length(M) mod 128 <> 112 do M := M + #0;
  for I := 1 to 8 do M := M + #0; { the high 64 bits of the length }
  for I := 7 downto 0 do M := M + Chr((BitLen shr (8 * I)) and $FF);
  P := 1;
  while P <= Length(M) do
  begin
    for J := 0 to 15 do
    begin
      W[J] := 0;
      for K := 0 to 7 do W[J] := (W[J] shl 8) or QWord(Ord(M[P + J * 8 + K]));
    end;
    for J := 16 to 79 do
      W[J] := (Ror64(W[J - 2], 19) xor Ror64(W[J - 2], 61) xor (W[J - 2] shr 6)) + W[J - 7] +
        (Ror64(W[J - 15], 1) xor Ror64(W[J - 15], 8) xor (W[J - 15] shr 7)) + W[J - 16];
    A := H[0]; B := H[1]; C := H[2]; D := H[3];
    E := H[4]; F := H[5]; G := H[6]; HH := H[7];
    for J := 0 to 79 do
    begin
      T1 := HH + (Ror64(E, 14) xor Ror64(E, 18) xor Ror64(E, 41)) + ((E and F) xor ((not E) and G)) +
        K512[J] + W[J];
      T2 := (Ror64(A, 28) xor Ror64(A, 34) xor Ror64(A, 39)) + ((A and B) xor (A and C) xor (B and C));
      HH := G; G := F; F := E; E := D + T1;
      D := C; C := B; B := A; A := T1 + T2;
    end;
    H[0] := H[0] + A; H[1] := H[1] + B; H[2] := H[2] + C; H[3] := H[3] + D;
    H[4] := H[4] + E; H[5] := H[5] + F; H[6] := H[6] + G; H[7] := H[7] + HH;
    Inc(P, 128);
  end;
  Result := '';
  for I := 0 to 7 do
    for K := 7 downto 0 do
      Result := Result + Chr((H[I] shr (8 * K)) and $FF);
end;

{ ---- HMAC and HKDF ---- }

function HmacSha256(const Key, Data: string): string;
var
  K, IPad, OPad: string;
  I: Integer;
begin
  K := Key;
  if Length(K) > 64 then K := Sha256(K);
  while Length(K) < 64 do K := K + #0;
  SetLength(IPad, 64);
  SetLength(OPad, 64);
  for I := 1 to 64 do
  begin
    IPad[I] := Chr(Ord(K[I]) xor $36);
    OPad[I] := Chr(Ord(K[I]) xor $5C);
  end;
  Result := Sha256(OPad + Sha256(IPad + Data));
end;

function HkdfSha256(const Salt, Ikm, Info: string; Len: Integer): string;
var
  Prk, T: string;
  N: Integer;
begin
  if Salt = '' then Prk := HmacSha256(StringOfChar(#0, 32), Ikm)
  else Prk := HmacSha256(Salt, Ikm);
  Result := '';
  T := '';
  N := 1;
  while (Length(Result) < Len) and (N <= 255) do
  begin
    T := HmacSha256(Prk, T + Info + Chr(N));
    Result := Result + T;
    Inc(N);
  end;
  SetLength(Result, Len);
end;

{ ---- GF(2^255 - 19), sixteen 16-bit limbs ---- }

type
  TGf = array[0..15] of Int64;
  TBytes32 = array[0..31] of Byte;
  TPoint = array[0..3] of TGf;

const
  Gf0: TGf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  Gf1: TGf = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  Gf121665: TGf = ($DB41, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  GfD: TGf = ($78a3, $1359, $4dca, $75eb, $d8ab, $4141, $0a4d, $0070,
    $e898, $7779, $4079, $8cc7, $fe73, $2b6f, $6cee, $5203);
  GfD2: TGf = ($f159, $26b2, $9b94, $ebd6, $b156, $8283, $149a, $00e0,
    $d130, $eef3, $80f2, $198e, $fce7, $56df, $d9dc, $2406);
  GfX: TGf = ($d51a, $8f25, $2d60, $c956, $a7b2, $9525, $c760, $692c,
    $dc5c, $fdd6, $e231, $c0a4, $53fe, $cd6e, $36d3, $2169);
  GfY: TGf = ($6658, $6666, $6666, $6666, $6666, $6666, $6666, $6666,
    $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666);
  GfI: TGf = ($a0b0, $4a0e, $1b27, $c4ee, $e478, $ad2f, $1806, $2f43,
    $d7a7, $3dfb, $0099, $2b4d, $df0b, $4fc1, $2480, $2b83);
  { the group order L, little endian }
  OrderL: array[0..31] of Int64 = ($ed, $d3, $f5, $5c, $1a, $63, $12, $58,
    $d6, $9c, $f7, $a2, $de, $f9, $de, $14, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, $10);

function Sar(V: Int64; N: Integer): Int64; inline;
begin
  Result := SarInt64(V, N);
end;

procedure Car25519(var O: TGf);
var
  I: Integer;
  C: Int64;
begin
  for I := 0 to 15 do
  begin
    O[I] := O[I] + 65536;
    C := Sar(O[I], 16);
    if I < 15 then O[I + 1] := O[I + 1] + C - 1
    else O[0] := O[0] + 38 * (C - 1);
    O[I] := O[I] - C * 65536;
  end;
end;

procedure Sel25519(var P, Q: TGf; B: Integer);
var
  I: Integer;
  C, T: Int64;
begin
  C := not (Int64(B) - 1);
  for I := 0 to 15 do
  begin
    T := C and (P[I] xor Q[I]);
    P[I] := P[I] xor T;
    Q[I] := Q[I] xor T;
  end;
end;

procedure Pack25519(out O: TBytes32; const N: TGf);
var
  I, J: Integer;
  B: Integer;
  M, T: TGf;
begin
  T := N;
  Car25519(T);
  Car25519(T);
  Car25519(T);
  for J := 0 to 1 do
  begin
    M[0] := T[0] - $FFED;
    for I := 1 to 14 do
    begin
      M[I] := T[I] - $FFFF - (Sar(M[I - 1], 16) and 1);
      M[I - 1] := M[I - 1] and $FFFF;
    end;
    M[15] := T[15] - $7FFF - (Sar(M[14], 16) and 1);
    B := Integer(Sar(M[15], 16) and 1);
    M[14] := M[14] and $FFFF;
    Sel25519(T, M, 1 - B);
  end;
  for I := 0 to 15 do
  begin
    O[2 * I] := T[I] and $FF;
    O[2 * I + 1] := Sar(T[I], 8) and $FF;
  end;
end;

procedure Unpack25519(out O: TGf; const N: TBytes32);
var
  I: Integer;
begin
  for I := 0 to 15 do O[I] := Int64(N[2 * I]) + (Int64(N[2 * I + 1]) shl 8);
  O[15] := O[15] and $7FFF;
end;

function Neq25519(const A, B: TGf): Boolean;
var
  C, D: TBytes32;
  I: Integer;
  X: Byte;
begin
  Pack25519(C, A);
  Pack25519(D, B);
  X := 0;
  for I := 0 to 31 do X := X or (C[I] xor D[I]);
  Result := X <> 0;
end;

function Par25519(const A: TGf): Integer;
var
  D: TBytes32;
begin
  Pack25519(D, A);
  Result := D[0] and 1;
end;

procedure FAdd(out O: TGf; const A, B: TGf);
var
  I: Integer;
begin
  for I := 0 to 15 do O[I] := A[I] + B[I];
end;

procedure FSub(out O: TGf; const A, B: TGf);
var
  I: Integer;
begin
  for I := 0 to 15 do O[I] := A[I] - B[I];
end;

procedure FMul(out O: TGf; const A, B: TGf);
var
  T: array[0..30] of Int64;
  I, J: Integer;
  R: TGf;
begin
  for I := 0 to 30 do T[I] := 0;
  for I := 0 to 15 do
    for J := 0 to 15 do
      T[I + J] := T[I + J] + A[I] * B[J];
  for I := 0 to 14 do T[I] := T[I] + 38 * T[I + 16];
  for I := 0 to 15 do R[I] := T[I];
  Car25519(R);
  Car25519(R);
  O := R;
end;

procedure FSqr(out O: TGf; const A: TGf);
begin
  FMul(O, A, A);
end;

procedure Inv25519(out O: TGf; const I: TGf);
var
  C: TGf;
  A: Integer;
begin
  C := I;
  for A := 253 downto 0 do
  begin
    FSqr(C, C);
    if (A <> 2) and (A <> 4) then FMul(C, C, I);
  end;
  O := C;
end;

procedure Pow2523(out O: TGf; const I: TGf);
var
  C: TGf;
  A: Integer;
begin
  C := I;
  for A := 250 downto 0 do
  begin
    FSqr(C, C);
    if A <> 1 then FMul(C, C, I);
  end;
  O := C;
end;

procedure StrTo32(const S: string; out B: TBytes32);
var
  I: Integer;
begin
  for I := 0 to 31 do
    if I < Length(S) then B[I] := Ord(S[I + 1]) else B[I] := 0;
end;

function B32ToStr(const B: TBytes32): string;
var
  I: Integer;
begin
  SetLength(Result, 32);
  for I := 0 to 31 do Result[I + 1] := Chr(B[I]);
end;

{ ---- X25519 ---- }

function X25519(const Scalar, U: string): string;
var
  Z, P, Q: TBytes32;
  X, A, B, C, D, E, F: TGf;
  I, R: Integer;
begin
  StrTo32(Scalar, Z);
  StrTo32(U, P);
  Z[31] := (Z[31] and 127) or 64;
  Z[0] := Z[0] and 248;
  Unpack25519(X, P);
  B := X;
  A := Gf1; C := Gf0; D := Gf1;
  for I := 254 downto 0 do
  begin
    R := (Z[I shr 3] shr (I and 7)) and 1;
    Sel25519(A, B, R);
    Sel25519(C, D, R);
    FAdd(E, A, C);
    FSub(A, A, C);
    FAdd(C, B, D);
    FSub(B, B, D);
    FSqr(D, E);
    FSqr(F, A);
    FMul(A, C, A);
    FMul(C, B, E);
    FAdd(E, A, C);
    FSub(A, A, C);
    FSqr(B, A);
    FSub(C, D, F);
    FMul(A, C, Gf121665);
    FAdd(A, A, D);
    FMul(C, C, A);
    FMul(A, D, F);
    FMul(D, B, X);
    FSqr(B, E);
    Sel25519(A, B, R);
    Sel25519(C, D, R);
  end;
  Inv25519(C, C);
  FMul(A, A, C);
  Pack25519(Q, A);
  Result := B32ToStr(Q);
end;

function X25519Base(const Scalar: string): string;
begin
  Result := X25519(Scalar, #9 + StringOfChar(#0, 31));
end;

{ ---- Ed25519 ---- }

procedure PAdd(var P: TPoint; const Q: TPoint);
var
  A, B, C, D, T, E, F, G, H: TGf;
begin
  FSub(A, P[1], P[0]);
  FSub(T, Q[1], Q[0]);
  FMul(A, A, T);
  FAdd(B, P[0], P[1]);
  FAdd(T, Q[0], Q[1]);
  FMul(B, B, T);
  FMul(C, P[3], Q[3]);
  FMul(C, C, GfD2);
  FMul(D, P[2], Q[2]);
  FAdd(D, D, D);
  FSub(E, B, A);
  FSub(F, D, C);
  FAdd(G, D, C);
  FAdd(H, B, A);
  FMul(P[0], E, F);
  FMul(P[1], H, G);
  FMul(P[2], G, F);
  FMul(P[3], E, H);
end;

procedure PSwap(var P, Q: TPoint; B: Integer);
var
  I: Integer;
begin
  for I := 0 to 3 do Sel25519(P[I], Q[I], B);
end;

procedure PPack(out R: TBytes32; const P: TPoint);
var
  Tx, Ty, Zi: TGf;
begin
  Inv25519(Zi, P[2]);
  FMul(Tx, P[0], Zi);
  FMul(Ty, P[1], Zi);
  Pack25519(R, Ty);
  R[31] := R[31] xor (Par25519(Tx) shl 7);
end;

{ P = [S]Q; Q is used as scratch. }
procedure PScalarMult(out P: TPoint; var Q: TPoint; const S: TBytes32);
var
  I, B: Integer;
  T: TPoint;
begin
  P[0] := Gf0; P[1] := Gf1; P[2] := Gf1; P[3] := Gf0;
  for I := 255 downto 0 do
  begin
    B := (S[I shr 3] shr (I and 7)) and 1;
    PSwap(P, Q, B);
    PAdd(Q, P);
    T := P;
    PAdd(P, T);
    PSwap(P, Q, B);
  end;
end;

procedure PScalarBase(out P: TPoint; const S: TBytes32);
var
  Q: TPoint;
begin
  Q[0] := GfX;
  Q[1] := GfY;
  Q[2] := Gf1;
  FMul(Q[3], GfX, GfY);
  PScalarMult(P, Q, S);
end;

procedure ModL(out R: TBytes32; var X: array of Int64);
var
  Carry: Int64;
  I, J: Integer;
begin
  for I := 63 downto 32 do
  begin
    Carry := 0;
    J := I - 32;
    while J < I - 12 do
    begin
      X[J] := X[J] + Carry - 16 * X[I] * OrderL[J - (I - 32)];
      Carry := Sar(X[J] + 128, 8);
      X[J] := X[J] - Carry * 256;
      Inc(J);
    end;
    X[J] := X[J] + Carry;
    X[I] := 0;
  end;
  Carry := 0;
  for J := 0 to 31 do
  begin
    X[J] := X[J] + Carry - Sar(X[31], 4) * OrderL[J];
    Carry := Sar(X[J], 8);
    X[J] := X[J] and 255;
  end;
  for J := 0 to 31 do X[J] := X[J] - Carry * OrderL[J];
  for I := 0 to 31 do
  begin
    X[I + 1] := X[I + 1] + Sar(X[I], 8);
    R[I] := X[I] and 255;
  end;
end;

{ a 64-byte little-endian number mod L }
procedure Reduce64(const H: string; out R: TBytes32);
var
  X: array[0..63] of Int64;
  I: Integer;
begin
  for I := 0 to 63 do X[I] := Ord(H[I + 1]);
  ModL(R, X);
end;

{ -P from its encoding; False if it is not a point. }
function UnpackNeg(out R: TPoint; const P: TBytes32): Boolean;
var
  T, Chk, Num, Den, Den2, Den4, Den6: TGf;
begin
  Result := False;
  R[2] := Gf1;
  Unpack25519(R[1], P);
  FSqr(Num, R[1]);
  FMul(Den, Num, GfD);
  FSub(Num, Num, R[2]);
  FAdd(Den, R[2], Den);
  FSqr(Den2, Den);
  FSqr(Den4, Den2);
  FMul(Den6, Den4, Den2);
  FMul(T, Den6, Num);
  FMul(T, T, Den);
  Pow2523(T, T);
  FMul(T, T, Num);
  FMul(T, T, Den);
  FMul(T, T, Den);
  FMul(R[0], T, Den);
  FSqr(Chk, R[0]);
  FMul(Chk, Chk, Den);
  if Neq25519(Chk, Num) then FMul(R[0], R[0], GfI);
  FSqr(Chk, R[0]);
  FMul(Chk, Chk, Den);
  if Neq25519(Chk, Num) then Exit;
  if Par25519(R[0]) = (P[31] shr 7) then FSub(R[0], Gf0, R[0]);
  FMul(R[3], R[0], R[1]);
  Result := True;
end;

{ y below p, and x = 0 not given a set sign bit }
function CanonicalPoint(const P: TBytes32): Boolean;
var
  Y: TGf;
  B: TBytes32;
  I: Integer;
begin
  Unpack25519(Y, P);
  Pack25519(B, Y);
  Result := True;
  for I := 0 to 30 do
    if B[I] <> P[I] then Result := False;
  if B[31] <> (P[31] and $7F) then Result := False;
end;

{ [8]P is the neutral point }
function SmallOrder(const P: TPoint): Boolean;
var
  Q, T: TPoint;
  E: TBytes32;
  I: Integer;
begin
  Q := P;
  for I := 1 to 3 do
  begin
    T := Q;
    PAdd(Q, T);
  end;
  PPack(E, Q);
  Result := E[0] = 1;
  for I := 1 to 31 do
    if E[I] <> 0 then Result := False;
end;

{ S < L }
function ScalarBelowL(const S: string): Boolean;
var
  I: Integer;
begin
  for I := 31 downto 0 do
  begin
    if Ord(S[I + 1]) < OrderL[I] then begin Result := True; Exit; end;
    if Ord(S[I + 1]) > OrderL[I] then begin Result := False; Exit; end;
  end;
  Result := False; { equal to L }
end;

function Ed25519Verify(const Sig, Msg, PublicKey: string): Boolean;
var
  PkB, RB, SB, HB, T: TBytes32;
  NegA, NegR, P, Q: TPoint;
  I: Integer;
  D: Byte;
begin
  Result := False;
  if (Length(Sig) <> 64) or (Length(PublicKey) <> 32) then Exit;
  if not ScalarBelowL(Copy(Sig, 33, 32)) then Exit;
  StrTo32(PublicKey, PkB);
  StrTo32(Copy(Sig, 1, 32), RB);
  StrTo32(Copy(Sig, 33, 32), SB);
  if not CanonicalPoint(PkB) or not CanonicalPoint(RB) then Exit;
  if not UnpackNeg(NegA, PkB) or not UnpackNeg(NegR, RB) then Exit;
  if SmallOrder(NegA) or SmallOrder(NegR) then Exit;
  Reduce64(Sha512(Copy(Sig, 1, 32) + PublicKey + Msg), HB);
  PScalarMult(P, NegA, HB); { -[k]A }
  PScalarBase(Q, SB);       { [S]B }
  PAdd(P, Q);
  PPack(T, P);
  D := 0;
  for I := 0 to 31 do D := D or (T[I] xor RB[I]);
  Result := D = 0;
end;

function Ed25519PublicKey(const Seed: string): string;
var
  H: string;
  A: TBytes32;
  P: TPoint;
begin
  H := Sha512(Copy(Seed, 1, 32));
  StrTo32(H, A);
  A[0] := A[0] and 248;
  A[31] := (A[31] and 127) or 64;
  PScalarBase(P, A);
  PPack(A, P);
  Result := B32ToStr(A);
end;

function Ed25519Sign(const Msg, Seed: string): string;
var
  H, Pk: string;
  A, RB, KB, RE: TBytes32;
  P: TPoint;
  X: array[0..63] of Int64;
  I, J: Integer;
begin
  H := Sha512(Copy(Seed, 1, 32));
  StrTo32(H, A);
  A[0] := A[0] and 248;
  A[31] := (A[31] and 127) or 64;
  Pk := Ed25519PublicKey(Seed);
  Reduce64(Sha512(Copy(H, 33, 32) + Msg), RB);
  PScalarBase(P, RB);
  PPack(RE, P);
  Reduce64(Sha512(B32ToStr(RE) + Pk + Msg), KB);
  for I := 0 to 63 do X[I] := 0;
  for I := 0 to 31 do X[I] := RB[I];
  for I := 0 to 31 do
    for J := 0 to 31 do
      X[I + J] := X[I + J] + Int64(KB[I]) * Int64(A[J]);
  ModL(KB, X);
  Result := B32ToStr(RE) + B32ToStr(KB);
end;

{ ---- ChaCha20 and Poly1305 ---- }

procedure ChaChaBlock(const Key, Nonce: string; Counter: Cardinal; out Block: string);
var
  S, X: array[0..15] of Cardinal;
  I: Integer;

  procedure QR(A, B, C, D: Integer);
  begin
    X[A] := X[A] + X[B]; X[D] := Rol32(X[D] xor X[A], 16);
    X[C] := X[C] + X[D]; X[B] := Rol32(X[B] xor X[C], 12);
    X[A] := X[A] + X[B]; X[D] := Rol32(X[D] xor X[A], 8);
    X[C] := X[C] + X[D]; X[B] := Rol32(X[B] xor X[C], 7);
  end;

begin
  S[0] := $61707865; S[1] := $3320646e; S[2] := $79622d32; S[3] := $6b206574;
  for I := 0 to 7 do S[4 + I] := LE32(Key, 1 + 4 * I);
  S[12] := Counter;
  for I := 0 to 2 do S[13 + I] := LE32(Nonce, 1 + 4 * I);
  X := S;
  for I := 1 to 10 do
  begin
    QR(0, 4, 8, 12); QR(1, 5, 9, 13); QR(2, 6, 10, 14); QR(3, 7, 11, 15);
    QR(0, 5, 10, 15); QR(1, 6, 11, 12); QR(2, 7, 8, 13); QR(3, 4, 9, 14);
  end;
  Block := '';
  for I := 0 to 15 do Block := Block + LE32Str(X[I] + S[I]);
end;

function ChaCha20Xor(const Key, Nonce: string; Counter: Cardinal; const Data: string): string;
var
  Block: string;
  I, P: Integer;
begin
  Result := Data;
  UniqueString(Result);
  P := 1;
  while P <= Length(Data) do
  begin
    ChaChaBlock(Key, Nonce, Counter, Block);
    for I := 0 to 63 do
    begin
      if P + I > Length(Data) then Break;
      Result[P + I] := Chr(Ord(Result[P + I]) xor Ord(Block[I + 1]));
    end;
    Inc(Counter);
    Inc(P, 64);
  end;
end;

function Poly1305Mac(const Key, Msg: string): string;
const
  Mask26 = $3FFFFFF;
var
  R0, R1, R2, R3, R4, S1, S2, S3, S4: QWord;
  H0, H1, H2, H3, H4, G0, G1, G2, G3, G4, C, Hibit, M: QWord;
  D0, D1, D2, D3, D4, F: QWord;
  Blk: string;
  P, N: Integer;
begin
  R0 := LE32(Key, 1) and $3FFFFFF;
  R1 := (LE32(Key, 4) shr 2) and $3FFFF03;
  R2 := (LE32(Key, 7) shr 4) and $3FFC0FF;
  R3 := (LE32(Key, 10) shr 6) and $3F03FFF;
  R4 := (LE32(Key, 13) shr 8) and $00FFFFF;
  S1 := R1 * 5; S2 := R2 * 5; S3 := R3 * 5; S4 := R4 * 5;
  H0 := 0; H1 := 0; H2 := 0; H3 := 0; H4 := 0;
  P := 1;
  while P <= Length(Msg) do
  begin
    N := Length(Msg) - P + 1;
    if N >= 16 then
    begin
      Blk := Copy(Msg, P, 16);
      Hibit := QWord(1) shl 24;
    end
    else
    begin
      Blk := Copy(Msg, P, N) + #1 + StringOfChar(#0, 15 - N);
      Hibit := 0;
    end;
    H0 := H0 + (LE32(Blk, 1) and Mask26);
    H1 := H1 + ((LE32(Blk, 4) shr 2) and Mask26);
    H2 := H2 + ((LE32(Blk, 7) shr 4) and Mask26);
    H3 := H3 + ((LE32(Blk, 10) shr 6) and Mask26);
    H4 := H4 + ((LE32(Blk, 13) shr 8) or Hibit);
    D0 := H0 * R0 + H1 * S4 + H2 * S3 + H3 * S2 + H4 * S1;
    D1 := H0 * R1 + H1 * R0 + H2 * S4 + H3 * S3 + H4 * S2;
    D2 := H0 * R2 + H1 * R1 + H2 * R0 + H3 * S4 + H4 * S3;
    D3 := H0 * R3 + H1 * R2 + H2 * R1 + H3 * R0 + H4 * S4;
    D4 := H0 * R4 + H1 * R3 + H2 * R2 + H3 * R1 + H4 * R0;
    C := D0 shr 26; H0 := D0 and Mask26;
    D1 := D1 + C; C := D1 shr 26; H1 := D1 and Mask26;
    D2 := D2 + C; C := D2 shr 26; H2 := D2 and Mask26;
    D3 := D3 + C; C := D3 shr 26; H3 := D3 and Mask26;
    D4 := D4 + C; C := D4 shr 26; H4 := D4 and Mask26;
    H0 := H0 + C * 5; C := H0 shr 26; H0 := H0 and Mask26;
    H1 := H1 + C;
    Inc(P, 16);
  end;
  C := H1 shr 26; H1 := H1 and Mask26;
  H2 := H2 + C; C := H2 shr 26; H2 := H2 and Mask26;
  H3 := H3 + C; C := H3 shr 26; H3 := H3 and Mask26;
  H4 := H4 + C; C := H4 shr 26; H4 := H4 and Mask26;
  H0 := H0 + C * 5; C := H0 shr 26; H0 := H0 and Mask26;
  H1 := H1 + C;
  { h + -p }
  G0 := H0 + 5; C := G0 shr 26; G0 := G0 and Mask26;
  G1 := H1 + C; C := G1 shr 26; G1 := G1 and Mask26;
  G2 := H2 + C; C := G2 shr 26; G2 := G2 and Mask26;
  G3 := H3 + C; C := G3 shr 26; G3 := G3 and Mask26;
  G4 := H4 + C - (QWord(1) shl 26);
  { G4's top bit set: h was below p, keep h }
  M := (G4 shr 63) - 1; { all ones when h >= p }
  G0 := G0 and M; G1 := G1 and M; G2 := G2 and M; G3 := G3 and M; G4 := G4 and M;
  M := not M;
  H0 := (H0 and M) or G0; H1 := (H1 and M) or G1; H2 := (H2 and M) or G2;
  H3 := (H3 and M) or G3; H4 := (H4 and M) or G4;
  H0 := (H0 or (H1 shl 26)) and $FFFFFFFF;
  H1 := ((H1 shr 6) or (H2 shl 20)) and $FFFFFFFF;
  H2 := ((H2 shr 12) or (H3 shl 14)) and $FFFFFFFF;
  H3 := ((H3 shr 18) or (H4 shl 8)) and $FFFFFFFF;
  F := H0 + LE32(Key, 17); H0 := F and $FFFFFFFF;
  F := H1 + LE32(Key, 21) + (F shr 32); H1 := F and $FFFFFFFF;
  F := H2 + LE32(Key, 25) + (F shr 32); H2 := F and $FFFFFFFF;
  F := H3 + LE32(Key, 29) + (F shr 32); H3 := F and $FFFFFFFF;
  Result := LE32Str(Cardinal(H0)) + LE32Str(Cardinal(H1)) + LE32Str(Cardinal(H2)) +
    LE32Str(Cardinal(H3));
end;

function Pad16(N: Integer): string;
begin
  if N mod 16 = 0 then Result := '' else Result := StringOfChar(#0, 16 - N mod 16);
end;

function AeadTag(const Key, Nonce, Aad, Cipher: string): string;
var
  Otk: string;
begin
  ChaChaBlock(Key, Nonce, 0, Otk);
  Otk := Copy(Otk, 1, 32);
  Result := Poly1305Mac(Otk, Aad + Pad16(Length(Aad)) + Cipher + Pad16(Length(Cipher)) +
    LE64Str(Length(Aad)) + LE64Str(Length(Cipher)));
end;

function AeadSeal(const Key, Nonce, Aad, Plain: string): string;
begin
  Result := ChaCha20Xor(Key, Nonce, 1, Plain);
  Result := Result + AeadTag(Key, Nonce, Aad, Result);
end;

function AeadOpen(const Key, Nonce, Aad, Sealed: string; out Plain: string): Boolean;
var
  Ct: string;
begin
  Plain := '';
  Result := False;
  if Length(Sealed) < 16 then Exit;
  Ct := Copy(Sealed, 1, Length(Sealed) - 16);
  if not SameBytes(AeadTag(Key, Nonce, Aad, Ct), Copy(Sealed, Length(Sealed) - 15, 16)) then Exit;
  Plain := ChaCha20Xor(Key, Nonce, 1, Ct);
  Result := True;
end;

{ ---- base64 ---- }

const
  B64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function B64Encode(const Data: string): string;
var
  I, N: Integer;
  V: Cardinal;
begin
  Result := '';
  I := 1;
  N := Length(Data);
  while I <= N do
  begin
    V := Cardinal(Ord(Data[I])) shl 16;
    if I + 1 <= N then V := V or (Cardinal(Ord(Data[I + 1])) shl 8);
    if I + 2 <= N then V := V or Cardinal(Ord(Data[I + 2]));
    Result := Result + B64Chars[(V shr 18) + 1] + B64Chars[((V shr 12) and 63) + 1];
    if I + 1 <= N then Result := Result + B64Chars[((V shr 6) and 63) + 1];
    if I + 2 <= N then Result := Result + B64Chars[(V and 63) + 1];
    Inc(I, 3);
  end;
end;

function B64Decode(const Text: string; out Data: string): Boolean;
var
  T: string;
  I, Bits, NBits, C: Integer;
begin
  Data := '';
  Result := False;
  T := Text;
  while (T <> '') and (T[Length(T)] = '=') do SetLength(T, Length(T) - 1);
  if Length(T) mod 4 = 1 then Exit;
  Bits := 0;
  NBits := 0;
  for I := 1 to Length(T) do
  begin
    C := Pos(T[I], B64Chars) - 1;
    if C < 0 then Exit;
    Bits := ((Bits shl 6) or C) and $FFFFFF;
    Inc(NBits, 6);
    if NBits >= 8 then
    begin
      Dec(NBits, 8);
      Data := Data + Chr((Bits shr NBits) and $FF);
    end;
  end;
  { the bits left over must be zero (canonical form) }
  if (Bits and ((1 shl NBits) - 1)) <> 0 then Exit;
  Result := True;
end;

{ ---- random ---- }

{$IFDEF MSWINDOWS}
function RtlGenRandom(Buf: Pointer; Len: ULONG): BOOLEAN; stdcall;
  external 'advapi32.dll' name 'SystemFunction036';

function RandomBytes(N: Integer; out Data: string): Boolean;
begin
  SetLength(Data, N);
  Result := (N = 0) or RtlGenRandom(@Data[1], N);
  if not Result then Data := '';
end;
{$ELSE}
function RandomBytes(N: Integer; out Data: string): Boolean;
var
  F: File;
  Got, OldMode: Integer;
begin
  Result := False;
  SetLength(Data, N);
  if N = 0 then begin Result := True; Exit; end;
  AssignFile(F, '/dev/urandom');
  OldMode := FileMode;
  FileMode := 0;
  {$I-}
  Reset(F, 1);
  {$I+}
  FileMode := OldMode;
  if IOResult <> 0 then begin Data := ''; Exit; end;
  BlockRead(F, Data[1], N, Got);
  CloseFile(F);
  Result := Got = N;
  if not Result then Data := '';
end;
{$ENDIF}

end.
