{ Protocol121: message ids and constants of the 1.21 client (GSERV007).

  Names follow gs2lib (graal_analysis protocol/packet-ids.md). The ids and
  props are the ones the 2.05 rebuild knows, from which this build was
  made; graal_analysis version-profiles/1.33-1.39 lists what the gen-2
  builds send and handle. 0.0.1 keeps the wider receive set (a server sends
  this build nothing outside its own) and narrows only what is sent. }
unit Protocol121;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { 1.21 has no listserver: its connect dialog was pre-filled with a host
    and port. The rebuild pre-fills the community host instead, and
    graalconfig.txt (serveraddr=, serverport=) or listserver.txt next to
    the program replace it. }
  DefaultServerHost = 'listserver.graal.in';
  DefaultServerPort = 14923;

  { The 8-byte version token in the login line. }
  ClientVersionToken = 'GSERV007';
  ClientBuildLabel = '1.21';
  ClientBuildTitle = 'Graal 1.21';
  ClientType = 0; { PLTYPE_CLIENT }

  { Generation 2: zlib on every flush, no cipher, no key byte, and no
    language packet after the login line. }
  { PLI_ITEMTAKE (32) came with 1.38; before it the client deleted the item
    (PLI_ITEMDEL) and gave it to itself. }
  HasItemTake = False;

  OutFlushAt = $1000;   { the out buffer is compressed and sent at 4 KB }
  OutDropAt = $40000;   { more than 256 KB queued drops the link }
  { Receive limits. These are the rebuild's, not 2.05's: they keep a hostile
    server from growing the client without bound. }
  InFrameMax = 16 * 1024 * 1024;  { one inflated frame }
  InPendingMax = 4 * 1024 * 1024; { an unfinished message }
  TickMs = 50;          { the idle handler's frame gate }

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
  { the character list of the start dialog as the build's headsconfig.txt
    gives it (used when the install has none), and each one's head }
  CharacterNames: array[0..27] of string = (
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
    'Ninjii Knight',
    'Fire',
    'Dragoon',
    'Lunar',
    'Judge',
    'Vincent',
    'Silver',
    'Terra',
    'Squall');
  CharacterHeads: array[0..27] of string = (
    'head0.gif',
    'head1.gif',
    'head2.gif',
    'head3.gif',
    'head4.gif',
    'head5.gif',
    'head6.gif',
    'head7.gif',
    'head8.gif',
    'head9.gif',
    'head10.gif',
    'head11.gif',
    'head12.gif',
    'head13.gif',
    'head14.gif',
    'head15.gif',
    'head16.gif',
    'head17.gif',
    'head18.gif',
    'head19.gif',
    'head20.gif',
    'head23.gif',
    'head24.gif',
    'head25.gif',
    'head26.gif',
    'head27.gif',
    'head28.gif',
    'head29.gif');

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
