{ Test39ster: the 39ster profile with generated fixtures only.

  No file of the original install is read: every level, category table and
  tile sheet here is made by the test. Covers the first slices of #176:
  the profile and player-supplied loading, 64 x 64 NW boards, the sheet
  mapping across 512-id blocks, category-index interpretation, and camera
  clamping and centring. }
program Test39ster;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  SysUtils, Classes, GLevel, GSurface, GAssetDirs,
  Profile39 in '../src/Profile39.pas',
  Tiles39 in '../src/Tiles39.pas',
  Camera39 in '../src/Camera39.pas',
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
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
