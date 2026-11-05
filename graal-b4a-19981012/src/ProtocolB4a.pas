{ ProtocolB4a: what is particular to 4th Graal alpha (gen 1, linked 19981012)
  on the wire and on disk. Everything here comes from graal_analysis
  client-internals/version-profiles/v1998-v11.toml (the "4th Graal alpha" entry),
  protocol/relay-1998.md and client-internals/build-catalogue.md. }
unit ProtocolB4a;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { the build as players and the archive name it, and its folder under
    graal-assets }
  ClientBuildLabel = 'b4a';
  ClientBuildName = '4th Graal alpha';
  { gen 1 sends no version token; the folder carries the link date }
  ClientLinkDate = '19981012';
  ClientVersionToken = '';
  ClientGeneration = 1;

  { the fixed game sent with N, and the prefix of the per-level game
    (G2 + the level's location) }
  RelayGame = 'Graal2';
  RelayRoomPrefix = 'G2';
  { 1st and 2nd Graal name the level game Z + level base + 2 }
  RelayZeldaRooms: Boolean = False;

  { D types this build sends (v1998-v11.toml d_types_sent) }
  DTypesSent = 'ABCEFGHILMNOPQRSTUWXYZ';

  { level magics the loader accepts }
  LevelFormats = 'GR-V1.00,GR-V1.01,Z3-V1.03,Z3-V1.04';

  { colours in the S payload: 4 up to 4th Graal, 5 from 4th Graal alpha }
  ColourCount = 5;

  { the connect dialog: this build has no pre-filled relay host; its
    compiled-in default port is 14801. The host is the project's listserver
    host, never a hard-coded one. }
  HasConnectDialog: Boolean = False;
  DialogHost = 'listserver.graal.in';
  DialogPort = 14801;

  { NR / NL after N picks onlinestart.graal (server levels) or
    onlinestartlocal.graal (local levels); 15th Graal on }
  ServerLevelChoice: Boolean = False;

  { save files, for reference (not written by this rebuild yet) }
  SaveMagic = 'Graalsav2';
  SaveExt = '.save';

  { the offline start: the first of these found in the install }
  TrainingLevels = 'levels/level1.graal;level1.graal';

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
  CharacterNames: array[0..5] of string = (
    'Fung Si Yan',
    'Nick',
    'Mandi',
    'Bad Max',
    'Pachukite',
    'Blond');

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
