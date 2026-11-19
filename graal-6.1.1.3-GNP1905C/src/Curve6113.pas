{ Curve6113: X25519 and Ed25519 verification for the SEI00001 secure login.

  SEI00001 is Seihai's own login (seihai/documentation/secure-login.md). The
  client makes a fresh X25519 key (X25519Base), derives the shared secret
  (X25519), and checks the server's Ed25519 signature over the handshake
  (Ed25519Verify).

  The field is GF(2^255-19). Field elements are sixteen radix-2^16 limbs in
  Int64, a plain big-integer layout chosen for this rebuild; the Montgomery
  ladder is RFC 7748 and the Edwards verification is RFC 8032. The curve
  constants (d, 2d, the base point, sqrt(-1), the group order L) are the
  fixed numbers those standards define. Written clean-room from the
  standards, not from any other implementation's source. Checked against the
  RFC 7748 and RFC 8032 test vectors. }
unit Curve6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$Q-}{$R-}

interface

{ X25519(Scalar, UPoint): the 32-byte shared secret. Scalar and UPoint are
  32 bytes each. }
function X25519(const Scalar, UPoint: string): string;

{ X25519 with the standard base point u = 9: the public key for Scalar. }
function X25519Base(const Scalar: string): string;

{ Ed25519 signature check. PubKey is 32 bytes, Sig is 64 bytes (R || S).
  True when Sig is a valid signature of Msg under PubKey. }
function Ed25519Verify(const PubKey, Msg, Sig: string): Boolean;

implementation

uses
  Sha512_6113;

type
  TGf = array[0..15] of Int64;
  TPt = array[0..3] of TGf;

const
  Gf0: TGf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  Gf1: TGf = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  C121665: TGf = ($DB41, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  CD: TGf = ($78a3, $1359, $4dca, $75eb, $d8ab, $4141, $0a4d, $0070,
             $e898, $7779, $4079, $8cc7, $fe73, $2b6f, $6cee, $5203);
  CD2: TGf = ($f159, $26b2, $9b94, $ebd6, $b156, $8283, $149a, $00e0,
              $d130, $eef3, $80f2, $198e, $fce7, $56df, $d9dc, $2406);
  CX: TGf = ($d51a, $8f25, $2d60, $c956, $a7b2, $9525, $c760, $692c,
             $dc5c, $fdd6, $e231, $c0a4, $53fe, $cd6e, $36d3, $2169);
  CY: TGf = ($6658, $6666, $6666, $6666, $6666, $6666, $6666, $6666,
             $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666);
  CI: TGf = ($a0b0, $4a0e, $1b27, $c4ee, $e478, $ad2f, $1806, $2f43,
             $d7a7, $3dfb, $0099, $2b4d, $df0b, $4fc1, $2480, $2b83);
  { The group order L = 2^252 + 27742317777372353535851937790883648493,
    little-endian, 32 bytes. }
  OrderL: array[0..31] of Int64 = (
    $ed, $d3, $f5, $5c, $1a, $63, $12, $58, $d6, $9c, $f7, $a2, $de, $f9, $de, $14,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, $10);

{ Arithmetic (sign-propagating) shift right. }
function Asr(X: Int64; N: Integer): Int64; inline;
begin
  if X >= 0 then Result := X shr N
  else Result := not ((not X) shr N);
end;

procedure GfAdd(var O: TGf; const A, B: TGf);
var I: Integer;
begin
  for I := 0 to 15 do O[I] := A[I] + B[I];
end;

procedure GfSub(var O: TGf; const A, B: TGf);
var I: Integer;
begin
  for I := 0 to 15 do O[I] := A[I] - B[I];
end;

procedure Car25519(var O: TGf);
var I: Integer; C: Int64;
begin
  for I := 0 to 15 do
  begin
    O[I] := O[I] + 65536;
    C := Asr(O[I], 16);
    if I < 15 then O[I + 1] := O[I + 1] + (C - 1)
    else O[0] := O[0] + 38 * (C - 1);
    O[I] := O[I] - (C shl 16);
  end;
end;

procedure GfMul(var O: TGf; const A, B: TGf);
var
  T: array[0..30] of Int64;
  I, J: Integer;
begin
  for I := 0 to 30 do T[I] := 0;
  for I := 0 to 15 do
    for J := 0 to 15 do
      T[I + J] := T[I + J] + A[I] * B[J];
  for I := 0 to 14 do T[I] := T[I] + 38 * T[I + 16];
  for I := 0 to 15 do O[I] := T[I];
  Car25519(O);
  Car25519(O);
end;

procedure GfSq(var O: TGf; const A: TGf);
begin
  GfMul(O, A, A);
end;

procedure GfCopy(var O: TGf; const A: TGf);
var I: Integer;
begin
  for I := 0 to 15 do O[I] := A[I];
end;

procedure Sel25519(var P, Q: TGf; B: Integer);
var T, C: Int64; I: Integer;
begin
  C := -Int64(B);
  for I := 0 to 15 do
  begin
    T := C and (P[I] xor Q[I]);
    P[I] := P[I] xor T;
    Q[I] := Q[I] xor T;
  end;
end;

procedure Inv25519(var O: TGf; const Inp: TGf);
var C: TGf; A: Integer;
begin
  GfCopy(C, Inp);
  for A := 253 downto 0 do
  begin
    GfSq(C, C);
    if (A <> 2) and (A <> 4) then GfMul(C, C, Inp);
  end;
  GfCopy(O, C);
end;

procedure Pow2523(var O: TGf; const Inp: TGf);
var C: TGf; A: Integer;
begin
  GfCopy(C, Inp);
  for A := 250 downto 0 do
  begin
    GfSq(C, C);
    if A <> 1 then GfMul(C, C, Inp);
  end;
  GfCopy(O, C);
end;

procedure Unpack25519(var O: TGf; const N: string);
var I: Integer;
begin
  for I := 0 to 15 do
    O[I] := Ord(N[2 * I + 1]) + (Int64(Ord(N[2 * I + 2])) shl 8);
  O[15] := O[15] and $7FFF;
end;

procedure Pack25519(out R: string; const N: TGf);
var
  M, T: TGf;
  I, J, B: Integer;
begin
  GfCopy(T, N);
  Car25519(T); Car25519(T); Car25519(T);
  for J := 0 to 1 do
  begin
    M[0] := T[0] - $FFED;
    for I := 1 to 14 do
    begin
      M[I] := T[I] - $FFFF - (Asr(M[I - 1], 16) and 1);
      M[I - 1] := M[I - 1] and $FFFF;
    end;
    M[15] := T[15] - $7FFF - (Asr(M[14], 16) and 1);
    B := Asr(M[15], 16) and 1;
    M[14] := M[14] and $FFFF;
    Sel25519(T, M, 1 - B);
  end;
  SetLength(R, 32);
  for I := 0 to 15 do
  begin
    R[2 * I + 1] := Chr(T[I] and $FF);
    R[2 * I + 2] := Chr(Asr(T[I], 8) and $FF);
  end;
end;

{ True when A and B are different field elements (canonical compare). }
function Neq25519(const A, B: TGf): Boolean;
var Pa, Pb: string;
begin
  Pack25519(Pa, A);
  Pack25519(Pb, B);
  Result := Pa <> Pb;
end;

function Par25519(const A: TGf): Integer;
var D: string;
begin
  Pack25519(D, A);
  Result := Ord(D[1]) and 1;
end;

{ ---- X25519 (RFC 7748) ---- }

function X25519(const Scalar, UPoint: string): string;
var
  Z: array[0..31] of Byte;
  X, A, B, C, D, E, F: TGf;
  I, R: Integer;
begin
  for I := 0 to 30 do Z[I] := Ord(Scalar[I + 1]);
  Z[31] := (Ord(Scalar[32]) and 127) or 64;
  Z[0] := Z[0] and 248;
  Unpack25519(X, UPoint);
  GfCopy(B, X);
  GfCopy(A, Gf0); GfCopy(C, Gf0); GfCopy(D, Gf0);
  A[0] := 1; D[0] := 1;
  for I := 254 downto 0 do
  begin
    R := (Z[I shr 3] shr (I and 7)) and 1;
    Sel25519(A, B, R);
    Sel25519(C, D, R);
    GfAdd(E, A, C);
    GfSub(A, A, C);
    GfAdd(C, B, D);
    GfSub(B, B, D);
    GfSq(D, E);
    GfSq(F, A);
    GfMul(A, C, A);
    GfMul(C, B, E);
    GfAdd(E, A, C);
    GfSub(A, A, C);
    GfSq(B, A);
    GfSub(C, D, F);
    GfMul(A, C, C121665);
    GfAdd(A, A, D);
    GfMul(C, C, A);
    GfMul(A, D, F);
    GfMul(D, B, X);
    GfSq(B, E);
    Sel25519(A, B, R);
    Sel25519(C, D, R);
  end;
  Inv25519(C, C);
  GfMul(A, A, C);
  Pack25519(Result, A);
end;

function X25519Base(const Scalar: string): string;
var U: string;
begin
  U := Chr(9) + StringOfChar(#0, 31);
  Result := X25519(Scalar, U);
end;

{ ---- Ed25519 (RFC 8032) ---- }

procedure PtAdd(var P: TPt; const Q: TPt);
var A, B, C, D, T, E, F, G, H: TGf;
begin
  GfSub(A, P[1], P[0]);
  GfSub(T, Q[1], Q[0]);
  GfMul(A, A, T);
  GfAdd(B, P[0], P[1]);
  GfAdd(T, Q[0], Q[1]);
  GfMul(B, B, T);
  GfMul(C, P[3], Q[3]);
  GfMul(C, C, CD2);
  GfMul(D, P[2], Q[2]);
  GfAdd(D, D, D);
  GfSub(E, B, A);
  GfSub(F, D, C);
  GfAdd(G, D, C);
  GfAdd(H, B, A);
  GfMul(P[0], E, F);
  GfMul(P[1], H, G);
  GfMul(P[2], G, F);
  GfMul(P[3], E, H);
end;

procedure PtCswap(var P, Q: TPt; B: Integer);
var I: Integer;
begin
  for I := 0 to 3 do Sel25519(P[I], Q[I], B);
end;

procedure PtCopy(var P: TPt; const Q: TPt);
var I: Integer;
begin
  for I := 0 to 3 do GfCopy(P[I], Q[I]);
end;

procedure ScalarMult(var P: TPt; var Q: TPt; const S: string);
var I, B: Integer;
begin
  GfCopy(P[0], Gf0); GfCopy(P[1], Gf1); GfCopy(P[2], Gf1); GfCopy(P[3], Gf0);
  for I := 255 downto 0 do
  begin
    B := (Ord(S[(I shr 3) + 1]) shr (I and 7)) and 1;
    PtCswap(P, Q, B);
    PtAdd(Q, P);
    PtAdd(P, P);
    PtCswap(P, Q, B);
  end;
end;

procedure ScalarBase(var P: TPt; const S: string);
var Q: TPt;
begin
  GfCopy(Q[0], CX); GfCopy(Q[1], CY); GfCopy(Q[2], Gf1);
  GfMul(Q[3], CX, CY);
  ScalarMult(P, Q, S);
end;

procedure PackPt(out R: string; const P: TPt);
var Zi, Tx, Ty: TGf;
begin
  Inv25519(Zi, P[2]);
  GfMul(Tx, P[0], Zi);
  GfMul(Ty, P[1], Zi);
  Pack25519(R, Ty);
  R[32] := Chr(Ord(R[32]) xor (Par25519(Tx) shl 7));
end;

{ Decompress PubKey into -A (the negated point), as RFC 8032 verification
  uses. Returns False when the encoding is not a curve point. }
function UnpackNeg(var R: TPt; const P: string): Boolean;
var
  T, Chk, Num, Den, Den2, Den4, Den6: TGf;
begin
  Result := False;
  GfCopy(R[2], Gf1);
  Unpack25519(R[1], P);
  GfSq(Num, R[1]);
  GfMul(Den, Num, CD);
  GfSub(Num, Num, R[2]);
  GfAdd(Den, R[2], Den);
  GfSq(Den2, Den);
  GfSq(Den4, Den2);
  GfMul(Den6, Den4, Den2);
  GfMul(T, Den6, Num);
  GfMul(T, T, Den);
  Pow2523(T, T);
  GfMul(T, T, Num);
  GfMul(T, T, Den);
  GfMul(T, T, Den);
  GfMul(R[0], T, Den);
  GfSq(Chk, R[0]);
  GfMul(Chk, Chk, Den);
  if Neq25519(Chk, Num) then GfMul(R[0], R[0], CI);
  GfSq(Chk, R[0]);
  GfMul(Chk, Chk, Den);
  if Neq25519(Chk, Num) then Exit;
  if Par25519(R[0]) = (Ord(P[32]) shr 7) then GfSub(R[0], Gf0, R[0]);
  GfMul(R[3], R[0], R[1]);
  Result := True;
end;

{ Reduce the 64-byte little-endian X modulo L, into the low 32 bytes of R. }
procedure ModL(var R: string; var X: array of Int64);
var Carry: Int64; I, J: Integer;
begin
  for I := 63 downto 32 do
  begin
    Carry := 0;
    J := I - 32;
    while J < I - 12 do
    begin
      X[J] := X[J] + Carry - 16 * X[I] * OrderL[J - (I - 32)];
      Carry := Asr(X[J] + 128, 8);
      X[J] := X[J] - (Carry shl 8);
      Inc(J);
    end;
    X[J] := X[J] + Carry;
    X[I] := 0;
  end;
  Carry := 0;
  for J := 0 to 31 do
  begin
    X[J] := X[J] + Carry - Asr(X[31], 4) * OrderL[J];
    Carry := Asr(X[J], 8);
    X[J] := X[J] and 255;
  end;
  for J := 0 to 31 do X[J] := X[J] - Carry * OrderL[J];
  for I := 0 to 31 do
  begin
    X[I + 1] := X[I + 1] + Asr(X[I], 8);
    R[I + 1] := Chr(X[I] and 255);
  end;
end;

procedure Reduce(var R: string);
var X: array[0..63] of Int64; I: Integer;
begin
  for I := 0 to 63 do X[I] := Ord(R[I + 1]);
  for I := 0 to 63 do R[I + 1] := #0;
  ModL(R, X);
end;

function CTEqual32(const A, B: string): Boolean;
var I, Diff: Integer;
begin
  Diff := 0;
  for I := 1 to 32 do Diff := Diff or (Ord(A[I]) xor Ord(B[I]));
  Result := Diff = 0;
end;

function Ed25519Verify(const PubKey, Msg, Sig: string): Boolean;
var
  Q, P: TPt;
  H, T, R: string;
begin
  Result := False;
  if (Length(PubKey) <> 32) or (Length(Sig) <> 64) then Exit;
  if not UnpackNeg(Q, PubKey) then Exit;
  { h = SHA-512(R || A || M) reduced mod L }
  H := Copy(Sig, 1, 32) + PubKey + Msg;
  H := Sha512(H);
  SetLength(H, 64);
  Reduce(H);
  SetLength(H, 32);
  { p = [h](-A); q = [S]B; p = p + q = [S]B - [h]A }
  ScalarMult(P, Q, H);
  ScalarBase(Q, Copy(Sig, 33, 32));
  PtAdd(P, Q);
  PackPt(T, P);
  R := Copy(Sig, 1, 32);
  Result := CTEqual32(R, T);
end;

end.
