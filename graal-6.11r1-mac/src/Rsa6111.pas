{ Rsa6111: RSA-2048 signature check for the connector reply.

  The 6.11 connector signs the conf.gs payload with RSA-2048 over the bare
  SHA-256 digest: PKCS #1 v1.5 type-1 padding (RFC 8017 section 9.2) with
  no DigestInfo label in front of the 32 digest bytes. This unit checks
  that shape with the public exponent 65537 and a public modulus the
  caller supplies. It never holds or needs a private key.

  Written from RFC 8017. Nothing here comes from a Graal image. }
unit Rsa6111;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$Q-}{$R-}

interface

const
  RsaBytes = 256; { 2048-bit modulus }
  RsaE = 65537;

{ Modulus as 512 hex digits, most significant first. Returns False and
  sets Err when the signature is the wrong size, is not below the modulus,
  does not unpad as type 1 with no DigestInfo, or carries another digest. }
function RsaVerifyBareSha256(const ModulusHex, Signature, Digest: string;
  out Err: string): Boolean;

{ The 256-byte block s^e mod n, for tests. Empty on a bad modulus. }
function RsaPublicOp(const ModulusHex, Block: string): string;

implementation

const
  Limbs = RsaBytes div 4; { 64 }

type
  TBig = array[0..Limbs] of Cardinal; { one spare limb for the carry }

procedure BigZero(var A: TBig);
var
  I: Integer;
begin
  for I := 0 to Limbs do A[I] := 0;
end;

function BigFromBytes(const S: string; out A: TBig): Boolean;
var
  I, B: Integer;
begin
  BigZero(A);
  Result := Length(S) = RsaBytes;
  if not Result then Exit;
  for I := 0 to RsaBytes - 1 do
  begin
    B := Ord(S[RsaBytes - I]); { little end first }
    A[I div 4] := A[I div 4] or (Cardinal(B) shl ((I mod 4) * 8));
  end;
end;

function BigToBytes(const A: TBig): string;
var
  I: Integer;
begin
  SetLength(Result, RsaBytes);
  for I := 0 to RsaBytes - 1 do
    Result[RsaBytes - I] := Chr((A[I div 4] shr ((I mod 4) * 8)) and 255);
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function HexToBytes(const H: string; out S: string): Boolean;
var
  I, Hi, Lo: Integer;
begin
  S := '';
  Result := False;
  if Odd(Length(H)) then Exit;
  SetLength(S, Length(H) div 2);
  for I := 1 to Length(H) div 2 do
  begin
    Hi := HexVal(H[I * 2 - 1]);
    Lo := HexVal(H[I * 2]);
    if (Hi < 0) or (Lo < 0) then Exit;
    S[I] := Chr(Hi * 16 + Lo);
  end;
  Result := True;
end;

function BigCmp(const A, B: TBig): Integer;
var
  I: Integer;
begin
  for I := Limbs downto 0 do
    if A[I] <> B[I] then
    begin
      if A[I] > B[I] then Result := 1 else Result := -1;
      Exit;
    end;
  Result := 0;
end;

procedure BigSub(var A: TBig; const B: TBig);
var
  I: Integer;
  T: Int64;
  Borrow: Int64;
begin
  Borrow := 0;
  for I := 0 to Limbs do
  begin
    T := Int64(A[I]) - Int64(B[I]) - Borrow;
    if T < 0 then
    begin
      T := T + (Int64(1) shl 32);
      Borrow := 1;
    end
    else
      Borrow := 0;
    A[I] := Cardinal(T);
  end;
end;

procedure BigAdd(var A: TBig; const B: TBig);
var
  I: Integer;
  T: QWord;
begin
  T := 0;
  for I := 0 to Limbs do
  begin
    T := T + QWord(A[I]) + QWord(B[I]);
    A[I] := Cardinal(T and $FFFFFFFF);
    T := T shr 32;
  end;
end;

procedure BigShl1(var A: TBig);
var
  I: Integer;
begin
  for I := Limbs downto 1 do
    A[I] := (A[I] shl 1) or (A[I - 1] shr 31);
  A[0] := A[0] shl 1;
end;

{ R := A * B mod N, with A and B already below N. Double-and-add, so every
  intermediate stays below 2N and fits the spare limb. }
procedure BigMulMod(const A, B, N: TBig; out R: TBig);
var
  Bit: Integer;
begin
  BigZero(R);
  for Bit := RsaBytes * 8 - 1 downto 0 do
  begin
    BigShl1(R);
    if BigCmp(R, N) >= 0 then BigSub(R, N);
    if (A[Bit div 32] shr (Bit mod 32)) and 1 = 1 then
    begin
      BigAdd(R, B);
      if BigCmp(R, N) >= 0 then BigSub(R, N);
    end;
  end;
end;

function RsaPublicOp(const ModulusHex, Block: string): string;
var
  NBytes: string;
  N, S, M, T: TBig;
  I: Integer;
begin
  Result := '';
  if not HexToBytes(ModulusHex, NBytes) or (Length(NBytes) <> RsaBytes) then Exit;
  if not BigFromBytes(NBytes, N) or not BigFromBytes(Block, S) then Exit;
  if BigCmp(S, N) >= 0 then Exit;
  { e = 65537 = 2^16 + 1: sixteen squarings, then one multiply. }
  M := S;
  for I := 1 to 16 do
  begin
    BigMulMod(M, M, N, T);
    M := T;
  end;
  BigMulMod(M, S, N, T);
  Result := BigToBytes(T);
end;

function RsaVerifyBareSha256(const ModulusHex, Signature, Digest: string;
  out Err: string): Boolean;
var
  EM: string;
  I, PadEnd: Integer;
begin
  Result := False;
  Err := '';
  if Length(Digest) <> 32 then
  begin
    Err := 'digest is not 32 bytes';
    Exit;
  end;
  if Length(Signature) <> RsaBytes then
  begin
    Err := 'signature is not 256 bytes';
    Exit;
  end;
  EM := RsaPublicOp(ModulusHex, Signature);
  if EM = '' then
  begin
    Err := 'signature is not below the modulus, or the modulus is bad';
    Exit;
  end;
  { 00 01 FF..FF 00 <32-byte digest>, no DigestInfo. }
  PadEnd := RsaBytes - 32; { 1-based index of the 00 separator }
  if (EM[1] <> #0) or (EM[2] <> #1) or (EM[PadEnd] <> #0) then
  begin
    Err := 'signature padding is not type 1 over a bare digest';
    Exit;
  end;
  for I := 3 to PadEnd - 1 do
    if EM[I] <> #$FF then
    begin
      Err := 'signature padding is not type 1 over a bare digest';
      Exit;
    end;
  if Copy(EM, PadEnd + 1, 32) <> Digest then
  begin
    Err := 'signature does not match the payload digest';
    Exit;
  end;
  Result := True;
end;

end.
