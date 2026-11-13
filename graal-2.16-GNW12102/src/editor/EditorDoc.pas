{ EditorDoc: the document side of the 2.05 built-in level editor.

  2.17.1 copy of the 2.05 rev 2 unit: 2.17.1 runs it as 2.05 does until a
  difference is found (see the build's README).

  No drawing here, so it can be tested headless. The screen (EditorView)
  and the dialogs drive these objects.

  Behaviour from graal_analysis client-internals/level-editor-205.md and
  tools/level-editor/222-reference.md (2.22 notes that say "as in 2.05"):
  - one tab per level, each with its own scroll position, selection,
    floating paste, undo stack and object lists; new tabs are "(new)"
  - new levels are filled with the background tile
  - undo covers board tiles only: before every board write the rectangle
    and its old tiles are kept, at most 128 records per tab, oldest dropped
  - Copy / Cut lift the selection into a floating block; Paste floats the
    clipboard; a drop writes it to the board
  - Delete fills the selection with the background tile
  - right button: on a baddy, NPC or chest it clones the object; elsewhere
    it flood fills with the floating block / picked tile, or with the
    background tile when nothing is picked
  - warp field: a link over the selection, new x/y playerx/playery, then
    the first matching edge rule
  - chests default to item 1 (bluerupee) and sign -1; baddies to
    "Stop!" / "Ouch!"
  - open accepts GR-V1.00..1.03, Z3-V1.03/1.04 and GLEVNW01, otherwise
    "Unsupported file type!"; save picks the writer by extension }
unit EditorDoc;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GLevel;

const
  MaxUndo = 128;
  NewLevelTitle = '(new)';
  BaddyTypeNames: array[0..9] of string = ('Gray Soldier', 'Blue Soldier',
    'Red Soldier', 'Shooting Soldier', 'Swamp Soldier', 'Frog', 'Spider',
    'Golden Warrior', 'Lizardon', 'Dragon');
  DefaultBaddyVerses = 'Stop!\Ouch!\';
  DefaultChestItem = 1;
  { a stamp cell that leaves the board tile as it is (2047 in objects.dat) }
  TransparentTile = $FFFF;

type
  TTileBlock = record
    W, H: Integer;
    Tiles: array of Word; { row by row, W * H }
  end;

  TUndoRecord = record
    X, Y, W, H: Integer;
    Tiles: array of Word;
  end;

  TEditorObjKind = (okNone, okChest, okNPC, okBaddy, okSign, okLink);

  { Size of an NPC on the board in tiles, from its image. }
  TNPCSizeFunc = function(const Image: string; out W, H: Integer): Boolean of object;

  TEditorDoc = class
  private
    FUndo: array of TUndoRecord;
    FUndoCount: Integer;
    procedure PushUndo(X, Y, W, H: Integer);
  public
    Level: TAdventureLevel;
    FileName: string;
    Modified: Boolean;
    LastError: string;
    ScrollX, ScrollY: Integer; { board pixels }
    HasSel: Boolean;
    SelX, SelY, SelW, SelH: Integer;
    Floating: Boolean;
    FloatX, FloatY: Integer;
    Float: TTileBlock;
    NPCSize: TNPCSizeFunc;
    constructor Create(Background: Word);
    destructor Destroy; override;
    function Title: string;
    function Open(const AFileName: string): Boolean;
    function OpenData(const Data, AName: string): Boolean;
    { Save under FileName. False with no name (the caller asks Save as) or
      for a URL level. }
    function Save: Boolean;
    function SaveAs(const AFileName: string): Boolean;
    function NeedsName: Boolean;

    { board }
    function UndoCount: Integer;
    { Writes a block at (X, Y), clipped to the board, keeping an undo record. }
    procedure WriteBlock(X, Y: Integer; const B: TTileBlock);
    procedure SetTile(X, Y: Integer; T: Word);
    function Undo: Boolean;
    procedure Select(X1, Y1, X2, Y2: Integer);
    procedure SelectNone;
    function BlockAt(X, Y, W, H: Integer): TTileBlock;
    function SelectionBlock: TTileBlock;
    procedure FillSelection(T: Word);
    procedure StartFloat(const B: TTileBlock; X, Y: Integer);
    procedure MoveFloat(X, Y: Integer);
    function FloatContains(X, Y: Integer): Boolean;
    { Writes the floating block and selects where it landed. }
    procedure DropFloat;
    procedure CancelFloat;
    { Lifts the selection off the board (filled with Background) as a
      floating block, for moving it. }
    procedure LiftSelection(Background: Word);
    { Fills the 4-connected area of tiles equal to the one at (X, Y) with
      B, repeated from (X, Y). One undo record. }
    procedure FloodFill(X, Y: Integer; const B: TTileBlock);
    { Turn selection into a warp field: index of the new link, or -1. }
    function MakeWarpLink: Integer;

    { objects }
    function AddChest(X, Y: Integer): Integer;
    function AddNPC(X, Y: Double; const Image: string): Integer;
    function AddBaddy(X, Y, Kind: Integer): Integer;
    function AddSign(X, Y: Integer): Integer;
    function AddLink(const L: TLevelLink): Integer;
    procedure DeleteObject(Kind: TEditorObjKind; Index: Integer);
    procedure MoveObject(Kind: TEditorObjKind; Index: Integer; X, Y: Double);
    function CloneObject(Kind: TEditorObjKind; Index: Integer; X, Y: Double): Integer;
    { The topmost chest, NPC or baddy on tile (X, Y). }
    function ObjectAt(X, Y: Integer; out Kind: TEditorObjKind; out Index: Integer): Boolean;
    function ObjectRect(Kind: TEditorObjKind; Index: Integer; out X, Y, W, H: Integer): Boolean;
  end;

  { The editor: open tabs, the clipboard and the background tile. }
  TEditor = class
  public
    Docs: array of TEditorDoc;
    Current: Integer;
    Clipboard: TTileBlock;
    Background: Word;
    LastError: string;
    { Edit flags: the client's in-memory flag list; never saved }
    Flags: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Doc: TEditorDoc;
    function DocCount: Integer;
    function NewDoc: TEditorDoc;
    { Opens a level in a new tab; an already open file switches to its tab. }
    function OpenDoc(const FileName: string): TEditorDoc;
    procedure CloseDoc(Index: Integer);
    procedure Copy;
    procedure Cut;
    procedure Paste(X, Y: Integer);
    procedure Delete;
  end;

function TileBlock(W, H: Integer; T: Word): TTileBlock;
function LinkWarpDefaults(SX, SY, SW, SH: Integer): TLevelLink;

implementation

uses
  SysUtils, GLevelWrite;

function TileBlock(W, H: Integer; T: Word): TTileBlock;
var
  I: Integer;
begin
  Result.W := W;
  Result.H := H;
  SetLength(Result.Tiles, W * H);
  for I := 0 to W * H - 1 do Result.Tiles[I] := T;
end;

function LinkWarpDefaults(SX, SY, SW, SH: Integer): TLevelLink;
begin
  Result.Dest := '';
  Result.X := SX;
  Result.Y := SY;
  Result.W := SW;
  Result.H := SH;
  Result.NewX := 'playerx';
  Result.NewY := 'playery';
  if SX = 63 then Result.NewX := '0'
  else if SY = 63 then Result.NewY := '0'
  else if (SX = 0) and (SW = 1) then Result.NewX := '61'
  else if (SY = 0) and (SH = 1) then Result.NewY := '61';
end;

function ClampI(V, Lo, Hi: Integer): Integer;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

{ TEditorDoc }

constructor TEditorDoc.Create(Background: Word);
var
  I: Integer;
begin
  inherited Create;
  Level := TAdventureLevel.Create;
  for I := 0 to BoardSize - 1 do Level.Tiles[I] := Background;
  Level.Magic := 'GR-V1.03';
end;

destructor TEditorDoc.Destroy;
begin
  Level.Free;
  inherited Destroy;
end;

function TEditorDoc.Title: string;
begin
  if FileName = '' then Result := NewLevelTitle
  else Result := ExtractFileName(FileName);
end;

function TEditorDoc.OpenData(const Data, AName: string): Boolean;
var
  M: string;
begin
  M := Copy(Data, 1, 8);
  if not ((M = 'GLEVNW01') or (M = 'GR-V1.00') or (M = 'GR-V1.01') or (M = 'GR-V1.02') or
    (M = 'GR-V1.03') or (M = 'Z3-V1.03') or (M = 'Z3-V1.04')) then
  begin
    LastError := 'Unsupported file type!';
    Result := False;
    Exit;
  end;
  Result := Level.LoadFromString(Data);
  if not Result then
  begin
    LastError := Level.LastError;
    Exit;
  end;
  Level.Name := ExtractFileName(AName);
  FileName := AName;
  Modified := False;
  HasSel := False;
  Floating := False;
  FUndoCount := 0;
end;

function TEditorDoc.Open(const AFileName: string): Boolean;
var
  F: file;
  S: string;
  N: Integer;
begin
  Result := False;
  if not FileExists(AFileName) then
  begin
    LastError := 'Cannot open ' + AFileName;
    Exit;
  end;
  AssignFile(F, AFileName);
  FileMode := 0;
  Reset(F, 1);
  try
    N := FileSize(F);
    SetLength(S, N);
    if N > 0 then BlockRead(F, S[1], N);
  finally
    CloseFile(F);
  end;
  Result := OpenData(S, AFileName);
end;

function TEditorDoc.NeedsName: Boolean;
begin
  Result := (FileName = '') or (Pos('://', FileName) > 0);
end;

function TEditorDoc.Save: Boolean;
begin
  Result := False;
  if NeedsName then
  begin
    LastError := 'Please save the level under a new name';
    Exit;
  end;
  if Floating then DropFloat;
  Result := SaveLevelToFile(Level, FileName);
  if Result then Modified := False
  else LastError := Level.LastError;
end;

function TEditorDoc.SaveAs(const AFileName: string): Boolean;
var
  Old: string;
begin
  Old := FileName;
  FileName := AFileName;
  Result := Save;
  if Result then Level.Name := ExtractFileName(AFileName)
  else FileName := Old;
end;

function TEditorDoc.UndoCount: Integer;
begin
  Result := FUndoCount;
end;

procedure TEditorDoc.PushUndo(X, Y, W, H: Integer);
var
  I, J: Integer;
  R: TUndoRecord;
begin
  R.X := X;
  R.Y := Y;
  R.W := W;
  R.H := H;
  SetLength(R.Tiles, W * H);
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
      R.Tiles[J * W + I] := Level.Tiles[(X + I) + (Y + J) * BoardW];
  if FUndoCount = MaxUndo then
  begin
    for I := 1 to MaxUndo - 1 do FUndo[I - 1] := FUndo[I];
    Dec(FUndoCount);
  end;
  if Length(FUndo) <= FUndoCount then SetLength(FUndo, FUndoCount + 16);
  FUndo[FUndoCount] := R;
  Inc(FUndoCount);
end;

procedure TEditorDoc.WriteBlock(X, Y: Integer; const B: TTileBlock);
var
  X1, Y1, X2, Y2, I, J: Integer;
begin
  X1 := ClampI(X, 0, BoardW);
  Y1 := ClampI(Y, 0, BoardH);
  X2 := ClampI(X + B.W, 0, BoardW);
  Y2 := ClampI(Y + B.H, 0, BoardH);
  if (X2 <= X1) or (Y2 <= Y1) then Exit;
  PushUndo(X1, Y1, X2 - X1, Y2 - Y1);
  for J := Y1 to Y2 - 1 do
    for I := X1 to X2 - 1 do
      if B.Tiles[(J - Y) * B.W + (I - X)] <> TransparentTile then
        Level.Tiles[I + J * BoardW] := B.Tiles[(J - Y) * B.W + (I - X)];
  Modified := True;
end;

procedure TEditorDoc.SetTile(X, Y: Integer; T: Word);
begin
  WriteBlock(X, Y, TileBlock(1, 1, T));
end;

function TEditorDoc.Undo: Boolean;
var
  R: TUndoRecord;
  I, J: Integer;
begin
  Result := FUndoCount > 0;
  if not Result then Exit;
  Dec(FUndoCount);
  R := FUndo[FUndoCount];
  FUndo[FUndoCount].Tiles := nil;
  for J := 0 to R.H - 1 do
    for I := 0 to R.W - 1 do
      Level.Tiles[(R.X + I) + (R.Y + J) * BoardW] := R.Tiles[J * R.W + I];
  if (R.W = BoardW) and (R.H = BoardH) then
    SelectNone
  else
  begin
    HasSel := True;
    SelX := R.X; SelY := R.Y; SelW := R.W; SelH := R.H;
  end;
  Modified := True;
end;

procedure TEditorDoc.Select(X1, Y1, X2, Y2: Integer);
var
  T: Integer;
begin
  if X2 < X1 then begin T := X1; X1 := X2; X2 := T; end;
  if Y2 < Y1 then begin T := Y1; Y1 := Y2; Y2 := T; end;
  X1 := ClampI(X1, 0, BoardW - 1);
  Y1 := ClampI(Y1, 0, BoardH - 1);
  X2 := ClampI(X2, 0, BoardW - 1);
  Y2 := ClampI(Y2, 0, BoardH - 1);
  HasSel := True;
  SelX := X1;
  SelY := Y1;
  SelW := X2 - X1 + 1;
  SelH := Y2 - Y1 + 1;
end;

procedure TEditorDoc.SelectNone;
begin
  HasSel := False;
end;

function TEditorDoc.BlockAt(X, Y, W, H: Integer): TTileBlock;
var
  I, J: Integer;
begin
  Result.W := W;
  Result.H := H;
  SetLength(Result.Tiles, W * H);
  for J := 0 to H - 1 do
    for I := 0 to W - 1 do
      Result.Tiles[J * W + I] := Level.Tile(X + I, Y + J);
end;

function TEditorDoc.SelectionBlock: TTileBlock;
begin
  if HasSel then Result := BlockAt(SelX, SelY, SelW, SelH)
  else begin Result.W := 0; Result.H := 0; Result.Tiles := nil; end;
end;

procedure TEditorDoc.FillSelection(T: Word);
begin
  if HasSel then WriteBlock(SelX, SelY, TileBlock(SelW, SelH, T));
end;

procedure TEditorDoc.StartFloat(const B: TTileBlock; X, Y: Integer);
begin
  if (B.W <= 0) or (B.H <= 0) then Exit;
  Float.W := B.W;
  Float.H := B.H;
  Float.Tiles := Copy(B.Tiles, 0, Length(B.Tiles));
  FloatX := X;
  FloatY := Y;
  Floating := True;
  HasSel := False;
end;

procedure TEditorDoc.MoveFloat(X, Y: Integer);
begin
  FloatX := X;
  FloatY := Y;
end;

function TEditorDoc.FloatContains(X, Y: Integer): Boolean;
begin
  Result := Floating and (X >= FloatX) and (Y >= FloatY) and
    (X < FloatX + Float.W) and (Y < FloatY + Float.H);
end;

procedure TEditorDoc.DropFloat;
begin
  if not Floating then Exit;
  WriteBlock(FloatX, FloatY, Float);
  Floating := False;
  Select(FloatX, FloatY, FloatX + Float.W - 1, FloatY + Float.H - 1);
end;

procedure TEditorDoc.CancelFloat;
begin
  Floating := False;
end;

procedure TEditorDoc.LiftSelection(Background: Word);
var
  B: TTileBlock;
  X, Y: Integer;
begin
  if not HasSel then Exit;
  B := SelectionBlock;
  X := SelX;
  Y := SelY;
  FillSelection(Background);
  StartFloat(B, X, Y);
end;

procedure TEditorDoc.FloodFill(X, Y: Integer; const B: TTileBlock);
var
  Old: Word;
  Mark: array of Boolean;
  Stack: array of Integer;
  SP, P, PX, PY, MinX, MinY, MaxX, MaxY, I, J, BX, BY: Integer;

  procedure Push(QX, QY: Integer);
  var
    Q: Integer;
  begin
    if (QX < 0) or (QY < 0) or (QX >= BoardW) or (QY >= BoardH) then Exit;
    Q := QX + QY * BoardW;
    if Mark[Q] or (Level.Tiles[Q] <> Old) then Exit;
    Mark[Q] := True;
    if SP >= Length(Stack) then SetLength(Stack, Length(Stack) * 2 + 64);
    Stack[SP] := Q;
    Inc(SP);
  end;

begin
  if (B.W <= 0) or (B.H <= 0) or (X < 0) or (Y < 0) or (X >= BoardW) or (Y >= BoardH) then Exit;
  Old := Level.Tiles[X + Y * BoardW];
  if (B.W = 1) and (B.H = 1) and (B.Tiles[0] = Old) then Exit;
  SetLength(Mark, BoardSize);
  SP := 0;
  MinX := X; MinY := Y; MaxX := X; MaxY := Y;
  Push(X, Y);
  P := 0;
  while P < SP do
  begin
    PX := Stack[P] mod BoardW;
    PY := Stack[P] div BoardW;
    if PX < MinX then MinX := PX;
    if PX > MaxX then MaxX := PX;
    if PY < MinY then MinY := PY;
    if PY > MaxY then MaxY := PY;
    Push(PX - 1, PY);
    Push(PX + 1, PY);
    Push(PX, PY - 1);
    Push(PX, PY + 1);
    Inc(P);
  end;
  PushUndo(MinX, MinY, MaxX - MinX + 1, MaxY - MinY + 1);
  for J := MinY to MaxY do
    for I := MinX to MaxX do
      if Mark[I + J * BoardW] then
      begin
        BX := (I - X) mod B.W;
        if BX < 0 then Inc(BX, B.W);
        BY := (J - Y) mod B.H;
        if BY < 0 then Inc(BY, B.H);
        if B.Tiles[BY * B.W + BX] <> TransparentTile then
          Level.Tiles[I + J * BoardW] := B.Tiles[BY * B.W + BX];
      end;
  Modified := True;
end;

function TEditorDoc.MakeWarpLink: Integer;
begin
  Result := -1;
  if not HasSel then Exit;
  Result := AddLink(LinkWarpDefaults(SelX, SelY, SelW, SelH));
end;

function TEditorDoc.AddLink(const L: TLevelLink): Integer;
begin
  SetLength(Level.Links, Length(Level.Links) + 1);
  Result := High(Level.Links);
  Level.Links[Result] := L;
  Modified := True;
end;

function TEditorDoc.AddChest(X, Y: Integer): Integer;
begin
  SetLength(Level.Chests, Length(Level.Chests) + 1);
  Result := High(Level.Chests);
  FillChar(Level.Chests[Result], SizeOf(TLevelChest), 0);
  Level.Chests[Result].X := X;
  Level.Chests[Result].Y := Y;
  Level.Chests[Result].Item := DefaultChestItem;
  Level.Chests[Result].Sign := -1;
  Modified := True;
end;

function TEditorDoc.AddNPC(X, Y: Double; const Image: string): Integer;
begin
  SetLength(Level.NPCs, Length(Level.NPCs) + 1);
  Result := High(Level.NPCs);
  Level.NPCs[Result].X := X;
  Level.NPCs[Result].Y := Y;
  Level.NPCs[Result].Image := Image;
  Level.NPCs[Result].Script := '';
  Modified := True;
end;

function TEditorDoc.AddBaddy(X, Y, Kind: Integer): Integer;
begin
  SetLength(Level.Baddies, Length(Level.Baddies) + 1);
  Result := High(Level.Baddies);
  Level.Baddies[Result].X := X;
  Level.Baddies[Result].Y := Y;
  Level.Baddies[Result].Kind := Kind;
  if BaddyTalks(Kind) then
    Level.Baddies[Result].Verses := DefaultBaddyVerses
  else
    Level.Baddies[Result].Verses := '\\';
  Modified := True;
end;

function TEditorDoc.AddSign(X, Y: Integer): Integer;
begin
  SetLength(Level.Signs, Length(Level.Signs) + 1);
  Result := High(Level.Signs);
  Level.Signs[Result].X := X;
  Level.Signs[Result].Y := Y;
  Level.Signs[Result].Text := '';
  Modified := True;
end;

procedure TEditorDoc.DeleteObject(Kind: TEditorObjKind; Index: Integer);
var
  I: Integer;
begin
  case Kind of
    okChest:
      if (Index >= 0) and (Index <= High(Level.Chests)) then
      begin
        for I := Index to High(Level.Chests) - 1 do Level.Chests[I] := Level.Chests[I + 1];
        SetLength(Level.Chests, Length(Level.Chests) - 1);
      end else Exit;
    okNPC:
      if (Index >= 0) and (Index <= High(Level.NPCs)) then
      begin
        for I := Index to High(Level.NPCs) - 1 do Level.NPCs[I] := Level.NPCs[I + 1];
        SetLength(Level.NPCs, Length(Level.NPCs) - 1);
      end else Exit;
    okBaddy:
      if (Index >= 0) and (Index <= High(Level.Baddies)) then
      begin
        for I := Index to High(Level.Baddies) - 1 do Level.Baddies[I] := Level.Baddies[I + 1];
        SetLength(Level.Baddies, Length(Level.Baddies) - 1);
      end else Exit;
    okSign:
      if (Index >= 0) and (Index <= High(Level.Signs)) then
      begin
        for I := Index to High(Level.Signs) - 1 do Level.Signs[I] := Level.Signs[I + 1];
        SetLength(Level.Signs, Length(Level.Signs) - 1);
      end else Exit;
    okLink:
      if (Index >= 0) and (Index <= High(Level.Links)) then
      begin
        for I := Index to High(Level.Links) - 1 do Level.Links[I] := Level.Links[I + 1];
        SetLength(Level.Links, Length(Level.Links) - 1);
      end else Exit;
  else
    Exit;
  end;
  Modified := True;
end;

procedure TEditorDoc.MoveObject(Kind: TEditorObjKind; Index: Integer; X, Y: Double);
var
  OX, OY, OW, OH: Integer;
begin
  { a click without a move changes nothing }
  if ObjectRect(Kind, Index, OX, OY, OW, OH) and (Kind <> okNPC) and (OX = Round(X)) and
    (OY = Round(Y)) then Exit;
  if (Kind = okNPC) and (Index >= 0) and (Index <= High(Level.NPCs)) and
    (Level.NPCs[Index].X = X) and (Level.NPCs[Index].Y = Y) then Exit;
  case Kind of
    okChest:
      if (Index >= 0) and (Index <= High(Level.Chests)) then
      begin
        Level.Chests[Index].X := Round(X);
        Level.Chests[Index].Y := Round(Y);
      end;
    okNPC:
      if (Index >= 0) and (Index <= High(Level.NPCs)) then
      begin
        Level.NPCs[Index].X := X;
        Level.NPCs[Index].Y := Y;
      end;
    okBaddy:
      if (Index >= 0) and (Index <= High(Level.Baddies)) then
      begin
        Level.Baddies[Index].X := Round(X);
        Level.Baddies[Index].Y := Round(Y);
      end;
    okSign:
      if (Index >= 0) and (Index <= High(Level.Signs)) then
      begin
        Level.Signs[Index].X := Round(X);
        Level.Signs[Index].Y := Round(Y);
      end;
  else
    Exit;
  end;
  Modified := True;
end;

function TEditorDoc.CloneObject(Kind: TEditorObjKind; Index: Integer; X, Y: Double): Integer;
begin
  Result := -1;
  case Kind of
    okChest:
      if (Index >= 0) and (Index <= High(Level.Chests)) then
      begin
        SetLength(Level.Chests, Length(Level.Chests) + 1);
        Result := High(Level.Chests);
        Level.Chests[Result] := Level.Chests[Index];
      end;
    okNPC:
      if (Index >= 0) and (Index <= High(Level.NPCs)) then
      begin
        SetLength(Level.NPCs, Length(Level.NPCs) + 1);
        Result := High(Level.NPCs);
        Level.NPCs[Result] := Level.NPCs[Index];
      end;
    okBaddy:
      if (Index >= 0) and (Index <= High(Level.Baddies)) then
      begin
        SetLength(Level.Baddies, Length(Level.Baddies) + 1);
        Result := High(Level.Baddies);
        Level.Baddies[Result] := Level.Baddies[Index];
      end;
  end;
  if Result >= 0 then MoveObject(Kind, Result, X, Y);
end;

function TEditorDoc.ObjectRect(Kind: TEditorObjKind; Index: Integer; out X, Y, W, H: Integer): Boolean;
begin
  Result := False;
  W := 2;
  H := 2;
  case Kind of
    okChest:
      if (Index >= 0) and (Index <= High(Level.Chests)) then
      begin
        X := Level.Chests[Index].X;
        Y := Level.Chests[Index].Y;
        Result := True;
      end;
    okNPC:
      if (Index >= 0) and (Index <= High(Level.NPCs)) then
      begin
        X := Trunc(Level.NPCs[Index].X);
        Y := Trunc(Level.NPCs[Index].Y);
        if not (Assigned(NPCSize) and NPCSize(Level.NPCs[Index].Image, W, H)) then
        begin
          W := 2;
          H := 2;
        end;
        if W < 1 then W := 1;
        if H < 1 then H := 1;
        Result := True;
      end;
    okBaddy:
      if (Index >= 0) and (Index <= High(Level.Baddies)) then
      begin
        X := Level.Baddies[Index].X;
        Y := Level.Baddies[Index].Y;
        Result := True;
      end;
    okSign:
      if (Index >= 0) and (Index <= High(Level.Signs)) then
      begin
        X := Level.Signs[Index].X;
        Y := Level.Signs[Index].Y;
        Result := True;
      end;
    okLink:
      if (Index >= 0) and (Index <= High(Level.Links)) then
      begin
        X := Level.Links[Index].X;
        Y := Level.Links[Index].Y;
        W := Level.Links[Index].W;
        H := Level.Links[Index].H;
        Result := True;
      end;
  end;
end;

function TEditorDoc.ObjectAt(X, Y: Integer; out Kind: TEditorObjKind; out Index: Integer): Boolean;
var
  I, RX, RY, RW, RH: Integer;

  function Hit(K: TEditorObjKind; N: Integer): Boolean;
  begin
    Result := ObjectRect(K, N, RX, RY, RW, RH) and (X >= RX) and (Y >= RY) and
      (X < RX + RW) and (Y < RY + RH);
  end;

begin
  Result := True;
  { drawn last is on top: baddies over NPCs over chests }
  for I := High(Level.Baddies) downto 0 do
    if Hit(okBaddy, I) then begin Kind := okBaddy; Index := I; Exit; end;
  for I := High(Level.NPCs) downto 0 do
    if Hit(okNPC, I) then begin Kind := okNPC; Index := I; Exit; end;
  for I := High(Level.Chests) downto 0 do
    if Hit(okChest, I) then begin Kind := okChest; Index := I; Exit; end;
  Kind := okNone;
  Index := -1;
  Result := False;
end;

{ TEditor }

constructor TEditor.Create;
begin
  inherited Create;
  Current := -1;
  Flags := TStringList.Create;
end;

destructor TEditor.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Docs) do Docs[I].Free;
  Flags.Free;
  inherited Destroy;
end;

function TEditor.Doc: TEditorDoc;
begin
  if (Current >= 0) and (Current <= High(Docs)) then Result := Docs[Current]
  else Result := nil;
end;

function TEditor.DocCount: Integer;
begin
  Result := Length(Docs);
end;

function TEditor.NewDoc: TEditorDoc;
begin
  Result := TEditorDoc.Create(Background);
  SetLength(Docs, Length(Docs) + 1);
  Docs[High(Docs)] := Result;
  Current := High(Docs);
end;

function TEditor.OpenDoc(const FileName: string): TEditorDoc;
var
  I: Integer;
begin
  for I := 0 to High(Docs) do
    if (Docs[I].FileName <> '') and (CompareText(ExpandFileName(Docs[I].FileName),
      ExpandFileName(FileName)) = 0) then
    begin
      Current := I;
      Result := Docs[I];
      Exit;
    end;
  Result := TEditorDoc.Create(Background);
  if not Result.Open(FileName) then
  begin
    LastError := Result.LastError;
    Result.Free;
    Result := nil;
    Exit;
  end;
  SetLength(Docs, Length(Docs) + 1);
  Docs[High(Docs)] := Result;
  Current := High(Docs);
end;

procedure TEditor.CloseDoc(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index > High(Docs)) then Exit;
  Docs[Index].Free;
  for I := Index to High(Docs) - 1 do Docs[I] := Docs[I + 1];
  SetLength(Docs, Length(Docs) - 1);
  if Current >= Length(Docs) then Current := High(Docs);
end;

procedure TEditor.Copy;
var
  D: TEditorDoc;
begin
  D := Doc;
  if (D = nil) or not D.HasSel then Exit;
  Clipboard := D.SelectionBlock;
  D.StartFloat(Clipboard, D.SelX, D.SelY);
end;

procedure TEditor.Cut;
var
  D: TEditorDoc;
begin
  D := Doc;
  if (D = nil) or not D.HasSel then Exit;
  Clipboard := D.SelectionBlock;
  D.LiftSelection(Background);
end;

procedure TEditor.Paste(X, Y: Integer);
var
  D: TEditorDoc;
begin
  D := Doc;
  if (D = nil) or (Clipboard.W <= 0) then Exit;
  if D.Floating then D.DropFloat;
  D.StartFloat(Clipboard, X, Y);
end;

procedure TEditor.Delete;
var
  D: TEditorDoc;
begin
  D := Doc;
  if D = nil then Exit;
  if D.Floating then
    D.CancelFloat
  else
    D.FillSelection(Background);
end;

end.
