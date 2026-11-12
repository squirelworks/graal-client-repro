{ Tests for the 2.05 rev 2 rebuild. No framework: each check prints a line
  and the run exits 1 if any failed.

  Optional: GRAAL205_TUTORIALS = a folder with the 13 tutorial_*.graal
  files and their .json decodes (from graal_analysis
  tools/file-formats/extract_tutorials.py). These are the original game's
  data and are not committed; without the folder those checks are skipped. }
program TestNwb1;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GClamp in '../../common/GClamp.pas',
  GCompat in '../../common/GCompat.pas',
  GPaths in '../../common/GPaths.pas',
  GNumText in '../../common/GNumText.pas',
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GAssetDirs in '../../common/GAssetDirs.pas',
  GAni in '../../common/GAni.pas',
  ProtocolNwb1 in '../src/ProtocolNwb1.pas',
  ClientNwb1 in '../src/ClientNwb1.pas',
  GGs1 in '../../common/GGs1.pas',
  NpcNwb1 in '../src/NpcNwb1.pas',
  BaddyNwb1 in '../src/BaddyNwb1.pas',
  NpcBridgeNwb1 in '../src/NpcBridgeNwb1.pas',
  Adventure in '../src/Adventure.pas',
  GFont in '../../common/GFont.pas',
  GWindow in '../../common/GWindow.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  TestNpcNwb1 in 'TestNpcNwb1.pas',
  TestBaddyNwb1 in 'TestBaddyNwb1.pas';

var
  Passed, Failed, Skipped, NpcSkipped: Integer;

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
    Check(Copy(Line, 1, 10) = ' ' + Chr(98 + 32) + 'G2N15041', 'login line: type 0, key, token G2N15041');
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

{ The 2.05 sprite prop and the other-player prop stream. }
procedure TestSpriteAndOthers;
var
  G: TAdventure;
  P: TServerPlayer;
  R: TGReader;
begin
  Check(WireSprite('idle', 0, DirDown) = DirDown, 'sprite: idle is sprite 0 plus direction');
  Check(WireSprite('walk', 0, DirRight) = DirRight + 4 * 4, 'sprite: walk frame 0 is step 1, sprite 4');
  Check(WireSprite('walk', 4, DirUp) = 4 * 2, 'sprite: walk frame 4 is step 5, sprite 2');
  Check(WireSprite('sword', 6, DirLeft) = DirLeft + 4 * 7, 'sprite: sword wraps mod 5 from step 9');
  Check((WireSprite('swim', 3, DirDown) = DirDown) and (WireSprite('lava', 0, 1) = 1),
    'sprite: swim and lava go out as idle');
  Check(WireSprite('sleep', 0, 0) = 4 * 29, 'sprite: the last table step (sleep, 38)');
  G := TAdventure.Create;
  try
    P := G.FindOther(7, True);
    { nickname "bob", sprite walk frame 2 facing left, x 20, then MAXPOWER,
      which the other-player stream does not take, then y }
    R := TGReader.Create(GChar(PLPROP_NICKNAME) + GString('bob') +
      GChar(PLPROP_SPRITE) + GChar(DirLeft + 4 * 4) + GChar(PLPROP_X) + GChar(40) +
      GChar(PLPROP_MAXPOWER) + GChar(6) + GChar(PLPROP_Y) + GChar(50));
    try
      P.ApplyProps(R, True);
    finally
      R.Free;
    end;
    Check((G.OtherCount = 1) and (P.Nickname = 'bob') and (P.X = 20) and (P.Y = 0),
      'others: the stream stops at an id 2.05 does not accept from other players');
    Check((P.Dir = DirLeft) and (P.AniName = 'walk') and (P.FixedStep = 0),
      'others: the pose comes from the sprite prop');
    R := TGReader.Create(GChar(PLPROP_PCONNECTED));
    try
      P.ApplyProps(R, True);
    finally
      R.Free;
    end;
    Check(P.Gone, 'others: PCONNECTED marks the player gone');
    { NewWorld: prop 10 is the gani by name, and colours are eight bytes }
    R := TGReader.Create(GChar(PLPROP_GANI) + GString('sit') + GChar(PLPROP_COLORS) +
      GChar(1) + GChar(2) + GChar(3) + GChar(4) + GChar(5) + GChar(6) + GChar(7) + GChar(8) +
      GChar(PLPROP_X) + GChar(44));
    try
      Check(P.ApplyProps(R, True) = '10,13,15', 'others: gani by name, eight colours, then x');
    finally
      R.Free;
    end;
    Check((P.AniName = 'sit') and (P.Colors[7] = 8) and (P.X = 22),
      'others: the gani and the eighth colour are kept');
    G.RemoveOther(7);
    Check((G.OtherCount = 0) and (G.FindOther(7, False) = nil), 'others: removed');
    R := TGReader.Create(GChar(PLPROP_X) + GChar(40) + GChar(PLPROP_JOINLEAVELVL) + GChar(1) +
      GChar(PLPROP_Y) + GChar(50));
    try
      G.Player.ApplyProps(R, False);
    finally
      R.Free;
    end;
    Check((G.Player.X = 20) and (G.Player.Y <> 25),
      'self: the own stream stops at ids above 42');
  finally
    G.Free;
  end;
end;

procedure WriteText(const FileName, Text: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Text <> '' then F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

{ Two levels side by side, joined by an edge link. }
procedure TestLinks;
var
  G: TAdventure;
  Dir: string;
  I: Integer;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'gNwb1links' + PathDelim;
  ForceDirectories(Dir);
  WriteText(Dir + 'a.nw', 'GLEVNW01'#10'LINK b.nw 63 0 1 64 0 playery'#10);
  WriteText(Dir + 'b.nw', 'GLEVNW01'#10'LINK a.nw 0 10 1 10 61 12.5'#10);
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    Check(G.LoadLevelFile(Dir + 'a.nw'), 'links: level a loads');
    Check((G.LinkAt(63.5, 20) = 0) and (G.LinkAt(62.9, 20) = -1),
      'links: the link rectangle is a half-open tile box');
    G.Player.X := 59;
    G.Player.Y := 20;
    for I := 1 to 6 do
      if G.Level.Name = 'a.nw' then
      begin
        G.Keys[DirRight] := True;
        G.Tick;
      end;
    if G.Level.Name <> 'b.nw' then
      WriteLn(Format('  at %.2f,%.2f in %s', [G.Player.X, G.Player.Y, G.Level.Name]));
    Check((G.Level.Name = 'b.nw') and (G.Player.X = 0) and (G.Player.Y = 20),
      'links: walking right into the edge link loads b.nw at x 0, keeping y');
    G.Keys[DirRight] := False;
    G.Player.Y := 12;
    Check(G.FollowLink(G.LinkAt(0.5, 14)) and (G.Level.Name = 'a.nw') and
      (G.Player.X = 61) and (G.Player.Y = 12.5), 'links: a decimal arrival');
    G.Level.Links[0].Dest := 'missing.nw';
    Check(not G.FollowLink(0) and (G.Level.Name = 'a.nw'),
      'links: a missing level leaves the player where they are');
  finally
    G.Free;
    DeleteFile(Dir + 'a.nw');
    DeleteFile(Dir + 'b.nw');
    RemoveDir(Dir);
  end;
end;

{ The link point, as measured on the real 2.05 under Wine: walking right
  from y 30.5, a 1x1 link at row 32 warps while rows 31 and 33 are walked
  past; walking down from x 30, column 31 warps and column 32 does not. }
function WalkInto(const Dir, Link: string; X, Y: Double; Key: Integer;
  out PreX, PreY: Double): Boolean; overload;
var
  G: TAdventure;
  I: Integer;
begin
  WriteText(Dir + 'c.nw', 'GLEVNW01'#10'LINK d.nw ' + Link + ' 5 5'#10);
  WriteText(Dir + 'd.nw', 'GLEVNW01'#10);
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    G.LoadLevelFile(Dir + 'c.nw');
    G.Player.X := X;
    G.Player.Y := Y;
    PreX := X;
    PreY := Y;
    for I := 1 to 40 do
      if G.Level.Name = 'c.nw' then
      begin
        PreX := G.Player.X;
        PreY := G.Player.Y;
        G.Keys[Key] := True;
        G.Tick;
      end;
    Result := G.Level.Name = 'd.nw';
  finally
    G.Free;
    DeleteFile(Dir + 'c.nw');
    DeleteFile(Dir + 'd.nw');
  end;
end;

function WalkInto(const Dir, Link: string; X, Y: Double; Key: Integer): Boolean; overload;
var
  PreX, PreY: Double;
begin
  Result := WalkInto(Dir, Link, X, Y, Key, PreX, PreY);
end;

procedure TestLinkPoint;
var
  Dir: string;
  PX, PY: Double;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'gNwb1point' + PathDelim;
  ForceDirectories(Dir);
  try
    Check(WalkInto(Dir, '45 32 1 1', 30, 30.5, DirRight),
      'link point: walking right from y 30.5, the row 32 link warps');
    Check(not WalkInto(Dir, '45 31 1 1', 30, 30.5, DirRight) and
      not WalkInto(Dir, '45 33 1 1', 30, 30.5, DirRight),
      'link point: rows 31 and 33 are walked past');
    Check(WalkInto(Dir, '45 31 1 2', 30, 30.5, DirRight),
      'link point: a link over rows 31-32 warps');
    Check(WalkInto(Dir, '45 32 1 1', 30, 30, DirRight),
      'link point: from y 30.0 row 32 still warps');
    Check(WalkInto(Dir, '31 45 1 1', 30, 30, DirDown) and
      not WalkInto(Dir, '32 45 1 1', 30, 30, DirDown),
      'link point: walking down from x 30, column 31 warps, column 32 not');
    Check(WalkInto(Dir, '32 45 1 1', 30.5, 30, DirDown),
      'link point: from x 30.5 column 32 warps');
    Check(WalkInto(Dir, '20 32 1 1', 30, 30.5, DirLeft) and
      WalkInto(Dir, '31 20 1 1', 30, 30, DirUp),
      'link point: left and up links warp');
    { the point runs 1 to 1.5 tiles ahead of the centre, so the warp comes
      before the centre itself reaches the link }
    Check(WalkInto(Dir, '45 32 1 1', 30, 30.5, DirRight, PX, PY) and (PX + 1.5 < 44),
      'link point: walking right, the link fires ahead of the centre');
    Check(WalkInto(Dir, '31 20 1 1', 30, 30, DirUp, PX, PY) and (PY + 2 >= 22),
      'link point: walking up, the link fires ahead of the centre');
  finally
    RemoveDir(Dir);
  end;
end;

{ ---- fuzzing the receive path ----
  Random and mangled server input must never raise (this program is built
  with range and overflow checks, so a bad index raises here) and must not
  leak (the heap tracer checks at exit). }

const
  FuzzIds: array[0..21] of Integer = (PLO_LEVELLINK, PLO_LEVELCHEST, PLO_LEVELSIGN,
    PLO_LEVELNAME, PLO_OTHERPLPROPS, PLO_PLAYERPROPS, PLO_PLAYERWARP, PLO_WARPFAILED,
    PLO_DISCMESSAGE, PLO_SIGNATURE, PLO_NEWWORLDTIME, PLO_STARTMESSAGE, PLO_BOARDPACKET,
    PLO_SETACTIVELEVEL, PLO_TOALL, PLO_LEVELBOARD, PLO_BOARDMODIFY, PLO_NPCPROPS,
    PLO_BADDYPROPS, PLO_LEVELMODTIME, PLO_FILE, PLO_RAWDATA);

function RandomBytes(N: Integer; Printable: Boolean): string;
var
  I: Integer;
begin
  SetLength(Result, N);
  for I := 1 to N do
    if Printable then Result[I] := Chr(32 + Random(96))
    else Result[I] := Chr(Random(256));
end;

{ A prop stream of real ids with random values, sometimes cut short. }
function RandomProps: string;
var
  I, N: Integer;
begin
  Result := '';
  N := Random(12);
  for I := 1 to N do
  begin
    Result := Result + GChar(Random(56));
    case Random(4) of
      0: Result := Result + GChar(Random(224) - 32);
      1: Result := Result + GString(RandomBytes(Random(12), True));
      2: Result := Result + RandomBytes(Random(6), False);
    else
      Result := Result + Chr(Random(256));
    end;
  end;
  if (Result <> '') and (Random(3) = 0) then
    SetLength(Result, Random(Length(Result)));
end;

function RandomMessage(out Id: Integer): string;
begin
  if Random(5) = 0 then Id := Random(256) else Id := FuzzIds[Random(Length(FuzzIds))];
  case Id of
    PLO_PLAYERPROPS: Result := RandomProps;
    PLO_OTHERPLPROPS: Result := GShort(Random(8)) + RandomProps;
    PLO_BOARDPACKET:
      case Random(3) of
        0: Result := RandomBytes(8192, False);
        1: Result := RandomBytes(Random(9000), False);
      else
        Result := '';
      end;
    PLO_LEVELLINK:
      Result := RandomBytes(Random(10), True) + ' ' + IntToStr(Random(80) - 8) + ' ' +
        IntToStr(Random(80) - 8) + ' ' + IntToStr(Random(70)) + ' ' + IntToStr(Random(70)) +
        ' ' + RandomBytes(Random(5), True) + ' ' + RandomBytes(Random(5), True);
  else
    Result := RandomBytes(Random(48), Random(2) = 0);
  end;
end;

function Frame(const Plain: string): string;
var
  Z: string;
begin
  Z := ZCompress(Plain);
  Result := Chr(Length(Z) shr 8) + Chr(Length(Z) and $FF) + Z;
end;

procedure TestFuzz;
var
  G: TAdventure;
  I, J, Id, Raised: Integer;
  Data, Plain, LastErr: string;
begin
  RandSeed := 205;
  Raised := 0;
  LastErr := '';
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    { with an install, the drawing of fuzzed players (heads, bodies,
      colours, poses) is covered too }
    if GetEnvironmentVariable('GRAALNwb1_DATA') <> '' then
      G.UseInstall(GetEnvironmentVariable('GRAALNwb1_DATA'));
    { messages straight into the dispatcher, with ticks between }
    for I := 1 to 20000 do
    begin
      Data := RandomMessage(Id);
      try
        G.Receive(Id, Data);
        if I mod 50 = 0 then
        begin
          for J := 0 to 3 do G.Keys[J] := Random(2) = 0;
          G.Tick;
        end;
      except
        on E: Exception do
        begin
          Inc(Raised);
          if LastErr = '' then
          begin
            LastErr := Format('id %d, %d bytes: %s: %s', [Id, Length(Data), E.ClassName, E.Message]);
{$IFDEF FPC}
            DumpExceptionBackTrace(Output);
{$ENDIF}
          end;
        end;
      end;
    end;
    if LastErr <> '' then WriteLn('  first: ', LastErr);
    Check(Raised = 0, Format('fuzz: 20000 random messages, %d raised', [Raised]));

    { frames: valid zlib around random messages and RAWDATA headers, and
      raw garbage }
    Raised := 0;
    LastErr := '';
    for I := 1 to 3000 do
    begin
      try
        if Random(4) = 0 then
          G.Client.FeedRaw(RandomBytes(Random(64), False))
        else
        begin
          Plain := '';
          for J := 1 to 1 + Random(6) do
          begin
            Data := RandomMessage(Id);
            if Random(8) = 0 then
              Plain := Plain + Chr(PLO_RAWDATA + 32) + GInt3(Length(Data) + 2) + #10 +
                Chr((Id + 32) and $FF) + Data + #10
            else
              Plain := Plain + Chr((Id + 32) and $FF) + StringReplace(Data, #10, ' ',
                [rfReplaceAll]) + #10;
          end;
          Data := Frame(Plain);
          { sometimes in two pieces, as TCP may deliver it }
          J := Random(Length(Data) + 1);
          G.Client.FeedRaw(Copy(Data, 1, J));
          G.Client.FeedRaw(Copy(Data, J + 1, MaxInt));
        end;
        if I mod 20 = 0 then G.Tick;
      except
        on E: Exception do
        begin
          Inc(Raised);
          if LastErr = '' then
          begin
            LastErr := E.ClassName + ': ' + E.Message;
{$IFDEF FPC}
            DumpExceptionBackTrace(Output);
{$ENDIF}
          end;
        end;
      end;
    end;
    if LastErr <> '' then WriteLn('  first: ', LastErr);
    Check(Raised = 0, Format('fuzz: 3000 random frames, %d raised', [Raised]));
  finally
    G.Free;
  end;
end;

procedure TestReceiveLimits;
var
  G: TAdventure;
  I: Integer;
  Plain: string;
  T0: TDateTime;
begin
  G := TAdventure.Create;
  try
    { a burst of 20000 small messages in one frame is handled in one pass }
    Plain := '';
    for I := 1 to 20000 do Plain := Plain + Chr(PLO_TOALL + 32) + 'x' + #10;
    T0 := Now;
    G.Client.FeedRaw(Frame(Plain));
    Check(G.Handled[PLO_TOALL] = 20000, 'receive: 20000 messages in one frame');
    Check((Now - T0) * 86400 < 2, 'receive: a big burst takes well under 2 s');
    { a message with no end (no LF) longer than the limit; it compresses to
      a few KB, so it fits one frame }
    G.Client.FeedRaw(Frame(StringOfChar('a', InPendingMax + 1)));
    Check(Pos('unfinished', G.Client.LastError) > 0,
      'receive: an unfinished message past the limit drops the link');
    G.Client.LastError := '';
    G.Client.FeedRaw(#0#5'xxxxx');
    Check(Pos('zlib', G.Client.LastError) > 0, 'receive: a bad zlib frame drops the link');
    G.Client.LastError := '';
    G.Client.FeedRaw(Frame(Chr(PLO_TOALL + 32) + 'y' + #10));
    Check(G.Handled[PLO_TOALL] = 20001, 'receive: buffers are clean after a dropped link');
  finally
    G.Free;
  end;
end;

function GS(const S: string): string;
begin
  Result := Chr(Length(S) + 32) + S;
end;

procedure PutFile(const Path, Text: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFilePath(Path));
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(Path);
  finally
    L.Free;
  end;
end;

procedure TestAssetDirs;
var
  Root, Exe: string;
begin
  Root := IncludeTrailingPathDelimiter(GetTempDir) + 'assetdirs-' + IntToStr(Random(1000000)) + PathDelim;
  Exe := Root + 'clients' + PathDelim;
  { graal-assets one folder above the program is not used }
  PutFile(Root + 'graal-assets' + PathDelim + 'common' + PathDelim + 'z.txt', 'above');
  SetAssetRootsFor('', Exe, '2.05r2');
  Check(AssetPath('z.txt') = '', 'assets: nothing is read from above the program folder');
  Root := Exe;
  PutFile(Root + 'graal-assets' + PathDelim + 'common' + PathDelim + 'a.txt', 'common');
  PutFile(Root + 'graal-assets' + PathDelim + 'common' + PathDelim + 'b.txt', 'common');
  PutFile(Root + 'graal-assets' + PathDelim + '2.05r2' + PathDelim + 'b.txt', 'version');
  PutFile(Exe + 'c.txt', 'exe');
  PutFile(Root + 'graal-assets' + PathDelim + 'common' + PathDelim + 'c.txt', 'common');
  SetAssetRootsFor('', Exe, '2.05r2');
  Check(AssetRootCount = 3, 'assets: the program folder, the version folder, common');
  Check(Pos('common', AssetPath('a.txt')) > 0, 'assets: a file only in common is found there');
  Check(Pos('2.05r2', AssetPath('b.txt')) > 0, 'assets: the version folder wins over common');
  Check(AssetPath('c.txt') = Exe + 'c.txt', 'assets: the program folder wins over both');
  Check(AssetPath('nothere.txt') = '', 'assets: a missing file gives no path');
  SetAssetRootsFor('', Root + 'graal-assets', '2.05r2');
  Check(Pos('2.05r2', AssetPath('b.txt')) > 0, 'assets: --data may point at graal-assets itself');
  PutFile(Root + 'graal-assets' + PathDelim + '2.22' + PathDelim + 'd.txt', 'fallback');
  PutFile(Root + 'graal-assets' + PathDelim + '2.22' + PathDelim + 'b.txt', 'fallback');
  SetAssetRootsFor('', Root + 'graal-assets', '2.05r2;2.22');
  Check(AssetRootCount = 3, 'assets: a fallback version adds its folder');
  Check(Pos('2.22', AssetPath('d.txt')) > 0, 'assets: a file only in the fallback version is found');
  Check(Pos('2.05r2', AssetPath('b.txt')) > 0, 'assets: the own version wins over the fallback');
  SetAssetRootsFor('', '', '');
end;

procedure TestStatus;
var
  G: TAdventure;

  function Lit(X, Y, W, H: Integer): Boolean;
  var
    I, J: Integer;
  begin
    Result := False;
    for J := Y to Y + H - 1 do
      for I := X to X + W - 1 do
        if G.Screen.GetPixel(I, J) and $FFFFFF <> 0 then
        begin
          Result := True;
          Exit;
        end;
  end;

begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check((G.Player.MaxPower = 3) and (G.Player.Power = 6) and (G.Player.Bombs = 10) and
      (G.Player.Arrows = 5) and (G.AP = 50), 'status: a new account starts at 3 hearts, 10 bombs, 5 arrows');
    G.Screen.Fill($FF000000);
    G.DrawStatus;
    { Graal-NW.exe's bar (the real client under Wine): POWER/MAX in the
      state.png digits ending at 540 on y 39, over the bear at 532,24 }
    Check(Lit(454, 39, 12, 16) and Lit(532, 24, 33, 41), 'status: 150/150 and the bear');
    Check(not Lit(ScreenW - 198, 60, 90, 40), 'status: no hearts');
    Check(Lit(15, 30, 22, 33) and Lit(75, 30, 22, 33) and Lit(135, 30, 22, 33),
      'status: the A, S and D tags 60 px apart');
    Check(Lit(274, 30, 16, 16) and not Lit(326, 48, 26, 16) and not Lit(374, 48, 26, 16),
      'status: the gralat orb, no bomb or arrow counts');
    G.Screen.Fill($FF000000);
    G.Player.MaxPower := 6;
    G.Player.Power := 3;
    G.DrawStatus;
    Check(Lit(466, 39, 12, 16) and not Lit(440, 39, 26, 16),
      'status: 75/300 stays right-aligned on the bear');
    G.Screen.Fill($FF000000);
    G.ShowStats := 0;
    G.DrawStatus;
    Check(not Lit(0, 0, ScreenW, 120), 'status: showstats 0 hides everything');
  finally
    G.Free;
  end;
end;

procedure TestActions;
var
  G: TAdventure;
  A: TGraalAni;
  OX, OY, I, R0: Integer;
  X, Y, W, H: Integer;
begin
  { the sprite table packing, against two rectangles the HUD notes give }
  G := TAdventure.Create;
  try
    G.Arrays.Lists[24].Free;
    G.Arrays.Lists[24] := TGArray.Create;
    SetLength(G.Arrays.Lists[24].Values, 2);
    G.Arrays.Lists[24].Values[0] := Integer($0E06A390);
    G.Arrays.Lists[24].Values[1] := Integer($2F01238E);
    Check(G.Arrays.SpriteRect(0, X, Y, W, H) and (X = 28) and (Y = 212) and (W = 28) and (H = 32),
      'sprites: table entry 145 is (28, 212, 28, 32)');
    Check(G.Arrays.SpriteRect(1, X, Y, W, H) and (X = 94) and (Y = 36) and (W = 28) and (H = 28),
      'sprites: table entry 17 is (94, 36, 28, 28)');
  finally
    G.Free;
  end;
  { PARAM placements keep their row (the carry ganis have one per row) }
  A := TGraalAni.Create;
  try
    Check(A.LoadFromString('SPRITE 1 BODY 0 0 36 36 b'#10'DEFAULTPARAM1 20'#10'ANI'#10 +
      ' 1 0 0, PARAM1 8 -18'#10' 1 0 0'#10' 1 0 0'#10' 1 0 0, PARAM1 8 -18'#10'ANIEND'#10) and
      (Length(A.Steps) = 1) and (Length(A.Steps[0].Dirs[3]) = 2) and
      (A.Steps[0].Dirs[3][1].Sprite = ParamSprite - 1) and (A.DefaultParam[1] = '20'),
      'gani: a PARAM1 placement is read, not dropped');
  finally
    A.Free;
  end;
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'actions: the built-in level loads');
    { the sword cuts the bush below: built-in bush 36, 26 }
    G.Player.X := 35;
    G.Player.Y := 22;
    G.Player.Dir := DirDown;
    Check(G.MatchObject(9, 99, 36.5, 26, OX, OY) = 0, 'actions: the bush matches the cut table');
    G.Attack;
    Check((G.Mode <> ModeSword) and (G.Level.Tile(36, 26) <> G.Arrays.ObjectTile(10, 0, 0, 0)),
      'actions: no built-in sword: S swings nothing');
    G.Mode := ModeFree;
    { the pot lifts with glove 1, the stone needs glove 2 }
    G.Player.X := 24.5;
    G.Player.Y := 32;
    G.Action;
    Check((G.Mode = ModeLift) and (G.CarryKind = 2) and
      (G.Level.Tile(26, 36) = G.Arrays.ObjectTile(12, 2, 0, 0)), 'actions: A lifts the pot');
    for I := 1 to 10 do G.Tick;
    Check(G.Mode = ModeCarry, 'actions: the lift ends in carrying');
    G.AttackKey := True;
    G.Tick;
    Check((G.Mode = ModeFree) and (G.CarryKind = -1) and (Length(G.Thrown) = 1),
      'actions: S throws what is carried');
    for I := 1 to 10 do G.Tick;
    Check(Length(G.Thrown) = 0, 'actions: the thrown pot lands');
    G.Player.X := 34.5;
    G.Player.Y := 33;
    G.Action;
    Check(G.Mode = ModeFree, 'actions: glove 1 does not lift a stone');
    G.Player.GlovePower := 2;
    G.Action;
    Check((G.Mode = ModeLift) and (G.CarryKind = 3), 'actions: glove 2 lifts it');
    G.Mode := ModeFree;
    G.CarryKind := -1;
    { the chest gives its red rupee once }
    G.Player.X := 25;
    G.Player.Y := 27;
    G.Player.Dir := DirUp;
    R0 := G.Player.Rupees;
    G.Action;
    Check((G.Player.Rupees = R0 + 30) and G.Level.Chests[0].Opened, 'actions: the chest gives 30 rupees');
    G.Action;
    Check(G.Player.Rupees = R0 + 30, 'actions: an open chest gives nothing more');
    { floor items: taken after the first four ticks, offline given at once }
    SetLength(G.Items, 0);
    G.AddItem(G.Player.X + 0.5, G.Player.Y + 1, 5, ItemLife);
    G.Player.Power := 2;
    G.Tick;
    Check(Length(G.Items) = 1, 'items: not taken in the first ticks');
    for I := 1 to 4 do G.Tick;
    Check((Length(G.Items) = 0) and (G.Player.Power = 4), 'items: a heart is taken and gives a heart');
    G.AddItem(10, 10, 0, ItemLife);
    for I := 1 to ItemLife do G.Tick;
    Check(Length(G.Items) = 1, 'items: still there at life 0');
    G.Tick;
    Check(Length(G.Items) = 0, 'items: gone when the life runs out');
    { from the server }
    G.Receive(PLO_ITEMADD, GChar(20) + GChar(20) + GChar(3));
    G.Receive(PLO_ITEMADD, GChar(22) + GChar(20) + GChar(6));
    Check((Length(G.Items) = 1) and (G.Items[0].X = 10) and (G.Items[0].Item = 3),
      'items: ITEMADD makes floor items only');
    G.Receive(PLO_ITEMDEL, GChar(20) + GChar(20));
    Check(Length(G.Items) = 0, 'items: ITEMDEL removes it');
    G.Receive(PLO_BOARDMODIFY, GChar(5) + GChar(6) + GChar(2) + GChar(1) + GShort(100) + GShort(101));
    Check((G.Level.Tile(5, 6) = 100) and (G.Level.Tile(6, 6) = 101), 'board: BOARDMODIFY writes its tiles');
  finally
    G.Free;
  end;
end;

procedure TestCombat;
var
  G: TAdventure;
  P: TServerPlayer;
  I, T0: Integer;
  X0, Y0: Double;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'combat: the built-in level loads');
    G.Tick;
    G.Player.X := 30;
    G.Player.Y := 30;
    { a hit clamps CURPOWER to the maximum first, then takes half hearts }
    G.Player.MaxPower := 3;
    G.Player.Power := 9;
    X0 := G.Player.X;
    G.HurtPlayer(1, 1, 0);
    Check(G.Player.Power = 4, 'combat: power is clamped to the maximum before the hit');
    Check(not G.Hurtable, 'combat: hurt mode after a hit');
    G.HurtPlayer(1, 1, 0);
    Check(G.Player.Power = 4, 'combat: no second hit in hurt mode');
    for I := 1 to 5 do G.Tick;
    Check(Abs(G.Player.X - (X0 + 5)) < 0.01, 'combat: five ticks of knockback, a tile each');
    for I := 1 to 10 do G.Tick;
    Check(Abs(G.Player.X - (X0 + 5)) < 0.01, 'combat: no knockback after the fifth tick');
    for I := 1 to 25 do G.Tick;
    Check(G.Hurtable, 'combat: hurt mode ends after 40 ticks');
    { death, then a direction key respawns at the entry point }
    G.AP := 10;
    G.HurtPlayer(2, 0, 1);
    Check((G.Mode = ModeDead) and (G.Player.Power = 0), 'combat: no hearts left is death');
    G.Player.MaxPower := 5;
    G.Respawn;
    Check((G.Mode = ModeFree) and (G.Player.Power = 6), 'combat: AP under 20 respawns with three hearts');
    G.AP := 30;
    G.Mode := ModeDead;
    G.Respawn;
    Check(G.Player.Power = 10, 'combat: AP under 40 respawns with five hearts');
    G.AP := 50;
    G.Respawn;
    Check(G.Player.Power = 10, 'combat: else all hearts (5)');
    { PLO_HURTPLAYER: known attackers within 10 tiles, players only }
    G.Player.X := 30;
    G.Player.Y := 30;
    P := G.FindOther(7, True);
    P.X := 33;
    P.Y := 30;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(5) +
      GChar(0) + GChar(0) + GChar(0));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER with the NPC field is refused');
    G.Receive(PLO_HURTPLAYER, GShort(8) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(2));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER from an unknown player is refused');
    P.X := 41;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(2));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER from over 10 tiles is refused');
    P.X := 33;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(5));
    Check(G.Player.Power = 8, 'combat: HURTPLAYER power is capped at two half hearts');
    for I := 1 to 40 do G.Tick;
    { another player's swing: facing the player, two tiles off }
    G.Player.X := 30;
    G.Player.Y := 30;
    P.X := 28;
    P.Y := 30;
    P.Dir := DirRight;
    P.SwordPower := 2;
    P.Sprite := 6 * 4 + DirRight;
    G.Tick;
    Check(G.Player.Power = 6, 'combat: a swing from another player takes SwordPower / 2 hearts');
    P.Sprite := 0;
    for I := 1 to 40 do G.Tick;
    P.Dir := DirLeft;
    P.Sprite := 6 * 4 + DirLeft;
    G.Tick;
    Check(G.Player.Power = 6, 'combat: a swing facing away misses');
    G.RemoveOther(7);
    { a bomb: laid ahead, goes off after 60 ticks, cuts the bush and hurts }
    G.Player.X := 35;
    G.Player.Y := 22;
    G.Player.Dir := DirDown;
    G.Player.Bombs := 3;
    G.WeaponsOn := True;
    G.LayBomb;
    Check((Length(G.Bombs) = 1) and (G.Player.Bombs = 2), 'bombs: D lays a bomb');
    T0 := G.Player.Power;
    G.Bombs[0].X := 36;
    G.Bombs[0].Y := 24;
    G.Player.Y := 23;
    for I := 1 to 59 do G.Tick;
    Check((Length(G.Bombs) = 1) and (Length(G.Blasts) = 0), 'bombs: the fuse is 60 ticks');
    G.Tick;
    Check((Length(G.Bombs) = 0) and (Length(G.Blasts) = 1), 'bombs: then it explodes');
    Check(G.Level.Tile(36, 26) = G.Arrays.ObjectTile(10, 0, 0, 0), 'bombs: the blast destroys the bush');
    Check(G.Player.Power = T0 - 1, 'bombs: the blast hurts the player half a heart');
    for I := 1 to 12 do G.Tick;
    Check(Length(G.Blasts) = 0, 'bombs: the blast is gone after 11 ticks');
  finally
    G.Free;
  end;
end;

procedure TestSigns;
var
  G: TAdventure;
  I: Integer;

  procedure Press(D: Integer);
  begin
    G.Keys[D] := True;
    G.Tick;
    G.Keys[D] := False;
    G.Tick;
  end;

begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw') and (G.SignAt(24.5, 27.5) = 0) and (G.SignAt(22, 27) = -1),
      'signs: the sign covers its 2 x 2');
    G.Player.X := 23;
    G.Player.Y := 30;
    G.Player.Dir := DirUp;
    for I := 1 to 30 do
    begin
      G.Keys[DirUp] := True;
      G.Tick;
      if G.Reading then Break;
    end;
    Check(G.Reading and (Length(G.SignLines) = 7) and (G.SignLine = 0), 'signs: walking up into a sign reads it');
    G.Keys[DirUp] := True;
    G.Tick;
    Check(G.SignLine = 0, 'signs: the key that opened it does nothing while held');
    G.Keys[DirUp] := False;
    G.Tick;
    Press(DirRight);
    Check(G.SignLine = 3, 'signs: another key turns the page');
    G.AttackKey := True;
    G.Tick;
    Check((G.SignLine = 6) and (G.Mode = ModeFree), 'signs: S turns the page, no swing');
    G.Tick;
    Press(DirUp);
    Check(G.SignLine = 3, 'signs: Up turns back');
    Press(DirDown);
    Check(G.Reading and (G.SignLine = 6), 'signs: the last page');
    Press(DirDown);
    Check(not G.Reading, 'signs: a key on a page that is not full ends reading');
    G.ReadSign('a'#10'b'#10'c');
    G.Tick;
    Press(DirLeft);
    Check(G.Reading and (G.SignLine = 3), 'signs: three lines show an empty second page');
    Press(DirLeft);
    Check(not G.Reading, 'signs: then close');
  finally
    G.Free;
  end;
end;

procedure TestWeapons;
var
  G: TAdventure;
  I, A0, P0: Integer;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'weapons: the built-in level loads');
    G.Tick;
    Check((Length(G.Weapons) = 1) and (G.Weapons[0].Name = 'Bomb') and (G.Selected = 0),
      'weapons: offline the list starts with the bomb');
    G.GiveItem(7);
    Check((Length(G.Weapons) = 2) and (G.Weapons[1].Name = 'Bow') and
      (G.Weapons[1].Image = 'wbowi1.gif') and (G.Selected = 1), 'weapons: the bow is added and selected');
    G.GiveItem(7);
    Check(Length(G.Weapons) = 2, 'weapons: a name already listed is not added again');
    G.AddWeapon('-hidden', '', -1);
    G.SelectWeapon(2);
    Check(G.Selected = 0, 'weapons: selecting skips names starting with -');
    G.RemoveWeapon('-hidden');
    G.Selected := 1;
    G.RemoveWeapon('Bow');
    Check(G.Selected = 0, 'weapons: deleting the last entry selects the new last');
    G.GiveItem(7);
    { the bow: an arrow flies a tile a tick and stops at a wall }
    G.Player.X := 20;
    G.Player.Y := 30;
    G.Player.Dir := DirRight;
    A0 := G.Player.Arrows;
    G.ItemKey := True;
    G.Tick;
    Check((Length(G.Shots) = 1) and (G.Player.Arrows = A0 - 1) and G.Shots[0].Mine,
      'weapons: D with the bow shoots an arrow');
    Check(G.Shots[0].Sprite = 110, 'weapons: the arrow sprite is 107 + direction');
    for I := 1 to 80 do G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: the arrow is gone at the edge or a wall');
    G.Player.Arrows := 0;
    G.ItemKey := True;
    G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: no arrows, no shot');
    { another player's arrow hurts half a heart; a shield facing it stops it }
    P0 := G.Player.Power;
    G.Receive(PLO_ARROWADD, GShort(9) + GChar(Round((G.Player.X - 3) * 2)) +
      GChar(Round((G.Player.Y + 1.5) * 2)) + GChar(DirRight) + GChar(110) + GChar(1));
    Check((Length(G.Shots) = 1) and not G.Shots[0].Mine, 'weapons: ARROWADD makes a shot');
    for I := 1 to 6 do G.Tick;
    Check(G.Player.Power = P0 - 1, 'weapons: an arrow takes half a heart');
    for I := 1 to 40 do G.Tick;
    G.Player.Dir := DirLeft;
    G.Player.ShieldPower := 1;
    P0 := G.Player.Power;
    G.Receive(PLO_ARROWADD, GShort(9) + GChar(Round((G.Player.X - 3) * 2)) +
      GChar(Round((G.Player.Y + 1.5) * 2)) + GChar(DirRight) + GChar(110) + GChar(1));
    for I := 1 to 6 do G.Tick;
    Check(G.Player.Power = P0, 'weapons: a shield facing the arrow stops it');
    for I := 1 to 6 do G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: a power-1 shield knocks it back for three ticks');
    { the server's list }
    I := Length(G.Weapons);
    G.Receive(PLO_DEFAULTWEAPON, GChar(20));
    Check(Length(G.Weapons) = I, 'weapons: no built-in weapons: DEFAULTWEAPON adds none');
    G.Receive(PLO_NPCWEAPONADD, GS('Lantern') + 'xx');
    Check(G.Weapons[High(G.Weapons)].Name = 'Lantern', 'weapons: NPCWEAPONADD adds by name');
    G.Receive(PLO_NPCWEAPONDEL, 'Lantern');
    Check(Length(G.Weapons) = I, 'weapons: NPCWEAPONDEL removes it');
    { the item list: Q opens it, arrows move the selection, other keys close }
    G.Selected := 0;
    A0 := Round(G.Player.X * 2);
    G.ItemListKey := True;
    G.Tick;
    Check(G.ItemListOpen, 'item list: Q opens it');
    G.Tick;
    G.Keys[DirRight] := True;
    G.Tick;
    G.Keys[DirRight] := False;
    Check(G.Selected = 1, 'item list: Right takes the next cell');
    Check(Round(G.Player.X * 2) = A0, 'item list: the player does not walk');
    G.Tick;
    G.AttackKey := True;
    G.Tick;
    Check(not G.ItemListOpen and (G.Mode = ModeFree), 'item list: another game key closes it');
  finally
    G.Free;
  end;
end;

procedure TestServerList;
var
  L: TListServers;
  Data: string;
begin
  Data := Chr(2 + 32) +
    Chr(8 + 32) + GS('P Seihai') + GS('English') + GS('a test') + GS('http://x') +
      GS('2.05') + GS('7') + GS('10.0.0.1') + GS('14802') +
    Chr(8 + 32) + GS('Other') + GS('German') + GS('') + GS('') +
      GS('2.05') + GS('0') + GS('10.0.0.2') + GS('nope');
  L := ParseServerList(Data);
  Check(Length(L) = 2, 'server list: two entries');
  Check((L[0].Host = '10.0.0.1') and (L[0].Port = 14802) and (L[0].Players = '7'),
    'server list: host, port and players');
  Check((L[1].Language = 'German') and (L[1].Port = 0), 'server list: a bad port reads as 0');
  L := ParseServerList(Chr(3 + 32) + Chr(8 + 32) + GS('cut'));
  Check(Length(L) = 0, 'server list: a cut entry is dropped');
  Check(Length(ParseServerList('')) = 0, 'server list: empty reply');
  Check((ServerDisplayName('P Seihai') = 'Seihai') and (ServerDisplayName('Plain') = 'Plain'),
    'server list: the type letter is taken off the name');
end;

procedure TestBuiltins;
var
  D: string;
  G: TAdventure;
begin
  Check(BuiltinFile('pics1.png', D) and (Copy(D, 2, 3) = 'PNG'), 'built-in: pics1.png');
  Check(BuiltinFile('PICS1.GIF', D), 'built-in: any image extension and case');
  Check(BuiltinFile('arrays.dat', D) and BuiltinFile('start.nw', D), 'built-in: arrays and a level');
  Check(not BuiltinFile('nothere.png', D), 'built-in: unknown names are not found');
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.SheetBuiltin and (G.Sheet <> nil) and (G.Sheet.Width > 0), 'built-in: the default tile sheet');
    Check(G.LoadLevelFile('start.nw') and (Length(G.Level.Links) > 0),
      'built-in: start.nw loads with no install and has a link');
    Check(G.Assets.Ani('idle') <> nil, 'built-in: idle gani');
    Check(G.Assets.Image('body.png', 'bodies') <> nil, 'built-in: body image');
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
  TestSpriteAndOthers;
  TestLinks;
  TestLinkPoint;
  TestFuzz;
  TestReceiveLimits;
  TestTutorials;
  TestServerList;
  TestAssetDirs;
  TestBuiltins;
  TestStatus;
  TestActions;
  RunNpcTests(Check, NpcSkipped);
  Inc(Skipped, NpcSkipped);
  RunBaddyTests(Check);
  TestCombat;
  TestSigns;
  TestWeapons;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
