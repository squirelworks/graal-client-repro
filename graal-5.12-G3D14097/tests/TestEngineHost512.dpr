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

type
  TTextFn = procedure(S: PAnsiChar); cdecl;

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
    TTextFn(HostSlotFn('OnServerLogin'))('Lab Server');
    Check(H.ServerName = 'Lab Server', 'OnServerLogin gives the launcher the server''s name for its title');
    H.ClipW := 1;
    H.Render;
    Check((H.ClipX = 0) and (H.ClipY = 0) and (H.ClipW = 640) and (H.ClipH = 480),
      'renderGraalCanvas reads the screen size and clips to it');
    H.Key($26, 0, 0, True);
    H.Mouse(10, 10, EngineMouseDown, 0, 1, 0, 0);
    H.Render;
    H.Unload;
    Check(not H.Loaded, 'unloads');
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
