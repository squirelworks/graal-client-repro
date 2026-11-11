{ Tests for the 6.11r1 Mac rebuild. Framing, the connector login (conf.gs,
  signature, connector script, retries), property storage, and a lab-only
  movement round trip after the SEI00001 hello on 127.0.0.1. No window. }
program Test6111;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSurface in '../../common/GSurface.pas',
  GZlib in '../../common/GZlib.pas',
  GBzip2 in '../../common/GBzip2.pas',
  Frame6111 in '../src/Frame6111.pas',
  Props6111 in '../src/Props6111.pas',
  Level6111 in '../src/Level6111.pas',
  Sha6111 in '../src/Sha6111.pas',
  Rsa6111 in '../src/Rsa6111.pas',
  Connector6111 in '../src/Connector6111.pas',
  Lab6111 in '../src/Lab6111.pas',
  Play6111 in '../src/Play6111.pas';

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
    Check(P.SendRaw(SeiToken, Wire) and (Wire = 'SEI00001') and (Length(Wire) = 8),
      'sendraw writes the eight token bytes with no header');
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
      (Err = 'generation-5 numbered send is not used after the connector hello'),
      'a generation-5 numbered send is not invented as the login');
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
    Check(Gen5Seed = 78121784, 'the generation-5 seed is the shared 6.x seed');
    Check(Step = 388683801, 'LCG step is state times the multiplier plus 1');
    P.SetEncryptionOut('AES', 'k', 'iv');
    Check((P.Enc = eoNamedUnused) and (P.EncName = 'AES'), 'AES is named and not applied');
    Check(P.SendRaw('SEI00001', Wire) and (Wire = 'SEI00001'),
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
  Body: string;
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
  Check(LabDecodeProps(LabEncodeProps('name=x'), Body) and (Body = 'name=x'),
    'lab properties round-trip');
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
    Check(not L.LoadText('GLEVNW01' + #10, Err) and (Pos('not in the 6.x', Err) > 0),
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
  Cands[0] := 'graal-6.11r1-mac/levels/lab-yard.lvl';
  Cands[1] := 'levels/lab-yard.lvl';
  Cands[2] := Dir + '../../graal-6.11r1-mac/levels/lab-yard.lvl';
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

{ ---- connector login (6.11 method, SEI00001 scaffold) ---- }

function LocateConf: string;
var
  Dir: string;
  I: Integer;
  Cands: array[0..3] of string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Cands[0] := 'graal-6.11r1-mac/connector/sei00001-conf.gs';
  Cands[1] := 'connector/sei00001-conf.gs';
  Cands[2] := Dir + '../../graal-6.11r1-mac/connector/sei00001-conf.gs';
  Cands[3] := Dir + '../connector/sei00001-conf.gs';
  for I := 0 to 3 do
    if FileExists(Cands[I]) then
    begin
      Result := Cands[I];
      Exit;
    end;
  Result := '';
end;

function LoadConf: string;
var
  F: TFileStream;
  Path: string;
begin
  Result := '';
  Path := LocateConf;
  if Path = '' then Exit;
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

var
  ConnUnderTest: TLabConnector = nil;

procedure PumpConnector;
begin
  if ConnUnderTest <> nil then ConnUnderTest.Pump;
end;

procedure TestLabRoundTrip;
var
  Srv: TLabServer;
  Con: TLabConnector;
  S: TSession;
  I: Integer;
  Body: string;
begin
  Srv := TLabServer.Create;
  Con := TLabConnector.Create;
  S := TSession.Create;
  try
    Check(S.LoadLevelText('LABLVL1' + #10 + '10 6' + #10 +
      '@.........' + #10 + '..........' + #10 + '..........' + #10 +
      '..........' + #10 + '..........' + #10 + '..........'), 'open yard');
    Check(Srv.Listen(0) and Con.Listen(0), 'lab and connector listeners');
    Con.Reply := LoadConf;
    ConnUnderTest := Con;
    S.ConnectorIdle := PumpConnector;
    S.Lab := True;
    Check(S.ConnectViaConnector([Con.Port], Srv.Port), 'lab connect through the connector');
    Check(S.ConnectorToken = 'SEI00001', 'the lab login sent SEI00001');
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if S.Phase = phLabWorld then Break;
      Sleep(5);
    end;
    Check(S.Phase = phLabWorld, 'lab fixture entered after the SEI00001 hello');
    Check(S.HasOther and (S.OtherId = LabOtherId), 'another entity was received');
    Check(LabDecodeProps(S.Props.Other, Body) and (Pos('name=other', Body) > 0),
      'that entity''s lab properties decoded');
    S.MoveBy(LabStep, 0);
    { The props frame follows the move echo. Loopback can deliver that
      second write on a later pump, so wait for step=2, not only Moves. }
    for I := 1 to 40 do
    begin
      Srv.Pump;
      S.Pump;
      if (Srv.Moves > 0) and (S.MyX = LabStep) and
        (Pos('step=2', S.Props.Other) > 0) then Break;
      Sleep(5);
    end;
    Check(S.MovesSent = 1, 'a move was sent');
    Check((Srv.Moves = 1) and (Srv.PlayerX = LabStep), 'the lab server got the move');
    Check(S.MyX = LabStep, 'the echoed position is the position that was sent');
    Check(Pos('step=2', S.Props.Other) > 0, 'a later property update was stored');
    Check(S.UdpOpens = 0, 'the round trip stayed on TCP');
    Check(S.EndToken = 'clean', 'lab run ends clean');
  finally
    ConnUnderTest := nil;
    S.Free;
    Con.Free;
    Srv.Free;
  end;
end;


procedure TestSha256;
begin
  Check(Sha256Hex('') = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    'SHA-256 of the empty string');
  Check(Sha256Hex('abc') = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    'SHA-256 of abc');
  Check(Sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq') =
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    'SHA-256 of the two-block FIPS vector');
end;

procedure TestConfReply;
var
  Reply, Sig, Payload, Err, Bad: string;
begin
  Reply := LoadConf;
  Check(Reply <> '', 'the signed SEI00001 conf.gs fixture is in the repo');
  if Reply = '' then Exit;
  Check(ParseConfReply(Reply, Sig, Payload, Err), 'conf.gs splits into signature and payload');
  Check(Length(Sig) = 256, 'the signature block is 256 bytes');
  Check(Length(Reply) = 4 + 256 + 4 + Length(Payload), 'reply is 4 + 256 + 4 + payload');
  Check(Payload = SeiConnectorScript, 'the fixture payload is the project connector script');
  Check(VerifyConfReply(Sig, Payload, Err), 'the project key verifies the fixture: ' + Err);
  Bad := Payload;
  Bad[Pos('SEI00001', Bad) + 7] := '2';
  Check(not VerifyConfReply(Sig, Bad, Err) and (Pos('digest', Err) > 0),
    'a changed token fails the digest check');
  Bad := Sig;
  Bad[100] := Chr(Ord(Bad[100]) xor 1);
  Check(not VerifyConfReply(Bad, Payload, Err), 'a changed signature is refused');
  Check(not ParseConfReply(Copy(Reply, 1, Length(Reply) - 1), Sig, Payload, Err),
    'a short reply is refused');
  Check(BuildConfReply(Copy(Reply, 5, 256), SeiConnectorScript) = Reply,
    'BuildConfReply writes big-endian lengths');
end;

procedure TestConnectorScript;
var
  Steps: TConnectorSteps;
  Err, Token: string;
  P: TProtocol;
begin
  Check(SeiToken = 'SEI00001', 'the scaffold token is SEI00001');
  Check(not SeiTokenUsable, 'SEI00001 is marked not yet usable');
  Check(ParseConnectorScript(SeiConnectorScript, Steps, Err), 'the project script parses: ' + Err);
  Check((Length(Steps) = 3) and (Steps[0].Call = ccSetProtocol) and
    (Steps[1].Call = ccSendRaw) and (Steps[2].Call = ccSetEncryptionOut),
    'order is setProtocol, sendRaw, setEncryptionOut');
  Check(Steps[0].Args[0] = 'EILLLT', 'the template is EILLLT');
  Check(Steps[1].Args[0] = SeiToken, 'sendRaw carries SEI00001');
  P := TProtocol.Create;
  try
    Check(RunConnectorSteps(Steps, P, nil, Token, Err), 'the steps run: ' + Err);
    Check(Token = 'SEI00001', 'the token step reports SEI00001');
    Check(not P.OnGen5 and (P.HeaderLen = 6), 'EILLLT leaves generation-5 for a six-byte header');
    Check((P.FE.At = 0) and (P.FE.Width = 1) and (P.FI.At = 1) and (P.FI.Width = 1) and
      (P.FL.At = 2) and (P.FL.Width = 3) and (P.FT.At = 5) and (P.FT.Width = 1),
      'EILLLT is E at 0, I at 1, LLL at 2, T at 5');
    Check(P.Counter = 1, 'sendRaw did not advance the counter');
    Check(P.Enc = eoCleared, 'the pending setEncryptionOut name selects no cipher');
  finally
    P.Free;
  end;
  Check(not ParseConnectorScript('setProtocol("EILLLT"); exec("x");', Steps, Err) and
    (Pos('exec', Err) > 0), 'any other call is refused');
  Check(not ParseConnectorScript('sendRaw(SEI00001);', Steps, Err), 'arguments must be strings');
  Check(not ParseConnectorScript('function onCreated() { sendRaw("A");', Steps, Err),
    'an unclosed onCreated is refused');
end;

procedure TestConnectorLogin;
var
  Con: TLabConnector;
  Srv: TLabServer;
  S: TSession;
  I: Integer;
begin
  Con := TLabConnector.Create;
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Con.Reply := LoadConf;
    Check(Con.Listen(0) and Srv.Listen(0), 'connector and game listeners on 127.0.0.1');
    ConnUnderTest := Con;
    S.ConnectorIdle := PumpConnector;
    Srv.Fixture := False;
    Check(S.ConnectViaConnector([Con.Port], Srv.Port), 'connector login runs: ' + S.Err);
    Check(S.ConnectorTries = 1, 'the first connector answered');
    Check(Con.Requests = 1, 'one conf.gs request');
    Check(Pos('GET /conf.gs HTTP/1.0', Con.LastRequest) = 1, 'plain GET /conf.gs, no p= blob');
    Check(Pos('User-Agent: Graal/6.111', Con.LastHeaders) > 0, 'the request says Graal/6.111');
    Check(Pos('Connection: Keep-Alive', Con.LastHeaders) > 0, 'the request asks for keep-alive');
    Check(S.Phase = phSeiPending, 'the client stops after the SEI00001 hello');
    Check(S.ConnectorToken = 'SEI00001', 'the token came from the connector script');
    Check(S.ConnectorSteps = 3, 'three connector steps ran');
    Check(S.UdpOpens = 0, 'the connector path opens no datagram socket');
    for I := 1 to 50 do
    begin
      Srv.Pump;
      if Srv.GotHello then Break;
      Sleep(5);
    end;
    Check(Srv.GotHello and (Srv.Hello = 'SEI00001'), 'the game side saw SEI00001 first');
    Check(Srv.AfterSei = '', 'nothing follows the hello yet');
    Check(Pos('not yet usable', Logs.Text) > 0, 'the log says SEI00001 is not yet usable');
    Check(Pos('signature verified', Logs.Text) > 0, 'the log shows the signature check');
    Check(S.EndToken = 'sei-pending', 'the summary ends sei-pending');
  finally
    ConnUnderTest := nil;
    S.Free;
    Srv.Free;
    Con.Free;
  end;
end;

procedure TestConnectorRefusesTamper;
var
  Con: TLabConnector;
  Srv: TLabServer;
  S: TSession;
  Reply: string;
begin
  Con := TLabConnector.Create;
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Reply := LoadConf;
    if Reply <> '' then
      Reply[Length(Reply) - 3] := 'X';
    Con.Reply := Reply;
    Check(Con.Listen(0) and Srv.Listen(0), 'tamper listeners on 127.0.0.1');
    ConnUnderTest := Con;
    S.ConnectorIdle := PumpConnector;
    Check(not S.ConnectViaConnector([Con.Port], Srv.Port), 'a tampered reply is refused');
    Check((S.Phase = phError) and (Pos('refused', S.Err) > 0), 'refused before any script runs');
    Check(S.ConnectorSteps = 0, 'no connector step ran');
    Srv.Pump;
    Check(not Srv.GotHello, 'the game side saw nothing');
  finally
    ConnUnderTest := nil;
    S.Free;
    Srv.Free;
    Con.Free;
  end;
end;

procedure TestRetries;
var
  Good, Dead: TLabConnector;
  Srv: TLabServer;
  S: TSession;
  DeadPort: Word;
begin
  { A port that refuses: listen, note the port, close it. }
  Dead := TLabConnector.Create;
  Good := TLabConnector.Create;
  Srv := TLabServer.Create;
  S := TSession.Create;
  try
    Check(Dead.Listen(0), 'scratch listener');
    DeadPort := Dead.Port;
    Dead.Close;
    Good.Reply := LoadConf;
    Check(Good.Listen(0) and Srv.Listen(0), 'second connector and game listener');
    Srv.Fixture := False;
    ConnUnderTest := Good;
    S.ConnectorIdle := PumpConnector;
    Check(S.ConnectViaConnector([DeadPort, Good.Port], Srv.Port),
      'the retry on the second connector logs in: ' + S.Err);
    Check(S.ConnectorTries = 2, 'one failed try, then the second connector');
    Check(S.ConnectorToken = 'SEI00001', 'the retry still sends SEI00001');
    S.Free;
    S := TSession.Create;
    Check(not S.ConnectViaConnector([DeadPort, DeadPort], Srv.Port),
      'three failed tries give up');
    Check(S.ConnectorTries = ConnectorAttempts, 'one try plus two retries');
    Check(S.Err = CouldNotConnect, 'the warning is the 6.11 one');
  finally
    ConnUnderTest := nil;
    S.Free;
    Srv.Free;
    Good.Free;
    Dead.Free;
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
    TestLevelAndCollision;
    TestYardFile;
    TestLabRoundTrip;
    TestRetries;
    TestSha256;
    TestConfReply;
    TestConnectorScript;
    TestConnectorLogin;
    TestConnectorRefusesTamper;
  finally
    SessionLog := nil;
    Logs.Free;
    Logs := nil;
  end;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then Halt(1);
end.
