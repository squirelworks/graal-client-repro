{ Level6113: local levels.

  verified-from-evidence:
    the unpacked image names GR-V1.03, GR-V1.04 and GR-V1.05. It does not
    name GLEVNW01. The bytes after those magics were not recovered, so a
    file that starts with one of them is refused.
  provisional adapter:
    none.
  lab-only fixture:
    LABLVL1, a grid of floor, wall, a local start and an optional marker.
    It is not a 6.1.1.3 level.

  Source: protocol/unpacked-6113-wire.md. }
unit Level6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  LabLevelMagic = 'LABLVL1';
  CellPx = 16;

type
  TLabLevel = class
  public
    W, H: Integer;
    Cells: string;
    StartX, StartY: Integer;
    OtherX, OtherY: Integer;
    HasOther: Boolean;
    function LoadText(const Text: string; out Err: string): Boolean;
    function LoadFile(const Path: string; out Err: string): Boolean;
    function InBounds(CX, CY: Integer): Boolean;
    function SolidCell(CX, CY: Integer): Boolean;
    function Fits(PixelX, PixelY, Box: Integer): Boolean;
  end;

implementation

uses
  SysUtils, Classes;

function TLabLevel.InBounds(CX, CY: Integer): Boolean;
begin
  Result := (CX >= 0) and (CY >= 0) and (CX < W) and (CY < H);
end;

function TLabLevel.SolidCell(CX, CY: Integer): Boolean;
begin
  if not InBounds(CX, CY) then
    Result := True
  else
    Result := Cells[CY * W + CX + 1] = '#';
end;

function TLabLevel.Fits(PixelX, PixelY, Box: Integer): Boolean;
var
  X0, Y0, X1, Y1, CX, CY: Integer;
begin
  Result := False;
  if (W <= 0) or (Box <= 0) then Exit;
  if (PixelX < 0) or (PixelY < 0) then Exit;
  if (PixelX + Box > W * CellPx) or (PixelY + Box > H * CellPx) then Exit;
  X0 := PixelX div CellPx;
  Y0 := PixelY div CellPx;
  X1 := (PixelX + Box - 1) div CellPx;
  Y1 := (PixelY + Box - 1) div CellPx;
  for CY := Y0 to Y1 do
    for CX := X0 to X1 do
      if SolidCell(CX, CY) then Exit;
  Result := True;
end;

function SplitLines(const Text: string): TStringList;
var
  I, Start: Integer;
  S: string;
begin
  Result := TStringList.Create;
  S := Text;
  Start := 1;
  for I := 1 to Length(S) do
    if S[I] = #10 then
    begin
      Result.Add(Copy(S, Start, I - Start));
      Start := I + 1;
    end;
  if Start <= Length(S) + 1 then
    Result.Add(Copy(S, Start, MaxInt));
  for I := 0 to Result.Count - 1 do
    if (Length(Result[I]) > 0) and (Result[I][Length(Result[I])] = #13) then
      Result[I] := Copy(Result[I], 1, Length(Result[I]) - 1);
end;

function FirstWord(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] <> ' ') and (S[I] <> #9) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

function TLabLevel.LoadText(const Text: string; out Err: string): Boolean;
var
  Lines: TStringList;
  Magic, Row: string;
  X, Y, P: Integer;
begin
  Result := False;
  Err := '';
  W := 0;
  H := 0;
  Cells := '';
  HasOther := False;
  StartX := 0;
  StartY := 0;
  Lines := SplitLines(Text);
  try
    if Lines.Count = 0 then
    begin
      Err := 'empty level';
      Exit;
    end;
    Magic := FirstWord(Lines[0]);
    if (Magic = 'GR-V1.03') or (Magic = 'GR-V1.04') or (Magic = 'GR-V1.05') then
    begin
      Err := 'level magic is named in the image; the body was not recovered';
      Exit;
    end;
    if Magic = 'GLEVNW01' then
    begin
      Err := 'this magic is not in the unpacked 6.1.1.3 image';
      Exit;
    end;
    if Magic <> LabLevelMagic then
    begin
      Err := 'not a lab-only level';
      Exit;
    end;
    if Lines.Count < 2 then
    begin
      Err := 'lab level has no size';
      Exit;
    end;
    P := Pos(' ', Lines[1]);
    if P < 2 then
    begin
      Err := 'lab level size is not two numbers';
      Exit;
    end;
    W := StrToIntDef(Copy(Lines[1], 1, P - 1), -1);
    H := StrToIntDef(Trim(Copy(Lines[1], P + 1, MaxInt)), -1);
    if (W < 1) or (H < 1) or (Lines.Count < 2 + H) then
    begin
      Err := 'lab level size does not match the rows';
      Exit;
    end;
    SetLength(Cells, W * H);
    FillChar(Cells[1], Length(Cells), Ord('.'));
    for Y := 0 to H - 1 do
    begin
      Row := Lines[2 + Y];
      if Length(Row) < W then
      begin
        Err := 'lab level row is short';
        Exit;
      end;
      for X := 0 to W - 1 do
      begin
        Cells[Y * W + X + 1] := Row[X + 1];
        if Row[X + 1] = '@' then
        begin
          StartX := X * CellPx;
          StartY := Y * CellPx;
          Cells[Y * W + X + 1] := '.';
        end
        else if Row[X + 1] = 'O' then
        begin
          OtherX := X * CellPx;
          OtherY := Y * CellPx;
          HasOther := True;
          Cells[Y * W + X + 1] := '.';
        end
        else if (Row[X + 1] <> '.') and (Row[X + 1] <> '#') then
        begin
          Err := 'lab level has an unknown cell';
          Exit;
        end;
      end;
    end;
    if not Fits(StartX, StartY, CellPx) then
    begin
      Err := 'lab level start is inside a wall';
      Exit;
    end;
    Result := True;
  finally
    Lines.Free;
    if not Result then
    begin
      W := 0;
      H := 0;
      Cells := '';
      HasOther := False;
    end;
  end;
end;

function TLabLevel.LoadFile(const Path: string; out Err: string): Boolean;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Path);
    except
      on E: Exception do
      begin
        Err := 'level file was not read';
        Result := False;
        Exit;
      end;
    end;
    Result := LoadText(SL.Text, Err);
  finally
    SL.Free;
  end;
end;

end.
