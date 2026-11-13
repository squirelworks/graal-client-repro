{ The 5.12 launcher against the rebuilt engine library
  (common/cpp/graalengine, Track C3).

  Loads the library built next to this program, registers the 5.0
  launcher's callback slots, tells the library it is 5.12, initialises,
  builds the canvas, draws a frame and sends a key and a click. The drawing
  callbacks themselves are checked by the 4.04r2 launcher's test (the same
  GEngineHost). No original files. }
program TestEngineHost512;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GEngineHost in '../../common/GEngineHost.pas',
  Protocol512 in '../src/Protocol512.pas';

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
  N, I, Build50: Integer;
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
    Build50 := 0;
    for I := 0 to H.SlotCount - 1 do
      if (H.SlotBuilds(I) and EngineBuild50) <> 0 then Inc(Build50);
    N := H.RegisterSlots(EngineBuild50);
    Check((N = Build50) and (N = 95), Format('registers the 5.0 launcher''s 95 slots (%d of %d)', [N, Build50]));
    Check(H.Missing.Count = 0, 'no 5.0 slot without a launcher function ' + H.Missing.CommaText);
    Check(H.SetBuild(ClientBuildLabel), 'the library has a 5.12 build row');
    Check(not H.SetBuild('9.99'), 'a build with no row is refused');
    Check(H.Initialize(ExtractFilePath(ParamStr(0)) + 'Graal.exe'), 'graal_engineInitialize returns success');
    Check(H.Log.Count = 0, 'the 5.0 launcher has no LogGraalMessage, so nothing comes back through it');
    H.LoadGui;
    H.ClipW := 1;
    H.Render;
    Check((H.ClipX = 0) and (H.ClipY = 0) and (H.ClipW = 640) and (H.ClipH = 480),
      'renderGraalCanvas reads the screen size and clips to it');
    H.Key($26, 0, 0, True);
    H.Mouse(10, 10, EngineMouseDown, 0, 1, 0, 0);
    H.Render;
    { A 3D server (Track C4): StartGraal3D, then on the next frame the 3D
      library is loaded beside the engine and the server connected again.
      Nothing listens on loopback port 1 (TCP) or 2 (the Torque link); the
      link itself is tested in common/cpp/graal3dengine. }
    H.Connect('3 Lab', '127.0.0.1', 1);
    Check(HasEvent(H, 'StartGraal3D'), 'a "3 " server asks the launcher for 3D');
    H.Render;
    if FileExists(ExtractFilePath(ParamStr(0)) + Graal3DLibName) then
    begin
      Check(H.Loaded3D and HasEvent(H, 'Graal3D loaded'), 'the launcher loads ' + Graal3DLibName);
      Check(H.Graal3DLoginStep = 0, 'no mission start without a 3D server');
      H.Render;
    end
    else
      Check(not H.Loaded3D and (H.Log.IndexOf('You need to download Graal3D for playing this server!') >= 0),
        'without the 3D library the launcher says so');
    H.Unload;
    Check(not H.Loaded, 'unloads');
    Check(not H.Loaded3D, 'unloads the 3D library too');
  finally
    H.Free;
  end;
end;

begin
  TestEngine;
  if Failed > 0 then
  begin
    WriteLn(Failed, ' check(s) failed');
    Halt(1);
  end;
  WriteLn('all checks passed');
end.
