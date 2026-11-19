{ SecLogin6113: the primitives for the Seihai SEI00001 secure login.

  SEI00001 is Seihai's OWN login protocol (seihai/documentation/secure-login.md,
  revision 1). It is not part of any Graal build: real Graal clients never
  send or expect it. This unit is the client half of that handshake's
  cryptography, written clean-room from the public standards and from the
  Seihai document, NOT from the Rust reference or the C++ server, so the
  licences stay apart. The fixed test values this is checked against are the
  published RFC vectors.

  This first slice is the pure, vector-testable primitives:
    - base64, standard alphabet, no padding, strict decode  (RFC 4648)
    - HMAC-SHA256 and HKDF-SHA256                            (RFC 2104, 5869)
    - ChaCha20 and Poly1305 and the IETF AEAD                (RFC 8439)

  SHA-256 is reused from Sha6113. The X25519 key exchange, the Ed25519
  signature check, and the C1/S1/C2 message flow land in later slices.

  Buffers are AnsiString used as byte arrays, one byte per character,
  indexed from 1, as elsewhere in this rebuild. }
unit SecLogin6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$Q-}{$R-}

interface

{ ---- base64, standard alphabet, no padding ---- }

{ Encode Data as standard base64 with no '=' padding. }
function Base64Encode(const Data: string): string;

{ Decode a standard base64 string with no padding. Strict: any character
  outside the alphabet, or a length that cannot be a no-padding encoding,
  fails with Ok = False and Out = ''. }
function Base64Decode(const Text: string; out Decoded: string): Boolean;

{ ---- HMAC and HKDF over SHA-256 ---- }

{ HMAC-SHA256(Key, Msg): the 32-byte tag. }
function HmacSha256(const Key, Msg: string): string;

{ HKDF-SHA256 extract-then-expand. Salt may be empty (then a block of
  zero bytes is used, per RFC 5869). Returns L bytes. }
function HkdfSha256(const Salt, Ikm, Info: string; L: Integer): string;

{ ---- ChaCha20 / Poly1305 / AEAD (RFC 8439) ---- }

{ The 64-byte ChaCha20 block for a 32-byte Key, 32-bit block Counter and
  12-byte Nonce. }
function Chacha20Block(const Key: string; Counter: Cardinal; const Nonce: string): string;

{ ChaCha20 keystream XORed over Data, starting at block index Counter. }
function Chacha20Xor(const Key, Nonce: string; Counter: Cardinal; const Data: string): string;

{ Poly1305(Msg) under the 32-byte one-time Key: the 16-byte tag. }
function Poly1305(const Key, Msg: string): string;

{ AEAD_CHACHA20_POLY1305 seal. Key is 32 bytes, Nonce 12 bytes. Returns
  ciphertext (same length as Plain) followed by the 16-byte tag. }
function AeadSeal(const Key, Nonce, Aad, Plain: string): string;

{ AEAD open. Box is ciphertext followed by the 16-byte tag. On a good tag
  returns True and the plaintext; on a bad tag or a short box returns False
  and Plain = ''. The tag is compared in constant time. }
function AeadOpen(const Key, Nonce, Aad, Box: string; out Plain: string): Boolean;

implementation

uses
  Sha6113;

const
  B64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

{ ---- base64 ---- }

function Base64Encode(const Data: string): string;
var
  I, N: Integer;
  B0, B1, B2: Byte;
begin
  Result := '';
  N := Length(Data);
  I := 1;
  while I <= N do
  begin
    B0 := Ord(Data[I]);
    Result := Result + B64Alphabet[(B0 shr 2) + 1];
    if I + 1 <= N then
    begin
      B1 := Ord(Data[I + 1]);
      Result := Result + B64Alphabet[(((B0 and 3) shl 4) or (B1 shr 4)) + 1];
      if I + 2 <= N then
      begin
        B2 := Ord(Data[I + 2]);
        Result := Result + B64Alphabet[(((B1 and 15) shl 2) or (B2 shr 6)) + 1];
        Result := Result + B64Alphabet[(B2 and 63) + 1];
      end
      else
        Result := Result + B64Alphabet[((B1 and 15) shl 2) + 1];
    end
    else
      Result := Result + B64Alphabet[((B0 and 3) shl 4) + 1];
    Inc(I, 3);
  end;
end;

function B64Value(C: Char): Integer;
begin
  case C of
    'A'..'Z': Result := Ord(C) - Ord('A');
    'a'..'z': Result := Ord(C) - Ord('a') + 26;
    '0'..'9': Result := Ord(C) - Ord('0') + 52;
    '+': Result := 62;
    '/': Result := 63;
  else
    Result := -1;
  end;
end;

function Base64Decode(const Text: string; out Decoded: string): Boolean;
var
  I, N, Rem: Integer;
  Acc, Bits, V: Integer;
begin
  Result := False;
  Decoded := '';
  N := Length(Text);
  Rem := N mod 4;
  { A no-padding base64 string is 0, 2 or 3 characters past a multiple of
    four. A remainder of one is impossible. }
  if Rem = 1 then Exit;
  Acc := 0;
  Bits := 0;
  for I := 1 to N do
  begin
    V := B64Value(Text[I]);
    if V < 0 then
    begin
      Decoded := '';
      Exit;
    end;
    Acc := (Acc shl 6) or V;
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      Decoded := Decoded + Chr((Acc shr Bits) and 255);
    end;
  end;
  { The leftover bits of a valid no-padding encoding are zero. }
  if (Bits > 0) and ((Acc and ((1 shl Bits) - 1)) <> 0) then
  begin
    Decoded := '';
    Exit;
  end;
  Result := True;
end;

{ ---- HMAC / HKDF ---- }

function HmacSha256(const Key, Msg: string): string;
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
  Result := Sha256(OPad + Sha256(IPad + Msg));
end;

function HkdfSha256(const Salt, Ikm, Info: string; L: Integer): string;
var
  UseSalt, Prk, T, Block: string;
  Counter: Integer;
begin
  UseSalt := Salt;
  if UseSalt = '' then UseSalt := StringOfChar(#0, 32);
  Prk := HmacSha256(UseSalt, Ikm);
  Result := '';
  T := '';
  Counter := 1;
  while Length(Result) < L do
  begin
    Block := HmacSha256(Prk, T + Info + Chr(Counter and 255));
    Result := Result + Block;
    T := Block;
    Inc(Counter);
    if Counter > 255 then Break;
  end;
  SetLength(Result, L);
end;

{ ---- ChaCha20 ---- }

function Rotl32(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shl N) or (X shr (32 - N));
end;

function Ru32le(const S: string; At: Integer): Cardinal; inline;
begin
  Result := Cardinal(Ord(S[At])) or (Cardinal(Ord(S[At + 1])) shl 8) or
    (Cardinal(Ord(S[At + 2])) shl 16) or (Cardinal(Ord(S[At + 3])) shl 24);
end;

procedure Wu32le(var S: string; At: Integer; V: Cardinal); inline;
begin
  S[At] := Chr(V and 255);
  S[At + 1] := Chr((V shr 8) and 255);
  S[At + 2] := Chr((V shr 16) and 255);
  S[At + 3] := Chr((V shr 24) and 255);
end;

procedure QuarterRound(var X: array of Cardinal; A, B, C, D: Integer);
begin
  X[A] := X[A] + X[B]; X[D] := Rotl32(X[D] xor X[A], 16);
  X[C] := X[C] + X[D]; X[B] := Rotl32(X[B] xor X[C], 12);
  X[A] := X[A] + X[B]; X[D] := Rotl32(X[D] xor X[A], 8);
  X[C] := X[C] + X[D]; X[B] := Rotl32(X[B] xor X[C], 7);
end;

function Chacha20Block(const Key: string; Counter: Cardinal; const Nonce: string): string;
var
  State, Work: array[0..15] of Cardinal;
  I: Integer;
begin
  State[0] := $61707865; State[1] := $3320646e;
  State[2] := $79622d32; State[3] := $6b206574;
  for I := 0 to 7 do State[4 + I] := Ru32le(Key, 1 + I * 4);
  State[12] := Counter;
  State[13] := Ru32le(Nonce, 1);
  State[14] := Ru32le(Nonce, 5);
  State[15] := Ru32le(Nonce, 9);
  for I := 0 to 15 do Work[I] := State[I];
  for I := 1 to 10 do
  begin
    QuarterRound(Work, 0, 4, 8, 12);
    QuarterRound(Work, 1, 5, 9, 13);
    QuarterRound(Work, 2, 6, 10, 14);
    QuarterRound(Work, 3, 7, 11, 15);
    QuarterRound(Work, 0, 5, 10, 15);
    QuarterRound(Work, 1, 6, 11, 12);
    QuarterRound(Work, 2, 7, 8, 13);
    QuarterRound(Work, 3, 4, 9, 14);
  end;
  SetLength(Result, 64);
  for I := 0 to 15 do
    Wu32le(Result, 1 + I * 4, Work[I] + State[I]);
end;

function Chacha20Xor(const Key, Nonce: string; Counter: Cardinal; const Data: string): string;
var
  N, Off, I, Take: Integer;
  Ks: string;
begin
  N := Length(Data);
  SetLength(Result, N);
  Off := 0;
  while Off < N do
  begin
    Ks := Chacha20Block(Key, Counter, Nonce);
    Take := N - Off;
    if Take > 64 then Take := 64;
    for I := 1 to Take do
      Result[Off + I] := Chr(Ord(Data[Off + I]) xor Ord(Ks[I]));
    Inc(Off, Take);
    Inc(Counter);
  end;
end;

{ ---- Poly1305 (RFC 8439), 5 x 26-bit limbs ---- }

function Poly1305(const Key, Msg: string): string;
var
  r0, r1, r2, r3, r4: QWord;
  s1, s2, s3, s4: QWord;
  h0, h1, h2, h3, h4: QWord;
  d0, d1, d2, d3, d4, c: QWord;
  g0, g1, g2, g3, g4: QWord;
  mask, t0, t1, t2, t3: QWord;
  f: QWord;
  N, Off, I, Take: Integer;
  Blk: array[0..15] of Byte;
  HiBit: QWord;
const
  M26 = QWord($3FFFFFF);
begin
  { clamp r = key[0..15] & 0x0ffffffc0ffffffc0ffffffc0fffffff }
  t0 := Ru32le(Key, 1);
  t1 := Ru32le(Key, 5);
  t2 := Ru32le(Key, 9);
  t3 := Ru32le(Key, 13);
  r0 := t0 and M26;
  r1 := ((t0 shr 26) or (t1 shl 6)) and M26;
  r2 := ((t1 shr 20) or (t2 shl 12)) and M26;
  r3 := ((t2 shr 14) or (t3 shl 18)) and M26;
  r4 := (t3 shr 8) and M26;
  { clamp bits: top four of r3-equivalent and bottom two of r1-equivalent,
    applied on the 26-bit limbs as poly1305-donna does }
  r1 := r1 and QWord($3FFFF03);
  r2 := r2 and QWord($3FFC0FF);
  r3 := r3 and QWord($3F03FFF);
  r4 := r4 and QWord($00FFFFF);
  r0 := r0 and QWord($3FFFFFF);
  { The clamp above matches 0x0ffffffc0ffffffc0ffffffc0fffffff once the
    limbs are recombined; verified against the RFC 8439 vector. }
  s1 := r1 * 5;
  s2 := r2 * 5;
  s3 := r3 * 5;
  s4 := r4 * 5;
  h0 := 0; h1 := 0; h2 := 0; h3 := 0; h4 := 0;
  N := Length(Msg);
  Off := 0;
  while Off < N do
  begin
    Take := N - Off;
    if Take > 16 then Take := 16;
    for I := 0 to 15 do Blk[I] := 0;
    for I := 0 to Take - 1 do Blk[I] := Ord(Msg[Off + I + 1]);
    if Take = 16 then
    begin
      HiBit := QWord(1) shl 24;
    end
    else
    begin
      Blk[Take] := 1;
      HiBit := 0;
    end;
    t0 := Cardinal(Blk[0]) or (Cardinal(Blk[1]) shl 8) or (Cardinal(Blk[2]) shl 16) or (Cardinal(Blk[3]) shl 24);
    t1 := Cardinal(Blk[4]) or (Cardinal(Blk[5]) shl 8) or (Cardinal(Blk[6]) shl 16) or (Cardinal(Blk[7]) shl 24);
    t2 := Cardinal(Blk[8]) or (Cardinal(Blk[9]) shl 8) or (Cardinal(Blk[10]) shl 16) or (Cardinal(Blk[11]) shl 24);
    t3 := Cardinal(Blk[12]) or (Cardinal(Blk[13]) shl 8) or (Cardinal(Blk[14]) shl 16) or (Cardinal(Blk[15]) shl 24);
    h0 := h0 + (t0 and M26);
    h1 := h1 + (((t0 shr 26) or (t1 shl 6)) and M26);
    h2 := h2 + (((t1 shr 20) or (t2 shl 12)) and M26);
    h3 := h3 + (((t2 shr 14) or (t3 shl 18)) and M26);
    h4 := h4 + ((t3 shr 8) or HiBit);
    { d = h * r mod 2^130-5 }
    d0 := h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1;
    d1 := h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2;
    d2 := h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3;
    d3 := h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4;
    d4 := h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0;
    c := d0 shr 26; h0 := d0 and M26;
    d1 := d1 + c; c := d1 shr 26; h1 := d1 and M26;
    d2 := d2 + c; c := d2 shr 26; h2 := d2 and M26;
    d3 := d3 + c; c := d3 shr 26; h3 := d3 and M26;
    d4 := d4 + c; c := d4 shr 26; h4 := d4 and M26;
    h0 := h0 + c * 5; c := h0 shr 26; h0 := h0 and M26;
    h1 := h1 + c;
    Inc(Off, Take);
  end;
  { full carry }
  c := h1 shr 26; h1 := h1 and M26; h2 := h2 + c;
  c := h2 shr 26; h2 := h2 and M26; h3 := h3 + c;
  c := h3 shr 26; h3 := h3 and M26; h4 := h4 + c;
  c := h4 shr 26; h4 := h4 and M26; h0 := h0 + c * 5;
  c := h0 shr 26; h0 := h0 and M26; h1 := h1 + c;
  { g = h - (2^130 - 5) = h + 5, then subtract 2^130 }
  g0 := h0 + 5; c := g0 shr 26; g0 := g0 and M26;
  g1 := h1 + c; c := g1 shr 26; g1 := g1 and M26;
  g2 := h2 + c; c := g2 shr 26; g2 := g2 and M26;
  g3 := h3 + c; c := g3 shr 26; g3 := g3 and M26;
  g4 := h4 + c - (QWord(1) shl 26);
  { select g if g4 did not borrow (bit 63 clear), else h }
  mask := (g4 shr 63) - 1;   { all ones when g4 >= 0, else zero }
  g0 := g0 and mask; g1 := g1 and mask; g2 := g2 and mask;
  g3 := g3 and mask; g4 := g4 and mask;
  mask := not mask;
  h0 := (h0 and mask) or g0;
  h1 := (h1 and mask) or g1;
  h2 := (h2 and mask) or g2;
  h3 := (h3 and mask) or g3;
  h4 := (h4 and mask) or g4;
  { recombine the 26-bit limbs into four 32-bit words }
  h0 := (h0 or (h1 shl 26)) and QWord($FFFFFFFF);
  h1 := ((h1 shr 6) or (h2 shl 20)) and QWord($FFFFFFFF);
  h2 := ((h2 shr 12) or (h3 shl 14)) and QWord($FFFFFFFF);
  h3 := ((h3 shr 18) or (h4 shl 8)) and QWord($FFFFFFFF);
  { h += key[16..31] mod 2^128 }
  f := h0 + Ru32le(Key, 17);                 h0 := f and QWord($FFFFFFFF);
  f := h1 + Ru32le(Key, 21) + (f shr 32);    h1 := f and QWord($FFFFFFFF);
  f := h2 + Ru32le(Key, 25) + (f shr 32);    h2 := f and QWord($FFFFFFFF);
  f := h3 + Ru32le(Key, 29) + (f shr 32);    h3 := f and QWord($FFFFFFFF);
  SetLength(Result, 16);
  Wu32le(Result, 1, Cardinal(h0));
  Wu32le(Result, 5, Cardinal(h1));
  Wu32le(Result, 9, Cardinal(h2));
  Wu32le(Result, 13, Cardinal(h3));
end;

{ ---- AEAD ---- }

function Pad16(Len: Integer): string;
var
  R: Integer;
begin
  R := Len mod 16;
  if R = 0 then Result := '' else Result := StringOfChar(#0, 16 - R);
end;

function U64le(V: QWord): string;
var
  I: Integer;
begin
  SetLength(Result, 8);
  for I := 0 to 7 do
    Result[I + 1] := Chr((V shr (I * 8)) and 255);
end;

function Poly1305KeyGen(const Key, Nonce: string): string;
begin
  Result := Copy(Chacha20Block(Key, 0, Nonce), 1, 32);
end;

function AeadTag(const OtKey, Aad, Cipher: string): string;
var
  MacData: string;
begin
  MacData := Aad + Pad16(Length(Aad)) + Cipher + Pad16(Length(Cipher)) +
    U64le(Length(Aad)) + U64le(Length(Cipher));
  Result := Poly1305(OtKey, MacData);
end;

function AeadSeal(const Key, Nonce, Aad, Plain: string): string;
var
  OtKey, Cipher: string;
begin
  OtKey := Poly1305KeyGen(Key, Nonce);
  Cipher := Chacha20Xor(Key, Nonce, 1, Plain);
  Result := Cipher + AeadTag(OtKey, Aad, Cipher);
end;

function AeadOpen(const Key, Nonce, Aad, Box: string; out Plain: string): Boolean;
var
  OtKey, Cipher, GotTag, WantTag: string;
  I, Diff: Integer;
begin
  Plain := '';
  Result := False;
  if Length(Box) < 16 then Exit;
  Cipher := Copy(Box, 1, Length(Box) - 16);
  GotTag := Copy(Box, Length(Box) - 15, 16);
  OtKey := Poly1305KeyGen(Key, Nonce);
  WantTag := AeadTag(OtKey, Aad, Cipher);
  Diff := 0;
  for I := 1 to 16 do
    Diff := Diff or (Ord(GotTag[I]) xor Ord(WantTag[I]));
  if Diff <> 0 then Exit;
  Plain := Chacha20Xor(Key, Nonce, 1, Cipher);
  Result := True;
end;

end.
