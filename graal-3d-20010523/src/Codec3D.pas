{ Codec3D: the Graal3D (February 2000) wire: frames, ids, the login line
  and the player property table.

  The text codec is the 2D one (GTypes): c(v) = v + 32, sN = N groups of
  7 bits, most significant first, str = c(len) + bytes. What Graal3D does
  differently is written here: no key byte and no scramble, its own packet
  ids, 3D positions, one-byte angles, 24-bit colours in four 6-bit groups,
  and the IPv4 prop. Source: graal_analysis graal3d/protocol.md. }
unit Codec3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GTypes;

const
  VersionString = 'GR3DV003';
  DefaultPort = 14901;
  DefaultUdpPort = 14898;
  MaxPlayers = 200;
  { the client sends in 256-byte slices and drops the link when more than
    256 KiB of compressed output is waiting }
  SendSlice = 256;
  MaxPending = 256 * 1024;
  FlushAt = 4096;
  MaxInflate = 256000;
  LineBreak = #$A7; { a \n inside a message is written as this byte }

  { server -> client }
  SV_LEVEL = 0;
  SV_LEVELNAME = 1;
  SV_OTHERPLPROPS = 2;
  SV_PLAYERPROPS = 3;
  SV_LEADER = 4;
  SV_DISCMESSAGE = 5;
  SV_SESSION = 6;
  SV_FILESENDFAILED = 7;
  SV_ADMINMESSAGE = 8;
  SV_RAWDATA = 100;
  SV_FILE = 101;

  { client -> server }
  CL_LOGIN = 0;
  CL_ADMINLOGIN = 1;
  CL_PROPS = 1;
  CL_WANTFILE = 2;

  { player props }
  PP_ID = 0;
  PP_X = 1;
  PP_Y = 2;
  PP_Z = 3;
  PP_ANGLE = 4;
  PP_ANIM = 5;
  PP_BODYX = 6;
  PP_HEADX = 7;
  PP_BODYTEX = 8;
  PP_HEADTEX = 9;
  PP_ARMCOLOR = 10;
  PP_SHOECOLOR = 11;
  PP_NICK = 12;
  PP_CHAT = 13;
  PP_LEVEL = 14;
  PP_UDPPORT = 15;
  PP_IP = 16;
  PP_HANDCOLOR = 17;
  PP_INLEVEL = 50;
  PP_LEFT = 51;
  PropCount = 18; { 0..17 }

  { UDP datagram kinds }
  UDP_POS = 0;
  UDP_CHAT = 1;

type
  { One player's props as the client holds them. Positions are world units. }
  TProps3D = record
    Id: Integer;
    X, Y, Z: Double;
    Angle: Integer;      { degrees, 0..358, even }
    Anim: Integer;
    BodyX, HeadX, BodyTex, HeadTex: string;
    ArmColor, ShoeColor, HandColor: Cardinal; { $RRGGBB }
    Nick, Chat, Level: string;
    UdpPort: Integer;
    Ip: Cardinal;        { in_addr word as a little-endian integer }
    InLevel: Boolean;
    Left: Boolean;
  end;

procedure DefaultProps(out P: TProps3D);

{ Wire forms of single values. }
function EncodeCoord(V: Double): string;      { s2: v * 2 + 8000 }
function DecodeCoord(R: TGReader): Double;
function EncodeColor(C: Cardinal): string;    { 4 x 6 bits }
function DecodeColor(R: TGReader): Cardinal;
function EncodeAngle(Degrees: Integer): Char; { c(degrees / 2) }

{ One prop as c(id) + value. }
function EncodeProp(const P: TProps3D; Id: Integer): string;
{ Applies a run of props; returns the ids seen (as a set of bits). }
function ApplyProps(var P: TProps3D; const Data: string): Cardinal;
{ The values of props 1..5 back to back with no ids (the UDP position
  body, 9 bytes). }
function EncodePosBody(const P: TProps3D): string;
function ApplyPosBody(var P: TProps3D; const Data: string): Boolean;

{ The first line: c(0) GR3DV003 str(account) str(password). }
function LoginLine(const Account, Password: string): string;
{ c(id) + payload + \n; a \n inside the payload becomes the 0xA7 byte. }
function MessageLine(Id: Integer; const Payload: string): string;
{ A frame: u16 big-endian length, then a zlib block of whole lines. }
function BuildFrame(const Lines: string): string;
{ Takes whole frames off the front of Buf and returns their lines, inflated
  and joined. Returns False on a bad frame. }
function TakeFrames(var Buf: string; out Lines: string): Boolean;
{ \n -> 0xA7 and back. }
function ToWire(const S: string): string;
function FromWire(const S: string): string;

{ An in_addr word (as read from memory, little-endian) for a dotted IPv4. }
function IpWord(const Dotted: string): Cardinal;
function IpDotted(W: Cardinal): string;

implementation

uses
  SysUtils, GZlib;

procedure DefaultProps(out P: TProps3D);
begin
  P.Id := 0;
  P.X := 0;
  P.Y := 0;
  P.Z := 0;
  P.Angle := 0;
  P.Anim := 0;
  P.BodyX := 'body.x';
  P.HeadX := 'head.x';
  P.BodyTex := 'body.bmp';
  P.HeadTex := 'man.bmp';
  P.ArmColor := $FF0000;
  P.ShoeColor := $800000;
  P.HandColor := $FDCC47;
  P.Nick := '';
  P.Chat := '';
  P.Level := 'level1.x';
  P.UdpPort := 0;
  P.Ip := 0;
  P.InLevel := False;
  P.Left := False;
end;

function EncodeCoord(V: Double): string;
var
  I: Integer;
begin
  I := Round(V * 2 + 8000);
  Result := GShort(I);
end;

function DecodeCoord(R: TGReader): Double;
begin
  Result := (R.ReadGShort - 8000) / 2;
end;

function EncodeColor(C: Cardinal): string;
begin
  Result := Chr(((C shr 18) and $3F) + $20) + Chr(((C shr 12) and $3F) + $20) +
    Chr(((C shr 6) and $3F) + $20) + Chr((C and $3F) + $20);
end;

function DecodeColor(R: TGReader): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to 4 do
    Result := (Result shl 6) or Cardinal(R.ReadGChar and $3F);
end;

function EncodeAngle(Degrees: Integer): Char;
begin
  Degrees := Degrees mod 360;
  if Degrees < 0 then Inc(Degrees, 360);
  Result := GChar(Degrees div 2);
end;

function EncodeProp(const P: TProps3D; Id: Integer): string;
begin
  Result := GChar(Id);
  case Id of
    PP_ID: Result := Result + GChar(P.Id);
    PP_X: Result := Result + EncodeCoord(P.X);
    PP_Y: Result := Result + EncodeCoord(P.Y);
    PP_Z: Result := Result + EncodeCoord(P.Z);
    PP_ANGLE: Result := Result + EncodeAngle(P.Angle);
    PP_ANIM: Result := Result + GShort(P.Anim);
    PP_BODYX: Result := Result + GString(P.BodyX);
    PP_HEADX: Result := Result + GString(P.HeadX);
    PP_BODYTEX: Result := Result + GString(P.BodyTex);
    PP_HEADTEX: Result := Result + GString(P.HeadTex);
    PP_ARMCOLOR: Result := Result + EncodeColor(P.ArmColor);
    PP_SHOECOLOR: Result := Result + EncodeColor(P.ShoeColor);
    PP_NICK: Result := Result + GString(Copy(P.Nick, 1, 200));
    PP_CHAT: Result := Result + GString(Copy(P.Chat, 1, 200));
    PP_LEVEL: Result := Result + GString(P.Level);
    PP_UDPPORT: Result := Result + GInt3(P.UdpPort);
    PP_IP: Result := Result + GInt5(P.Ip);
    PP_HANDCOLOR: Result := Result + EncodeColor(P.HandColor);
    PP_INLEVEL: Result := Result + GChar(Ord(P.InLevel));
    PP_LEFT: ;
  else
    Result := '';
  end;
end;

function ApplyProps(var P: TProps3D; const Data: string): Cardinal;
var
  R: TGReader;
  Id: Integer;
begin
  Result := 0;
  R := TGReader.Create(Data);
  try
    while not R.Eof do
    begin
      Id := R.ReadGChar;
      case Id of
        PP_ID: P.Id := R.ReadGChar;
        PP_X: P.X := DecodeCoord(R);
        PP_Y: P.Y := DecodeCoord(R);
        PP_Z: P.Z := DecodeCoord(R);
        PP_ANGLE: P.Angle := R.ReadGChar * 2;
        PP_ANIM: P.Anim := R.ReadGShort;
        PP_BODYX: P.BodyX := R.ReadGString;
        PP_HEADX: P.HeadX := R.ReadGString;
        PP_BODYTEX: P.BodyTex := R.ReadGString;
        PP_HEADTEX: P.HeadTex := R.ReadGString;
        PP_ARMCOLOR: P.ArmColor := DecodeColor(R);
        PP_SHOECOLOR: P.ShoeColor := DecodeColor(R);
        PP_NICK: P.Nick := R.ReadGString;
        PP_CHAT: P.Chat := R.ReadGString;
        PP_LEVEL: P.Level := R.ReadGString;
        PP_UDPPORT: P.UdpPort := R.ReadGInt3;
        PP_IP: P.Ip := R.ReadGInt5;
        PP_HANDCOLOR: P.HandColor := DecodeColor(R);
        PP_INLEVEL: P.InLevel := R.ReadGChar <> 0;
        PP_LEFT: P.Left := True;
      else
        Break; { an unknown id: the length of what follows is not known }
      end;
      if R.Overrun then Break;
      if Id < 32 then Result := Result or (Cardinal(1) shl Id);
    end;
  finally
    R.Free;
  end;
end;

function EncodePosBody(const P: TProps3D): string;
begin
  Result := EncodeCoord(P.X) + EncodeCoord(P.Y) + EncodeCoord(P.Z) +
    EncodeAngle(P.Angle) + GShort(P.Anim);
end;

function ApplyPosBody(var P: TProps3D; const Data: string): Boolean;
var
  R: TGReader;
begin
  { 8 bytes or fewer are ignored }
  Result := Length(Data) > 8;
  if not Result then Exit;
  R := TGReader.Create(Data);
  try
    P.X := DecodeCoord(R);
    P.Y := DecodeCoord(R);
    P.Z := DecodeCoord(R);
    P.Angle := R.ReadGChar * 2;
    P.Anim := R.ReadGShort;
  finally
    R.Free;
  end;
end;

function LoginLine(const Account, Password: string): string;
begin
  Result := MessageLine(CL_LOGIN, VersionString + GString(Account) + GString(Password));
end;

function ToWire(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, LineBreak, [rfReplaceAll]);
end;

function FromWire(const S: string): string;
begin
  Result := StringReplace(S, LineBreak, #10, [rfReplaceAll]);
end;

function MessageLine(Id: Integer; const Payload: string): string;
begin
  Result := GChar(Id) + ToWire(Payload) + #10;
end;

function BuildFrame(const Lines: string): string;
var
  Z: string;
begin
  Z := ZCompress(Lines);
  Result := Chr((Length(Z) shr 8) and $FF) + Chr(Length(Z) and $FF) + Z;
end;

function TakeFrames(var Buf: string; out Lines: string): Boolean;
var
  N: Integer;
  Plain: string;
begin
  Result := True;
  Lines := '';
  while Length(Buf) >= 2 do
  begin
    N := (Ord(Buf[1]) shl 8) or Ord(Buf[2]);
    if Length(Buf) < N + 2 then Break;
    if (N = 0) or not ZDecompress(Copy(Buf, 3, N), Plain) or
      (Length(Plain) > MaxInflate) then
    begin
      Result := False;
      Buf := '';
      Exit;
    end;
    Delete(Buf, 1, N + 2);
    Lines := Lines + Plain;
  end;
end;

function IpWord(const Dotted: string): Cardinal;
var
  Rest, Part: string;
  I, P, V: Integer;
begin
  Result := 0;
  Rest := Dotted;
  for I := 0 to 3 do
  begin
    P := Pos('.', Rest);
    if P = 0 then P := Length(Rest) + 1;
    Part := Copy(Rest, 1, P - 1);
    Delete(Rest, 1, P);
    V := StrToIntDef(Part, -1);
    if (V < 0) or (V > 255) then
    begin
      Result := 0;
      Exit;
    end;
    { byte I of the in_addr in memory is the I-th number }
    Result := Result or (Cardinal(V) shl (8 * I));
  end;
end;

function IpDotted(W: Cardinal): string;
begin
  Result := IntToStr(W and $FF) + '.' + IntToStr((W shr 8) and $FF) + '.' +
    IntToStr((W shr 16) and $FF) + '.' + IntToStr((W shr 24) and $FF);
end;

end.
