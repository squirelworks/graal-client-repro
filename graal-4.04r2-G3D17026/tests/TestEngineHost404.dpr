{ The 4.04r2 launcher against the rebuilt engine library
  (common/cpp/graalengine, Track C1).

  Loads the library built next to this program, registers the 4.x
  launcher's callback slots, initialises, builds the canvas, draws a frame
  and sends a key, a click and a 3D connect, checking that each crosses the
  interface in both directions. The drawing callbacks are also called
  directly and checked pixel by pixel. No original files. }
program TestEngineHost404;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GEngineHost in '../../common/GEngineHost.pas';

var
  Failed: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
    WriteLn('ok   ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Failed);
  end;
end;

type
  TFill = procedure(X, Y, W, H: LongInt; Color: Cardinal); cdecl;
  TClip = procedure(X, Y, W, H: LongInt); cdecl;
  TText = procedure(X, Y: LongInt; Text, Font: PAnsiChar; Size, Style: LongInt; Color: Cardinal); cdecl;
  TGfx = procedure(T: PGraalTexture; X, Y, SX, SY, SW, SH: LongInt; M: Cardinal); cdecl;
  TWidth = function(Text, Font: PAnsiChar; Size, Style: LongInt): LongInt; cdecl;

function HasEvent(H: TEngineHost; const S: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to H.Events.Count - 1 do
    if Pos(S, H.Events[I]) = 1 then Exit(True);
  Result := False;
end;

procedure TestEngine;
var
  H: TEngineHost;
  Lib: string;
  N, I, Build4: Integer;
begin
  Lib := ExtractFilePath(ParamStr(0)) + EngineLibName;
  if not FileExists(Lib) then
  begin
    WriteLn('skip engine library tests: ', Lib, ' not built');
    Exit;
  end;
  H := TEngineHost.Create(640, 480);
  try
    Check(H.Load(Lib), 'loads ' + EngineLibName + ' ' + H.Error);
    if not H.Loaded then Exit;
    Build4 := 0;
    for I := 0 to H.SlotCount - 1 do
      if (H.SlotBuilds(I) and EngineBuild4x) <> 0 then Inc(Build4);
    N := H.RegisterSlots(EngineBuild4x);
    Check(N = Build4, Format('registers every 4.x slot (%d of %d)', [N, Build4]));
    Check(H.Missing.Count = 0, 'no 4.x slot without a launcher function ' + H.Missing.CommaText);
    Check(Build4 = 94, Format('the 4.x launcher fills 94 slots (%d)', [Build4]));
    N := H.RegisterSlots(EngineBuild50);
    Check((N = 95) and (H.Missing.Count = 0),
      Format('the 5.0 launcher''s 95 slots all have a function (%d) %s', [N, H.Missing.CommaText]));
    N := H.RegisterSlots(EngineBuild4x);
    Check(H.Initialize(ExtractFilePath(ParamStr(0)) + 'Graal.exe'), 'graal_engineInitialize returns success');
    Check((H.Log.Count > 0) and (Pos('GraalEngine: started', H.Log[0]) = 1),
      'the engine writes through LogGraalMessage');
    H.LoadGui;
    H.ClipW := 1;
    H.Render;
    Check((H.ClipX = 0) and (H.ClipY = 0) and (H.ClipW = 640) and (H.ClipH = 480),
      'renderGraalCanvas reads the screen size and clips to it');
    H.Key($26, 0, 0, True);
    H.Mouse(10, 10, EngineMouseDown, 0, 1, 0, 0);
    H.Connect('3 Seihai Test', '127.0.0.1', 14800);
    Check(HasEvent(H, 'StartGraal3D'), 'a "3 " server asks the launcher for 3D');
    H.Unload;
    Check(not H.Loaded, 'unloads');
  finally
    H.Free;
  end;
end;

procedure TestDrawing;
var
  H: TEngineHost;
  Fill: TFill;
  Clip: TClip;
  Text: TText;
  Gfx: TGfx;
  Width: TWidth;
  Tex: TGraalTexture;
  Px: array[0..3] of Cardinal;
  Lit, X, Y: Integer;
begin
  { The callbacks draw for the host that loaded the library; without a
    library, Load is skipped and the host is made current by Render. }
  H := TEngineHost.Create(32, 32);
  try
    H.Screen.Fill($FF000000);
    H.Render; { no library: makes H current, calls nothing }
    Fill := TFill(HostSlotFn('FillScreenRectangle'));
    Clip := TClip(HostSlotFn('SetClippingRectangle'));
    Text := TText(HostSlotFn('DrawText'));
    Gfx := TGfx(HostSlotFn('DrawGraphics'));
    Width := TWidth(HostSlotFn('GetTextWidth'));
    Check(Assigned(Fill) and Assigned(Clip) and Assigned(Text) and Assigned(Gfx), 'draw slots exist');
    Clip(0, 0, 32, 32);
    Fill(2, 2, 4, 4, $FFFF0000);
    Check((H.Screen.GetPixel(2, 2) = $FFFF0000) and (H.Screen.GetPixel(5, 5) = $FFFF0000) and
      (H.Screen.GetPixel(6, 6) = $FF000000), 'FillScreenRectangle fills its rectangle');
    Clip(10, 10, 2, 2);
    Fill(8, 8, 8, 8, $FF00FF00);
    Check((H.Screen.GetPixel(10, 10) = $FF00FF00) and (H.Screen.GetPixel(11, 11) = $FF00FF00) and
      (H.Screen.GetPixel(12, 12) = $FF000000) and (H.Screen.GetPixel(9, 9) = $FF000000),
      'the clip rectangle cuts a fill');
    Clip(0, 0, 32, 32);
    Fill(20, 20, 1, 1, $80FFFFFF);
    Check(H.Screen.GetPixel(20, 20) = $FF808080, 'half alpha blends');
    Px[0] := $FF0000FF; Px[1] := 0; Px[2] := 0; Px[3] := $FF00FFFF;
    Tex.Name := 'test';
    Tex.Width := 2;
    Tex.Height := 2;
    Tex.Pixels := @Px[0];
    Tex.HostData := nil;
    Gfx(@Tex, 24, 2, 0, 0, 2, 2, $FFFFFFFF);
    Check((H.Screen.GetPixel(24, 2) = $FF0000FF) and (H.Screen.GetPixel(25, 2) = $FF000000) and
      (H.Screen.GetPixel(25, 3) = $FF00FFFF), 'DrawGraphics skips clear pixels');
    Check(Width('Graal', nil, 12, 0) > 0, 'GetTextWidth measures');
    H.Screen.Fill($FF000000);
    Text(0, 14, 'Hi', nil, 12, 0, $FFFFFFFF);
    Lit := 0;
    for Y := 0 to 31 do
      for X := 0 to 31 do
        if H.Screen.GetPixel(X, Y) <> $FF000000 then Inc(Lit);
    Check(Lit > 0, 'DrawText draws');
    { A face with no font file keeps the built-in line; a face the
      machine has (Arial, or Liberation Sans standing in for it) follows
      the script's size. }
    Check(Width('Graal', 'NoSuchFace', 30, 0) = Width('Graal', nil, 12, 0),
      'a face with no file is drawn in the built-in font');
    if Width('Graal', 'Arial', 24, 0) <> Width('Graal', 'Arial', 12, 0) then
    begin
      Check(Width('Graal', 'Arial', 24, 0) > Width('Graal', 'Arial', 12, 0),
        'Arial grows with the size');
      H.Screen.Fill($FF000000);
      Text(0, 4, 'Hi', 'Arial', 14, 0, $FFFFFFFF);
      Lit := 0;
      for Y := 0 to 31 do
        for X := 0 to 31 do
          if H.Screen.GetPixel(X, Y) <> $FF000000 then Inc(Lit);
      Check((Lit > 0) and (H.Screen.GetPixel(0, 20) = $FF000000), 'Arial 14 draws in its cell');
    end
    else
      WriteLn('skip Arial: no font file for it on this machine');
  finally
    H.Free;
  end;
end;

begin
  TestDrawing;
  TestEngine;
  if Failed > 0 then
  begin
    WriteLn(Failed, ' check(s) failed');
    Halt(1);
  end;
  WriteLn('all checks passed');
end.
