{ Tests for the 2.05 rev 2 rebuild. No framework: each check prints a line
  and the run exits 1 if any failed.

  Optional: GRAAL205_TUTORIALS = a folder with the 13 tutorial_*.graal
  files and their .json decodes (from graal_analysis
  tools/file-formats/extract_tutorials.py). These are the original game's
  data and are not committed; without the folder those checks are skipped. }
program Test205;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GAni in '../../common/GAni.pas',
  Protocol205 in '../src/Protocol205.pas',
  GraalClient in '../src/GraalClient.pas',
  Adventure in '../src/Adventure.pas';

var
  Passed, Failed, Skipped: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

procedure TestGTypes;
var
  R: TGReader;
  S: string;
begin
  Check(GChar(0) = ' ', 'GCHAR 0 is a space');
  Check(GChar(37) = 'E', 'GCHAR 37 (PLI_LANGUAGE) is E');
  S := GShort(28671) + GInt3(3670015) + GInt3(8194) + GInt5($DEADBEEF) + GString('walk');
  R := TGReader.Create(S);
  try
    Check(R.ReadGShort = 28671, 'GSHORT max (223*128+127) round trip');
    Check(R.ReadGInt3 = 3670015, 'GINT3 max round trip');
    Check(R.ReadGInt3 = 8194, 'GINT3 8194 round trip');
    Check(R.ReadGInt5 = $DEADBEEF, 'GINT5 32-bit round trip');
    Check(R.ReadGString = 'walk', 'GSTRING round trip');
    Check(R.Eof and not R.Overrun, 'reader ends cleanly');
    R.ReadGChar;
    Check(R.Overrun, 'reading past the end flags overrun');
  finally
    R.Free;
  end;
  { the raw-data header from a real 2.05 session: ' `"' = 8194 }
  R := TGReader.Create(' `"');
  try
    Check(R.ReadGInt3 = 8194, 'RAWDATA header from capture = 8194 (id + 8192 + LF)');
  finally
    R.Free;
  end;
end;

{ A real 2.05 rev 2 session against a lab GServer (graal_analysis lab run 2,
  key 98): the junk byte of each message after the login line sat at these
  0-based indexes. }
procedure TestGen3Capture;
const
  Ids: array[0..6] of Integer = (37, 34, 34, 23, 23, 23, 34);
  Junk: array[0..6] of Integer = (2, 5, 8, 0, 2, 4, 13);
var
  Payloads: array[0..6] of string;
  It, It2: Cardinal;
  I: Integer;
  Msg, Enc, Back: string;
  AllPos, AllRoundTrip: Boolean;
begin
  Payloads[0] := 'English';
  Payloads[1] := '&v'#$83'jTsword1.png';
  Payloads[2] := '&v'#$83'jTshield1.png';
  Payloads[3] := '+.gani';
  Payloads[4] := 'wbomb1';
  Payloads[5] := 'wbowi1';
  Payloads[6] := '&v'#$83'jTwbomb1.png';
  It := Gen3Seed;
  It2 := Gen3Seed;
  AllPos := True;
  AllRoundTrip := True;
  for I := 0 to 6 do
  begin
    Msg := GChar(Ids[I]) + Payloads[I] + #10;
    Enc := Gen3Insert(It, 98, Msg);
    { removing the byte at the captured index must give the message back }
    if Copy(Enc, 1, Junk[I]) + Copy(Enc, Junk[I] + 2, MaxInt) <> Msg then
      AllPos := False;
    Back := Gen3Remove(It2, 98, Copy(Enc, 1, Length(Enc) - 1));
    if Back + #10 <> Msg then AllRoundTrip := False;
  end;
  Check(AllPos, 'gen-3 junk positions match a real 2.05 capture (7 messages)');
  Check(AllRoundTrip, 'gen-3 server-side removal restores every message');
  Check(It = It2, 'client and server iterators stay in step');
end;

procedure TestLoginLine;
var
  C: TAdventureClient;
  Line: string;
begin
  C := TAdventureClient.Create;
  try
    C.Key := 98;
    Line := GChar(ClientType) + GChar(C.Key) + ClientVersionToken + GString('acc') + GString('pw');
    Check(Copy(Line, 1, 10) = ' ' + Chr(98 + 32) + 'GNW03081', 'login line: type 0, key, token GNW03081');
    Check(Pos(#10, Line) = 0, 'login line holds no LF');
  finally
    C.Free;
  end;
end;

procedure TestZlib;
var
  Z, P: string;
begin
  Z := ZCompress('hello hello hello'#10);
  Check(ZDecompress(Z, P) and (P = 'hello hello hello'#10), 'zlib round trip');
  Check(not ZDecompress('not zlib', P), 'bad zlib is rejected');
end;

procedure TestBoardWriter;
var
  L: TAdventureLevel;
  T: TBoardTiles;
  I: Integer;
  Same: Boolean;
begin
  for I := 0 to BoardSize - 1 do
    case (I div 64) mod 4 of
      0: T[I] := 2047;                      { long single runs }
      1: T[I] := I mod 2 * 5 + 100;         { AB AB double runs }
      2: T[I] := (I * 37) mod 4096;         { no runs }
      3: T[I] := (I div 3) mod 7;           { short runs }
    end;
  L := TAdventureLevel.Create;
  try
    Check(L.LoadGRV('GR-V1.03' + WriteBoard13(T) + '#'#10#$FF#$FF#$FF#10'#'#10'#'#10),
      'GR-V1.03 written by the 2.05 rules parses');
    Same := True;
    for I := 0 to BoardSize - 1 do
      if L.Tiles[I] <> T[I] then Same := False;
    Check(Same, 'GR-V1.03 board round trip (single, double and no runs)');
  finally
    L.Free;
  end;
end;

procedure TestNW;
var
  L: TAdventureLevel;
begin
  L := TAdventureLevel.Create;
  try
    Check(L.LoadFromString('GLEVNW01'#10'BOARD 0 5 3 0 AAAB//'#10 +
      'LINK next.nw 0 0 1 64 62 playery'#10'SIGN 3 4'#10'Hello'#10'SIGNEND'#10),
      'GLEVNW01 parses');
    Check((L.Tile(0, 5) = 0) and (L.Tile(1, 5) = 1) and (L.Tile(2, 5) = 4095),
      'GLEVNW01 BOARD run: AA=0, AB=1, //=4095');
    Check((Length(L.Links) = 1) and (L.Links[0].Dest = 'next.nw') and
      (L.Links[0].NewY = 'playery'), 'GLEVNW01 LINK');
    Check((Length(L.Signs) = 1) and (L.Signs[0].Text = 'Hello'), 'GLEVNW01 SIGN');
    Check(not L.LoadFromString('GR-V1.04xxxx'), 'GR-V1.04 is not accepted by 2.05');
  finally
    L.Free;
  end;
end;

procedure TestTileSheet;
var
  X, Y: Integer;
begin
  TileSheetPos(0, X, Y);
  Check((X = 0) and (Y = 0), 'tile 0 at (0,0)');
  TileSheetPos(17, X, Y);
  Check((X = 16) and (Y = 16), 'tile 17 at (16,16)');
  TileSheetPos(512, X, Y);
  Check((X = 256) and (Y = 0), 'tile 512 starts the second 16-wide block');
  TileSheetPos(4095, X, Y);
  Check((X = 2032) and (Y = 496), 'tile 4095 at the bottom right of a 2048x512 sheet');
end;

function ReadFileStr(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ The "tiles" array from extract_tutorials.py --json. }
function JsonTiles(const Json: string; out T: TBoardTiles): Boolean;
var
  P, N, V: Integer;
begin
  Result := False;
  P := Pos('"tiles"', Json);
  if P = 0 then Exit;
  while (P <= Length(Json)) and (Json[P] <> '[') do Inc(P);
  Inc(P);
  N := 0;
  V := -1;
  while (P <= Length(Json)) and (Json[P] <> ']') and (N < BoardSize) do
  begin
    if Json[P] in ['0'..'9'] then
    begin
      if V < 0 then V := 0;
      V := V * 10 + Ord(Json[P]) - 48;
    end
    else if V >= 0 then
    begin
      T[N] := V;
      Inc(N);
      V := -1;
    end;
    Inc(P);
  end;
  if (V >= 0) and (N < BoardSize) then
  begin
    T[N] := V;
    Inc(N);
  end;
  Result := N = BoardSize;
end;

procedure TestTutorials;
var
  Dir, Data, Board: string;
  SR: TSearchRec;
  L: TAdventureLevel;
  T: TBoardTiles;
  I, Count, Bad, Reencoded: Integer;
begin
  Dir := GetEnvironmentVariable('GRAAL205_TUTORIALS');
  if (Dir = '') or not DirectoryExists(Dir) then
  begin
    Inc(Skipped);
    WriteLn('skip  tutorial levels (set GRAAL205_TUTORIALS)');
    Exit;
  end;
  Count := 0;
  Bad := 0;
  Reencoded := 0;
  L := TAdventureLevel.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.graal', faAnyFile, SR) = 0 then
    begin
      repeat
        Inc(Count);
        Data := ReadFileStr(IncludeTrailingPathDelimiter(Dir) + SR.Name);
        if not L.LoadFromString(Data) or
          not JsonTiles(ReadFileStr(IncludeTrailingPathDelimiter(Dir) +
            ChangeFileExt(SR.Name, '.json')), T) then
        begin
          Inc(Bad);
          Continue;
        end;
        for I := 0 to BoardSize - 1 do
          if L.Tiles[I] <> T[I] then
          begin
            Inc(Bad);
            Break;
          end;
        Board := WriteBoard13(L.Tiles);
        if Copy(Data, 9, Length(Board)) = Board then Inc(Reencoded);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  finally
    L.Free;
  end;
  Check((Count = 13) and (Bad = 0), Format('13 embedded tutorial levels decode (%d files, %d bad)', [Count, Bad]));
  Check(Reencoded = Count, Format('tutorial boards re-encode byte for byte (%d of %d)', [Reencoded, Count]));
end;


function BE(V: Integer): string;
begin
  Result := Chr((V shr 24) and $FF) + Chr((V shr 16) and $FF) + Chr((V shr 8) and $FF) + Chr(V and $FF);
end;

{ arrays.dat with array 0 = the given passable tiles, array 1 = (), then
  23 empty arrays; array 2 nested to check kind 1. }
function MakeArrays(const Free: array of Integer): string;
var
  I: Integer;
begin
  Result := BE(Length(Free));
  for I := 0 to High(Free) do Result := Result + BE(Free[I]);
  Result := Result + BE(0);
  Result := Result + BE((1 shl 16) or 2) + BE(1) + BE(7) + BE(0);
  for I := 3 to 24 do Result := Result + BE(0);
end;

procedure TestArrays;
var
  A: TGArrays;
begin
  A := TGArrays.Create;
  try
    Check(A.LoadFromString(MakeArrays([0, 5, 4095])), 'arrays.dat: 25 arrays parse');
    Check(A.TilePassable(5) and A.TilePassable(4095) and not A.TilePassable(6),
      'arrays.dat: tiles in array 0 are passable, others block');
    Check((Length(A.Lists[2].Items) = 2) and (A.Lists[2].Items[0].Values[0] = 7),
      'arrays.dat: nested array (kind 1)');
    Check(not A.LoadFromString(BE(3) + BE(1)), 'arrays.dat: short file is rejected');
  finally
    A.Free;
  end;
end;

procedure TestGani;
var
  A: TGraalAni;
  S: TGraalAniSprite;
begin
  A := TGraalAni.Create;
  try
    Check(A.LoadFromString(
      'GANI0001'#10 +
      'SPRITE 1 BODY 0 0 32 32 test body'#10 +
      'SPRITE 2 HEAD 0 64 32 32 test head'#10 +
      'loop'#10'DEFAULTATTR1 hat1.png'#10#10 +
      'ANI'#10 +
      '  1 8 16,  2 8 2'#10'  1 8 16'#10'  1 8 16, 2 8 0'#10'  1 8 16'#10 +
      'WAIT 2'#10#10 +
      '  2 0 0'#10'  2 0 0'#10'  2 0 0'#10'  2 0 0'#10 +
      'PLAYSOUND step.wav 1 2'#10 +
      'ANIEND'#10), 'gani: sprite mode parses');
    Check((Length(A.Steps) = 2) and A.Loop and (A.DefaultAttr[1] = 'hat1.png'),
      'gani: two steps, LOOP, DEFAULTATTR1');
    Check((Length(A.Steps[0].Dirs[0]) = 2) and (A.Steps[0].Dirs[2][1].Y = 0) and
      (A.Steps[0].Ticks = 3) and (A.Steps[1].Sound = 'step.wav'),
      'gani: placements per direction, WAIT and PLAYSOUND go to their step');
    Check(A.FindSprite(2, S) and (S.Sheet = 'HEAD') and (S.Y = 64), 'gani: sprite lookup');
    Check((A.StepAt(0) = 0) and (A.StepAt(2) = 0) and (A.StepAt(3) = 1) and (A.StepAt(4) = 0),
      'gani: step timing and looping');
  finally
    A.Free;
  end;
end;

{ A walled 64x64 level: tile 1 blocks, tile 0 is free. }
procedure TestWalking;
var
  G: TAdventure;
  I: Integer;
begin
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    for I := 0 to BoardSize - 1 do G.Level.Tiles[I] := 0;
    for I := 0 to 63 do G.Level.Tiles[I + 20 * 64] := 1; { a wall along y = 20 }
    G.Player.X := 9.5;
    G.Player.Y := 10;
    G.WalkStep(DirRight);
    Check((G.Player.X = 10) and (G.Player.Y = 10) and (G.Player.Dir = DirRight),
      'walk: a free step moves half a tile and sets the facing');
    for I := 1 to 40 do G.WalkStep(DirDown);
    Check(G.Player.Y = 17,
      'walk: walking down stops with the body (y + 3) on the wall''s tile line');
    for I := 1 to 10 do G.WalkStep(DirUp);
    Check(G.Player.Y = 12, 'walk: walking away is free');
    { a one-tile pillar at (30, 5) under the left edge of the body: only
      probe 0 is blocked, so the step is refused and nudged +0.1 }
    G.Level.Tiles[30 + 5 * 64] := 1;
    G.Player.X := 30;
    G.Player.Y := 5;
    G.WalkStep(DirUp);
    Check((G.Player.Y = 5) and (Abs(G.Player.X - 30.1) < 1e-9),
      'walk: a refused step nudges 0.1 round a corner');
  finally
    G.Free;
  end;
end;

begin
  TestGTypes;
  TestGen3Capture;
  TestLoginLine;
  TestZlib;
  TestBoardWriter;
  TestNW;
  TestTileSheet;
  TestArrays;
  TestGani;
  TestWalking;
  TestTutorials;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
