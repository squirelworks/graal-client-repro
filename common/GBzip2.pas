{ GBzip2: bzip2 in and out of string buffers.

  2.22 and later pick bz2 for frame bodies of 0x1000 bytes or more (gen-5
  compression byte 0x06; graal_analysis protocol/codec-and-framing.md and
  protocol/client-versions.md). Delphi 5 has no bzip2 unit and Free Pascal's
  only decompresses, so the format is written out here from the bzip2 file
  format (Seward's bzip2 1.0 stream layout, as also described in the
  bzip2 format notes): "BZh" + level, blocks of 48-bit magic, block CRC,
  BWT origin, symbol map, Huffman tables and selectors, then the stream
  trailer with the combined CRC.

  The encoder is plain and small rather than tight: one Huffman table set
  (written twice, since the format wants at least two), prefix-doubling
  BWT so runs of equal bytes (an empty board) stay O(n log^2 n). Its output
  is a valid bzip2 stream that any decoder reads; it is not byte-identical
  to libbzip2's, which the wire does not require. }
unit GBzip2;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ MaxOut caps the decoded size; a stream that would decode past it is
  rejected. Returns False for anything that is not a whole valid stream. }
function BZ2Decompress(const Data: string; out Plain: string;
  MaxOut: Integer): Boolean;
function BZ2Compress(const Data: string): string;
{ The bzip2 CRC (CRC-32, polynomial 0x04C11DB7, not reflected). }
function BZ2Crc(const Data: string): Cardinal;

implementation

{ the CRC and the bit buffers wrap at 32 bits on purpose }
{$Q-}{$R-}

var
  CrcTable: array[0..255] of Cardinal;
  CrcReady: Boolean = False;

procedure MakeCrcTable;
var
  I, J: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := Cardinal(I) shl 24;
    for J := 0 to 7 do
      if (C and $80000000) <> 0 then C := (C shl 1) xor $04C11DB7
      else C := C shl 1;
    CrcTable[I] := C;
  end;
  CrcReady := True;
end;

function CrcUpdate(Crc: Cardinal; B: Byte): Cardinal;
begin
  Result := (Crc shl 8) xor CrcTable[((Crc shr 24) xor B) and $FF];
end;

function BZ2Crc(const Data: string): Cardinal;
var
  I: Integer;
begin
  if not CrcReady then MakeCrcTable;
  Result := $FFFFFFFF;
  for I := 1 to Length(Data) do Result := CrcUpdate(Result, Ord(Data[I]));
  Result := not Result;
end;

const
  MaxGroups = 6;
  MaxAlpha = 258;
  MaxCodeLen = 20;
  GroupSize = 50;

{ ---------------------------------------------------------------- reading }

type
  TBitReader = record
    Data: string;
    Pos: Integer;    { next byte, 1-based }
    Buf: Cardinal;
    Count: Integer;  { valid bits in Buf }
    Bad: Boolean;    { read past the end }
  end;

function GetBits(var R: TBitReader; N: Integer): Cardinal;
begin
  { N <= 24 }
  while R.Count < N do
  begin
    if R.Pos > Length(R.Data) then
    begin
      R.Bad := True;
      Result := 0;
      Exit;
    end;
    R.Buf := (R.Buf shl 8) or Ord(R.Data[R.Pos]);
    Inc(R.Pos);
    Inc(R.Count, 8);
  end;
  Result := (R.Buf shr (R.Count - N)) and ((Cardinal(1) shl N) - 1);
  Dec(R.Count, N);
end;

function GetBit(var R: TBitReader): Integer;
begin
  Result := GetBits(R, 1);
end;

type
  { one canonical Huffman table }
  THuffTable = record
    MinLen, MaxLen: Integer;
    Limit: array[0..MaxCodeLen + 1] of Integer; { largest code of each length }
    Base: array[0..MaxCodeLen + 1] of Integer;  { code -> index in Perm }
    Perm: array[0..MaxAlpha - 1] of Integer;    { symbols by length, then value }
  end;

procedure MakeDecodeTable(var T: THuffTable; const Lens: array of Byte; Alpha: Integer);
var
  L, I, P, Code: Integer;
  Count: array[0..MaxCodeLen + 1] of Integer;
begin
  T.MinLen := 32;
  T.MaxLen := 0;
  for I := 0 to Alpha - 1 do
  begin
    if Lens[I] > T.MaxLen then T.MaxLen := Lens[I];
    if Lens[I] < T.MinLen then T.MinLen := Lens[I];
  end;
  for L := 0 to MaxCodeLen + 1 do Count[L] := 0;
  for I := 0 to Alpha - 1 do Inc(Count[Lens[I]]);
  P := 0;
  for L := T.MinLen to T.MaxLen do
    for I := 0 to Alpha - 1 do
      if Lens[I] = L then
      begin
        T.Perm[P] := I;
        Inc(P);
      end;
  { canonical codes: by length, then by symbol }
  Code := 0;
  P := 0;
  for L := 0 to MaxCodeLen + 1 do
  begin
    T.Limit[L] := -1;
    T.Base[L] := 0;
  end;
  for L := T.MinLen to T.MaxLen do
  begin
    T.Base[L] := P - Code;  { index = code + Base }
    Inc(Code, Count[L]);
    Inc(P, Count[L]);
    T.Limit[L] := Code - 1;
    Code := Code shl 1;
  end;
end;

function DecodeSym(var R: TBitReader; const T: THuffTable): Integer;
var
  L, Code: Integer;
begin
  Result := -1;
  Code := GetBits(R, T.MinLen);
  L := T.MinLen;
  while True do
  begin
    if R.Bad then Exit;
    if Code <= T.Limit[L] then
    begin
      Result := T.Perm[Code + T.Base[L]];
      Exit;
    end;
    Inc(L);
    if L > T.MaxLen then Exit;
    Code := (Code shl 1) or GetBit(R);
  end;
end;

function BZ2Decompress(const Data: string; out Plain: string;
  MaxOut: Integer): Boolean;
var
  R: TBitReader;
  Level, BlockMax: Integer;
  OutLen: Integer;
  { per block }
  Magic1, Magic2, BlockCrc, StoredCombined, Combined: Cardinal;
  OrigPtr, I, J, K, G, NGroups, NSelectors, Alpha, NumInUse, EOB: Integer;
  InUse16: Cardinal;
  SeqToUnf: array[0..255] of Byte;
  Selectors: array of Byte;
  MtfSel: array[0..MaxGroups - 1] of Byte;
  Lens: array[0..MaxGroups - 1, 0..MaxAlpha - 1] of Byte;
  Tables: array[0..MaxGroups - 1] of THuffTable;
  Mtf: array[0..255] of Byte;
  Unzftab: array[0..255] of Integer;
  LL: array of Byte;
  TT: array of Integer;
  NBlock, GroupPos, GroupNo, Sym, Run, RunBit, Curr: Integer;
  Uc: Byte;
  Cftab: array[0..256] of Integer;
  TPos, RunLen, Last, Ch: Integer;
  Crc: Cardinal;

  procedure Emit(B: Byte);
  begin
    if OutLen >= Length(Plain) then
      SetLength(Plain, 2 * Length(Plain) + 4096);
    Inc(OutLen);
    Plain[OutLen] := Chr(B);
    Crc := CrcUpdate(Crc, B);
  end;

begin
  Result := False;
  Plain := '';
  OutLen := 0;
  if not CrcReady then MakeCrcTable;
  if (Length(Data) < 4) or (Copy(Data, 1, 3) <> 'BZh') then Exit;
  if (Data[4] < '1') or (Data[4] > '9') then Exit;
  Level := Ord(Data[4]) - Ord('0');
  BlockMax := Level * 100000;
  R.Data := Data;
  R.Pos := 5;
  R.Buf := 0;
  R.Count := 0;
  R.Bad := False;
  Combined := 0;
  while True do
  begin
    Magic1 := GetBits(R, 24);
    Magic2 := GetBits(R, 24);
    if R.Bad then Exit;
    if (Magic1 = $177245) and (Magic2 = $385090) then
    begin
      StoredCombined := (GetBits(R, 16) shl 16) or GetBits(R, 16);
      if R.Bad or (StoredCombined <> Combined) then Exit;
      SetLength(Plain, OutLen);
      Result := True;
      Exit;
    end;
    if (Magic1 <> $314159) or (Magic2 <> $265359) then Exit;
    BlockCrc := (GetBits(R, 16) shl 16) or GetBits(R, 16);
    if GetBit(R) <> 0 then Exit; { randomised blocks: obsolete, refused }
    OrigPtr := GetBits(R, 24);
    { the symbol map }
    InUse16 := GetBits(R, 16);
    NumInUse := 0;
    for I := 0 to 15 do
      if (InUse16 and ($8000 shr I)) <> 0 then
      begin
        K := GetBits(R, 16);
        for J := 0 to 15 do
          if (K and ($8000 shr J)) <> 0 then
          begin
            SeqToUnf[NumInUse] := I * 16 + J;
            Inc(NumInUse);
          end;
      end;
    if R.Bad or (NumInUse = 0) then Exit;
    Alpha := NumInUse + 2;
    NGroups := GetBits(R, 3);
    NSelectors := GetBits(R, 15);
    if R.Bad or (NGroups < 2) or (NGroups > MaxGroups) or (NSelectors < 1) then Exit;
    SetLength(Selectors, NSelectors);
    for I := 0 to NSelectors - 1 do
    begin
      J := 0;
      while GetBit(R) = 1 do
      begin
        Inc(J);
        if J >= NGroups then Exit;
      end;
      if R.Bad then Exit;
      Selectors[I] := J;
    end;
    { undo the selector MTF }
    for I := 0 to NGroups - 1 do MtfSel[I] := I;
    for I := 0 to NSelectors - 1 do
    begin
      J := Selectors[I];
      Uc := MtfSel[J];
      while J > 0 do
      begin
        MtfSel[J] := MtfSel[J - 1];
        Dec(J);
      end;
      MtfSel[0] := Uc;
      Selectors[I] := Uc;
    end;
    { code lengths, delta coded }
    for G := 0 to NGroups - 1 do
    begin
      Curr := GetBits(R, 5);
      for I := 0 to Alpha - 1 do
      begin
        while True do
        begin
          if (Curr < 1) or (Curr > MaxCodeLen) or R.Bad then Exit;
          if GetBit(R) = 0 then Break;
          if GetBit(R) = 0 then Inc(Curr) else Dec(Curr);
        end;
        Lens[G, I] := Curr;
      end;
      MakeDecodeTable(Tables[G], Lens[G], Alpha);
    end;
    { the MTF / RLE2 symbols }
    for I := 0 to 255 do
    begin
      Mtf[I] := I;
      Unzftab[I] := 0;
    end;
    SetLength(LL, BlockMax);
    NBlock := 0;
    EOB := NumInUse + 1;
    GroupNo := -1;
    GroupPos := 0;
    Run := 0;
    RunBit := 1;
    while True do
    begin
      if GroupPos = 0 then
      begin
        Inc(GroupNo);
        if GroupNo >= NSelectors then Exit;
        GroupPos := GroupSize;
      end;
      Dec(GroupPos);
      Sym := DecodeSym(R, Tables[Selectors[GroupNo]]);
      if (Sym < 0) or (Sym >= Alpha) then Exit;
      if Sym <= 1 then
      begin
        { RUNA / RUNB: a run of the front symbol, in bijective base 2 }
        if Sym = 0 then Inc(Run, RunBit) else Inc(Run, 2 * RunBit);
        RunBit := RunBit * 2;
        if Run > BlockMax then Exit;
        Continue;
      end;
      if Run > 0 then
      begin
        if NBlock + Run > BlockMax then Exit;
        Uc := SeqToUnf[Mtf[0]];
        Inc(Unzftab[Uc], Run);
        for I := 1 to Run do
        begin
          LL[NBlock] := Uc;
          Inc(NBlock);
        end;
        Run := 0;
        RunBit := 1;
      end;
      if Sym = EOB then Break;
      if NBlock >= BlockMax then Exit;
      J := Sym - 1;
      Uc := Mtf[J];
      while J > 0 do
      begin
        Mtf[J] := Mtf[J - 1];
        Dec(J);
      end;
      Mtf[0] := Uc;
      Uc := SeqToUnf[Uc];
      Inc(Unzftab[Uc]);
      LL[NBlock] := Uc;
      Inc(NBlock);
    end;
    if (NBlock = 0) or (OrigPtr >= NBlock) then Exit;
    { inverse BWT }
    Cftab[0] := 0;
    for I := 1 to 256 do Cftab[I] := Cftab[I - 1] + Unzftab[I - 1];
    SetLength(TT, NBlock);
    for I := 0 to NBlock - 1 do
    begin
      Uc := LL[I];
      TT[Cftab[Uc]] := I;
      Inc(Cftab[Uc]);
    end;
    { undo the first RLE while walking the BWT chain }
    Crc := $FFFFFFFF;
    TPos := TT[OrigPtr];
    RunLen := 0;
    Last := -1;
    I := 0;
    while I < NBlock do
    begin
      Ch := LL[TPos];
      TPos := TT[TPos];
      Inc(I);
      if RunLen = 4 then
      begin
        { a count of extra copies of the last byte }
        if OutLen + Ch > MaxOut then Exit;
        for J := 1 to Ch do Emit(Last);
        RunLen := 0;
        Last := -1;
        Continue;
      end;
      if Ch = Last then Inc(RunLen)
      else
      begin
        RunLen := 1;
        Last := Ch;
      end;
      if OutLen + 1 > MaxOut then Exit;
      Emit(Ch);
    end;
    Crc := not Crc;
    if Crc <> BlockCrc then Exit;
    Combined := ((Combined shl 1) or (Combined shr 31)) xor BlockCrc;
  end;
end;

{ ---------------------------------------------------------------- writing }

type
  TBitWriter = record
    Out: string;
    Len: Integer;
    Buf: Cardinal;
    Count: Integer;
  end;

procedure PutByte(var W: TBitWriter; B: Byte);
begin
  if W.Len >= Length(W.Out) then SetLength(W.Out, 2 * Length(W.Out) + 256);
  Inc(W.Len);
  W.Out[W.Len] := Chr(B);
end;

procedure PutBits(var W: TBitWriter; N: Integer; V: Cardinal);
begin
  { N <= 24 }
  W.Buf := (W.Buf shl N) or (V and ((Cardinal(1) shl N) - 1));
  Inc(W.Count, N);
  while W.Count >= 8 do
  begin
    PutByte(W, (W.Buf shr (W.Count - 8)) and $FF);
    Dec(W.Count, 8);
  end;
end;

procedure PutU32(var W: TBitWriter; V: Cardinal);
begin
  PutBits(W, 16, V shr 16);
  PutBits(W, 16, V and $FFFF);
end;

{ Rotation order of Block by prefix doubling: Rank[i] holds the order of the
  first K bytes of rotation i; each pass sorts by (Rank[i], Rank[i + K]). }
procedure SortRotations(const Block: array of Byte; N: Integer; var SA: array of Integer);
var
  Rank, Tmp, Idx2, Cnt: array of Integer;
  K, I, R, Classes: Integer;

  procedure SortByKey(const Key: array of Integer; MaxKey: Integer);
  var
    I2, S, T: Integer;
  begin
    { stable counting sort of SA by Key[SA[i]] }
    SetLength(Cnt, MaxKey + 1);
    for I2 := 0 to MaxKey do Cnt[I2] := 0;
    for I2 := 0 to N - 1 do Inc(Cnt[Key[SA[I2]]]);
    S := 0;
    for I2 := 0 to MaxKey do
    begin
      T := Cnt[I2];
      Cnt[I2] := S;
      Inc(S, T);
    end;
    for I2 := 0 to N - 1 do
    begin
      Idx2[Cnt[Key[SA[I2]]]] := SA[I2];
      Inc(Cnt[Key[SA[I2]]]);
    end;
    for I2 := 0 to N - 1 do SA[I2] := Idx2[I2];
  end;

var
  Second: array of Integer;
begin
  SetLength(Rank, N);
  SetLength(Tmp, N);
  SetLength(Idx2, N);
  SetLength(Second, N);
  for I := 0 to N - 1 do
  begin
    SA[I] := I;
    Rank[I] := Block[I];
  end;
  SortByKey(Rank, 255);
  { ranks after one byte }
  Classes := 0;
  Tmp[SA[0]] := 0;
  for I := 1 to N - 1 do
  begin
    if Block[SA[I]] <> Block[SA[I - 1]] then Inc(Classes);
    Tmp[SA[I]] := Classes;
  end;
  for I := 0 to N - 1 do Rank[I] := Tmp[I];
  K := 1;
  while (Classes < N - 1) and (K < N) do
  begin
    { sort by the second key, then stably by the first }
    for I := 0 to N - 1 do Second[I] := Rank[(I + K) mod N];
    SortByKey(Second, Classes);
    SortByKey(Rank, Classes);
    Classes := 0;
    Tmp[SA[0]] := 0;
    for I := 1 to N - 1 do
    begin
      R := SA[I];
      if (Rank[R] <> Rank[SA[I - 1]]) or
        (Rank[(R + K) mod N] <> Rank[(SA[I - 1] + K) mod N]) then
        Inc(Classes);
      Tmp[R] := Classes;
    end;
    for I := 0 to N - 1 do Rank[I] := Tmp[I];
    K := K * 2;
  end;
end;

{ Huffman code lengths for Freq, none longer than MaxLen. }
procedure MakeCodeLengths(var Lens: array of Byte; const Freq: array of Integer;
  Alpha, MaxLen: Integer);
var
  W: array of Int64;
  Parent: array of Integer;
  Alive: array of Boolean;
  F: array of Integer;
  I, J, A, B, Nodes, D, Longest: Integer;
begin
  SetLength(F, Alpha);
  for I := 0 to Alpha - 1 do
    if Freq[I] = 0 then F[I] := 1 else F[I] := Freq[I];
  while True do
  begin
    SetLength(W, 2 * Alpha);
    SetLength(Parent, 2 * Alpha);
    SetLength(Alive, 2 * Alpha);
    for I := 0 to Alpha - 1 do
    begin
      W[I] := F[I];
      Parent[I] := -1;
      Alive[I] := True;
    end;
    Nodes := Alpha;
    for J := 1 to Alpha - 1 do
    begin
      A := -1;
      B := -1;
      for I := 0 to Nodes - 1 do
        if Alive[I] then
        begin
          if (A < 0) or (W[I] < W[A]) then
          begin
            B := A;
            A := I;
          end
          else if (B < 0) or (W[I] < W[B]) then
            B := I;
        end;
      W[Nodes] := W[A] + W[B];
      Parent[Nodes] := -1;
      Alive[Nodes] := True;
      Alive[A] := False;
      Alive[B] := False;
      Parent[A] := Nodes;
      Parent[B] := Nodes;
      Inc(Nodes);
    end;
    Longest := 0;
    for I := 0 to Alpha - 1 do
    begin
      D := 0;
      J := I;
      while Parent[J] >= 0 do
      begin
        J := Parent[J];
        Inc(D);
      end;
      if D = 0 then D := 1;
      Lens[I] := D;
      if D > Longest then Longest := D;
    end;
    if Longest <= MaxLen then Exit;
    for I := 0 to Alpha - 1 do F[I] := 1 + F[I] div 2;
  end;
end;

procedure WriteBlock(var W: TBitWriter; const Src: string; SrcPos, SrcLen: Integer;
  var Combined: Cardinal);
var
  Block: array of Byte;
  N, I, J, RunLen, Sym, Alpha, NumInUse, NMtf, NSel, ZRun, OrigPtr: Integer;
  B, Uc: Byte;
  Crc: Cardinal;
  InUse: array[0..255] of Boolean;
  Unseq: array[0..255] of Integer;
  SA: array of Integer;
  Mtf: array[0..255] of Byte;
  Syms: array of Integer;
  Freq: array[0..MaxAlpha - 1] of Integer;
  Lens: array[0..MaxAlpha - 1] of Byte;
  Codes: array[0..MaxAlpha - 1] of Cardinal;
  L, Code, G, Curr: Integer;
  Bits16: Cardinal;

  procedure AddSym(S: Integer);
  begin
    if NMtf >= Length(Syms) then SetLength(Syms, 2 * Length(Syms) + 64);
    Syms[NMtf] := S;
    Inc(NMtf);
    Inc(Freq[S]);
  end;

  procedure FlushZeros;
  begin
    if ZRun = 0 then Exit;
    Dec(ZRun);
    while True do
    begin
      if (ZRun and 1) <> 0 then AddSym(1) else AddSym(0);
      if ZRun < 2 then Break;
      ZRun := (ZRun - 2) div 2;
    end;
    ZRun := 0;
  end;

begin
  { the first RLE: runs of 4 to 255 become 4 bytes and a count }
  SetLength(Block, SrcLen + SrcLen div 4 + 8);
  N := 0;
  I := SrcPos;
  Crc := $FFFFFFFF;
  while I < SrcPos + SrcLen do
  begin
    B := Ord(Src[I]);
    RunLen := 1;
    while (I + RunLen < SrcPos + SrcLen) and (Ord(Src[I + RunLen]) = B) and
      (RunLen < 255) do
      Inc(RunLen);
    for J := 1 to RunLen do Crc := CrcUpdate(Crc, B);
    if RunLen < 4 then
      for J := 1 to RunLen do
      begin
        Block[N] := B;
        Inc(N);
      end
    else
    begin
      for J := 1 to 4 do
      begin
        Block[N] := B;
        Inc(N);
      end;
      Block[N] := RunLen - 4;
      Inc(N);
    end;
    Inc(I, RunLen);
  end;
  Crc := not Crc;
  Combined := ((Combined shl 1) or (Combined shr 31)) xor Crc;

  SetLength(SA, N);
  SortRotations(Block, N, SA);
  OrigPtr := 0;
  for I := 0 to N - 1 do
    if SA[I] = 0 then OrigPtr := I;

  for I := 0 to 255 do InUse[I] := False;
  for I := 0 to N - 1 do InUse[Block[I]] := True;
  NumInUse := 0;
  for I := 0 to 255 do
    if InUse[I] then
    begin
      Unseq[I] := NumInUse;
      Inc(NumInUse);
    end;
  Alpha := NumInUse + 2;
  for I := 0 to MaxAlpha - 1 do Freq[I] := 0;

  { MTF and the zero-run coding over the last column }
  for I := 0 to 255 do Mtf[I] := I;
  for I := 0 to MaxAlpha - 1 do Freq[I] := 0;
  NMtf := 0;
  ZRun := 0;
  for I := 0 to N - 1 do
  begin
    Uc := Unseq[Block[(SA[I] + N - 1) mod N]];
    J := 0;
    while Mtf[J] <> Uc do Inc(J);
    if J = 0 then
    begin
      Inc(ZRun);
      Continue;
    end;
    FlushZeros;
    AddSym(J + 1);
    while J > 0 do
    begin
      Mtf[J] := Mtf[J - 1];
      Dec(J);
    end;
    Mtf[0] := Uc;
  end;
  FlushZeros;
  AddSym(NumInUse + 1); { EOB }

  MakeCodeLengths(Lens, Freq, Alpha, 17);
  { canonical codes, by length then symbol, as the decoder rebuilds them }
  Code := 0;
  for L := 1 to MaxCodeLen do
  begin
    for I := 0 to Alpha - 1 do
      if Lens[I] = L then
      begin
        Codes[I] := Code;
        Inc(Code);
      end;
    Code := Code shl 1;
  end;

  { block header }
  PutBits(W, 24, $314159);
  PutBits(W, 24, $265359);
  PutU32(W, Crc);
  PutBits(W, 1, 0);
  PutBits(W, 24, OrigPtr);
  Bits16 := 0;
  for I := 0 to 15 do
    for J := 0 to 15 do
      if InUse[I * 16 + J] then Bits16 := Bits16 or ($8000 shr I);
  PutBits(W, 16, Bits16);
  for I := 0 to 15 do
    if (Bits16 and ($8000 shr I)) <> 0 then
    begin
      Code := 0;
      for J := 0 to 15 do
        if InUse[I * 16 + J] then Code := Code or ($8000 shr J);
      PutBits(W, 16, Code);
    end;
  { two identical tables, every selector 0 (MTF-coded as a single 0 bit) }
  NSel := (NMtf + GroupSize - 1) div GroupSize;
  PutBits(W, 3, 2);
  PutBits(W, 15, NSel);
  for I := 1 to NSel do PutBits(W, 1, 0);
  for G := 0 to 1 do
  begin
    Curr := Lens[0];
    PutBits(W, 5, Curr);
    for I := 0 to Alpha - 1 do
    begin
      while Curr < Lens[I] do
      begin
        PutBits(W, 2, 2);
        Inc(Curr);
      end;
      while Curr > Lens[I] do
      begin
        PutBits(W, 2, 3);
        Dec(Curr);
      end;
      PutBits(W, 1, 0);
    end;
  end;
  for I := 0 to NMtf - 1 do
    PutBits(W, Lens[Syms[I]], Codes[Syms[I]]);
end;

function BZ2Compress(const Data: string): string;
const
  Chunk = 500000; { worst-case RLE growth (5/4) stays under the 900k block }
var
  W: TBitWriter;
  P, N: Integer;
  Combined: Cardinal;
begin
  if not CrcReady then MakeCrcTable;
  W.Out := '';
  W.Len := 0;
  W.Buf := 0;
  W.Count := 0;
  PutByte(W, Ord('B'));
  PutByte(W, Ord('Z'));
  PutByte(W, Ord('h'));
  PutByte(W, Ord('9'));
  Combined := 0;
  P := 1;
  while P <= Length(Data) do
  begin
    N := Length(Data) - P + 1;
    if N > Chunk then N := Chunk;
    WriteBlock(W, Data, P, N, Combined);
    Inc(P, N);
  end;
  PutBits(W, 24, $177245);
  PutBits(W, 24, $385090);
  PutU32(W, Combined);
  if W.Count > 0 then PutBits(W, 8 - W.Count, 0);
  SetLength(W.Out, W.Len);
  Result := W.Out;
end;

end.
