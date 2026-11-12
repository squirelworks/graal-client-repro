{ Tiles39: 39ster's tile ids, sheet cells and tile categories.

  From Graal_analysis client-internals/precursor-mechanics-2026-11-09.md
  ("Tiles"):
  - an NW tile is a base64 pair giving a 12-bit id; the sheet is 128 x 32
    cells and each block of 512 ids moves 16 columns across (the 2.x pics1
    layout);
  - a category file holds one entry per sheet cell;
  - internally a tile packs 10 bits of column, 10 of row and 12 of
    category; the category is an index, turned into a bit later, not a
    collision mask;
  - blocking, jump and throw-through tiles count as walls.

  The category file the player's install carries is plain text, one letter
  per sheet cell, row by row: 'A' is the first category, 'B' the next, in
  the order Profile39 lists them. The file itself is never copied here;
  tests build their own. }
unit Tiles39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Profile39;

type
  { a packed tile: 10 bits column, 10 bits row, 12 bits category }
  TPackedTile39 = Cardinal;

  TCategoryTable39 = class
  private
    FCats: array[0..SheetCells - 1] of Byte;
    FLoaded: Boolean;
  public
    LastError: string;
    constructor Create;
    { Text with one letter per sheet cell (line breaks are skipped). False,
      with LastError set, when it holds fewer than 128 x 32 entries or a
      letter outside the known categories; the table is then all ground. }
    function LoadFromString(const S: string): Boolean;
    function LoadFromFile(const FileName: string): Boolean;
    { the category index of a sheet cell; ground outside the sheet }
    function CellCategory(Col, Row: Integer): Integer;
    { the category index of a 12-bit tile id }
    function TileCategory(Id: Integer): Integer;
    property Loaded: Boolean read FLoaded;
  end;

{ The sheet cell of a 12-bit tile id. }
procedure TileCell(Id: Integer; out Col, Row: Integer);
{ The base64 pair of an NW board as a 12-bit id; -1 for a bad character. }
function NwPairId(C1, C2: Char): Integer;
function PackTile(Col, Row, Category: Integer): TPackedTile39;
function PackedCol(T: TPackedTile39): Integer;
function PackedRow(T: TPackedTile39): Integer;
function PackedCategory(T: TPackedTile39): Integer;
{ The bit a category index turns into when a tile is tested. }
function CategoryBit(Category: Integer): Cardinal;
{ Blocking, jump and throw-through count as walls. }
function CategoryIsWall(Category: Integer): Boolean;

implementation

uses
  SysUtils, Classes;

const
  B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

procedure TileCell(Id: Integer; out Col, Row: Integer);
begin
  Id := Id and ((1 shl TileIdBits) - 1);
  Col := (Id mod 16) + (Id div TileIdBlock) * TileIdBlockCols;
  Row := (Id div 16) mod SheetRows;
end;

function NwPairId(C1, C2: Char): Integer;
var
  A, B: Integer;
begin
  A := Pos(C1, B64) - 1;
  B := Pos(C2, B64) - 1;
  if (A < 0) or (B < 0) then Result := -1
  else Result := A * 64 + B;
end;

function PackTile(Col, Row, Category: Integer): TPackedTile39;
begin
  Result := (Cardinal(Col) and $3FF) or ((Cardinal(Row) and $3FF) shl 10) or
    ((Cardinal(Category) and $FFF) shl 20);
end;

function PackedCol(T: TPackedTile39): Integer;
begin
  Result := T and $3FF;
end;

function PackedRow(T: TPackedTile39): Integer;
begin
  Result := (T shr 10) and $3FF;
end;

function PackedCategory(T: TPackedTile39): Integer;
begin
  Result := (T shr 20) and $FFF;
end;

function CategoryBit(Category: Integer): Cardinal;
begin
  if (Category < 0) or (Category > 31) then Result := 0
  else Result := Cardinal(1) shl Category;
end;

function CategoryIsWall(Category: Integer): Boolean;
begin
  Result := (Category = Ord(tcBlocking)) or (Category = Ord(tcJump)) or
    (Category = Ord(tcThrowThrough));
end;

constructor TCategoryTable39.Create;
begin
  inherited Create;
  FillChar(FCats, SizeOf(FCats), 0);
end;

function TCategoryTable39.LoadFromString(const S: string): Boolean;
var
  I, N, C: Integer;
begin
  FillChar(FCats, SizeOf(FCats), 0);
  FLoaded := False;
  Result := False;
  N := 0;
  for I := 1 to Length(S) do
  begin
    if (S[I] = #13) or (S[I] = #10) then Continue;
    C := Ord(S[I]) - Ord('A');
    if (C < 0) or (C > Ord(High(TCategory39))) then
    begin
      LastError := Format('category table: entry %d is %s', [N, QuotedStr(S[I])]);
      FillChar(FCats, SizeOf(FCats), 0);
      Exit;
    end;
    if N < SheetCells then FCats[N] := C;
    Inc(N);
  end;
  if N < SheetCells then
  begin
    LastError := Format('category table: %d entries, %d needed', [N, SheetCells]);
    FillChar(FCats, SizeOf(FCats), 0);
    Exit;
  end;
  LastError := '';
  FLoaded := True;
  Result := True;
end;

function TCategoryTable39.LoadFromFile(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then
  begin
    LastError := 'category table: no ' + FileName;
    Exit;
  end;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(S, F.Size);
    if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
  finally
    F.Free;
  end;
  Result := LoadFromString(S);
end;

function TCategoryTable39.CellCategory(Col, Row: Integer): Integer;
begin
  if (Col < 0) or (Col >= SheetCols) or (Row < 0) or (Row >= SheetRows) then
    Result := Ord(tcGround)
  else
    Result := FCats[Row * SheetCols + Col];
end;

function TCategoryTable39.TileCategory(Id: Integer): Integer;
var
  Col, Row: Integer;
begin
  TileCell(Id, Col, Row);
  Result := CellCategory(Col, Row);
end;

end.
