{ Connector6113: the 6.11 connector login, rebuilt clean-room.

  The 6.11 desktop client does not hold its version token. Before it
  speaks to a game server it fetches conf.gs from a connector, checks the
  reply's RSA-2048 signature over the bare SHA-256 digest of the payload,
  and only then decrypts the payload and runs it as the connector script.
  That script calls, in order:

    setProtocol("EILLLT")   E compression, I counter, LLL length, T type
    sendRaw("<token>")      the eight-byte hello, no header
    setEncryptionOut(...)   the outgoing cipher for what follows

  This unit is that pipeline with three differences from a stock client:

  - The public key is this project's open lab key (SeiPublicModulusHex),
    or one an operator gives with --connector-key, not the stock
    operator's. A stock connector reply does not verify against it, and a
    reply signed for this key is never accepted by a stock client.
  - The token in the project's connector script is the placeholder
    SEI00001 (SeiToken). It is NOT YET USABLE: no game server accepts it
    until the SEI00001 handling lands on the seihai-gserver-v2 side.
  - The payload cipher and the outgoing session cipher are not chosen yet.
    The payload is taken as clear text, and setEncryptionOut is recorded
    by name only, as Frame6113 already does.

  The pieces are separate so the token step is easy to find:
  ParseConfReply, VerifyConfReply, DecryptConfPayload, ParseConnectorScript,
  and RunConnectorSteps (which owns the sendRaw step).

  Sources (read, not copied): protocol/v6-login-token-explained.md,
  protocol/v6x-clients.md "6.11 Mac: the connector", RFC 8017 9.2. }
unit Connector6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Frame6113;

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

  { The project's open lab signing key (RSA-2048, e = 65537), the default
    trust anchor. Both halves are public in common/connector-lab-key, so a
    signature under it shows only that the script arrived unchanged, not
    who wrote it. --connector-key FILE trusts a server operator's key
    instead. }
  SeiPublicModulusHex =
    'CAAF704D5D19A024335740AB2F9B844E12B9134EA9049ABEA6C3491E663F4230' +
    '97FC6F85F70C8E224D00532B784D3999D6E5007442F88CBDA81ECF8C2CC64053' +
    'A604A842CAB8CD90B51D4BE2CA18351370FD977CBD7CE6A9A6BD4FF3F07C1CCC' +
    '4868C1EA259AFFC21E70DE8FCE23008FD67478E4500B5F490C9009678A62AD8C' +
    '8DB7D74B49055A701FBCB3FCBEFC501A8D03CA7BC3B54ADB4E482A106A3AB877' +
    'AB703A413755934B892752C1F1F3B2E934B739688D0A78DED083086E652EB861' +
    'A89CB8A449A982BC2DBE6B36FDFE1F48A1E196ADAC3D81BA0FA0BD5B01247D4A' +
    '7D98EE6494411C30AF6001EB267686A5D512D3DDE13833290972266B05D8D763';

  { TODO(seihai-gserver-v2): the project's payload cipher is not chosen.
    While this is True the verified payload is read as clear script text. }
  PayloadCipherPending = True;

  ConfPath = '/conf.gs';
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

var
  { The modulus VerifyConfReply checks against: the lab key unless
    LoadConnectorKey read another. }
  ConnectorModulusHex: string;

{ Trust a server operator's key instead of the lab key. The file holds the
  RSA-2048 modulus in hex, as `openssl rsa -pubin -noout -modulus` prints
  it (a leading "Modulus=" is allowed). The exponent must be 65537. }
function LoadConnectorKey(const Path: string; out Err: string): Boolean;

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

{ GET conf.gs from 127.0.0.1:Port over plain HTTP/1.0. No p= blob and no
  HTTPS step: neither is needed by this project's connector. }
function FetchConfReply(Port: Word; TimeoutMs: Integer; Idle: TIdleProc;
  out Reply, Err: string): Boolean;

implementation

uses
  SysUtils, Classes, GSocket, Sha6113, Rsa6113;

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
  Result := RsaVerifyBareSha256(ConnectorModulusHex, Signature, Sha256(Payload), Err);
end;

function LoadConnectorKey(const Path: string; out Err: string): Boolean;
var
  L: TStringList;
  Hex: string;
  I: Integer;
begin
  Result := False;
  Err := '';
  if not FileExists(Path) then
  begin
    Err := 'connector key file not found: ' + Path;
    Exit;
  end;
  L := TStringList.Create;
  try
    L.LoadFromFile(Path);
    Hex := UpperCase(Trim(L.Text));
  finally
    L.Free;
  end;
  if Copy(Hex, 1, 8) = 'MODULUS=' then Delete(Hex, 1, 8);
  if Length(Hex) <> 512 then
  begin
    Err := 'connector key must be a 2048-bit modulus in hex (512 digits)';
    Exit;
  end;
  for I := 1 to Length(Hex) do
    if not (Hex[I] in ['0'..'9', 'A'..'F']) then
    begin
      Err := 'connector key holds a character that is not hex';
      Exit;
    end;
  ConnectorModulusHex := Hex;
  Result := True;
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
      'Host: 127.0.0.1' + #13#10 + 'Connection: close' + #13#10#13#10) then
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

initialization
  ConnectorModulusHex := SeiPublicModulusHex;
end.
