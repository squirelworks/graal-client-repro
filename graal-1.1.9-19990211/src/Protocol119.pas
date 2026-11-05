{ Protocol119: constants of the 1.1.9 client.

  1.1.9 speaks the relay protocol of the 1998 betas (encryption
  generation 1): text lines, no token, no compression
  (graal_analysis protocol/relay-1998.md). The game code below the link
  still works on numbered events; the PLI_ / PLO_ numbers are kept as
  those event numbers, and GraalClient maps them to and from relay lines.
  The RLO_ events have no number on any wire: they are the relay's own
  lines (an id, a partner, a peer gone) told to the game. }
unit Protocol119;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { the generation scripts/loopback.sh reads to pick the relay check }
  ClientGeneration = 1;

  { What the connect dialog is filled with when listserver.txt names nothing.
    1.1.9 filled it with the Cyberjoueur relay host on 14802, which is gone;
    the community host stands in, never a hard-coded address. The port
    stays the relay's 14802: 14923 is the listserver port of the later
    clients, which speaks a protocol a relay client cannot. }
  DefaultListHost = 'listserver.graal.in';
  DefaultListPort = 14802;

  { 1.1.9 sends no version token. The build is named by its link date. }
  ClientVersionToken = '';
  ClientBuildId = '19990211';
  ClientBuildLabel = '1.1.9';
  { asset folders under graal-assets/: its own, then 15th Graal's and
    11th Graal's, whose install files it shares (1,501 of its 1,649 files
    are the same as 15th Graal's) }
  ClientAssetFolders = '1.1.9;b15;b11';

  { the relay games: the fixed one, and the prefix of the level rooms }
  RelayGame = 'Graal8';
  RelayLevelPrefix = 'G8';

  { The start levels: One Player starts on level1.graal; online the client
    starts on onlinestart.graal and moves to onlinestartlocal.graal when
    the server says it plays local levels (NL). }
  OfflineStartLevel = 'level1.graal';
  OnlineStartLevel = 'onlinestart.graal';
  OnlineLocalLevel = 'onlinestartlocal.graal';

  TickMs = 50;          { the idle handler's frame gate }

  { relay events told to the game (not wire numbers) }
  RLO_JOINED = 1000;      { the game link has its id }
  RLO_PARTNER = 1001;     { paired with a player: push the whole state }
  RLO_PEERLEFT = 1002;    { a player of the level room went }
  RLO_LEVELSOURCE = 1003; { NR or NL after the join }
  RLO_UNHANDLED = 1004;   { a D type this rebuild does not apply yet }

  { client -> server }
  PLI_LEVELWARP = 0;
  PLI_BOARDMODIFY = 1;
  PLI_PLAYERPROPS = 2;
  PLI_NPCPROPS = 3;
  PLI_BOMBADD = 4;
  PLI_BOMBDEL = 5;
  PLI_ARROWADD = 9;
  PLI_NPCWEAPONDEL = 29;
  PLI_HURTPLAYER = 26;
  PLI_EXPLOSION = 27;
  PLI_TOALL = 6;
  PLI_ITEMDEL = 13;
  PLI_OPENCHEST = 20;
  PLI_WANTFILE = 23;
  PLI_PRIVATEMESSAGE = 28;
  PLI_ITEMTAKE = 32;
  PLI_ADJACENTLEVEL = 35;
  PLI_LANGUAGE = 37;
  PLI_TRIGGERACTION = 38;
  PLI_PROFILEGET = 80;
  PLI_PROFILESET = 81;

  { server -> client }
  PLO_LEVELBOARD = 0;
  PLO_LEVELLINK = 1;
  PLO_BADDYPROPS = 2;
  PLO_NPCPROPS = 3;
  PLO_LEVELCHEST = 4;
  PLO_LEVELSIGN = 5;
  PLO_LEVELNAME = 6;
  PLO_BOARDMODIFY = 7;
  PLO_OTHERPLPROPS = 8;
  PLO_PLAYERPROPS = 9;
  PLO_ISLEADER = 10;
  PLO_TOALL = 13;
  PLO_PLAYERWARP = 14;
  PLO_WARPFAILED = 15;
  PLO_DISCMESSAGE = 16;
  PLO_BOMBADD = 11;
  PLO_BOMBDEL = 12;
  PLO_ITEMADD = 22;
  PLO_EXPLOSION = 36;
  PLO_HURTPLAYER = 40;
  PLO_ITEMDEL = 23;
  PLO_SIGNATURE = 25;
  PLO_FLAGSET = 28;
  PLO_FILESENDFAILED = 30;
  PLO_ARROWADD = 19;
  PLO_NPCWEAPONADD = 33;
  PLO_NPCWEAPONDEL = 34;
  PLO_PRIVATEMESSAGE = 37;
  PLO_LEVELMODTIME = 39;
  PLO_STARTMESSAGE = 41;
  PLO_NEWWORLDTIME = 42;
  PLO_DEFAULTWEAPON = 43;
  PLO_HASNPCSERVER = 44;
  PLO_FILEUPTODATE = 45;
  PLO_STAFFGUILDS = 47;
  PLO_PROFILE = 75;
  PLO_RAWDATA = 100;
  PLO_BOARDPACKET = 101;
  PLO_FILE = 102;
  PLO_SAY2 = 153;
  PLO_SETACTIVELEVEL = 156;
  PLO_UNKNOWN168 = 168;

  { player props (pre-2.1 forms, as the server sends them to GNW03081) }
  PLPROP_NICKNAME = 0;
  PLPROP_MAXPOWER = 1;
  PLPROP_CURPOWER = 2;
  PLPROP_RUPEESCOUNT = 3;
  PLPROP_ARROWSCOUNT = 4;
  PLPROP_BOMBSCOUNT = 5;
  PLPROP_GLOVEPOWER = 6;
  PLPROP_BOMBPOWER = 7;
  PLPROP_SWORDPOWER = 8;
  PLPROP_SHIELDPOWER = 9;
  PLPROP_BOWGIF = 10;
  PLPROP_HEADGIF = 11;
  PLPROP_CURCHAT = 12;
  PLPROP_COLORS = 13;
  PLPROP_ID = 14;
  PLPROP_X = 15;
  PLPROP_Y = 16;
  PLPROP_SPRITE = 17;
  PLPROP_STATUS = 18;
  PLPROP_CARRYSPRITE = 19;
  PLPROP_CURLEVEL = 20;
  PLPROP_HORSEGIF = 21;
  PLPROP_HORSEBUSHES = 22;
  PLPROP_EFFECTCOLORS = 23;
  PLPROP_CARRYNPC = 24;
  PLPROP_APCOUNTER = 25;
  PLPROP_MAGICPOINTS = 26;
  PLPROP_KILLSCOUNT = 27;
  PLPROP_DEATHSCOUNT = 28;
  PLPROP_ONLINESECS = 29;
  PLPROP_IPADDR = 30;
  PLPROP_UDPPORT = 31;
  PLPROP_ALIGNMENT = 32;
  PLPROP_ADDITFLAGS = 33;
  PLPROP_ACCOUNTNAME = 34;
  PLPROP_BODYIMG = 35;
  PLPROP_RATING = 36;
  PLPROP_GATTRIB1 = 37;
  PLPROP_GATTRIB5 = 41;
  PLPROP_ATTACHNPC = 42;
  PLPROP_GMAPLEVELX = 43;
  PLPROP_GMAPLEVELY = 44;
  PLPROP_Z = 45;
  PLPROP_GATTRIB6 = 46;
  PLPROP_GATTRIB9 = 49;
  PLPROP_JOINLEAVELVL = 50;
  PLPROP_PCONNECTED = 51;
  PLPROP_PLANGUAGE = 52;
  PLPROP_PSTATUSMSG = 53;
  PLPROP_GATTRIB10 = 54;
  PLPROP_GATTRIB30 = 74;

function PLOName(Id: Integer): string;

const
  { the character lists of the start dialog, in the build's order (the
    real client's lists); each entry is the head of the same column of
    heads.gif }
  CharacterNames: array[0..20] of string = (
    'Fung Si Yan',
    'Nick',
    'Mandi',
    'Bad Max',
    'Pachukite',
    'Blond',
    'Dino',
    'Brendan',
    'Athena',
    'Bob',
    'Zoraas',
    'Raven',
    'Joe',
    'Old Man',
    'Slade',
    'Azraelite',
    'NeoKnight',
    'Thief',
    'Adventurer',
    'Ninji Knight',
    'Fire');

implementation

uses
  SysUtils;

function PLOName(Id: Integer): string;
begin
  case Id of
    PLO_LEVELBOARD: Result := 'LEVELBOARD';
    PLO_LEVELLINK: Result := 'LEVELLINK';
    PLO_BADDYPROPS: Result := 'BADDYPROPS';
    PLO_NPCPROPS: Result := 'NPCPROPS';
    PLO_LEVELCHEST: Result := 'LEVELCHEST';
    PLO_LEVELSIGN: Result := 'LEVELSIGN';
    PLO_LEVELNAME: Result := 'LEVELNAME';
    PLO_BOARDMODIFY: Result := 'BOARDMODIFY';
    PLO_OTHERPLPROPS: Result := 'OTHERPLPROPS';
    PLO_PLAYERPROPS: Result := 'PLAYERPROPS';
    PLO_ISLEADER: Result := 'ISLEADER';
    PLO_TOALL: Result := 'TOALL';
    PLO_PLAYERWARP: Result := 'PLAYERWARP';
    PLO_WARPFAILED: Result := 'WARPFAILED';
    PLO_DISCMESSAGE: Result := 'DISCMESSAGE';
    PLO_SIGNATURE: Result := 'SIGNATURE';
    PLO_FLAGSET: Result := 'FLAGSET';
    PLO_FILESENDFAILED: Result := 'FILESENDFAILED';
    PLO_NPCWEAPONADD: Result := 'NPCWEAPONADD';
    PLO_NPCWEAPONDEL: Result := 'NPCWEAPONDEL';
    PLO_ARROWADD: Result := 'ARROWADD';
    PLO_PRIVATEMESSAGE: Result := 'PRIVATEMESSAGE';
    PLO_LEVELMODTIME: Result := 'LEVELMODTIME';
    PLO_STARTMESSAGE: Result := 'STARTMESSAGE';
    PLO_NEWWORLDTIME: Result := 'NEWWORLDTIME';
    PLO_DEFAULTWEAPON: Result := 'DEFAULTWEAPON';
    PLO_HASNPCSERVER: Result := 'HASNPCSERVER';
    PLO_FILEUPTODATE: Result := 'FILEUPTODATE';
    PLO_STAFFGUILDS: Result := 'STAFFGUILDS';
    PLO_PROFILE: Result := 'PROFILE';
    PLO_RAWDATA: Result := 'RAWDATA';
    PLO_BOARDPACKET: Result := 'BOARDPACKET';
    PLO_FILE: Result := 'FILE';
    PLO_SAY2: Result := 'SAY2';
    PLO_SETACTIVELEVEL: Result := 'SETACTIVELEVEL';
    PLO_UNKNOWN168: Result := 'UNKNOWN168';
  else
    Result := 'PLO_' + IntToStr(Id);
  end;
end;

end.
