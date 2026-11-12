{ GEngineHost: the launcher's side of the 4.x/5.0 engine library.

  The 4.x and 5.0 clients are a Delphi launcher over an engine library
  (Graal_analysis torque/4208-launcher.md, torque/5007-launcher.md). The
  launcher owns the window and draws every pixel; the engine owns the
  session, the canvas and the controls, and draws only by calling back.
  The launcher loads the library, resolves one graal_set<Name> per callback
  slot, calls every one with its own function, then calls
  graal_engineInitialize. Each frame it calls renderGraalCanvas.

  This unit is that launcher half for the rebuild's engine
  (common/cpp/graalengine). The original draws with DirectDraw; this one
  draws into a TGSurface the client presents like every other frame. The
  argument lists are the rebuild's own and must match
  common/cpp/graalengine/include/graalengine_slots.def; the library's
  graalengine_abi() guards that.

  Slots the rebuild cannot serve yet (Flash, the microphone, the external
  windows) are still registered, as the original registers all of them;
  they record the call in Events and do nothing else. }
unit GEngineHost;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GSurface;

const
  { Must equal GRAALENGINE_ABI in graalengine.h. }
  EngineAbi = 1;
  { GRAAL_BUILD_* in graalengine.h. }
  EngineBuild4x = 1;
  EngineBuild50 = 2;
  { Mouse actions and buttons (GRAAL_MOUSE_*). }
  EngineMouseMove = 0;
  EngineMouseDown = 1;
  EngineMouseUp = 2;
  EngineMouseWheel = 3;
  EngineMods_Shift = 1;
  EngineMods_Ctrl = 2;
  EngineMods_Alt = 4;

type
  PGraalTexture = ^TGraalTexture;
  TGraalTexture = record
    Name: PAnsiChar;
    Width, Height: LongInt;
    Pixels: PCardinal;
    HostData: Pointer;
  end;

  PGraalMatrix2D = ^TGraalMatrix2D;
  TGraalMatrix2D = record
    A, B, C, D, TX, TY: Single;
  end;

  TEngineHost = class
  private
    FLib: PtrUInt;
    FLibPath: string;
    FError: string;
    FMissing: TStringList;
    procedure SetError(const S: string);
  public
    { The frame the engine draws into, sized to the window. }
    Screen: TGSurface;
    ClipX, ClipY, ClipW, ClipH: Integer;
    { Text the engine wrote with LogGraalMessage. }
    Log: TStringList;
    { One line per call of a slot the rebuild only records ("Name args"). }
    Events: TStringList;
    Clipboard: AnsiString;
    Active: Boolean;
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;
    { Loads the library and checks its interface version. }
    function Load(const LibPath: string): Boolean;
    { Calls graal_set<Name> for every slot the library lists for Build
      (EngineBuild4x or EngineBuild50). Returns the number registered.
      Slots of that build this unit has no function for are in Missing. }
    function RegisterSlots(Build: Integer): Integer;
    function Initialize(const ExePath: string): Boolean;
    procedure LoadGui;
    procedure Render;
    procedure Key(VK, Ch, Mods: Integer; Down: Boolean);
    procedure Mouse(X, Y, Action, Button, Clicks, Mods, Wheel: Integer);
    procedure StartOffline;
    procedure Connect(const Name, Host: AnsiString; Port: Integer);
    procedure Shutdown;
    procedure Unload;
    function Loaded: Boolean;
    { The library's slot list. }
    function SlotCount: Integer;
    function SlotName(I: Integer): string;
    function SlotBuilds(I: Integer): Integer;
    property Error: string read FError;
    property Missing: TStringList read FMissing;
  end;

{ The library's file name next to the program: GraalEngineRepro.dll on Windows
  (not GraalEngine.dll, which is the player's original and the source of the
  start menus),
  libgraalengine.dylib on macOS, libgraalengine.so elsewhere. }
function EngineLibName: string;

{ The number of launcher functions this unit has, and each one's slot name. }
function HostSlotCount: Integer;
function HostSlotName(I: Integer): string;
{ The launcher function for a slot name, nil when there is none (tests). }
function HostSlotFn(const Name: string): Pointer;

implementation

uses
  SysUtils, DynLibs, GUiFont;

type
  TSetter = procedure(Fn: Pointer); cdecl;
  TInit = function(ExePath: PAnsiChar): LongInt; cdecl;
  TProc0 = procedure; cdecl;
  TKeyProc = procedure(VK, Ch, Mods, Down: LongInt); cdecl;
  TMouseProc = procedure(X, Y, Action, Button, Clicks, Mods, Wheel: LongInt); cdecl;
  TConnectProc = procedure(Name, Host: PAnsiChar; Port: LongInt); cdecl;
  TIntFn = function: LongInt; cdecl;
  TNameFn = function(I: LongInt): PAnsiChar; cdecl;
  TBuildsFn = function(I: LongInt): LongInt; cdecl;

var
  { The host the callbacks draw for. One engine library per process, as in
    the original. }
  Cur: TEngineHost = nil;
  { Strings handed back to the engine stay valid until the next call. }
  RetText: AnsiString;

function EngineLibName: string;
begin
{$IFDEF MSWINDOWS}
  Result := 'GraalEngineRepro.dll';
{$ELSE}
{$IFDEF DARWIN}
  Result := 'libgraalengine.dylib';
{$ELSE}
  Result := 'libgraalengine.so';
{$ENDIF}
{$ENDIF}
end;

procedure Note(const S: string);
begin
  if Cur <> nil then Cur.Events.Add(S);
end;

function Str(P: PAnsiChar): string;
begin
  if P = nil then Result := '' else Result := string(AnsiString(P));
end;

{ ---- Pixels ------------------------------------------------------------ }

function Blend(Dst, Src: Cardinal): Cardinal;
var
  A, IA: Cardinal;
begin
  A := Src shr 24;
  if A = 255 then Exit(Src);
  if A = 0 then Exit(Dst);
  IA := 255 - A;
  Result := $FF000000 or
    (((((Src shr 16) and $FF) * A + ((Dst shr 16) and $FF) * IA + 127) div 255) shl 16) or
    (((((Src shr 8) and $FF) * A + ((Dst shr 8) and $FF) * IA + 127) div 255) shl 8) or
    ((((Src and $FF) * A + (Dst and $FF) * IA + 127) div 255));
end;

function Modulate(C, M: Cardinal): Cardinal;
begin
  if (M = 0) or (M = $FFFFFFFF) then Exit(C);
  Result :=
    ((((C shr 24) * (M shr 24) + 127) div 255) shl 24) or
    (((((C shr 16) and $FF) * ((M shr 16) and $FF) + 127) div 255) shl 16) or
    (((((C shr 8) and $FF) * ((M shr 8) and $FF) + 127) div 255) shl 8) or
    ((((C and $FF) * (M and $FF) + 127) div 255));
end;

function InClip(X, Y: Integer): Boolean;
begin
  Result := (X >= Cur.ClipX) and (Y >= Cur.ClipY) and (X < Cur.ClipX + Cur.ClipW) and
    (Y < Cur.ClipY + Cur.ClipH) and (X >= 0) and (Y >= 0) and (X < Cur.Screen.Width) and
    (Y < Cur.Screen.Height);
end;

procedure PutPixel(X, Y: Integer; C: Cardinal);
var
  P: PCardinal;
begin
  if not InClip(X, Y) then Exit;
  P := @Cur.Screen.Pixels[X + Y * Cur.Screen.Width];
  P^ := Blend(P^, C);
end;

function TexPixel(T: PGraalTexture; X, Y: Integer): Cardinal;
begin
  if (T = nil) or (T^.Pixels = nil) or (X < 0) or (Y < 0) or (X >= T^.Width) or (Y >= T^.Height) then
    Exit(0);
  Result := PCardinal(PAnsiChar(T^.Pixels) + SizeOf(Cardinal) * PtrUInt(X + Y * T^.Width))^;
end;

{ A plain surface list for tile buffers and panels; handle = index + 1. }
type
  TSurfaceList = array of TGSurface;

var
  TileBufs: TSurfaceList;
  Panels: TSurfaceList;
  Matrices: array of TGraalMatrix2D;

function NewSurface(var L: TSurfaceList; W, H: Integer): LongInt;
var
  I: Integer;
begin
  for I := 0 to High(L) do
    if L[I] = nil then
    begin
      L[I] := TGSurface.Create(W, H);
      L[I].Fill(0);
      Exit(I + 1);
    end;
  SetLength(L, Length(L) + 1);
  L[High(L)] := TGSurface.Create(W, H);
  L[High(L)].Fill(0);
  Result := Length(L);
end;

function GetSurface(const L: TSurfaceList; H: LongInt): TGSurface;
begin
  if (H < 1) or (H > Length(L)) then Result := nil else Result := L[H - 1];
end;

procedure FreeSurface(var L: TSurfaceList; H: LongInt);
begin
  if (H >= 1) and (H <= Length(L)) then FreeAndNil(L[H - 1]);
end;

procedure FreeAll(var L: TSurfaceList);
var
  I: Integer;
begin
  for I := 0 to High(L) do FreeAndNil(L[I]);
  L := nil;
end;

procedure TexToSurface(T: PGraalTexture; Dest: TGSurface; X, Y, SX, SY, SW, SH: Integer);
var
  I, J: Integer;
  C: Cardinal;
  P: PCardinal;
begin
  for J := 0 to SH - 1 do
    for I := 0 to SW - 1 do
    begin
      if (X + I < 0) or (Y + J < 0) or (X + I >= Dest.Width) or (Y + J >= Dest.Height) then Continue;
      C := TexPixel(T, SX + I, SY + J);
      P := @Dest.Pixels[X + I + (Y + J) * Dest.Width];
      if (C shr 24) <> 0 then P^ := Blend(P^, C);
    end;
end;

procedure SurfaceToScreen(S: TGSurface; X, Y, SX, SY, W, H: Integer; Modul: Cardinal);
var
  I, J: Integer;
  C: Cardinal;
begin
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
    begin
      if (SX + I < 0) or (SY + J < 0) or (SX + I >= S.Width) or (SY + J >= S.Height) then Continue;
      C := Modulate(S.Pixels[SX + I + (SY + J) * S.Width], Modul);
      if (C shr 24) <> 0 then PutPixel(X + I, Y + J, C);
    end;
end;

{ ---- Screen, clip, matrix ---------------------------------------------- }

function cbScreenWidth: LongInt; cdecl;
begin
  Result := Cur.Screen.Width;
end;

function cbScreenHeight: LongInt; cdecl;
begin
  Result := Cur.Screen.Height;
end;

procedure cbClip(X, Y, W, H: LongInt); cdecl;
begin
  Cur.ClipX := X;
  Cur.ClipY := Y;
  Cur.ClipW := W;
  Cur.ClipH := H;
end;

procedure cbGetClip(R: PLongInt); cdecl;
begin
  if R = nil then Exit;
  R^ := Cur.ClipX; Inc(R);
  R^ := Cur.ClipY; Inc(R);
  R^ := Cur.ClipW; Inc(R);
  R^ := Cur.ClipH;
end;

procedure cbPushMatrix(M: PGraalMatrix2D); cdecl;
begin
  SetLength(Matrices, Length(Matrices) + 1);
  if M <> nil then Matrices[High(Matrices)] := M^;
end;

procedure cbPopMatrix; cdecl;
begin
  if Length(Matrices) > 0 then SetLength(Matrices, Length(Matrices) - 1);
end;

function cbMatrixActive: LongInt; cdecl;
begin
  Result := Ord(Length(Matrices) > 0);
end;

function cbGetMatrix(M: PGraalMatrix2D): LongInt; cdecl;
begin
  Result := Ord(Length(Matrices) > 0);
  if (Result <> 0) and (M <> nil) then M^ := Matrices[High(Matrices)];
end;

{ ---- Tiles --------------------------------------------------------------- }

function cbCreateTiles(W, H: LongInt): LongInt; cdecl;
begin
  Result := NewSurface(TileBufs, W, H);
end;

procedure cbDeleteTiles(B: LongInt); cdecl;
begin
  FreeSurface(TileBufs, B);
end;

procedure cbResizeTiles(B, W, H: LongInt); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(TileBufs, B);
  if S <> nil then
  begin
    S.SetSize(W, H);
    S.Fill(0);
  end;
end;

procedure cbScrollTiles(B, DX, DY: LongInt); cdecl;
var
  S, T: TGSurface;
begin
  S := GetSurface(TileBufs, B);
  if S = nil then Exit;
  T := TGSurface.Create(S.Width, S.Height);
  try
    T.Fill(0);
    T.Blit(S, 0, 0, S.Width, S.Height, DX, DY);
    S.Pixels := Copy(T.Pixels);
  finally
    T.Free;
  end;
end;

procedure cbStartTiles(B: LongInt); cdecl;
begin
end;

procedure cbEndTiles(B: LongInt); cdecl;
begin
end;

procedure cbDrawTile(B: LongInt; Sheet: PGraalTexture; SX, SY, DX, DY: LongInt); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(TileBufs, B);
  if S <> nil then
  begin
    S.FillRect(DX, DY, TileSize, TileSize, 0);
    TexToSurface(Sheet, S, DX, DY, SX, SY, TileSize, TileSize);
  end;
end;

procedure cbClearTile(B, DX, DY: LongInt); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(TileBufs, B);
  if S <> nil then S.FillRect(DX, DY, TileSize, TileSize, 0);
end;

procedure cbTilesOnScreen(B, X, Y, SX, SY, W, H: LongInt); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(TileBufs, B);
  if S <> nil then SurfaceToScreen(S, X, Y, SX, SY, W, H, $FFFFFFFF);
end;

{ ---- Text ---------------------------------------------------------------- }

function FaceOf(Style: LongInt): TUiFace;
begin
  if (Style and 1) <> 0 then Result := ufBold else Result := ufRegular;
end;

procedure TextAt(X, Y: Integer; const S: string; Color: Cardinal; Face: TUiFace);
var
  T: TGSurface;
  W: Integer;
begin
  W := UiTextWidth(S, Face);
  if W <= 0 then Exit;
  T := TGSurface.Create(W, UiLineH);
  try
    T.Fill(0);
    UiDrawText(T, 0, 0, S, Color, Face);
    SurfaceToScreen(T, X, Y, 0, 0, W, UiLineH, $FFFFFFFF);
  finally
    T.Free;
  end;
end;

procedure cbDrawText(X, Y: LongInt; Text, Font: PAnsiChar; Size, Style: LongInt; Color: Cardinal); cdecl;
begin
  TextAt(X, Y, Str(Text), Color, FaceOf(Style));
end;

procedure cbDrawShadowed(X, Y: LongInt; Text, Font: PAnsiChar; Size, Style: LongInt;
  Color, Shadow: Cardinal); cdecl;
begin
  TextAt(X + 1, Y + 1, Str(Text), Shadow, FaceOf(Style));
  TextAt(X, Y, Str(Text), Color, FaceOf(Style));
end;

function cbTextWidth(Text, Font: PAnsiChar; Size, Style: LongInt): LongInt; cdecl;
begin
  Result := UiTextWidth(Str(Text), FaceOf(Style));
end;

function cbTextHeight(Font: PAnsiChar; Size, Style: LongInt): LongInt; cdecl;
begin
  Result := UiLineH;
end;

{ GUiFont's 16 px line: 13 above the baseline, 3 below. }
function cbTextAscent(Font: PAnsiChar; Size, Style: LongInt): LongInt; cdecl;
begin
  Result := 13;
end;

function cbTextDescent(Font: PAnsiChar; Size, Style: LongInt): LongInt; cdecl;
begin
  Result := UiLineH - 13;
end;

{ ---- Pictures and shapes ------------------------------------------------- }

procedure cbDrawGraphics(T: PGraalTexture; X, Y, SX, SY, SW, SH: LongInt; M: Cardinal); cdecl;
var
  I, J: Integer;
  C: Cardinal;
begin
  for J := 0 to SH - 1 do
    for I := 0 to SW - 1 do
    begin
      C := Modulate(TexPixel(T, SX + I, SY + J), M);
      if (C shr 24) <> 0 then PutPixel(X + I, Y + J, C);
    end;
end;

procedure cbDrawStretched(T: PGraalTexture; X, Y, W, H, SX, SY, SW, SH: LongInt; M: Cardinal); cdecl;
var
  I, J: Integer;
  C: Cardinal;
begin
  if (W <= 0) or (H <= 0) then Exit;
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
    begin
      C := Modulate(TexPixel(T, SX + (I * SW) div W, SY + (J * SH) div H), M);
      if (C shr 24) <> 0 then PutPixel(X + I, Y + J, C);
    end;
end;

procedure cbFillRect(X, Y, W, H: LongInt; Color: Cardinal); cdecl;
var
  I, J: Integer;
begin
  for J := Y to Y + H - 1 do
    for I := X to X + W - 1 do
      PutPixel(I, J, Color);
end;

procedure cbLine(X0, Y0, X1, Y1: LongInt; Color: Cardinal); cdecl;
var
  DX, DY, SX, SY, Err, E2: Integer;
begin
  DX := Abs(X1 - X0);
  DY := -Abs(Y1 - Y0);
  if X0 < X1 then SX := 1 else SX := -1;
  if Y0 < Y1 then SY := 1 else SY := -1;
  Err := DX + DY;
  while True do
  begin
    PutPixel(X0, Y0, Color);
    if (X0 = X1) and (Y0 = Y1) then Break;
    E2 := 2 * Err;
    if E2 >= DY then begin Inc(Err, DY); Inc(X0, SX); end;
    if E2 <= DX then begin Inc(Err, DX); Inc(Y0, SY); end;
  end;
end;

procedure cbLineEx(X0, Y0, X1, Y1, Width: Single; Color: Cardinal); cdecl;
begin
  cbLine(Round(X0), Round(Y0), Round(X1), Round(Y1), Color);
end;

procedure cbPolygonEx(T: PGraalTexture; XYUV: PSingle; Points: LongInt; Color: Cardinal); cdecl;
var
  I: Integer;
  P: PSingle;
  X0, Y0, X1, Y1: Integer;
begin
  { Outline only for now; filled and textured polygons come with TShowImg. }
  if (XYUV = nil) or (Points < 2) then Exit;
  for I := 0 to Points - 1 do
  begin
    P := XYUV;
    Inc(P, I * 4);
    X0 := Round(P^);
    Inc(P);
    Y0 := Round(P^);
    P := XYUV;
    Inc(P, ((I + 1) mod Points) * 4);
    X1 := Round(P^);
    Inc(P);
    Y1 := Round(P^);
    cbLine(X0, Y0, X1, Y1, Color);
  end;
end;

function cbTexWidth(T: PGraalTexture): LongInt; cdecl;
begin
  if T = nil then Result := 0 else Result := T^.Width;
end;

function cbTexHeight(T: PGraalTexture): LongInt; cdecl;
begin
  if T = nil then Result := 0 else Result := T^.Height;
end;

function cbTexPixel(T: PGraalTexture; X, Y: LongInt): Cardinal; cdecl;
begin
  Result := TexPixel(T, X, Y);
end;

function cbPixelTransparent(T: PGraalTexture; X, Y: LongInt): LongInt; cdecl;
begin
  Result := Ord((TexPixel(T, X, Y) shr 24) = 0);
end;

function cbRectTransparent(T: PGraalTexture; X, Y, W, H: LongInt): LongInt; cdecl;
var
  I, J: Integer;
begin
  Result := 1;
  for J := Y to Y + H - 1 do
    for I := X to X + W - 1 do
      if (TexPixel(T, I, J) shr 24) <> 0 then Exit(0);
end;

function cbBitmapArrayRects(T: PGraalTexture; Out_: Pointer; Max: LongInt): LongInt; cdecl;
begin
  { The engine splits bitmap arrays itself (common/torque/gui). }
  Result := 0;
end;

{ ---- Panels -------------------------------------------------------------- }

function cbCreatePanel(W, H: LongInt): LongInt; cdecl;
begin
  Result := NewSurface(Panels, W, H);
end;

procedure cbDeletePanel(P: LongInt); cdecl;
begin
  FreeSurface(Panels, P);
end;

procedure cbPanelGraphics(P: LongInt; T: PGraalTexture; X, Y, SX, SY, SW, SH: LongInt); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(Panels, P);
  if S <> nil then TexToSurface(T, S, X, Y, SX, SY, SW, SH);
end;

procedure cbPanelStretched(P: LongInt; T: PGraalTexture; X, Y, W, H, SX, SY, SW, SH: LongInt); cdecl;
var
  S: TGSurface;
  I, J: Integer;
  C: Cardinal;
begin
  S := GetSurface(Panels, P);
  if (S = nil) or (W <= 0) or (H <= 0) then Exit;
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
    begin
      C := TexPixel(T, SX + (I * SW) div W, SY + (J * SH) div H);
      if (C shr 24) <> 0 then S.FillRect(X + I, Y + J, 1, 1, C);
    end;
end;

procedure cbPanelPalette(P: LongInt; Indexes: PByte; Palette: PCardinal; X, Y, W, H: LongInt); cdecl;
var
  S: TGSurface;
  I, J: Integer;
  Ix: PByte;
  Pal: PCardinal;
begin
  S := GetSurface(Panels, P);
  if (S = nil) or (Indexes = nil) or (Palette = nil) then Exit;
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
    begin
      Ix := Indexes;
      Inc(Ix, I + J * W);
      Pal := Palette;
      Inc(Pal, Ix^);
      S.FillRect(X + I, Y + J, 1, 1, Pal^);
    end;
end;

procedure cbPanelPixels(P: LongInt; Px: PCardinal; X, Y, W, H: LongInt); cdecl;
var
  S: TGSurface;
  I, J: Integer;
  Q: PCardinal;
begin
  S := GetSurface(Panels, P);
  if (S = nil) or (Px = nil) then Exit;
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
    begin
      Q := Px;
      Inc(Q, I + J * W);
      S.FillRect(X + I, Y + J, 1, 1, Q^);
    end;
end;

procedure cbPanelFill(P, X, Y, W, H: LongInt; Color: Cardinal); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(Panels, P);
  if S <> nil then S.FillRect(X, Y, W, H, Color);
end;

procedure cbDrawPanel(P, X, Y: LongInt; M: Cardinal); cdecl;
var
  S: TGSurface;
begin
  S := GetSurface(Panels, P);
  if S <> nil then SurfaceToScreen(S, X, Y, 0, 0, S.Width, S.Height, M);
end;

procedure cbTriangleStrip(P: LongInt; XYUV: PSingle; Points: LongInt; M: Cardinal); cdecl;
begin
  Note('DrawTriangleStripPanel ' + IntToStr(P) + ' ' + IntToStr(Points));
end;

function cbSavePanel(P: LongInt; FileName: PAnsiChar): LongInt; cdecl;
var
  S: TGSurface;
begin
  Result := 0;
  S := GetSurface(Panels, P);
  if (S = nil) or (FileName = nil) then Exit;
  try
    S.SaveBMP(Str(FileName));
    Result := 1;
  except
    Result := 0;
  end;
end;

{ ---- Flash: the original hosts an ActiveX player; the rebuild has none. -- }

function cbFlashCreate: LongInt; cdecl;
begin
  Note('CreateFlashPanel');
  Result := 0;
end;

procedure cbFlashInt(FP: LongInt); cdecl;
begin
  Note('Flash ' + IntToStr(FP));
end;

procedure cbFlashRect(FP, X, Y, W, H: LongInt); cdecl;
begin
  Note('Flash rect ' + IntToStr(FP));
end;

procedure cbFlashText(FP: LongInt; S: PAnsiChar); cdecl;
begin
  Note('Flash ' + IntToStr(FP) + ' ' + Str(S));
end;

procedure cbFlashFlag(FP, V: LongInt); cdecl;
begin
  Note('Flash ' + IntToStr(FP) + ' ' + IntToStr(V));
end;

function cbFlashGet(FP: LongInt; S: PAnsiChar): PAnsiChar; cdecl;
begin
  RetText := '';
  Result := PAnsiChar(RetText);
end;

procedure cbFlashSet(FP: LongInt; N, V: PAnsiChar); cdecl;
begin
  Note('Flash ' + IntToStr(FP) + ' ' + Str(N) + '=' + Str(V));
end;

{ ---- 5.0 only ---------------------------------------------------------- }

procedure cbColorMatrix(M: PSingle); cdecl;
begin
  Note('PushColorMatrix');
end;

procedure cbPopColorMatrix; cdecl;
begin
  Note('PopColorMatrix');
end;

function cbScreenCapture(Out_: PCardinal; Max: LongInt): LongInt; cdecl;
var
  I, N: Integer;
begin
  N := Length(Cur.Screen.Pixels);
  if (Out_ <> nil) and (Max >= N) then
    for I := 0 to N - 1 do
    begin
      Out_^ := Cur.Screen.Pixels[I];
      Inc(Out_);
    end;
  Result := N;
end;

procedure cbForceTransparency(T: PGraalTexture; On_: LongInt); cdecl;
begin
  Note('ForceTextureTransparency ' + IntToStr(On_));
end;

{ ---- Clipboard ----------------------------------------------------------- }

procedure cbSetClipboard(S: PAnsiChar); cdecl;
begin
  if S = nil then Cur.Clipboard := '' else Cur.Clipboard := AnsiString(S);
end;

function cbGetClipboard: PAnsiChar; cdecl;
begin
  RetText := Cur.Clipboard;
  Result := PAnsiChar(RetText);
end;

{ ---- Window, files, shell ------------------------------------------------ }

function cbActive: LongInt; cdecl;
begin
  Result := Ord(Cur.Active);
end;

function cbZero: LongInt; cdecl;
begin
  Result := 0;
end;

procedure cbInt(V: LongInt); cdecl;
begin
  Note('int ' + IntToStr(V));
end;

procedure cbText(S: PAnsiChar); cdecl;
begin
  Note('text ' + Str(S));
end;

procedure cbText2(A, B: PAnsiChar); cdecl;
begin
  Note('text ' + Str(A) + ' | ' + Str(B));
end;

procedure cbNone; cdecl;
begin
  Note('call');
end;

function cbEmptyText(V: LongInt): PAnsiChar; cdecl;
begin
  RetText := '';
  Result := PAnsiChar(RetText);
end;

{ The folder the launcher runs from, with a trailing separator. }
function cbHomeDir: PAnsiChar; cdecl;
begin
  RetText := AnsiString(ExtractFilePath(ParamStr(0)));
  Result := PAnsiChar(RetText);
end;

function cbKeyCode(S: PAnsiChar): LongInt; cdecl;
begin
  Result := 0;
end;

procedure cbScanProgress(S: PAnsiChar; Done, Total: LongInt); cdecl;
begin
  Note('scan ' + Str(S) + ' ' + IntToStr(Done) + '/' + IntToStr(Total));
end;

procedure cbScreenshot(FileName: PAnsiChar); cdecl;
begin
  if FileName <> nil then
  try
    Cur.Screen.SaveBMP(Str(FileName));
  except
  end;
end;

procedure cbLog(S: PAnsiChar); cdecl;
begin
  Cur.Log.Add(Str(S));
end;

procedure cbMessageBox(Title, Text: PAnsiChar); cdecl;
begin
  Note('MessageBox ' + Str(Title) + ': ' + Str(Text));
end;

procedure cbServerText(S: PAnsiChar); cdecl;
begin
  Note('ServerText ' + Str(S));
end;

procedure cbServerLogin(S: PAnsiChar); cdecl;
begin
  Note('ServerLogin ' + Str(S));
end;

procedure cbListerConnect; cdecl;
begin
  Note('ServerListerConnect');
end;

procedure cbStart3D; cdecl;
begin
  Note('StartGraal3D');
end;

procedure cbShutdownPrep; cdecl;
begin
  Note('PrepareShutdownGraal');
end;

procedure cbShutdown; cdecl;
begin
  Note('ShutdownGraal');
end;

{ ---- The slot table ------------------------------------------------------ }

type
  THostSlot = record
    Name: string;
    Fn: Pointer;
  end;

const
  NHost = 102;

var
  HostSlots: array[0..NHost - 1] of THostSlot;

procedure FillHostSlots;
var
  N: Integer;

  procedure Add(const Name: string; Fn: Pointer);
  begin
    HostSlots[N].Name := Name;
    HostSlots[N].Fn := Fn;
    Inc(N);
  end;

begin
  N := 0;
  Add('GetScreenWidth', @cbScreenWidth);
  Add('GetScreenHeight', @cbScreenHeight);
  Add('SetClippingRectangle', @cbClip);
  Add('GetClippingRectangle', @cbGetClip);
  Add('PushGraal2DMatrix', @cbPushMatrix);
  Add('PopGraal2DMatrix', @cbPopMatrix);
  Add('IsGraal2DMatrixActivated', @cbMatrixActive);
  Add('GetGraal2DMatrix', @cbGetMatrix);
  Add('CreateTilesBuffer', @cbCreateTiles);
  Add('DeleteTilesBuffer', @cbDeleteTiles);
  Add('SetTilesBufferSize', @cbResizeTiles);
  Add('ScrollTilesBuffer', @cbScrollTiles);
  Add('StartTilesDrawing', @cbStartTiles);
  Add('EndTilesDrawing', @cbEndTiles);
  Add('Draw2DTile', @cbDrawTile);
  Add('Clear2DTile', @cbClearTile);
  Add('Draw3DTile', @cbDrawTile);
  Add('Clear3DTile', @cbClearTile);
  Add('DrawTilesOnScreen', @cbTilesOnScreen);
  Add('DrawText', @cbDrawText);
  Add('DrawShadowedText', @cbDrawShadowed);
  Add('GetTextWidth', @cbTextWidth);
  Add('GetTextHeight', @cbTextHeight);
  Add('GetTextAscent', @cbTextAscent);
  Add('GetTextDescent', @cbTextDescent);
  Add('DrawGraphics', @cbDrawGraphics);
  Add('DrawGraphicsStretched', @cbDrawStretched);
  Add('FillScreenRectangle', @cbFillRect);
  Add('DrawLine', @cbLine);
  Add('DrawLine2', @cbLineEx);
  Add('DrawPolygonEx', @cbPolygonEx);
  Add('GetTextureWidth', @cbTexWidth);
  Add('GetTextureHeight', @cbTexHeight);
  Add('GetTexturePixel', @cbTexPixel);
  Add('IsPixelTransparent', @cbPixelTransparent);
  Add('IsRectangleTransparent', @cbRectTransparent);
  Add('GetBitmapArrayRects', @cbBitmapArrayRects);
  Add('CreateDrawingPanel', @cbCreatePanel);
  Add('DeleteDrawingPanel', @cbDeletePanel);
  Add('DrawPanelGraphics', @cbPanelGraphics);
  Add('DrawPanelGraphicsStretched', @cbPanelStretched);
  Add('DrawPanelGraphicsPalette', @cbPanelPalette);
  Add('DrawPanelGraphicsPixels', @cbPanelPixels);
  Add('FillPanelRectangle', @cbPanelFill);
  Add('DrawDrawingPanel', @cbDrawPanel);
  Add('DrawTriangleStripPanel', @cbTriangleStrip);
  Add('SaveDrawingPanel', @cbSavePanel);
  Add('CreateFlashPanel', @cbFlashCreate);
  Add('DeleteFlashPanel', @cbFlashInt);
  Add('SetFlashPanelSize', @cbFlashRect);
  Add('SetFlashPanelClipping', @cbFlashRect);
  Add('SetFlashPanelFile', @cbFlashText);
  Add('SetFlashPanelVisible', @cbFlashFlag);
  Add('SetFlashPanelLooping', @cbFlashFlag);
  Add('PlayFlashPanelMovie', @cbFlashInt);
  Add('StopFlashPanelMovie', @cbFlashInt);
  Add('GetFlashPanelVar', @cbFlashGet);
  Add('SetFlashPanelVar', @cbFlashSet);
  Add('CallFlashPanelFunction', @cbFlashGet);
  Add('SetFlashPanelGraalVar', @cbFlashSet);
  Add('SetClipBoard', @cbSetClipboard);
  Add('GetClipBoard', @cbGetClipboard);
  Add('GetGraalApplicationActive', @cbActive);
  Add('PushColorMatrix', @cbColorMatrix);
  Add('PopColorMatrix', @cbPopColorMatrix);
  Add('GetGraalScreenCapture', @cbScreenCapture);
  Add('ForceTextureTransparency', @cbForceTransparency);
  Add('GetGraalIsFullscreen', @cbZero);
  Add('SetGraalFullscreen', @cbInt);
  Add('ShowGraalWindow', @cbInt);
  Add('MakeGraalScreenshot', @cbScreenshot);
  Add('SetGraalStatusIcons', @cbInt);
  Add('GetGraalActionKeyText', @cbEmptyText);
  Add('GetVirtualKeyCode', @cbKeyCode);
  Add('SwitchToSetupMode', @cbInt);
  Add('ShowSelectPathDialog', @cbText);
  Add('PrepareShutdownGraal', @cbShutdownPrep);
  Add('ShutdownGraal', @cbShutdown);
  Add('HomeDirectory', @cbHomeDir);
  Add('ShowFileScanMessage', @cbScanProgress);
  Add('UpdateGraalFile', @cbText);
  Add('SetGraalLanguage', @cbText);
  Add('SetGraalTranslationURL', @cbText);
  Add('OpenURL', @cbText);
  Add('OpenURL2', @cbText);
  Add('LogGraalMessage', @cbLog);
  Add('OpenExternalLogWindow', @cbNone);
  Add('OpenExternalPlayerlist', @cbNone);
  Add('ExternalPlayerlistUpdate', @cbText);
  Add('ExternalPlayerlistDelete', @cbText);
  Add('OpenExternalPM', @cbText2);
  Add('OpenExternalHistory', @cbText);
  Add('OpenExternalProfile', @cbText);
  Add('OpenExternalOptions', @cbNone);
  Add('OpenMessageBox', @cbMessageBox);
  Add('GetMicroInfoRequired', @cbZero);
  Add('SetMicroIsActivated', @cbInt);
  Add('SetMicroVolume', @cbInt);
  Add('ReceiveServerText', @cbServerText);
  Add('OnServerLogin', @cbServerLogin);
  Add('OnServerListerConnect', @cbListerConnect);
  Add('StartGraal3D', @cbStart3D);
  Assert(N = NHost);
end;

function HostSlotCount: Integer;
begin
  Result := NHost;
end;

function HostSlotName(I: Integer): string;
begin
  if (I < 0) or (I >= NHost) then Result := '' else Result := HostSlots[I].Name;
end;

function FindHost(const Name: string): Pointer;
var
  I: Integer;
begin
  for I := 0 to NHost - 1 do
    if HostSlots[I].Name = Name then Exit(HostSlots[I].Fn);
  Result := nil;
end;

function HostSlotFn(const Name: string): Pointer;
begin
  Result := FindHost(Name);
end;

{ ---- TEngineHost --------------------------------------------------------- }

constructor TEngineHost.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Screen := TGSurface.Create(AWidth, AHeight);
  Screen.Fill($FF000000);
  ClipW := AWidth;
  ClipH := AHeight;
  Log := TStringList.Create;
  Events := TStringList.Create;
  FMissing := TStringList.Create;
  Active := True;
  FLib := 0;
end;

destructor TEngineHost.Destroy;
begin
  Unload;
  Screen.Free;
  Log.Free;
  Events.Free;
  FMissing.Free;
  inherited;
end;

procedure TEngineHost.SetError(const S: string);
begin
  FError := S;
end;

function TEngineHost.Loaded: Boolean;
begin
  Result := FLib <> 0;
end;

function TEngineHost.Load(const LibPath: string): Boolean;
var
  Abi: TIntFn;
begin
  Result := False;
  if Loaded then Unload;
  FLibPath := LibPath;
  FLib := PtrUInt(LoadLibrary(LibPath));
  if FLib = 0 then
  begin
    SetError('cannot load ' + LibPath);
    Exit;
  end;
  Abi := TIntFn(GetProcedureAddress(TLibHandle(FLib), 'graalengine_abi'));
  if not Assigned(Abi) then
  begin
    SetError(LibPath + ' is not a rebuilt engine library');
    Unload;
    Exit;
  end;
  if Abi() <> EngineAbi then
  begin
    SetError(Format('%s has interface %d, this launcher needs %d', [LibPath, Abi(), EngineAbi]));
    Unload;
    Exit;
  end;
  Cur := Self;
  Result := True;
end;

function TEngineHost.SlotCount: Integer;
var
  F: TIntFn;
begin
  Result := 0;
  if not Loaded then Exit;
  F := TIntFn(GetProcedureAddress(TLibHandle(FLib), 'graalengine_slotCount'));
  if Assigned(F) then Result := F();
end;

function TEngineHost.SlotName(I: Integer): string;
var
  F: TNameFn;
begin
  Result := '';
  if not Loaded then Exit;
  F := TNameFn(GetProcedureAddress(TLibHandle(FLib), 'graalengine_slotName'));
  if Assigned(F) then Result := Str(F(I));
end;

function TEngineHost.SlotBuilds(I: Integer): Integer;
var
  F: TBuildsFn;
begin
  Result := 0;
  if not Loaded then Exit;
  F := TBuildsFn(GetProcedureAddress(TLibHandle(FLib), 'graalengine_slotBuilds'));
  if Assigned(F) then Result := F(I);
end;

function TEngineHost.RegisterSlots(Build: Integer): Integer;
var
  I: Integer;
  Name: string;
  Fn: Pointer;
  Setter: TSetter;
begin
  Result := 0;
  FMissing.Clear;
  if not Loaded then Exit;
  for I := 0 to SlotCount - 1 do
  begin
    if (SlotBuilds(I) and Build) = 0 then Continue;
    Name := SlotName(I);
    Setter := TSetter(GetProcedureAddress(TLibHandle(FLib), AnsiString('graal_set' + Name)));
    Fn := FindHost(Name);
    if not Assigned(Setter) or (Fn = nil) then
    begin
      FMissing.Add(Name);
      Continue;
    end;
    Setter(Fn);
    Inc(Result);
  end;
end;

function TEngineHost.Initialize(const ExePath: string): Boolean;
var
  F: TInit;
begin
  Result := False;
  if not Loaded then Exit;
  F := TInit(GetProcedureAddress(TLibHandle(FLib), 'graal_engineInitialize'));
  Result := Assigned(F) and (F(PAnsiChar(AnsiString(ExePath))) <> 0);
end;

procedure Call0(Lib: PtrUInt; const Name: AnsiString);
var
  F: TProc0;
begin
  if Lib = 0 then Exit;
  F := TProc0(GetProcedureAddress(TLibHandle(Lib), Name));
  if Assigned(F) then F();
end;

procedure TEngineHost.LoadGui;
begin
  Call0(FLib, 'loadGraalGui');
end;

procedure TEngineHost.Render;
begin
  Cur := Self;
  Call0(FLib, 'renderGraalCanvas');
end;

procedure TEngineHost.Key(VK, Ch, Mods: Integer; Down: Boolean);
var
  F: TKeyProc;
begin
  if not Loaded then Exit;
  F := TKeyProc(GetProcedureAddress(TLibHandle(FLib), 'invokeGraalKeyboardEvent'));
  if Assigned(F) then F(VK, Ch, Mods, Ord(Down));
end;

procedure TEngineHost.Mouse(X, Y, Action, Button, Clicks, Mods, Wheel: Integer);
var
  F: TMouseProc;
begin
  if not Loaded then Exit;
  F := TMouseProc(GetProcedureAddress(TLibHandle(FLib), 'invokeGraalMouseEvent'));
  if Assigned(F) then F(X, Y, Action, Button, Clicks, Mods, Wheel);
end;

procedure TEngineHost.StartOffline;
begin
  Call0(FLib, 'startOfflineMode');
end;

procedure TEngineHost.Connect(const Name, Host: AnsiString; Port: Integer);
var
  F: TConnectProc;
begin
  if not Loaded then Exit;
  F := TConnectProc(GetProcedureAddress(TLibHandle(FLib), 'connectToGraalServer'));
  if Assigned(F) then F(PAnsiChar(Name), PAnsiChar(Host), Port);
end;

procedure TEngineHost.Shutdown;
begin
  Call0(FLib, 'prepareGraalShutdown');
  Call0(FLib, 'shutdownGraalEngine');
end;

procedure TEngineHost.Unload;
begin
  if FLib <> 0 then
  begin
    Shutdown;
    UnloadLibrary(TLibHandle(FLib));
    FLib := 0;
  end;
  if Cur = Self then
  begin
    Cur := nil;
    FreeAll(TileBufs);
    FreeAll(Panels);
    Matrices := nil;
  end;
end;

initialization
  FillHostSlots;
end.
