{ Protocol600b1: message ids and constants of the 6.00b1 Windows client
  (G3D03048).

  The original 6.00b1 for Windows (8 January 2010, one MoleBox-wrapped exe) is one native
  C++ program; this rebuild runs on Linux and Windows. Names follow gs2lib
  (graal_analysis protocol/packet-ids.md). Sources: protocol/v6x-clients.md
  and protocol/v5v6-lab-play.md (the lab ran the Windows 6.03r7; 6.00b1
  was never run, so where its behaviour is not read from the binary the
  6.03r7 run stands in). 6.00b1 speaks
  the gen-5 wire with its own token, no tamper check, no listserver and no
  licence file: it logs into a game server it calls Login, and plays only
  after that server sends a server warp (178). It handles 97 server ids;
  every other id is ignored silently. }
unit Protocol600b1;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { The 8-byte version token in the login line (v6x-clients.md, "Login
    message": G plus seven one-character strings, concatenated). }
  ClientVersionToken = 'G3D03048';
  ClientBuildLabel = '6.00b1';
  { Login type 5, gen-5 cipher on the server, as 2.22. }
  ClientType = 5;
  { After the password, the login line ends with an unprefixed comma list:
    the platform, then four machine fields (on the Windows 5.12 to 6.03r7
    builds: the MD5 hex of the product id, of the adapter MAC and of the
    C:\ volume serial, then the quoted Windows version;
    v5v6-windows-unpacked.md, "Login message"). The rebuild reads no machine
    values. It sends fixed made-up ones of the same shape: the MD5 hex of
    "SquirrelOS product id SQRL7-ACORN-OAK42-NUTS1", of "SquirrelNIC MAC
    AC:04:2D:5E:ED:01" and of "SquirrelBIOS C: volume serial ACE5-5EED",
    then the version Windows 8 and later report to a program with no
    manifest, which the lab's 5.12 sent. }
  LoginPlatform = 'win';
  LoginMachineFields = ',c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400,"6.2 9200 "';
  { The name it gives the first server it reaches. While the current
    server's name starts with "login" (any case) it draws no characters
    and no HUD. 5.24 drew the tiles there all the same, before any server
    warp (v5v6-lab-play.md, "Tiles in 5.31r4 and 6.03r7": 5.24 and 5.30r3
    draw them). }
  FirstServerName = 'Login';
  LoginTiles = True;
  { The built-in Login server port (compiled in, with three hosts). }
  LoginServerPort = 14900;
  { 6.00b1 has no listserver step. The rebuild's start screen still gets a
    list from a Seihai listserver with the 3.x list hello (id 7 + key +
    this + "newmain"), because it cannot show the Login server's scripted
    list; see ListServer600b1. }
  ListVersionToken = 'G3D30123';

  { 6.00b1 never sends PLI_TAMPERCHECK (39): no constant 39 in its send
    code (v6x-clients.md, "Client -> server ids"). }

  { A frame of 0xFFFF bytes or more goes as the length 0xFFFF, then the
    real length as 4 bytes big-endian (v6x-clients.md, "Cipher and
    framing"). }
  LongFrameMark = $FFFF;

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

  { The out buffer is sent at the end of each tick, or as soon as it
    would pass 0x1000 bytes (v6x-clients.md: "Buffers flush at 0x1000"). }
  OutFlushAt = $1000;
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
  PLI_TRIGGERACTION = 38;
  PLI_TAMPERCHECK = 39;
  PLI_PROCESSLIST = 44;
  PLI_UPDATEGANI = 157;

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
  PLO_SERVERLISTCONNECTED = 190;  { raises onServerListerConnect on the Login server; was PLO_UNKNOWN190 }
  PLO_RESETCLIENT = 194;  { was PLO_CLEARWEAPONS }
  PLO_GANISCRIPT = 195;
  PLO_FILEREDIRECT = 109;   { i5 time, two strings (probably a file redirect) }
  PLO_SERVEROPTIONS = 198;     { one i5, stored on the connection; was PLO_UNKNOWN198 }

  { player props (2.1+ forms). No 6.x prop parser was read: the sets are
    3.153's, plus X2 / Y2 / Z2 (78 to 80), which the lab saw 5.x and 6.x
    send. }
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
  PLPROP_X2 = 78;
  PLPROP_Y2 = 79;
  PLPROP_Z2 = 80;

  { What 6.00b1 says about itself in its first props: the lab saw the
    Windows builds send nickname, colours, language, win, then the position;
    the code
    page is the 3.04 lab value, assumed. }
  OsType = 'win';
  TextCodePage = 1250;

function PLOName(Id: Integer): string;
{ True for the 97 server ids 6.00b1's receive switch has a case for. }
function PLOKnown(Id: Integer): Boolean;

implementation

uses
  SysUtils;

function PLOKnown(Id: Integer): Boolean;
begin
  { v6x-clients.md, "Server -> client ids (6.01, 6.03)" }
  case Id of
    0..25, 27..40, 42, 43, 45..49, 67..69, 74, 82, 84, 101, 102, 104..107, 109,
    131, 134, 140, 150, 151, 153..156, 166, 168, 170, 172..174, 176,
    178..180, 182, 183, 185..187, 189..191, 194, 195, 197, 198:
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
    PLO_LISTPROCESSES: Result := 'LISTPROCESSES';
    PLO_SERVERLISTCONNECTED: Result := 'UNKNOWN190';
    PLO_RESETCLIENT: Result := 'RESETCLIENT';
    PLO_GANISCRIPT: Result := 'GANISCRIPT';
  else
    Result := 'PLO_' + IntToStr(Id);
  end;
end;

end.
