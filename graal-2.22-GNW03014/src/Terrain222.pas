{ Terrain222: the height-shaped ground of 2.22's new-world maps.

  A level of a generator gmap (formats/grmap001.txt) has a 65 x 65 grid of
  heights, one per tile corner. 2.22 builds it the way the client does
  (client-internals/newworld-betas.md, read again from Graal_222.exe):

  - the map: HEIGHTMAP gives the level corners; each level edge is filled
    by 1-D midpoint displacement, amplitude LEVHEIGHT, times LEVCHAOS per
    step, from the RTL random seed GENSEED (edges are shared, so seams
    match);
  - the level: its four edges come from the map, the seed is the level's
    RANDOMSEEDS entry, and the inside is filled by recursive subdivision
    (centre row, then the two halves of the centre column, then the four
    quarters), amplitude LEVHEIGHT x LEVCHAOS;
  - its HEIGHTS block (9 x 9 points, one every 8 tiles) then corrects each
    8 x 8 cell bilinearly so that the surface passes through the points;
    a cell whose four points are equal is set flat to them.

  The heights between corners are blended bilinearly. Each height step
  lifts what stands there by one tile (16 px) on screen: the ground, and
  players and NPCs at their foot point.

  The ground is drawn as 2.22 draws it (read from Graal_222.exe):

  - a tile of the level other than 0 is copied from the sheet; tile 0 is
    picked from the four corner heights. Seven thresholds (0, 3, 4, 5, 25,
    55, 65) are tried from the top: when all four corners reach one, the
    tile comes from the full patch of the band above it; when only some
    do, from that band's transition tiles, chosen by which corners reach
    it. A full patch tile is a decoration (flowers, stones) when the
    fraction of the corners' sum says so, otherwise a plain tile picked by
    the tile's place;
  - each pixel is darkened by the slope down the screen at that place,
    32 levels on flat ground, none on ground that falls towards the
    viewer, 63 on ground that rises;
  - where the ground is under 0 the pixel is water: the deeper, the darker
    and bluer, and white foam at the shore. }
unit Terrain222;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, SysUtils, GPaths, GSurface, GAssetDirs;

const
  LevelCorners = 65;  { per side of a level's height grid }
  HeightPoints = 9;   { per side of a level's HEIGHTS block }
  HeightStep = 8;     { tiles between HEIGHTS points }
  LiftPerHeight = 16; { screen pixels per height step }

type
  { [row, col]: the height at each tile corner of a level }
  THeightGrid = array[0..LevelCorners - 1, 0..LevelCorners - 1] of Double;
  PHeightGrid = ^THeightGrid;
  THeightPoints = array[0..HeightPoints - 1, 0..HeightPoints - 1] of Double;

  { One gmap's terrain: what its generator form says, and the level grids
    built from it so far. }
  TTerrainMap = class
  private
    FW, FH: Integer;
    FSeed: Cardinal;
    FLevHeight, FLevChaos: Double;
    FCorners: array of Double;     { (FH + 1) x (FW + 1) }
    FSeeds: array of Cardinal;     { FH x FW }
    FHasMap: Boolean;
    FHEdges, FVEdges: array of Double;
    FEdgesBuilt: Boolean;
    FCells: TStringList;           { lower-case name per cell }
    FPoints: array of THeightPoints;
    FHasPoints: array of Boolean;
    FGrids: array of PHeightGrid;
    procedure BuildEdges;
    function Build(Cell: Integer): PHeightGrid;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  THeightStore = class
  private
    FNames: TStringList; { lower-case level name -> map * 65536 + cell }
    FMaps: TList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Reads a gmap's generator form and its HEIGHTS blocks. Returns how
      many HEIGHTS blocks were read. }
    function AddGmap(const Data: string): Integer;
    { Reads every .gmap in Dir. }
    procedure AddDir(const Dir: string);
    { The height grid of a level, or nil when it has none. The store owns it. }
    function Find(const Level: string): PHeightGrid;
    function Count: Integer;
  end;

{ The height at (X, Y) in tiles, 0..64 across the level. }
function HeightAt(const G: THeightGrid; X, Y: Double): Double;

{ The screen lift in pixels of something standing at (X, Y): heights under
  0 (water) lift nothing. }
function LiftAt(const G: THeightGrid; X, Y: Double): Integer;

type
  { the heights at a tile's corners, and the slope down the screen there
    (the height one corner below less the one above): top left, top right,
    bottom left, bottom right }
  TTileCorners = record
    H, S: array[0..3] of Double;
  end;

const
  CornerTL = 0; CornerTR = 1; CornerBL = 2; CornerBR = 3;

{ Where on a new-order sheet (picso.png and kin) the ground of a tile 0
  with corners C comes from; X and Y are its place in the level. }
procedure PickGroundTile(const C: TTileCorners; X, Y: Integer; out SX, SY: Integer);

{ Draws tile Tile of a level with height corners C at (DX, DY) on Dest,
  from the new-order sheet: tile 0 is picked by height, and every pixel is
  lit by the slope or drawn as water. }
procedure DrawGroundTile(Dest, Sheet: TGSurface; Tile: Integer;
  const C: TTileCorners; X, Y, DX, DY: Integer);

implementation

{ Delphi's Random: RandSeed := RandSeed * $08088405 + 1, scaled to 0..1. }
type
  TRtlRandom = record
    Seed: Cardinal;
  end;

function NextRandom(var R: TRtlRandom): Double;
begin
  {$PUSH}{$Q-}{$R-}
  R.Seed := R.Seed * $08088405 + 1;
  {$POP}
  Result := R.Seed / 4294967296.0;
end;

type
  { a grid of doubles seen through (X, Y) with a row stride }
  TGridView = record
    P: PDouble;
    Stride: Integer;
  end;

function GV(const V: TGridView; X, Y: Integer): Double; inline;
begin
  Result := V.P[Y * V.Stride + X];
end;

{ 1-D midpoint displacement from (X1, Y1) to (X2, Y2): the midpoint gets
  the average of the ends plus (random - 0.5) x 2 x Amp, then each half
  with Amp x Ratio. }
procedure DisplaceLine(const V: TGridView; X1, Y1, X2, Y2: Integer;
  Amp, Ratio: Double; var R: TRtlRandom);
var
  MX, MY: Integer;
  D: Double;
begin
  if (X2 - X1 <= 1) and (Y2 - Y1 <= 1) then Exit;
  MX := (X1 + X2) div 2;
  MY := (Y1 + Y2) div 2;
  D := (NextRandom(R) - 0.5) * 2 * Amp;
  V.P[MY * V.Stride + MX] := D + (GV(V, X1, Y1) + GV(V, X2, Y2)) / 2;
  DisplaceLine(V, X1, Y1, MX, MY, Amp * Ratio, Ratio, R);
  DisplaceLine(V, MX, MY, X2, Y2, Amp * Ratio, Ratio, R);
end;

procedure Subdivide(const V: TGridView; X1, Y1, X2, Y2: Integer;
  Amp, Ratio: Double; var R: TRtlRandom);
var
  MX, MY: Integer;
begin
  if (X2 - X1 <= 1) and (Y2 - Y1 <= 1) then Exit;
  MX := (X1 + X2) div 2;
  MY := (Y1 + Y2) div 2;
  DisplaceLine(V, X1, MY, X2, MY, Amp, Ratio, R);
  DisplaceLine(V, MX, Y1, MX, MY, Amp * Ratio, Ratio, R);
  DisplaceLine(V, MX, MY, MX, Y2, Amp * Ratio, Ratio, R);
  Subdivide(V, X1, Y1, MX, MY, Amp * Ratio, Ratio, R);
  Subdivide(V, MX, Y1, X2, MY, Amp * Ratio, Ratio, R);
  Subdivide(V, X1, MY, MX, Y2, Amp * Ratio, Ratio, R);
  Subdivide(V, MX, MY, X2, Y2, Amp * Ratio, Ratio, R);
end;

{ TTerrainMap }

constructor TTerrainMap.Create;
begin
  inherited Create;
  FCells := TStringList.Create;
end;

destructor TTerrainMap.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FGrids) do
    if FGrids[I] <> nil then Dispose(FGrids[I]);
  FCells.Free;
  inherited Destroy;
end;

procedure TTerrainMap.BuildEdges;
var
  X, Y, HW: Integer;
  R: TRtlRandom;
  V: TGridView;
begin
  FEdgesBuilt := True;
  HW := FW * 64 + 1;
  SetLength(FHEdges, (FH + 1) * HW);
  SetLength(FVEdges, (FH * 64 + 1) * (FW + 1));
  if not FHasMap then Exit;
  for X := 0 to FW do
    for Y := 0 to FH do
    begin
      FHEdges[Y * HW + X * 64] := FCorners[Y * (FW + 1) + X];
      FVEdges[Y * 64 * (FW + 1) + X] := FCorners[Y * (FW + 1) + X];
    end;
  R.Seed := FSeed;
  for X := 0 to FW do
    for Y := 0 to FH do
    begin
      if X < FW then
      begin
        V.P := @FHEdges[0];
        V.Stride := HW;
        DisplaceLine(V, X * 64, Y, (X + 1) * 64, Y, FLevHeight, FLevChaos, R);
      end;
      if Y < FH then
      begin
        V.P := @FVEdges[0];
        V.Stride := FW + 1;
        DisplaceLine(V, X, Y * 64, X, (Y + 1) * 64, FLevHeight, FLevChaos, R);
      end;
    end;
end;

function TTerrainMap.Build(Cell: Integer): PHeightGrid;
var
  G: PHeightGrid;
  LX, LY, I, CX, CY, X, Y, X2, Y2, HW: Integer;
  R: TRtlRandom;
  V: TGridView;
  P: THeightPoints;
  D00, D10, D01, D11, A, B: Double;
begin
  Result := FGrids[Cell];
  if Result <> nil then Exit;
  New(G);
  FillChar(G^, SizeOf(G^), 0);
  if FHasMap and (Cell < FW * FH) then
  begin
    if not FEdgesBuilt then BuildEdges;
    LX := Cell mod FW;
    LY := Cell div FW;
    HW := FW * 64 + 1;
    for I := 0 to 64 do
    begin
      G^[0, I] := FHEdges[LY * HW + LX * 64 + I];
      G^[64, I] := FHEdges[(LY + 1) * HW + LX * 64 + I];
      G^[I, 0] := FVEdges[(LY * 64 + I) * (FW + 1) + LX];
      G^[I, 64] := FVEdges[(LY * 64 + I) * (FW + 1) + LX + 1];
    end;
    R.Seed := 0;
    if Cell < Length(FSeeds) then R.Seed := FSeeds[Cell];
    V.P := @G^[0, 0];
    V.Stride := LevelCorners;
    Subdivide(V, 0, 0, 64, 64, FLevHeight * FLevChaos, FLevChaos, R);
  end;
  if (Cell < Length(FHasPoints)) and FHasPoints[Cell] then
  begin
    P := FPoints[Cell];
    for CX := 0 to HeightPoints - 2 do
      for CY := 0 to HeightPoints - 2 do
      begin
        X2 := (CX + 1) * HeightStep;
        if CX < HeightPoints - 2 then Dec(X2);
        Y2 := (CY + 1) * HeightStep;
        if CY < HeightPoints - 2 then Dec(Y2);
        if (P[CY, CX] = P[CY + 1, CX]) and (P[CY, CX] = P[CY, CX + 1]) and
          (P[CY, CX] = P[CY + 1, CX + 1]) then
        begin
          for Y := CY * HeightStep to Y2 do
            for X := CX * HeightStep to X2 do
              G^[Y, X] := P[CY, CX];
          Continue;
        end;
        D00 := P[CY, CX] - G^[CY * HeightStep, CX * HeightStep];
        D10 := P[CY + 1, CX] - G^[(CY + 1) * HeightStep, CX * HeightStep];
        D01 := P[CY, CX + 1] - G^[CY * HeightStep, (CX + 1) * HeightStep];
        D11 := P[CY + 1, CX + 1] - G^[(CY + 1) * HeightStep, (CX + 1) * HeightStep];
        for Y := CY * HeightStep to Y2 do
        begin
          A := (D10 - D00) * (Y - CY * HeightStep) / HeightStep + D00;
          B := (D11 - D01) * (Y - CY * HeightStep) / HeightStep + D01;
          for X := CX * HeightStep to X2 do
            G^[Y, X] := G^[Y, X] + (B - A) * (X - CX * HeightStep) / HeightStep + A;
        end;
      end;
  end;
  FGrids[Cell] := G;
  Result := G;
end;

{ THeightStore }

constructor THeightStore.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
  FMaps := TList.Create;
end;

destructor THeightStore.Destroy;
begin
  Clear;
  FNames.Free;
  FMaps.Free;
  inherited Destroy;
end;

procedure THeightStore.Clear;
var
  I: Integer;
begin
  for I := 0 to FMaps.Count - 1 do TTerrainMap(FMaps[I]).Free;
  FMaps.Clear;
  FNames.Clear;
end;

function THeightStore.Count: Integer;
begin
  Result := FNames.Count;
end;

function THeightStore.AddGmap(const Data: string): Integer;
var
  Lines, Row: TStringList;
  I, R, C, K, N: Integer;
  S, W, Name, Generated: string;
  M: TTerrainMap;
  P: THeightPoints;
  Vals: array of Double;
  Names: TStringList;
  Seeds: array of Cardinal;

  procedure ReadBlock(const EndWord: string; out Rows: TStringList);
  begin
    Rows := TStringList.Create;
    while (I < Lines.Count) and (UpperCase(Trim(Lines[I])) <> EndWord) do
    begin
      if Trim(Lines[I]) <> '' then Rows.Add(Trim(Lines[I]));
      Inc(I);
    end;
    Inc(I);
  end;

var
  Block: TStringList;
begin
  Result := 0;
  M := TTerrainMap.Create;
  Lines := TStringList.Create;
  Row := TStringList.Create;
  Names := TStringList.Create;
  try
    Row.Delimiter := ',';
    Row.StrictDelimiter := True;
    Lines.Text := StringReplace(Data, #13, '', [rfReplaceAll]);
    Generated := '';
    SetLength(Vals, 0);
    SetLength(Seeds, 0);
    I := 0;
    while I < Lines.Count do
    begin
      S := Trim(Lines[I]);
      Inc(I);
      W := UpperCase(Copy(S, 1, Pos(' ', S + ' ') - 1));
      if W = 'WIDTH' then M.FW := StrToIntDef(Trim(Copy(S, 6, MaxInt)), 0)
      else if W = 'HEIGHT' then M.FH := StrToIntDef(Trim(Copy(S, 7, MaxInt)), 0)
      else if W = 'GENERATED' then Generated := Trim(Copy(S, 10, MaxInt))
      else if W = 'GENSEED' then M.FSeed := Cardinal(StrToInt64Def(Trim(Copy(S, 8, MaxInt)), 0))
      else if W = 'LEVHEIGHT' then
        M.FLevHeight := StrToFloatDef(Trim(Copy(S, 10, MaxInt)), 0, DefaultFormatSettings)
      else if W = 'LEVCHAOS' then
        M.FLevChaos := StrToFloatDef(Trim(Copy(S, 9, MaxInt)), 0, DefaultFormatSettings)
      else if W = 'LEVELNAMES' then
      begin
        ReadBlock('LEVELNAMESEND', Block);
        for R := 0 to Block.Count - 1 do
        begin
          Row.DelimitedText := Block[R];
          for C := 0 to Row.Count - 1 do
            Names.Add(LowerCase(Trim(AnsiDequotedStr(Trim(Row[C]), '"'))));
        end;
        Block.Free;
      end
      else if W = 'HEIGHTMAP' then
      begin
        ReadBlock('HEIGHTMAPEND', Block);
        SetLength(Vals, 0);
        for R := 0 to Block.Count - 1 do
        begin
          Row.DelimitedText := Block[R];
          for C := 0 to Row.Count - 1 do
          begin
            SetLength(Vals, Length(Vals) + 1);
            Vals[High(Vals)] := StrToFloatDef(Trim(Row[C]), 0, DefaultFormatSettings);
          end;
        end;
        Block.Free;
        M.FHasMap := True;
      end
      else if W = 'RANDOMSEEDS' then
      begin
        ReadBlock('RANDOMSEEDSEND', Block);
        for R := 0 to Block.Count - 1 do
        begin
          Row.DelimitedText := Block[R];
          for C := 0 to Row.Count - 1 do
          begin
            SetLength(Seeds, Length(Seeds) + 1);
            Seeds[High(Seeds)] := Cardinal(StrToInt64Def(Trim(Row[C]), 0));
          end;
        end;
        Block.Free;
      end;
    end;
    if (M.FW < 0) or (M.FH < 0) or (M.FW > 256) or (M.FH > 256) then
    begin
      M.FW := 0;
      M.FH := 0;
    end;
    { a generated gmap lists no names: its cells are <base>_<column
      letter>-<row from 1><ext>, row by row (as TGmap) }
    if (Names.Count = 0) and (Generated <> '') and (M.FW <= 26) and
      (LastDelimiter('_', Generated) > 1) then
      for K := 0 to M.FW * M.FH - 1 do
        Names.Add(LowerCase(Copy(Generated, 1, LastDelimiter('_', Generated)) +
          Chr(Ord('a') + K mod M.FW) + '-' + IntToStr(K div M.FW + 1) +
          ExtractFileExt(Generated)));
    while Names.Count < M.FW * M.FH do Names.Add('');
    if Length(Vals) < (M.FW + 1) * (M.FH + 1) then M.FHasMap := False;
    if M.FHasMap then
    begin
      SetLength(M.FCorners, (M.FW + 1) * (M.FH + 1));
      for K := 0 to High(M.FCorners) do M.FCorners[K] := Vals[K];
    end;
    M.FSeeds := Copy(Seeds, 0, Length(Seeds));
    M.FCells.Assign(Names);
    { the HEIGHTS blocks, second pass: a level not among the cells gets a
      cell of its own after them }
    I := 0;
    while I < Lines.Count do
    begin
      S := Trim(Lines[I]);
      Inc(I);
      if UpperCase(Copy(S, 1, 8)) <> 'HEIGHTS ' then Continue;
      Name := Trim(Copy(S, 9, MaxInt));
      if Pos(' ', Name) > 0 then Name := Copy(Name, 1, Pos(' ', Name) - 1);
      FillChar(P, SizeOf(P), 0);
      R := 0;
      while (I < Lines.Count) and (UpperCase(Trim(Lines[I])) <> 'HEIGHTSEND') do
      begin
        if R < HeightPoints then
        begin
          Row.DelimitedText := Trim(Lines[I]);
          for C := 0 to Row.Count - 1 do
            if C < HeightPoints then
              P[R, C] := StrToFloatDef(Trim(Row[C]), 0, DefaultFormatSettings);
        end;
        Inc(R);
        Inc(I);
      end;
      Inc(I); { HEIGHTSEND }
      if Name = '' then Continue;
      K := M.FCells.IndexOf(LowerCase(Name));
      if K < 0 then K := M.FCells.Add(LowerCase(Name));
      if Length(M.FPoints) < M.FCells.Count then
      begin
        SetLength(M.FPoints, M.FCells.Count);
        SetLength(M.FHasPoints, M.FCells.Count);
      end;
      M.FPoints[K] := P;
      M.FHasPoints[K] := True;
      Inc(Result);
    end;
    SetLength(M.FPoints, M.FCells.Count);
    SetLength(M.FHasPoints, M.FCells.Count);
    SetLength(M.FGrids, M.FCells.Count);
    { a map with neither a height field nor a HEIGHTS block has no terrain }
    if not M.FHasMap and (Result = 0) then Exit;
    N := FMaps.Add(M);
    for K := 0 to M.FCells.Count - 1 do
    begin
      if M.FCells[K] = '' then Continue;
      if not M.FHasMap and not M.FHasPoints[K] then Continue;
      C := FNames.IndexOf(M.FCells[K]);
      if C >= 0 then FNames.Objects[C] := TObject(PtrInt(N * 65536 + K))
      else FNames.AddObject(M.FCells[K], TObject(PtrInt(N * 65536 + K)));
    end;
    M := nil;
  finally
    M.Free;
    Lines.Free;
    Row.Free;
    Names.Free;
  end;
end;

procedure THeightStore.AddDir(const Dir: string);
var
  SR: TSearchRec;
  F: TFileStream;
  S: string;
begin
  if Dir = '' then Exit;
  if FindFirst(WithTrailingSep(Dir) + '*.gmap', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then Continue;
      if SR.Size > 4 * 1024 * 1024 then Continue;
      { under a shared root, only this build's own maps }
      if not AssetAllowed(WithTrailingSep(Dir) + SR.Name) then Continue;
      try
        F := TFileStream.Create(WithTrailingSep(Dir) + SR.Name,
          fmOpenRead or fmShareDenyNone);
        try
          SetLength(S, F.Size);
          if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
        finally
          F.Free;
        end;
        AddGmap(S);
      except
        { an unreadable map is skipped }
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function THeightStore.Find(const Level: string): PHeightGrid;
var
  K, V: Integer;
begin
  Result := nil;
  K := FNames.IndexOf(LowerCase(ExtractFileName(Level)));
  if K < 0 then Exit;
  V := PtrInt(FNames.Objects[K]);
  Result := TTerrainMap(FMaps[V div 65536]).Build(V mod 65536);
end;

function HeightAt(const G: THeightGrid; X, Y: Double): Double;
var
  FX, FY, A, B: Double;
  C, R: Integer;
begin
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  if X > LevelCorners - 1 then X := LevelCorners - 1;
  if Y > LevelCorners - 1 then Y := LevelCorners - 1;
  C := Trunc(X);
  R := Trunc(Y);
  if C >= LevelCorners - 1 then C := LevelCorners - 2;
  if R >= LevelCorners - 1 then R := LevelCorners - 2;
  FX := X - C;
  FY := Y - R;
  A := (G[R + 1, C] - G[R, C]) * FY + G[R, C];
  B := (G[R + 1, C + 1] - G[R, C + 1]) * FY + G[R, C + 1];
  Result := (B - A) * FX + A;
end;

function LiftAt(const G: THeightGrid; X, Y: Double): Integer;
var
  H: Double;
begin
  H := HeightAt(G, X, Y);
  if H < 0 then H := 0;
  Result := Round(H * LiftPerHeight);
end;

{ 2.22's own rounding: down, after adding 0.0001 }
function Floor2(X: Double): Integer;
var
  F: Double;
begin
  F := X + 0.0001;
  Result := Trunc(F);
  if Result > F then Dec(Result);
end;

function Frac2(X: Double): Double;
var
  F: Integer;
begin
  F := Floor2(X);
  if F > X then Result := 0
  else Result := X - F;
end;

const
  { the heights where the ground's bands begin }
  BandFrom: array[0..6] of Double = (0, 3, 4, 5, 25, 55, 65);
  { the transition tile (column, row) of each corner mask: 1 bottom right,
    2 bottom left, 4 top right, 8 top left reach the band }
  Transition: array[0..15, 0..1] of Integer = (
    (7, 8), (0, 0), (2, 0), (1, 0), (0, 2), (0, 1), (3, 0), (4, 2),
    (2, 2), (4, 0), (2, 1), (3, 2), (1, 2), (4, 1), (3, 1), (1, 1));
  Band = 256;          { each band is a 256 x 256 block of the sheet }
  WaterLevel = 0.0;
  HeightFix = 24 * 16; { heights and slopes in fixed point }
  SlopeFix = 32 * 16;

procedure PickGroundTile(const C: TTileCorners; X, Y: Integer; out SX, SY: Integer);
var
  B, Mask, V: Integer;
begin
  SX := 0;
  SY := 0;
  for B := 6 downto 0 do
  begin
    Mask := 0;
    if C.H[CornerBR] >= BandFrom[B] then Inc(Mask, 1);
    if C.H[CornerBL] >= BandFrom[B] then Inc(Mask, 2);
    if C.H[CornerTR] >= BandFrom[B] then Inc(Mask, 4);
    if C.H[CornerTL] >= BandFrom[B] then Inc(Mask, 8);
    if Mask = 15 then
    begin
      SX := ((B + 1) shr 1) * Band;
      SY := ((B + 1) and 1) * Band;
      Break;
    end;
    if Mask > 0 then
    begin
      SX := (B shr 1) * Band + Band div 2 + Transition[Mask, 0] * TileSize;
      SY := (B and 1) * Band + Transition[Mask, 1] * TileSize;
      Exit;
    end;
  end;
  { a full patch: a decoration now and then, else a plain tile }
  V := Floor2(Frac2(C.H[0] + C.H[1] + C.H[2] + C.H[3]) * 1000) mod 256;
  if (V >= 0) and (V < 63) then
  begin
    Inc(V);
    Inc(SX, (V and 7) * TileSize);
    Inc(SY, (V shr 3) * TileSize);
  end
  else
  begin
    Inc(SX, (X and 3) * TileSize);
    Inc(SY, 64 + (Y and 3) * TileSize);
  end;
end;

{ (A * N) div 16, rounded down as an arithmetic shift }
function Step16(A: Int64; N: Integer): Int64; inline;
begin
  Result := SarInt64(A * N, 4);
end;

function SubSat(V, D: Integer): Cardinal; inline;
begin
  if V < D then Result := 0
  else if V - D > 255 then Result := 255
  else Result := V - D;
end;

procedure DrawGroundTile(Dest, Sheet: TGSurface; Tile: Integer;
  const C: TTileCorners; X, Y, DX, DY: Integer);
var
  H, S: array[0..3] of Integer;
  K, I, J, PX, PY, SX, SY, D, L: Integer;
  HL, HR, SL, SR, HP, Depth: Int64;
  AnyWater, AllWater: Boolean;
  Col: Cardinal;
begin
  if Sheet = nil then Exit;
  if Tile = 0 then PickGroundTile(C, X, Y, SX, SY)
  else TileSheetPos(Tile, SX, SY);
  if (SX + TileSize > Sheet.Width) or (SY + TileSize > Sheet.Height) then Exit;
  AnyWater := False;
  AllWater := True;
  for K := 0 to 3 do
  begin
    H[K] := Floor2(C.H[K] * HeightFix);
    S[K] := Floor2(C.S[K] * SlopeFix);
    if C.H[K] < WaterLevel then AnyWater := True
    else AllWater := False;
  end;
  for J := 0 to TileSize - 1 do
  begin
    PY := DY + J;
    if (PY < 0) or (PY >= Dest.Height) then Continue;
    HL := Step16(H[CornerBL] - H[CornerTL], J) + H[CornerTL];
    HR := Step16(H[CornerBR] - H[CornerTR], J) + H[CornerTR];
    SL := Step16(S[CornerBL] - S[CornerTL], J) + S[CornerTL];
    SR := Step16(S[CornerBR] - S[CornerTR], J) + S[CornerTR];
    for I := 0 to TileSize - 1 do
    begin
      PX := DX + I;
      if (PX < 0) or (PX >= Dest.Width) then Continue;
      D := 0;
      HP := 0;
      if AnyWater then HP := Step16(HR - HL, I) + HL;
      if AnyWater and (HP < 0) then
      begin
        { water: the depth darkens red and green and sets blue }
        Depth := -HP;
        if Depth >= $C00 then D := $C0
        else
        begin
          D := (Depth shr 4) and $FF;
          if Depth < $180 then D := ((Depth shr 1) and $FF) + D - $C0;
        end;
        if AllWater then Col := Sheet.Pixels[(SY + J) * Sheet.Width + SX + I]
        else Col := Sheet.Pixels[((SY and (Band - 1)) + 48 + J) * Sheet.Width +
          (SX and (Band - 1)) + I];
        if D >= -15 then K := (240 - D) and $FF else K := 255;
        Dest.Pixels[PY * Dest.Width + PX] := $FF000000 or
          (SubSat((Col shr 16) and $FF, D) shl 16) or
          (SubSat((Col shr 8) and $FF, D) shl 8) or Cardinal(K);
      end
      else
      begin
        L := SarInt64(Step16(SR - SL, I) + SL, 4) + 32;
        if L > 63 then L := 63;
        if L < 0 then L := 0;
        Col := Sheet.Pixels[(SY + J) * Sheet.Width + SX + I];
        Dest.Pixels[PY * Dest.Width + PX] := $FF000000 or
          (SubSat((Col shr 16) and $FF, L) shl 16) or
          (SubSat((Col shr 8) and $FF, L) shl 8) or SubSat(Col and $FF, L);
      end;
    end;
  end;
end;

end.
