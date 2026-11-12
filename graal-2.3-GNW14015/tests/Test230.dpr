{ Tests for the 2.22 rebuild. No framework: each check prints a line and
  the run exits 1 if any failed.

  Wire checks run against frames of a real 2.22 session (Capture222.inc).
  Optional: GRAAL230_DATA = a 2.22 install, so the fuzzer also draws the
  fuzzed players with real heads, bodies and ganis. }
program Test230;

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
  Protocol230 in '../src/Protocol230.pas',
  GraalClient in '../src/GraalClient.pas',
  GGs1 in '../src/GGs1.pas',
  Npc230 in '../src/Npc230.pas',
  Baddy230 in '../src/Baddy230.pas',
  NpcBridge230 in '../src/NpcBridge230.pas',
  Adventure in '../src/Adventure.pas',
  GSound in '../../common/GSound.pas',
  Sound230 in '../src/Sound230.pas',
  Map230 in '../src/Map230.pas',
  GBuiltin in '../../common/GBuiltin.pas',
  GStartScreen in '../../common/GStartScreen.pas',
  ListServer230 in '../src/ListServer230.pas',
  GWindow in '../../common/GWindow.pas',
  GUiFont in '../../common/GUiFont.pas',
  GSysUiFont in '../../common/GSysUiFont.pas',
  Res230 in '../src/Res230.pas',
  Dialogs230 in '../src/Dialogs230.pas',
  RealStart230 in '../src/RealStart230.pas',
  GDfmObj in '../../common/GDfmObj.pas',
  GVclForm in '../../common/GVclForm.pas',
  GOptionsWindow in '../../common/GOptionsWindow.pas',
  TestNpc230 in 'TestNpc230.pas',
  TestBaddy230 in 'TestBaddy230.pas';

{$I Capture222.inc}

type
  { reaches the codec hooks }
  TClientAccess = class(TAdventureClient);

var
  Passed, Failed, Skipped, NpcSkipped: Integer;

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
{ PLI_ENTERLEVEL (46) messages ServerReadAll took out: 2.3 sends one on
  every level entry, which the 2.22 capture the checks compare with has
  not. Tests that care read and reset this count. }
var
  EnterLevels: Integer = 0;

function ServerReadAll(Codec: TGen5; const Wire: string; Msgs: TStrings): Boolean;
var
  P, Len, I: Integer;
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
      for I := L.Count - 1 downto 0 do
        if (L[I] <> '') and (Ord(L[I][1]) - 32 = PLI_ENTERLEVEL) then
        begin
          if L[I] = GChar(PLI_ENTERLEVEL) + GChar(1) then Inc(EnterLevels);
          L.Delete(I);
        end;
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

{ The login: its own frame, zlib, no compression byte; then 37 and the
  tamper check in the next frame, exactly as the real client sent them. }
procedure TestLogin;
var
  C: TAdventureClient;
  Wire, Plain: string;
  Len: Integer;
  Codec: TGen5;
begin
  C := TAdventureClient.Create;
  Codec := TGen5.Create(CaptureKey);
  try
    C.StartOffline(CaptureKey);
    C.Sink := True;
    C.SendLogin('acc', 'pw', 'English');
    C.Flush;
    Wire := C.Sent;
    Len := (Ord(Wire[1]) shl 8) or Ord(Wire[2]);
    Check(ZDecompress(Copy(Wire, 3, Len), Plain) and
      (Plain = '%' + Chr(CaptureKey + 32) + 'GNW14015' + GString('acc') + GString('pw') + #10),
      'login: type 5, key, GNW14015, account, password; zlib, no compression byte');
    { the same frame as 2.22's, with 2.3's tamper bytes in place of 2.22's }
    Check(ServerReadFrame(Codec, Copy(Wire, Len + 3, MaxInt), Plain) and
      (Plain = StringReplace(Unhex(CapturePlainCS[0]),
        #$25#$0E#$4D#$0F#$96#$2B#$03#$ED#$E6#$31, TamperCheckBytes, [])),
      'login: PLI_LANGUAGE and the tamper check, laid out as 2.22''s real first frame');
    Check(Pos(TamperCheckBytes, Plain) > 0, 'login: tamper check (2.31''s bytes, a stand-in)');
  finally
    C.Free;
    Codec.Free;
  end;
end;

{ The 2.22 listserver step: id 7 with the key, GNW30123 and newmain in a
  plain zlib frame, then id 1 in gen 5; the list, status and urls back. }
procedure TestListServer;
var
  C: TListServerClient;
  Codec, SCodec: TGen5;
  Wire, Plain, List: string;
  Len: Integer;
  H: TListHosts;
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
      (Plain = GChar(7) + GChar(CaptureKey) + 'GNW30123newmain' + #10) and
      (Length(Plain) = 18),
      'list: id 7, key, GNW30123, newmain in a plain zlib frame (18 bytes)');
    Check(ServerReadFrame(Codec, Copy(Wire, Len + 3, MaxInt), Plain) and
      (Plain = GChar(1) + GString('acc') + GString('pw') + #10) and
      (Ord(Wire[Len + 5]) = 2),
      'list: id 1 account and password in a raw gen-5 frame');
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
    H := ParseArrays2('list.example'#13#10'14922'#13#10'a'#13#10'b'#13#10'c'#13#10 +
      'fb1.example'#13#10'fb2.example'#13#10);
    Check((Length(H.Hosts) = 3) and (H.Hosts[0] = 'list.example') and
      (H.Hosts[1] = 'fb1.example') and (H.Hosts[2] = 'fb2.example') and
      (H.Port = 14922), 'arrays2.dat: host, port, fallbacks on lines 5 and 6');
    H := ParseArrays2('');
    Check((Length(H.Hosts) = 0) and (H.Port = 14922), 'arrays2.dat: empty file');
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
  Msgs, Real: TStringList;
  I, J: Integer;
  Props: string;
begin
  G := LoggedInGame(Codec);
  Msgs := TStringList.Create;
  Real := TStringList.Create;
  try
    Check(G.LoggedIn and G.BoardLoaded and (G.Level.Name = 'onlinestartlocal.nw'),
      'burst: the real server''s login frames log in and load the board');
    Check((G.Player.SwordImage = 'sword1.png') and (G.Player.ShieldImage = 'shield1.png') and
      (G.Player.HeadImage = 'head0.png') and (G.Player.AniName = 'idle'),
      'burst: own props in their 2.1 forms (sword, shield, GANI, head)');
    Check((G.Player.X = 30) and (G.Player.Y = 30.5), 'burst: PLAYERWARP 30, 30.5');
    Check((G.Ignored[190] = 1) and (G.Ignored[82] = 1) and (G.Ignored[194] = 1),
      'burst: ids 2.22 has no case for (82, 190, 194) are ignored');
    { the client's first frame after the burst }
    G.Player.Nickname := 'stubstub';
    G.Player.Colors[0] := 2; G.Player.Colors[1] := 0; G.Player.Colors[2] := 10;
    G.Player.Colors[3] := 4; G.Player.Colors[4] := 18;
    G.Player.Status := 20;
    G.Tick;
    EnterLevels := 0;
    Check(ServerReadAll(Codec, G.Client.Sent, Msgs), 'burst: the client''s frame decodes');
    Check(EnterLevels = 1, 'burst: ENTERLEVEL (46) = 1 for the start level');
    SplitLines(Unhex(CapturePlainCS[1]), Real);
    { the real frame minus the FLAGSETs of the server's movement script and
      the 24, which the rebuild sends only with another player present }
    for I := Real.Count - 1 downto 0 do
      if (MsgId(Real[I]) = PLI_FLAGSET) or (MsgId(Real[I]) = PLI_SHOWIMG) or (Real[I] = '') then
        Real.Delete(I);
    for I := Msgs.Count - 1 downto 0 do
      if Msgs[I] = '' then Msgs.Delete(I);
    J := 0;
    for I := 0 to Real.Count - 1 do
      if (I < Msgs.Count) and (MsgId(Msgs[I]) = MsgId(Real[I])) then Inc(J);
    Check((Msgs.Count = Real.Count) and (J = Real.Count),
      'burst: UPDATEFILE x4 then PLAYERPROPS, in the real client''s order');
    Props := '';
    for I := 0 to Msgs.Count - 1 do
      if MsgId(Msgs[I]) = PLI_PLAYERPROPS then Props := Msgs[I];
    Check(Props = Real[Real.Count - 1],
      'burst: the props message matches the real one byte for byte (0, 11, 13, 18, 31, 33, 52, 75, 76)');
    Check(Copy(Msgs[0], 7, MaxInt) = 'plisticoneating.png', 'burst: UPDATEFILE i5 mod time + name');
  finally
    Msgs.Free;
    Real.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ Walking sends GANI, X and Y as the real client does (b4_222: "*$walk0^",
  then Y steps, then "*$idle"). }
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
    if G.Frame mod 2 = 1 then G.Tick; { line up with the 100 ms props gate }
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
        if Pos(GChar(PLPROP_Y), Msgs[I]) > 0 then Inc(NY);
      end;
    Check((NWalk = 1) and (NIdle = 1), 'walk: GANI walk once at the start, idle once at the end');
    Check(NY = 4, Format('walk: 8 half-tile steps go out as 4 Y props (every 100 ms), got %d', [NY]));
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
    Check((G.Player.Y <> 25) and (G.Player.OsType = ''), 'self: the own stream takes 74 and stops at 75');
    { 2.3: X2 / Y2 / Z2 (78 to 80) as s(abs(v * 16) shl 1 or sign) }
    R := TGReader.Create(GChar(PLPROP_X2) + GShort((10 * 16) shl 1) +
      GChar(PLPROP_Y2) + GShort(((3 * 16 + 8) shl 1) or 1) +
      GChar(PLPROP_Z2) + GShort((2 * 16) shl 1) + GChar(81) + GChar(PLPROP_X) + GChar(2));
    try
      P.ApplyProps(R, True, 0);
    finally
      R.Free;
    end;
    Check((P.X = 10) and (P.Y = -3.5) and (P.Z = 2), 'others: X2, Y2 (negative) and Z2; stops above 80');
    R := TGReader.Create(GChar(77) + GChar(0) + GChar(PLPROP_X) + GChar(2));
    try
      P.ApplyProps(R, True, 0);
    finally
      R.Free;
    end;
    Check(P.X = 10, 'others: the stream stops at 77');
    Check(not PLOKnown(PLO_HASNPCSERVER) and PLOKnown(PLO_LARGEFILESIZE) and PLOKnown(PLO_MOVE2),
      'ids: 2.3 drops 44 and handles 84 and 189');
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
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'g230links' + PathDelim;
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
    Check((Msgs.Count = 1) and (Msgs[0] = GChar(PLI_LEVELWARP) + GChar(20) + GChar(22) + 'b.nw'),
      'links: LEVELWARP x*2, y*2, level, and no 39 after it');
    G.Client.Sent := '';
    { the server's answer: level name, board, mod time }
    SetLength(Board, 8192);
    for I := 1 to 8192 do Board[I] := #0;
    G.Client.FeedRaw(ServerFrame(SrvOut, GChar(PLO_LEVELNAME) + 'b.nw'#10 +
      GChar(PLO_RAWDATA) + GInt3(8194) + #10 + GChar(PLO_BOARDPACKET) + Board + #10 +
      GChar(PLO_LEVELMODTIME) + GInt5(1234567) + #10));
    Check((G.Level.Name = 'b.nw') and G.BoardLoaded and (G.Player.X = 10) and
      (G.Player.Y = 11) and (G.WarpCount = 1), 'links: the warp completes when b.nw arrives');
    EnterLevels := 0;
    G.Client.Flush;
    ServerReadAll(Codec, G.Client.Sent, Msgs);
    G.Client.Sent := '';
    Check(EnterLevels = 1, 'links: entering b.nw sends ENTERLEVEL (46) = 1');
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
  GotCell: Boolean;
  J39, K: Integer;
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
    GotCell := False;
    for I := 0 to Msgs.Count - 1 do
    begin
      if (MsgId(Msgs[I]) = PLI_PLAYERPROPS) and
        (Pos(GChar(PLPROP_GMAPLEVELX) + GChar(1), Msgs[I]) > 0) then GotCell := True;
    end;
    Check((G.Player.GmapX = 1) and (G.Player.X < 10) and (G.Level.Name = 'g_1_0.nw') and
      (G.EdgeCrossings = 1), 'gmap: walking east past x 64 moves into cell 1,0');
    Check(GotCell, 'gmap: the crossing sends props with GMAPLEVELX = 1');
    { 2.3 sends 39 on its 64-tick timer, not on the crossing }
    G.Client.Sent := '';
    J39 := 0;
    for I := 1 to 64 do
    begin
      G.Tick;
      G.Client.Flush;
      ServerReadAll(Codec, G.Client.Sent, Msgs);
      G.Client.Sent := '';
      for K := 0 to Msgs.Count - 1 do
        if Msgs[K] = GChar(PLI_TAMPERCHECK) + TamperCheckBytes then Inc(J39);
    end;
    Check(J39 = 1, 'tamper check: once every 64 ticks (about 3.2 s)');
  finally
    Msgs.Free;
    SrvOut.Free;
    Codec.Free;
    G.Free;
  end;
end;

{ 24 = 9 at intervals of 5.1 s while another player is in the level. }
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
    Check(N = 2, Format('24: two in 11 s with another player in the level, got %d', [N]));
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
    PLO_BOARDMODIFY2, PLO_SERVERWARP, PLO_LISTPROCESSES, PLO_HASPROCESSRUNNING,
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
    if GetEnvironmentVariable('GRAAL230_DATA') <> '' then
      G.UseInstall(GetEnvironmentVariable('GRAAL230_DATA'));
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

{ a GSTRING: c(length) + text }
function GS(const S: string): string;
begin
  Result := Chr(Length(S) + 32) + S;
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

procedure TestStatus;
var
  G: TAdventure;

  function Lit(X, Y, W, H: Integer): Boolean;
  var
    I, J: Integer;
  begin
    Result := False;
    for J := Y to Y + H - 1 do
      for I := X to X + W - 1 do
        if G.Screen.GetPixel(I, J) and $FFFFFF <> 0 then
        begin
          Result := True;
          Exit;
        end;
  end;

begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check((G.Player.MaxPower = 3) and (G.Player.Power = 6) and (G.Player.Bombs = 10) and
      (G.Player.Arrows = 5) and (G.AP = 50), 'status: a new account starts at 3 hearts, 10 bombs, 5 arrows');
    G.Screen.Fill($FF000000);
    G.DrawStatus;
    Check(Lit(ScreenW - 198, 24, 40, 44), 'status: the first big heart is drawn');
    Check(Lit(ScreenW - 198 + 90, 24, 40, 44), 'status: the third big heart is drawn');
    Check(not Lit(ScreenW - 198 + 135, 24, 40, 44), 'status: no fourth heart with three containers');
    Check(Lit(15, 30, 22, 33) and Lit(145, 30, 22, 33), 'status: the A and D buttons');
    Check(Lit(326, 48, 26, 16), 'status: the bomb count');
    G.Screen.Fill($FF000000);
    G.Player.MaxPower := 6;
    G.Player.Power := 3;
    G.DrawStatus;
    Check(Lit(ScreenW - 198, 34, 31, 33) and not Lit(ScreenW - 198 + 70, 34, 31, 33),
      'status: small hearts past four containers, only while power remains');
    G.Screen.Fill($FF000000);
    G.ShowStats := 0;
    G.DrawStatus;
    Check(not Lit(0, 0, ScreenW, 120), 'status: showstats 0 hides everything');
  finally
    G.Free;
  end;
end;

procedure TestActions;
var
  G: TAdventure;
  A: TGraalAni;
  OX, OY, I, R0: Integer;
  X, Y, W, H: Integer;
begin
  { the sprite table packing, against two rectangles the HUD notes give }
  G := TAdventure.Create;
  try
    G.Arrays.Lists[24].Free;
    G.Arrays.Lists[24] := TGArray.Create;
    SetLength(G.Arrays.Lists[24].Values, 2);
    G.Arrays.Lists[24].Values[0] := Integer($0E06A390);
    G.Arrays.Lists[24].Values[1] := Integer($2F01238E);
    Check(G.Arrays.SpriteRect(0, X, Y, W, H) and (X = 28) and (Y = 212) and (W = 28) and (H = 32),
      'sprites: table entry 145 is (28, 212, 28, 32)');
    Check(G.Arrays.SpriteRect(1, X, Y, W, H) and (X = 94) and (Y = 36) and (W = 28) and (H = 28),
      'sprites: table entry 17 is (94, 36, 28, 28)');
  finally
    G.Free;
  end;
  { PARAM placements keep their row (the carry ganis have one per row) }
  A := TGraalAni.Create;
  try
    Check(A.LoadFromString('SPRITE 1 BODY 0 0 36 36 b'#10'DEFAULTPARAM1 20'#10'ANI'#10 +
      ' 1 0 0, PARAM1 8 -18'#10' 1 0 0'#10' 1 0 0'#10' 1 0 0, PARAM1 8 -18'#10'ANIEND'#10) and
      (Length(A.Steps) = 1) and (Length(A.Steps[0].Dirs[3]) = 2) and
      (A.Steps[0].Dirs[3][1].Sprite = ParamSprite - 1) and (A.DefaultParam[1] = '20'),
      'gani: a PARAM1 placement is read, not dropped');
  finally
    A.Free;
  end;
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'actions: the built-in level loads');
    { the sword cuts the bush below: built-in bush 36, 26 }
    G.Player.X := 35;
    G.Player.Y := 22;
    G.Player.Dir := DirDown;
    Check(G.MatchObject(9, 99, 36.5, 26, OX, OY) = 0, 'actions: the bush matches the cut table');
    G.Attack;
    Check((G.Mode = ModeSword) and (G.Level.Tile(36, 26) = G.Arrays.ObjectTile(10, 0, 0, 0)),
      'actions: a swing cuts the bush at the tip');
    G.Mode := ModeFree;
    { the pot lifts with glove 1, the stone needs glove 2 }
    G.Player.X := 24.5;
    G.Player.Y := 32;
    G.Action;
    Check((G.Mode = ModeLift) and (G.CarryKind = 2) and
      (G.Level.Tile(26, 36) = G.Arrays.ObjectTile(12, 2, 0, 0)), 'actions: A lifts the pot');
    for I := 1 to 10 do G.Tick;
    Check(G.Mode = ModeCarry, 'actions: the lift ends in carrying');
    G.AttackKey := True;
    G.Tick;
    Check((G.Mode = ModeFree) and (G.CarryKind = -1) and (Length(G.Thrown) = 1),
      'actions: S throws what is carried');
    for I := 1 to 10 do G.Tick;
    Check(Length(G.Thrown) = 0, 'actions: the thrown pot lands');
    G.Player.X := 34.5;
    G.Player.Y := 33;
    G.Action;
    Check(G.Mode = ModeFree, 'actions: glove 1 does not lift a stone');
    G.Player.GlovePower := 2;
    G.Action;
    Check((G.Mode = ModeLift) and (G.CarryKind = 3), 'actions: glove 2 lifts it');
    G.Mode := ModeFree;
    G.CarryKind := -1;
    { the chest gives its red rupee once }
    G.Player.X := 25;
    G.Player.Y := 27;
    G.Player.Dir := DirUp;
    R0 := G.Player.Rupees;
    G.Action;
    Check((G.Player.Rupees = R0 + 30) and G.Level.Chests[0].Opened, 'actions: the chest gives 30 rupees');
    G.Action;
    Check(G.Player.Rupees = R0 + 30, 'actions: an open chest gives nothing more');
    { floor items: taken after the first four ticks, offline given at once }
    SetLength(G.Items, 0);
    G.AddItem(G.Player.X + 0.5, G.Player.Y + 1, 5, ItemLife);
    G.Player.Power := 2;
    G.Tick;
    Check(Length(G.Items) = 1, 'items: not taken in the first ticks');
    for I := 1 to 4 do G.Tick;
    Check((Length(G.Items) = 0) and (G.Player.Power = 4), 'items: a heart is taken and gives a heart');
    G.AddItem(10, 10, 0, ItemLife);
    for I := 1 to ItemLife do G.Tick;
    Check(Length(G.Items) = 1, 'items: still there at life 0');
    G.Tick;
    Check(Length(G.Items) = 0, 'items: gone when the life runs out');
    { from the server }
    G.Receive(PLO_ITEMADD, GChar(20) + GChar(20) + GChar(3));
    G.Receive(PLO_ITEMADD, GChar(22) + GChar(20) + GChar(6));
    Check((Length(G.Items) = 1) and (G.Items[0].X = 10) and (G.Items[0].Item = 3),
      'items: ITEMADD makes floor items only');
    G.Receive(PLO_ITEMDEL, GChar(20) + GChar(20));
    Check(Length(G.Items) = 0, 'items: ITEMDEL removes it');
    G.Receive(PLO_BOARDMODIFY, GChar(5) + GChar(6) + GChar(2) + GChar(1) + GShort(100) + GShort(101));
    Check((G.Level.Tile(5, 6) = 100) and (G.Level.Tile(6, 6) = 101), 'board: BOARDMODIFY writes its tiles');
  finally
    G.Free;
  end;
end;

procedure TestCombat;
var
  G: TAdventure;
  P: TServerPlayer;
  I, T0: Integer;
  X0, Y0: Double;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'combat: the built-in level loads');
    G.Tick;
    G.Player.X := 30;
    G.Player.Y := 30;
    { a hit clamps CURPOWER to the maximum first, then takes half hearts }
    G.Player.MaxPower := 3;
    G.Player.Power := 9;
    X0 := G.Player.X;
    G.HurtPlayer(1, 1, 0);
    Check(G.Player.Power = 4, 'combat: power is clamped to the maximum before the hit');
    Check(not G.Hurtable, 'combat: hurt mode after a hit');
    G.HurtPlayer(1, 1, 0);
    Check(G.Player.Power = 4, 'combat: no second hit in hurt mode');
    for I := 1 to 5 do G.Tick;
    Check(Abs(G.Player.X - (X0 + 5)) < 0.01, 'combat: five ticks of knockback, a tile each');
    for I := 1 to 10 do G.Tick;
    Check(Abs(G.Player.X - (X0 + 5)) < 0.01, 'combat: no knockback after the fifth tick');
    for I := 1 to 25 do G.Tick;
    Check(G.Hurtable, 'combat: hurt mode ends after 40 ticks');
    { death, then a direction key respawns at the entry point }
    G.AP := 10;
    G.HurtPlayer(2, 0, 1);
    Check((G.Mode = ModeDead) and (G.Player.Power = 0), 'combat: no hearts left is death');
    G.Player.MaxPower := 5;
    G.Respawn;
    Check((G.Mode = ModeFree) and (G.Player.Power = 6), 'combat: AP under 20 respawns with three hearts');
    G.AP := 30;
    G.Mode := ModeDead;
    G.Respawn;
    Check(G.Player.Power = 10, 'combat: AP under 40 respawns with five hearts');
    G.AP := 50;
    G.Respawn;
    Check(G.Player.Power = 10, 'combat: else all hearts (5)');
    { PLO_HURTPLAYER: known attackers within 10 tiles, players only }
    G.Player.X := 30;
    G.Player.Y := 30;
    P := G.FindOther(7, True);
    P.X := 33;
    P.Y := 30;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(5) +
      GChar(0) + GChar(0) + GChar(0));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER with the NPC field is refused');
    G.Receive(PLO_HURTPLAYER, GShort(8) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(2));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER from an unknown player is refused');
    P.X := 41;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(2));
    Check(G.Player.Power = 10, 'combat: HURTPLAYER from over 10 tiles is refused');
    P.X := 33;
    G.Receive(PLO_HURTPLAYER, GShort(7) + GChar($60 - 32 + 16) + GChar($60 - 32) + GChar(5));
    Check(G.Player.Power = 8, 'combat: HURTPLAYER power is capped at two half hearts');
    for I := 1 to 40 do G.Tick;
    { another player's swing: facing the player, two tiles off }
    G.Player.X := 30;
    G.Player.Y := 30;
    P.X := 28;
    P.Y := 30;
    P.Dir := DirRight;
    P.SwordPower := 2;
    P.Sprite := 6 * 4 + DirRight;
    G.Tick;
    Check(G.Player.Power = 6, 'combat: a swing from another player takes SwordPower / 2 hearts');
    P.Sprite := 0;
    for I := 1 to 40 do G.Tick;
    P.Dir := DirLeft;
    P.Sprite := 6 * 4 + DirLeft;
    G.Tick;
    Check(G.Player.Power = 6, 'combat: a swing facing away misses');
    G.RemoveOther(7);
    { a bomb: laid ahead, goes off after 60 ticks, cuts the bush and hurts }
    G.Player.X := 35;
    G.Player.Y := 22;
    G.Player.Dir := DirDown;
    G.Player.Bombs := 3;
    G.WeaponsOn := True;
    G.LayBomb;
    Check((Length(G.Bombs) = 1) and (G.Player.Bombs = 2), 'bombs: D lays a bomb');
    T0 := G.Player.Power;
    G.Bombs[0].X := 36;
    G.Bombs[0].Y := 24;
    G.Player.Y := 23;
    for I := 1 to 59 do G.Tick;
    Check((Length(G.Bombs) = 1) and (Length(G.Blasts) = 0), 'bombs: the fuse is 60 ticks');
    G.Tick;
    Check((Length(G.Bombs) = 0) and (Length(G.Blasts) = 1), 'bombs: then it explodes');
    Check(G.Level.Tile(36, 26) = G.Arrays.ObjectTile(10, 0, 0, 0), 'bombs: the blast destroys the bush');
    Check(G.Player.Power = T0 - 1, 'bombs: the blast hurts the player half a heart');
    for I := 1 to 12 do G.Tick;
    Check(Length(G.Blasts) = 0, 'bombs: the blast is gone after 11 ticks');
  finally
    G.Free;
  end;
end;

procedure TestSigns;
var
  G: TAdventure;
  I: Integer;

  procedure Press(D: Integer);
  begin
    G.Keys[D] := True;
    G.Tick;
    G.Keys[D] := False;
    G.Tick;
  end;

begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw') and (G.SignAt(24.5, 27.5) = 0) and (G.SignAt(22, 27) = -1),
      'signs: the sign covers its 2 x 2');
    G.Player.X := 23;
    G.Player.Y := 30;
    G.Player.Dir := DirUp;
    for I := 1 to 30 do
    begin
      G.Keys[DirUp] := True;
      G.Tick;
      if G.Reading then Break;
    end;
    Check(G.Reading and (Length(G.SignLines) = 7) and (G.SignLine = 0), 'signs: walking up into a sign reads it');
    G.Keys[DirUp] := True;
    G.Tick;
    Check(G.SignLine = 0, 'signs: the key that opened it does nothing while held');
    G.Keys[DirUp] := False;
    G.Tick;
    Press(DirRight);
    Check(G.SignLine = 3, 'signs: another key turns the page');
    G.AttackKey := True;
    G.Tick;
    Check((G.SignLine = 6) and (G.Mode = ModeFree), 'signs: S turns the page, no swing');
    G.Tick;
    Press(DirUp);
    Check(G.SignLine = 3, 'signs: Up turns back');
    Press(DirDown);
    Check(G.Reading and (G.SignLine = 6), 'signs: the last page');
    Press(DirDown);
    Check(not G.Reading, 'signs: a key on a page that is not full ends reading');
    G.ReadSign('a'#10'b'#10'c');
    G.Tick;
    Press(DirLeft);
    Check(G.Reading and (G.SignLine = 3), 'signs: three lines show an empty second page');
    Press(DirLeft);
    Check(not G.Reading, 'signs: then close');
  finally
    G.Free;
  end;
end;

procedure TestWeapons;
var
  G: TAdventure;
  I, A0, P0: Integer;
begin
  G := TAdventure.Create;
  try
    G.Headless := True;
    Check(G.LoadLevelFile('start.nw'), 'weapons: the built-in level loads');
    G.Tick;
    Check((Length(G.Weapons) = 1) and (G.Weapons[0].Name = 'Bomb') and (G.Selected = 0),
      'weapons: offline the list starts with the bomb');
    G.GiveItem(7);
    Check((Length(G.Weapons) = 2) and (G.Weapons[1].Name = 'Bow') and
      (G.Weapons[1].Image = 'wbowi1.gif') and (G.Selected = 1), 'weapons: the bow is added and selected');
    G.GiveItem(7);
    Check(Length(G.Weapons) = 2, 'weapons: a name already listed is not added again');
    G.AddWeapon('-hidden', '', -1);
    G.SelectWeapon(2);
    Check(G.Selected = 0, 'weapons: selecting skips names starting with -');
    G.RemoveWeapon('-hidden');
    G.Selected := 1;
    G.RemoveWeapon('Bow');
    Check(G.Selected = 0, 'weapons: deleting the last entry selects the new last');
    G.GiveItem(7);
    { the bow: an arrow flies a tile a tick and stops at a wall }
    G.Player.X := 20;
    G.Player.Y := 30;
    G.Player.Dir := DirRight;
    A0 := G.Player.Arrows;
    G.ItemKey := True;
    G.Tick;
    Check((Length(G.Shots) = 1) and (G.Player.Arrows = A0 - 1) and G.Shots[0].Mine,
      'weapons: D with the bow shoots an arrow');
    Check(G.Shots[0].Sprite = 110, 'weapons: the arrow sprite is 107 + direction');
    for I := 1 to 80 do G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: the arrow is gone at the edge or a wall');
    G.Player.Arrows := 0;
    G.ItemKey := True;
    G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: no arrows, no shot');
    { another player's arrow hurts half a heart; a shield facing it stops it }
    P0 := G.Player.Power;
    G.Receive(PLO_ARROWADD, GShort(9) + GChar(Round((G.Player.X - 3) * 2)) +
      GChar(Round((G.Player.Y + 1.5) * 2)) + GChar(DirRight) + GChar(110) + GChar(1));
    Check((Length(G.Shots) = 1) and not G.Shots[0].Mine, 'weapons: ARROWADD makes a shot');
    for I := 1 to 6 do G.Tick;
    Check(G.Player.Power = P0 - 1, 'weapons: an arrow takes half a heart');
    for I := 1 to 40 do G.Tick;
    G.Player.Dir := DirLeft;
    G.Player.ShieldPower := 1;
    P0 := G.Player.Power;
    G.Receive(PLO_ARROWADD, GShort(9) + GChar(Round((G.Player.X - 3) * 2)) +
      GChar(Round((G.Player.Y + 1.5) * 2)) + GChar(DirRight) + GChar(110) + GChar(1));
    for I := 1 to 6 do G.Tick;
    Check(G.Player.Power = P0, 'weapons: a shield facing the arrow stops it');
    for I := 1 to 6 do G.Tick;
    Check(Length(G.Shots) = 0, 'weapons: a power-1 shield knocks it back for three ticks');
    { the server's list }
    G.Receive(PLO_DEFAULTWEAPON, GChar(20));
    Check((G.Weapons[High(G.Weapons)].Name = 'Fireball') and (G.Selected = High(G.Weapons)),
      'weapons: DEFAULTWEAPON adds a built-in weapon');
    G.Receive(PLO_DEFAULTWEAPON, GChar(5));
    Check(G.Weapons[High(G.Weapons)].Name = 'Fireball', 'weapons: a pickup number adds no weapon');
    G.Receive(PLO_NPCWEAPONADD, GS('Lantern') + 'xx');
    Check(G.Weapons[High(G.Weapons)].Name = 'Lantern', 'weapons: NPCWEAPONADD adds by name');
    G.Receive(PLO_NPCWEAPONDEL, 'Lantern');
    Check(G.Weapons[High(G.Weapons)].Name = 'Fireball', 'weapons: NPCWEAPONDEL removes it');
    { the item list: Q opens it, arrows move the selection, other keys close }
    G.Selected := 0;
    A0 := Round(G.Player.X * 2);
    G.ItemListKey := True;
    G.Tick;
    Check(G.ItemListOpen, 'item list: Q opens it');
    G.Tick;
    G.Keys[DirRight] := True;
    G.Tick;
    G.Keys[DirRight] := False;
    Check(G.Selected = 1, 'item list: Right takes the next cell');
    Check(Round(G.Player.X * 2) = A0, 'item list: the player does not walk');
    G.Tick;
    G.AttackKey := True;
    G.Tick;
    Check(not G.ItemListOpen and (G.Mode = ModeFree), 'item list: another game key closes it');
  finally
    G.Free;
  end;
end;

{ What the rebuild carries from 2.31's own program (2.3 is modelled on
  2.31; no 2.3 program survives): the start window's
  pictures (and their sizes in Graal_231.exe), the tutorial levels, and
  the server list's tabs as 2.31 names them. }
procedure TestRealStart;
var
  Art: TRealStartArt;
  D: string;
  L: TAdventureLevel;
  C: Char;
  N, K: Integer;
begin
  Art := TRealStartArt.Create;
  try
    Check(Art.Load(''), 'real start: the compiled-in pictures decode');
    Check((Art.Back1.Width = 577) and (Art.Back1.Height = 416), 'real start: SCREENIMG1 is 577 x 416');
    Check((Art.Back2.Width = 577) and (Art.Back2.Height = 416), 'real start: SCREENIMG2 is 577 x 416');
    Check(Art.Btn[2].Width > Art.Btn[1].Width, 'real start: BUTTON2 is the wide button');
    Check(Art.Text('StartScreen-Button5', 'Editor') = 'Editor', 'real start: no language file, the defaults');
  finally
    Art.Free;
  end;
  Check(ServerTab('P Gold Server') = ltGold, 'tabs: P is Graal Gold');
  Check(ServerTab('3 A 3D Server') = lt3D, 'tabs: 3 is Graal 3D');
  Check(ServerTab('H Someone''s') = ltHosted, 'tabs: H is Hosted');
  Check(ServerTab('Classic One') = ltClassic, 'tabs: no prefix is Classic');
  Check(ServerTab('U Hidden') = ltNone, 'tabs: U is on no tab');
  N := 0;
  for C := 'A' to 'C' do
    for K := 1 to 3 do
      if ResFile('TUTORIAL' + C + IntToStr(K), D) and (Copy(D, 1, 8) = 'GR-V1.03') then Inc(N);
  Check(N = 9, 'tutorial: the nine levels are compiled in, GR-V1.03');
  L := TAdventureLevel.Create;
  try
    Check(ResFile('TUTORIALB2', D) and L.LoadFromString(D),
      'tutorial: b-2 parses');
  finally
    L.Free;
  end;
end;

procedure TestConfig;
var
  C: TGraalConfig;
  F: TStringList;
  Name, D: string;
  G: TGSurface;
begin
  Name := GetTempDir + 'graalconfig-test.txt';
  C := TGraalConfig.Create;
  F := TStringList.Create;
  try
    DeleteFile(Name);
    C.Load(Name);
    Check(C.Bool('automapping') and C.Bool('noudp') and not C.Bool('waitvertical'),
      'graalconfig: 2.31''s defaults with no file');
    Check((C.Str('font') = 'Tempus Sans ITC') and (C.Int('fontsize', 0) = 24) and
      (C.Str('fullscreenmode') = '1024x768'), 'graalconfig: font, size, fullscreen mode');
    F.Add('head=head1.gif');
    F.Add('notoalls=true');
    F.SaveToFile(Name);
    C.Load(Name);
    Check((C.Lines[0] = 'head=head1.gif') and C.Bool('notoalls'),
      'graalconfig: the file''s own lines first, in order');
    C.SetBool('startinfullscreen', True);
    C.SetStr('midivolume', '40');
    Check(C.Save, 'graalconfig: saves');
    C.Load(Name);
    Check(C.Bool('startinfullscreen') and (C.Int('midivolume', 0) = 40) and
      (C.Lines[0] = 'head=head1.gif'), 'graalconfig: what was saved reads back');
  finally
    DeleteFile(Name);
    F.Free;
    C.Free;
  end;
  G := TGSurface.Create(0, 0);
  try
    Check(ResFile('OPENGLYPH', D) and LoadImageData(D, 'OPENGLYPH.bmp', G, False) and
      (G.Width = 15) and (G.Height = 14), 'open url: the Open button''s picture is compiled in');
  finally
    G.Free;
  end;
end;

procedure TestMovie;
const
  Src = 'GANI0002'#10'SPRITE 0 arrow.png 0 0 16 16'#10'FRAMES 60'#10'MOVIE'#10 +
    'ACTOR SPRITE'#10'FRAME 0 sprite #=0,dx=0,dy=0'#10'FRAME 20 dy=-4'#10'ACTOREND'#10 +
    'ACTOR TEXT'#10'FRAME 0 text=Touch to get information,color=FFE080,fontsize=14,shaded=true'#10 +
    'ACTOREND'#10'MOVIEEND'#10'SCRIPT'#10'timeout = 0.05;'#10'SCRIPTEND'#10;
var
  A: TGraalAni;
  K: TGaniKey;
  S: TGraalAniSprite;
begin
  A := TGraalAni.Create;
  try
    Check(A.LoadFromString(Src) and (A.MovieFrames = 60) and (Length(A.Actors) = 2),
      'movie gani: frames and actors read');
    Check(A.FindSprite(0, S) and (S.Sheet = 'arrow.png') and (S.W = 16),
      'movie gani: the sprite table');
    Check(A.ActorAt(0, 30, K) and (Round(K.DY) = -4) and (K.Sprite = 0),
      'movie gani: later key frames change only what they name');
    Check(A.ActorAt(1, 0, K) and A.Actors[1].IsText and
      (K.Text = 'Touch to get information') and (K.Color = $FFE080) and K.Shaded,
      'movie gani: a text actor');
    Check(Trim(A.Script) = 'timeout = 0.05;', 'gani script: the SCRIPT block is kept');
  finally
    A.Free;
  end;
end;

procedure TestHelpForm;
var
  Img, Shown: TGSurface;
  Data: string;
  O: TDfmObj;
  F: TVclForm;
  C: TVclCtl;
  I, Buttons, Mapped, X, Y: Integer;
  Diff: Boolean;
begin
  Check(ResFile('TOPTIONS', Data) and (Copy(Data, 1, 4) = 'TPF0'), 'F1: TOPTIONS is carried');
  Img := TGSurface.Create(1, 1);
  Shown := TGSurface.Create(1, 1);
  try
    Check(RenderOptionsWindow(Data, 'level1.graal', Img, 'EditButton,DebuggerButton') and (Img.Width = 370) and
      (Img.Height = 259), 'F1: the Help window draws at the form''s 370 x 259');
    { 2.31 hides Edit level and Debugger: the two drawings differ }
    RenderOptionsWindow(Data, 'level1.graal', Shown);
    Diff := False;
    for Y := 0 to Img.Height - 1 do
      for X := 0 to Img.Width - 1 do
        if Img.GetPixel(X, Y) <> Shown.GetPixel(X, Y) then Diff := True;
    Check(Diff, 'F1: Edit level and Debugger are hidden');
  finally
    Shown.Free;
    Img.Free;
  end;
  O := GDfmObj.ParseDfm(Data);
  F := TVclForm.Create(O, 'Graal');
  try
    Check(F.Caption = 'Help', 'F1: the window is titled Help');
    Buttons := 0;
    Mapped := 0;
    for I := 0 to F.CtlCount - 1 do
    begin
      C := F.CtlAt(I);
      if C.Kind <> vkButton then Continue;
      Inc(Buttons);
      if OptionsActionOf(C.Obj.Ident('OnClick', '')) <> oaNone then Inc(Mapped);
    end;
    Check((Buttons = 7) and (Mapped = Buttons), 'F1: each of the seven buttons has its action');
  finally
    F.Free;
    O.Free;
  end;
end;

begin
  TestHelpForm;
  Skipped := 0;
  TestRealStart;
  TestConfig;
  TestMovie;
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
  TestBoardModify;
  TestFuzz;
  TestReceiveLimits;
  TestStatus;
  TestActions;
  RunNpcTests(Check, NpcSkipped);
  Inc(Skipped, NpcSkipped);
  RunBaddyTests(Check);
  TestCombat;
  TestSigns;
  TestWeapons;
  WriteLn(Format('%d passed, %d failed, %d skipped', [Passed, Failed, Skipped]));
  if Failed > 0 then Halt(1);
end.
