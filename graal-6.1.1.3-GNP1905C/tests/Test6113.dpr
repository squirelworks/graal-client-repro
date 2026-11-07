{ Tests for the 6.1.1.3 rebuild. Framing, login state, property storage,
  and a lab-only movement round trip on 127.0.0.1. No window. }
program Test6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GZlib in '../../common/GZlib.pas',
  GBzip2 in '../../common/GBzip2.pas',
  Frame6113 in '../src/Frame6113.pas',
  Props6113 in '../src/Props6113.pas',
  Gs26113 in '../src/Gs26113.pas',
  Level6113 in '../src/Level6113.pas',
  Lab6113 in '../src/Lab6113.pas',
  Play6113 in '../src/Play6113.pas';

var
  Passed, Failed: Integer;
  Logs: TStringList;

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

procedure Capture(const S: string);
begin
  if Logs <> nil then Logs.Add(S);
end;

procedure TestHelloAndRaw;
var
  P: TProtocol;
  Wire: string;
begin
  P := TProtocol.Create;
  try
    Check(P.OnGen5 and (P.Mode = 3) and (P.Enc = eoDefaultLcg), 'starts on generation-5, mode 3');
    Check(P.LcgState = Gen5Seed, 'LCG state is the documented seed');
    Check(P.SendRaw(ClearHello, Wire) and (Wire = 'GNP1905C') and (Length(Wire) = 8),
      'sendraw writes GNP1905C with no header');
    Check(P.Counter = 1, 'sendraw does not advance the counter');
    Check(P.Flushes = 0, 'eight hello bytes do not flush');
    Check(P.SendRaw(StringOfChar('A', 4096), Wire) and (Length(Wire) = 4096) and (P.Flushes = 1),
      'a 4096-byte generation-5 buffer flushes');
  finally
    P.Free;
  end;
end;

procedure TestRefusals;
var
  P: TProtocol;
  Wire, Err: string;
begin
  P := TProtocol.Create;
  try
    Check(P.Gen5Reject(1, 'a' + #10 + 'b') = IllegalChars, 'newline is refused');
    Check(P.Gen5Reject(93, 'a' + #10 + 'b') = Id50Gap, 'id 93 skips the newline refusal');
    Check(P.Gen5Reject(163, 'ok') = Id50Gap, 'id 163 needs the unrecovered id 50 prefix');
    Check(not P.SendData(1, 'a' + #10 + 'b', Wire, Err) and (Err = IllegalChars),
      'numbered generation-5 send with a newline is refused');
    Check(not P.SendData(1, 'hi', Wire, Err) and
      (Err = 'generation-5 numbered send is not used after the clear hello'),
      'a clear generation-5 numbered send is not invented as the hello');
    P.SetProtocol('T');
    Check(not P.SendData(1, 'hi', Wire, Err) and (Err = CannotSend),
      'numbered send without L is refused');
  finally
    P.Free;
  end;
end;

procedure TestHeaderOrder;
var
  P: TProtocol;
  Wire, Err, Body: string;
begin
  P := TProtocol.Create;
  try
    P.SetProtocol('TIEL');
    Check(P.SendData(4, 'ab', Wire, Err) and (Err = ''), 'first numbered send');
    Check(Wire = #4 + #1 + #0 + #6 + 'ab', 'T then I then E then L, then the body');
    Check(P.SendData(4, 'ab', Wire, Err) and (Wire[2] = #2), 'I increases by one');
    P.SetProtocol('T.L');
    Check(P.SendData(4, 'Z', Wire, Err) and (Wire = #4 + #0 + #4 + 'Z'),
      'a template byte that is not I L T or E stays zero');
    P.SetProtocol('TIELLL');
    SetLength(Body, 273);
    FillChar(Body[1], 273, Ord('x'));
    Check(P.SendData(1, Body, Wire, Err), 'six-byte test template send');
    Check(HeaderPlusBody(6, 273) = 279, 'L value is header length plus body length');
    Check((Ord(Wire[4]) = 0) and (Ord(Wire[5]) = 1) and (Ord(Wire[6]) = $17),
      'that 279 is written big-endian in L');
    Check(Copy(Wire, 1, 6) <> #$01#$02#$00#$01#$17#$FD,
      'the test template is not the capture header');
  finally
    P.Free;
  end;
end;

procedure TestCompression;
var
  P: TProtocol;
  Wire, Err, Body, Plain: string;
begin
  P := TProtocol.Create;
  try
    P.SetProtocol('TIEL');
    P.CompressId := 7;
    Body := StringOfChar('A', 48);
    Check(P.SendData(7, Body, Wire, Err), 'zlib send');
    Check(Ord(Wire[3]) = 1, 'E is 1 at 48 bytes for the compression id');
    Check(ZDecompress(Copy(Wire, 5, MaxInt), Plain) and (Plain = Body), 'E 1 round-trips zlib');
    Check(not P.SendData(8, Body, Wire, Err) or (Ord(Wire[3]) = 0), 'a different id stays uncompressed');
    P.Free;
    P := TProtocol.Create;
    P.SetProtocol('TIELL');
    P.CompressId := 7;
    P.BzipGlobal := True;
    P.BzipConn := True;
    Body := StringOfChar('A', 4096);
    Check(P.SendData(7, Body, Wire, Err), 'bzip2 send');
    Check(Ord(Wire[3]) = 2, 'E is 2 at 4096 bytes when both flags are set');
    Check(Copy(Wire, 6, 4) = 'BZh5', 'E 2 is bzip2 with block-size digit 5');
    Check(BZ2Decompress(Copy(Wire, 6, MaxInt), Plain, 20000) and (Plain = Body),
      'E 2 round-trips');
    P.BzipGlobal := False;
    Check(P.SendData(7, Body, Wire, Err) and (Ord(Wire[3]) = 1),
      '4096 bytes without the bzip flag still use zlib');
    Check(P.SendData(9, Body, Wire, Err) and (Ord(Wire[3]) = 0),
      'a different id at 4096 bytes stays uncompressed');
    P.BzipGlobal := True;
    P.ForceCompressFail := True;
    Check(P.SendData(7, Body, Wire, Err) and (Ord(Wire[3]) = 0) and
      (Copy(Wire, 6, 4) = 'AAAA'), 'a failed compressor is sent as E 0');
  finally
    P.Free;
  end;
end;

procedure TestCipherChoice;
var
  P, Q: TProtocol;
  Wire: string;
  Step: Cardinal;
begin
  P := TProtocol.Create;
  try
    Step := P.LcgStepPlusOne;
    Check(Step = 460380825, 'LCG step is state times the multiplier plus 1');
    P.SetEncryptionOut('AES', 'k', 'iv');
    Check((P.Enc = eoNamedUnused) and (P.EncName = 'AES'), 'AES is named and not applied');
    Check(P.SendRaw('GNP1905C', Wire) and (Wire = 'GNP1905C'),
      'a named cipher does not change sendraw');
    P.SetEncryptionOut('nope', '', '');
    Check((P.Enc = eoCleared) and (P.LcgState = Gen5Seed) and (P.Mode = 3),
      'any other name clears back to the LCG default');
  finally
    P.Free;
  end;
  P := TProtocol.Create;
  Q := TProtocol.Create;
  try
    P.LcgStepPlusOne;
    Q.LcgStepPlusKey(3);
    Check(P.LcgState <> Q.LcgState, 'the hello note adds the key; the wire note adds 1');
  finally
    Q.Free;
    P.Free;
  end;
end;

procedure TestProps;
var
  Bag: TPropBag;
  Id: Integer;
  Wire: Byte;
  Err, Text: string;
  N: Integer;
begin
  Bag := TPropBag.Create;
  try
    Bag.SetPlayer('player-bytes');
    Bag.SetOther('other-bytes');
    Bag.SetNpc('npc-bytes');
    Bag.SetBaddy('baddy-bytes');
    Check((Bag.Player = 'player-bytes') and (Bag.Other = 'other-bytes') and
      (Bag.Npc = 'npc-bytes') and (Bag.Baddy = 'baddy-bytes'),
      'the four setters store the string and do not switch on an id');
  finally
    Bag.Free;
  end;
  N := 0;
  for Id := 0 to 83 do
    if PlayerIdHasCase(Id) then Inc(N);
  Check(N = 72, 'player encoder has 72 cases in 0..83');
  Check(not PlayerIdHasCase(3) and not PlayerIdHasCase(83) and PlayerIdHasCase(0),
    'the twelve missing player ids include 3 and 83');
  Check(PropIdPrefix(0, True, Wire, Err) and (Wire = 32) and (Err = ''),
    'a player id with a case is stored plus 32');
  Check(not PropIdPrefix(3, False, Wire, Err) and (Err = 'no encoder case'),
    'an id without a case does not invent a value');
  Check(BaddyIdHasCase(0) and BaddyIdHasCase(10) and not BaddyIdHasCase(11),
    'baddy ids 0 through 10 have cases');
  Check(not NpcIdHasCase(1), 'no numbered NPC property table');
  Check(ParseOnToall(Chr(33) + Chr(34) + Chr(35) + 'abc', Id, Text) and
    (Id = 130) and (Text = 'abc'), 'onToall reads the id and the text');
  Check(not ParseOnToall('ab', Id, Text), 'onToall ignores a body of two bytes');
  Check(not ParseOnToall(#32 + #32 + #31 + 'x', Id, Text),
    'onToall ignores a third byte below 32');
end;

procedure TestGs2;
var
  I, Present: Integer;
begin
  Check(not GrescrAccepted('GRESCR0'), 'a code buffer shorter than eight bytes is rejected');
  Check(not GrescrAccepted('XXXXXXXX'), 'the magic is GRESCR01');
  Check(GrescrAccepted('GRESCR01'), 'eight magic bytes are accepted');
  Check(GrescrCrcStart = 9, 'the CRC covers the bytes after the eight');
  Present := 0;
  for I := 11 to 242 do
    if Gs2CaseOf(I) = gscPresent then Inc(Present);
  Check(Present = 2 + 42, 'named present cases are 54, 121 and 201..242');
  Check(Gs2CaseOf(48) = gscAbsent, 'case 48 is absent');
  Check(Gs2CaseOf(49) = gscAbsent, 'case 49 is absent');
  Check(Gs2CaseOf(200) = gscAbsent, 'case 200 is absent');
  Check(Gs2CaseOf(11) = gscUnlisted, 'unnamed span cases stay unlisted');
  Check(Gs2CaseOf(10) = gscOutside, 'below 11 is outside the span');
  Check(Gs2CaseTotal = 152, 'the note''s case total is 152');
end;

procedure TestLevelAndCollision;
var
  S: TSession;
  Surf: TGSurface;
  Err: string;
  L: TLabLevel;
begin
  L := TLabLevel.Create;
  try
    Check(not L.LoadText('GR-V1.05' + #10 + 'no body', Err) and
      (Pos('not recovered', Err) > 0), 'GR-V1.05 body is not invented');
    Check(not L.LoadText('GLEVNW01' + #10, Err) and (Pos('not in the unpacked', Err) > 0),
      'GLEVNW01 is not this image''s level magic');
  finally
    L.Free;
  end;
  S := TSession.Create;
  Surf := TGSurface.Create(ViewW, ViewH);
  try
    Check(S.LoadLevelText('LABLVL1' + #10 + '5 1' + #10 + '.#@..'), 'adjacent-wall level');
    Check(S.MyX = 32, 'start is the @ cell');
    S.MoveBy(-LabStep, 0);
    Check(S.MyX = 32, 'a step into the wall does not move');
    S.MoveBy(LabStep, 0);
    Check(S.MyX = 36, 'a step onto floor moves');
    S.Free;
    S := TSession.Create;
    Check(S.LoadLevelText('LABLVL1' + #10 + '40 3' + #10 +
      StringOfChar('.', 30) + '@' + StringOfChar('.', 9) + #10 +
      StringOfChar('.', 40) + #10 + StringOfChar('.', 40)), 'wide level');
    Check(S.MyX = 30 * 16, 'wide start column');
    Check(S.CamX = 368, 'camera follows and stays inside the level');
    S.Free;
    S := TSession.Create;
    Check(S.LoadLevelText('LABLVL1' + #10 + '4 2' + #10 + '@.#.' + #10 + '....'),
      'render level');
    S.Render(Surf);
    Check(Surf.GetPixel(1, 1) = ColPlayer, 'the local player is drawn');
    Check(Surf.GetPixel(16, 0) = ColFloor, 'floor is drawn');
    Check(Surf.GetPixel(32, 0) = ColWall, 'a wall is drawn');
    Check(S.UdpOpens = 0, 'drawing does not open a datagram socket');
  finally
    Surf.Free;
    S.Free;
  end;
end;

function LocateYard: string;
var
  Dir: string;
  I: Integer;
  Cands: array[0..3] of string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Cands[0] := 'graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl';
  Cands[1] := 'levels/lab-yard.lvl';
  Cands[2] := Dir + '../../graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl';
  Cands[3] := Dir + '../levels/lab-yard.lvl';
  for I := 0 to 3 do
    if FileExists(Cands[I]) then
    begin
      Result := Cands[I];
      Exit;
    end;
  Result := '';
end;

procedure TestYardFile;
var
  S: TSession;
  Path: string;
begin
  Path := LocateYard;
  Check(Path <> '', 'lab-yard.lvl is in the repo');
  if Path = '' then Exit;
  S := TSession.Create;
  try
    Check(S.LoadLevelFile(Path), 'lab-yard.lvl loads: ' + Path);
    Check((S.MyX = 11 * 16) and (S.MyY = 6 * 16), 'yard start is the @ cell');
    Check(S.HasOther and (S.OtherX = 22 * 16), 'yard marker is lab-only local art');
  finally
    S.Free;
  end;
end;

procedure TestClearStop;
var
  Srv: TLabServer;
  S: TSession;
  I: Integer;
begin
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Check(Srv.Listen(0), 'lab listener on 127.0.0.1');
    S.Lab := False;
    Check(S.ConnectTo('127.0.0.1', Srv.Port), 'tcp connect');
    Check(S.Phase = phStoppedClear, 'without --lab the client stops at the clear hello');
    Check(S.UdpOpens = 0, 'connect path opens no datagram socket');
    for I := 1 to 30 do
    begin
      Srv.Pump;
      S.Pump;
      if S.BytesAfterHello > 0 then Break;
      Sleep(5);
    end;
    Check(Srv.GotHello, 'the server saw GNP1905C');
    Check(S.BytesAfterHello > 0, 'later server bytes were counted');
    Check(S.Props.Other = '', 'those bytes were not decoded as properties');
    Check(Pos('not decoded', Logs.Text) > 0, 'the log says the cipher was not identified');
    Check(Pos('GNP1905C', Logs.Text) = 0, 'the log does not echo a secret-looking token body');
  finally
    S.Free;
    Srv.Free;
  end;
end;

procedure TestLabRoundTrip;
var
  Srv: TLabServer;
  S: TSession;
  I: Integer;
  Body: string;
begin
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Check(S.LoadLevelText('LABLVL1' + #10 + '10 6' + #10 +
      '@.........' + #10 + '..........' + #10 + '..........' + #10 +
      '..........' + #10 + '..........' + #10 + '..........'), 'open yard');
    Check(Srv.Listen(0), 'second lab listener');
    S.Lab := True;
    Check(S.ConnectTo('127.0.0.1', Srv.Port), 'lab connect');
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if S.Phase = phLabWorld then Break;
      Sleep(5);
    end;
    Check(S.Phase = phLabWorld, 'lab fixture entered after the clear hello');
    Check(S.HasOther and (S.OtherId = LabOtherId), 'another entity was received');
    Check(LabDecodeProps(S.Props.Other, Body) and (Pos('name=other', Body) > 0),
      'that entity''s lab properties decoded');
    S.MoveBy(LabStep, 0);
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if Srv.Moves > 0 then Break;
      Sleep(5);
    end;
    Check(S.MovesSent = 1, 'a move was sent');
    Check((Srv.Moves = 1) and (Srv.PlayerX = LabStep), 'the lab server got the move');
    Check(S.MyX = LabStep, 'the echoed position is the position that was sent');
    Check(Pos('step=2', S.Props.Other) > 0, 'a later property update was stored');
    Check(S.UdpOpens = 0, 'the round trip stayed on TCP');
    Check(S.EndToken = 'clean', 'lab run ends clean');
  finally
    S.Free;
    Srv.Free;
  end;
end;

procedure TestRejectHost;
var
  S: TSession;
begin
  S := TSession.Create;
  try
    Check(not S.ConnectTo('other-host', 14900), 'a non-loopback host is refused');
    Check(S.Phase = phError, 'the refusal is an error state');
  finally
    S.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  Logs := TStringList.Create;
  SessionLog := Capture;
  try
    TestHelloAndRaw;
    TestRefusals;
    TestHeaderOrder;
    TestCompression;
    TestCipherChoice;
    TestProps;
    TestGs2;
    TestLevelAndCollision;
    TestYardFile;
    TestClearStop;
    TestLabRoundTrip;
    TestRejectHost;
  finally
    SessionLog := nil;
    Logs.Free;
    Logs := nil;
  end;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then Halt(1);
end.
