{ GLevelWrite: writes a TAdventureLevel the way the 2.05 editor saves it.

  From graal_analysis client-internals/level-editor-205.md ("Saving"),
  formats/level-binary.md, formats/level-binary-client.md,
  formats/sign-text.md and formats/glevnw01.txt:

    .nw         GLEVNW01 text: 64 BOARD rows, then LINK, SIGN..SIGNEND,
                CHEST, BADDY..BADDYEND, NPC..NPCEND
    otherwise   always GR-V1.03 (the 2.05 editor writes no older version):
                13-bit board, links + '#', baddies + FF FF FF 0A,
                NPCs + '#', chests + '#', signs to the end of the file

  Sign text in a GR-V file uses the sign alphabet (byte - 32). A line break
  is written as the editor wrote it: the escape #K(13) then the newline
  code. Characters outside the alphabet become #K(n). }
unit GLevelWrite;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GLevel;

{ Sign text to sign-alphabet bytes (no x, y, no trailing newline). }
function EncodeSignText(const Text: string): string;
{ The three baddy verses of a level baddy (attack, hurt, player hurt), split
  from the '\'-separated Verses field. }
procedure SplitVerses(const Verses: string; out V1, V2, V3: string);
{ Types 4..6 (swamp soldier, frog, spider) do not talk. }
function BaddyTalks(Kind: Integer): Boolean;
function WriteGRV103(Level: TAdventureLevel): string;
function WriteNW(Level: TAdventureLevel): string;
{ Picks the format from the extension as the 2.05 editor does: '.nw' is
  GLEVNW01, anything else GR-V1.03. }
function LevelToString(Level: TAdventureLevel; const FileName: string): string;
function SaveLevelToFile(Level: TAdventureLevel; const FileName: string): Boolean;

implementation

uses
  SysUtils, Classes;

const
  SignAlphabet: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
    '!?-.,#>()#####"####'':/~&### <####;'#10;
  NWAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  CodeHash = 86; { a literal '#' }

function GlyphCodes(C: Char): string;
begin
  case C of
    'A': Result := Chr(91);
    'B': Result := Chr(92);
    'X': Result := Chr(93);
    'Y': Result := Chr(94);
    'u': Result := Chr(77);
    'd': Result := Chr(78);
    'l': Result := Chr(79);
    'r': Result := Chr(80);
    'h': Result := Chr(74) + Chr(75);
    'x': Result := Chr(71);
    'y': Result := Chr(72);
    'z': Result := Chr(73);
    '4': Result := Chr(87) + Chr(88);
    '.': Result := Chr(67);
  else
    Result := '';
  end;
end;

{ The alphabet index of a plain character, or -1. '#' slots never match. }
function AlphaIndex(C: Char): Integer;
var
  I: Integer;
begin
  Result := -1;
  if C = '#' then Exit;
  for I := 1 to Length(SignAlphabet) do
    if SignAlphabet[I] = C then
    begin
      Result := I - 1;
      Exit;
    end;
end;

function EncodeSignText(const Text: string): string;
var
  T, Codes, G, N: string;
  I, J, K: Integer;
  C: Char;
begin
  { one CRLF form: a newline the decoder kept with its #K(13) and a bare
    newline typed in the editor both become #K(13) + newline }
  T := StringReplace(Text, '#K(13)'#10, #10, [rfReplaceAll]);
  T := StringReplace(T, #13#10, #10, [rfReplaceAll]);
  T := StringReplace(T, #10, '#K(13)'#10, [rfReplaceAll]);
  Codes := '';
  I := 1;
  while I <= Length(T) do
  begin
    C := T[I];
    if C = '#' then
    begin
      G := '';
      if I < Length(T) then G := GlyphCodes(T[I + 1]);
      if G <> '' then
      begin
        Codes := Codes + G;
        Inc(I, 2);
        Continue;
      end;
      Codes := Codes + Chr(CodeHash);
    end
    else if C <> #13 then
    begin
      K := AlphaIndex(C);
      if K >= 0 then
        Codes := Codes + Chr(K)
      else
      begin
        { #K(n) with n spelled in alphabet digits }
        Codes := Codes + Chr(CodeHash) + Chr(AlphaIndex('K')) + Chr(AlphaIndex('('));
        N := IntToStr(Ord(C));
        for J := 1 to Length(N) do
          Codes := Codes + Chr(AlphaIndex(N[J]));
        Codes := Codes + Chr(AlphaIndex(')'));
      end;
    end;
    Inc(I);
  end;
  SetLength(Result, Length(Codes));
  for I := 1 to Length(Codes) do
    Result[I] := Chr(Ord(Codes[I]) + 32);
end;

procedure SplitVerses(const Verses: string; out V1, V2, V3: string);
var
  P: Integer;
  S: string;

  function Next: string;
  begin
    P := Pos('\', S);
    if P = 0 then
    begin
      Result := S;
      S := '';
    end
    else
    begin
      Result := Copy(S, 1, P - 1);
      S := Copy(S, P + 1, MaxInt);
    end;
  end;

begin
  S := Verses;
  V1 := Next;
  V2 := Next;
  V3 := Next;
end;

function BaddyTalks(Kind: Integer): Boolean;
begin
  Result := not ((Kind >= 4) and (Kind <= 6));
end;

function GChr(V: Integer): Char;
begin
  if V < -32 then V := -32;
  if V > 223 then V := 223;
  Result := Chr(V + 32);
end;

function NoNewlines(const S: string): string;
begin
  Result := StringReplace(S, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function WriteGRV103(Level: TAdventureLevel): string;
var
  I: Integer;
  V1, V2, V3, Body: string;
  L: TLevelLink;
begin
  Result := 'GR-V1.03' + WriteBoard13(Level.Tiles);
  for I := 0 to High(Level.Links) do
  begin
    L := Level.Links[I];
    Result := Result + NoNewlines(L.Dest) + ' ' + IntToStr(L.X) + ' ' + IntToStr(L.Y) + ' ' +
      IntToStr(L.W) + ' ' + IntToStr(L.H) + ' ' + NoNewlines(L.NewX) + ' ' + NoNewlines(L.NewY) + #10;
  end;
  Result := Result + '#'#10;
  for I := 0 to High(Level.Baddies) do
    with Level.Baddies[I] do
    begin
      { a first byte >= $80 would end the section on load }
      if (X < 0) or (X >= $80) or (Y < 0) or (Y > 255) or (Kind < 0) or (Kind > 255) then
        Continue;
      if BaddyTalks(Kind) then
        SplitVerses(Verses, V1, V2, V3)
      else
      begin
        V1 := ''; V2 := ''; V3 := '';
      end;
      Result := Result + Chr(X) + Chr(Y) + Chr(Kind) +
        NoNewlines(V1) + '\' + NoNewlines(V2) + '\' + NoNewlines(V3) + #10;
    end;
  Result := Result + #$FF#$FF#$FF#10;
  for I := 0 to High(Level.NPCs) do
    with Level.NPCs[I] do
    begin
      Body := StringReplace(Script, #13#10, #10, [rfReplaceAll]);
      Body := StringReplace(Body, #10, #$A7, [rfReplaceAll]);
      Result := Result + GChr(Trunc(X)) + GChr(Trunc(Y)) + NoNewlines(Image) + '#' + Body + #10;
    end;
  Result := Result + '#'#10;
  for I := 0 to High(Level.Chests) do
    with Level.Chests[I] do
      Result := Result + GChr(X) + GChr(Y) + GChr(Item) + GChr(Sign) + #10;
  Result := Result + '#'#10;
  for I := 0 to High(Level.Signs) do
    with Level.Signs[I] do
      Result := Result + GChr(X) + GChr(Y) + EncodeSignText(Text) + #10;
end;

{ NPC positions may be fractional; always with a '.' whatever the locale. }
function FloatStr(V: Double): string;
begin
  if Frac(V) = 0 then
    Result := IntToStr(Trunc(V))
  else
    Result := StringReplace(FloatToStr(V), ',', '.', []);
end;

{ GLEVNW01 fields are space separated and may not be empty. }
function NWToken(const S: string): string;
begin
  Result := StringReplace(NoNewlines(S), ' ', '_', [rfReplaceAll]);
  if Result = '' then Result := '-';
end;

{ Lines of a text block, without an empty last line from a trailing newline. }
function BlockLines(const Text: string): string;
begin
  Result := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  if (Result <> '') and (Result[Length(Result)] = #10) then
    Result := Copy(Result, 1, Length(Result) - 1);
  if Result <> '' then Result := Result + #10;
end;

function WriteNW(Level: TAdventureLevel): string;
var
  X, Y, I, T: Integer;
  Row, ItemS, Img, V1, V2, V3: string;
  SB: TStringList;
begin
  SB := TStringList.Create;
  try
    SB.Add('GLEVNW01');
    for Y := 0 to BoardH - 1 do
    begin
      SetLength(Row, BoardW * 2);
      for X := 0 to BoardW - 1 do
      begin
        T := Level.Tiles[X + Y * BoardW] and $FFF;
        Row[X * 2 + 1] := NWAlphabet[(T shr 6) + 1];
        Row[X * 2 + 2] := NWAlphabet[(T and 63) + 1];
      end;
      SB.Add('BOARD 0 ' + IntToStr(Y) + ' 64 0 ' + Row);
    end;
    for I := 0 to High(Level.Links) do
      with Level.Links[I] do
        SB.Add('LINK ' + NWToken(Dest) + ' ' + IntToStr(X) + ' ' + IntToStr(Y) + ' ' +
          IntToStr(W) + ' ' + IntToStr(H) + ' ' + NWToken(NewX) + ' ' + NWToken(NewY));
    Result := '';
    for I := 0 to SB.Count - 1 do
      Result := Result + SB[I] + #10;
    for I := 0 to High(Level.Signs) do
      with Level.Signs[I] do
        Result := Result + #10'SIGN ' + IntToStr(X) + ' ' + IntToStr(Y) + #10 +
          BlockLines(StringReplace(Text, '#K(13)'#10, #10, [rfReplaceAll])) + 'SIGNEND'#10;
    for I := 0 to High(Level.Chests) do
      with Level.Chests[I] do
      begin
        if (Item >= 0) and (Item <= High(ItemNames)) then
          ItemS := ItemNames[Item]
        else
          ItemS := IntToStr(Item);
        Result := Result + #10'CHEST ' + IntToStr(X) + ' ' + IntToStr(Y) + ' ' + ItemS + ' ' +
          IntToStr(Sign) + #10;
      end;
    for I := 0 to High(Level.Baddies) do
      with Level.Baddies[I] do
      begin
        if BaddyTalks(Kind) then
          SplitVerses(Verses, V1, V2, V3)
        else
        begin
          V1 := ''; V2 := ''; V3 := '';
        end;
        Result := Result + #10'BADDY ' + IntToStr(X) + ' ' + IntToStr(Y) + ' ' + IntToStr(Kind) + #10 +
          NoNewlines(V1) + #10 + NoNewlines(V2) + #10 + NoNewlines(V3) + #10'BADDYEND'#10;
      end;
    for I := 0 to High(Level.NPCs) do
      with Level.NPCs[I] do
      begin
        Img := NWToken(Image);
        Result := Result + #10'NPC ' + Img + ' ' + FloatStr(X) + ' ' + FloatStr(Y) + #10 +
          BlockLines(Script) + 'NPCEND'#10;
      end;
  finally
    SB.Free;
  end;
end;

function LevelToString(Level: TAdventureLevel; const FileName: string): string;
begin
  if LowerCase(ExtractFileExt(FileName)) = '.nw' then
    Result := WriteNW(Level)
  else
    Result := WriteGRV103(Level);
end;

function SaveLevelToFile(Level: TAdventureLevel; const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  S := LevelToString(Level, FileName);
  try
    F := TFileStream.Create(FileName, fmCreate);
    try
      if S <> '' then F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
    Result := True;
  except
    on E: Exception do
      Level.LastError := E.Message;
  end;
end;

end.
