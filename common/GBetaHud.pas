{ GBetaHud: the status display of the 1998-1999 clients (betas 1-15, 1.1,
  1.1.9, 1.21, 1.28b2), drawn from the build's own state.gif and the digit
  sprites of its body sheet (link.gif or sprites.gif, sprite-table entries
  268-277: 0-8 in a row, 9 above the 7).

  Each build's layout is a table in its Protocol unit: which parts of
  state.gif go where, where the numbers stand and how they are written.
  The rectangles and places were measured by matching the build's own
  sheets against screenshots of the real client at the start of a game
  (640 x 448 view): every piece lands on the real one to the pixel. }
unit GBetaHud;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface;

type
  { a piece of a sheet drawn at a fixed place }
  THudPiece = record
    Sheet: Integer;           { 0 state.gif, 1 the digit sheet, 2 the sword }
    SX, SY, W, H: Integer;
    DX, DY: Integer;
  end;

  THudLayout = record
    DigitSheet: string;       { link.gif or sprites.gif }
    SwordSheet: string;       { the sword picture beside S (1.21 on) }
    DigitY, DigitH: Integer;  { the row of 0-8 in the digit sheet }
    DigitStep: Integer;       { pixels from one digit to the next }
    RupeeX: Integer;          { the centre of the rupee count, or its left }
    RupeeDigits: Integer;     { 0: as many digits as needed, centred on
                                RupeeX; n: always n digits from RupeeX }
    BombX, ArrowX: Integer;   { the left of the two-digit counts }
    NumberY: Integer;
    HeartSX, HeartSY: Integer; { the full heart (40 x 44) in state.gif }
    HeartX, HeartY, HeartStep: Integer;
    Count: Integer;
    Pieces: array[0..7] of THudPiece;
  end;

  THudValues = record
    Rupees, Bombs, Arrows: Integer;
    Hearts: Integer;          { whole hearts to draw }
  end;

{ The start of a game: the counts the originals show before anything is
  picked up. }
function HudStartValues(Rupees: Integer): THudValues;

procedure DrawBetaHud(Screen: TGSurface; const L: THudLayout; const V: THudValues);

{ Frees the sheets loaded for the display. }
procedure FreeHudSheets;

implementation

uses
  SysUtils, GAssetDirs;

var
  Sheets: array[0..2] of TGSurface;
  SheetNames: array[0..2] of string;

function HudStartValues(Rupees: Integer): THudValues;
begin
  Result.Rupees := Rupees;
  Result.Bombs := 10;
  Result.Arrows := 5;
  Result.Hearts := 3;
end;

function LoadSheet(Slot: Integer; const Name: string): TGSurface;
var
  F: string;
begin
  Result := nil;
  if Name = '' then Exit;
  if (Sheets[Slot] <> nil) and (SheetNames[Slot] = Name) then
  begin
    Result := Sheets[Slot];
    Exit;
  end;
  FreeAndNil(Sheets[Slot]);
  SheetNames[Slot] := Name;
  F := AssetPath(Name);
  if F = '' then F := AssetPath('levels/' + Name);
  if F = '' then F := AssetPath('levels/swords/' + Name);
  if F = '' then Exit;
  Sheets[Slot] := TGSurface.Create(0, 0);
  if not LoadImageFile(F, Sheets[Slot]) then FreeAndNil(Sheets[Slot]);
  Result := Sheets[Slot];
end;

procedure DrawBetaHud(Screen: TGSurface; const L: THudLayout; const V: THudValues);
var
  St, Dg, Sw, Img: TGSurface;
  I: Integer;

  procedure Digit(D, X: Integer);
  begin
    if Dg = nil then Exit;
    if D = 9 then
      Screen.Blit(Dg, 96, L.DigitY - 16, 14, L.DigitH, X, L.NumberY)
    else
      Screen.Blit(Dg, 14 * D, L.DigitY, 14, L.DigitH, X, L.NumberY);
  end;

  procedure Number(V, X, Digits: Integer; Centred: Boolean);
  var
    S: string;
    J: Integer;
  begin
    if V < 0 then V := 0;
    S := IntToStr(V);
    if Digits > 0 then
    begin
      while Length(S) < Digits do S := '0' + S;
      if Length(S) > Digits then S := Copy(S, Length(S) - Digits + 1, Digits);
    end;
    if Centred then X := X - (Length(S) * L.DigitStep) div 2;
    for J := 1 to Length(S) do
      Digit(Ord(S[J]) - Ord('0'), X + (J - 1) * L.DigitStep);
  end;

begin
  St := LoadSheet(0, 'state.gif');
  Dg := LoadSheet(1, L.DigitSheet);
  Sw := LoadSheet(2, L.SwordSheet);
  for I := 0 to L.Count - 1 do
  begin
    case L.Pieces[I].Sheet of
      0: Img := St;
      1: Img := Dg;
    else
      Img := Sw;
    end;
    if Img <> nil then
      with L.Pieces[I] do Screen.Blit(Img, SX, SY, W, H, DX, DY);
  end;
  if L.RupeeDigits > 0 then
    Number(V.Rupees, L.RupeeX, L.RupeeDigits, False)
  else
    Number(V.Rupees, L.RupeeX, 0, True);
  Number(V.Bombs, L.BombX, 2, False);
  Number(V.Arrows, L.ArrowX, 2, False);
  if St <> nil then
    for I := 0 to V.Hearts - 1 do
      Screen.Blit(St, L.HeartSX, L.HeartSY, 40, 44, L.HeartX + I * L.HeartStep, L.HeartY);
end;

procedure FreeHudSheets;
var
  I: Integer;
begin
  for I := 0 to 2 do
  begin
    FreeAndNil(Sheets[I]);
    SheetNames[I] := '';
  end;
end;

finalization
  FreeHudSheets;
end.
