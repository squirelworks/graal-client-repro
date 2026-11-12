{ Test39ster: the 39ster profile with generated fixtures only.

  No file of the original install is read: every level, category table and
  tile sheet here is made by the test. Covers the slices of #176 so far:
  the profile and player-supplied loading, 64 x 64 NW boards, the sheet
  mapping across 512-id blocks, category-index interpretation, camera
  clamping and centring, and movement and collision against generated,
  asymmetric walls. }
program Test39ster;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  SysUtils, Classes, GLevel, GSurface, GAssetDirs,
  Profile39 in '../src/Profile39.pas',
  Tiles39 in '../src/Tiles39.pas',
  Camera39 in '../src/Camera39.pas',
  Move39 in '../src/Move39.pas',
  Anim39 in '../src/Anim39.pas',
  World39 in '../src/World39.pas';

var
  Passed, Failed: Integer;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
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

const
  B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function Pair(Id: Integer): string;
begin
  Result := B64[Id div 64 + 1] + B64[Id mod 64 + 1];
end;

{ A GLEVNW01 level whose tile at (x, y) is Fn(x, y), all 64 rows. }
function MakeNw(Seed: Integer): string;
var
  X, Y: Integer;
  Row: string;
begin
  Result := 'GLEVNW01'#10;
  for Y := 0 to 63 do
  begin
    Row := '';
    for X := 0 to 63 do Row := Row + Pair((X * 64 + Y + Seed) mod 4096);
    Result := Result + Format('BOARD 0 %d 64 0 ', [Y]) + Row + #10;
  end;
end;

{ A category table: every cell ground, with the listed cells changed. }
function MakeCategories(const Cells: array of Integer; const Cats: array of Char): string;
var
  I: Integer;
begin
  Result := StringOfChar('A', SheetCells);
  for I := 0 to High(Cells) do Result[Cells[I] + 1] := Cats[I];
end;

procedure WriteText(const FileName, S: string);
var
  F: TFileStream;
begin
  ForceDirectories(ExtractFileDir(FileName));
  F := TFileStream.Create(FileName, fmCreate);
  try
    if S <> '' then F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

procedure TestProfile;
begin
  Check((StartLevel = 'level13.nw') and (StartX = 512) and (StartY = 512) and
    (StartFacing = fDown), 'profile: starts in level13.nw at (512, 512) facing down');
  Check((ViewW = 640) and (ViewH = 480) and (TilePx = 16), 'profile: 640 x 480 view, 16-pixel tiles');
  Check((Ord(fUp) = 0) and (Ord(fLeft) = 1) and (Ord(fDown) = 2) and (Ord(fRight) = 3),
    'profile: facing order up, left, down, right');
  Check((GaniFrames[gIdle] = 1) and (GaniFrames[gWalk] = 8) and (GaniFrames[gSword] = 5) and
    (GaniFrames[gSwim] = 8) and (GaniFrames[gSit] = 1) and (GaniFrames[gGrab] = 1) and
    (GaniFrames[gPull] = 3) and (GaniFrames[gPush] = 5),
    'profile: eight ganis with 1, 8, 5, 8, 1, 1, 3, 5 frames');
  Check(Abs(TimeFactor(1000 / 60) - 1) < 1e-9, 'time factor: one nominal frame is 1');
  Check(Abs(TimeFactor(1000 / 30) - 2) < 1e-9, 'time factor: a 33 ms frame is 2');
  Check(TimeFactor(500) = 4, 'time factor: capped at 4');
end;

procedure TestSheetMapping;
var
  C, R: Integer;
begin
  TileCell(0, C, R);
  Check((C = 0) and (R = 0), 'sheet: id 0 is cell (0, 0)');
  TileCell(15, C, R);
  Check((C = 15) and (R = 0), 'sheet: id 15 is cell (15, 0)');
  TileCell(16, C, R);
  Check((C = 0) and (R = 1), 'sheet: id 16 wraps to row 1');
  TileCell(511, C, R);
  Check((C = 15) and (R = 31), 'sheet: id 511 is the last cell of block 0 (15, 31)');
  TileCell(512, C, R);
  Check((C = 16) and (R = 0), 'sheet: id 512 starts block 1 at column 16, row 0');
  TileCell(1023, C, R);
  Check((C = 31) and (R = 31), 'sheet: id 1023 ends block 1 at (31, 31)');
  TileCell(1024, C, R);
  Check((C = 32) and (R = 0), 'sheet: id 1024 starts block 2 at column 32');
  TileCell(4095, C, R);
  Check((C = 127) and (R = 31), 'sheet: id 4095 is the last cell (127, 31)');
  Check((NwPairId('A', 'A') = 0) and (NwPairId('A', 'B') = 1) and
    (NwPairId('I', 'A') = 512) and (NwPairId('/', '/') = 4095) and (NwPairId('!', 'A') = -1),
    'NW pair: base64 pairs give 12-bit ids (AA 0, AB 1, IA 512, // 4095)');
end;

procedure TestPacking;
var
  T: TPackedTile39;
begin
  T := PackTile(127, 31, 7);
  Check((PackedCol(T) = 127) and (PackedRow(T) = 31) and (PackedCategory(T) = 7),
    'packed tile: 10 bits column, 10 bits row, 12 bits category round trip');
  T := PackTile(1023, 1023, 4095);
  Check((PackedCol(T) = 1023) and (PackedRow(T) = 1023) and (PackedCategory(T) = 4095),
    'packed tile: every field at its maximum stays in its own bits');
end;

procedure TestCategories;
var
  T: TCategoryTable39;
  S: string;
begin
  T := TCategoryTable39.Create;
  try
    { cells: (1,0) blocking, (16,0) water (id 512), (127,31) shallow water,
      (3,1) chair, (4,1) jump, (5,1) throw-through, (6,1) swamp }
    S := MakeCategories([1, 16, SheetCells - 1, 128 + 3, 128 + 4, 128 + 5, 128 + 6],
      ['B', 'D', 'H', 'E', 'F', 'C', 'G']);
    Check(T.LoadFromString(S), 'categories: a generated 128 x 32 table loads');
    Check(T.TileCategory(0) = Ord(tcGround), 'categories: A is ground');
    Check(T.TileCategory(1) = Ord(tcBlocking), 'categories: B is blocking');
    Check(T.TileCategory(512) = Ord(tcWater),
      'categories: id 512 reads the cell at column 16 (water), not column 0');
    Check(T.TileCategory(4095) = Ord(tcShallowWater), 'categories: id 4095 reads the last cell');
    Check(T.TileCategory(16 + 3) = Ord(tcChair), 'categories: E is chair');
    Check(T.TileCategory(16 + 6) = Ord(tcSwamp), 'categories: G is swamp');
    Check(T.TileCategory(16 + 4) = Ord(tcJump), 'categories: F is jump');
    Check(CategoryIsWall(Ord(tcBlocking)) and CategoryIsWall(Ord(tcJump)) and
      CategoryIsWall(Ord(tcThrowThrough)) and not CategoryIsWall(Ord(tcWater)) and
      not CategoryIsWall(Ord(tcGround)) and not CategoryIsWall(Ord(tcChair)),
      'categories: blocking, jump and throw-through are walls; water, chair, ground are not');
    Check((T.TileCategory(512) = 3) and (CategoryBit(T.TileCategory(512)) = 8),
      'categories: water is index 3, which becomes bit 8 only when tested');
    Check(T.LoadFromString(Copy(S, 1, 2048) + #13#10 + Copy(S, 2049, MaxInt)) and
      (T.TileCategory(4095) = Ord(tcShallowWater)), 'categories: line breaks are skipped');
    Check(not T.LoadFromString(Copy(S, 1, 100)) and (T.TileCategory(1) = Ord(tcGround)),
      'categories: a short table is refused and leaves all ground');
    Check(not T.LoadFromString(StringOfChar('Z', SheetCells)), 'categories: an unknown letter is refused');
  finally
    T.Free;
  end;
end;

procedure TestBoards;
var
  L: TAdventureLevel;
  Ok: Boolean;
  X, Y: Integer;
begin
  L := TAdventureLevel.Create;
  try
    Check(L.LoadFromString(MakeNw(7)), 'board: a generated 64 x 64 GLEVNW01 level loads');
    Ok := True;
    for Y := 0 to 63 do
      for X := 0 to 63 do
        if L.Tile(X, Y) <> (X * 64 + Y + 7) mod 4096 then Ok := False;
    Check(Ok, 'board: every one of the 4096 tiles reads back');
    Check((L.Tile(8, 0) = 512 + 7) and (L.Tile(63, 63) = (63 * 64 + 63 + 7) mod 4096),
      'board: ids past a 512 block survive (8,0) and the far corner');
  finally
    L.Free;
  end;
end;

procedure TestCamera;
var
  OX, OY: Integer;
begin
  CameraOrigin(512, 512, 1024, 1024, 640, 480, OX, OY);
  Check((OX = 512 + 8 - 320) and (OY = 512 + 8 - 240), 'camera: centres the 16-pixel anchor');
  CameraOrigin(0, 0, 1024, 1024, 640, 480, OX, OY);
  Check((OX = 0) and (OY = 0), 'camera: clamped at the top-left');
  CameraOrigin(1008, 1008, 1024, 1024, 640, 480, OX, OY);
  Check((OX = 1024 - 640) and (OY = 1024 - 480), 'camera: clamped at the bottom-right');
  CameraOrigin(100, 100, 320, 1024, 640, 480, OX, OY);
  Check((OX = -160) and (OY = 0), 'camera: a level narrower than the view is centred on that axis only');
  CameraOrigin(0, 0, 320, 240, 640, 480, OX, OY);
  Check((OX = -160) and (OY = -120), 'camera: a level smaller than the view is centred');
end;

{ The world reads the player's install from the asset roots: a generated
  install folder with levels/, pics1 and arrays.dat. }
procedure TestInstall;
var
  W: TWorld39;
  Dir: string;
  Sheet: TGSurface;
  X, Y, OX, OY: Integer;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'g39install' + PathDelim;
  ForceDirectories(Dir + 'levels');
  WriteText(Dir + 'levels' + PathDelim + StartLevel, MakeNw(0));
  WriteText(Dir + 'arrays.dat', MakeCategories([16 * 0 + 1], ['B']));
  { a 2048 x 512 sheet whose cell (c, r) is coloured $FF000000 + c * 256 + r }
  Sheet := TGSurface.Create(SheetCols * TilePx, SheetRows * TilePx);
  W := TWorld39.Create;
  try
    for Y := 0 to Sheet.Height - 1 do
      for X := 0 to Sheet.Width - 1 do
        Sheet.Pixels[Y * Sheet.Width + X] := $FF000000 or Cardinal((X div TilePx) shl 8) or
          Cardinal(Y div TilePx);
    Sheet.SaveBMP(Dir + 'pics1.bmp');
    SetAssetRootsFor('', Dir, ClientAssetFolders);
    Check(not W.LoadInstall and (W.Sheet = nil) and W.Categories.Loaded,
      'install: the category table is read; no pics1.png is reported');
    Check(W.LoadLevel(StartLevel) and (W.Level.Tile(1, 0) = 64),
      'install: levels/level13.nw is read from the player''s folder');
    Check(W.CategoryAt(-1, 0) = Ord(tcBlocking), 'install: outside the level is blocked');
    { draw with the generated sheet (as .bmp; the install's own is .png) }
    W.Sheet := TGSurface.Create(1, 1);
    Check(W.Sheet.LoadBMP(Dir + 'pics1.bmp'), 'install: the generated sheet loads');
    { the anchor box away from board tile (8, 0), which is id 512: sheet
      column 16, row 0 }
    W.AnchorX := 0;
    W.AnchorY := 64;
    W.Draw;
    CameraOrigin(W.AnchorX, W.AnchorY, 1024, 1024, ViewW, ViewH, OX, OY);
    Check((OX = 0) and (OY = 0) and (W.Screen.GetPixel(8 * TilePx + 1, 1) = $FF001000),
      'draw: id 512 is drawn from sheet column 16');
    Check(W.Screen.GetPixel(1, 64 + 1) = $FFFFFFFF, 'draw: the anchor box is drawn at its level pixel');
    Check(not W.LoadLevel('missing.nw') and (W.LastError <> ''), 'install: a missing level fails');
  finally
    W.Free;
    Sheet.Free;
    DeleteFile(Dir + 'levels' + PathDelim + StartLevel);
    DeleteFile(Dir + 'arrays.dat');
    DeleteFile(Dir + 'pics1.bmp');
    RemoveDir(Dir + 'levels');
    RemoveDir(Dir);
  end;
end;

{ A generated wall map for Move39: a 64 x 64 board of free tiles with the
  listed walls. }
type
  TWalls = class
    Wall: array[0..63, 0..63] of Boolean;
    function IsWall(TX, TY: Integer): Boolean;
    procedure Put(TX, TY: Integer);
  end;

function TWalls.IsWall(TX, TY: Integer): Boolean;
begin
  Result := Wall[TX, TY];
end;

procedure TWalls.Put(TX, TY: Integer);
begin
  Wall[TX, TY] := True;
end;

const
  LvW = 64 * 16;
  LvH = 64 * 16;

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) < 1e-9;
end;

procedure TestEdges;
var
  M: TWalls;
begin
  M := TWalls.Create;
  try
    M.Put(2, 1);
    Check(not RectBlocked(M.IsWall, 16, 16, 16, 16, LvW, LvH),
      'edges: a box on tile (1, 1) ends before the wall at (2, 1) (end exclusive)');
    Check(RectBlocked(M.IsWall, 16.5, 16, 16, 16, LvW, LvH),
      'edges: half a pixel right, the right edge rounds up into the wall');
    Check(RectBlocked(M.IsWall, 47.9, 16, 0, 16, LvW, LvH),
      'edges: the left edge truncates, so x 47.9 is still in the wall tile');
    Check(not RectBlocked(M.IsWall, 32, 16, 0, 16, LvW, LvH),
      'edges: a zero-width edge on a tile boundary covers no tile');
    Check(RectBlocked(M.IsWall, 33, 16, 0, 16, LvW, LvH),
      'edges: a zero-width edge inside the wall tile is blocked');
    Check(RectBlocked(M.IsWall, -0.5, 100, 16, 16, LvW, LvH) and
      RectBlocked(M.IsWall, 100, LvH - 15.5, 16, 16, LvW, LvH),
      'edges: a box leaving the level is blocked');
    Check(not RectBlocked(M.IsWall, LvW - 16, LvH - 16, 16, 16, LvW, LvH),
      'edges: a box touching the far edges from inside is free');
  finally
    M.Free;
  end;
end;

procedure TestMovement;
var
  M: TWalls;
  X, Y: Double;
begin
  M := TWalls.Create;
  try
    X := 100; Y := 100;
    Check(MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH) and Near(X, 103) and Near(Y, 100),
      'move: 3 pixels right in one nominal update');
    X := 100; Y := 100;
    MovePlayer(M.IsWall, X, Y, 0, -1, 2, MoveStep, LvW, LvH);
    Check(Near(Y, 94), 'move: a 2x time factor moves 6 pixels');
    X := 100; Y := 100;
    MovePlayer(M.IsWall, X, Y, 0, 1, TimeFactor(500), MoveStep, LvW, LvH);
    Check(Near(Y, 112), 'move: a long frame is capped at 4x (12 pixels)');
    X := 100; Y := 100;
    MovePlayer(M.IsWall, X, Y, -1, 1, 1, MoveStep, LvW, LvH);
    Check(Near(X, 97.75) and Near(Y, 102.25), 'move: each diagonal component is 3 x 0.75');
    X := 100; Y := 100;
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, GetUpStep, LvW, LvH);
    Check(Near(X, 102), 'move: getting up moves 2 pixels');
    X := 100; Y := 100;
    Check(not MovePlayer(M.IsWall, X, Y, 0, 0, 1, MoveStep, LvW, LvH) and Near(X, 100),
      'move: nothing held, nothing moves');

    { vertical before horizontal: from (47, 30) down-right, the wall at
      (4, 1) blocks the horizontal move on the old rows but not on the new
      ones }
    M.Put(4, 1);
    X := 47; Y := 30;
    MovePlayer(M.IsWall, X, Y, 1, 1, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 32.25) and Near(X, 49.25),
      'move: the vertical move is resolved first, freeing the horizontal one');
    X := 47; Y := 30;
    MovePlayer(M.IsWall, X, Y, 1, -1, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 27.75) and Near(X, 47.25),
      'move: going up instead, the wall still blocks and 2.25 shrinks to 0.25');

    { a blocked component shrinks a pixel at a time }
    X := 46; Y := 16;
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(X, 48), 'shrink: 3 pixels into a wall become 2, stopping on its edge');
    X := 46.5; Y := 16;
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(X, 47.5), 'shrink: from 46.5 the move shrinks by whole pixels to 1');
    X := 0.5; Y := 300;
    MovePlayer(M.IsWall, X, Y, -1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(X, 0.5), 'shrink: half a pixel from the level edge, the move shrinks to nothing');
  finally
    M.Free;
  end;
end;

procedure TestSlides;
var
  M: TWalls;
  X, Y: Double;
  I: Integer;
begin
  M := TWalls.Create;
  try
    { one wall tile at (4, 1); the box pushes right at x 48 }
    M.Put(4, 1);
    X := 48; Y := 20;
    Check(MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH) and Near(X, 48) and Near(Y, 21.5),
      'slide: the nearer boundary (16) is still blocked, so it slides 1.5 toward 32');
    X := 48; Y := 29;
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 30.5), 'slide: 1.5 pixels at a time');
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 32), 'slide: within one step of the boundary it snaps to it');
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(X, 51) and Near(Y, 32), 'slide: once past the wall the move goes ahead');
    X := 48; Y := 20;
    MovePlayer(M.IsWall, X, Y, 1, 0, 2, MoveStep, LvW, LvH);
    Check(Near(Y, 23), 'slide: the slide scales with the time factor');
    { the mirror case: the wall at (4, 2) makes the nearer boundary the way out }
    M.Wall[4, 1] := False;
    M.Put(4, 2);
    X := 48; Y := 20;
    MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 18.5), 'slide: the nearer boundary (16) is preferred when it is free');
    { already on a boundary, a blocked push does nothing }
    X := 48; Y := 32;
    Check(not MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH) and Near(X, 48) and Near(Y, 32),
      'slide: aligned to the tiles, a blocked push does not slide');
    { vertical pushes slide horizontally }
    M.Put(10, 10);
    X := 165; Y := 144;
    MovePlayer(M.IsWall, X, Y, 0, 1, 1, MoveStep, LvW, LvH);
    Check(Near(Y, 144) and Near(X, 166.5), 'slide: a blocked push down slides along x');
    { diagonal moves never slide }
    M.Put(11, 9);
    X := 168; Y := 145;
    for I := 1 to 2 do MovePlayer(M.IsWall, X, Y, 1, 1, 1, MoveStep, LvW, LvH);
    Check(Near(X, 168) and Near(Y, 145), 'slide: a blocked diagonal move does not slide');
    { both ways blocked: no slide }
    M.Put(4, 3);
    M.Put(4, 1);
    X := 48; Y := 20;
    Check(not MovePlayer(M.IsWall, X, Y, 1, 0, 1, MoveStep, LvW, LvH),
      'slide: with walls on both sides there is nowhere to slide');
  finally
    M.Free;
  end;
end;

{ The world's own step: the generated category table's walls, the level's
  tiles and the facing. }
procedure TestWorldStep;
var
  W: TWorld39;
  Lv: string;
  Y: Integer;
begin
  W := TWorld39.Create;
  try
    Lv := 'GLEVNW01'#10;
    for Y := 0 to 63 do
      if Y = 5 then
        Lv := Lv + 'BOARD 0 5 64 0 ' + StringOfChar('A', 10) + Pair(1) + StringOfChar('A', 116) + #10
      else
        Lv := Lv + Format('BOARD 0 %d 64 0 ', [Y]) + StringOfChar('A', 128) + #10;
    Check(W.Level.LoadFromString(Lv) and W.Categories.LoadFromString(MakeCategories([1], ['B'])),
      'world: a level with one blocking tile at (5, 5)');
    Check(W.IsWall(5, 5) and not W.IsWall(4, 5) and W.IsWall(-1, 0), 'world: walls from the categories');
    W.PlaceAt(62, 80);
    Check(W.Step(1, 0, 1) and (W.AnchorX = 64) and (W.Facing = fRight),
      'world: walking right stops on the wall tile''s edge and faces right');
    W.PlaceAt(80, 100.5);
    W.Step(0, -1, 1);
    Check((W.AnchorY = 97) and Near(W.PosY, 97.5) and (W.Facing = fUp),
      'world: the anchor is the position truncated; the fraction is kept');
  finally
    W.Free;
  end;
end;


{ --- animation (generated ganis and pictures only) --- }

{ A gani with N steps; each step's four rows place sprite 1 (BODY) and
  sprite 2 (HEAD) at the given spots, row d using sprite 10 + d (BODY) so
  the facing can be told apart. Extra header lines go in Head; Wait > 0
  puts a WAIT line after every step. }
function MakeGani(N: Integer; const Head: string; Wait: Integer): string;
var
  I, D: Integer;
begin
  Result := 'GANI0001'#10 +
    'SPRITE 2 HEAD 0 0 16 16 head'#10;
  for D := 0 to 3 do
    Result := Result + Format('SPRITE %d BODY %d 0 16 16 body dir %d', [10 + D, 16 * D, D]) + #10;
  Result := Result + Head + 'DEFAULTHEAD head.bmp'#10'DEFAULTBODY body.bmp'#10#10'ANI'#10;
  for I := 1 to N do
  begin
    for D := 0 to 3 do
      Result := Result + Format('%d 8 16, 2 8 0', [10 + D]) + #10;
    if Wait > 0 then Result := Result + Format('WAIT %d', [Wait]) + #10;
    Result := Result + #10;
  end;
  Result := Result + 'ANIEND'#10;
end;

procedure WriteGanis(const Dir: string; WalkWait: Integer);
const
  Heads: array[TGani39] of string = ('', 'LOOP'#10'CONTINUOUS'#10,
    'SETBACKTO idle'#10, 'LOOP'#10, '', '', 'LOOP'#10, 'LOOP'#10);
var
  G: TGani39;
begin
  for G := Low(TGani39) to High(TGani39) do
    WriteText(Dir + 'levels' + PathDelim + GaniName[G] + '.gani',
      MakeGani(GaniFrames[G], Heads[G], Ord(G = gWalk) * WalkWait));
end;

procedure RemoveInstall(const Dir: string);
var
  G: TGani39;
begin
  for G := Low(TGani39) to High(TGani39) do
    DeleteFile(Dir + 'levels' + PathDelim + GaniName[G] + '.gani');
  DeleteFile(Dir + 'levels' + PathDelim + StartLevel);
  DeleteFile(Dir + 'levels' + PathDelim + 'head.bmp');
  DeleteFile(Dir + 'levels' + PathDelim + 'body.bmp');
  DeleteFile(Dir + 'arrays.dat');
  RemoveDir(Dir + 'levels');
  RemoveDir(Dir);
end;

procedure TestAnimationProfile;
var
  Set39: TGaniSet39;
  A: TAnimState39;
  I: Integer;
  R: TGani39;
begin
  { no install: the profile's frame counts and endings }
  Set39 := TGaniSet39.Create;
  try
    Check((Set39.Frames(gWalk) = 8) and (Set39.Frames(gSword) = 5) and (Set39.Frames(gPull) = 3),
      'anim: without ganis, the profile frame counts');
    A.Gani := gIdle;
    A.Pos := 0;
    PlayGani(A, gWalk);
    for I := 1 to 3 do AdvanceAnim(A, Set39, 1);
    Check(Near(A.Pos, 1.05) and (AnimFrame(A, Set39) = 1), 'anim: 0.35 a nominal update, 3 updates reach frame 1');
    for I := 1 to 20 do AdvanceAnim(A, Set39, 1);
    Check((A.Gani = gWalk) and Near(A.Pos, 23 * 0.35 - 8) and (AnimFrame(A, Set39) = 0),
      'anim: walk loops back to frame 0 after 8 frames');
    PlayGani(A, gWalk);
    Check(A.Pos > 0, 'anim: playing the gani already playing does not restart it');
    PlayGani(A, gSword);
    for I := 1 to 14 do AdvanceAnim(A, Set39, 1);
    Check((A.Gani = gSword) and (AnimFrame(A, Set39) = 4), 'anim: the sword is on its last frame after 14 updates');
    AdvanceAnim(A, Set39, 1);
    Check((A.Gani = gIdle) and (A.Pos = 0), 'anim: the sword returns to idle when it ends');
    PlayGani(A, gSit);
    for I := 1 to 50 do AdvanceAnim(A, Set39, 4);
    Check((A.Gani = gSit) and (AnimFrame(A, Set39) = 0), 'anim: a held pose stays on its frame');
    PlayGani(A, gWalk);
    AdvanceAnim(A, Set39, 2);
    Check(Near(A.Pos, 0.7), 'anim: the step scales with the time factor (0.7 at 2)');
    Check(Set39.ReturnTo(gSword, R) and (R = gIdle) and not Set39.ReturnTo(gGrab, R),
      'anim: only the sword has a return gani by default');
    Check(GaniByName('Sword.gani', R) and (R = gSword) and not GaniByName('dance', R),
      'anim: gani names match without case or .gani');
  finally
    Set39.Free;
  end;
end;

procedure TestAnimationInstall;
var
  W: TWorld39;
  Dir: string;
  Body, Head: TGSurface;
  I, X0, Y0, OX, OY: Integer;
  X1: Double;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'g39anim' + PathDelim;
  ForceDirectories(Dir + 'levels');
  WriteText(Dir + 'levels' + PathDelim + StartLevel, MakeNw(0));
  WriteText(Dir + 'arrays.dat', StringOfChar('A', SheetCells));
  { WAIT 5 after every walk step: the waits are skipped }
  WriteGanis(Dir, 5);
  { body: a 64 x 16 strip, one colour per direction; head: one colour }
  Body := TGSurface.Create(64, 16);
  Head := TGSurface.Create(16, 16);
  W := TWorld39.Create;
  try
    for I := 0 to 3 do Body.FillRect(16 * I, 0, 16, 16, $FF000000 or (Cardinal(I + 1) shl 20));
    Head.Fill($FF0000FF);
    Body.SaveBMP(Dir + 'levels' + PathDelim + 'body.bmp');
    Head.SaveBMP(Dir + 'levels' + PathDelim + 'head.bmp');
    SetAssetRootsFor('', Dir, ClientAssetFolders);
    W.LoadInstall;
    Check((W.Ganis.Ganis[gWalk] <> nil) and (W.Ganis.Frames(gWalk) = 8),
      'install anim: the eight generated ganis load');
    Check(W.LoadLevel(StartLevel), 'install anim: the level loads');
    W.Anim.Gani := gWalk;
    W.Anim.Pos := 0;
    for I := 1 to 3 do AdvanceAnim(W.Anim, W.Ganis, 1);
    Check(AnimFrame(W.Anim, W.Ganis) = 1, 'install anim: WAIT lines are skipped (frame 1 after 3 updates)');
    Check(W.Ganis.PieceFile(gIdle, 'HEAD') = 'head.bmp',
      'install anim: a piece the gani names and the install has is used');
    Check(W.Ganis.PieceFile(gIdle, 'SHIELD') = PieceShield,
      'install anim: otherwise the profile''s picture for that piece');
    { draw: the box at (512, 512), facing down; the gani origin is the box
      less (16, 32), body at (8, 16) and head at (8, 0) from it }
    W.PlaceAt(512, 512);
    W.Facing := fDown;
    W.Anim.Gani := gIdle;
    W.Anim.Pos := 0;
    W.Draw;
    CameraOrigin(512, 512, 1024, 1024, ViewW, ViewH, OX, OY);
    X0 := 512 - OX + CharOriginDX;
    Y0 := 512 - OY + CharOriginDY;
    Check(W.Screen.GetPixel(X0 + 8 + 1, Y0 + 16 + 1) = ($FF300000 or $FF000000),
      'draw: the body piece facing down (row 2) at (8, 16) from the gani origin');
    Check(W.Screen.GetPixel(X0 + 8 + 1, Y0 + 1) = $FF0000FF, 'draw: the head piece at (8, 0)');
    W.Facing := fLeft;
    W.Draw;
    Check(W.Screen.GetPixel(X0 + 8 + 1, Y0 + 16 + 1) = ($FF200000 or $FF000000),
      'draw: facing left draws the left row');
    { play: Space starts the sword, which roots the player until it ends }
    W.PlaceAt(512, 512);
    W.Update(0, 0, True, 1);
    X1 := W.PosX;
    Check(W.Anim.Gani = gSword, 'play: attack starts the sword');
    for I := 1 to 10 do W.Update(1, 0, False, 1);
    Check((W.Anim.Gani = gSword) and Near(W.PosX, X1), 'play: the player does not walk while the sword swings');
    for I := 1 to 5 do W.Update(0, 0, False, 1);
    Check(W.Anim.Gani = gIdle, 'play: the sword ends in idle');
    W.Update(1, 0, False, 1);
    Check((W.Anim.Gani = gWalk) and (W.PosX > X1) and (W.Facing = fRight), 'play: held arrows walk with the walk gani');
    W.Update(0, 0, False, 1);
    Check(W.Anim.Gani = gIdle, 'play: letting go stands idle');
  finally
    W.Free;
    Body.Free;
    Head.Free;
    RemoveInstall(Dir);
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestProfile;
  TestSheetMapping;
  TestPacking;
  TestCategories;
  TestBoards;
  TestCamera;
  TestInstall;
  TestEdges;
  TestMovement;
  TestSlides;
  TestWorldStep;
  TestAnimationProfile;
  TestAnimationInstall;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
