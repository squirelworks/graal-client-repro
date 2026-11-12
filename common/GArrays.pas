{ GArrays: arrays.dat, the 25 built-in tile and sprite tables.

  Format (graal_analysis formats/arrays-and-signatures.md): big-endian
  32-bit integers. Each array starts with a header word
  (kind shl 16) or count; kind 0 = count ints follow, kind 1 = count nested
  arrays follow. The client reads exactly 25 arrays, in order, at start-up,
  and quits with "File not found" if the file is missing.

  Arrays 0 and 1 are the passable tile lists of the walking test. }
unit GArrays;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TGArray = class
  public
    Values: array of Integer;   { kind 0 }
    Items: array of TGArray;    { kind 1 }
    destructor Destroy; override;
    function Contains(V: Integer): Boolean;
  end;

  TGArrays = class
  private
    FPassable: array[0..4095] of Boolean;
  public
    Lists: array[0..24] of TGArray;
    Loaded: Boolean;
    destructor Destroy; override;
    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromString(const Data: string): Boolean;
    { Walking test: a tile is free when it is in array 0 or array 1. }
    function TilePassable(Tile: Integer): Boolean;
    { A table of 2 x 2 objects (9 cut, 10 what a cut leaves, 11 lift, 12
      what a lift leaves, 14 the open chest): the number of objects, and
      tile (Col, Row) of object I, or -1 when the table lacks it. }
    function ObjectCount(List: Integer): Integer;
    function ObjectTile(List, I, Col, Row: Integer): Integer;
    { Sprite I of the sprite table (array 24): its rectangle in pixels.
      Each entry packs h / 2 in bits 0-5, w / 2 in 6-11, y / 2 in 12-21
      and x in 23-31 (the HUD's sprites 17, 145 and 325 and the item
      sprites read back to the rectangles the client draws). }
    function SpriteRect(I: Integer; out X, Y, W, H: Integer): Boolean;
  end;

implementation

uses
  GCompat,
  SysUtils, Classes;

destructor TGArray.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Items) do Items[I].Free;
  inherited Destroy;
end;

function TGArray.Contains(V: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to High(Values) do
    if Values[I] = V then Exit;
  Result := False;
end;

destructor TGArrays.Destroy;
var
  I: Integer;
begin
  for I := 0 to 24 do Lists[I].Free;
  inherited Destroy;
end;

function TGArrays.LoadFromFile(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(S, F.Size);
    if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
  finally
    F.Free;
  end;
  Result := LoadFromString(S);
end;

function TGArrays.LoadFromString(const Data: string): Boolean;
var
  P: Integer;
  Bad: Boolean;

  function ReadInt: Integer;
  begin
    if P + 3 > Length(Data) then
    begin
      Bad := True;
      Result := 0;
      Exit;
    end;
    Result := (Ord(Data[P]) shl 24) or (Ord(Data[P + 1]) shl 16) or
      (Ord(Data[P + 2]) shl 8) or Ord(Data[P + 3]);
    Inc(P, 4);
  end;

  function ReadArray(Depth: Integer): TGArray;
  var
    H, Kind, Count, I: Integer;
  begin
    Result := TGArray.Create;
    H := ReadInt;
    Kind := (H shr 16) and $FFFF;
    Count := H and $FFFF;
    if Bad or (Depth > 8) then Exit;
    if Kind = 0 then
    begin
      SetLength(Result.Values, Count);
      for I := 0 to Count - 1 do
        Result.Values[I] := ReadInt;
    end
    else
    begin
      SetLength(Result.Items, Count);
      for I := 0 to Count - 1 do
        Result.Items[I] := ReadArray(Depth + 1);
    end;
  end;

var
  I, J: Integer;
begin
  for I := 0 to 24 do FreeAndNil(Lists[I]);
  P := 1;
  Bad := False;
  for I := 0 to 24 do
    Lists[I] := ReadArray(0);
  Loaded := not Bad;
  FillChar(FPassable, SizeOf(FPassable), 0);
  if Loaded then
    for I := 0 to 1 do
      for J := 0 to High(Lists[I].Values) do
        if (Lists[I].Values[J] >= 0) and (Lists[I].Values[J] < 4096) then
          FPassable[Lists[I].Values[J]] := True;
  Result := Loaded;
end;

function TGArrays.ObjectCount(List: Integer): Integer;
begin
  Result := 0;
  if (List >= 0) and (List <= 24) and (Lists[List] <> nil) then
    Result := Length(Lists[List].Items);
end;

function TGArrays.ObjectTile(List, I, Col, Row: Integer): Integer;
var
  A: TGArray;
begin
  Result := -1;
  if (I < 0) or (I >= ObjectCount(List)) then Exit;
  A := Lists[List].Items[I];
  if (Col < 0) or (Col > High(A.Items)) then Exit;
  A := A.Items[Col];
  if (Row < 0) or (Row > High(A.Values)) then Exit;
  Result := A.Values[Row];
end;

function TGArrays.SpriteRect(I: Integer; out X, Y, W, H: Integer): Boolean;
var
  V: Cardinal;
begin
  X := 0;
  Y := 0;
  W := 0;
  H := 0;
  Result := False;
  if (Lists[24] = nil) or (I < 0) or (I > High(Lists[24].Values)) then Exit;
  V := Cardinal(Lists[24].Values[I]);
  H := Integer(V and 63) * 2;
  W := Integer((V shr 6) and 63) * 2;
  Y := Integer((V shr 12) and 1023) * 2;
  X := Integer(V shr 23);
  Result := (W > 0) and (H > 0);
end;

function TGArrays.TilePassable(Tile: Integer): Boolean;
begin
  if not Loaded then
    Result := True { no table: walk anywhere, and say so at start-up }
  else
    Result := (Tile >= 0) and (Tile < 4096) and FPassable[Tile];
end;

end.
