{ EditorMain: how the game enters and leaves the 2.05 built-in editor.

  2.05 (client-internals/level-editor-205.md, "Entering and leaving"):
  - F4 opens the editor; online it is refused with "You cannot open the
    editor in the online mode."
  - Entering opens the level the player stands on as a tab, read again
    from disk, and centres the view on the player.
  - Play (P) goes back to the game on the current level; a named,
    modified level is saved first.
  - Starting the client with a level file as its only argument opens that
    file in the editor (the folder becomes the current one, the local
    player stands at 30, 30.5).

  The editor and its tabs live as long as the program, so leaving and
  coming back keeps them, as the editor mode of the one 2.05 window did. }
unit EditorMain;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GWindow, Adventure;

const
  EditorOnlineRefused = 'You cannot open the editor in the online mode.';

{ Runs the editor in Win until Play or Esc. With Play, the played level is
  loaded into G and True is returned. }
function RunEditor(Win: TGWindow; G: TAdventure): Boolean;
{ The F4 handler of the game loop. }
procedure EditorKey(Win: TGWindow; G: TAdventure; Online: Boolean);
procedure FreeEditor;

implementation

uses
  SysUtils, GSurface, GLevel, GBuiltin, EditorUI, EditorDoc, EditorView;

type
  TImageSource = class
  public
    G: TAdventure;
    function Image(const Name: string): TGSurface;
  end;

var
  View: TEditorView = nil;
  NoInput: TEditorInput; { all zero: a global, so the string in it is managed }
  Source: TImageSource = nil;

function TImageSource.Image(const Name: string): TGSurface;
begin
  Result := G.Assets.Image(Name, '');
end;

procedure FreeEditor;
begin
  FreeAndNil(View);
  FreeAndNil(Source);
end;

function NowMsE: Int64;
begin
  Result := Trunc(Now * 86400000.0);
end;

{ Opens the level the player is on, centred on the player. }
procedure OpenPlayerLevel(G: TAdventure);
var
  Path, Data: string;
  D: TEditorDoc;
begin
  if G.Level.Name = '' then Exit;
  Path := G.LevelDir + G.Level.Name;
  D := nil;
  if (G.LevelDir <> '') and FileExists(Path) then
  begin
    if View.OpenFile(Path) then D := View.Editor.Doc;
  end
  else if BuiltinFile(G.Level.Name, Data) then
  begin
    D := View.Editor.NewDoc;
    if not D.OpenData(Data, G.Level.Name) then
    begin
      View.Editor.CloseDoc(View.Editor.Current);
      D := nil;
    end;
  end;
  if D = nil then Exit;
  D.ScrollX := Round((G.Player.X + 1.5) * 16) - BoardViewW div 2;
  D.ScrollY := Round((G.Player.Y + 2) * 16) - BoardViewH div 2;
end;

function RunEditor(Win: TGWindow; G: TAdventure): Boolean;
var
  I: TEditorInput;
  X, Y: Integer;
  T0: Int64;
begin
  Result := False;
  if View = nil then
  begin
    View := TEditorView.Create(G.Sheet);
    Source := TImageSource.Create;
    View.Editor.Background := 0;
  end;
  Source.G := G;
  View.Sheet := G.Sheet;
  View.Images := Source.Image;
  View.ExitCode := eeNone;
  OpenPlayerLevel(G);
  { keys held when the editor opened do not count }
  Win.TakeChars;
  Win.TakeClick(X, Y);
  Win.TakeRightClick(X, Y);
  Win.TakeWheel;
  Win.WasPressed(gkEditor);
  Win.WasPressed(gkEscape);
  while not Win.Closed do
  begin
    T0 := NowMsE;
    Win.Pump;
    I := NoInput;
    I.MouseX := Win.MouseX;
    I.MouseY := Win.MouseY;
    I.LeftPress := Win.TakeClick(I.PressX, I.PressY);
    I.RightPress := Win.TakeRightClick(I.RightX, I.RightY);
    I.Left := Win.MouseLeft or I.LeftPress;
    I.Right := Win.MouseRight or I.RightPress;
    I.Ctrl := Win.CtrlHeld;
    I.Shift := Win.ShiftHeld;
    I.Chars := Win.TakeChars;
    I.Wheel := Win.TakeWheel;
    I.Up := Win.ArrowHeld[0];
    I.LeftKey := Win.ArrowHeld[1];
    I.Down := Win.ArrowHeld[2];
    I.RightKey := Win.ArrowHeld[3];
    I.Del := Win.WasPressed(gkDelete);
    I.Ins := Win.WasPressed(gkInsert);
    I.F4 := Win.WasPressed(gkEditor);
    I.F5 := Win.WasPressed(gkLoadLevel);
    Win.WasPressed(gkEscape); { Esc comes as #27 in Chars }
    I.NowMs := T0;
    View.Step(I);
    if View.ExitCode <> eeNone then Break;
    View.Draw(G.Screen);
    Win.Present(G.Screen);
    X := 20 - Integer(NowMsE - T0);
    if X > 0 then Sleep(X);
  end;
  { the game ends on a held Esc: wait until it is let go }
  while (not Win.Closed) and Win.Held[gkEscape] do
  begin
    Win.Pump;
    Sleep(10);
  end;
  Win.TakeChars;
  if View.ExitCode = eePlay then
  begin
    if G.LoadLevelFile(View.PlayFile) then
    begin
      G.Player.Level := G.Level.Name;
      G.Log('editor: playing ' + View.PlayFile);
      Result := True;
    end
    else
      G.Log('editor: cannot play ' + View.PlayFile + ': ' + G.Level.LastError);
  end;
end;

procedure EditorKey(Win: TGWindow; G: TAdventure; Online: Boolean);
begin
  if Online then
    G.Log(EditorOnlineRefused)
  else
    RunEditor(Win, G);
end;

initialization

finalization
  FreeEditor;
end.
