{ World39: one 39ster level with the player's tile sheet and category
  table, drawn into a 640 x 480 frame.

  Everything is read from the player's own 39ster install at run time
  (common/GAssetDirs: the program's folder, graal-assets/39ster/, then
  --data): levels/<name> for levels, pics1.png for the sheet and arrays.dat
  for the category table. Nothing of the original is built in. Without a
  sheet the tiles are drawn as flat colours by category, so a level still
  shows. }
unit World39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GLevel, GSurface, Profile39, Tiles39, Anim39;

type
  TWorld39 = class
  public
    Level: TAdventureLevel;
    Categories: TCategoryTable39;
    Sheet: TGSurface;      { nil until a sheet is found }
    Screen: TGSurface;     { ViewW x ViewH }
    { the camera anchor, level pixels (the player's 16-pixel box) }
    AnchorX, AnchorY: Integer;
    { the same position with its fraction, which movement keeps }
    PosX, PosY: Double;
    Facing: TFacing39;
    { the player's ganis and the one playing }
    Ganis: TGaniSet39;
    Anim: TAnimState39;
    LastError: string;
    constructor Create;
    destructor Destroy; override;
    { the sheet and category table from the asset roots; False if either
      is missing (the world still draws, with flat colours / all ground) }
    function LoadInstall: Boolean;
    { a level by its name under levels/, or a path; resets nothing else }
    function LoadLevel(const Name: string): Boolean;
    { the category index of board tile (TX, TY); blocking outside the level }
    function CategoryAt(TX, TY: Integer): Integer;
    { True if board tile (TX, TY) is blocking, jump or throw-through }
    function IsWall(TX, TY: Integer): Boolean;
    { puts the player's box at level pixel (X, Y) }
    procedure PlaceAt(X, Y: Double);
    { one update with the held directions DX, DY (-1, 0, 1) and time factor
      TF; turns to face the move; True if the box moved }
    function Step(DX, DY: Integer; TF: Double): Boolean;
    { One frame of play: Attack starts the sword (once it is not already
      swinging); while it swings the player stands. Otherwise the held
      directions walk (walk gani) or the player stands (idle). Then the
      animation advances by TF. }
    procedure Update(DX, DY: Integer; Attack: Boolean; TF: Double);
    { the frame for the current anchor }
    procedure Draw;
  end;

implementation

uses
  SysUtils, GAssetDirs, Camera39, Move39;

const
  FlatColour: array[TCategory39] of Cardinal = ($FF3C8C3C, $FF505050,
    $FF6E9E3C, $FF2850C8, $FF8C6428, $FFB4B464, $FF506432, $FF5A8CDC,
    $FFC83C14);

constructor TWorld39.Create;
begin
  inherited Create;
  Level := TAdventureLevel.Create;
  Categories := TCategoryTable39.Create;
  Ganis := TGaniSet39.Create;
  Anim.Gani := gIdle;
  Anim.Pos := 0;
  Screen := TGSurface.Create(ViewW, ViewH);
  PlaceAt(StartX, StartY);
  Facing := StartFacing;
end;

destructor TWorld39.Destroy;
begin
  Screen.Free;
  Ganis.Free;
  Sheet.Free;
  Categories.Free;
  Level.Free;
  inherited Destroy;
end;

function TWorld39.LoadInstall: Boolean;
var
  P: string;
begin
  Result := True;
  FreeAndNil(Sheet);
  P := AssetPath('pics1.png');
  if P <> '' then
  begin
    Sheet := TGSurface.Create(1, 1);
    if not LoadImageFile(P, Sheet) then FreeAndNil(Sheet);
  end;
  if Sheet = nil then
  begin
    LastError := 'no pics1.png';
    Result := False;
  end;
  P := AssetPath('arrays.dat');
  if (P = '') or not Categories.LoadFromFile(P) then
  begin
    if P = '' then LastError := 'no arrays.dat' else LastError := Categories.LastError;
    Result := False;
  end;
  if not Ganis.LoadInstall then
  begin
    LastError := 'missing ganis under levels/';
    Result := False;
  end;
end;

function TWorld39.LoadLevel(const Name: string): Boolean;
var
  P: string;
begin
  if FileExists(Name) then P := Name
  else P := AssetPath('levels/' + Name);
  if P = '' then
  begin
    LastError := 'no level ' + Name;
    Result := False;
    Exit;
  end;
  Result := Level.LoadFromFile(P);
  if Result then Level.Name := ExtractFileName(P)
  else LastError := Level.LastError;
end;

function TWorld39.CategoryAt(TX, TY: Integer): Integer;
begin
  if (TX < 0) or (TY < 0) or (TX >= BoardW) or (TY >= BoardH) then
    Result := Ord(tcBlocking)
  else
    Result := Categories.TileCategory(Level.Tile(TX, TY));
end;

function TWorld39.IsWall(TX, TY: Integer): Boolean;
begin
  Result := CategoryIsWall(CategoryAt(TX, TY));
end;

procedure TWorld39.PlaceAt(X, Y: Double);
begin
  PosX := X;
  PosY := Y;
  AnchorX := Trunc(X);
  AnchorY := Trunc(Y);
end;

function TWorld39.Step(DX, DY: Integer; TF: Double): Boolean;
var
  X, Y: Double;
begin
  { the last of up, left, down, right that is held }
  if DY < 0 then Facing := fUp;
  if DX < 0 then Facing := fLeft;
  if DY > 0 then Facing := fDown;
  if DX > 0 then Facing := fRight;
  X := PosX;
  Y := PosY;
  Result := MovePlayer(IsWall, X, Y, DX, DY, TF, MoveStep, BoardW * TilePx, BoardH * TilePx);
  PlaceAt(X, Y);
end;

procedure TWorld39.Update(DX, DY: Integer; Attack: Boolean; TF: Double);
begin
  if Attack and (Anim.Gani <> gSword) then PlayGani(Anim, gSword);
  if Anim.Gani <> gSword then
  begin
    Step(DX, DY, TF);
    if (DX <> 0) or (DY <> 0) then PlayGani(Anim, gWalk)
    else PlayGani(Anim, gIdle);
  end;
  AdvanceAnim(Anim, Ganis, TF);
end;

procedure TWorld39.Draw;
var
  OX, OY, TX, TY, DX, DY, C: Integer;
begin
  Screen.Fill($FF000000);
  CameraOrigin(AnchorX, AnchorY, BoardW * TilePx, BoardH * TilePx, ViewW, ViewH, OX, OY);
  for TY := 0 to BoardH - 1 do
  begin
    DY := TY * TilePx - OY;
    if (DY <= -TilePx) or (DY >= ViewH) then Continue;
    for TX := 0 to BoardW - 1 do
    begin
      DX := TX * TilePx - OX;
      if (DX <= -TilePx) or (DX >= ViewW) then Continue;
      if Sheet <> nil then
        DrawTile(Screen, Sheet, Level.Tile(TX, TY), DX, DY)
      else
      begin
        C := CategoryAt(TX, TY);
        Screen.FillRect(DX, DY, TilePx, TilePx, FlatColour[TCategory39(C)]);
      end;
    end;
  end;
  { the character, its pieces placed by the gani playing; without the
    install's ganis, the 16-pixel box it stands on }
  if Ganis.Ganis[Anim.Gani] <> nil then
    Ganis.DrawCharacter(Screen, Anim, Facing, AnchorX - OX + CharOriginDX,
      AnchorY - OY + CharOriginDY)
  else
    Screen.FillRect(AnchorX - OX, AnchorY - OY, TilePx, TilePx, $FFFFFFFF);
end;

end.
