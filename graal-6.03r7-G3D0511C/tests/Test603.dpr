{ Tests for the 6.03r7 Linux rebuild. No framework: each check prints a
  line and the run exits 1 if any failed.

  6.03r7 keeps the gen-5 wire, so the gen-5 codec checks run against frames
  of a real 2.22 session (Capture603.inc, the 2.22 capture); the login
  follows graal_analysis protocol/v6x-clients.md, and the Login mode and
  server warp checks the 6.03r7 lab run (protocol/v5v6-lab-play.md).
  Optional: GRAAL603_DATA = a 6.03r7 install, so the fuzzer also draws the
  fuzzed players with real heads, bodies and ganis. }
program Test603;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GTypes in '../../common/GTypes.pas',
  GZlib in '../../common/GZlib.pas',
  GBzip2 in '../../common/GBzip2.pas',
  GSocket in '../../common/GSocket.pas',
  GLevel in '../../common/GLevel.pas',
  GSurface in '../../common/GSurface.pas',
  GArrays in '../../common/GArrays.pas',
  GAni in '../../common/GAni.pas',
  Protocol603 in '../src/Protocol603.pas',
  GraalClient in '../src/GraalClient.pas',
  Adventure in '../src/Adventure.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  ListServer603 in '../src/ListServer603.pas';

{$I Capture603.inc}

type
  { reaches the codec hooks }
  TClientAccess = class(TAdventureClient);

var
  Passed, Failed, Skipped: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

function Unhex(const H: string): string;
var
  I: Integer;
begin
  SetLength(Result, Length(H) div 2);
  for I := 1 to Length(H) div 2 do
    Result[I] := Chr(StrToInt('$' + Copy(H, 2 * I - 1, 2)));
end;

{ Messages of a plain body, split on LF. }
procedure SplitLines(const Plain: string; L: TStrings);
var
  P, E: Integer;
begin
  L.Clear;
  P := 1;
  while P <= Length(Plain) do
  begin
    E := P;
    while (E <= Length(Plain)) and (Plain[E] <> #10) do Inc(E);
    L.Add(Copy(Plain, P, E - P));
    P := E + 1;
  end;
end;

{ A client frame as the server reads it: u16be, compression byte, XOR. }
function ServerReadFrame(Codec: TGen5; const Wire: string; out Plain: string): Boolean;
var
  Len, CType: Integer;
  B: string;
begin
  Plain := '';
  Result := False;
  if Length(Wire) < 3 then Exit;
  Len := (Ord(Wire[1]) shl 8) or Ord(Wire[2]);
  if Length(Wire) <> Len + 2 then Exit;
  CType := Ord(Wire[3]);
  B := Copy(Wire, 4, MaxInt);
  Codec.Apply(B, CType);
  case CType of
    2: begin Plain := B; Result := True; end;
    4: Result := ZDecompress(B, Plain);
    6: Result := BZ2Decompress(B, Plain, 1 shl 24);
  end;
end;

{ All frames in a sink's output, decoded in order. }
function ServerReadAll(Codec: TGen5; const Wire: string; Msgs: TStrings): Boolean;
var
  P, Len: Integer;
  Plain: string;
  L: TStringList;
begin
  Result := True;
  Msgs.Clear;
  L := TStringList.Create;
  try
    P := 1;
    while P + 1 <= Length(Wire) do
    begin
      Len := (Ord(Wire[P]) shl 8) or Ord(Wire[P + 1]);
      if not ServerReadFrame(Codec, Copy(Wire, P, Len + 2), Plain) then
      begin
        Result := False;
        Exit;
      end;
      SplitLines(Plain, L);
      Msgs.AddStrings(L);
      Inc(P, Len + 2);
    end;
  finally
    L.Free;
  end;
end;

{ A server frame for a gen-5 client. }
function ServerFrame(Codec: TGen5; const Plain: string): string;
var
  B: string;
  CType: Integer;
begin
  B := PackBody(Plain, CType);
  Codec.Apply(B, CType);
  B := Chr(CType) + B;
  Result := Chr(Length(B) shr 8) + Chr(Length(B) and $FF) + B;
end;

function MsgId(const M: string): Integer;
begin
  if M = '' then Result := -1 else Result := Ord(M[1]) - 32;
end;

procedure TestGTypes;
var
  R: TGReader;
  S: string;
begin
  Check(GChar(5) = '%', 'GCHAR 5 (login type of 2.22) is %');
  Check(GChar(39) = 'G', 'GCHAR 39 (PLI_TAMPERCHECK) is G');
  S := GShort(28671) + GInt3(3670015) + GInt5($DEADBEEF) + GString('walk');
  R := TGReader.Create(S);
  try
    Check(R.ReadGShort = 28671, 'GSHORT max round trip');
    Check(R.ReadGInt3 = 3670015, 'GINT3 max round trip');
    Check(R.ReadGInt5 = $DEADBEEF, 'GINT5 32-bit round trip');
    Check(R.ReadGString = 'walk', 'GSTRING round trip');
    Check(R.Eof and not R.Overrun, 'reader ends cleanly');
  finally
    R.Free;
  end;
end;

procedure TestBzip2;
var
  S, Z, P: string;
  I, J: Integer;
  AllOk: Boolean;
begin
  Check(BZ2Crc('123456789') = $FC891918, 'bzip2 CRC check value');
  AllOk := True;
  RandSeed := 22;
  for I := 0 to 40 do
  begin
    case I mod 5 of
      0: S := StringOfChar(Chr(I), I * 300);
      1: begin S := ''; while Length(S) < I * 200 do S := S + 'abc' + Chr(Random(4) + 65); end;
      2: begin SetLength(S, I * 150); if S <> '' then FillChar(S[1], Length(S), 0);
           if Length(S) > 10 then S[10] := 'x'; end;
      3: begin
           SetLength(S, I * 97);
           for J := 1 to Length(S) do S[J] := Chr(Random(256));
         end;
    else
      S := Copy(StringOfChar(#$FF, 300) + #$07, 1, I * 7);
    end;
    Z := BZ2Compress(S);
    if not BZ2Decompress(Z, P, 1 shl 24) or (P <> S) then AllOk := False;
  end;
  Check(AllOk, 'bzip2: 41 buffers (runs, text, zeros, random) round trip');
  { the same round trip at a frame-sized buffer of random bytes }
  SetLength(S, 70000);
  for I := 1 to Length(S) do S[I] := Chr(Random(256));
  Check(BZ2Decompress(BZ2Compress(S), P, 1 shl 24) and (P = S),
    'bzip2: 70000 random bytes round trip');
  Check(not BZ2Decompress('BZh9 not bzip2 at all', P, 1000), 'bzip2: garbage is rejected');
  Z := BZ2Compress(StringOfChar('a', 5000));
  Check(not BZ2Decompress(Z, P, 4999), 'bzip2: output past the cap is rejected');
  Z[Length(Z) - 2] := Chr(Ord(Z[Length(Z) - 2]) xor 1);
  Check(not BZ2Decompress(Z, P, 1 shl 24), 'bzip2: a wrong stream CRC is rejected');
end;

{ The real 2.22 frames: the decoder reads both directions, and the encoder
  makes the client's uncompressed frames byte for byte. }
procedure TestGen5Capture;
var
  Dec, Enc: TGen5;
  I, CType, Raw, Same, NPacked: Integer;
  Wire, Body, Plain, B, Mine: string;
  C: TClientAccess;
  AllPlain, CrcOk: Boolean;
begin
  Dec := TGen5.Create(CaptureKey);
  Enc := TGen5.Create(CaptureKey);
  try
    AllPlain := True;
    Raw := 0;
    Same := 0;
    NPacked := 0;
    for I := 0 to High(CaptureCS) do
    begin
      Wire := Unhex(CaptureCS[I]);
      Wire := Chr(Length(Wire) shr 8) + Chr(Length(Wire) and $FF) + Wire;
      if not ServerReadFrame(Dec, Wire, Plain) or (Plain <> Unhex(CapturePlainCS[I])) then
        AllPlain := False;
      { encode the same plain body again }
      B := PackBody(Unhex(CapturePlainCS[I]), CType);
      Enc.Apply(B, CType);
      Mine := Chr(CType) + B;
      Body := Unhex(CaptureCS[I]);
      if Ord(Body[1]) = CompressNone then
      begin
        Inc(Raw);
        if Mine = Body then Inc(Same);
      end
      else if (CType = Ord(Body[1])) then
        Inc(NPacked);
    end;
    Check(AllPlain, Format('gen 5: %d real client frames decode (XOR + zlib)',
      [Length(CaptureCS)]));
    Check((Raw > 0) and (Same = Raw), Format(
      'gen 5: %d of %d uncompressed client frames re-encoded byte for byte', [Same, Raw]));
    Check(NPacked = Length(CaptureCS) - Raw,
      'gen 5: the compression byte picked matches the client''s for every frame');
    Check(Dec.Iterator = Enc.Iterator, 'gen 5: encoder and decoder iterators stay in step');
  finally
    Dec.Free;
    Enc.Free;
  end;
  { the server's frames through the client's own receive path }
  C := TClientAccess.Create;
  try
    C.StartOffline(CaptureKey);
    CrcOk := True;
    for I := 0 to High(CaptureSC) do
      if not C.DecodeFrame(Unhex(CaptureSC[I]), Plain) or
        (Length(Plain) <> CapturePlainSCLen[I]) or (BZ2Crc(Plain) <> CapturePlainSCCrc[I]) then
        CrcOk := False;
    Check(CrcOk, 'gen 5: the server''s first 8 frames decode (zlib, bz2 and raw)');
    Check(Ord(Unhex(CaptureSC[3])[1]) = CompressBz2, 'gen 5: the capture has a bz2 frame');
  finally
    C.Free;
  end;
end;

{ The login as 6.03r7 sends it: the login line alone in the plain zlib
  frame, ending with linux and four machine fields, then 37 in its own
  gen-5 frame; no tamper check. }
procedure TestLogin;
var
  C: TAdventureClient;
  Codec: TGen5;
  Msgs: TStringList;
  Wire, Plain: string;
  Len: Integer;
begin
  C := TAdventureClient.Create;
  Codec := TGen5.Create(CaptureKey);
  Msgs := TStringList.Create;
  try
    C.StartOffline(CaptureKey);
    C.Sink := True;
    C.SendLogin('acc', 'pw', 'English');
    C.Flush;
    Wire := C.Sent;
    Len := (Ord(Wire[1]) shl 8) or Ord(Wire[2]);
    Check(ZDecompress(Copy(Wire, 3, Len), Plain) and
      (Plain = '%' + Chr(CaptureKey + 32) + 'G3D0511C' + GString('acc') + GString('pw') +
        'linux,"","","",""' + #10),
      'login: 5 (key, G3D0511C, account, password, linux and four machine fields) alone in the plain zlib frame');
    Check(ServerReadAll(Codec, Copy(Wire, Len + 3, MaxInt), Msgs) and
      (Msgs.Count = 1) and (Msgs[0] = GChar(PLI_LANGUAGE) + 'English'),
      'login: 37 English in its own gen-5 frame, and no tamper check');
    Check(LoginTail = 'linux,"","","",""', 'login: the tail is linux and four empty quoted fields');
    C.Sent := '';
    C.StartOffline(CaptureKey);
    C.SendLogin('acc', StringOfChar('p', 300), 'English');
    Wire := C.Sent;
    Len := (Ord(Wire[1]) shl 8) or Ord(Wire[2]);
    Check(ZDecompress(Copy(Wire, 3, Len), Plain) and
      (Pos(#255 + StringOfChar('p', 223) + 'linux,', Plain) > 0),
      'login: a long password goes as 0xFF and its first 0xDF bytes');
  finally
    Msgs.Free;
    Codec.Free;
    C.Free;
  end;
end;

{ The rebuild's list step (6.03r7 has none): id 7 with the key, G3D30123
  and newmain and id 1 in one plain zlib frame; the list, status and urls
  back in gen 5. }
procedure TestListServer;
var
  C: TListServerClient;
  Codec, SCodec: TGen5;
  Wire, Plain, List: string;
  Len: Integer;
begin
  C := TListServerClient.Create;
  Codec := TGen5.Create(CaptureKey);
  SCodec := TGen5.Create(CaptureKey);
  try
    C.StartOffline(CaptureKey);
    C.Sink := True;
    C.SendRequest('acc', 'pw');
    Wire := C.Sent;
    Len := (Ord(Wire[1]) shl 8) or Ord(Wire[2]);
    Check(ZDecompress(Copy(Wire, 3, Len), Plain) and
      (Plain = GChar(7) + GChar(CaptureKey) + 'G3D30123newmain' + #10 +
        GChar(1) + GString('acc') + GString('pw') + #10) and
      (Length(Wire) = Len + 2),
      'list: id 7 (key, G3D30123, newmain) and id 1 (account, password) in one plain zlib frame');
    List := GChar(2) +
      GChar(8) + GString('P Classic') + GString('English') + GString('A server') +
        GString('http://x') + GString('2.22') + GString('12') +
        GString('127.0.0.1') + GString('14802') +
      GChar(8) + GString('Plain') + GString('') + GString('') + GString('') +
        GString('') + GString('0') + GString('10.0.0.1') + GString('14900');
    C.FeedRaw(ServerFrame(SCodec, GChar(0) + List + #10 + GChar(2) +
      'Line one'#13'Line two' + #10 + GChar(3) + 'http://site' + #10 +
      GChar(5) + 'http://up' + #10));
    Check(C.GotList and (Length(C.Servers) = 2), 'list: two servers read');
    if Length(C.Servers) = 2 then
    begin
      Check((C.Servers[0].Name = 'P Classic') and
        (ServerDisplayName(C.Servers[0].Name) = 'Classic') and
        (C.Servers[0].Players = '12') and (C.Servers[0].Host = '127.0.0.1') and
        (C.Servers[0].Port = 14802), 'list: type prefix, name, players, ip, port');
      Check((ServerDisplayName(C.Servers[1].Name) = 'Plain') and
        (C.Servers[1].Port = 14900), 'list: a silver server has no prefix');
    end;
    Check((C.Status = 'Line one'#10'Line two') and (C.SiteUrl = 'http://site') and
      (C.UpgradeUrl = 'http://up'), 'list: status, site and upgrade lines');
    Check((DefaultListHost = 'listserver.graal.in') and (DefaultListPort = 14922),
      'list: listserver.graal.in on 14922 by default');
    Check(Length(ParseServerList(GChar(5) + GChar(8) + GString('x'))) = 0,
      'list: a cut-off list gives no half-read server');
  finally
    C.Free;
    Codec.Free;
    SCodec.Free;
  end;
end;

{ Reads and drops what the client sent, keeping the iterator in step. }
procedure Drain(G: TAdventure; Codec: TGen5);
var
  M: TStringList;
begin
  M := TStringList.Create;
  try
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, M);
    G.Client.Sent := '';
  finally
    M.Free;
  end;
end;

{ A TAdventure on a sink, logged in through the real server frames. }
function LoggedInGame(out Codec: TGen5): TAdventure;
var
  I, Len: Integer;
  Msgs: TStringList;
  SrvOut: TGen5;
begin
  Result := TAdventure.Create;
  Result.UseWallClock := False;
  Result.Client.StartOffline(CaptureKey);
  Result.Client.Sink := True;
  Result.Client.SendLogin('stubstub', 'pw', 'English');
  Result.Client.Flush;
  Codec := TGen5.Create(CaptureKey);
  { what the login sent: the login frame (no XOR) is skipped, the 37/39
    frame read, so the server-side iterator is in step }
  Len := (Ord(Result.Client.Sent[1]) shl 8) or Ord(Result.Client.Sent[2]);
  Msgs := TStringList.Create;
  try
    ServerReadAll(Codec, Copy(Result.Client.Sent, Len + 3, MaxInt), Msgs);
  finally
    Msgs.Free;
  end;
  Result.Client.Sent := '';
  SrvOut := TGen5.Create(CaptureKey);
  try
    for I := 0 to High(CaptureSC) do
      Result.Client.FeedRaw(Chr(Length(Unhex(CaptureSC[I])) shr 8) +
        Chr(Length(Unhex(CaptureSC[I])) and $FF) + Unhex(CaptureSC[I]));
  finally
    SrvOut.Free;
  end;
end;

procedure TestLoginBurst;
var
  G: TAdventure;
  Codec: TGen5;
  Msgs: TStringList;
  I, NUpd: Integer;
  Props: string;
begin
  G := LoggedInGame(Codec);
  Msgs := TStringList.Create;
  try
    Check(G.LoggedIn and G.BoardLoaded and (G.Level.Name = 'onlinestartlocal.nw'),
      'burst: the server''s login frames (2.22 capture, same wire) log in and load the board');
    Check((G.Player.SwordImage = 'sword1.png') and (G.Player.ShieldImage = 'shield1.png') and
      (G.Player.HeadImage = 'head0.png') and (G.Player.AniName = 'idle'),
      'burst: own props in their 2.1 forms (sword, shield, GANI, head)');
    Check((G.Ignored[190] = 0) and (G.Ignored[82] = 0) and (G.Ignored[194] = 0),
      'burst: 82, 190 and 194 have a case in 6.03r7');
    G.Player.Nickname := 'stubstub';
    G.Player.Status := 20;
    for I := 0 to 4 do G.Player.Colors[I] := I + 1;
    G.Tick;
    Check(ServerReadAll(Codec, G.Client.Sent, Msgs), 'burst: the client''s frame decodes');
    for I := Msgs.Count - 1 downto 0 do
      if Msgs[I] = '' then Msgs.Delete(I);
    Props := '';
    NUpd := 0;
    for I := 0 to Msgs.Count - 1 do
    begin
      if MsgId(Msgs[I]) = PLI_PLAYERPROPS then Props := Msgs[I];
      if MsgId(Msgs[I]) = PLI_UPDATEFILE then Inc(NUpd);
    end;
    Check((Msgs.Count > 0) and (MsgId(Msgs[0]) = PLI_PLAYERPROPS),
      'burst: the props come first, as in the lab run');
    Check(Props = GChar(PLI_PLAYERPROPS) +
      GChar(PLPROP_NICKNAME) + GString('stubstub') +
      GChar(PLPROP_COLORS) + GChar(1) + GChar(2) + GChar(3) + GChar(4) + GChar(5) +
      GChar(PLPROP_PLANGUAGE) + GString(G.Player.Language) +
      GChar(PLPROP_OSTYPE) + GString('linux') +
      GChar(PLPROP_X2) + GShort(ToPixels2(G.Player.X)) +
      GChar(PLPROP_Y2) + GShort(ToPixels2(G.Player.Y)),
      'burst: props nickname, colours, language, linux, then X2 and Y2');
    Check(NUpd = 1, 'burst: UPDATEFILE for the head');
    for I := 0 to Msgs.Count - 1 do
      Check(MsgId(Msgs[I]) <> PLI_TAMPERCHECK, 'burst: no tamper check');
  finally
    Msgs.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ Walking sends GANI once, then the coordinate that changed as Y2 every
  tick, then "idle" (protocol/v5v6-lab-play.md, "Play"). }
procedure TestWalkProps;
var
  G: TAdventure;
  Codec: TGen5;
  Msgs: TStringList;
  I, NWalk, NIdle, NY: Integer;
begin
  G := LoggedInGame(Codec);
  { the built-in tile types belong to the built-in sheet, not to this real
    board: walk with no table, as on a board with no arrays.dat }
  G.Arrays.LoadFromString('');
  Msgs := TStringList.Create;
  try
    G.Tick; { the login frame }
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    G.Client.Sent := '';
    for I := 1 to 8 do
    begin
      G.Keys[DirDown] := True;
      G.Tick;
    end;
    G.Keys[DirDown] := False;
    G.Tick;
    G.Tick;
    Check(ServerReadAll(Codec, G.Client.Sent, Msgs), 'walk: frames decode');
    NWalk := 0;
    NIdle := 0;
    NY := 0;
    for I := 0 to Msgs.Count - 1 do
      if MsgId(Msgs[I]) = PLI_PLAYERPROPS then
      begin
        if Pos(GChar(PLPROP_GANI) + GString('walk'), Msgs[I]) = 2 then Inc(NWalk);
        if Pos(GChar(PLPROP_GANI) + GString('idle'), Msgs[I]) = 2 then Inc(NIdle);
        if Pos(GChar(PLPROP_Y2), Msgs[I]) > 0 then Inc(NY);
      end;
    Check((NWalk = 1) and (NIdle = 1), 'walk: GANI walk once at the start, idle once at the end');
    Check(NY = 8, Format('walk: 8 half-tile steps go out as 8 Y2 props (every tick), got %d', [NY]));
    Check(G.Player.Y = 34.5, 'walk: 8 frames down moves 4 tiles');
  finally
    Msgs.Free;
    Codec.Free;
    G.Free;
  end;
end;

procedure TestProps;
var
  G: TAdventure;
  P: TServerPlayer;
  R: TGReader;
begin
  G := TAdventure.Create;
  try
    P := G.FindOther(7, True);
    R := TGReader.Create(GChar(PLPROP_NICKNAME) + GString('bob') +
      GChar(PLPROP_GANI) + GString('walk') + GChar(PLPROP_SPRITE) + GChar(DirLeft) +
      GChar(PLPROP_X) + GChar(40) + GChar(PLPROP_OSTYPE) + GString('wind') +
      GChar(PLPROP_TEXTCODEPAGE) + GInt3(1252) +
      GChar(PLPROP_MAXPOWER) + GChar(6) + GChar(PLPROP_Y) + GChar(50));
    try
      P.ApplyProps(R, True, 0);
    finally
      R.Free;
    end;
    Check((P.Nickname = 'bob') and (P.X = 20) and (P.Y = 0) and (P.OsType = 'wind') and
      (P.CodePage = 1252), 'others: 75 and 76 parse; the stream stops at MAXPOWER');
    Check((P.AniName = 'walk') and (P.FixedStep = -1) and (P.Dir = DirLeft),
      'others: the pose comes from the GANI prop and runs with time');
    R := TGReader.Create(GChar(PLPROP_GMAPLEVELX) + GChar(3) + GChar(PLPROP_Z) + GChar(52) +
      GChar(PLPROP_JOINLEAVELVL) + GChar(0));
    try
      P.ApplyProps(R, True, 0);
    finally
      R.Free;
    end;
    Check((P.GmapX = 3) and (P.Z = 2) and P.Gone, 'others: GMAPLEVELX, Z and a level leave');
    R := TGReader.Create(GChar(PLPROP_X) + GChar(40) + GChar(PLPROP_JOINLEAVELVL) + GChar(1) +
      GChar(PLPROP_Y) + GChar(50));
    try
      G.Player.ApplyProps(R, False, 0);
    finally
      R.Free;
    end;
    Check((G.Player.X = 20) and (G.Player.Y <> 25), 'self: the own stream stops at 50');
    R := TGReader.Create(GChar(PLPROP_GATTRIB30) + GString('a') + GChar(PLPROP_OSTYPE) +
      GString('wind') + GChar(PLPROP_Y) + GChar(50));
    try
      G.Player.ApplyProps(R, False, 0);
    finally
      R.Free;
    end;
    Check((G.Player.Y = 25) and (G.Player.OsType = 'wind'), 'self: the own stream takes 74, 75 and Y');
    R := TGReader.Create(GChar(PLPROP_X2) + GShort(ToPixels2(12.5)) + GChar(PLPROP_Y2) +
      GShort(ToPixels2(-1.0)) + GChar(77) + GChar(1) + GChar(PLPROP_X) + GChar(2));
    try
      G.Player.ApplyProps(R, False, 0);
    finally
      R.Free;
    end;
    Check((G.Player.X = 12.5) and (G.Player.Y = -1) and (ToPixels2(12.5) = 400) and
      (ToPixels2(-1) = 33), 'X2 / Y2: pixels x 2, low bit the sign; the stream stops at 77');
  finally
    G.Free;
  end;
end;

procedure WriteText(const FileName, Text: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Text <> '' then F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

function BE(V: Integer): string;
begin
  Result := Chr((V shr 24) and $FF) + Chr((V shr 16) and $FF) + Chr((V shr 8) and $FF) + Chr(V and $FF);
end;

function MakeArrays(const Free: array of Integer): string;
var
  I: Integer;
begin
  Result := BE(Length(Free));
  for I := 0 to High(Free) do Result := Result + BE(Free[I]);
  for I := 1 to 24 do Result := Result + BE(0);
end;

{ The walking rule (as 2.05's; run-222d shows the same half-tile steps). }
procedure TestWalking;
var
  G: TAdventure;
  I: Integer;
begin
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    for I := 0 to BoardSize - 1 do G.Level.Tiles[I] := 0;
    for I := 0 to 63 do G.Level.Tiles[I + 20 * 64] := 1;
    G.Player.X := 9.5;
    G.Player.Y := 10;
    G.WalkStep(DirRight);
    Check((G.Player.X = 10) and (G.Player.Dir = DirRight), 'walk: a free step is half a tile');
    for I := 1 to 40 do G.WalkStep(DirDown);
    Check(G.Player.Y = 17, 'walk: stops with the body on the wall''s tile line');
  finally
    G.Free;
  end;
end;

{ Links offline, and online: LEVELWARP the first time, LEVELWARPMOD with
  the mod time once the level is held, each followed by the tamper check
  in the same frame. }
procedure TestLinks;
var
  G: TAdventure;
  Codec, SrvOut: TGen5;
  Dir: string;
  Msgs: TStringList;
  I: Integer;
  Plain, Board: string;
begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'g222links' + PathDelim;
  ForceDirectories(Dir);
  WriteText(Dir + 'a.nw', 'GLEVNW01'#10'LINK b.nw 63 0 1 64 0 playery'#10);
  WriteText(Dir + 'b.nw', 'GLEVNW01'#10'LINK a.nw 0 10 1 10 61 12.5'#10);
  G := TAdventure.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    Check(G.LoadLevelFile(Dir + 'a.nw'), 'links: level a loads');
    G.Player.X := 59;
    G.Player.Y := 20;
    for I := 1 to 6 do
      if G.Level.Name = 'a.nw' then
      begin
        G.Keys[DirRight] := True;
        G.Tick;
      end;
    Check((G.Level.Name = 'b.nw') and (G.Player.X = 0) and (G.Player.Y = 20),
      'links: offline, the edge link loads b.nw at x 0, keeping y');
  finally
    G.Free;
    DeleteFile(Dir + 'a.nw');
    DeleteFile(Dir + 'b.nw');
    RemoveDir(Dir);
  end;

  G := LoggedInGame(Codec);
  SrvOut := TGen5.Create(CaptureKey);
  Msgs := TStringList.Create;
  try
    { the server's out iterator: in step after the 8 captured frames }
    for I := 0 to High(CaptureSC) do
    begin
      Plain := Copy(Unhex(CaptureSC[I]), 2, MaxInt);
      SrvOut.Apply(Plain, Ord(Unhex(CaptureSC[I])[1]));
    end;
    G.Tick;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    G.Client.Sent := '';
    SetLength(G.Level.Links, 1);
    G.Level.Links[0].Dest := 'b.nw';
    G.Level.Links[0].X := 0; G.Level.Links[0].Y := 0;
    G.Level.Links[0].W := 64; G.Level.Links[0].H := 64;
    G.Level.Links[0].NewX := '10'; G.Level.Links[0].NewY := '11';
    Check(G.FollowLink(0), 'links: online, a link asks the server');
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    Check((Msgs.Count >= 1) and (Msgs[0] = GChar(PLI_LEVELWARP) + GChar(20) + GChar(22) + 'b.nw') and
      (Msgs.Count = 1),
      'links: LEVELWARP x*2, y*2, level, and no tamper check');
    { the server's answer: level name, board, mod time }
    SetLength(Board, 8192);
    for I := 1 to 8192 do Board[I] := #0;
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LEVELNAME) + 'b.nw'#10 +
      GChar(PLO_RAWDATA) + GInt3(8194) + #10 + GChar(PLO_BOARDPACKET) + Board + #10 +
      GChar(PLO_LEVELMODTIME) + GInt5(1234567) + #10));
    Check((G.Level.Name = 'b.nw') and G.BoardLoaded and (G.Player.X = 10) and
      (G.Player.Y = 11) and (G.WarpCount = 1), 'links: the warp completes when b.nw arrives');
    Check(G.CachedLevel('b.nw', False).HasModTime and
      (G.CachedLevel('b.nw', False).ModTime = 1234567), 'links: the mod time is kept');
    { back to the start level (no mod time for it in this test: LEVELWARP),
      then to b.nw again: LEVELWARPMOD }
    G.CachedLevel('onlinestartlocal.nw', False).HasModTime := False;
    G.Client.Sent := '';
    SetLength(G.Level.Links, 1);
    G.Level.Links[0].Dest := 'onlinestartlocal.nw';
    G.Level.Links[0].X := 0; G.Level.Links[0].Y := 0;
    G.Level.Links[0].W := 64; G.Level.Links[0].H := 64;
    G.Level.Links[0].NewX := '1'; G.Level.Links[0].NewY := '1';
    G.FollowLink(0);
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    Check((Msgs.Count >= 1) and (MsgId(Msgs[0]) = PLI_LEVELWARP),
      'links: a level without a mod time goes as LEVELWARP');
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LEVELNAME) + 'onlinestartlocal.nw'#10));
    SetLength(G.Level.Links, 1);
    G.Level.Links[0].Dest := 'b.nw';
    G.Level.Links[0].X := 0; G.Level.Links[0].Y := 0;
    G.Level.Links[0].W := 64; G.Level.Links[0].H := 64;
    G.Level.Links[0].NewX := '3'; G.Level.Links[0].NewY := '4';
    G.Client.Sent := '';
    G.FollowLink(0);
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    Check((Msgs.Count = 1) and (Msgs[0] = GChar(PLI_LEVELWARPMOD) + GInt5(1234567) +
      GChar(6) + GChar(8) + 'b.nw'),
      'links: a held level goes as LEVELWARPMOD with its mod time, no 39');
    { a cached answer has no board: the level stays drawn from the cache }
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LEVELNAME) + 'b.nw'#10 +
      GChar(PLO_SETACTIVELEVEL) + 'b.nw'#10));
    Check((G.Level.Name = 'b.nw') and G.BoardLoaded and (G.Player.X = 3),
      'links: a cached answer (no board) still lands the player in b.nw');
  finally
    Msgs.Free;
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ A 3x2 gmap: login with PLAYERWARP2, the .gmap by WANTFILE / FILE, the
  neighbours by ADJACENTLEVEL, and a walk across the east edge. }
procedure TestGmap;
const
  GmapText = 'GRMAP001'#13#10'WIDTH 3'#13#10'HEIGHT 2'#13#10'LEVELNAMES'#13#10 +
    '"g_0_0.nw","g_1_0.nw","g_2_0.nw"'#13#10'"g_0_1.nw","g_1_1.nw","g_2_1.nw"'#13#10 +
    'LEVELNAMESEND'#13#10;
var
  G: TAdventure;
  Codec, SrvOut: TGen5;
  M: TGmap;
  Msgs: TStringList;
  I, NAdj: Integer;
  Plain, Board, F: string;
  CX, CY: Integer;
  Got39, GotCell: Boolean;
begin
  M := TGmap.Create;
  try
    Check(M.LoadFromString(GmapText) and (M.Width = 3) and (M.Height = 2) and
      (M.CellName(2, 1) = 'g_2_1.nw') and (M.CellName(3, 0) = ''),
      'gmap: GRMAP001 WIDTH, HEIGHT and LEVELNAMES');
    Check(M.FindCell('G_1_1.NW', CX, CY) and (CX = 1) and (CY = 1), 'gmap: a level''s cell');
    Check(not M.LoadFromString('GRMAP002'#10'WIDTH 1'), 'gmap: a wrong signature is rejected');
  finally
    M.Free;
  end;

  G := LoggedInGame(Codec);
  SrvOut := TGen5.Create(CaptureKey);
  Msgs := TStringList.Create;
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    for I := 0 to High(CaptureSC) do
    begin
      Plain := Copy(Unhex(CaptureSC[I]), 2, MaxInt);
      SrvOut.Apply(Plain, Ord(Unhex(CaptureSC[I])[1]));
    end;
    G.Tick;
    Drain(G, Codec);
    SetLength(Board, 8192);
    for I := 1 to 8192 do Board[I] := #0;
    { the server warps the player onto the gmap, cell 0,0 at x 60 }
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_PLAYERWARP2) + GChar(120) + GChar(60) +
      GChar(50) + GChar(0) + GChar(0) + 'g.gmap'#10 +
      GChar(PLO_LEVELNAME) + 'g_0_0.nw'#10 + GChar(PLO_RAWDATA) + GInt3(8194) + #10 +
      GChar(PLO_BOARDPACKET) + Board + #10 + GChar(PLO_LEVELMODTIME) + GInt5(99) + #10 +
      GChar(PLO_LEVELNAME) + 'g.gmap'#10 + GChar(PLO_SETACTIVELEVEL) + 'g.gmap'#10));
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    Check((G.GmapName = 'g.gmap') and (G.Gmap = nil) and (Msgs.Count >= 1) and
      (Msgs[0] = GChar(PLI_WANTFILE) + 'g.gmap'), 'gmap: an unknown .gmap is asked for with WANTFILE');
    Check((G.Level.Name = 'g_0_0.nw') or (G.Level.Name = ''), 'gmap: the player''s level is the cell''s');
    { the file arrives: i5 mod time, name, data }
    G.Client.Sent := '';
    F := GInt5(1) + GString('g.gmap') + GmapText;
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_RAWDATA) + GInt3(Length(F) + 2) + #10 +
      GChar(PLO_FILE) + F + #10));
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    NAdj := 0;
    for I := 0 to Msgs.Count - 1 do
      if MsgId(Msgs[I]) = PLI_ADJACENTLEVEL then Inc(NAdj);
    Check((G.Gmap <> nil) and (NAdj = 3) and (Msgs[0] = GChar(PLI_ADJACENTLEVEL) + GInt5(0) + 'g_0_1.nw'),
      'gmap: the 3 neighbours of cell 0,0 are asked for, mod time 0');
    { neighbour data goes to the neighbour, not the player's level }
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LEVELNAME) + 'g_1_0.nw'#10 +
      GChar(PLO_RAWDATA) + GInt3(8194) + #10 + GChar(PLO_BOARDPACKET) + Board + #10 +
      GChar(PLO_LEVELNAME) + 'g.gmap'#10));
    Check((G.Level.Name = 'g_0_0.nw') and G.CachedLevel('g_1_0.nw', False).HasBoard,
      'gmap: a neighbour''s board is kept apart from the current level');
    Check(G.WorldTile(64 + 5, 3) = 0, 'gmap: world tiles come from the neighbour''s board');
    { walk east across x 64 }
    G.Client.Sent := '';
    for I := 1 to 12 do
    begin
      G.Keys[DirRight] := True;
      G.Tick;
    end;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    Got39 := False;
    GotCell := False;
    for I := 0 to Msgs.Count - 1 do
    begin
      if MsgId(Msgs[I]) = PLI_TAMPERCHECK then Got39 := True;
      if (MsgId(Msgs[I]) = PLI_PLAYERPROPS) and
        (Pos(GChar(PLPROP_GMAPLEVELX) + GChar(1), Msgs[I]) > 0) then GotCell := True;
    end;
    Check((G.Player.GmapX = 1) and (G.Player.X < 10) and (G.Level.Name = 'g_1_0.nw') and
      (G.EdgeCrossings = 1), 'gmap: walking east past x 64 moves into cell 1,0');
    Check(not Got39 and GotCell, 'gmap: the crossing sends props with GMAPLEVELX = 1 and no 39');
  finally
    Msgs.Free;
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ The lab saw these clients send 24 about every 5 s, but not its payload or what
  starts it; the rebuild sends none yet. }
procedure TestShowImg;
var
  G: TAdventure;
  Codec, SrvOut: TGen5;
  Msgs: TStringList;
  I, N: Integer;
  Plain: string;
begin
  G := LoggedInGame(Codec);
  SrvOut := TGen5.Create(CaptureKey);
  Msgs := TStringList.Create;
  try
    for I := 0 to High(CaptureSC) do
    begin
      Plain := Copy(Unhex(CaptureSC[I]), 2, MaxInt);
      SrvOut.Apply(Plain, Ord(Unhex(CaptureSC[I])[1]));
    end;
    G.ClockMs := 1000;
    G.Tick;
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_OTHERPLPROPS) + GShort(2) +
      GChar(PLPROP_NICKNAME) + GString('other') + #10));
    Drain(G, Codec);
    for I := 1 to 220 do
    begin
      G.ClockMs := 1000 + I * 50;
      G.Tick;
    end;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    N := 0;
    for I := 0 to Msgs.Count - 1 do
      if Msgs[I] = GChar(PLI_SHOWIMG) + GChar(9) then Inc(N);
    Check(N = 0, Format('24: none over TCP in 11 s with another player in the level, got %d', [N]));
  finally
    Msgs.Free;
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ ---- fuzzing the receive path ---- }

const
  FuzzIds: array[0..31] of Integer = (PLO_LEVELLINK, PLO_LEVELCHEST, PLO_LEVELSIGN,
    PLO_LEVELNAME, PLO_OTHERPLPROPS, PLO_PLAYERPROPS, PLO_PLAYERWARP, PLO_WARPFAILED,
    PLO_DISCMESSAGE, PLO_SIGNATURE, PLO_NEWWORLDTIME, PLO_STARTMESSAGE, PLO_BOARDPACKET,
    PLO_SETACTIVELEVEL, PLO_TOALL, PLO_LEVELBOARD, PLO_BOARDMODIFY, PLO_NPCPROPS,
    PLO_BADDYPROPS, PLO_LEVELMODTIME, PLO_FILE, PLO_RAWDATA, PLO_PLAYERWARP2,
    PLO_BOARDMODIFY2, PLO_SERVERWARP, PLO_LARGEFILESTART, PLO_LARGEFILEEND,
    PLO_FREEZEPLAYER2, PLO_UNFREEZEPLAYER, PLO_SHOWIMGPLAYER, PLO_GHOSTICON, PLO_LARGEFILESTART);

function RandomBytes(N: Integer; Printable: Boolean): string;
var
  I: Integer;
begin
  SetLength(Result, N);
  for I := 1 to N do
    if Printable then Result[I] := Chr(32 + Random(96))
    else Result[I] := Chr(Random(256));
end;

function RandomProps: string;
var
  I, N: Integer;
begin
  Result := '';
  N := Random(12);
  for I := 1 to N do
  begin
    Result := Result + GChar(Random(80));
    case Random(4) of
      0: Result := Result + GChar(Random(224) - 32);
      1: Result := Result + GString(RandomBytes(Random(12), True));
      2: Result := Result + RandomBytes(Random(6), False);
    else
      Result := Result + Chr(Random(256));
    end;
  end;
  if (Result <> '') and (Random(3) = 0) then
    SetLength(Result, Random(Length(Result)));
end;

function RandomMessage(out Id: Integer): string;
const
  Names: array[0..4] of string = ('g.gmap', 'a.nw', 'g_0_0.nw', 'x.gmap', '');
begin
  if Random(5) = 0 then Id := Random(256) else Id := FuzzIds[Random(Length(FuzzIds))];
  case Id of
    PLO_PLAYERPROPS: Result := RandomProps;
    PLO_OTHERPLPROPS: Result := GShort(Random(8)) + RandomProps;
    PLO_BOARDPACKET:
      case Random(3) of
        0: Result := RandomBytes(8192, False);
        1: Result := RandomBytes(Random(9000), False);
      else
        Result := '';
      end;
    PLO_LEVELNAME, PLO_SETACTIVELEVEL: Result := Names[Random(5)];
    PLO_PLAYERWARP2:
      Result := RandomBytes(Random(6), False) + Names[Random(5)];
    PLO_FILE:
      if Random(2) = 0 then
        Result := GInt5(Random(1000)) + GString('g.gmap') + 'GRMAP001'#10'WIDTH ' +
          IntToStr(Random(300) - 10) + #10'HEIGHT ' + IntToStr(Random(5)) +
          #10'LEVELNAMES'#10 + RandomBytes(Random(40), True) + #10'LEVELNAMESEND'#10
      else
        Result := RandomBytes(Random(60), False);
    PLO_SERVERWARP:
      { never four good fields: the fuzzer must not open connections }
      Result := RandomBytes(Random(10), True) + ',' + RandomBytes(Random(10), True);
    PLO_LEVELLINK:
      Result := RandomBytes(Random(10), True) + ' ' + IntToStr(Random(80) - 8) + ' ' +
        IntToStr(Random(80) - 8) + ' ' + IntToStr(Random(70)) + ' ' + IntToStr(Random(70)) +
        ' ' + RandomBytes(Random(5), True) + ' ' + RandomBytes(Random(5), True);
  else
    Result := RandomBytes(Random(48), Random(2) = 0);
  end;
end;

procedure TestFuzz;
var
  G: TAdventure;
  I, J, Id, Raised: Integer;
  Data, Plain, LastErr: string;
  SrvOut: TGen5;
begin
  RandSeed := 222;
  Raised := 0;
  LastErr := '';
  G := TAdventure.Create;
  SrvOut := TGen5.Create(9);
  try
    G.Arrays.LoadFromString(MakeArrays([0]));
    G.UseWallClock := False;
    if GetEnvironmentVariable('GRAAL603_DATA') <> '' then
      G.UseInstall(GetEnvironmentVariable('GRAAL603_DATA'));
    G.Client.StartOffline(9);
    G.Client.Sink := True;
    for I := 1 to 20000 do
    begin
      Data := RandomMessage(Id);
      try
        G.Receive(Id, Data);
        if I mod 50 = 0 then
        begin
          for J := 0 to 3 do G.Keys[J] := Random(2) = 0;
          G.ClockMs := G.ClockMs + 50;
          G.Tick;
          G.Client.Sent := '';
          G.Client.Sink := True;
        end;
      except
        on E: Exception do
        begin
          Inc(Raised);
          if LastErr = '' then
          begin
            LastErr := Format('id %d, %d bytes: %s: %s', [Id, Length(Data), E.ClassName, E.Message]);
{$IFDEF FPC}
            DumpExceptionBackTrace(Output);
{$ENDIF}
          end;
        end;
      end;
    end;
    if LastErr <> '' then WriteLn('  first: ', LastErr);
    Check(Raised = 0, Format('fuzz: 20000 random messages, %d raised', [Raised]));

    { gen-5 frames around random messages, and raw garbage; a bad frame
      drops the link, so the codec is started again for the next one }
    Raised := 0;
    LastErr := '';
    for I := 1 to 3000 do
    begin
      try
        if not G.Client.Connected then
        begin
          G.Client.StartOffline(9);
          G.Client.Sink := True;
          SrvOut.Iterator := CipherSeed;
        end;
        if Random(4) = 0 then
          G.Client.FeedRaw(RandomBytes(Random(64), False))
        else
        begin
          Plain := '';
          for J := 1 to 1 + Random(6) do
          begin
            Data := RandomMessage(Id);
            if Random(8) = 0 then
              Plain := Plain + Chr(PLO_RAWDATA + 32) + GInt3(Length(Data) + 2) + #10 +
                Chr((Id + 32) and $FF) + Data + #10
            else
              Plain := Plain + Chr((Id + 32) and $FF) + StringReplace(Data, #10, ' ',
                [rfReplaceAll]) + #10;
          end;
          Data := ServerFrame(SrvOut, Plain);
          J := Random(Length(Data) + 1);
          G.Client.FeedRaw(Copy(Data, 1, J));
          G.Client.FeedRaw(Copy(Data, J + 1, MaxInt));
        end;
        if I mod 20 = 0 then
        begin
          G.Tick;
          G.Client.Sent := '';
        end;
      except
        on E: Exception do
        begin
          Inc(Raised);
          if LastErr = '' then
          begin
            LastErr := E.ClassName + ': ' + E.Message;
{$IFDEF FPC}
            DumpExceptionBackTrace(Output);
{$ENDIF}
          end;
        end;
      end;
    end;
    if LastErr <> '' then WriteLn('  first: ', LastErr);
    Check(Raised = 0, Format('fuzz: 3000 random gen-5 frames, %d raised', [Raised]));
  finally
    SrvOut.Free;
    G.Free;
  end;
end;

procedure TestReceiveLimits;
var
  G: TAdventure;
  I: Integer;
  Plain: string;
  T0: TDateTime;
  SrvOut: TGen5;
begin
  G := TAdventure.Create;
  SrvOut := TGen5.Create(3);
  try
    G.Client.StartOffline(3);
    Plain := '';
    for I := 1 to 20000 do Plain := Plain + Chr(PLO_TOALL + 32) + 'x' + #10;
    T0 := Now;
    G.Client.FeedRaw(ServerFrame(SrvOut, Plain));
    Check(G.Handled[PLO_TOALL] = 20000, 'receive: 20000 messages in one bz2 frame');
    Check((Now - T0) * 86400 < 2, 'receive: a big burst takes well under 2 s');
    G.Client.FeedRaw(ServerFrame(SrvOut, StringOfChar('a', InPendingMax + 1)));
    Check(Pos('unfinished', G.Client.LastError) > 0,
      'receive: an unfinished message past the limit drops the link');
    G.Client.StartOffline(3);
    SrvOut.Iterator := CipherSeed;
    G.Client.LastError := '';
    G.Client.FeedRaw(#0#6#4'xxxxx');
    Check(Pos('bad frame', G.Client.LastError) > 0, 'receive: a bad zlib frame drops the link');
    G.Client.StartOffline(3);
    G.Client.LastError := '';
    G.Client.FeedRaw(#0#4#7'abc');
    Check(Pos('bad frame', G.Client.LastError) > 0, 'receive: an unknown compression byte drops the link');
    G.Client.StartOffline(3);
    SrvOut.Iterator := CipherSeed;
    G.Client.FeedRaw(ServerFrame(SrvOut, Chr(PLO_TOALL + 32) + 'y' + #10));
    Check(G.Handled[PLO_TOALL] = 20001, 'receive: buffers are clean after a dropped link');
  finally
    SrvOut.Free;
    G.Free;
  end;
end;

{ The Login lobby: the first server is Login, where no characters are
  drawn; 182 is answered with 44; a 178 "x,name,host,port" is split on
  commas only and its name ends Login mode (protocol/v5v6-lab-play.md). }
procedure TestLobby;
var
  G: TAdventure;
  Codec, SrvOut: TGen5;
  Msgs: TStringList;
  I, N: Integer;
  Plain: string;
begin
  G := LoggedInGame(Codec);
  SrvOut := TGen5.Create(CaptureKey);
  Msgs := TStringList.Create;
  try
    for I := 0 to High(CaptureSC) do
    begin
      Plain := Copy(Unhex(CaptureSC[I]), 2, MaxInt);
      SrvOut.Apply(Plain, Ord(Unhex(CaptureSC[I])[1]));
    end;
    Check((G.ServerName = 'Login') and G.LoginMode and not LoginTiles,
      'lobby: the first server is Login, in Login mode, with no tiles drawn');
    G.ServerName := 'LOGIN2';
    Check(G.LoginMode, 'lobby: any name that starts with login, in any case');
    G.ServerName := 'Classic';
    Check(not G.LoginMode, 'lobby: another name plays');
    G.ServerName := 'Login';
    G.Tick;
    Drain(G, Codec);
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LISTPROCESSES) + #10));
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    G.Client.Sent := '';
    N := 0;
    for I := 0 to Msgs.Count - 1 do
      if Msgs[I] = GChar(PLI_PROCESSLIST) + 'Login' then Inc(N);
    Check(N = 1, '182: answered with 44 naming only the game window');
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_SERVERWARP) + '0,Lab Server,127.0.0.1' + #10));
    Check((G.ServerWarps = 0) and (G.ServerName = 'Login'), '178: three fields are ignored');
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_SERVERWARP) + '0,Lab Server,127.0.0.1,1' + #10));
    Check((G.ServerWarps = 1) and (G.ServerName = 'Lab Server') and not G.LoginMode and
      not G.LoggedIn, '178: split on commas only; the name with its space ends Login mode');
  finally
    Msgs.Free;
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ 6.x frames of 0xFFFF bytes or more: 0xFFFF, then a u32be length. }
procedure TestLongFrame;
var
  G: TAdventure;
  Codec, SrvOut: TGen5;
  Plain, Body, Msgs: string;
  I, CType: Integer;
begin
  G := LoggedInGame(Codec);
  SrvOut := TGen5.Create(CaptureKey);
  try
    for I := 0 to High(CaptureSC) do
    begin
      Plain := Copy(Unhex(CaptureSC[I]), 2, MaxInt);
      SrvOut.Apply(Plain, Ord(Unhex(CaptureSC[I])[1]));
    end;
    Check((FrameLength(10) = #0#10) and (FrameLength($FFFE) = #$FF#$FE) and
      (FrameLength($FFFF) = #$FF#$FF#0#0#$FF#$FF) and
      (FrameLength($12345) = #$FF#$FF#0#1#$23#$45), 'long frames: u16be, or 0xFFFF and a u32be');
    { 7000 messages, 70000 raw bytes: one frame of the long form }
    Msgs := '';
    for I := 1 to 7000 do Msgs := Msgs + GChar(PLO_TOALL) + 'abcdefgh' + #10;
    Body := Msgs;
    CType := CompressNone;
    SrvOut.Apply(Body, CType);
    Body := Chr(CType) + Body;
    I := G.Handled[PLO_TOALL];
    G.Client.FeedRaw(FrameLength(Length(Body)) + Copy(Body, 1, 1000));
    G.Client.FeedRaw(Copy(Body, 1001, MaxInt));
    Check(G.Client.Connected and (G.Handled[PLO_TOALL] - I = 7000),
      'long frames: a 70000-byte frame in the long form, fed in two parts');
    G.Client.FeedRaw(#$FF#$FF#$7F#0#0#0);
    Check(not G.Client.Connected and (Pos('limit', G.Client.LastError) > 0),
      'long frames: a length past the limit drops the link');
  finally
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

procedure TestBoardModify;
var
  G: TAdventure;
begin
  G := TAdventure.Create;
  try
    G.Receive(PLO_BOARDMODIFY, GChar(2) + GChar(3) + GChar(2) + GChar(1) + GShort(77) + GShort(78));
    Check((G.Level.Tile(2, 3) = 77) and (G.Level.Tile(3, 3) = 78), 'BOARDMODIFY: a 2x1 patch');
    G.Receive(PLO_BOARDMODIFY, GChar(2) + GChar(3) + GChar(2) + GChar(1) + GShort(5));
    Check(G.Level.Tile(2, 3) = 77, 'BOARDMODIFY: a short payload is dropped');
    G.Receive(PLO_BOARDMODIFY2, GChar(0) + GChar(0) + GChar(62) + GChar(63) + GChar(4) +
      GChar(1) + GShort(9) + GShort(9) + GShort(9) + GShort(9) + 'pad');
    Check(G.Level.Tile(63, 63) = 9, 'BOARDMODIFY2: tiles past the board edge are clipped');
  finally
    G.Free;
  end;
end;

{ The built-in defaults: a game with nothing next to it still has a tile
  sheet, the starter level and the walking gani. }
procedure TestBuiltins;
var
  G: TAdventure;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.SheetBuiltin and (G.Sheet <> nil) and (G.Sheet.Width > 0),
      'built-in: the default tile sheet');
    Check(G.LoadLevelFile('start.nw') and (Length(G.Level.Links) > 0),
      'built-in: start.nw loads with no install');
    Check(G.Assets.Ani('walk') <> nil, 'built-in: walk gani');
    { the tutorial's addtiledef, read from its NPC script }
    SetLength(G.Level.NPCs, 1);
    G.Level.NPCs[0].Script := 'if (playerenters) {'#10 +
      '  addtiledef picso.png,offlinetutorial,1;'#10'  loadmap x;'#10'}';
    G.NoteTileDefs(G.Level);
    Check((G.TileDefs.Count = 1) and (G.TileDefs[0] = 'offlinetutorial'#9'picso.png'),
      'addtiledef: image and prefix read from the level script');
    Check(G.TileSheetFor('offlinetutorial_a-1.graal') = G.Sheet,
      'addtiledef: a missing image keeps pics1');
    Check(G.TileSheetFor('start.nw') = G.Sheet, 'addtiledef: other levels keep pics1');
  finally
    G.Free;
  end;
end;

begin
  TestGTypes;
  TestBzip2;
  TestGen5Capture;
  TestLogin;
  TestListServer;
  TestBuiltins;
  TestLoginBurst;
  TestWalkProps;
  TestProps;
  TestWalking;
  TestLinks;
  TestGmap;
  TestShowImg;
  TestLobby;
  TestLongFrame;
  TestBoardModify;
  TestFuzz;
  TestReceiveLimits;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
