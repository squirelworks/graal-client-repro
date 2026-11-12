{ Profile39: the 39ster client 1.00 profile.

  39ster's Graal client 1.00 (April 2014) is an offline fan remake: a small
  C++ engine on SDL 1.2 with the GameMonkey scripting language, where all
  of the Graal logic is in a game script. It is not a Delphi Graal client
  and not one of the Torque builds. This folder is a behavioural port in
  Object Pascal, not the original's language or runtime.

  Every value here is from Graal_analysis
  client-internals/precursor-mechanics-2026-11-09.md ("39ster's client
  mechanics", evidence GRAAL39STER-ENGINE-20261109-01) and
  client-internals/precursors-and-fan-builds.md. Only the town render and
  pause were checked at run time; the numbers were not. The original's game
  script and art are never imported: the player's own install supplies the
  levels, tile sheet and category table at run time. }
unit Profile39;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ClientBuildLabel = '39ster 1.00';
  { its folder under graal-assets/ }
  ClientAssetFolders = '39ster';

  { Start: level13.nw at pixel (512, 512), facing down }
  StartLevel = 'level13.nw';
  StartX = 512;
  StartY = 512;

  { the view, in pixels, and the tile size }
  ViewW = 640;
  ViewH = 480;
  TilePx = 16;

  { The tile sheet: 128 x 32 cells. A 12-bit tile id is placed with the 2.x
    pics1 rule: each block of 512 ids moves 16 columns across. }
  SheetCols = 128;
  SheetRows = 32;
  SheetCells = SheetCols * SheetRows;
  TileIdBits = 12;
  TileIdBlock = 512;
  TileIdBlockCols = 16;

  { Movement, per nominal update (not wired into a game loop yet) }
  MoveStep = 3;          { pixels }
  GetUpStep = 2;         { pixels, getting up from sitting }
  DiagonalScale = 0.75;  { each component of a diagonal move }
  SlideScale = 1.5;      { a single-axis blocked move slides at this x the time factor }
  NominalFrameMs = 1000 / 60;
  TimeFactorCap = 4;

  { Animation }
  FrameAdvance = 0.35;   { frame position step x the time factor }
  FreezeDrop = 60;       { the freeze counter drops 60 x the time factor per update }
  SwordFrames = 5;
  SignPageLines = 3;

type
  { Facing order: up, left, down, right }
  TFacing39 = (fUp, fLeft, fDown, fRight);

  { Tile categories, in the order the notes list them. The category is an
    index, turned into a bit only when tested; it is not a collision mask.
    Lava is named in the original but no tile uses it. }
  TCategory39 = (tcGround, tcBlocking, tcThrowThrough, tcWater, tcChair,
    tcJump, tcSwamp, tcShallowWater, tcLava);

  { The eight ganis it ships, with their frame counts }
  TGani39 = (gIdle, gWalk, gSword, gSwim, gSit, gGrab, gPull, gPush);

const
  StartFacing = fDown;
  GaniName: array[TGani39] of string = ('idle', 'walk', 'sword', 'swim',
    'sit', 'grab', 'pull', 'push');
  GaniFrames: array[TGani39] of Integer = (1, 8, 5, 8, 1, 1, 3, 5);

{ The time factor for a previous frame of Ms milliseconds: Ms / (1000/60),
  capped at 4. }
function TimeFactor(Ms: Double): Double;

implementation

function TimeFactor(Ms: Double): Double;
begin
  if Ms <= 0 then Result := 0
  else Result := Ms / NominalFrameMs;
  if Result > TimeFactorCap then Result := TimeFactorCap;
end;

end.
