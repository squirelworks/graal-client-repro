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
  Protocol512 in '../src/Protocol512.pas',
  GUiFont in '../../common/GUiFont.pas',
  PlayerList512 in '../src/PlayerList512.pas';

type
  TTextFn = procedure(S: PAnsiChar); cdecl;
  TListUpdateFn = procedure(Id: LongInt; Nick, Head, Props: PAnsiChar; Flags: LongInt); cdecl;
  TListDeleteFn = procedure(Id: LongInt); cdecl;
  TMessageBoxFn = procedure(Title, Text: PAnsiChar; Kind: LongInt); cdecl;

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

{ Draws the list with one other player and looks for ink on that row
  (under Normal, the fourth group) and none on an empty group's row. }
procedure TestDrawList(H: TEngineHost);
var
  S: TGSurface;
  X, Y, Ink, RowY: Integer;
begin
  S := TGSurface.Create(1, 1);
  try
    TListUpdateFn(HostSlotFn('ExternalPlayerlistUpdate'))(7, 'lab205', '', 'account=pc:1,level=b.nw,communityname=,attr[1]=', $2000);
    DrawPlayerList(S, H, nil);
    Check((S.Width = PlayerListW) and (S.Height = PlayerListH), 'the Players window is drawn at its size');
    { groups from y 32, 20 px apart: Staff, Buddies, Guild, Normal, then the row }
    RowY := 32 + 4 * 20;
    Ink := 0;
    for Y := RowY + 2 to RowY + 17 do
      for X := 40 to 120 do
        if S.GetPixel(X, Y) and $FFFFFF < $808080 then Inc(Ink);
    Check(Ink > 20, Format('the other player''s nick is drawn under Normal (%d dark pixels)', [Ink]));
    TListDeleteFn(HostSlotFn('ExternalPlayerlistDelete'))(7);
  finally
    S.Free;
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
    { The player list, as the lab's 5.12 engine reported it. }
    TTextFn(HostSlotFn('SetGraalStatusIcons'))('Online,Away,DND,Eating,Hiding,No PMs,RPing,Sparring,PKing');
    Check((H.Statuses.Count = 9) and (H.Statuses[5] = 'No PMs'), 'SetGraalStatusIcons fills the Status names');
    TListUpdateFn(HostSlotFn('ExternalPlayerlistUpdate'))(1, '', '', 'account=guest,level=a.nw,communityname=,attr[1]=', $4000);
    TListUpdateFn(HostSlotFn('ExternalPlayerlistUpdate'))(4, 'lab205', 'head0.png', 'account=pc:1,level=b.nw,communityname=guest,attr[1]=', $2000);
    TListUpdateFn(HostSlotFn('ExternalPlayerlistUpdate'))(4, 'lab205', 'head25.png', 'account=pc:1,level=b.nw,communityname=guest,attr[1]=', $2000);
    Check((H.OnlineCount = 2) and (H.Players[1].Head = 'head25.png'), 'ExternalPlayerlistUpdate adds a row, then updates it in place');
    TListDeleteFn(HostSlotFn('ExternalPlayerlistDelete'))(4);
    Check((H.OnlineCount = 1) and (H.PlayerIndex(1) = 0) and (H.PlayerIndex(4) = -1), 'ExternalPlayerlistDelete removes the row by id');
    { The Players window and tray tip, as the lab's 5.12 showed them. }
    Check(PlayerListTitle(H.OnlineCount) = 'Players: 1 online', 'the window title counts the player''s own row');
    Check(TrayTip('Lab Server', 2) = 'Lab Server: 2 online', 'the tray tip names the server and the count');
    Check((PlayerGroup($4000) = -1) and (PlayerGroup($2000) = 3) and (PlayerGroup($2001) = 0),
      'own row unlisted, players under Normal, flag $0001 under Staff');
    TestDrawList(H);
    TMessageBoxFn(HostSlotFn('OpenMessageBox'))('Warning', 'You have been disconnected from the game server.', 1);
    Check((H.MessageCount = 1) and (H.MessageTitle = 'Warning'), 'OpenMessageBox keeps the warning for the launcher');
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
