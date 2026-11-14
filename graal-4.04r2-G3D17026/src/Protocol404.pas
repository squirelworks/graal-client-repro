{ Protocol404: message ids and constants of the 4.04r2 Windows client
  (G3D17026).

  4.x is a Delphi launcher over a C++ engine DLL; on the wire it is gen 5,
  as 2.22 to 4.04r2 (graal_analysis protocol/v4x-clients.md). Sources:
  protocol/v4x-clients.md, version-profiles/4.04-4.20.toml and the lab
  runs of the real 4.04r2 under Wine (client-internals/
  live-behaviour-404.md). There is no listserver protocol any more: the
  client logs in to a game server named Login, which serves the list and
  hands the client on with 178. 4.04r2 handles 98 server ids; every other
  id is ignored silently. }
unit Protocol404;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { The 8-byte version token in the login line (v4x-clients.md, "Version
    tokens": 17 February 2006; GServer-v2 reports it as 4.042). }
  ClientVersionToken = 'G3D17026';
  ClientBuildLabel = '4.04r2';
  { After the password the login line carries an unprefixed comma list:
    the platform and three machine fields. }
  LoginPlatform = 'win';
  { Login type 5, gen-5 cipher on the server, as 2.22. }
  ClientType = 5;
  { The first server: a game server named Login (license.graal). }
  LoginServerName = 'Login';

  { 4.x never sends PLI_TAMPERCHECK (39) (4.04-4.20.toml). }

  { gen-5 cipher: the same LCG as gen 3 }
  CipherSeed: Cardinal = $04A80B38;
  CipherMul: Cardinal = $08088405;
  { XOR group limits per compression type (codec-and-framing.md) }
  XorGroupsRaw = 12;
  XorGroupsPacked = 4;
  { Compression bytes. Odd codes are the same compression with no XOR. }
  CompressNone = 2;
  CompressZlib = 4;
  CompressBz2 = 6;
  { Buffer size thresholds for the compression choice (client-versions.md,
    "Gen-5 send on the client"). }
  ZlibFrom = $30;
  Bz2From = $1000;

  { The out buffer is sent at the end of each tick. 4.04r2's own threshold
    for an early flush is not traced; this one keeps a raw body under the
    u16be frame length. }
  OutFlushAt = 60000;
  OutDropAt = $40000;   { more than 256 KB queued drops the link }
  { Receive limits. These are the rebuild's, not 2.22's: they keep a hostile
    server from growing the client without bound. }
  InFrameMax = 16 * 1024 * 1024;  { one inflated frame }
  InPendingMax = 4 * 1024 * 1024; { an unfinished message }
  TickMs = 50;          { the frame gate (the lab saw 0.5 tiles per 50 ms) }

  { client -> server }
  PLI_LEVELWARP = 0;
  PLI_BOARDMODIFY = 1;
  PLI_PLAYERPROPS = 2;
  PLI_NPCPROPS = 3;
  PLI_BOMBADD = 4;
  PLI_BOMBDEL = 5;
  PLI_TOALL = 6;
  PLI_ARROWADD = 9;
  PLI_THROWCARRIED = 11;
  PLI_ITEMADD = 12;
  PLI_ITEMDEL = 13;
  PLI_OPENCHEST = 20;
  PLI_HURTPLAYER = 26;
  PLI_EXPLOSION = 27;
  PLI_ITEMTAKE = 32;
  PLI_FLAGSET = 18;
  PLI_FLAGDEL = 19;
  PLI_WANTFILE = 23;
  PLI_SHOWIMG = 24;
  PLI_PRIVATEMESSAGE = 28;
  PLI_LEVELWARPMOD = 30;
  PLI_PACKETCOUNT = 31;
  PLI_UPDATEFILE = 34;
  PLI_ADJACENTLEVEL = 35;
  PLI_LANGUAGE = 37;
  PLI_ENTERLEVEL = 46;
  PLI_UPDATEGANI = 157;
  PLI_TRIGGERACTION = 38;
  PLI_TAMPERCHECK = 39;
  PLI_PROCESSLIST = 44;

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
  PLO_BOMBADD = 11;
  PLO_BOMBDEL = 12;
  PLO_TOALL = 13;
  PLO_PLAYERWARP = 14;
  PLO_WARPFAILED = 15;
  PLO_DISCMESSAGE = 16;
  PLO_ARROWADD = 19;
  PLO_ITEMADD = 22;
  PLO_ITEMDEL = 23;
  PLO_NPCMOVED = 24;
  PLO_SIGNATURE = 25;
  PLO_FLAGSET = 28;
  PLO_NPCDEL = 29;
  PLO_FILESENDFAILED = 30;
  PLO_FLAGDEL = 31;
  PLO_SHOWIMGPLAYER = 32;
  PLO_NPCWEAPONADD = 33;
  PLO_NPCWEAPONDEL = 34;
  PLO_EXPLOSION = 36;
  PLO_PRIVATEMESSAGE = 37;
  PLO_PUSHAWAY = 38;
  PLO_LEVELMODTIME = 39;
  PLO_HURTPLAYER = 40;
  PLO_STARTMESSAGE = 41;
  PLO_NEWWORLDTIME = 42;
  PLO_DEFAULTWEAPON = 43;
  PLO_HASNPCSERVER = 44;
  PLO_FILEUPTODATE = 45;
  PLO_HITOBJECTS = 46;
  PLO_STAFFGUILDS = 47;
  PLO_TRIGGERACTION = 48;
  PLO_PLAYERWARP2 = 49;
  PLO_LARGEFILESTART = 68;
  PLO_LARGEFILEEND = 69;
  PLO_PROFILE = 75;
  PLO_RAWDATA = 100;
  PLO_BOARDPACKET = 101;
  PLO_FILE = 102;
  PLO_NPCDEL2 = 150;
  PLO_HIDENPCS = 151;
  PLO_SAY2 = 153;
  PLO_FREEZEPLAYER2 = 154;
  PLO_UNFREEZEPLAYER = 155;
  PLO_SETACTIVELEVEL = 156;
  PLO_MOVE = 165;
  PLO_SHOWIMGNPC = 166;
  PLO_ONLINEMODE = 168;  { was PLO_UNKNOWN168 }
  PLO_UPGRADEURL = 169;
  PLO_GHOSTMODE = 170;
  PLO_BIGMAP = 171;
  PLO_MINIMAP = 172;
  PLO_GHOSTTEXT = 173;
  PLO_GHOSTICON = 174;
  PLO_SHOOT = 175;
  PLO_KINGDOMSMODE = 176;
  PLO_NEWWORLDMODE = 177;
  PLO_SERVERWARP = 178;
  PLO_RPGWINDOW = 179;
  PLO_STATUSLIST = 180;
  PLO_PLAYERNOUDP = 181;  { was PLO_UNKNOWN181 }
  PLO_LISTPROCESSES = 182;
  PLO_HASPROCESSRUNNING = 183;
  PLO_TAKESCREENSHOT = 184;
  PLO_BOARDHEIGHTS = 185;
  PLO_BOARDMODIFY2 = 186;

  { player props (2.1+ forms; 4.04r2 parses its own stream up to 74 and
    other players' up to 76, as 2.22) }
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
  PLPROP_GANI = 10;
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
  PLPROP_OSTYPE = 75;
  PLPROP_TEXTCODEPAGE = 76;
  PLPROP_UNKNOWN77 = 77;
  PLPROP_X2 = 78;
  PLPROP_Y2 = 79;
  PLPROP_Z2 = 80;

  { OSTYPE and the code page in the first props: not in the 4.04r2 notes;
    2.22's Windows values are assumed. }
  OsType = 'wind';
  TextCodePage = 1252;

  { PLI_SHOWIMG (24) = GCHAR 9 every 5.14 to 5.15 s, alone in the level
    too (live-behaviour-404.md, third run). }
  ShowImgEveryMs = 5145;

function PLOName(Id: Integer): string;
{ True for the 98 server ids 4.04r2's receive switch has a case for. }
function PLOKnown(Id: Integer): Boolean;

implementation

uses
  SysUtils;

function PLOKnown(Id: Integer): Boolean;
begin
  { 4.04-4.20.toml: 4.20r8's set without 107, 108 and 196 }
  case Id of
    0..25, 27..43, 45..49, 67..69, 74, 75, 82, 84, 100..102, 104..106, 131..134,
    150, 151, 153..156, 165, 166, 168..176, 178..187, 189..191, 193..195:
      Result := True;
  else
    Result := False;
  end;
end;

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
    PLO_SHOWIMGPLAYER: Result := 'SHOWIMGPLAYER';
    PLO_NPCWEAPONADD: Result := 'NPCWEAPONADD';
    PLO_NPCWEAPONDEL: Result := 'NPCWEAPONDEL';
    PLO_PRIVATEMESSAGE: Result := 'PRIVATEMESSAGE';
    PLO_LEVELMODTIME: Result := 'LEVELMODTIME';
    PLO_STARTMESSAGE: Result := 'STARTMESSAGE';
    PLO_NEWWORLDTIME: Result := 'NEWWORLDTIME';
    PLO_DEFAULTWEAPON: Result := 'DEFAULTWEAPON';
    PLO_HASNPCSERVER: Result := 'HASNPCSERVER';
    PLO_FILEUPTODATE: Result := 'FILEUPTODATE';
    PLO_STAFFGUILDS: Result := 'STAFFGUILDS';
    PLO_PLAYERWARP2: Result := 'PLAYERWARP2';
    PLO_PROFILE: Result := 'PROFILE';
    PLO_RAWDATA: Result := 'RAWDATA';
    PLO_BOARDPACKET: Result := 'BOARDPACKET';
    PLO_FILE: Result := 'FILE';
    PLO_SAY2: Result := 'SAY2';
    PLO_SETACTIVELEVEL: Result := 'SETACTIVELEVEL';
    PLO_ONLINEMODE: Result := 'UNKNOWN168';
    PLO_GHOSTICON: Result := 'GHOSTICON';
    PLO_RPGWINDOW: Result := 'RPGWINDOW';
    PLO_STATUSLIST: Result := 'STATUSLIST';
    PLO_SERVERWARP: Result := 'SERVERWARP';
    PLO_BOARDMODIFY2: Result := 'BOARDMODIFY2';
  else
    Result := 'PLO_' + IntToStr(Id);
  end;
end;

end.
