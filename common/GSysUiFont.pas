{ GSysUiFont: dialog text in the font the original forms name, drawn by
  Windows itself.

  The Delphi forms of the 2.x clients (TCONNECTFRAME, TSERVERLISTFRAME,
  TMOREOPTIONS, TOPENURL ...) set Font.Name = 'MS Sans Serif',
  Font.Height = -14 (TextHeight 16). That font is part of Windows and is
  not ours to ship, so on Windows the text is drawn through GDI with that
  very font, the way the original's controls draw it; elsewhere it falls
  back to GUiFont (Liberation Sans, built in).

  A client opts in by naming this unit after GUiFont in its uses: the two
  functions below then take the place of GUiFont's. }
unit GSysUiFont;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GUiFont;

{ Width in pixels of S. }
function UiTextWidth(const S: string; Face: TUiFace): Integer;
{ Draws S with the top of its 16 px line at Y. }
procedure UiDrawText(Dest: TGSurface; X, Y: Integer; const S: string; Color: Cardinal;
  Face: TUiFace);

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;

var
  Fonts: array[TUiFace] of HFONT;
  MemDC: HDC;
  Tried: Boolean;

function FontFor(Face: TUiFace): HFONT;
var
  W: Integer;
begin
  if not Tried then
  begin
    Tried := True;
    MemDC := CreateCompatibleDC(0);
  end;
  if (Fonts[Face] = 0) and (MemDC <> 0) then
  begin
    if Face = ufRegular then W := FW_NORMAL else W := FW_BOLD;
    { Font.Height = -14: a 14 px character height, no smoothing (a
      bitmap font, as the forms show it) }
    Fonts[Face] := CreateFont(-14, 0, 0, 0, W, 0, 0, 0, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, NONANTIALIASED_QUALITY,
      DEFAULT_PITCH or FF_DONTCARE, 'MS Sans Serif');
  end;
  Result := Fonts[Face];
end;

function UiTextWidth(const S: string; Face: TUiFace): Integer;
var
  F: HFONT;
  Sz: TSize;
begin
  F := FontFor(Face);
  if (F = 0) or (S = '') then
  begin
    Result := GUiFont.UiTextWidth(S, Face);
    Exit;
  end;
  SelectObject(MemDC, F);
  if GetTextExtentPoint32(MemDC, PChar(S), Length(S), Sz) then Result := Sz.cx
  else Result := GUiFont.UiTextWidth(S, Face);
end;

procedure UiDrawText(Dest: TGSurface; X, Y: Integer; const S: string; Color: Cardinal;
  Face: TUiFace);
var
  F: HFONT;
  W, H, I, J, DX, DY: Integer;
  BI: TBitmapInfo;
  Bits: PCardinal;
  Bmp, Old: HBITMAP;
  P: PCardinal;
begin
  if S = '' then Exit;
  F := FontFor(Face);
  if F = 0 then
  begin
    GUiFont.UiDrawText(Dest, X, Y, S, Color, Face);
    Exit;
  end;
  W := UiTextWidth(S, Face) + 2;
  H := UiLineH;
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := W;
  BI.bmiHeader.biHeight := -H;
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  Bits := nil;
  Bmp := CreateDIBSection(MemDC, BI, DIB_RGB_COLORS, Pointer(Bits), 0, 0);
  if (Bmp = 0) or (Bits = nil) then
  begin
    GUiFont.UiDrawText(Dest, X, Y, S, Color, Face);
    Exit;
  end;
  Old := SelectObject(MemDC, Bmp);
  try
    FillChar(Bits^, W * H * 4, 0);
    SelectObject(MemDC, F);
    SetBkMode(MemDC, TRANSPARENT);
    SetTextColor(MemDC, $00FFFFFF);
    TextOut(MemDC, 0, 0, PChar(S), Length(S));
    GdiFlush;
    { every lit pixel of the white text takes Color }
    for J := 0 to H - 1 do
    begin
      DY := Y + J;
      if (DY < 0) or (DY >= Dest.Height) then Continue;
      P := Bits;
      Inc(P, J * W);
      for I := 0 to W - 1 do
      begin
        DX := X + I;
        if (P^ and $FF) >= $80 then
          if (DX >= 0) and (DX < Dest.Width) then
            Dest.Pixels[DY * Dest.Width + DX] := Color;
        Inc(P);
      end;
    end;
  finally
    SelectObject(MemDC, Old);
    DeleteObject(Bmp);
  end;
end;

{$ELSE}

function UiTextWidth(const S: string; Face: TUiFace): Integer;
begin
  Result := GUiFont.UiTextWidth(S, Face);
end;

procedure UiDrawText(Dest: TGSurface; X, Y: Integer; const S: string; Color: Cardinal;
  Face: TUiFace);
begin
  GUiFont.UiDrawText(Dest, X, Y, S, Color, Face);
end;

{$ENDIF}

end.
