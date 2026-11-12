{ Anim39: 39ster's player animations and how its character is drawn.

  From Graal_analysis client-internals/precursor-mechanics-2026-11-09.md
  ("Controls and animation", "Start and drawing"):
  - eight ganis: idle, walk, sword, swim, sit, grab, pull, push;
  - the frame position advances by 0.35 x the time factor each update;
  - an animation loops, switches to its return animation, or holds its
    last frame;
  - frame commands such as wait and sound are skipped, so every step of a
    gani lasts the same;
  - the player is drawn as separate body, head, shield, sword and
    attribute pieces.

  The ganis and pictures are the player's own (levels/<name>.gani and the
  pictures they name, read through common/GAssetDirs). Nothing of the
  original is built in. }
unit Anim39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes, GAni, GSurface, Profile39;

type
  { The animation one character is playing. }
  TAnimState39 = record
    Gani: TGani39;
    Pos: Double;      { frame position; the frame shown is Trunc(Pos) }
  end;

  { The eight ganis of an install, and the pictures their pieces use. }
  TGaniSet39 = class
  private
    FImages: TStringList;   { file name -> TGSurface (nil when not found) }
    function Image(const FileName: string): TGSurface;
  public
    Ganis: array[TGani39] of TGraalAni;
    constructor Create;
    destructor Destroy; override;
    { levels/<name>.gani for each of the eight; False if any is missing
      (the missing ones keep the profile's frame count and draw nothing) }
    function LoadInstall: Boolean;
    { steps in gani G: the file's, else the profile's frame count }
    function Frames(G: TGani39): Integer;
    function Loops(G: TGani39): Boolean;
    { the gani G switches to when it ends; False when it has none }
    function ReturnTo(G: TGani39; out R: TGani39): Boolean;
    { The picture a sprite sheet name stands for in gani G: the gani's
      DEFAULT line for that piece, else the profile's file for it. }
    function PieceFile(G: TGani39; const Sheet: string): string;
    { Draws the character's frame for State, facing F, with its gani
      origin at (X, Y) on Dest. }
    procedure DrawCharacter(Dest: TGSurface; const State: TAnimState39;
      F: TFacing39; X, Y: Integer);
  end;

{ Starts gani G unless it is already playing. }
procedure PlayGani(var State: TAnimState39; G: TGani39);
{ One update at time factor TF: the position moves 0.35 x TF; at the end
  the gani loops, switches to its return gani, or holds its last frame. }
procedure AdvanceAnim(var State: TAnimState39; Ganis: TGaniSet39; TF: Double);
{ The step shown: Trunc(Pos), kept inside the gani. }
function AnimFrame(const State: TAnimState39; Ganis: TGaniSet39): Integer;
function GaniByName(const Name: string; out G: TGani39): Boolean;

implementation

uses
  SysUtils, GAssetDirs;

function GaniByName(const Name: string; out G: TGani39): Boolean;
var
  I: TGani39;
  N: string;
begin
  N := LowerCase(Trim(Name));
  if (Length(N) > 5) and (Copy(N, Length(N) - 4, 5) = '.gani') then
    N := Copy(N, 1, Length(N) - 5);
  for I := Low(TGani39) to High(TGani39) do
    if GaniName[I] = N then
    begin
      G := I;
      Result := True;
      Exit;
    end;
  G := gIdle;
  Result := False;
end;

procedure PlayGani(var State: TAnimState39; G: TGani39);
begin
  if State.Gani = G then Exit;
  State.Gani := G;
  State.Pos := 0;
end;

procedure AdvanceAnim(var State: TAnimState39; Ganis: TGaniSet39; TF: Double);
var
  N: Integer;
  R: TGani39;
begin
  N := Ganis.Frames(State.Gani);
  State.Pos := State.Pos + FrameAdvance * TF;
  if (N <= 0) or (State.Pos < N) then Exit;
  if Ganis.Loops(State.Gani) then
    State.Pos := State.Pos - Trunc(State.Pos / N) * N
  else if Ganis.ReturnTo(State.Gani, R) then
  begin
    State.Gani := R;
    State.Pos := 0;
  end
  else
    State.Pos := N - 1;
end;

function AnimFrame(const State: TAnimState39; Ganis: TGaniSet39): Integer;
var
  N: Integer;
begin
  N := Ganis.Frames(State.Gani);
  Result := Trunc(State.Pos);
  if Result >= N then Result := N - 1;
  if Result < 0 then Result := 0;
end;

constructor TGaniSet39.Create;
begin
  inherited Create;
  FImages := TStringList.Create;
  FImages.Sorted := True;
  FImages.CaseSensitive := False;
end;

destructor TGaniSet39.Destroy;
var
  I: Integer;
  G: TGani39;
begin
  for I := 0 to FImages.Count - 1 do FImages.Objects[I].Free;
  FImages.Free;
  for G := Low(TGani39) to High(TGani39) do Ganis[G].Free;
  inherited Destroy;
end;

function TGaniSet39.LoadInstall: Boolean;
var
  G: TGani39;
  P: string;
  A: TGraalAni;
begin
  Result := True;
  for G := Low(TGani39) to High(TGani39) do
  begin
    FreeAndNil(Ganis[G]);
    P := AssetPath('levels/' + GaniName[G] + '.gani');
    A := TGraalAni.Create;
    if (P <> '') and A.LoadFromFile(P) and (Length(A.Steps) > 0) then
      Ganis[G] := A
    else
    begin
      A.Free;
      Result := False;
    end;
  end;
end;

function TGaniSet39.Frames(G: TGani39): Integer;
begin
  if Ganis[G] <> nil then Result := Length(Ganis[G].Steps)
  else Result := GaniFrames[G];
end;

function TGaniSet39.Loops(G: TGani39): Boolean;
begin
  if Ganis[G] <> nil then Result := Ganis[G].Loop
  else Result := G in [gWalk, gSwim, gPull, gPush];
end;

function TGaniSet39.ReturnTo(G: TGani39; out R: TGani39): Boolean;
begin
  if Ganis[G] <> nil then
    Result := (Ganis[G].SetBackTo <> '') and GaniByName(Ganis[G].SetBackTo, R)
  else
  begin
    { the sword returns to idle (the notes' "sword return") }
    R := gIdle;
    Result := G = gSword;
  end;
end;

function TGaniSet39.PieceFile(G: TGani39; const Sheet: string): string;
var
  S: string;
  A: TGraalAni;
  N: Integer;
begin
  Result := '';
  S := UpperCase(Sheet);
  A := Ganis[G];
  if S = 'SPRITES' then Result := PieceSprites
  else if S = 'HEAD' then
  begin
    if A <> nil then Result := A.DefaultHead;
    if (Result = '') or (AssetPath('levels/' + Result) = '') then Result := PieceHead;
  end
  else if S = 'BODY' then
  begin
    if A <> nil then Result := A.DefaultBody;
    if (Result = '') or (AssetPath('levels/' + Result) = '') then Result := PieceBody;
  end
  else if S = 'SWORD' then Result := PieceSword
  else if S = 'SHIELD' then Result := PieceShield
  else if Copy(S, 1, 4) = 'ATTR' then
  begin
    N := StrToIntDef(Copy(S, 5, 2), 0);
    if (A <> nil) and (N >= 1) and (N <= 30) then Result := A.DefaultAttr[N];
    if ((Result = '') or (AssetPath('levels/' + Result) = '')) and (N = 1) then
      Result := PieceAttr1;
  end
  else if Copy(S, 1, 5) = 'PARAM' then
  begin
    N := StrToIntDef(Copy(S, 6, 2), 0);
    if (A <> nil) and (N >= 1) and (N <= 20) then Result := A.DefaultParam[N];
  end
  else
    Result := Sheet;   { a file named in the sprite table }
end;

function TGaniSet39.Image(const FileName: string): TGSurface;
var
  I: Integer;
  P: string;
begin
  Result := nil;
  if FileName = '' then Exit;
  if FImages.Find(FileName, I) then
  begin
    Result := TGSurface(FImages.Objects[I]);
    Exit;
  end;
  P := AssetPath('levels/' + FileName);
  if P = '' then P := AssetPath(FileName);
  if P <> '' then
  begin
    Result := TGSurface.Create(1, 1);
    if not LoadImageFile(P, Result) then FreeAndNil(Result);
  end;
  FImages.AddObject(FileName, Result);
end;

procedure TGaniSet39.DrawCharacter(Dest: TGSurface; const State: TAnimState39;
  F: TFacing39; X, Y: Integer);
var
  A: TGraalAni;
  Row: TGraalAniPartList;
  Sp: TGraalAniSprite;
  Img: TGSurface;
  I, D, Step, P: Integer;
begin
  A := Ganis[State.Gani];
  if (A = nil) or (Length(A.Steps) = 0) then Exit;
  Step := AnimFrame(State, Self);
  if Step > High(A.Steps) then Step := High(A.Steps);
  if A.SingleDirection then D := 0 else D := Ord(F);
  Row := A.Steps[Step].Dirs[D];
  for I := 0 to High(Row) do
  begin
    if Row[I].Sprite <= ParamSprite then
    begin
      { PARAMn as a sheet of its own: the whole picture }
      P := ParamSprite - Row[I].Sprite;
      if (P >= 1) and (P <= 20) then Img := Image(A.DefaultParam[P]) else Img := nil;
      if Img <> nil then
        Dest.Blit(Img, 0, 0, Img.Width, Img.Height, X + Row[I].X, Y + Row[I].Y);
      Continue;
    end;
    if not A.FindSprite(Row[I].Sprite, Sp) then Continue;
    Img := Image(PieceFile(State.Gani, Sp.Sheet));
    if Img = nil then Continue;
    Dest.Blit(Img, Sp.X, Sp.Y, Sp.W, Sp.H, X + Row[I].X, Y + Row[I].Y);
  end;
end;

end.
