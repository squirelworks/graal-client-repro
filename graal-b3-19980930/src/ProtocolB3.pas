{ ProtocolB3: what is particular to 3rd Graal (gen 1, linked 19980930)
  on the wire and on disk. Everything here comes from graal_analysis
  client-internals/version-profiles/v1998-v11.toml (the "3rd Graal" entry),
  protocol/relay-1998.md and client-internals/build-catalogue.md. }
unit ProtocolB3;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

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
  TrainingLevels = 'levels/level1.graal;level1.graal';

  { P is sent every 100 ms while walking (two 50 ms ticks) }
  PositionEveryTicks = 2;

  { the frame gate, as in the later builds (not measured on 1998 builds) }
  TickMs = 50;

{ True when this build sends D type C (a character from DTypesSent). }
function SendsType(C: Char): Boolean;
{ True when the level magic is one this build reads. }
function AcceptsLevel(const Magic: string): Boolean;

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
