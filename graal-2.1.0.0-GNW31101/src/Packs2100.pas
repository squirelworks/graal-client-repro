{ Packs2100: the 2.1 updater's packages, as the Graal2001 setup program
  handled them.

  Graal 2.1.0.0 was not shipped as an installer. The download was a small
  setup program (a web installer made from the Cygwin setup of 2001) that
  read a package list, setup.ini, from a mirror and fetched the packages it
  names (graal_analysis notes; the originals are copies of the official
  downloads of May to November 2001):

  - mirrors.lst: one mirror a line, "URL;host;country;".
  - setup.ini: "setup-timestamp:" and "setup-version:" lines, then one
    block per component, opened by "@ Name" ("@ -Name": not picked unless
    asked for; the developer tools). Each block has "version: 1.0.0-8" and
    "install: graal/main_1008.pack 1", and after a "[prev]" line the
    previous version and its package.
  - A .pack is a tar.gz archive with another name: the files at their
    paths under the install folder (mainexe_2100.pack holds Graal.exe and
    newfeatures2001.txt; main_1010, levels_1004, sounds_1003 and dev_1004
    the rest).
  - setup/installed.db in the install folder: the line "INSTALLED.DB 2",
    then a line "name package 0" for each component installed. A component
    whose version in setup.ini is newer than the installed one is fetched
    again.

  This unit has the parts with no window or network: the two lists, the
  installed list, version order, gunzip (its own inflate, so Delphi 4 to 7
  and Free Pascal read a .pack the same way) and the tar reader. }
unit Packs2100;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

type
  TPackComponent = record
    Name: string;        { "Executable", "Main", ... }
    Optional: Boolean;   { "@ -Name" }
    Version: string;     { "2.1.0-0" }
    Install: string;     { "graal/mainexe_2100.pack" }
    PrevVersion, PrevInstall: string;
  end;
  TPackComponents = array of TPackComponent;

  TSetupIni = record
    Timestamp: string;
    SetupVersion: string;
    Components: TPackComponents;
  end;

  TMirror = record
    Url, Host, Country: string;
  end;
  TMirrors = array of TMirror;

{ setup.ini as text. Unknown lines are skipped. }
function ParseSetupIni(const Text: string): TSetupIni;
function ParseMirrors(const Text: string): TMirrors;

{ "1.0.0-8" against "1.0.0-10": -1, 0 or 1, comparing the numbers in turn. }
function CompareVersions(const A, B: string): Integer;

{ setup/installed.db: Names[i] = component, Values: "package version". }
function ParseInstalledDb(const Text: string; Names, Packages: TStrings): Boolean;
function InstalledDbText(Names, Packages: TStrings): string;

{ The package file name as installed.db writes it, and the version a
  package name carries (main_1008.pack -> 1.0.0-8 is not recoverable in
  general, so installed.db keeps the name and the version is taken from
  the matching setup.ini line). }
function PackBaseName(const Install: string): string;

{ gzip (RFC 1952) to plain; False on a bad stream or CRC. }
function Gunzip(const Data: string; out Plain: string): Boolean;
{ raw deflate (RFC 1951) to plain. }
function Inflate(const Data: string; out Plain: string): Boolean;
function Crc32Of(const S: string): Cardinal;

type
  TTarEntry = record
    Name: string;
    IsDir: Boolean;
    Data: string;
  end;
  TTarEntries = array of TTarEntry;

{ A ustar/GNU tar archive in memory. Entries other than files and folders
  (links, devices) are skipped. False when a header is cut or bad. }
function ReadTar(const Data: string; out Entries: TTarEntries): Boolean;

{ True when a path from an archive stays inside the install folder: no
  drive, no leading slash, no "..". }
function SafeArchivePath(const Name: string): Boolean;

implementation

uses
  SysUtils;

function Trimmed(const S: string): string;
begin
  Result := Trim(S);
end;

function AfterColon(const Line: string): string;
var
  P: Integer;
begin
  P := Pos(':', Line);
  Result := Trimmed(Copy(Line, P + 1, MaxInt));
end;

function StartsText(const Prefix, S: string): Boolean;
begin
  Result := LowerCase(Copy(S, 1, Length(Prefix))) = LowerCase(Prefix);
end;

{ the first word of an "install:" value: the path; the number after it
  is the size field, which the Graal lists set to 1 }
function FirstWord(const S: string): string;
var
  P: Integer;
begin
  Result := Trimmed(S);
  P := Pos(' ', Result);
  if P > 0 then Result := Copy(Result, 1, P - 1);
end;

function ParseSetupIni(const Text: string): TSetupIni;
var
  L: TStringList;
  I, N: Integer;
  Line: string;
  Prev: Boolean;
begin
  Result.Timestamp := '';
  Result.SetupVersion := '';
  SetLength(Result.Components, 0);
  L := TStringList.Create;
  try
    L.Text := Text;
    N := -1;
    Prev := False;
    for I := 0 to L.Count - 1 do
    begin
      Line := Trimmed(L[I]);
      if (Line = '') or (Line[1] = '#') then Continue;
      if Line[1] = '@' then
      begin
        N := Length(Result.Components);
        SetLength(Result.Components, N + 1);
        Line := Trimmed(Copy(Line, 2, MaxInt));
        Result.Components[N].Optional := (Line <> '') and (Line[1] = '-');
        if Result.Components[N].Optional then Line := Trimmed(Copy(Line, 2, MaxInt));
        Result.Components[N].Name := Line;
        Result.Components[N].Version := '';
        Result.Components[N].Install := '';
        Result.Components[N].PrevVersion := '';
        Result.Components[N].PrevInstall := '';
        Prev := False;
      end
      else if LowerCase(Line) = '[prev]' then Prev := True
      else if StartsText('setup-timestamp:', Line) then Result.Timestamp := AfterColon(Line)
      else if StartsText('setup-version:', Line) then Result.SetupVersion := AfterColon(Line)
      else if N >= 0 then
      begin
        if StartsText('version:', Line) then
        begin
          if Prev then Result.Components[N].PrevVersion := AfterColon(Line)
          else Result.Components[N].Version := AfterColon(Line);
        end
        else if StartsText('install:', Line) then
        begin
          if Prev then Result.Components[N].PrevInstall := FirstWord(AfterColon(Line))
          else Result.Components[N].Install := FirstWord(AfterColon(Line));
        end;
      end;
    end;
  finally
    L.Free;
  end;
end;

function ParseMirrors(const Text: string): TMirrors;
var
  L: TStringList;
  I, N, P: Integer;
  Line, Rest: string;
  F: array[0..2] of string;
  K: Integer;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.Text := Text;
    for I := 0 to L.Count - 1 do
    begin
      Line := Trimmed(L[I]);
      if (Line = '') or (Line[1] = '#') then Continue;
      Rest := Line;
      for K := 0 to 2 do
      begin
        P := Pos(';', Rest);
        if P = 0 then
        begin
          F[K] := Rest;
          Rest := '';
        end
        else
        begin
          F[K] := Copy(Rest, 1, P - 1);
          Delete(Rest, 1, P);
        end;
      end;
      if F[0] = '' then Continue;
      N := Length(Result);
      SetLength(Result, N + 1);
      Result[N].Url := F[0];
      Result[N].Host := F[1];
      Result[N].Country := F[2];
    end;
  finally
    L.Free;
  end;
end;

function CompareVersions(const A, B: string): Integer;
var
  PA, PB, NA, NB: Integer;

  function NextNum(const S: string; var P: Integer; out V: Integer): Boolean;
  begin
    while (P <= Length(S)) and not (S[P] in ['0'..'9']) do Inc(P);
    Result := P <= Length(S);
    V := 0;
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do
    begin
      if V < 100000000 then V := V * 10 + Ord(S[P]) - Ord('0');
      Inc(P);
    end;
  end;

var
  HA, HB: Boolean;
begin
  PA := 1;
  PB := 1;
  repeat
    HA := NextNum(A, PA, NA);
    HB := NextNum(B, PB, NB);
    if not HA then NA := 0;
    if not HB then NB := 0;
    if NA < NB then
    begin
      Result := -1;
      Exit;
    end;
    if NA > NB then
    begin
      Result := 1;
      Exit;
    end;
  until not HA and not HB;
  Result := 0;
end;

function PackBaseName(const Install: string): string;
var
  I: Integer;
begin
  Result := Install;
  for I := Length(Result) downto 1 do
    if (Result[I] = '/') or (Result[I] = '\') then
    begin
      Result := Copy(Result, I + 1, MaxInt);
      Break;
    end;
end;

function ParseInstalledDb(const Text: string; Names, Packages: TStrings): Boolean;
var
  L: TStringList;
  I, P: Integer;
  Line, Rest: string;
begin
  Names.Clear;
  Packages.Clear;
  L := TStringList.Create;
  try
    L.Text := Text;
    Result := (L.Count = 0) or (Trimmed(L[0]) = 'INSTALLED.DB 2');
    if not Result then Exit;
    for I := 1 to L.Count - 1 do
    begin
      Line := Trimmed(L[I]);
      if Line = '' then Continue;
      P := Pos(' ', Line);
      if P = 0 then Continue;
      Names.Add(Copy(Line, 1, P - 1));
      Rest := Trimmed(Copy(Line, P + 1, MaxInt));
      P := Pos(' ', Rest);
      if P > 0 then Rest := Copy(Rest, 1, P - 1);
      Packages.Add(Rest);
    end;
  finally
    L.Free;
  end;
end;

function InstalledDbText(Names, Packages: TStrings): string;
var
  I: Integer;
begin
  Result := 'INSTALLED.DB 2' + #10;
  for I := 0 to Names.Count - 1 do
    Result := Result + Names[I] + ' ' + Packages[I] + ' 0' + #10;
end;

{ ---- CRC-32 (the gzip trailer) ---- }

var
  CrcTable: array[0..255] of Cardinal;
  CrcReady: Boolean = False;

procedure MakeCrcTable;
var
  I, K: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := Cardinal(I);
    for K := 0 to 7 do
      if C and 1 <> 0 then C := $EDB88320 xor (C shr 1) else C := C shr 1;
    CrcTable[I] := C;
  end;
  CrcReady := True;
end;

function Crc32Of(const S: string): Cardinal;
var
  I: Integer;
begin
  if not CrcReady then MakeCrcTable;
  Result := $FFFFFFFF;
  for I := 1 to Length(S) do
    Result := CrcTable[(Result xor Ord(S[I])) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

{ ---- inflate (RFC 1951) ---- }

type
  THuff = record
    Counts: array[0..15] of Word;
    Symbols: array[0..287] of Word;
  end;

  TBits = record
    Src: string;
    Pos: Integer;     { next byte, 1-based }
    Buf: Cardinal;
    Cnt: Integer;
    Bad: Boolean;
  end;

function GetBits(var B: TBits; N: Integer): Cardinal;
begin
  while B.Cnt < N do
  begin
    if B.Pos > Length(B.Src) then
    begin
      B.Bad := True;
      Result := 0;
      Exit;
    end;
    B.Buf := B.Buf or (Cardinal(Ord(B.Src[B.Pos])) shl B.Cnt);
    Inc(B.Pos);
    Inc(B.Cnt, 8);
  end;
  Result := B.Buf and ((Cardinal(1) shl N) - 1);
  B.Buf := B.Buf shr N;
  Dec(B.Cnt, N);
end;

{ Builds a canonical Huffman table from code lengths; False if over-full. }
function BuildHuff(var H: THuff; const Lengths: array of Byte; N: Integer): Boolean;
var
  Offs: array[0..15] of Word;
  I, Left: Integer;
begin
  FillChar(H.Counts, SizeOf(H.Counts), 0);
  for I := 0 to N - 1 do Inc(H.Counts[Lengths[I]]);
  H.Counts[0] := 0;
  Left := 1;
  Result := True;
  for I := 1 to 15 do
  begin
    Left := Left shl 1;
    Dec(Left, H.Counts[I]);
    if Left < 0 then
    begin
      Result := False;
      Exit;
    end;
  end;
  Offs[1] := 0;
  for I := 1 to 14 do Offs[I + 1] := Offs[I] + H.Counts[I];
  for I := 0 to N - 1 do
    if Lengths[I] <> 0 then
    begin
      H.Symbols[Offs[Lengths[I]]] := I;
      Inc(Offs[Lengths[I]]);
    end;
end;

function Decode(var B: TBits; const H: THuff): Integer;
var
  Code, First, Index, Len, Count: Integer;
begin
  Code := 0;
  First := 0;
  Index := 0;
  for Len := 1 to 15 do
  begin
    Code := Code or Integer(GetBits(B, 1));
    if B.Bad then Break;
    Count := H.Counts[Len];
    if Code - Count < First then
    begin
      Result := H.Symbols[Index + (Code - First)];
      Exit;
    end;
    Inc(Index, Count);
    Inc(First, Count);
    First := First shl 1;
    Code := Code shl 1;
  end;
  Result := -1;
end;

const
  LenBase: array[0..28] of Word = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27,
    31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LenExtra: array[0..28] of Byte = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DistBase: array[0..29] of Word = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97,
    129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
    16385, 24577);
  DistExtra: array[0..29] of Byte = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);
  { the plain output is capped: a hostile pack cannot fill the memory }
  InflateMax = 64 * 1024 * 1024;

type
  TOut = record
    S: string;
    N: Integer;
  end;

procedure PutByte(var O: TOut; C: Char);
begin
  if O.N >= Length(O.S) then SetLength(O.S, Length(O.S) * 2 + 4096);
  Inc(O.N);
  O.S[O.N] := C;
end;

function Codes(var B: TBits; var O: TOut; const LenH, DistH: THuff): Boolean;
var
  Sym, Len, Dist, I: Integer;
begin
  Result := False;
  repeat
    Sym := Decode(B, LenH);
    if (Sym < 0) or B.Bad then Exit;
    if Sym < 256 then PutByte(O, Chr(Sym))
    else if Sym > 256 then
    begin
      Dec(Sym, 257);
      if Sym > 28 then Exit;
      Len := LenBase[Sym] + Integer(GetBits(B, LenExtra[Sym]));
      Sym := Decode(B, DistH);
      if (Sym < 0) or (Sym > 29) or B.Bad then Exit;
      Dist := DistBase[Sym] + Integer(GetBits(B, DistExtra[Sym]));
      if B.Bad or (Dist > O.N) then Exit;
      for I := 1 to Len do PutByte(O, O.S[O.N - Dist + 1]);
    end;
    if O.N > InflateMax then Exit;
  until Sym = 256;
  Result := True;
end;

function Inflate(const Data: string; out Plain: string): Boolean;
const
  Order: array[0..18] of Byte = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);
var
  B: TBits;
  O: TOut;
  Last, BType, Len, NLen, NL, ND, NC, I, Sym, Rep, Index: Integer;
  Lengths: array[0..319] of Byte;
  DistLengths: array[0..31] of Byte;
  LenH, DistH, CodeH: THuff;
begin
  Result := False;
  Plain := '';
  B.Src := Data;
  B.Pos := 1;
  B.Buf := 0;
  B.Cnt := 0;
  B.Bad := False;
  O.S := '';
  O.N := 0;
  repeat
    Last := GetBits(B, 1);
    BType := GetBits(B, 2);
    if B.Bad then Exit;
    case BType of
      0:
        begin
          B.Buf := 0;
          B.Cnt := 0;
          if B.Pos + 3 > Length(Data) then Exit;
          Len := Ord(Data[B.Pos]) or (Ord(Data[B.Pos + 1]) shl 8);
          NLen := Ord(Data[B.Pos + 2]) or (Ord(Data[B.Pos + 3]) shl 8);
          Inc(B.Pos, 4);
          if Len <> (not NLen) and $FFFF then Exit;
          if B.Pos + Len - 1 > Length(Data) then Exit;
          for I := 0 to Len - 1 do PutByte(O, Data[B.Pos + I]);
          Inc(B.Pos, Len);
        end;
      1:
        begin
          for I := 0 to 143 do Lengths[I] := 8;
          for I := 144 to 255 do Lengths[I] := 9;
          for I := 256 to 279 do Lengths[I] := 7;
          for I := 280 to 287 do Lengths[I] := 8;
          BuildHuff(LenH, Lengths, 288);
          for I := 0 to 29 do Lengths[I] := 5;
          BuildHuff(DistH, Lengths, 30);
          if not Codes(B, O, LenH, DistH) then Exit;
        end;
      2:
        begin
          NL := GetBits(B, 5) + 257;
          ND := GetBits(B, 5) + 1;
          NC := GetBits(B, 4) + 4;
          if B.Bad or (NL > 286) or (ND > 30) then Exit;
          FillChar(Lengths, SizeOf(Lengths), 0);
          for I := 0 to NC - 1 do Lengths[Order[I]] := GetBits(B, 3);
          if not BuildHuff(CodeH, Lengths, 19) then Exit;
          Index := 0;
          FillChar(Lengths, SizeOf(Lengths), 0);
          while Index < NL + ND do
          begin
            Sym := Decode(B, CodeH);
            if (Sym < 0) or B.Bad then Exit;
            if Sym < 16 then
            begin
              Lengths[Index] := Sym;
              Inc(Index);
            end
            else
            begin
              Len := 0;
              if Sym = 16 then
              begin
                if Index = 0 then Exit;
                Len := Lengths[Index - 1];
                Rep := 3 + Integer(GetBits(B, 2));
              end
              else if Sym = 17 then Rep := 3 + Integer(GetBits(B, 3))
              else Rep := 11 + Integer(GetBits(B, 7));
              if Index + Rep > NL + ND then Exit;
              for I := 1 to Rep do
              begin
                Lengths[Index] := Len;
                Inc(Index);
              end;
            end;
          end;
          if not BuildHuff(LenH, Lengths, NL) then Exit;
          for I := 0 to ND - 1 do DistLengths[I] := Lengths[NL + I];
          if not BuildHuff(DistH, DistLengths, ND) then Exit;
          if not Codes(B, O, LenH, DistH) then Exit;
        end;
    else
      Exit;
    end;
  until Last = 1;
  SetLength(O.S, O.N);
  Plain := O.S;
  Result := True;
end;

function Gunzip(const Data: string; out Plain: string): Boolean;
var
  P, Flags, XLen: Integer;
  Crc, Size: Cardinal;

  function U32(At: Integer): Cardinal;
  begin
    Result := Cardinal(Ord(Data[At])) or (Cardinal(Ord(Data[At + 1])) shl 8) or
      (Cardinal(Ord(Data[At + 2])) shl 16) or (Cardinal(Ord(Data[At + 3])) shl 24);
  end;

begin
  Result := False;
  Plain := '';
  if (Length(Data) < 18) or (Data[1] <> #$1F) or (Data[2] <> #$8B) or (Data[3] <> #8) then Exit;
  Flags := Ord(Data[4]);
  P := 11;
  if Flags and 4 <> 0 then
  begin
    XLen := Ord(Data[P]) or (Ord(Data[P + 1]) shl 8);
    Inc(P, 2 + XLen);
  end;
  if Flags and 8 <> 0 then
  begin
    while (P <= Length(Data)) and (Data[P] <> #0) do Inc(P);
    Inc(P);
  end;
  if Flags and 16 <> 0 then
  begin
    while (P <= Length(Data)) and (Data[P] <> #0) do Inc(P);
    Inc(P);
  end;
  if Flags and 2 <> 0 then Inc(P, 2);
  if P + 8 > Length(Data) + 1 then Exit;
  Crc := U32(Length(Data) - 7);
  Size := U32(Length(Data) - 3);
  if not Inflate(Copy(Data, P, Length(Data) - 8 - P + 1), Plain) then Exit;
  if (Crc32Of(Plain) <> Crc) or (Cardinal(Length(Plain)) <> Size) then
  begin
    Plain := '';
    Exit;
  end;
  Result := True;
end;

{ ---- tar ---- }

function Octal(const S: string): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] in ['0'..'7'] then Result := Result * 8 + Ord(S[I]) - Ord('0')
    else if (S[I] <> ' ') and (S[I] <> #0) then Break;
end;

function CString(const S: string): string;
var
  P: Integer;
begin
  P := Pos(#0, S);
  if P > 0 then Result := Copy(S, 1, P - 1) else Result := S;
end;

function SafeArchivePath(const Name: string): Boolean;
var
  S: string;
begin
  S := StringReplace(Name, '\', '/', [rfReplaceAll]);
  Result := (S <> '') and (S[1] <> '/') and (Pos(':', S) = 0) and
    (Pos('/../', '/' + S + '/') = 0);
end;

function ReadTar(const Data: string; out Entries: TTarEntries): Boolean;
var
  P, N: Integer;
  H, Name, Prefix: string;
  Size: Int64;
  T: Char;
  LongName: string;
begin
  SetLength(Entries, 0);
  Result := False;
  P := 1;
  LongName := '';
  while P + 511 <= Length(Data) do
  begin
    H := Copy(Data, P, 512);
    if H = StringOfChar(#0, 512) then
    begin
      Result := True;
      Exit;
    end;
    Name := CString(Copy(H, 1, 100));
    Size := Octal(Copy(H, 125, 12));
    T := H[157];
    if Copy(H, 258, 5) = 'ustar' then
    begin
      Prefix := CString(Copy(H, 346, 155));
      if Prefix <> '' then Name := Prefix + '/' + Name;
    end;
    Inc(P, 512);
    if (Size < 0) or (P + Size - 1 > Length(Data)) then Exit;
    if T = 'L' then
      LongName := CString(Copy(Data, P, Size))   { GNU long name for the next entry }
    else
    begin
      if LongName <> '' then
      begin
        Name := LongName;
        LongName := '';
      end;
      if (T = '0') or (T = #0) or (T = '5') then
      begin
        N := Length(Entries);
        SetLength(Entries, N + 1);
        Entries[N].Name := Name;
        Entries[N].IsDir := (T = '5') or ((Name <> '') and (Name[Length(Name)] = '/'));
        if Entries[N].IsDir then Entries[N].Data := ''
        else Entries[N].Data := Copy(Data, P, Size);
      end;
    end;
    Inc(P, ((Size + 511) div 512) * 512);
  end;
  { an archive may end without the two zero blocks }
  Result := P > Length(Data);
end;

end.
