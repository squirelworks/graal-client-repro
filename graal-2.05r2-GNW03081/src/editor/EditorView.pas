{ EditorView: the editor screen of the 2.05 built-in level editor.

  In 2.05 the editor is a second mode of the main window (TAdventure),
  not a separate program. The layout follows its form at 640x480:
    toolbar (0,0)-(640,33): New, Open, Save, Save as, Undo board copy,
      Cut, Copy, Paste, Delete, Turn selection into a warp field,
      Edit links, Edit signs, Edit flags, Close, and the Play button
    tab bar (0,33) 418x28, one tab per open level
    board (0,61) with its scroll bars, 16 px tiles
    side panel (418,33) 222 wide: the three palette modes
      ("Select predefined object", "Select tile", "Baddies,Npcs,Chests"),
      the palette with its scroll bars, the background tile preview and
      the status bar
  Keys and mouse as in client-internals/level-editor-205.md ("Editor
  keys", "Tile editing model").

  Step takes one frame of input; Draw paints the whole screen. Neither
  touches a window, so the tests drive it headless. }
unit EditorView;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GLevel, EditorUI, EditorDoc;

type
  TPaletteMode = (pmObjects, pmTiles, pmThings);
  TMouseState = (msIdle, msSelect, msDragFloat, msPaint, msDragObject, msPalette,
    msHScroll, msVScroll, msPalHScroll, msPalVScroll);
  TEditorExit = (eeNone, eeLeave, eePlay);
  TDialogKind = (dkNone, dkInfo, dkOpen, dkSaveAs, dkSaveAsClose, dkCloseAsk, dkPlayName);
  { An image from the install (NPC images), or nil. }
  TImageFunc = function(const Name: string): TGSurface of object;

  TToolAction = (taNew, taOpen, taSave, taSaveAs, taUndo, taCut, taCopy, taPaste,
    taDelete, taWarp, taLinks, taSigns, taFlags, taClose, taPlay);

  { Things on the "Baddies,Npcs,Chests" palette: the ten baddy types, then
    an NPC and a chest. }
const
  ThingNPC = 10;
  ThingChest = 11;
  ThingCount = 12;

  BoardX = 0;
  BoardY = 61;
  BoardViewW = 400;
  BoardViewH = 400;
  PalX0 = 430;
  PalY0 = 113;
  PalW = 176;
  PalH = 304;

type
  TEditorView = class
  private
    FBoard: TGSurface;
    FAnchorX, FAnchorY: Integer;
    FOffX, FOffY: Integer;
    FDragKind: TEditorObjKind;
    FDragIndex: Integer;
    FLastPaintX, FLastPaintY: Integer;
    FLastClickMs: Int64;
    FLastClickX, FLastClickY: Integer;
    FStatusMs: Int64;
    FNow: Int64;
    FDialogKind: TDialogKind;
    procedure ToolAt(X, Y: Integer);
    procedure BoardPress(const I: TEditorInput; TX, TY: Integer);
    procedure BoardRightPress(const I: TEditorInput; TX, TY: Integer);
    procedure PalettePress(const I: TEditorInput);
    procedure HandleKeys(const I: TEditorInput);
    procedure DragStep(const I: TEditorInput);
    procedure Release;
    procedure DialogClosed;
    procedure ShowDialog(D: TEditorDialog; Kind: TDialogKind);
    procedure DrawToolbar(S: TGSurface);
    procedure DrawTabs(S: TGSurface);
    procedure DrawBoard(S: TGSurface);
    procedure DrawPanel(S: TGSurface);
    function DoubleClick(const I: TEditorInput): Boolean;
    function TileAtMouse(X, Y: Integer; out TX, TY: Integer): Boolean;
    procedure ClampScroll;
    function PaletteTile(PX, PY: Integer): Integer;
  public
    Editor: TEditor;
    Sheet: TGSurface;
    Images: TImageFunc;
    Mode: TPaletteMode;
    PalScrollX, PalScrollY: Integer;
    Pen: TTileBlock;
    { the floating block follows the mouse (a palette pick or a paste) }
    FollowMouse: Boolean;
    { Pen came from one palette tile: dragging paints it }
    PenPaints: Boolean;
    Thing: Integer;   { the picked palette thing, -1 = none }
    Placing: Boolean; { a picked thing follows the mouse until a click }
    MouseState: TMouseState;
    MouseTX, MouseTY: Integer;
    Status: string;
    Dialog: TEditorDialog;
    ExitCode: TEditorExit;
    PlayFile: string;
    constructor Create(ASheet: TGSurface);
    destructor Destroy; override;
    procedure Step(const I: TEditorInput);
    procedure Draw(S: TGSurface);
    procedure Action(A: TToolAction);
    procedure SetStatus(const S: string);
    { Opens a level file in a tab; False with the reason in Status. }
    function OpenFile(const FileName: string): Boolean;
    { What the status bar shows for the tile under the mouse. }
    function HoverText: string;
  end;

const
  ToolCaptions: array[TToolAction] of string = ('New', 'Open', 'Save', 'SvAs',
    'Undo', 'Cut', 'Copy', 'Pste', 'Del', 'Warp', 'Lnks', 'Sgns', 'Flgs', 'Clse', 'Play');
  ToolHints: array[TToolAction] of string = ('New', 'Open', 'Save', 'Save as',
    'Undo board copy', 'Cut', 'Copy', 'Paste', 'Delete',
    'Turn selection into a warp field', 'Edit links', 'Edit signs', 'Edit flags',
    'Close', 'Play the current level');

function ToolRect(A: TToolAction): TRectI;
function SheetTileAt(PX, PY: Integer): Integer;

implementation

uses
  SysUtils, GFont, GLevelWrite;

const
  TileSz = 16;
  StatusShowMs = 4000;
  DoubleClickMs = 400;
  ThingNames: array[0..ThingCount - 1] of string = ('Gray Soldier', 'Blue Soldier',
    'Red Soldier', 'Shooting Soldier', 'Swamp Soldier', 'Frog', 'Spider',
    'Golden Warrior', 'Lizardon', 'Dragon', 'Npc', 'Chest');

function ToolRect(A: TToolAction): TRectI;
var
  X: Integer;
begin
  if A = taPlay then
  begin
    Result := RectI(523, 2, 88, 28);
    Exit;
  end;
  X := 2 + Ord(A) * 31;
  { gaps after Save as, Delete and Edit flags, as the toolbar groups them }
  if A > taSaveAs then Inc(X, 6);
  if A > taDelete then Inc(X, 6);
  if A > taFlags then Inc(X, 6);
  Result := RectI(X, 4, 30, 25);
end;

{ The sheet is eight blocks of 512 ids, each 16 columns by 32 rows
  (GSurface.TileSheetPos); this is its inverse. }
function SheetTileAt(PX, PY: Integer): Integer;
var
  Col, Row: Integer;
begin
  Col := PX div TileSz;
  Row := PY div TileSz;
  if (Col < 0) or (Row < 0) or (Col >= 128) or (Row >= 32) then
  begin
    Result := -1;
    Exit;
  end;
  Result := (Col div 16) * 512 + Row * 16 + (Col mod 16);
end;

function MinI(A, B: Integer): Integer;
begin
  if A < B then Result := A else Result := B;
end;

function MaxI(A, B: Integer): Integer;
begin
  if A > B then Result := A else Result := B;
end;

{ TEditorView }

constructor TEditorView.Create(ASheet: TGSurface);
begin
  inherited Create;
  Sheet := ASheet;
  Editor := TEditor.Create;
  FBoard := TGSurface.Create(BoardViewW, BoardViewH);
  Mode := pmTiles;
  Thing := -1;
  FDragIndex := -1;
end;

destructor TEditorView.Destroy;
begin
  Dialog.Free;
  FBoard.Free;
  Editor.Free;
  inherited Destroy;
end;

procedure TEditorView.SetStatus(const S: string);
begin
  Status := S;
  FStatusMs := FNow;
end;

function TEditorView.OpenFile(const FileName: string): Boolean;
begin
  Result := Editor.OpenDoc(FileName) <> nil;
  if Result then
    SetStatus(Editor.Doc.Title + ' loaded')
  else
    SetStatus(Editor.LastError);
end;

procedure TEditorView.ShowDialog(D: TEditorDialog; Kind: TDialogKind);
begin
  Dialog.Free;
  Dialog := D;
  FDialogKind := Kind;
  MouseState := msIdle;
end;

function TEditorView.TileAtMouse(X, Y: Integer; out TX, TY: Integer): Boolean;
var
  D: TEditorDoc;
begin
  D := Editor.Doc;
  Result := (D <> nil) and InRect(RectI(BoardX, BoardY, BoardViewW, BoardViewH), X, Y);
  if D = nil then
  begin
    TX := 0;
    TY := 0;
    Exit;
  end;
  TX := (X - BoardX + D.ScrollX) div TileSz;
  TY := (Y - BoardY + D.ScrollY) div TileSz;
  if X - BoardX + D.ScrollX < 0 then TX := -1;
  if Y - BoardY + D.ScrollY < 0 then TY := -1;
end;

procedure TEditorView.ClampScroll;
var
  D: TEditorDoc;
begin
  D := Editor.Doc;
  if D <> nil then
  begin
    D.ScrollX := MaxI(0, MinI(D.ScrollX, BoardW * TileSz - BoardViewW));
    D.ScrollY := MaxI(0, MinI(D.ScrollY, BoardH * TileSz - BoardViewH));
  end;
  PalScrollX := MaxI(0, MinI(PalScrollX, 128 * TileSz - PalW));
  PalScrollY := MaxI(0, MinI(PalScrollY, 32 * TileSz - PalH));
end;

function TEditorView.PaletteTile(PX, PY: Integer): Integer;
begin
  Result := SheetTileAt(PX - PalX0 + PalScrollX, PY - PalY0 + PalScrollY);
end;

function TEditorView.DoubleClick(const I: TEditorInput): Boolean;
begin
  Result := (I.NowMs - FLastClickMs <= DoubleClickMs) and
    (Abs(I.PressX - FLastClickX) <= 3) and (Abs(I.PressY - FLastClickY) <= 3);
  if Result then FLastClickMs := -DoubleClickMs * 2
  else FLastClickMs := I.NowMs;
  FLastClickX := I.PressX;
  FLastClickY := I.PressY;
end;

function TEditorView.HoverText: string;
var
  D: TEditorDoc;
  K: TEditorObjKind;
  N: Integer;
begin
  Result := '';
  D := Editor.Doc;
  if (D = nil) or (MouseTX < 0) or (MouseTY < 0) or (MouseTX >= BoardW) or (MouseTY >= BoardH) then
    Exit;
  Result := Format('%d,%d  %d', [MouseTX, MouseTY, D.Level.Tile(MouseTX, MouseTY)]);
  if D.ObjectAt(MouseTX, MouseTY, K, N) then
    case K of
      okChest: Result := Result + '  chest';
      okNPC: Result := Result + '  npc';
      okBaddy: Result := Result + '  baddy';
    end
  else
    Result := Result + '  tile';
end;

{ ---- actions ---- }

procedure TEditorView.Action(A: TToolAction);
var
  D: TEditorDoc;
  N: Integer;
begin
  D := Editor.Doc;
  case A of
    taNew:
      begin
        Editor.NewDoc;
        SetStatus('New level');
      end;
    taOpen:
      ShowDialog(TPromptDialog.Create('Load level', 'File name:', ''), dkOpen);
    taSave:
      if D <> nil then
      begin
        if D.NeedsName then
          ShowDialog(TPromptDialog.Create('Save Graal level', 'File name (.graal or .nw):',
            ''), dkSaveAs)
        else if D.Save then
          SetStatus('Level saved')
        else
          SetStatus(D.LastError);
      end;
    taSaveAs:
      if D <> nil then
        ShowDialog(TPromptDialog.Create('Save Graal level', 'File name (.graal or .nw):',
          D.FileName), dkSaveAs);
    taUndo:
      if (D <> nil) and not D.Undo then SetStatus('Nothing to undo');
    taCut:
      begin
        Editor.Cut;
        FollowMouse := False;
      end;
    taCopy:
      begin
        Editor.Copy;
        FollowMouse := False;
      end;
    taPaste:
      if (D <> nil) and (Editor.Clipboard.W > 0) then
      begin
        Editor.Paste(MaxI(0, MouseTX), MaxI(0, MouseTY));
        FollowMouse := True;
        PenPaints := False;
      end;
    taDelete:
      begin
        Editor.Delete;
        FollowMouse := False;
      end;
    taWarp:
      if D <> nil then
      begin
        N := D.MakeWarpLink;
        if N < 0 then SetStatus('Select the warp field first')
        else SetStatus('Warp field added: edit its destination in the link list');
      end;
    taLinks, taSigns, taFlags:
      SetStatus(ToolHints[A] + ': not in this build yet');
    taClose:
      if D <> nil then
      begin
        if D.Modified then
          ShowDialog(TMessageDialog.Create('Graal', 'Save changes to ' + D.Title + '?', 3),
            dkCloseAsk)
        else
          Editor.CloseDoc(Editor.Current);
      end;
    taPlay:
      if D <> nil then
      begin
        if D.Floating then D.DropFloat;
        if D.NeedsName then
          ShowDialog(TMessageDialog.Create('Graal',
            'Please save the level under a new name before playing!', 1), dkInfo)
        else
        begin
          if D.Modified then
          begin
            if D.Save then SetStatus('Level saved')
            else
            begin
              SetStatus(D.LastError);
              Exit;
            end;
          end;
          PlayFile := D.FileName;
          ExitCode := eePlay;
        end;
      end;
  end;
end;

procedure TEditorView.DialogClosed;
var
  Dlg: TEditorDialog;
  Kind: TDialogKind;
  D: TEditorDoc;
  V: string;
begin
  Dlg := Dialog;
  Kind := FDialogKind;
  Dialog := nil;
  FDialogKind := dkNone;
  try
    D := Editor.Doc;
    V := '';
    if Dlg is TPromptDialog then V := Trim(TPromptDialog(Dlg).Value);
    case Kind of
      dkOpen:
        if (Dlg.Result = drOk) and (V <> '') then OpenFile(V);
      dkSaveAs, dkSaveAsClose:
        if (Dlg.Result = drOk) and (V <> '') and (D <> nil) then
        begin
          if D.SaveAs(V) then
          begin
            SetStatus('Level saved');
            if Kind = dkSaveAsClose then Editor.CloseDoc(Editor.Current);
          end
          else
            SetStatus(D.LastError);
        end;
      dkCloseAsk:
        if D <> nil then
          case Dlg.Result of
            drYes:
              if D.NeedsName then
                ShowDialog(TPromptDialog.Create('Save Graal level',
                  'File name (.graal or .nw):', ''), dkSaveAsClose)
              else if D.Save then
                Editor.CloseDoc(Editor.Current)
              else
                SetStatus(D.LastError);
            drNo:
              Editor.CloseDoc(Editor.Current);
          end;
    end;
  finally
    Dlg.Free;
  end;
end;

{ ---- input ---- }

procedure TEditorView.ToolAt(X, Y: Integer);
var
  A: TToolAction;
begin
  for A := Low(TToolAction) to High(TToolAction) do
    if InRect(ToolRect(A), X, Y) then
    begin
      Action(A);
      Exit;
    end;
end;

procedure TEditorView.PalettePress(const I: TEditorInput);
var
  T, Row: Integer;
begin
  if Mode = pmTiles then
  begin
    T := PaletteTile(I.PressX, I.PressY);
    if T < 0 then Exit;
    if DoubleClick(I) then
    begin
      Editor.Background := T;
      SetStatus(Format('Background tile %d', [T]));
      MouseState := msIdle;
      Exit;
    end;
    FAnchorX := I.PressX - PalX0 + PalScrollX;
    FAnchorY := I.PressY - PalY0 + PalScrollY;
    MouseState := msPalette;
  end
  else if Mode = pmThings then
  begin
    Row := (I.PressY - PalY0 - 2) div LineH;
    if (Row >= 0) and (Row < ThingCount) then
    begin
      Thing := Row;
      Placing := True;
      if Editor.Doc <> nil then Editor.Doc.CancelFloat;
      FollowMouse := False;
      SetStatus('Click on the board to place: ' + ThingNames[Row]);
    end;
  end;
end;

procedure TEditorView.BoardPress(const I: TEditorInput; TX, TY: Integer);
var
  D: TEditorDoc;
  K: TEditorObjKind;
  N, OX, OY, OW, OH: Integer;
  Dbl: Boolean;
begin
  D := Editor.Doc;
  if D = nil then Exit;
  Dbl := DoubleClick(I);
  if Placing and (Thing >= 0) then
  begin
    if Thing < ThingNPC then D.AddBaddy(TX, TY, Thing)
    else if Thing = ThingNPC then D.AddNPC(TX, TY, '')
    else D.AddChest(TX, TY);
    Placing := False;
    SetStatus(ThingNames[Thing] + ' placed');
    Exit;
  end;
  if D.Floating then
  begin
    if FollowMouse then
    begin
      D.MoveFloat(TX, TY);
      if PenPaints then
      begin
        { a single palette tile: draw with it while the button is held }
        D.WriteBlock(TX, TY, D.Float);
        FLastPaintX := TX;
        FLastPaintY := TY;
        MouseState := msPaint;
        Exit;
      end;
      D.DropFloat;
      FollowMouse := False;
      Exit;
    end;
    if D.FloatContains(TX, TY) then
    begin
      FOffX := TX - D.FloatX;
      FOffY := TY - D.FloatY;
      MouseState := msDragFloat;
      Exit;
    end;
    D.DropFloat;
  end;
  if D.ObjectAt(TX, TY, K, N) then
  begin
    if Dbl then
    begin
      SetStatus('Object dialogs are not in this build yet');
      Exit;
    end;
    D.ObjectRect(K, N, OX, OY, OW, OH);
    FDragKind := K;
    FDragIndex := N;
    FOffX := TX - OX;
    FOffY := TY - OY;
    MouseState := msDragObject;
    Exit;
  end;
  if Dbl then
  begin
    Editor.Background := D.Level.Tile(TX, TY);
    SetStatus(Format('Background tile %d', [Editor.Background]));
    Exit;
  end;
  if D.HasSel and (TX >= D.SelX) and (TY >= D.SelY) and (TX < D.SelX + D.SelW) and
    (TY < D.SelY + D.SelH) and not ((D.SelW = 1) and (D.SelH = 1)) then
  begin
    { moving a selection: lift it and drag }
    FOffX := TX - D.SelX;
    FOffY := TY - D.SelY;
    D.LiftSelection(Editor.Background);
    MouseState := msDragFloat;
    Exit;
  end;
  FAnchorX := TX;
  FAnchorY := TY;
  D.Select(TX, TY, TX, TY);
  MouseState := msSelect;
end;

procedure TEditorView.BoardRightPress(const I: TEditorInput; TX, TY: Integer);
var
  D: TEditorDoc;
  K: TEditorObjKind;
  N: Integer;
  B: TTileBlock;
begin
  D := Editor.Doc;
  if D = nil then Exit;
  if Placing then
  begin
    Placing := False;
    Exit;
  end;
  if D.ObjectAt(TX, TY, K, N) then
  begin
    { Right Mousebutton -> copy: the copy hangs on the mouse }
    N := D.CloneObject(K, N, TX, TY);
    FDragKind := K;
    FDragIndex := N;
    FOffX := 0;
    FOffY := 0;
    MouseState := msDragObject;
    SetStatus('Object copied');
    Exit;
  end;
  if D.Floating then B := D.Float
  else if (Mode = pmTiles) and (Pen.W > 0) then B := Pen
  else B := TileBlock(1, 1, Editor.Background);
  D.FloodFill(TX, TY, B);
end;

procedure TEditorView.DragStep(const I: TEditorInput);
var
  D: TEditorDoc;
  TX, TY: Integer;
begin
  D := Editor.Doc;
  case MouseState of
    msHScroll:
      if D <> nil then
        D.ScrollX := ScrollPosAt(RectI(BoardX, BoardY + BoardViewH, BoardViewW, 19), False,
          I.MouseX, I.MouseY, BoardW * TileSz - BoardViewW, BoardViewW);
    msVScroll:
      if D <> nil then
        D.ScrollY := ScrollPosAt(RectI(BoardX + BoardViewW, BoardY, 18, BoardViewH), True,
          I.MouseX, I.MouseY, BoardH * TileSz - BoardViewH, BoardViewH);
    msPalHScroll:
      PalScrollX := ScrollPosAt(RectI(PalX0, PalY0 + PalH, PalW, 18), False, I.MouseX,
        I.MouseY, 128 * TileSz - PalW, PalW);
    msPalVScroll:
      PalScrollY := ScrollPosAt(RectI(PalX0 + PalW, PalY0, 18, PalH), True, I.MouseX,
        I.MouseY, 32 * TileSz - PalH, PalH);
  end;
  if D = nil then Exit;
  TileAtMouse(I.MouseX, I.MouseY, TX, TY);
  case MouseState of
    msSelect:
      D.Select(FAnchorX, FAnchorY, TX, TY);
    msDragFloat:
      D.MoveFloat(TX - FOffX, TY - FOffY);
    msPaint:
      if ((TX <> FLastPaintX) or (TY <> FLastPaintY)) and (TX >= 0) and (TY >= 0) and
        (TX < BoardW) and (TY < BoardH) then
      begin
        D.MoveFloat(TX, TY);
        D.WriteBlock(TX, TY, D.Float);
        FLastPaintX := TX;
        FLastPaintY := TY;
      end;
    msDragObject:
      if (TX >= 0) and (TY >= 0) and (TX < BoardW) and (TY < BoardH) then
        D.MoveObject(FDragKind, FDragIndex, TX - FOffX, TY - FOffY);
  end;
end;

procedure TEditorView.Release;
var
  D: TEditorDoc;
  X1, Y1, X2, Y2, IX, IY, T: Integer;
begin
  D := Editor.Doc;
  case MouseState of
    msDragFloat:
      if D <> nil then D.DropFloat;
    msPalette:
      begin
        X1 := MinI(FAnchorX, FLastPaintX) div TileSz;
        Y1 := MinI(FAnchorY, FLastPaintY) div TileSz;
        X2 := MaxI(FAnchorX, FLastPaintX) div TileSz;
        Y2 := MaxI(FAnchorY, FLastPaintY) div TileSz;
        X1 := MaxI(0, X1); Y1 := MaxI(0, Y1);
        X2 := MinI(127, X2); Y2 := MinI(31, Y2);
        Pen.W := X2 - X1 + 1;
        Pen.H := Y2 - Y1 + 1;
        SetLength(Pen.Tiles, Pen.W * Pen.H);
        for IY := 0 to Pen.H - 1 do
          for IX := 0 to Pen.W - 1 do
          begin
            T := SheetTileAt((X1 + IX) * TileSz, (Y1 + IY) * TileSz);
            if T < 0 then T := 0;
            Pen.Tiles[IY * Pen.W + IX] := T;
          end;
        PenPaints := (Pen.W = 1) and (Pen.H = 1);
        if D <> nil then
        begin
          D.StartFloat(Pen, MaxI(0, MouseTX), MaxI(0, MouseTY));
          FollowMouse := True;
        end;
        Placing := False;
        if PenPaints then SetStatus(Format('Tile %d', [Pen.Tiles[0]]))
        else SetStatus(Format('%dx%d tiles', [Pen.W, Pen.H]));
      end;
  end;
  MouseState := msIdle;
end;

procedure TEditorView.HandleKeys(const I: TEditorInput);
var
  K: Integer;
  C: Char;
  D: TEditorDoc;
begin
  D := Editor.Doc;
  for K := 1 to Length(I.Chars) do
  begin
    if Dialog <> nil then Exit;
    C := I.Chars[K];
    case C of
      #14: Action(taNew);        { Ctrl+N }
      #15: Action(taOpen);       { Ctrl+O }
      #19: Action(taSave);       { Ctrl+S }
      #26: Action(taUndo);       { Ctrl+Z }
      #24: Action(taCut);        { Ctrl+X }
      #3: Action(taCopy);        { Ctrl+C }
      #22: Action(taPaste);      { Ctrl+V }
      'l', 'L': if not I.Ctrl then Action(taLinks);
      's', 'S': if not I.Ctrl then Action(taSigns);
      'p', 'P': if not I.Ctrl then Action(taPlay);
      'm', 'M': if not I.Ctrl then SetStatus('Generate map: not in this build yet');
      #27:
        if (D <> nil) and D.Floating then
        begin
          D.CancelFloat;
          FollowMouse := False;
        end
        else if Placing then
          Placing := False
        else
          ExitCode := eeLeave;
    end;
  end;
  if Dialog <> nil then Exit;
  if I.Del then
  begin
    if I.Shift then Action(taCut) else Action(taDelete);
  end;
  if I.Ins then
  begin
    if I.Ctrl then Action(taCopy)
    else if I.Shift then Action(taPaste);
  end;
  if I.F5 then Action(taOpen);
  if D <> nil then
  begin
    if I.Up then Dec(D.ScrollY, TileSz);
    if I.Down then Inc(D.ScrollY, TileSz);
    if I.LeftKey then Dec(D.ScrollX, TileSz);
    if I.RightKey then Inc(D.ScrollX, TileSz);
    if I.Wheel <> 0 then
    begin
      if InRect(RectI(PalX0, PalY0, PalW, PalH), I.MouseX, I.MouseY) then
        Inc(PalScrollY, I.Wheel * 3 * TileSz)
      else
        Inc(D.ScrollY, I.Wheel * 3 * TileSz);
    end;
  end;
end;

procedure TEditorView.Step(const I: TEditorInput);
var
  TX, TY, T: Integer;
  D: TEditorDoc;
begin
  FNow := I.NowMs;
  if Editor.DocCount = 0 then Editor.NewDoc;
  if (Status <> '') and (FNow - FStatusMs > StatusShowMs) then Status := '';
  if Dialog <> nil then
  begin
    if not Dialog.Step(I) then DialogClosed;
    Exit;
  end;
  D := Editor.Doc;
  TileAtMouse(I.MouseX, I.MouseY, TX, TY);
  MouseTX := TX;
  MouseTY := TY;
  if (D <> nil) and D.Floating and FollowMouse and (MouseState = msIdle) and
    InRect(RectI(BoardX, BoardY, BoardViewW, BoardViewH), I.MouseX, I.MouseY) then
    D.MoveFloat(TX, TY);

  HandleKeys(I);
  if (Dialog <> nil) or (ExitCode <> eeNone) then Exit;
  D := Editor.Doc;
  if D = nil then Exit;

  if I.LeftPress then
  begin
    if I.PressY < 33 then
      ToolAt(I.PressX, I.PressY)
    else if (I.PressY < BoardY) and (I.PressX < 418) then
    begin
      { tabs }
      for T := 0 to Editor.DocCount - 1 do
        if (I.PressX >= 2 + T * 100) and (I.PressX < 2 + T * 100 + 98) then
        begin
          Editor.Current := T;
          MouseState := msIdle;
        end;
    end
    else if InRect(RectI(BoardX, BoardY, BoardViewW, BoardViewH), I.PressX, I.PressY) then
    begin
      TileAtMouse(I.PressX, I.PressY, TX, TY);
      BoardPress(I, TX, TY);
    end
    else if InRect(RectI(BoardX, BoardY + BoardViewH, BoardViewW, 19), I.PressX, I.PressY) then
      MouseState := msHScroll
    else if InRect(RectI(BoardX + BoardViewW, BoardY, 18, BoardViewH), I.PressX, I.PressY) then
      MouseState := msVScroll
    else if InRect(RectI(434, 41, 190, 14), I.PressX, I.PressY) then
      Mode := pmObjects
    else if InRect(RectI(434, 65, 190, 14), I.PressX, I.PressY) then
      Mode := pmTiles
    else if InRect(RectI(434, 89, 190, 14), I.PressX, I.PressY) then
      Mode := pmThings
    else if InRect(RectI(PalX0, PalY0, PalW, PalH), I.PressX, I.PressY) then
      PalettePress(I)
    else if (Mode = pmTiles) and InRect(RectI(PalX0, PalY0 + PalH, PalW, 18), I.PressX, I.PressY) then
      MouseState := msPalHScroll
    else if (Mode = pmTiles) and InRect(RectI(PalX0 + PalW, PalY0, 18, PalH), I.PressX, I.PressY) then
      MouseState := msPalVScroll;
    if ExitCode <> eeNone then Exit;
  end;
  if I.RightPress and (MouseState = msIdle) and
    InRect(RectI(BoardX, BoardY, BoardViewW, BoardViewH), I.RightX, I.RightY) then
  begin
    TileAtMouse(I.RightX, I.RightY, TX, TY);
    BoardRightPress(I, TX, TY);
  end;

  if MouseState = msPalette then
  begin
    FLastPaintX := MaxI(0, MinI(I.MouseX - PalX0, PalW - 1)) + PalScrollX;
    FLastPaintY := MaxI(0, MinI(I.MouseY - PalY0, PalH - 1)) + PalScrollY;
  end;
  if MouseState <> msIdle then
  begin
    DragStep(I);
    if not I.Left and not I.Right then Release;
  end;
  ClampScroll;
end;

{ ---- drawing ---- }

procedure TEditorView.DrawToolbar(S: TGSurface);
var
  A: TToolAction;
  R: TRectI;
begin
  FacePanel(S, RectI(0, 0, 640, 33));
  for A := Low(TToolAction) to High(TToolAction) do
  begin
    R := ToolRect(A);
    ButtonCtl(S, R, ToolCaptions[A], False, True);
  end;
end;

procedure TEditorView.DrawTabs(S: TGSurface);
var
  T, X: Integer;
  Cap: string;
begin
  S.FillRect(0, 33, 418, 28, ColFace);
  for T := 0 to Editor.DocCount - 1 do
  begin
    X := 2 + T * 100;
    if X > 418 then Break;
    Cap := Editor.Docs[T].Title;
    if Editor.Docs[T].Modified then Cap := Cap + '*';
    if T = Editor.Current then
    begin
      S.FillRect(X, 35, 98, 26, ColFace);
      Raised(S, RectI(X, 35, 98, 30));
    end
    else
      Raised(S, RectI(X, 38, 98, 27));
    TextClip(S, X + 6, 45, 88, Cap, ColText);
  end;
  S.FillRect(0, 60, 418, 1, ColLight);
end;

procedure TEditorView.DrawBoard(S: TGSurface);
var
  D: TEditorDoc;
  TX, TY, X0, Y0, I, X, Y, W, H: Integer;
  Img: TGSurface;
  Cap: string;

  procedure Box(BX, BY, BW, BH: Integer; Fill: Cardinal; const Lbl: string);
  begin
    FBoard.FillRect(BX, BY, BW, BH, Fill);
    FrameRect(FBoard, BX, BY, BW, BH, $FF000000);
    TextClip(FBoard, BX + 2, BY + 2, BW - 3, Lbl, $FFFFFFFF);
  end;

begin
  D := Editor.Doc;
  FBoard.Fill($FF000000);
  if D <> nil then
  begin
    X0 := D.ScrollX div TileSz;
    Y0 := D.ScrollY div TileSz;
    for TY := Y0 to Y0 + BoardViewH div TileSz + 1 do
      for TX := X0 to X0 + BoardViewW div TileSz + 1 do
        if (TX < BoardW) and (TY < BoardH) then
          DrawTile(FBoard, Sheet, D.Level.Tile(TX, TY), TX * TileSz - D.ScrollX,
            TY * TileSz - D.ScrollY);
    { links: their warp fields }
    for I := 0 to High(D.Level.Links) do
      with D.Level.Links[I] do
      begin
        FrameRect(FBoard, X * TileSz - D.ScrollX, Y * TileSz - D.ScrollY, W * TileSz,
          H * TileSz, $FFFFFF00);
        TextClip(FBoard, X * TileSz - D.ScrollX + 2, Y * TileSz - D.ScrollY + 2,
          MaxI(W * TileSz - 3, 30), Dest, $FFFFFF00);
      end;
    { signs (one at 0,0 is only used by index and not drawn) }
    for I := 0 to High(D.Level.Signs) do
      with D.Level.Signs[I] do
        if (X <> 0) or (Y <> 0) then
          FrameRect(FBoard, X * TileSz - D.ScrollX, Y * TileSz - D.ScrollY, 2 * TileSz,
            TileSz, $FF00FFFF);
    for I := 0 to High(D.Level.Chests) do
      with D.Level.Chests[I] do
        Box(X * TileSz - D.ScrollX, Y * TileSz - D.ScrollY, 32, 32, $FF805020, 'chest');
    for I := 0 to High(D.Level.NPCs) do
    begin
      D.ObjectRect(okNPC, I, X, Y, W, H);
      Img := nil;
      if Assigned(Images) and (D.Level.NPCs[I].Image <> '') then
        Img := Images(D.Level.NPCs[I].Image);
      X := Round(D.Level.NPCs[I].X * TileSz) - D.ScrollX;
      Y := Round(D.Level.NPCs[I].Y * TileSz) - D.ScrollY;
      if Img <> nil then
        FBoard.Blit(Img, 0, 0, Img.Width, Img.Height, X, Y)
      else
      begin
        Cap := D.Level.NPCs[I].Image;
        if Cap = '' then Cap := 'npc';
        Box(X, Y, W * TileSz, H * TileSz, $FF406080, Cap);
      end;
    end;
    for I := 0 to High(D.Level.Baddies) do
      with D.Level.Baddies[I] do
      begin
        if (Kind >= 0) and (Kind <= 9) then Cap := BaddyTypeNames[Kind] else Cap := '?';
        Box(X * TileSz - D.ScrollX, Y * TileSz - D.ScrollY, 32, 32, $FFA02020, Cap);
      end;
    if D.HasSel and not D.Floating then
      DashRect(FBoard, D.SelX * TileSz - D.ScrollX, D.SelY * TileSz - D.ScrollY,
        D.SelW * TileSz, D.SelH * TileSz, $FFFFFFFF, $FF000000);
    if D.Floating then
    begin
      for TY := 0 to D.Float.H - 1 do
        for TX := 0 to D.Float.W - 1 do
          DrawTile(FBoard, Sheet, D.Float.Tiles[TY * D.Float.W + TX],
            (D.FloatX + TX) * TileSz - D.ScrollX, (D.FloatY + TY) * TileSz - D.ScrollY);
      DashRect(FBoard, D.FloatX * TileSz - D.ScrollX, D.FloatY * TileSz - D.ScrollY,
        D.Float.W * TileSz, D.Float.H * TileSz, $FFFFFF00, $FF000000);
    end;
    if Placing and (Thing >= 0) and (MouseTX >= 0) and (MouseTY >= 0) then
      DashRect(FBoard, MouseTX * TileSz - D.ScrollX, MouseTY * TileSz - D.ScrollY,
        32, 32, $FFFF8080, $FF000000);
  end;
  S.Blit(FBoard, 0, 0, BoardViewW, BoardViewH, BoardX, BoardY);
  if D <> nil then
  begin
    ScrollCtl(S, RectI(BoardX, BoardY + BoardViewH, BoardViewW, 19), False, D.ScrollX,
      BoardW * TileSz - BoardViewW, BoardViewW);
    ScrollCtl(S, RectI(BoardX + BoardViewW, BoardY, 18, BoardViewH), True, D.ScrollY,
      BoardH * TileSz - BoardViewH, BoardViewH);
  end;
  S.FillRect(BoardX + BoardViewW, BoardY + BoardViewH, 18, 19, ColFace);
end;

procedure TEditorView.DrawPanel(S: TGSurface);
var
  I, X1, Y1, X2, Y2: Integer;
  T: string;
begin
  S.FillRect(418, 61, 222, 419, ColFace);
  S.FillRect(418, 33, 222, 28, ColFace);
  RadioCtl(S, 434, 41, 'Select predefined object', Mode = pmObjects);
  RadioCtl(S, 434, 65, 'Select tile', Mode = pmTiles);
  RadioCtl(S, 434, 89, 'Baddies,Npcs,Chests', Mode = pmThings);
  S.FillRect(PalX0, PalY0, PalW, PalH, ColWindow);
  case Mode of
    pmTiles:
      begin
        S.Blit(Sheet, PalScrollX, PalScrollY, PalW, PalH, PalX0, PalY0);
        if MouseState = msPalette then
        begin
          X1 := (MinI(FAnchorX, FLastPaintX) div TileSz) * TileSz - PalScrollX;
          Y1 := (MinI(FAnchorY, FLastPaintY) div TileSz) * TileSz - PalScrollY;
          X2 := (MaxI(FAnchorX, FLastPaintX) div TileSz + 1) * TileSz - PalScrollX;
          Y2 := (MaxI(FAnchorY, FLastPaintY) div TileSz + 1) * TileSz - PalScrollY;
          DashRect(S, PalX0 + X1, PalY0 + Y1, X2 - X1, Y2 - Y1, $FFFFFFFF, $FF000000);
        end;
        ScrollCtl(S, RectI(PalX0, PalY0 + PalH, PalW, 18), False, PalScrollX,
          128 * TileSz - PalW, PalW);
        ScrollCtl(S, RectI(PalX0 + PalW, PalY0, 18, PalH), True, PalScrollY,
          32 * TileSz - PalH, PalH);
      end;
    pmThings:
      for I := 0 to ThingCount - 1 do
      begin
        if I = Thing then
        begin
          S.FillRect(PalX0, PalY0 + 2 + I * LineH, PalW, LineH, ColHighlight);
          DrawLabel(S, PalX0 + 6, PalY0 + 6 + I * LineH, ThingNames[I], ColHighlightText);
        end
        else
          DrawLabel(S, PalX0 + 6, PalY0 + 6 + I * LineH, ThingNames[I], ColText);
      end;
    pmObjects:
      DrawLabel(S, PalX0 + 6, PalY0 + 6, 'No object sets loaded', ColGrayText);
  end;
  Sunken(S, RectI(PalX0 - 1, PalY0 - 1, PalW + 2, PalH + 2));
  { the background tile preview }
  DrawLabel(S, 430, 444, 'Background:', ColText);
  DrawTile(S, Sheet, Editor.Background, 608, 440);
  Sunken(S, RectI(607, 439, 18, 18));
  { status bar }
  if Status <> '' then T := Status else T := HoverText;
  Sunken(S, RectI(422, 460, 214, 18));
  TextClip(S, 426, 465, 206, T, ColText);
end;

procedure TEditorView.Draw(S: TGSurface);
begin
  if Sheet.Width = 0 then Exit;
  S.Fill(ColFace);
  DrawToolbar(S);
  DrawTabs(S);
  DrawBoard(S);
  DrawPanel(S);
  if Dialog <> nil then Dialog.Draw(S);
end;

end.
