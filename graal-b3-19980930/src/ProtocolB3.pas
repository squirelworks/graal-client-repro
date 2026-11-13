{ ProtocolB3: what is particular to 3rd Graal (gen 1, linked 19980930)
  on the wire and on disk. Everything here comes from graal_analysis
  client-internals/version-profiles/v1998-v11.toml (the "3rd Graal" entry),
  protocol/relay-1998.md and client-internals/build-catalogue.md. }
unit ProtocolB3;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface


uses
  GBetaHud;
const
  { the build as players and the archive name it, and its folder under
    graal-assets }
  ClientBuildLabel = 'b3';
  ClientBuildName = '3rd Graal';
  { gen 1 sends no version token; the folder carries the link date }
  ClientLinkDate = '19980930';
  ClientVersionToken = '';
  ClientGeneration = 1;

  { the fixed game sent with N, and the prefix of the per-level game
    (G + the level's location) }
  RelayGame = 'Graal';
  RelayRoomPrefix = 'G';
  { 1st and 2nd Graal name the level game Z + level base + 2 }
  RelayZeldaRooms: Boolean = False;

  { D types this build sends (v1998-v11.toml d_types_sent) }
  DTypesSent = 'ABCEFGHLMNOPQRSTW';

  { level magics the loader accepts }
  LevelFormats = 'GR-V1.00,GR-V1.01,Z3-V1.03,Z3-V1.04';

  { colours in the S payload: 4 up to 4th Graal, 5 from 4th Graal alpha }
  ColourCount = 4;

  { the connect dialog: its second port field is pre-filled with the relay
    server on 14802. The host is the project's listserver
    host, never a hard-coded one. }
  HasConnectDialog: Boolean = True;
  DialogHost = 'listserver.graal.in';
  DialogPort = 14802;

  { NR / NL after N picks onlinestart.graal (server levels) or
    onlinestartlocal.graal (local levels); 15th Graal on }
  ServerLevelChoice: Boolean = False;

  { save files, for reference (not written by this rebuild yet) }
  SaveMagic = 'Graalsav1';
  SaveExt = '.save';

  { the offline start: the first of these found in the install }
  { One Player starts in house1.graal, as every original does (read on
    Windows); the others as before when an install has none }
  TrainingLevels = 'levels/house1.graal;house1.graal;levels/level1.graal;level1.graal';

  { P is sent every 100 ms while walking (two 50 ms ticks) }
  PositionEveryTicks = 2;

  { the frame gate, as in the later builds (not measured on 1998 builds) }
  TickMs = 50;

{ True when this build sends D type C (a character from DTypesSent). }
function SendsType(C: Char): Boolean;
{ True when the level magic is one this build reads. }
function AcceptsLevel(const Magic: string): Boolean;

const
  { the character lists of the start dialog, in the build's order (the
    real client's lists, read on Windows; each entry is the head of the
    same column of heads.gif) }
  CharacterNames: array[0..3] of string = (
    'Fung Si Yan',
    'Nick',
    'Mandi',
    'Bad Max');

const
  { The status display: state.gif pieces and places, the digits and the
    hearts, measured against the real client's screen at the start of a
    game (common/GBetaHud.pas). }
  HudLayout: THudLayout = (
    DigitSheet: 'link.gif'; SwordSheet: '';
    DigitY: 1472; DigitH: 14; DigitStep: 12;
    RupeeX: 250; RupeeDigits: 0; BombX: 296; ArrowX: 344; NumberY: 48;
    HeartSX: 348; HeartSY: 33; HeartX: 422; HeartY: 24; HeartStep: 45;
    Count: 5;
    Pieces: (
      (Sheet: 0; SX: 3; SY: 36; W: 60; H: 60; DX: 70; DY: 15),
      (Sheet: 0; SX: 157; SY: 36; W: 31; H: 30; DX: 146; DY: 30),
      (Sheet: 0; SX: 104; SY: 6; W: 16; H: 16; DX: 244; DY: 30),
      (Sheet: 0; SX: 160; SY: 7; W: 16; H: 15; DX: 300; DY: 31),
      (Sheet: 0; SX: 209; SY: 6; W: 15; H: 16; DX: 349; DY: 30),
      (Sheet: 0; SX: 0; SY: 0; W: 0; H: 0; DX: 0; DY: 0),
      (Sheet: 0; SX: 0; SY: 0; W: 0; H: 0; DX: 0; DY: 0),
      (Sheet: 0; SX: 0; SY: 0; W: 0; H: 0; DX: 0; DY: 0)));

  { the rupees the real client shows when a game starts }
  HudStartRupees = 0;

const
  { where One Player puts the player in the start level: measured on the
    real client's first frame (Windows 11, 2026-11-05 captures), beside
    the left bed of house1's room, four tiles left of the room's middle }
  OfflineStartX = '24.5';
  OfflineStartY = '30';

implementation

function SendsType(C: Char): Boolean;
begin
  Result := Pos(C, DTypesSent) > 0;
end;

function AcceptsLevel(const Magic: string): Boolean;
begin
  Result := (Magic <> '') and (Pos(Magic, LevelFormats) > 0);
end;

end.
