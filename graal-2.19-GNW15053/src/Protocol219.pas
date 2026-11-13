{ Protocol219: message ids and constants of the 2.17.1 client (GNW22122).

  Names follow gs2lib (graal_analysis protocol/packet-ids.md). Only the ids
  2.17.1 sends or handles are listed; its receive jump table has 79 entries
  plus a shared silent default (dispatcher bound 0xB9 = id 185)
  (protocol/client-versions.md, version-profiles/plo-handled-ids-by-build.tsv). }
unit Protocol219;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { the listserver used when neither listserver.txt nor arrays2.dat names
    one: the community listserver's legacy port. 2.17.1's list login is
    the classic plain frame, which 14923 answers and 14922 (the
    supported-clients port) does not
    (protocol/public-listserver-2026-10-25.md) }
  DefaultListHost = 'listserver.graal.in';
  DefaultListPort = 14923;

  { The 8-byte version token in the login line. }
    { INFERRED BUILD. No binary of 2.19 is held; the token is gs2lib's
    (CLVER_2_19). Everything else is the 2.17.1 rebuild's, the nearest real
    build. See the folder's README. }
  ClientVersionToken = 'GNW15053';
  ClientBuildLabel = '2.19';
  { Where the build finds its files under graal-assets: 2.17.1 shipped in
    the same folder as 2.22, so it falls back to graal-assets/2.22/. }
  ClientAssetFolders = '2.19;2.17.1;2.22';
  { PLI_TAMPERCHECK, sent once right after PLI_LANGUAGE: 10 raw bytes, two
    chained CRC-32 words over the original exe's memory image, constant for
    the build (version-profiles/tampercheck-values.tsv). }
  TamperCheck219 = #$2a#$7b#$ad#$19#$5e#$23#$12#$43#$d8#$2c;
  { 2.19 to 2.21 log in as client type 4 (gs2lib PLTYPE_CLIENT2), the
    only type-4 game clients besides 3.0 and 3.01; the server then uses the
    gen-4 codec (graal_analysis protocol/codec-and-framing.md). The gen-4
    link here is INVENTED (made up to work, not observed): no 2.19 to 2.21
    binary is held and no type-4 login was captured. }
  ClientType = 4;
  { gen 4: every frame after the login is bzip2'd, then its first 4 dword
    groups are XORed with the gen-5 LCG; each direction has its own
    iterator, seeded as gen 3, with the login key }
  Gen4Groups = 4;

  { gen-3 insertion cipher }
  Gen3Seed: Cardinal = $04A80B38;
  Gen3Mul: Cardinal = $08088405;

  OutFlushAt = $1000;   { the out buffer is compressed and sent at 4 KB }
  OutDropAt = $40000;   { more than 256 KB queued drops the link }
  { Receive limits. These are the rebuild's, not 2.17's: they keep a hostile
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
  PLI_TAMPERCHECK = 39;
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
  PLO_PLAYERWARP2 = 49;
  PLO_LARGEFILESTART = 68;
  PLO_LARGEFILEEND = 69;
  PLO_PROFILE = 75;
  PLO_RAWDATA = 100;
  PLO_BOARDPACKET = 101;
  PLO_FILE = 102;
  PLO_SAY2 = 153;
  PLO_SETACTIVELEVEL = 156;
  PLO_ONLINEMODE = 168;  { was PLO_UNKNOWN168 }
  { 169..185 are all handled by 2.17.1; the rebuild accepts them and leaves
    their effects (ghost mode, server-sent maps, serverwarp, RPG window,
    status list, process list, screenshots, level heights) to later stages }
  PLO_UPGRADEURL = 169;
  PLO_BOARDHEIGHTS = 185;

  { player props (2.1+ forms: 10 is the GANI string, not the bow) }
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

function PLOName(Id: Integer): string;
{ True for the ids 2.17.1's receive switch has a case for }
function PLOKnown219(Id: Integer): Boolean;

implementation

uses
  SysUtils;

function PLOKnown219(Id: Integer): Boolean;
begin
  { the ids listed above, with 169 to 185 all handled }
  case Id of
    0..16, 19, 22, 23, 25, 28, 30, 33, 34, 36, 37, 39..45, 47, 49, 68, 69,
    75, 100..102, 153, 156, 168..185:
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
    PLO_PLAYERWARP2: Result := 'PLAYERWARP2';
    PLO_LARGEFILESTART: Result := 'LARGEFILESTART';
    PLO_LARGEFILEEND: Result := 'LARGEFILEEND';
    PLO_PROFILE: Result := 'PROFILE';
    PLO_RAWDATA: Result := 'RAWDATA';
    PLO_BOARDPACKET: Result := 'BOARDPACKET';
    PLO_FILE: Result := 'FILE';
    PLO_SAY2: Result := 'SAY2';
    PLO_SETACTIVELEVEL: Result := 'SETACTIVELEVEL';
    PLO_ONLINEMODE: Result := 'UNKNOWN168';
  else
    Result := 'PLO_' + IntToStr(Id);
  end;
end;

end.
