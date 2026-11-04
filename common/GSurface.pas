{ GSurface: a 32-bit software surface, and the tile sheet blit.

  2.05 draws through DelphiX (DirectDraw surfaces). DelphiX does not build
  under Free Pascal or outside Windows, so the rebuild draws into this
  surface instead and hands the finished frame to a front end (a window, or
  a .bmp file for tests). Everything the frame function decides (what to
  draw, in which order, where) is above this unit; only the pixel pushing
  is here.

  Tile sheet layout (graal_analysis client-internals/client-assets.md):
  tile t is at column (t mod 16) + (t div 512) * 16, row (t div 16) mod 32,
  16x16 pixels, on pics1. }
unit GSurface;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  TileSize = 16;

type
  TPixels = array of Cardinal; { $AARRGGBB }

  TGSurface = class
  public
    Width, Height: Integer;
    Pixels: TPixels;
    { Set for palette images loaded with LoadImageIndexed: the index of each
      pixel and the file's palette, so a body can be recoloured. }
    Indices: array of Byte;
    Palette: TPixels;
    constructor Create(AWidth, AHeight: Integer);
    procedure SetSize(AWidth, AHeight: Integer);
    procedure Fill(Color: Cardinal);
    procedure FillRect(X, Y, W, H: Integer; Color: Cardinal);
    function GetPixel(X, Y: Integer): Cardinal;
    { Copies a rectangle; source pixels with alpha 0 are skipped, the
      DirectDraw colour-key behaviour of the original sheets. }
    procedure Blit(Src: TGSurface; SX, SY, W, H, DX, DY: Integer);
    procedure SaveBMP(const FileName: string);
    function LoadBMP(const FileName: string): Boolean;
    { Rebuilds Pixels from Indices with palette entry Slot[i] replaced by
      Color[i]. Needs an indexed image. }
    procedure Recolor(const Slots: array of Integer; const Colors: array of Cardinal);
  end;

procedure TileSheetPos(Tile: Integer; out SX, SY: Integer);
{ Draws tile Tile of Sheet at (DX, DY) on Dest. }
procedure DrawTile(Dest, Sheet: TGSurface; Tile, DX, DY: Integer);
{ Loads .bmp everywhere, and .png / .gif through fcl-image under Free Pascal. }
function LoadImageFile(const FileName: string; Dest: TGSurface): Boolean;
{ Same, keeping the palette indices (palette .png / .gif only). }
function LoadImageIndexed(const FileName: string; Dest: TGSurface): Boolean;

implementation

uses
  SysUtils, Classes
{$IFDEF FPC}
  , FPImage, FPReadPNG, FPReadGIF, FPReadBMP
{$ENDIF};

procedure TileSheetPos(Tile: Integer; out SX, SY: Integer);
begin
  SX := ((Tile mod 16) + (Tile div 512) * 16) * TileSize;
  SY := ((Tile div 16) mod 32) * TileSize;
end;

procedure DrawTile(Dest, Sheet: TGSurface; Tile, DX, DY: Integer);
var
  SX, SY: Integer;
begin
  TileSheetPos(Tile, SX, SY);
  Dest.Blit(Sheet, SX, SY, TileSize, TileSize, DX, DY);
end;

{ TGSurface }

constructor TGSurface.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  SetSize(AWidth, AHeight);
end;

procedure TGSurface.SetSize(AWidth, AHeight: Integer);
begin
  Width := AWidth;
  Height := AHeight;
  SetLength(Pixels, Width * Height);
end;

procedure TGSurface.Fill(Color: Cardinal);
var
  I: Integer;
begin
  for I := 0 to High(Pixels) do Pixels[I] := Color;
end;

procedure TGSurface.FillRect(X, Y, W, H: Integer; Color: Cardinal);
var
  I, J: Integer;
begin
  for J := Y to Y + H - 1 do
    if (J >= 0) and (J < Height) then
      for I := X to X + W - 1 do
        if (I >= 0) and (I < Width) then
          Pixels[I + J * Width] := Color;
end;

function TGSurface.GetPixel(X, Y: Integer): Cardinal;
begin
  if (X < 0) or (Y < 0) or (X >= Width) or (Y >= Height) then
    Result := 0
  else
    Result := Pixels[X + Y * Width];
end;

procedure TGSurface.Blit(Src: TGSurface; SX, SY, W, H, DX, DY: Integer);
var
  I, J, X, Y: Integer;
  C: Cardinal;
begin
  for J := 0 to H - 1 do
  begin
    Y := DY + J;
    if (Y < 0) or (Y >= Height) or (SY + J < 0) or (SY + J >= Src.Height) then Continue;
    for I := 0 to W - 1 do
    begin
      X := DX + I;
      if (X < 0) or (X >= Width) or (SX + I < 0) or (SX + I >= Src.Width) then Continue;
      C := Src.Pixels[SX + I + (SY + J) * Src.Width];
      if (C shr 24) <> 0 then
        Pixels[X + Y * Width] := C;
    end;
  end;
end;

procedure PutLE(S: TStream; V: Cardinal; Bytes: Integer);
var
  B: Byte;
  I: Integer;
begin
  for I := 1 to Bytes do
  begin
    B := V and $FF;
    S.WriteBuffer(B, 1);
    V := V shr 8;
  end;
end;

procedure TGSurface.SaveBMP(const FileName: string);
var
  F: TFileStream;
  Row: array of Byte;
  X, Y, Stride: Integer;
  C: Cardinal;
begin
  Stride := (Width * 3 + 3) and not 3;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(PChar('BM')^, 2);
    PutLE(F, 54 + Stride * Height, 4);
    PutLE(F, 0, 4);
    PutLE(F, 54, 4);
    PutLE(F, 40, 4);
    PutLE(F, Width, 4);
    PutLE(F, Height, 4);
    PutLE(F, 1, 2);
    PutLE(F, 24, 2);
    PutLE(F, 0, 4);
    PutLE(F, Stride * Height, 4);
    PutLE(F, 2835, 4);
    PutLE(F, 2835, 4);
    PutLE(F, 0, 4);
    PutLE(F, 0, 4);
    SetLength(Row, Stride);
    for Y := Height - 1 downto 0 do
    begin
      FillChar(Row[0], Stride, 0);
      for X := 0 to Width - 1 do
      begin
        C := Pixels[X + Y * Width];
        Row[X * 3] := C and $FF;
        Row[X * 3 + 1] := (C shr 8) and $FF;
        Row[X * 3 + 2] := (C shr 16) and $FF;
      end;
      F.WriteBuffer(Row[0], Stride);
    end;
  finally
    F.Free;
  end;
end;

function GetLE(const S: string; P, Bytes: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := Bytes - 1 downto 0 do
    Result := (Result shl 8) or Ord(S[P + I]);
end;

{ Uncompressed 24- and 32-bit BMP only: enough for test sheets. }
function TGSurface.LoadBMP(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
  Off, W, H, Bpp, Stride, X, Y, P: Integer;
  BottomUp: Boolean;
begin
  Result := False;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(S, F.Size);
    if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
  finally
    F.Free;
  end;
  if (Length(S) < 54) or (Copy(S, 1, 2) <> 'BM') then Exit;
  Off := GetLE(S, 11, 4);
  W := GetLE(S, 19, 4);
  H := GetLE(S, 23, 4);
  BottomUp := H > 0;
  H := Abs(H);
  Bpp := GetLE(S, 29, 2);
  if (Bpp <> 24) and (Bpp <> 32) then Exit;
  Stride := (W * (Bpp div 8) + 3) and not 3;
  SetSize(W, H);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      if BottomUp then
        P := Off + 1 + (H - 1 - Y) * Stride + X * (Bpp div 8)
      else
        P := Off + 1 + Y * Stride + X * (Bpp div 8);
      Pixels[X + Y * W] := $FF000000 or (Cardinal(Ord(S[P + 2])) shl 16) or
        (Cardinal(Ord(S[P + 1])) shl 8) or Cardinal(Ord(S[P]));
    end;
  Result := True;
end;

procedure TGSurface.Recolor(const Slots: array of Integer; const Colors: array of Cardinal);
var
  Pal: TPixels;
  I: Integer;
begin
  if Length(Indices) <> Width * Height then Exit;
  Pal := Copy(Palette, 0, Length(Palette));
  for I := 0 to High(Slots) do
    if (Slots[I] >= 0) and (Slots[I] < Length(Pal)) and (I <= High(Colors)) then
      Pal[Slots[I]] := Colors[I];
  for I := 0 to High(Indices) do
    if Indices[I] < Length(Pal) then
      Pixels[I] := Pal[Indices[I]]
    else
      Pixels[I] := 0;
end;

function LoadAny(const FileName: string; Dest: TGSurface; Indexed: Boolean): Boolean;
{$IFDEF FPC}
var
  Img: TFPMemoryImage;
  X, Y: Integer;
  C: TFPColor;
{$ENDIF}
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  if LowerCase(ExtractFileExt(FileName)) = '.bmp' then
  begin
    Result := Dest.LoadBMP(FileName);
    Exit;
  end;
{$IFDEF FPC}
  Img := TFPMemoryImage.Create(0, 0);
  try
    Img.UsePalette := Indexed;
    try
      Img.LoadFromFile(FileName);
    except
      Exit;
    end;
    Dest.SetSize(Img.Width, Img.Height);
    for Y := 0 to Img.Height - 1 do
      for X := 0 to Img.Width - 1 do
      begin
        C := Img.Colors[X, Y];
        Dest.Pixels[X + Y * Img.Width] := (Cardinal(C.alpha shr 8) shl 24) or
          (Cardinal(C.red shr 8) shl 16) or (Cardinal(C.green shr 8) shl 8) or
          Cardinal(C.blue shr 8);
      end;
    SetLength(Dest.Indices, 0);
    SetLength(Dest.Palette, 0);
    if Indexed and Img.UsePalette and (Img.Palette.Count <= 256) then
    begin
      SetLength(Dest.Palette, Img.Palette.Count);
      for X := 0 to Img.Palette.Count - 1 do
      begin
        C := Img.Palette.Color[X];
        Dest.Palette[X] := (Cardinal(C.alpha shr 8) shl 24) or
          (Cardinal(C.red shr 8) shl 16) or (Cardinal(C.green shr 8) shl 8) or
          Cardinal(C.blue shr 8);
      end;
      SetLength(Dest.Indices, Img.Width * Img.Height);
      for Y := 0 to Img.Height - 1 do
        for X := 0 to Img.Width - 1 do
          Dest.Indices[X + Y * Img.Width] := Img.Pixels[X, Y];
    end;
    Result := True;
  finally
    Img.Free;
  end;
{$ENDIF}
end;

function LoadImageFile(const FileName: string; Dest: TGSurface): Boolean;
begin
  Result := LoadAny(FileName, Dest, False);
end;

function LoadImageIndexed(const FileName: string; Dest: TGSurface): Boolean;
begin
  Result := LoadAny(FileName, Dest, True) and (Length(Dest.Indices) = Dest.Width * Dest.Height);
end;

end.
