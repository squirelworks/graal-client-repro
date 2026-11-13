{ MapNm26: the big map (the M key) and the minimap of 2.05 rev 2.

  As 2.05 rev 2 does it (graal_analysis formats/gmap.md has the file
  format, client-internals/offline-tutorial-205.md the tutorial set):

  - Two maps, each a text grid of level names and a picture:
      big map  bigmap.txt + map.png
      minimap  minimap.txt + map2.png
    Offline on the tutorial both switch to tutorialmap.txt, with
    tutorialmap.png (big) and tutorialmap2.png (mini).
    A text line is a comma list (quotes allowed); the columns are the cells
    of the first line, the rows the cell count over that.
  - A player's place on a map is in half tiles: column * 128 + 2x, row *
    128 + 2y, with x, y the player's own position (the top-left of the
    3x3 box, no centring), when its level is in the grid.
  - Big map: 56 px a level whatever the picture's size. The map key
    (M) opens it; it centres on the player's head, or on the whole map when
    the player's level is not on it, then is kept inside the map, and a map
    smaller than the view is centred. While it is open
    each held arrow scrolls it 8 px a tick and the player does not move;
    the map key closes it. The view is cleared to black, the picture drawn,
    then a 16 px head icon of every player on the map, centred on its
    place, and the player's own name under its head.
  - Minimap: drawn with the status display, its picture at x 10 with its
    bottom 18 px above the view's bottom, a level being the picture's width
    over the columns; heads as on the big map, kept above that bottom line
    (showstats bit 0x100).

  Not yet: the text 2.05 writes at (20, 20) on the big map, names of the
  players under the mouse, the small (12 px) head icons, chat marks on the
  minimap, and setmap / setminimap from scripts (no GS1 engine yet). }
unit MapNm26;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface, Adventure, GCompat;

const
  BigMapCell = 56;        { px a level on the big map }
  MapScrollStep = 8;      { px a tick while an arrow is held }
  MinimapLeft = 10;
  MinimapBottom = 18;
  ShowMinimapBit = $100;

type
  TGraalMap = class
  public
    TextName, ImageName: string;
    Names: TStringList;   { the cells, row by row, normalised }
    Cols, Rows: Integer;
    Image: TGSurface;     { nil when the picture is missing }
    constructor Create;
    destructor Destroy; override;
    { Reads the grid from text (one row a line). }
    procedure LoadText(const Text: string);
    { Index of a level in the grid, or -1. }
    function IndexOf(const Level: string): Integer;
    { The place of a player on Level at X, Y (tiles) in half tiles; False
      when the level is not on the map. }
    function Place(const Level: string; X, Y: Double; out PX, PY: Integer): Boolean;
  end;

var
  BigMap, MiniMap: TGraalMap;
  { The big map is open, and its scroll in px (negative: centred). }
  MapOpen: Boolean = False;
  MapScrollX, MapScrollY: Integer;

{ The maps 2.05 starts with, and the tutorial set. They are read from the
  assets the first time they are drawn. }
procedure UseDefaultMaps;
procedure UseTutorialMaps;
procedure SetBigMap(const TextName, ImageName: string);
procedure SetMiniMap(const TextName, ImageName: string);
{ The level name as the map lists it: no folder, lower case. }
function MapLevelName(const S: string): string;
{ Once a tick, before the game keys: the map key opens or closes the big
  map; while it is open the arrows scroll it and the game keys are taken
  from the game. }
procedure MapTick(G: TAdventure);
{ After the game is drawn: the big map over it when open, else the
  minimap. }
procedure DrawMaps(G: TAdventure);
{ Opens the big map with its scroll set as 2.05 does. }
procedure OpenBigMap(G: TAdventure);
procedure ClampMapScroll(ViewW, ViewH: Integer);

implementation

uses
  SysUtils, GAssetDirs, GFont;

var
  Pending: Boolean = True;   { the files are still to be read }
  Heads: TStringList = nil;  { head image name -> 16x16 TGSurface }

{ ---- TGraalMap ---- }

constructor TGraalMap.Create;
begin
  Names := TStringList.Create;
end;

destructor TGraalMap.Destroy;
begin
  Names.Free;
  Image.Free;
  inherited;
end;

function MapLevelName(const S: string): string;
var
  I: Integer;
begin
  Result := Trim(S);
  for I := Length(Result) downto 1 do
    if (Result[I] = '/') or (Result[I] = '\') then
    begin
      Delete(Result, 1, I);
      Break;
    end;
  Result := LowerCase(Result);
end;

procedure TGraalMap.LoadText(const Text: string);
var
  Lines, Cells: TStringList;
  I, J: Integer;
begin
  Names.Clear;
  Cols := 0;
  Rows := 0;
  Lines := TStringList.Create;
  Cells := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then Continue;
      Cells.CommaText := Lines[I];
      if Cols = 0 then Cols := Cells.Count;
      for J := 0 to Cells.Count - 1 do
        Names.Add(MapLevelName(Cells[J]));
    end;
    if Cols > 0 then Rows := Names.Count div Cols;
  finally
    Cells.Free;
    Lines.Free;
  end;
end;

function TGraalMap.IndexOf(const Level: string): Integer;
var
  L: string;
begin
  Result := -1;
  L := MapLevelName(Level);
  if (L = '') or (L = 'x') then Exit;
  Result := Names.IndexOf(L);
  if Result >= Cols * Rows then Result := -1;
end;

function TGraalMap.Place(const Level: string; X, Y: Double; out PX, PY: Integer): Boolean;
var
  I: Integer;
begin
  PX := -1;
  PY := -1;
  I := IndexOf(Level);
  Result := (I >= 0) and (Cols > 0);
  if not Result then Exit;
  PX := Round(X * 128 / 64 + (I mod Cols) * 128);
  PY := Round(Y * 128 / 64 + (I div Cols) * 128);
end;

{ ---- which maps ---- }

procedure SetBigMap(const TextName, ImageName: string);
begin
  BigMap.TextName := TextName;
  BigMap.ImageName := ImageName;
  Pending := True;
end;

procedure SetMiniMap(const TextName, ImageName: string);
begin
  MiniMap.TextName := TextName;
  MiniMap.ImageName := ImageName;
  Pending := True;
end;

procedure UseDefaultMaps;
begin
  SetBigMap('bigmap.txt', 'map.png');
  SetMiniMap('minimap.txt', 'map2.png');
end;

procedure UseTutorialMaps;
begin
  SetBigMap('tutorialmap.txt', 'tutorialmap.png');
  SetMiniMap('tutorialmap.txt', 'tutorialmap2.png');
end;

function ReadText(const Path: string): string;
var
  F: TFileStream;
begin
  Result := '';
  if Path = '' then Exit;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, F.Size);
      if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
    finally
      F.Free;
    end;
  except
    Result := '';
  end;
end;

{ A map's file under the asset roots: as named, or under maps/ or levels/. }
function MapFile(const Name: string): string;
begin
  Result := AssetPath(Name);
  if Result = '' then Result := AssetPath('maps/' + Name);
  if Result = '' then Result := AssetPath('levels/' + Name);
end;

procedure LoadMap(M: TGraalMap);
var
  Path: string;
begin
  M.LoadText(ReadText(MapFile(M.TextName)));
  FreeAndNil(M.Image);
  Path := MapFile(M.ImageName);
  if Path <> '' then
  begin
    M.Image := TGSurface.Create(0, 0);
    if not LoadImageFile(Path, M.Image) or (M.Image.Width = 0) then FreeAndNil(M.Image);
  end;
end;

procedure LoadPending;
begin
  if not Pending then Exit;
  Pending := False;
  LoadMap(BigMap);
  LoadMap(MiniMap);
end;

{ ---- the big map ---- }

procedure ClampMapScroll(ViewW, ViewH: Integer);
var
  W, H: Integer;
begin
  W := BigMap.Cols * BigMapCell;
  H := BigMap.Rows * BigMapCell;
  if MapScrollX > W - ViewW then MapScrollX := W - ViewW;
  if MapScrollX < 0 then MapScrollX := 0;
  if MapScrollY > H - ViewH then MapScrollY := H - ViewH;
  if MapScrollY < 0 then MapScrollY := 0;
  if W < ViewW then MapScrollX := (W - ViewW) div 2;
  if H < ViewH then MapScrollY := (H - ViewH) div 2;
end;

procedure OpenBigMap(G: TAdventure);
var
  PX, PY: Integer;
begin
  LoadPending;
  MapOpen := True;
  if BigMap.Place(G.Level.Name, G.Player.X, G.Player.Y, PX, PY) then
  begin
    MapScrollX := Round(PX * BigMapCell / 128) - ScreenW div 2;
    MapScrollY := Round(PY * BigMapCell / 128) - ScreenH div 2;
    ClampMapScroll(ScreenW, ScreenH);
  end
  else
  begin
    { not on the map: the whole map centred, without the clamp }
    MapScrollX := (BigMap.Cols * BigMapCell - ScreenW) div 2;
    MapScrollY := (BigMap.Rows * BigMapCell - ScreenH) div 2;
  end;
end;

procedure MapTick(G: TAdventure);
var
  D: Integer;
begin
  if G.MapKey then
  begin
    if MapOpen then MapOpen := False
    else OpenBigMap(G);
  end;
  G.MapKey := False;
  if not MapOpen then Exit;
  if G.Keys[DirUp] then Dec(MapScrollY, MapScrollStep);
  if G.Keys[DirLeft] then Dec(MapScrollX, MapScrollStep);
  if G.Keys[DirDown] then Inc(MapScrollY, MapScrollStep);
  if G.Keys[DirRight] then Inc(MapScrollX, MapScrollStep);
  if G.Keys[DirUp] or G.Keys[DirLeft] or G.Keys[DirDown] or G.Keys[DirRight] then
    ClampMapScroll(ScreenW, ScreenH);
  { the player stands while the map is up }
  for D := 0 to 3 do G.Keys[D] := False;
  G.ActionKey := False;
  G.AttackKey := False;
  G.ItemKey := False;
end;

{ The player's head as a 16x16 icon: the face-down head (row 2 of the
  head picture) at half size. Made once per head picture. }
function HeadIcon(G: TAdventure; P: TServerPlayer): TGSurface;
var
  Img: TGSurface;
  I, X, Y: Integer;
  Key: string;
begin
  Result := nil;
  if Heads = nil then
  begin
    Heads := TStringList.Create;
    Heads.Sorted := True;
  end;
  Key := LowerCase(P.HeadImage);
  if Key = '' then Exit;
  I := Heads.IndexOf(Key);
  if I >= 0 then
  begin
    Result := TGSurface(Heads.Objects[I]);
    Exit;
  end;
  Img := G.Assets.Image(P.HeadImage, 'head');
  if (Img <> nil) and (Img.Width >= 32) and (Img.Height >= 96) then
  begin
    Result := TGSurface.Create(16, 16);
    for Y := 0 to 15 do
      for X := 0 to 15 do
        Result.Pixels[X + Y * 16] := Img.Pixels[X * 2 + (64 + Y * 2) * Img.Width];
  end;
  Heads.AddObject(Key, Result);
end;

procedure DrawHead(G: TAdventure; P: TServerPlayer; CX, CY: Integer);
var
  H: TGSurface;
begin
  H := HeadIcon(G, P);
  if H <> nil then G.Screen.Blit(H, 0, 0, 16, 16, CX - 8, CY - 8)
  else
  begin
    { no head picture: a plain marker }
    G.Screen.FillRect(CX - 3, CY - 3, 6, 6, $FF000000);
    G.Screen.FillRect(CX - 2, CY - 2, 4, 4, $FFFFFFFF);
  end;
end;

function PlayerLevel(G: TAdventure; P: TServerPlayer): string;
begin
  if (P = G.Player) or (P.Level = '') then Result := G.Level.Name
  else Result := P.Level;
end;

{ The players to draw: the others, then the player, sorted by y. }
procedure CollectPlayers(G: TAdventure; L: TList);
var
  I, J: Integer;
  T: Pointer;
begin
  for I := 0 to G.OtherCount - 1 do
    if not G.Others[I].Gone then L.Add(G.Others[I]);
  L.Add(G.Player);
  for I := 1 to L.Count - 1 do
  begin
    T := L[I];
    J := I - 1;
    while (J >= 0) and (TServerPlayer(L[J]).Y > TServerPlayer(T).Y) do
    begin
      L[J + 1] := L[J];
      Dec(J);
    end;
    L[J + 1] := T;
  end;
end;

procedure DrawBigMap(G: TAdventure);
var
  L: TList;
  I, PX, PY, CX, CY, OwnX, OwnY: Integer;
  P: TServerPlayer;
  Own: Boolean;
  Name: string;
begin
  G.Screen.Fill($FF000000);
  if BigMap.Image <> nil then
    G.Screen.Blit(BigMap.Image, 0, 0, BigMap.Image.Width, BigMap.Image.Height,
      -MapScrollX, -MapScrollY);
  Own := False;
  OwnX := 0;
  OwnY := 0;
  L := TList.Create;
  try
    CollectPlayers(G, L);
    for I := 0 to L.Count - 1 do
    begin
      P := TServerPlayer(L[I]);
      if not BigMap.Place(PlayerLevel(G, P), P.X, P.Y, PX, PY) then Continue;
      CX := Round(PX * BigMapCell / 128) - MapScrollX;
      CY := Round(PY * BigMapCell / 128) - MapScrollY;
      DrawHead(G, P, CX, CY);
      if P = G.Player then
      begin
        Own := True;
        OwnX := CX;
        OwnY := CY;
      end;
    end;
  finally
    L.Free;
  end;
  if Own then
  begin
    Name := G.Player.Nickname;
    if Name = '' then Name := G.Player.Account;
    if Name <> '' then
    begin
      CX := OwnX - TextWidth(Name, 1) div 2;
      DrawText(G.Screen, CX + 1, OwnY + 10 + 1, Name, $FF000000, 1);
      DrawText(G.Screen, CX, OwnY + 10, Name, $FFFFFFFF, 1);
    end;
  end;
end;

procedure DrawMiniMap(G: TAdventure);
var
  L: TList;
  I, PX, PY, CX, CY, Top, Bottom: Integer;
  Scale: Double;
  P: TServerPlayer;
begin
  if (MiniMap.Image = nil) or (MiniMap.Cols <= 0) then Exit;
  { only on a level of the map's grid: the start cave and the houses
    show none, nor does a server's level off the map (2.22, 2.31 and
    2.17.1 on the 2026-11-12 lab level) }
  if MiniMap.IndexOf(G.Level.Name) < 0 then Exit;
  Bottom := ScreenH - MinimapBottom;
  Top := Bottom - MiniMap.Image.Height;
  G.Screen.Blit(MiniMap.Image, 0, 0, MiniMap.Image.Width, MiniMap.Image.Height,
    MinimapLeft, Top);
  Scale := MiniMap.Image.Width / MiniMap.Cols;
  L := TList.Create;
  try
    CollectPlayers(G, L);
    for I := 0 to L.Count - 1 do
    begin
      P := TServerPlayer(L[I]);
      if not MiniMap.Place(PlayerLevel(G, P), P.X, P.Y, PX, PY) then Continue;
      CX := Round(PX * Scale / 128) + MinimapLeft;
      CY := Round(PY * Scale / 128) + Top;
      if CY > Bottom then CY := Bottom;
      DrawHead(G, P, CX, CY);
    end;
  finally
    L.Free;
  end;
end;

procedure DrawMaps(G: TAdventure);
begin
  LoadPending;
  if MapOpen then DrawBigMap(G)
  else if G.ShowStats and ShowMinimapBit <> 0 then DrawMiniMap(G);
end;

procedure FreeHeads;
var
  I: Integer;
begin
  if Heads = nil then Exit;
  for I := 0 to Heads.Count - 1 do Heads.Objects[I].Free;
  FreeAndNil(Heads);
end;

initialization
  BigMap := TGraalMap.Create;
  MiniMap := TGraalMap.Create;
  UseDefaultMaps;

finalization
  FreeHeads;
  BigMap.Free;
  MiniMap.Free;

end.
