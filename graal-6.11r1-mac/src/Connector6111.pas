{ Connector6111: the 6.11 connector login, rebuilt clean-room.

  The 6.11 desktop client does not hold its version token. Before it
  speaks to a game server it fetches conf.gs from a connector, checks the
  reply's RSA-2048 signature over the bare SHA-256 digest of the payload,
  and only then decrypts the payload and runs it as the connector script.
  That script calls, in order:

    setProtocol("EILLLT")   E compression, I counter, LLL length, T type
    sendRaw("<token>")      the eight-byte hello, no header
    setEncryptionOut(...)   the outgoing cipher for what follows

  This unit is that pipeline with three differences from a stock client:

  - The public key is this project's own (SeiPublicModulusHex), not the
    operator's. A stock connector reply does not verify against it, and a
    reply signed for this key is never accepted by a stock client.
  - The token in the project's connector script is the placeholder
    SEI00001 (SeiToken). It is NOT YET USABLE: no game server accepts it
    until the SEI00001 handling lands on the seihai-gserver-v2 side.
  - The payload cipher and the outgoing session cipher are not chosen yet.
    The payload is taken as clear text, and setEncryptionOut is recorded
    by name only, as Frame6111 already does.

  The pieces are separate so the token step is easy to find:
  ParseConfReply, VerifyConfReply, DecryptConfPayload, ParseConnectorScript,
  and RunConnectorSteps (which owns the sendRaw step).

  Sources (read, not copied): protocol/v6-login-token-explained.md,
  protocol/v6x-clients.md "6.11 Mac: the connector", RFC 8017 9.2. }
unit Connector6111;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Frame6111;

const
  { ---------------------------------------------------------------------
    SEI00001 SCAFFOLD. NOT YET USABLE.
    TODO(seihai-gserver-v2): the game server has no SEI00001 handling yet.
    Until it does, a login that sends this token stops after the hello.
    When the gserver-v2 side lands, flip SeiTokenUsable and continue the
    session after the hello instead of stopping.
    --------------------------------------------------------------------- }
  SeiToken = 'SEI00001';
  SeiTokenUsable = False;
  SeiPendingNote = 'SEI00001 is a placeholder token; not yet usable until ' +
    'seihai-gserver-v2 handles it';

  { The header template the 6.11 connector script sets. }
  ConnectorTemplate = 'EILLLT';

  { This project's own connector signing key (RSA-2048, e = 65537). Public
    half only. The private half is held by the project owner, outside the
    repo, and signs the project's conf.gs replies. }
  SeiPublicModulusHex =
    '876470239A4C64545BCCDA0B2739B87970C94F7106022685B95DC51CD7898253' +
    '604E54A150E452FC99122A488E7D0B139BBF60566CAADD2438A72AABD68E2011' +
    '07FA6712A14738414BC7C1E09106DD430255AF19D5F54CE1FC0DD8704CD13157' +
    '6B9E5B1FDEA6D7A150C0E100A7A3FA5A2E452D010FEB1B30AC65C0BDF7466E96' +
    'C9FA24090E5CEB67D2FD81B9578E5B6ED38EDC861E527047BAE2CFD3E717C052' +
    '9014369FEC58A5D74282A02AEFDB542AA6AA74289F236FB9959E798E782FD5C5' +
    '9D068D293BA9EA24E29A20A0F03B8BC30C11497B35C1C2E191568AF3788B24DF' +
    '5E2ECE8D30649335FC671A89CC5DCCC26A7C1195F3DB9D499FBD3CCE64557DE5';

  { TODO(seihai-gserver-v2): the project's payload cipher is not chosen.
    While this is True the verified payload is read as clear script text. }
  PayloadCipherPending = True;

  ConfPath = '/conf.gs';
  { One try plus up to two retries, the retries on the second connector. }
  ConnectorAttempts = 3;
  CouldNotConnect = 'Couldn''t connect to the server';
  { The 6.11 request headers seen in the lab run, minus the Host name. }
  ConnectorUserAgent = 'Graal/6.111';
  MaxConfBytes = 1 shl 20;

type
  TConnectorCall = (ccSetProtocol, ccSendRaw, ccSetEncryptionOut);

  TConnectorStep = record
    Call: TConnectorCall;
    Args: array of string;
  end;

  TConnectorSteps = array of TConnectorStep;

  { Called while FetchConfReply waits, so a single-threaded test can pump
    its loopback connector. }
  TIdleProc = procedure;

  { Where RunConnectorSteps writes the sendRaw bytes. }
  TRawSink = function(const Wire: string): Boolean of object;

{ The reply is two length-prefixed blocks: a four-byte length, the
  signature, a four-byte length, the payload. The note does not give the
  byte order of the length; this project's replies write it big-endian. }
function ParseConfReply(const Reply: string; out Signature, Payload, Err: string): Boolean;
function BuildConfReply(const Signature, Payload: string): string;

{ The signature check. Runs before anything is decrypted or executed. }
function VerifyConfReply(const Signature, Payload: string; out Err: string): Boolean;

{ Pending cipher: returns the payload unchanged. }
function DecryptConfPayload(const Payload: string; out Script, Err: string): Boolean;

{ Reads only the three connector calls, optionally inside one
  onCreated function body. Anything else is refused. }
function ParseConnectorScript(const Script: string; out Steps: TConnectorSteps;
  out Err: string): Boolean;

{ Applies the steps to Proto in order. sendRaw bytes go to Sink. Token
  receives the last sendRaw argument. }
function RunConnectorSteps(const Steps: TConnectorSteps; Proto: TProtocol;
  Sink: TRawSink; out Token, Err: string): Boolean;

{ The project's connector script, with the SEI00001 placeholder. }
function SeiConnectorScript: string;

{ GET conf.gs from 127.0.0.1:Port over plain HTTP/1.0 with the 6.11
  User-Agent and Connection headers. No p= blob and no HTTPS step: neither
  is needed by this project's connector. The read ends when the
  connector closes the link. }
function FetchConfReply(Port: Word; TimeoutMs: Integer; Idle: TIdleProc;
  out Reply, Err: string): Boolean;

implementation

uses
  SysUtils, GSocket, Sha6111, Rsa6111;

function U32BE(N: Cardinal): string;
begin
  Result := Chr((N shr 24) and 255) + Chr((N shr 16) and 255) +
    Chr((N shr 8) and 255) + Chr(N and 255);
end;

function RdU32BE(const S: string; At: Integer): Int64;
begin
  Result := (Int64(Ord(S[At])) shl 24) or (Int64(Ord(S[At + 1])) shl 16) or
    (Int64(Ord(S[At + 2])) shl 8) or Int64(Ord(S[At + 3]));
end;

function BuildConfReply(const Signature, Payload: string): string;
begin
  Result := U32BE(Length(Signature)) + Signature + U32BE(Length(Payload)) + Payload;
end;

function ParseConfReply(const Reply: string; out Signature, Payload, Err: string): Boolean;
var
  SigLen, PayLen: Int64;
begin
  Result := False;
  Signature := '';
  Payload := '';
  Err := '';
  if Length(Reply) < 8 then
  begin
    Err := 'conf.gs reply is too short';
    Exit;
  end;
  SigLen := RdU32BE(Reply, 1);
  if SigLen <> RsaBytes then
  begin
    Err := 'conf.gs signature block is not 256 bytes';
    Exit;
  end;
  if Length(Reply) < 4 + SigLen + 4 then
  begin
    Err := 'conf.gs reply ends inside the signature';
    Exit;
  end;
  PayLen := RdU32BE(Reply, 5 + SigLen);
  if 8 + SigLen + PayLen <> Length(Reply) then
  begin
    Err := 'conf.gs payload length does not match the reply';
    Exit;
  end;
  Signature := Copy(Reply, 5, SigLen);
  Payload := Copy(Reply, 9 + SigLen, PayLen);
  Result := True;
end;

function VerifyConfReply(const Signature, Payload: string; out Err: string): Boolean;
begin
  Result := RsaVerifyBareSha256(SeiPublicModulusHex, Signature, Sha256(Payload), Err);
end;

function DecryptConfPayload(const Payload: string; out Script, Err: string): Boolean;
begin
  Err := '';
  Script := Payload;
  Result := PayloadCipherPending;
  if not Result then
    Err := 'payload cipher not implemented';
end;

function SeiConnectorScript: string;
begin
  Result :=
    'function onCreated() {' + #10 +
    '  setProtocol("' + ConnectorTemplate + '");' + #10 +
    '  // TODO(seihai-gserver-v2): placeholder token, not yet usable' + #10 +
    '  sendRaw("' + SeiToken + '");' + #10 +
    '  // TODO(seihai-gserver-v2): session cipher and key not chosen' + #10 +
    '  setEncryptionOut("SEI-PENDING", "", "");' + #10 +
    '}' + #10;
end;

{ ---- connector script reader ---- }

type
  TScan = record
    S: string;
    I: Integer;
  end;

procedure SkipBlank(var T: TScan);
begin
  while T.I <= Length(T.S) do
  begin
    if T.S[T.I] in [' ', #9, #10, #13] then
      Inc(T.I)
    else if (T.S[T.I] = '/') and (T.I < Length(T.S)) and (T.S[T.I + 1] = '/') then
    begin
      while (T.I <= Length(T.S)) and (T.S[T.I] <> #10) do Inc(T.I);
    end
    else
      Break;
  end;
end;

function TakeChar(var T: TScan; C: Char): Boolean;
begin
  SkipBlank(T);
  Result := (T.I <= Length(T.S)) and (T.S[T.I] = C);
  if Result then Inc(T.I);
end;

function TakeIdent(var T: TScan): string;
var
  Start: Integer;
begin
  SkipBlank(T);
  Start := T.I;
  while (T.I <= Length(T.S)) and (T.S[T.I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(T.I);
  Result := Copy(T.S, Start, T.I - Start);
end;

function TakeString(var T: TScan; out V: string): Boolean;
begin
  V := '';
  Result := False;
  if not TakeChar(T, '"') then Exit;
  while (T.I <= Length(T.S)) and (T.S[T.I] <> '"') do
  begin
    if (T.S[T.I] = '\') and (T.I < Length(T.S)) then Inc(T.I);
    V := V + T.S[T.I];
    Inc(T.I);
  end;
  if T.I > Length(T.S) then Exit;
  Inc(T.I);
  Result := True;
end;

function ParseConnectorScript(const Script: string; out Steps: TConnectorSteps;
  out Err: string): Boolean;
var
  T: TScan;
  Name, Arg: string;
  Depth, N: Integer;
  Step: TConnectorStep;
begin
  Result := False;
  Err := '';
  SetLength(Steps, 0);
  T.S := Script;
  T.I := 1;
  Depth := 0;
  while True do
  begin
    SkipBlank(T);
    if T.I > Length(T.S) then Break;
    if T.S[T.I] = '}' then
    begin
      if Depth = 0 then
      begin
        Err := 'unbalanced } in the connector script';
        Exit;
      end;
      Dec(Depth);
      Inc(T.I);
      Continue;
    end;
    Name := TakeIdent(T);
    if Name = '' then
    begin
      Err := 'unexpected character in the connector script';
      Exit;
    end;
    if Name = 'function' then
    begin
      if (Depth <> 0) or (TakeIdent(T) <> 'onCreated') or not TakeChar(T, '(') or
        not TakeChar(T, ')') or not TakeChar(T, '{') then
      begin
        Err := 'only function onCreated() is read';
        Exit;
      end;
      Inc(Depth);
      Continue;
    end;
    if Name = 'setProtocol' then Step.Call := ccSetProtocol
    else if Name = 'sendRaw' then Step.Call := ccSendRaw
    else if Name = 'setEncryptionOut' then Step.Call := ccSetEncryptionOut
    else
    begin
      Err := 'connector call not supported: ' + Name;
      Exit;
    end;
    SetLength(Step.Args, 0);
    if not TakeChar(T, '(') then
    begin
      Err := Name + ': expected (';
      Exit;
    end;
    if not TakeChar(T, ')') then
    begin
      repeat
        if not TakeString(T, Arg) then
        begin
          Err := Name + ': arguments must be string literals';
          Exit;
        end;
        N := Length(Step.Args);
        SetLength(Step.Args, N + 1);
        Step.Args[N] := Arg;
      until not TakeChar(T, ',');
      if not TakeChar(T, ')') then
      begin
        Err := Name + ': expected )';
        Exit;
      end;
    end;
    TakeChar(T, ';');
    if ((Step.Call = ccSetProtocol) or (Step.Call = ccSendRaw)) and
      (Length(Step.Args) <> 1) then
    begin
      Err := Name + ' takes one argument';
      Exit;
    end;
    if (Step.Call = ccSetEncryptionOut) and
      ((Length(Step.Args) < 1) or (Length(Step.Args) > 3)) then
    begin
      Err := 'setEncryptionOut takes a name and an optional key and initial value';
      Exit;
    end;
    N := Length(Steps);
    SetLength(Steps, N + 1);
    Steps[N] := Step;
  end;
  if Depth <> 0 then
  begin
    Err := 'connector script ends inside onCreated';
    Exit;
  end;
  if Length(Steps) = 0 then
  begin
    Err := 'connector script has no calls';
    Exit;
  end;
  Result := True;
end;

function ArgAt(const Step: TConnectorStep; I: Integer): string;
begin
  if I < Length(Step.Args) then Result := Step.Args[I] else Result := '';
end;

function RunConnectorSteps(const Steps: TConnectorSteps; Proto: TProtocol;
  Sink: TRawSink; out Token, Err: string): Boolean;
var
  I: Integer;
  Wire: string;
begin
  Result := False;
  Token := '';
  Err := '';
  for I := 0 to High(Steps) do
    case Steps[I].Call of
      ccSetProtocol:
        Proto.SetProtocol(Steps[I].Args[0]);
      ccSendRaw:
        begin
          { The version-token step. A stock script puts the operator's
            token here; this project's script puts SeiToken. }
          if not Proto.SendRaw(Steps[I].Args[0], Wire) or (Wire <> Steps[I].Args[0]) then
          begin
            Err := 'sendRaw gained a header';
            Exit;
          end;
          if Assigned(Sink) and not Sink(Wire) then
          begin
            Err := 'sendRaw could not write to the game socket';
            Exit;
          end;
          Token := Steps[I].Args[0];
        end;
      ccSetEncryptionOut:
        Proto.SetEncryptionOut(ArgAt(Steps[I], 0), ArgAt(Steps[I], 1), ArgAt(Steps[I], 2));
    end;
  Result := True;
end;

{ ---- HTTP fetch ---- }

function FetchConfReply(Port: Word; TimeoutMs: Integer; Idle: TIdleProc;
  out Reply, Err: string): Boolean;
var
  Sock: TGSocket;
  Buf, Head: string;
  Start: QWord;
  At: Integer;
begin
  Result := False;
  Reply := '';
  Err := '';
  Buf := '';
  Sock := TGSocket.Create;
  try
    if not Sock.Connect('127.0.0.1', Port) then
    begin
      Err := 'connector: ' + Sock.LastError;
      Exit;
    end;
    if not Sock.Send('GET ' + ConfPath + ' HTTP/1.0' + #13#10 +
      'Host: 127.0.0.1' + #13#10 + 'User-Agent: ' + ConnectorUserAgent + #13#10 +
      'Connection: Keep-Alive' + #13#10#13#10) then
    begin
      Err := 'connector: ' + Sock.LastError;
      Exit;
    end;
    Start := GetTickCount64;
    while Sock.Poll(Buf) do
    begin
      if Length(Buf) > MaxConfBytes then
      begin
        Err := 'connector reply is too large';
        Exit;
      end;
      if GetTickCount64 - Start > QWord(TimeoutMs) then
      begin
        Err := 'connector did not finish its reply';
        Exit;
      end;
      if Assigned(Idle) then Idle;
      Sleep(5);
    end;
  finally
    Sock.Free;
  end;
  At := Pos(#13#10#13#10, Buf);
  if At = 0 then
  begin
    Err := 'connector reply has no HTTP header';
    Exit;
  end;
  Head := Copy(Buf, 1, At - 1);
  if (Copy(Head, 1, 9) <> 'HTTP/1.0 ') and (Copy(Head, 1, 9) <> 'HTTP/1.1 ') or
    (Copy(Head, 10, 3) <> '200') then
  begin
    Err := 'connector did not answer 200';
    Exit;
  end;
  Reply := Copy(Buf, At + 4, MaxInt);
  Result := True;
end;

end.
