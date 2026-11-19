{ Sha512_6113: SHA-512 (FIPS 180-4), used by Ed25519 in the SEI00001
  secure login. Written from the published standard; nothing here comes
  from a Graal image. Buffers are AnsiString used as byte arrays. }
unit Sha512_6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$Q-}{$R-}

interface

{ The 64-byte SHA-512 digest of Data, as raw bytes. }
function Sha512(const Data: string): string;

implementation

const
  K: array[0..79] of QWord = (
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

function Ror(X: QWord; N: Integer): QWord; inline;
begin
  Result := (X shr N) or (X shl (64 - N));
end;

function Sha512(const Data: string): string;
var
  H: array[0..7] of QWord;
  W: array[0..79] of QWord;
  Msg: string;
  BitLen: QWord;
  Blk, I, J: Integer;
  A, B, C, D, E, F, G, HH, S0, S1, T1, T2: QWord;
begin
  H[0] := QWord($6a09e667f3bcc908); H[1] := QWord($bb67ae8584caa73b);
  H[2] := QWord($3c6ef372fe94f82b); H[3] := QWord($a54ff53a5f1d36f1);
  H[4] := QWord($510e527fade682d1); H[5] := QWord($9b05688c2b3e6c1f);
  H[6] := QWord($1f83d9abfb41bd6b); H[7] := QWord($5be0cd19137e2179);
  BitLen := QWord(Length(Data)) * 8;
  Msg := Data + #$80;
  while (Length(Msg) mod 128) <> 112 do
    Msg := Msg + #0;
  { 128-bit length, big-endian: the high 64 bits are zero for our inputs. }
  for I := 0 to 7 do Msg := Msg + #0;
  for I := 7 downto 0 do
    Msg := Msg + Chr((BitLen shr (I * 8)) and 255);
  Blk := 0;
  while Blk < Length(Msg) do
  begin
    for I := 0 to 15 do
    begin
      J := Blk + I * 8 + 1;
      W[I] := (QWord(Ord(Msg[J])) shl 56) or (QWord(Ord(Msg[J + 1])) shl 48) or
        (QWord(Ord(Msg[J + 2])) shl 40) or (QWord(Ord(Msg[J + 3])) shl 32) or
        (QWord(Ord(Msg[J + 4])) shl 24) or (QWord(Ord(Msg[J + 5])) shl 16) or
        (QWord(Ord(Msg[J + 6])) shl 8) or QWord(Ord(Msg[J + 7]));
    end;
    for I := 16 to 79 do
    begin
      S0 := Ror(W[I - 15], 1) xor Ror(W[I - 15], 8) xor (W[I - 15] shr 7);
      S1 := Ror(W[I - 2], 19) xor Ror(W[I - 2], 61) xor (W[I - 2] shr 6);
      W[I] := W[I - 16] + S0 + W[I - 7] + S1;
    end;
    A := H[0]; B := H[1]; C := H[2]; D := H[3];
    E := H[4]; F := H[5]; G := H[6]; HH := H[7];
    for I := 0 to 79 do
    begin
      S1 := Ror(E, 14) xor Ror(E, 18) xor Ror(E, 41);
      T1 := HH + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I];
      S0 := Ror(A, 28) xor Ror(A, 34) xor Ror(A, 39);
      T2 := S0 + ((A and B) xor (A and C) xor (B and C));
      HH := G; G := F; F := E; E := D + T1;
      D := C; C := B; B := A; A := T1 + T2;
    end;
    H[0] := H[0] + A; H[1] := H[1] + B; H[2] := H[2] + C; H[3] := H[3] + D;
    H[4] := H[4] + E; H[5] := H[5] + F; H[6] := H[6] + G; H[7] := H[7] + HH;
    Inc(Blk, 128);
  end;
  SetLength(Result, 64);
  for I := 0 to 7 do
    for J := 0 to 7 do
      Result[I * 8 + J + 1] := Chr((H[I] shr ((7 - J) * 8)) and 255);
end;

end.
