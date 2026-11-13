{ Terrain221: the height-shaped ground of 2.22 (shared with 2.17.1)'s new-world maps.

  A gmap of the generator form (formats/grmap001.txt) carries, per level, a
  9 x 9 grid of heights: one point every 8 tiles, corners shared with the
  neighbours ("HEIGHTS <level> 8 8" ... "HEIGHTSEND"). 2.22 (shared with 2.17.1) draws tile 0 of
  a level with such a grid as ground picked by height instead of the tile
  itself.

  What is drawn here was measured on the real 2.22 (shared with 2.17.1) under Wine, by setting
  the offline tutorial's grid to one height at a time and comparing
  screenshots with picso.png (2026-11-04):

  - below 0: water, darker the deeper it is;
  - 0 to 3: sand; about 4: sand and grass mixed; 5 and up: grass;
  - flat ground is drawn about 30 levels darker than the sheet in each
    colour channel, and slopes are lit from the upper left.

  The height between grid points is blended linearly here; 2.22 (shared with 2.17.1) adds a
  seeded displacement (client-internals/newworld-betas.md) that is not
  reproduced, and the band edges are dithered rather than copied. }
unit Terrain221;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat, Classes, GSplit, SysUtils, GPaths, GNumText, GSurface, GAssetDirs;

const
  HeightPoints = 9;   { per side of a level's grid }
  HeightStep = 8;     { tiles between grid points }

type
  THeightGrid = array[0..HeightPoints - 1, 0..HeightPoints - 1] of Single; { [row, col] }

  THeightStore = class
  private
    FNames: TStringList; { lower-case level name -> index into FGrids }
    FGrids: array of THeightGrid;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Reads every HEIGHTS block of a gmap text. Returns how many were read. }
    function AddGmap(const Data: string): Integer;
    { Reads the HEIGHTS blocks of every .gmap in Dir. }
    procedure AddDir(const Dir: string);
    function Find(const Level: string; out Grid: THeightGrid): Boolean;
    function Count: Integer;
  end;

{ The height at (X, Y) in tiles, 0..64 across the level. }
function HeightAt(const G: THeightGrid; X, Y: Double): Double;

{ Draws the ground of tile (TX, TY) of a level with grid G at (DX, DY) on
  Dest, from the new-order sheet Sheet (picso.png and kin). }
procedure DrawTerrainTile(Dest, Sheet: TGSurface; const G: THeightGrid;
  TX, TY, DX, DY: Integer);

{ Darkens a tile already drawn at (DX, DY) the way the ground around it is
  lit, so that tiles on the ground (paths, flowers) sit in it. }
procedure ShadeTile(Dest: TGSurface; const G: THeightGrid; TX, TY, DX, DY: Integer);

implementation

constructor THeightStore.Create;
begin
  inherited Create;
  FNames := TStringList.Create;
end;

destructor THeightStore.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure THeightStore.Clear;
begin
  FNames.Clear;
  SetLength(FGrids, 0);
end;

function THeightStore.Count: Integer;
begin
  Result := FNames.Count;
end;

function THeightStore.AddGmap(const Data: string): Integer;
var
  Lines, Row: TStringList;
  I, R, C, K: Integer;
  S, Name: string;
  G: THeightGrid;
begin
  Result := 0;
  Lines := TStringList.Create;
  Row := TStringList.Create;
  try
    Lines.Text := StringReplace(Data, #13, '', [rfReplaceAll]);
    I := 0;
    while I < Lines.Count do
    begin
      S := Trim(Lines[I]);
      Inc(I);
      if UpperCase(Copy(S, 1, 8)) <> 'HEIGHTS ' then Continue;
      Name := Trim(Copy(S, 9, MaxInt));
      if Pos(' ', Name) > 0 then Name := Copy(Name, 1, Pos(' ', Name) - 1);
      FillChar(G, SizeOf(G), 0);
      R := 0;
      while (I < Lines.Count) and (UpperCase(Trim(Lines[I])) <> 'HEIGHTSEND') do
      begin
        if R < HeightPoints then
        begin
          SplitDelimited(Trim(Lines[I]), ',', Row);
          for C := 0 to Row.Count - 1 do
            if C < HeightPoints then
              G[R, C] := DotTextToFloatDef(Trim(Row[C]), 0);
        end;
        Inc(R);
        Inc(I);
      end;
      Inc(I); { HEIGHTSEND }
      if Name = '' then Continue;
      K := FNames.IndexOf(LowerCase(Name));
      if K < 0 then
      begin
        K := Length(FGrids);
        SetLength(FGrids, K + 1);
        FNames.AddObject(LowerCase(Name), TObject(PtrInt(K)));
      end
      else
        K := PtrInt(FNames.Objects[K]);
      FGrids[K] := G;
      Inc(Result);
    end;
  finally
    Lines.Free;
    Row.Free;
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

function THeightStore.Find(const Level: string; out Grid: THeightGrid): Boolean;
var
  K: Integer;
begin
  K := FNames.IndexOf(LowerCase(ExtractFileName(Level)));
  Result := K >= 0;
  if Result then Grid := FGrids[PtrInt(FNames.Objects[K])]
  else FillChar(Grid, SizeOf(Grid), 0);
end;

function HeightAt(const G: THeightGrid; X, Y: Double): Double;
var
  GX, GY, FX, FY: Double;
  C, R: Integer;
begin
  GX := X / HeightStep;
  GY := Y / HeightStep;
  if GX < 0 then GX := 0;
  if GY < 0 then GY := 0;
  if GX > HeightPoints - 1 then GX := HeightPoints - 1;
  if GY > HeightPoints - 1 then GY := HeightPoints - 1;
  C := Trunc(GX);
  R := Trunc(GY);
  if C >= HeightPoints - 1 then C := HeightPoints - 2;
  if R >= HeightPoints - 1 then R := HeightPoints - 2;
  FX := GX - C;
  FY := GY - R;
  Result := (G[R, C] * (1 - FX) + G[R, C + 1] * FX) * (1 - FY) +
    (G[R + 1, C] * (1 - FX) + G[R + 1, C + 1] * FX) * FY;
end;

{ A fixed noise in -0.5..0.5 per pixel, for the dithered band edges. }
function Noise(X, Y: Integer): Double;
var
  H: Cardinal;
begin
  {$PUSH}{$Q-}{$R-}
  H := Cardinal(X) * 374761393 + Cardinal(Y) * 668265263;
  H := (H xor (H shr 13)) * 1274126177;
  H := H xor (H shr 16);
  {$POP}
  Result := (H and $FFFF) / 65535 - 0.5;
end;

const
  { 128 x 128 ground patches on the new-order sheet (picso.png) }
  WaterX = 0;   WaterY = 0;
  SandX = 0;    SandY = 256;
  MixX = 256;   MixY = 256;
  GrassX = 512; GrassY = 256;
  Patch = 128;
  FlatShade = 30;
  SlopeShade = 22;   { per height step per tile }
  DepthShade = 14;   { per height step under 0 }

function ShadeChannel(V, D: Integer): Integer;
begin
  Result := V - D;
  if Result < 0 then Result := 0;
  if Result > 255 then Result := 255;
end;

function TileSlopeShade(const G: THeightGrid; TX, TY: Integer): Integer;
var
  HX, HY: Double;
begin
  HX := HeightAt(G, TX + 1.0, TY + 0.5) - HeightAt(G, TX + 0.0, TY + 0.5);
  HY := HeightAt(G, TX + 0.5, TY + 1.0) - HeightAt(G, TX + 0.5, TY + 0.0);
  Result := FlatShade + Round(-(HX + HY) * SlopeShade);
end;

procedure ShadeTile(Dest: TGSurface; const G: THeightGrid; TX, TY, DX, DY: Integer);
var
  I, J, PX, PY, D: Integer;
  Col: Cardinal;
begin
  D := TileSlopeShade(G, TX, TY);
  for J := 0 to TileSize - 1 do
  begin
    PY := DY + J;
    if (PY < 0) or (PY >= Dest.Height) then Continue;
    for I := 0 to TileSize - 1 do
    begin
      PX := DX + I;
      if (PX < 0) or (PX >= Dest.Width) then Continue;
      Col := Dest.Pixels[PY * Dest.Width + PX];
      Dest.Pixels[PY * Dest.Width + PX] := $FF000000 or
        (Cardinal(ShadeChannel((Col shr 16) and $FF, D)) shl 16) or
        (Cardinal(ShadeChannel((Col shr 8) and $FF, D)) shl 8) or
        Cardinal(ShadeChannel(Col and $FF, D));
    end;
  end;
end;

procedure DrawTerrainTile(Dest, Sheet: TGSurface; const G: THeightGrid;
  TX, TY, DX, DY: Integer);
var
  I, J, WX, WY, PX, PY, SX, SY, D, Dd, OX, OY: Integer;
  H, Hn: Double;
  Slope: Integer;
  Col: Cardinal;
begin
  if (Sheet = nil) or (Sheet.Width < GrassX + Patch) or (Sheet.Height < GrassY + Patch) then Exit;
  { the slope is taken once per tile, from the heights around its centre }
  Slope := TileSlopeShade(G, TX, TY) - FlatShade;
  for J := 0 to TileSize - 1 do
  begin
    PY := DY + J;
    if (PY < 0) or (PY >= Dest.Height) then Continue;
    WY := TY * TileSize + J;
    for I := 0 to TileSize - 1 do
    begin
      PX := DX + I;
      if (PX < 0) or (PX >= Dest.Width) then Continue;
      WX := TX * TileSize + I;
      H := HeightAt(G, WX / TileSize, WY / TileSize);
      Hn := H + Noise(WX, WY);
      D := FlatShade + Slope;
      if Hn < 0 then
      begin
        OX := WaterX;
        OY := WaterY;
        Dd := Round(-H * DepthShade);
        D := FlatShade + Dd;
      end
      else if Hn < 3.5 then
      begin
        OX := SandX;
        OY := SandY;
      end
      else if Hn < 4.75 then
      begin
        OX := MixX;
        OY := MixY;
      end
      else
      begin
        OX := GrassX;
        OY := GrassY;
      end;
      SX := OX + (WX mod Patch);
      SY := OY + (WY mod Patch);
      { the sand patch's top-left tile on picso.png is a grass tile, not
        sand: the real 2.22 (shared with 2.17.1) shows none at the grid points, so take the
        sand to its right }
      if (OX = SandX) and (OY = SandY) and (WX mod Patch < TileSize) and
        (WY mod Patch < TileSize) then Inc(SX, TileSize);
      Col := Sheet.Pixels[SY * Sheet.Width + SX];
      Dest.Pixels[PY * Dest.Width + PX] := $FF000000 or
        (Cardinal(ShadeChannel((Col shr 16) and $FF, D)) shl 16) or
        (Cardinal(ShadeChannel((Col shr 8) and $FF, D)) shl 8) or
        Cardinal(ShadeChannel(Col and $FF, D));
    end;
  end;
end;

end.
