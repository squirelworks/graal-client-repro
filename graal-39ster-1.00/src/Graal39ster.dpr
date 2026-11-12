{ Graal39ster: the 39ster client 1.00, rebuilt as a behavioural port.

    Graal39ster [--data DIR] [--level NAME] [--x PX --y PY]
    Graal39ster ... --frame OUT.bmp       draw one frame and exit
    Graal39ster --help

  With no --frame it opens a 640 x 480 window on level13.nw at (512, 512),
  as the original starts. This first version is a viewer: the arrow keys
  move the camera anchor 3 pixels a tick with no collision; Esc or closing
  the window ends it. Movement, animation, pause, signs and links are the
  next slices (issue #176).

  The player's own 39ster install supplies every file: put the program in
  its folder, or keep the install's files in graal-assets/39ster/ next to
  it, or name the folder with --data. }
program Graal39ster;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Graal39ster.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Graal39ster.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils, GCompat, GAssetDirs, GSurface, GWindow, GStartScreen,
  Profile39 in 'Profile39.pas',
  Tiles39 in 'Tiles39.pas',
  Camera39 in 'Camera39.pas',
  World39 in 'World39.pas';

procedure Usage;
begin
  WriteLn('Graal ', ClientBuildLabel, ' rebuild (graal-delphi)');
  WriteLn('  Graal39ster [--data DIR] [--level NAME] [--x PX --y PY] [--frame OUT.bmp]');
end;

function RunWindow(W: TWorld39): Integer;
var
  Win: TGWindow;
  T0: QWord;
begin
  Result := 0;
  Win := TGWindow.Create('Graal ' + ClientBuildLabel, ViewW, ViewH);
  try
    if not Win.Ok then
    begin
      WriteLn(ErrOutput, 'no display; use --frame OUT.bmp');
      Result := 1;
      Exit;
    end;
    while not Win.Closed do
    begin
      T0 := GetTickCount64;
      Win.Pump;
      if Win.Held[gkEscape] then Break;
      if Win.Held[gkUp] then begin Dec(W.AnchorY, MoveStep); W.Facing := fUp; end;
      if Win.Held[gkDown] then begin Inc(W.AnchorY, MoveStep); W.Facing := fDown; end;
      if Win.Held[gkLeft] then begin Dec(W.AnchorX, MoveStep); W.Facing := fLeft; end;
      if Win.Held[gkRight] then begin Inc(W.AnchorX, MoveStep); W.Facing := fRight; end;
      if W.AnchorX < 0 then W.AnchorX := 0;
      if W.AnchorY < 0 then W.AnchorY := 0;
      if W.AnchorX > 63 * TilePx then W.AnchorX := 63 * TilePx;
      if W.AnchorY > 63 * TilePx then W.AnchorY := 63 * TilePx;
      W.Draw;
      Win.Present(W.Screen);
      while GetTickCount64 - T0 < Round(NominalFrameMs) do Sleep(1);
    end;
  finally
    Win.Free;
  end;
end;

var
  W: TWorld39;
  I: Integer;
  Data, LevelName, FrameOut: string;
begin
  Data := '';
  LevelName := StartLevel;
  FrameOut := '';
  { a GUI program on Windows: write to the console it was started from }
  OpenConsoleIO;
  W := TWorld39.Create;
  try
    I := 1;
    while I <= ParamCount do
    begin
      if (ParamStr(I) = '--help') or (ParamStr(I) = '-h') then
      begin
        Usage;
        Exit;
      end
      else if (ParamStr(I) = '--data') and (I < ParamCount) then
      begin Inc(I); Data := ParamStr(I); end
      else if (ParamStr(I) = '--level') and (I < ParamCount) then
      begin Inc(I); LevelName := ParamStr(I); end
      else if (ParamStr(I) = '--x') and (I < ParamCount) then
      begin Inc(I); W.AnchorX := StrToIntDef(ParamStr(I), StartX); end
      else if (ParamStr(I) = '--y') and (I < ParamCount) then
      begin Inc(I); W.AnchorY := StrToIntDef(ParamStr(I), StartY); end
      else if (ParamStr(I) = '--frame') and (I < ParamCount) then
      begin Inc(I); FrameOut := ParamStr(I); end
      else
      begin
        WriteLn(ErrOutput, 'unknown argument ', ParamStr(I));
        Usage;
        ExitCode := 64;
        Exit;
      end;
      Inc(I);
    end;
    SetAssetRoots(Data, ClientAssetFolders);
    if not W.LoadInstall then
      WriteLn(ErrOutput, 'install: ', W.LastError, ' (drawing what is there)');
    if not W.LoadLevel(LevelName) then
    begin
      WriteLn(ErrOutput, W.LastError);
      ExitCode := 1;
      Exit;
    end;
    if FrameOut <> '' then
    begin
      W.Draw;
      W.Screen.SaveBMP(FrameOut);
      Exit;
    end;
    ExitCode := RunWindow(W);
  finally
    W.Free;
  end;
end.
