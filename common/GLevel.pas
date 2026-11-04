{ GLevel: the 64x64 level, its loaders and the GR-V board writer.

  Accepted inputs, as in 2.05 (graal_analysis client-internals/
  client-architecture-205.md, formats/level-binary-client.md,
  formats/glevnw01.txt):
    GLEVNW01                       text levels (.nw)
    GR-V1.00 .. GR-V1.03           binary Graal levels (.graal); no GR-V1.04
    Z3-V1.03, Z3-V1.04             binary Zelda levels (.zelda)
    PLO_BOARDPACKET                4096 little-endian words from the server

  Board coding: 12-bit codes for GR-V1.00/1.01 and Z3, 13-bit for GR-V1.02
  and GR-V1.03, packed least significant bit first. A code with the top bit
  set is a run header: low 8 bits = count, bit 0x100 = "double" (an AB pair
  repeated). }
unit GLevel;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  BoardW = 64;
  BoardH = 64;
  BoardSize = BoardW * BoardH;

type
  TBoardTiles = array[0..BoardSize - 1] of Word;

  TLevelLink = record
    Dest: string;
    X, Y, W, H: Integer;
    NewX, NewY: string; { may be 'playerx' / 'playery' }
  end;

  TLevelSign = record
    X, Y: Integer;
    Text: string;
  end;

  TLevelChest = record
    X, Y, Item, Sign: Integer;
  end;

  TLevelNPC = record
    X, Y: Double;
    Image: string;
    Script: string;
  end;

  TLevelBaddy = record
    X, Y, Kind: Integer;
    Verses: string;
  end;

  TAdventureLevel = class
  public
    Name: string;
    Magic: string;
    Tiles: TBoardTiles;
    Links: array of TLevelLink;
    Signs: array of TLevelSign;
    Chests: array of TLevelChest;
    NPCs: array of TLevelNPC;
    Baddies: array of TLevelBaddy;
    LastError: string;
    constructor Create;
    procedure Clear;
    function Tile(X, Y: Integer): Word;
    { Picks the loader from the 8-byte magic, as TLevel.loadLevel does for
      an unknown extension. }
    function LoadFromString(const Data: string): Boolean;
    function LoadFromFile(const FileName: string): Boolean;
    { PLO_BOARDPACKET payload: 8192 bytes, 4096 little-endian words. }
    function LoadBoardPacket(const Data: string): Boolean;
    function LoadGRV(const Data: string): Boolean;
    function LoadNW(const Data: string): Boolean;
  end;

function GRVCodeWidth(const Magic: string): Integer;
{ The 2.05 board writer: 13-bit codes, single and double runs. }
function WriteBoard13(const Tiles: TBoardTiles): string;
{ Sign text from a .graal file: byte - 32 indexes the shared alphabet. }
function DecodeSignText(const Enc: string): string;

implementation

uses
  SysUtils, Classes;

const
  SignChars: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
    '!?-.,#>()#####"####'':/~&### <####;'#10;
  NWAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function GRVCodeWidth(const Magic: string): Integer;
begin
  if (Magic = 'GR-V1.02') or (Magic = 'GR-V1.03') then
    Result := 13
  else
    Result := 12;
end;

function DecodeSignText(const Enc: string): string;
var
  I, K, Skip: Integer;
  C: Char;
  L: string;
begin
  Result := '';
  I := 1;
  while I <= Length(Enc) do
  begin
    K := Ord(Enc[I]) - 32;
    if (K >= 0) and (K < Length(SignChars)) then
      C := SignChars[K + 1]
    else
      C := '?';
    if C = '#' then
    begin
      Skip := 1;
      L := '';
      case K of
        91: L := 'A';
        92: L := 'B';
        93: L := 'X';
        94: L := 'Y';
        77: L := 'u';
        78: L := 'd';
        79: L := 'l';
        80: L := 'r';
        74: begin L := 'h'; Skip := 2; end;
        71: L := 'x';
        72: L := 'y';
        73: L := 'z';
        87: begin L := '4'; Skip := 2; end;
        67: L := '.';
      end;
      Result := Result + '#' + L;
      Inc(I, Skip - 1);
    end
    else
      Result := Result + C;
    Inc(I);
  end;
end;

{ Board writer }

function WriteBoard13(const Tiles: TBoardTiles): string;
var
  Codes: array of Word;
  NCodes: Integer;
  I, N: Integer;
  T, T2: Word;
  Acc: Cardinal;
  NAcc: Integer;

  procedure Emit(C: Word);
  begin
    if NCodes >= Length(Codes) then
      SetLength(Codes, Length(Codes) * 2 + 64);
    Codes[NCodes] := C;
    Inc(NCodes);
  end;

begin
  NCodes := 0;
  SetLength(Codes, 1024);
  I := 0;
  while I < BoardSize do
  begin
    T := Tiles[I];
    if (I < BoardSize - 3) and (Tiles[I + 1] = T) then
    begin
      N := 2;
      Inc(I, 2);
      while (N < 64) and (I < BoardSize) and (Tiles[I] = T) do
      begin
        Inc(N);
        Inc(I);
      end;
      Emit($1000 or N);
      Emit(T and $FFF);
    end
    else if (I < BoardSize - 3) and (Tiles[I + 2] = T) and (Tiles[I + 1] = Tiles[I + 3]) then
    begin
      T2 := Tiles[I + 1];
      N := 2;
      Inc(I, 4);
      while (N < 64) and (I < BoardSize - 1) and (Tiles[I] = T) and (Tiles[I + 1] = T2) do
      begin
        Inc(N);
        Inc(I, 2);
      end;
      Emit($1100 or N);
      Emit(T and $FFF);
      Emit(T2 and $FFF);
    end
    else
    begin
      Emit(T and $FFF);
      Inc(I);
    end;
  end;
  Result := '';
  Acc := 0;
  NAcc := 0;
  for I := 0 to NCodes - 1 do
  begin
    Acc := Acc or (Cardinal(Codes[I] and $1FFF) shl NAcc);
    Inc(NAcc, 13);
    while NAcc >= 8 do
    begin
      Result := Result + Chr(Acc and $FF);
      Acc := Acc shr 8;
      Dec(NAcc, 8);
    end;
  end;
  if NAcc > 0 then
    Result := Result + Chr(Acc and $FF);
end;

{ TAdventureLevel }

constructor TAdventureLevel.Create;
begin
  inherited Create;
  Clear;
end;

procedure TAdventureLevel.Clear;
begin
  FillChar(Tiles, SizeOf(Tiles), 0);
  SetLength(Links, 0);
  SetLength(Signs, 0);
  SetLength(Chests, 0);
  SetLength(NPCs, 0);
  SetLength(Baddies, 0);
  Magic := '';
  LastError := '';
end;

function TAdventureLevel.Tile(X, Y: Integer): Word;
begin
  if (X < 0) or (Y < 0) or (X >= BoardW) or (Y >= BoardH) then
    Result := 0
  else
    Result := Tiles[X + Y * BoardW];
end;

function TAdventureLevel.LoadBoardPacket(const Data: string): Boolean;
var
  I: Integer;
begin
  Result := Length(Data) >= BoardSize * 2;
  if not Result then
  begin
    LastError := Format('board packet is %d bytes, expected %d', [Length(Data), BoardSize * 2]);
    Exit;
  end;
  for I := 0 to BoardSize - 1 do
    Tiles[I] := Ord(Data[I * 2 + 1]) or (Ord(Data[I * 2 + 2]) shl 8);
end;

function TAdventureLevel.LoadFromFile(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then
  begin
    LastError := 'no such file: ' + FileName;
    Exit;
  end;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(S, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(S[1], F.Size);
  finally
    F.Free;
  end;
  Name := ExtractFileName(FileName);
  Result := LoadFromString(S);
end;

function TAdventureLevel.LoadFromString(const Data: string): Boolean;
var
  M: string;
begin
  M := Copy(Data, 1, 8);
  if M = 'GLEVNW01' then
    Result := LoadNW(Data)
  else if (M = 'GR-V1.00') or (M = 'GR-V1.01') or (M = 'GR-V1.02') or
    (M = 'GR-V1.03') or (M = 'Z3-V1.03') or (M = 'Z3-V1.04') then
    Result := LoadGRV(Data)
  else
  begin
    LastError := 'unknown level magic ' + M;
    Result := False;
  end;
end;

{ ---- binary GR-V / Z3-V ---- }

function TAdventureLevel.LoadGRV(const Data: string): Boolean;
var
  P: Integer; { 1-based read position }
  Width, Flag, Code, Count, N, I: Integer;
  Buf: Cardinal;
  NBits: Integer;
  Double, HaveFirst: Boolean;
  First: Word;
  IsGR: Boolean;
  S, Rec: string;
  Parts: TStringList;
  L: TLevelLink;
  B: TLevelBaddy;
  C: TLevelChest;
  NP: TLevelNPC;
  SG: TLevelSign;
  K: Integer;

  procedure Put(T: Word);
  begin
    if N < BoardSize then
    begin
      Tiles[N] := T;
      Inc(N);
    end;
  end;

  function ReadLine(out Line: string): Boolean;
  var
    E: Integer;
  begin
    Result := P <= Length(Data);
    if not Result then Exit;
    E := P;
    while (E <= Length(Data)) and (Data[E] <> #10) do Inc(E);
    Line := Copy(Data, P, E - P);
    P := E + 1;
  end;

begin
  Result := False;
  Clear;
  Magic := Copy(Data, 1, 8);
  IsGR := Copy(Magic, 1, 3) = 'GR-';
  Width := GRVCodeWidth(Magic);
  Flag := 1 shl (Width - 1);
  P := 9;
  Buf := 0;
  NBits := 0;
  N := 0;
  Count := 1;
  Double := False;
  HaveFirst := False;
  First := 0;
  while N < BoardSize do
  begin
    while NBits < Width do
    begin
      if P > Length(Data) then
      begin
        LastError := 'board ended early';
        Exit;
      end;
      Buf := Buf or (Cardinal(Ord(Data[P])) shl NBits);
      Inc(P);
      Inc(NBits, 8);
    end;
    Code := Buf and ((1 shl Width) - 1);
    Buf := Buf shr Width;
    Dec(NBits, Width);
    if (Code and Flag) <> 0 then
    begin
      Count := Code and $FF;
      Double := (Code and $100) <> 0;
      Continue;
    end;
    if Count = 1 then
      Put(Code)
    else if not Double then
    begin
      for I := 1 to Count do Put(Code);
      Count := 1;
    end
    else if not HaveFirst then
    begin
      First := Code;
      HaveFirst := True;
    end
    else
    begin
      for I := 1 to Count do
      begin
        Put(First);
        Put(Code);
      end;
      HaveFirst := False;
      Count := 1;
      Double := False;
    end;
  end;

  Parts := TStringList.Create;
  try
    { links, '#'-terminated: "dest x y w h newx newy", dest may hold spaces }
    while ReadLine(S) and (S <> '') and (S <> '#') do
    begin
      Parts.Clear;
      ExtractStrings([' '], [], PChar(S), Parts);
      if Parts.Count < 7 then Continue;
      L.Dest := '';
      for I := 0 to Parts.Count - 7 do
      begin
        if I > 0 then L.Dest := L.Dest + ' ';
        L.Dest := L.Dest + Parts[I];
      end;
      K := Parts.Count;
      L.X := StrToIntDef(Parts[K - 6], 0);
      L.Y := StrToIntDef(Parts[K - 5], 0);
      L.W := StrToIntDef(Parts[K - 4], 0);
      L.H := StrToIntDef(Parts[K - 3], 0);
      L.NewX := Parts[K - 2];
      L.NewY := Parts[K - 1];
      SetLength(Links, Length(Links) + 1);
      Links[High(Links)] := L;
    end;
  finally
    Parts.Free;
  end;

  { baddies: 3 raw bytes then the rest of the line; a #10 only ends the
    record after 3 bytes. Ends at a record whose first byte is >= $80. }
  while True do
  begin
    Rec := '';
    while P <= Length(Data) do
    begin
      if (Data[P] = #10) and (Length(Rec) > 2) then
      begin
        Inc(P);
        Break;
      end;
      Rec := Rec + Data[P];
      Inc(P);
    end;
    if (Length(Rec) < 3) or (Ord(Rec[1]) >= $80) then Break;
    B.X := Ord(Rec[1]);
    B.Y := Ord(Rec[2]);
    B.Kind := Ord(Rec[3]);
    B.Verses := Copy(Rec, 4, MaxInt);
    SetLength(Baddies, Length(Baddies) + 1);
    Baddies[High(Baddies)] := B;
  end;

  if IsGR then
    while ReadLine(S) and (S <> '') and (S <> '#') do
    begin
      if Length(S) < 2 then Continue;
      NP.X := Ord(S[1]) - 32;
      NP.Y := Ord(S[2]) - 32;
      Rec := Copy(S, 3, MaxInt);
      K := Pos('#', Rec);
      if K > 0 then
      begin
        NP.Image := Copy(Rec, 1, K - 1);
        NP.Script := StringReplace(Copy(Rec, K + 1, MaxInt), #$A7, #10, [rfReplaceAll]);
      end
      else
      begin
        NP.Image := Rec;
        NP.Script := '';
      end;
      SetLength(NPCs, Length(NPCs) + 1);
      NPCs[High(NPCs)] := NP;
    end;

  if (Magic = 'GR-V1.01') or (Magic = 'GR-V1.02') or (Magic = 'GR-V1.03') then
    while ReadLine(S) and (S <> '') and (S <> '#') do
    begin
      if Length(S) < 4 then Continue;
      C.X := Ord(S[1]) - 32;
      C.Y := Ord(S[2]) - 32;
      C.Item := Ord(S[3]) - 32;
      C.Sign := Ord(S[4]) - 32;
      SetLength(Chests, Length(Chests) + 1);
      Chests[High(Chests)] := C;
    end;

  { signs: 2.05 reads them to the end of the file }
  while ReadLine(S) do
  begin
    if Length(S) < 2 then Continue;
    SG.X := Ord(S[1]) - 32;
    SG.Y := Ord(S[2]) - 32;
    SG.Text := DecodeSignText(Copy(S, 3, MaxInt));
    SetLength(Signs, Length(Signs) + 1);
    Signs[High(Signs)] := SG;
  end;
  Result := True;
end;

{ ---- GLEVNW01 ---- }

function NWIndex(C: Char): Integer;
begin
  Result := Pos(C, NWAlphabet) - 1;
end;

function TAdventureLevel.LoadNW(const Data: string): Boolean;
var
  Lines, Tok: TStringList;
  I, J, X, Y, W, A, B: Integer;
  S, T: string;
  L: TLevelLink;
  SG: TLevelSign;
  NP: TLevelNPC;
  BD: TLevelBaddy;
  CH: TLevelChest;
begin
  Result := False;
  Clear;
  Magic := 'GLEVNW01';
  Lines := TStringList.Create;
  Tok := TStringList.Create;
  try
    Lines.Text := Data;
    I := 1;
    while I < Lines.Count do
    begin
      S := Lines[I];
      Tok.Clear;
      ExtractStrings([' '], [], PChar(S), Tok);
      if Tok.Count = 0 then
      begin
        Inc(I);
        Continue;
      end;
      T := Tok[0];
      if (T = 'BOARD') and (Tok.Count = 6) then
      begin
        X := StrToIntDef(Tok[1], -1);
        Y := StrToIntDef(Tok[2], -1);
        W := StrToIntDef(Tok[3], -1);
        if (X >= 0) and (Y >= 0) and (Y < BoardH) and (W > 0) and (X + W <= BoardW) and
          (Length(Tok[5]) >= W * 2) then
          for J := 0 to W - 1 do
          begin
            A := NWIndex(Tok[5][J * 2 + 1]);
            B := NWIndex(Tok[5][J * 2 + 2]);
            if (A >= 0) and (B >= 0) then
              Tiles[X + J + Y * BoardW] := (A shl 6) or B;
          end;
      end
      else if (T = 'LINK') and (Tok.Count >= 8) then
      begin
        L.Dest := Tok[1];
        L.X := StrToIntDef(Tok[2], 0);
        L.Y := StrToIntDef(Tok[3], 0);
        L.W := StrToIntDef(Tok[4], 0);
        L.H := StrToIntDef(Tok[5], 0);
        L.NewX := Tok[6];
        L.NewY := Tok[7];
        SetLength(Links, Length(Links) + 1);
        Links[High(Links)] := L;
      end
      else if (T = 'SIGN') and (Tok.Count >= 3) then
      begin
        SG.X := StrToIntDef(Tok[1], 0);
        SG.Y := StrToIntDef(Tok[2], 0);
        SG.Text := '';
        Inc(I);
        while (I < Lines.Count) and (Lines[I] <> 'SIGNEND') do
        begin
          if SG.Text <> '' then SG.Text := SG.Text + #10;
          SG.Text := SG.Text + Lines[I];
          Inc(I);
        end;
        SetLength(Signs, Length(Signs) + 1);
        Signs[High(Signs)] := SG;
      end
      else if (T = 'NPC') and (Tok.Count >= 4) then
      begin
        NP.Image := Tok[1];
        if NP.Image = '-' then NP.Image := '';
        NP.X := StrToFloatDef(Tok[2], 0);
        NP.Y := StrToFloatDef(Tok[3], 0);
        NP.Script := '';
        Inc(I);
        while (I < Lines.Count) and (Lines[I] <> 'NPCEND') do
        begin
          NP.Script := NP.Script + Lines[I] + #10;
          Inc(I);
        end;
        SetLength(NPCs, Length(NPCs) + 1);
        NPCs[High(NPCs)] := NP;
      end
      else if (T = 'BADDY') and (Tok.Count >= 4) then
      begin
        BD.X := StrToIntDef(Tok[1], 0);
        BD.Y := StrToIntDef(Tok[2], 0);
        BD.Kind := StrToIntDef(Tok[3], 0);
        BD.Verses := '';
        Inc(I);
        while (I < Lines.Count) and (Lines[I] <> 'BADDYEND') do
        begin
          BD.Verses := BD.Verses + Lines[I] + '\';
          Inc(I);
        end;
        SetLength(Baddies, Length(Baddies) + 1);
        Baddies[High(Baddies)] := BD;
      end
      else if (T = 'CHEST') and (Tok.Count >= 5) then
      begin
        CH.X := StrToIntDef(Tok[1], 0);
        CH.Y := StrToIntDef(Tok[2], 0);
        CH.Item := StrToIntDef(Tok[3], -1); { item names resolve in TAdventure }
        CH.Sign := StrToIntDef(Tok[4], 0);
        SetLength(Chests, Length(Chests) + 1);
        Chests[High(Chests)] := CH;
      end;
      Inc(I);
    end;
    Result := True;
  finally
    Tok.Free;
    Lines.Free;
  end;
end;

end.
