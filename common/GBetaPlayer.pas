{ GBetaPlayer: the player of the 1998-1999 betas (1st to 15th Graal),
  drawn the way those builds draw it, from the install's own sheets and
  arrays.dat (graal_analysis client-internals/rebuild-traces-2026-11-05.md,
  "The 1998 betas' player drawing").

  - arrays.dat: the last array holds the sprite rectangles, the array
    seven before it the poses: 4 x N entries, indexed by group x 4 +
    direction. Each part of a pose is one int, sprite shl 16 or dx shl 8
    or dy, with dx and dy signed bytes in eighths of a tile (2 px) from
    the player's x, y. Parts are drawn in their order. Every beta from
    the 1st to the 15th Graal has this shape (19 to 24 arrays).
  - A frame of the animation picks a pose group: 0 idle, 1 to 8 the walk
    cycle (groups 4, 5, 4, 3, 2, 1, 2, 3).
  - Sprite 8192 and up: heads.gif, sprite - 8192 as the rectangle, the
    source x moved by the head number x 32 (the head of the character
    picked in the start dialog: the same column of heads.gif as the
    dialog's list shows). 4096 to 8191: a carried object (not drawn
    here). Anything else: the body sheet (link.gif to the 4th Graal,
    sprites.gif from the 5th).
  - Sprites 1 to 4 are the shield, drawn with shield power 1 or more.
  - The 3rd Graal on mark the recoloured parts of the body sheet with
    key colours: magenta the coat, green the belt, blue the sleeves, and
    the skin and shoe colours of the colour list. The 1st and 2nd Graal
    have no character choice and draw the sheet as it is.

  Checked against the real clients' first frames (Windows 11, betas 1 to
  15): Nick, the first player's default, is drawn red, with the light red
  belt and head 1. The colour sets of the other characters were not
  captured; they are drawn in Nick's colours. }
unit GBetaPlayer;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GCompat,
  GSurface, GArrays;

const
  BetaWalkFrames = 8;
  { Nick's colours (skin, coat, sleeves, shoes, belt), as indices of the
    colour list: measured on the real clients' first frames }
  BetaNickColors: array[0..4] of Integer = (2, 4, 4, 4, 3);

type
  TBetaColors = array[0..4] of Cardinal;

  TBetaPlayerArt = class
  private
    FBody, FTinted, FHeads: TGSurface;
    FPoses, FRects: TGArray;
    FKeyed: Boolean;
    FTintKey: string;
    function Tinted(const Colors: TBetaColors): TGSurface;
  public
    constructor Create;
    destructor Destroy; override;
    { Count: how many arrays the install's arrays.dat really holds (the
      rest of Arrays.Lists is padding). Body and Heads are the sheets
      (Heads may be nil). Takes neither surface over. False when the
      tables or the body sheet are missing. }
    function Setup(Arrays: TGArrays; Count: Integer; Body, Heads: TGSurface): Boolean;
    function Ready: Boolean;
    { The pose group of animation frame Frame (0 idle, 1 to 8 walking). }
    class function GroupOf(Frame: Integer): Integer;
    { Sprite Index's rectangle in the sprite table. }
    function Rect(Index: Integer; out X, Y, W, H: Integer): Boolean;
    { Draws the player with its top-left at (X, Y). }
    procedure Draw(Dest: TGSurface; X, Y, Group, Dir, Head, ShieldPower: Integer;
      const Colors: TBetaColors);
    property Keyed: Boolean read FKeyed;
  end;

implementation

uses
  SysUtils;

const
  { frame to pose group, the start of the build's table }
  FrameGroups: array[0..8] of Integer = (0, 4, 5, 4, 3, 2, 1, 2, 3);
  KeyCoat = $FFFF00FF;
  KeyBelt = $FF00FF00;
  KeySleeves = $FF0000FF;
  KeySkin = $FFFFAD6B;
  KeyShoes = $FFCE1829;

constructor TBetaPlayerArt.Create;
begin
  inherited Create;
  FBody := TGSurface.Create(0, 0);
  FTinted := TGSurface.Create(0, 0);
  FHeads := TGSurface.Create(0, 0);
end;

destructor TBetaPlayerArt.Destroy;
begin
  FBody.Free;
  FTinted.Free;
  FHeads.Free;
  inherited Destroy;
end;

function TBetaPlayerArt.Setup(Arrays: TGArrays; Count: Integer; Body, Heads: TGSurface): Boolean;
var
  I: Integer;
begin
  Result := False;
  FPoses := nil;
  FRects := nil;
  FTintKey := '';
  FBody.SetSize(0, 0);
  FHeads.SetSize(0, 0);
  if (Arrays = nil) or (Body = nil) or (Count < 8) or (Count > 25) then Exit;
  FRects := Arrays.Lists[Count - 1];
  FPoses := Arrays.Lists[Count - 8];
  if (FRects = nil) or (FPoses = nil) or (Length(FRects.Values) = 0) or
    (Length(FPoses.Items) < 4) then
  begin
    FPoses := nil;
    FRects := nil;
    Exit;
  end;
  FBody.SetSize(Body.Width, Body.Height);
  FBody.Pixels := Copy(Body.Pixels, 0, Length(Body.Pixels));
  if Heads <> nil then
  begin
    FHeads.SetSize(Heads.Width, Heads.Height);
    FHeads.Pixels := Copy(Heads.Pixels, 0, Length(Heads.Pixels));
  end;
  FKeyed := False;
  for I := 0 to High(FBody.Pixels) do
    if FBody.Pixels[I] = KeyCoat then
    begin
      FKeyed := True;
      Break;
    end;
  Result := Ready;
end;

function TBetaPlayerArt.Ready: Boolean;
begin
  Result := (FPoses <> nil) and (FRects <> nil) and (FBody.Width > 0);
end;

class function TBetaPlayerArt.GroupOf(Frame: Integer): Integer;
begin
  if (Frame < 0) or (Frame > High(FrameGroups)) then Frame := 0;
  Result := FrameGroups[Frame];
end;

function TBetaPlayerArt.Rect(Index: Integer; out X, Y, W, H: Integer): Boolean;
var
  V: Cardinal;
begin
  X := 0;
  Y := 0;
  W := 0;
  H := 0;
  Result := False;
  if (FRects = nil) or (Index < 0) or (Index > High(FRects.Values)) then Exit;
  V := Cardinal(FRects.Values[Index]);
  X := Integer(V shr 23);
  Y := Integer((V shr 12) and 2047) * 2;
  W := Integer((V shr 6) and 63) * 2;
  H := Integer(V and 63) * 2;
  Result := (W > 0) and (H > 0);
end;

function TBetaPlayerArt.Tinted(const Colors: TBetaColors): TGSurface;
var
  Key: string;
  I: Integer;
  C: Cardinal;
begin
  Result := FBody;
  if not FKeyed then Exit;
  Key := '';
  for I := 0 to 4 do Key := Key + IntToHex(Colors[I], 8);
  if Key <> FTintKey then
  begin
    FTinted.SetSize(FBody.Width, FBody.Height);
    for I := 0 to High(FBody.Pixels) do
    begin
      C := FBody.Pixels[I];
      if C = KeySkin then C := Colors[0]
      else if C = KeyCoat then C := Colors[1]
      else if C = KeySleeves then C := Colors[2]
      else if C = KeyShoes then C := Colors[3]
      else if C = KeyBelt then C := Colors[4];
      FTinted.Pixels[I] := C;
    end;
    FTintKey := Key;
  end;
  Result := FTinted;
end;

procedure TBetaPlayerArt.Draw(Dest: TGSurface; X, Y, Group, Dir, Head, ShieldPower: Integer;
  const Colors: TBetaColors);
var
  Pose: TGArray;
  I, Part, S, DX, DY, SX, SY, SW, SH: Integer;
  Img: TGSurface;
begin
  if not Ready then Exit;
  I := Group * 4 + (Dir and 3);
  if (I < 0) or (I > High(FPoses.Items)) then I := Dir and 3;
  Pose := FPoses.Items[I];
  if Pose = nil then Exit;
  for I := 0 to High(Pose.Values) do
  begin
    Part := Pose.Values[I];
    S := (Part shr 16) and $FFFF;
    DX := ShortInt(Byte((Part shr 8) and $FF));
    DY := ShortInt(Byte(Part and $FF));
    if S >= 8192 then
    begin
      if (FHeads.Width = 0) or not Rect(S - 8192, SX, SY, SW, SH) then Continue;
      Img := FHeads;
      SX := SX + Head * 32;
    end
    else if S >= 4096 then
      Continue
    else
    begin
      if (S >= 1) and (S <= 4) and (ShieldPower < 1) then Continue;
      if not Rect(S, SX, SY, SW, SH) then Continue;
      Img := Tinted(Colors);
    end;
    Dest.Blit(Img, SX, SY, SW, SH, X + DX * 2, Y + DY * 2);
  end;
end;

end.
