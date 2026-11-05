{ GTrueType: draws text with a TrueType font file read at run time (the
  install's own fonts, such as 2.22's TEMPSITC.TTF for the names under
  players), so a rebuild can show the text the original showed without
  carrying the font.

  A small reader of the TrueType format (Apple's and Microsoft's
  specification): the head, hhea, maxp, hmtx, cmap (format 4), loca and
  glyf tables; simple and composite glyphs (offsets and a uniform scale);
  quadratic outlines flattened into lines and filled with the non-zero
  rule on a 4 x 4 grid per pixel, which gives each pixel a coverage from
  0 to 16. No hinting, kerning or other tables. }
unit GTrueType;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface;

type
  TTrueTypeFont = class
  private
    FData: string;
    FHead, FHhea, FMaxp, FHmtx, FCmap, FLoca, FGlyf: Integer;
    FUnits, FLocFormat, FGlyphs, FMetrics, FAscent, FDescent: Integer;
    FCmapSub: Integer;
    FCache: TStringList;
    function B8(Off: Integer): Integer;
    function U16(Off: Integer): Integer;
    function S16(Off: Integer): Integer;
    function U32(Off: Integer): Integer;
    function Table(const Tag: string): Integer;
    function GlyphIndex(C: Integer): Integer;
    function Advance(G: Integer): Integer;
    function GlyphAt(G: Integer; out Len: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadFromFile(const FileName: string): Boolean;
    function LoadFromString(const Data: string): Boolean;
    { Width in pixels of S at an em of Px pixels. }
    function TextWidth(const S: string; Px: Integer; Bold: Boolean = False): Integer;
    { Line height (ascent + descent) at an em of Px pixels. }
    function LineHeight(Px: Integer): Integer;
    { Draws S with the top of its line at Y, blended in Color by each
      pixel's coverage. }
    { Bold: GDI's made-up bold of a font with no bold face, each glyph
      twice, one pixel apart, and one pixel wider }
    procedure DrawText(Dest: TGSurface; X, Y: Integer; const S: string; Px: Integer;
      Color: Cardinal; Bold: Boolean = False);
  end;

implementation

uses
  SysUtils, Math;

type
  TPt = record
    X, Y: Double;
    On: Boolean;
  end;
  TPts = array of TPt;
  TContours = array of TPts;

  { a glyph's coverage: W x H bytes, 0 .. 16, its top-left at (OX, OY)
    from the pen on the baseline }
  TGlyphBits = class
    W, H, OX, OY, Adv: Integer;
    Cov: array of Byte;
  end;

constructor TTrueTypeFont.Create;
begin
  inherited Create;
  FCache := TStringList.Create;
  FCache.Sorted := True;
end;

destructor TTrueTypeFont.Destroy;
var
  I: Integer;
begin
  for I := 0 to FCache.Count - 1 do FCache.Objects[I].Free;
  FCache.Free;
  inherited Destroy;
end;

function TTrueTypeFont.B8(Off: Integer): Integer;
begin
  if (Off < 0) or (Off >= Length(FData)) then Result := 0
  else Result := Ord(FData[Off + 1]);
end;

function TTrueTypeFont.U16(Off: Integer): Integer;
begin
  if (Off < 0) or (Off + 2 > Length(FData)) then Result := 0
  else Result := (Ord(FData[Off + 1]) shl 8) or Ord(FData[Off + 2]);
end;

function TTrueTypeFont.S16(Off: Integer): Integer;
begin
  Result := U16(Off);
  if Result >= $8000 then Dec(Result, $10000);
end;

function TTrueTypeFont.U32(Off: Integer): Integer;
begin
  Result := (U16(Off) shl 16) or U16(Off + 2);
end;

function TTrueTypeFont.Table(const Tag: string): Integer;
var
  I, N: Integer;
begin
  Result := -1;
  N := U16(4);
  for I := 0 to N - 1 do
    if Copy(FData, 12 + I * 16 + 1, 4) = Tag then
    begin
      Result := U32(12 + I * 16 + 8);
      Exit;
    end;
end;

function TTrueTypeFont.LoadFromFile(const FileName: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(S, F.Size);
      if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  Result := LoadFromString(S);
end;

function TTrueTypeFont.LoadFromString(const Data: string): Boolean;
var
  I, N, Plat, Enc, Sub: Integer;
begin
  Result := False;
  FData := Data;
  if Length(FData) < 12 then
  begin
    FData := '';
    Exit;
  end;
  FHead := Table('head');
  FHhea := Table('hhea');
  FMaxp := Table('maxp');
  FHmtx := Table('hmtx');
  FCmap := Table('cmap');
  FLoca := Table('loca');
  FGlyf := Table('glyf');
  if (FHead < 0) or (FHhea < 0) or (FMaxp < 0) or (FHmtx < 0) or (FCmap < 0) or
    (FLoca < 0) or (FGlyf < 0) then
  begin
    FData := '';
    Exit;
  end;
  FUnits := U16(FHead + 18);
  FLocFormat := S16(FHead + 50);
  FGlyphs := U16(FMaxp + 4);
  FAscent := S16(FHhea + 4);
  FDescent := S16(FHhea + 6);
  FMetrics := U16(FHhea + 34);
  if FUnits <= 0 then
  begin
    FData := '';
    Exit;
  end;
  { a Windows Unicode (3, 1) or symbol (3, 0) subtable in format 4 }
  FCmapSub := -1;
  N := U16(FCmap + 2);
  for I := 0 to N - 1 do
  begin
    Plat := U16(FCmap + 4 + I * 8);
    Enc := U16(FCmap + 6 + I * 8);
    Sub := FCmap + U32(FCmap + 8 + I * 8);
    if (Plat = 3) and (Enc in [0, 1]) and (U16(Sub) = 4) then
    begin
      FCmapSub := Sub;
      if Enc = 1 then Break;
    end;
  end;
  Result := FCmapSub >= 0;
  if not Result then FData := '';
end;

function TTrueTypeFont.GlyphIndex(C: Integer): Integer;
var
  Seg, I, EndC, StartC, Delta, RangeOff, P: Integer;

  function Lookup(Code: Integer): Integer;
  var
    J: Integer;
  begin
    Result := 0;
    for J := 0 to Seg - 1 do
    begin
      EndC := U16(FCmapSub + 14 + J * 2);
      if Code > EndC then Continue;
      StartC := U16(FCmapSub + 16 + Seg * 2 + J * 2);
      if Code < StartC then Exit;
      Delta := S16(FCmapSub + 16 + Seg * 4 + J * 2);
      RangeOff := U16(FCmapSub + 16 + Seg * 6 + J * 2);
      if RangeOff = 0 then
        Result := (Code + Delta) and $FFFF
      else
      begin
        P := FCmapSub + 16 + Seg * 6 + J * 2 + RangeOff + (Code - StartC) * 2;
        Result := U16(P);
        if Result <> 0 then Result := (Result + Delta) and $FFFF;
      end;
      Exit;
    end;
  end;

begin
  Seg := U16(FCmapSub + 6) div 2;
  I := Lookup(C);
  { a symbol font maps its characters at $F000 + code }
  if I = 0 then I := Lookup($F000 + C);
  if (I < 0) or (I >= FGlyphs) then I := 0;
  Result := I;
end;

function TTrueTypeFont.Advance(G: Integer): Integer;
begin
  if FMetrics <= 0 then Result := 0
  else if G < FMetrics then Result := U16(FHmtx + G * 4)
  else Result := U16(FHmtx + (FMetrics - 1) * 4);
end;

function TTrueTypeFont.GlyphAt(G: Integer; out Len: Integer): Integer;
var
  A, B: Integer;
begin
  if FLocFormat = 0 then
  begin
    A := U16(FLoca + G * 2) * 2;
    B := U16(FLoca + G * 2 + 2) * 2;
  end
  else
  begin
    A := U32(FLoca + G * 4);
    B := U32(FLoca + G * 4 + 4);
  end;
  Len := B - A;
  Result := FGlyf + A;
end;

{ the contours of glyph G in font units, Y up }
procedure ReadGlyph(F: TTrueTypeFont; G: Integer; var Out: TContours; Depth: Integer;
  SX, DX, DY: Double);
var
  P, Len, NC, I, J, NPts, Flags, Rep, V, Comp, GI, A1, A2: Integer;
  EndPts: array of Integer;
  Fl: array of Byte;
  XS, YS: array of Integer;
  C: TPts;
  Sc: Double;
  More: Boolean;
begin
  if (Depth > 4) or (G < 0) or (G >= F.FGlyphs) then Exit;
  P := F.GlyphAt(G, Len);
  if Len <= 0 then Exit;
  NC := F.S16(P);
  if NC >= 0 then
  begin
    SetLength(EndPts, NC);
    for I := 0 to NC - 1 do EndPts[I] := F.U16(P + 10 + I * 2);
    if NC = 0 then Exit;
    NPts := EndPts[NC - 1] + 1;
    if (NPts <= 0) or (NPts > 5000) then Exit;
    P := P + 10 + NC * 2;
    P := P + 2 + F.U16(P);
    SetLength(Fl, NPts);
    I := 0;
    while I < NPts do
    begin
      Flags := F.B8(P);
      Inc(P);
      Fl[I] := Flags;
      Inc(I);
      if Flags and 8 <> 0 then
      begin
        Rep := F.B8(P);
        Inc(P);
        while (Rep > 0) and (I < NPts) do
        begin
          Fl[I] := Flags;
          Inc(I);
          Dec(Rep);
        end;
      end;
    end;
    SetLength(XS, NPts);
    SetLength(YS, NPts);
    V := 0;
    for I := 0 to NPts - 1 do
    begin
      if Fl[I] and 2 <> 0 then
      begin
        if Fl[I] and 16 <> 0 then Inc(V, F.B8(P)) else Dec(V, F.B8(P));
        Inc(P);
      end
      else if Fl[I] and 16 = 0 then
      begin
        Inc(V, F.S16(P));
        Inc(P, 2);
      end;
      XS[I] := V;
    end;
    V := 0;
    for I := 0 to NPts - 1 do
    begin
      if Fl[I] and 4 <> 0 then
      begin
        if Fl[I] and 32 <> 0 then Inc(V, F.B8(P)) else Dec(V, F.B8(P));
        Inc(P);
      end
      else if Fl[I] and 32 = 0 then
      begin
        Inc(V, F.S16(P));
        Inc(P, 2);
      end;
      YS[I] := V;
    end;
    J := 0;
    for I := 0 to NC - 1 do
    begin
      SetLength(C, 0);
      while J <= EndPts[I] do
      begin
        SetLength(C, Length(C) + 1);
        C[High(C)].X := XS[J] * SX + DX;
        C[High(C)].Y := YS[J] * SX + DY;
        C[High(C)].On := Fl[J] and 1 <> 0;
        Inc(J);
      end;
      if Length(C) > 1 then
      begin
        SetLength(Out, Length(Out) + 1);
        Out[High(Out)] := C;
      end;
    end;
  end
  else
  begin
    { composite: each part with its offset and, at most, one scale }
    P := P + 10;
    repeat
      Comp := F.U16(P);
      GI := F.U16(P + 2);
      Inc(P, 4);
      if Comp and 1 <> 0 then
      begin
        A1 := F.S16(P);
        A2 := F.S16(P + 2);
        Inc(P, 4);
      end
      else
      begin
        A1 := ShortInt(F.B8(P));
        A2 := ShortInt(F.B8(P + 1));
        Inc(P, 2);
      end;
      Sc := 1;
      if Comp and 8 <> 0 then
      begin
        Sc := F.S16(P) / 16384;
        Inc(P, 2);
      end
      else if Comp and $40 <> 0 then
      begin
        Sc := F.S16(P) / 16384;
        Inc(P, 4);
      end
      else if Comp and $80 <> 0 then
      begin
        Sc := F.S16(P) / 16384;
        Inc(P, 8);
      end;
      { args are x and y offsets (ARGS_ARE_XY_VALUES); point matching is
        not done }
      if Comp and 2 <> 0 then
        ReadGlyph(F, GI, Out, Depth + 1, SX * Sc, DX + A1 * SX, DY + A2 * SX);
      More := Comp and $20 <> 0;
    until not More;
  end;
end;

type
  TEdge = record
    X0, Y0, X1, Y1: Double;
  end;

function RenderGlyph(F: TTrueTypeFont; G, Px: Integer): TGlyphBits;
const
  SS = 4;
var
  Cs: TContours;
  Edges: array of TEdge;
  Scale, MinX, MinY, MaxX, MaxY, PX0, PY0, MX, MY, T: Double;
  I, J, K, N, X, Y, W, H, SW, SH, Wind, NX, XI: Integer;
  Prev, Cur, Nxt, Mid: TPt;
  Xs: array of Double;
  Ws: array of Integer;
  Grid: array of ShortInt;

  procedure AddLine(AX, AY, BX, BY: Double);
  begin
    SetLength(Edges, Length(Edges) + 1);
    Edges[High(Edges)].X0 := AX;
    Edges[High(Edges)].Y0 := AY;
    Edges[High(Edges)].X1 := BX;
    Edges[High(Edges)].Y1 := BY;
  end;

  procedure AddQuad(AX, AY, CX, CY, BX, BY: Double);
  var
    S: Integer;
    LX, LY, U, QX, QY: Double;
  begin
    LX := AX;
    LY := AY;
    for S := 1 to 6 do
    begin
      U := S / 6;
      QX := (1 - U) * (1 - U) * AX + 2 * (1 - U) * U * CX + U * U * BX;
      QY := (1 - U) * (1 - U) * AY + 2 * (1 - U) * U * CY + U * U * BY;
      AddLine(LX, LY, QX, QY);
      LX := QX;
      LY := QY;
    end;
  end;

begin
  Result := TGlyphBits.Create;
  Scale := Px / F.FUnits;
  Result.Adv := Round(F.Advance(G) * Scale);
  SetLength(Cs, 0);
  ReadGlyph(F, G, Cs, 0, Scale, 0, 0);
  { outlines to lines, Y down (pixel rows) }
  for I := 0 to High(Cs) do
  begin
    N := Length(Cs[I]);
    for J := 0 to N - 1 do Cs[I][J].Y := -Cs[I][J].Y;
    { start on an on-curve point, or the middle of two off-curve ones }
    K := -1;
    for J := 0 to N - 1 do
      if Cs[I][J].On then
      begin
        K := J;
        Break;
      end;
    if K < 0 then
    begin
      Prev.X := (Cs[I][0].X + Cs[I][1].X) / 2;
      Prev.Y := (Cs[I][0].Y + Cs[I][1].Y) / 2;
      K := 0;
    end
    else
      Prev := Cs[I][K];
    PX0 := Prev.X;
    PY0 := Prev.Y;
    J := 1;
    while J <= N do
    begin
      Cur := Cs[I][(K + J) mod N];
      if Cur.On then
      begin
        AddLine(Prev.X, Prev.Y, Cur.X, Cur.Y);
        Prev := Cur;
      end
      else
      begin
        Nxt := Cs[I][(K + J + 1) mod N];
        if Nxt.On then
        begin
          AddQuad(Prev.X, Prev.Y, Cur.X, Cur.Y, Nxt.X, Nxt.Y);
          Prev := Nxt;
          Inc(J);
        end
        else
        begin
          Mid.X := (Cur.X + Nxt.X) / 2;
          Mid.Y := (Cur.Y + Nxt.Y) / 2;
          AddQuad(Prev.X, Prev.Y, Cur.X, Cur.Y, Mid.X, Mid.Y);
          Prev := Mid;
        end;
      end;
      Inc(J);
    end;
    if (Prev.X <> PX0) or (Prev.Y <> PY0) then AddLine(Prev.X, Prev.Y, PX0, PY0);
  end;
  if Length(Edges) = 0 then Exit;
  MinX := 1E9; MinY := 1E9; MaxX := -1E9; MaxY := -1E9;
  for I := 0 to High(Edges) do
  begin
    MinX := Min(MinX, Min(Edges[I].X0, Edges[I].X1));
    MaxX := Max(MaxX, Max(Edges[I].X0, Edges[I].X1));
    MinY := Min(MinY, Min(Edges[I].Y0, Edges[I].Y1));
    MaxY := Max(MaxY, Max(Edges[I].Y0, Edges[I].Y1));
  end;
  Result.OX := Floor(MinX);
  Result.OY := Floor(MinY);
  W := Ceil(MaxX) - Result.OX + 1;
  H := Ceil(MaxY) - Result.OY + 1;
  if (W <= 0) or (H <= 0) or (W > 512) or (H > 512) then Exit;
  Result.W := W;
  Result.H := H;
  SetLength(Result.Cov, W * H);
  SW := W * SS;
  SH := H * SS;
  SetLength(Grid, SW);
  SetLength(Xs, Length(Edges));
  SetLength(Ws, Length(Edges));
  for Y := 0 to SH - 1 do
  begin
    MY := Result.OY + (Y + 0.5) / SS;
    NX := 0;
    for I := 0 to High(Edges) do
      with Edges[I] do
        if ((Y0 <= MY) and (Y1 > MY)) or ((Y1 <= MY) and (Y0 > MY)) then
        begin
          T := (MY - Y0) / (Y1 - Y0);
          Xs[NX] := X0 + T * (X1 - X0);
          if Y1 > Y0 then Ws[NX] := 1 else Ws[NX] := -1;
          Inc(NX);
        end;
    if NX = 0 then Continue;
    for X := 0 to SW - 1 do
    begin
      MX := Result.OX + (X + 0.5) / SS;
      Wind := 0;
      for I := 0 to NX - 1 do
        if Xs[I] < MX then Inc(Wind, Ws[I]);
      if Wind <> 0 then
      begin
        XI := (X div SS) + (Y div SS) * W;
        Inc(Result.Cov[XI]);
      end;
    end;
  end;
end;

function TTrueTypeFont.LineHeight(Px: Integer): Integer;
begin
  Result := 0;
  if FData = '' then Exit;
  Result := Round((FAscent - FDescent) * Px / FUnits);
end;

function TTrueTypeFont.TextWidth(const S: string; Px: Integer; Bold: Boolean): Integer;
var
  I: Integer;
begin
  Result := 0;
  if FData = '' then Exit;
  for I := 1 to Length(S) do
    Inc(Result, Round(Advance(GlyphIndex(Ord(S[I]))) * Px / FUnits) + Ord(Bold));
end;

procedure TTrueTypeFont.DrawText(Dest: TGSurface; X, Y: Integer; const S: string; Px: Integer;
  Color: Cardinal; Bold: Boolean);
var
  I, J, K, G, DX, DY, A, Idx, Pass: Integer;
  Key: string;
  B: TGlyphBits;
  Base: Integer;
  D: Cardinal;
  R, Gr, Bl: Integer;
begin
  if (FData = '') or (Px <= 0) then Exit;
  Base := Y + Round(FAscent * Px / FUnits);
  for I := 1 to Length(S) do
  begin
    G := GlyphIndex(Ord(S[I]));
    Key := IntToStr(Px) + ':' + IntToStr(G);
    Idx := FCache.IndexOf(Key);
    if Idx >= 0 then B := TGlyphBits(FCache.Objects[Idx])
    else
    begin
      B := RenderGlyph(Self, G, Px);
      FCache.AddObject(Key, B);
    end;
    for Pass := 0 to Ord(Bold) do
    for K := 0 to B.H - 1 do
    begin
      DY := Base + B.OY + K;
      if (DY < 0) or (DY >= Dest.Height) then Continue;
      for J := 0 to B.W - 1 do
      begin
        A := B.Cov[J + K * B.W];
        if A = 0 then Continue;
        DX := X + B.OX + J + Pass;
        if (DX < 0) or (DX >= Dest.Width) then Continue;
        if A >= 16 then Dest.Pixels[DX + DY * Dest.Width] := Color or $FF000000
        else
        begin
          D := Dest.Pixels[DX + DY * Dest.Width];
          R := ((Color shr 16) and $FF) * A div 16 + ((D shr 16) and $FF) * (16 - A) div 16;
          Gr := ((Color shr 8) and $FF) * A div 16 + ((D shr 8) and $FF) * (16 - A) div 16;
          Bl := (Color and $FF) * A div 16 + (D and $FF) * (16 - A) div 16;
          Dest.Pixels[DX + DY * Dest.Width] := $FF000000 or Cardinal(R shl 16) or
            Cardinal(Gr shl 8) or Cardinal(Bl);
        end;
      end;
    end;
    Inc(X, B.Adv + Ord(Bold));
  end;
end;

end.
