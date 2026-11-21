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
  - The project raw SEI00001 route exchanges fresh RSA-wrapped RC4 keys.
    This is project transport only, not stock interoperability or account
    admission; original GNP1905C and classic secure login remain separate.
  - The verified project payload is clear by design. Its parse private
    exponent is supplied at runtime, never embedded in the shipped script.

  The pieces are separate so the token step is easy to find:
  ParseConfReply, VerifyConfReply, DecryptConfPayload, ParseConnectorScript,
  and RunConnectorSteps (which owns the sendRaw step).

  Sources (read, not copied): protocol/v6-login-token-explained.md,
  protocol/v6x-clients.md "6.11 Mac: the connector", RFC 8017 9.2. }
unit Connector6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Frame6113, Project6113;

const
  { Account/game admission remains unavailable; key exchange is separate. }
  SeiToken = 'SEI00001';
  SeiTokenUsable = False;
  SeiPendingNote = 'project transport does not implement account admission';

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

  { Compatibility name: verified project scripts are deliberately clear. }
  PayloadCipherPending = True;

  ConfPath = '/conf.gs';
  MaxConfBytes = 1 shl 20;

type
  TConnectorCall = (ccSetProtocol, ccSendRaw, ccSetEncryptionOut,
    ccGenerateKey, ccRsaEncrypt, ccSendKeyFrame, ccSetParseKey);

  TConnectorStep = record
    Call: TConnectorCall;
    Args: array of string;
    Variables: array of Boolean;
    Target: string;
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

{ Project choice: returns the verified clear payload unchanged. }
function DecryptConfPayload(const Payload: string; out Script, Err: string): Boolean;

{ Reads the bounded project connector calls, simple assignments and named
  variables, optionally inside onCreated. General script execution is refused. }
function ParseConnectorScript(const Script: string; out Steps: TConnectorSteps;
  out Err: string): Boolean;

{ Applies the steps to Proto in order. sendRaw bytes go to Sink. Token
  receives the last sendRaw argument. }
function RunConnectorSteps(const Steps: TConnectorSteps; Proto: TProtocol;
  Sink: TRawSink; out Token, Err: string; Project: TProjectCipher = nil; const ParsePrivateExponent: string = ''): Boolean;

{ The signed project transport script, with a runtime parse-key binding. }
function SeiConnectorScript: string;

{ GET conf.gs from 127.0.0.1:Port over plain HTTP/1.0. No p= blob and no
  HTTPS step: neither is needed by this project's connector. }
function FetchConfReply(Port: Word; TimeoutMs: Integer; Idle: TIdleProc;
  out Reply, Err: string): Boolean;

implementation

uses
  SysUtils, Classes, GSocket, Sha6113, Rsa6113, Cipher6113, GSecCrypto;

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
  Result := RsaVerifyBareSha256(ConnectorModulusHex, Signature, Sha6113.Sha256(Payload), Err);
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
    '  setProtocol("EILLLT");' + #10 +
    '  sendRaw("SEI00001");' + #10 +
    '  key = generate16ByteKey();' + #10 +
    '  wrapped = rsa_encrypt(key, "B07DB79C65109A9C9B2AB5445C8FD5BF861B43DC825E4613F4AA2C115B30031534811DF985DC3AEA7E833FA53F4D94CADF5438589D321BF7D4B25EC452B6426561A4025291CDB0B90C7EF02810CBC4E3261853F69CFF88B103CD9314D170F7FD0A824070DF7650BD1B0F68385444D92FD847F2299AF086CE1FB8585704528BB45DDABD6CA3B201595A99FBD9CBFF76715F0D6E4FBC3393EDD38E97128E7501218D47540FDE293788DD67CC38B6D5EDD505E2C7BC979D02DE1553D780169A2113344FA78FBCDACF46904FAAA905865A2D6653F47AE4D9E3E5CC23236A0032F40CDE03343DA694C3B3627FCF2ECA83F98D263C14AAD4BFB027B3BE49F1BD87395D");' + #10 +
    '  sendKeyFrame(wrapped);' + #10 +
    '  setEncryptionOut("RC4", key, "");' + #10 +
    '  setEncryptionParseKey("EAD52851824753784B0C94BC3F96892320DF885D0FDF09C3DB894BE1673FE7E4C3634ED93AA1F5EEB288F9872E7F4B148C68B3C1FE83CF0215EF481A9DDCE18A40483C996BB09E22D5E3E6649629C7D50B16F94D470D281F7C8E9358CC2669B361C86E5BF339309D20BEBA205A0FC211C3B709813E499DFB9ADC48662D3D236DECE9421A1BA07B4B0E85478AD7678728091ED344BE9686209B3F758CCF359C19C2037AE4A028E93B69E4F6735CC2A58F233C1BCD1EE8DBD00A491D3FD56D34819A14A60B4A4E5C571B7B33028408A7B72D7705818A6769BF699477F3390D2F79E920808132AEAFB66BE6392723DC9DC8062E539E06C8DC9CD65B1B9DB723A289", parsePrivateExponent);' + #10 +
    '}' + #10;
end;

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
    Step.Target := '';
    if TakeChar(T, '=') then
    begin
      Step.Target := Name;
      Name := TakeIdent(T);
      if (Name <> 'generate16ByteKey') and (Name <> 'rsa_encrypt') then
      begin Err := 'unsupported connector assignment'; Exit; end;
    end;
    if Name = 'generate16ByteKey' then Step.Call := ccGenerateKey
    else if Name = 'rsa_encrypt' then Step.Call := ccRsaEncrypt
    else if Name = 'sendKeyFrame' then Step.Call := ccSendKeyFrame
    else if Name = 'setEncryptionParseKey' then Step.Call := ccSetParseKey
    else if Name = 'setProtocol' then Step.Call := ccSetProtocol
    else if Name = 'sendRaw' then Step.Call := ccSendRaw
    else if Name = 'setEncryptionOut' then Step.Call := ccSetEncryptionOut
    else
    begin
      Err := 'connector call not supported: ' + Name;
      Exit;
    end;
    SetLength(Step.Args, 0);
    SetLength(Step.Variables, 0);
    if not TakeChar(T, '(') then
    begin
      Err := Name + ': expected (';
      Exit;
    end;
    if not TakeChar(T, ')') then
    begin
      repeat
        N := Length(Step.Args);
        SetLength(Step.Args, N + 1);
        SetLength(Step.Variables, N + 1);
        Step.Variables[N] := not TakeString(T, Arg);
        if Step.Variables[N] then
        begin
          Arg := TakeIdent(T);
          if (Arg = '') or not (Step.Call in [ccRsaEncrypt, ccSendKeyFrame, ccSetEncryptionOut, ccSetParseKey]) then
          begin Err := Name + ': unsupported variable argument'; Exit; end;
        end;
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
    if ((Step.Call = ccGenerateKey) and ((Step.Target = '') or (Length(Step.Args) <> 0))) or
      ((Step.Call = ccRsaEncrypt) and ((Step.Target = '') or (Length(Step.Args) <> 2))) or
      ((Step.Call = ccSendKeyFrame) and (Length(Step.Args) <> 1)) or
      ((Step.Call = ccSetParseKey) and (Length(Step.Args) <> 2)) then
    begin Err := Name + ': invalid project arguments'; Exit; end;
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
  Sink: TRawSink; out Token, Err: string; Project: TProjectCipher; const ParsePrivateExponent: string): Boolean;
var
  I, J, At: Integer;
  Wire, Pad, Value: string;
  Values: TStringList;
  Step: TConnectorStep;
begin
  Result := False; Token := ''; Err := '';
  for I := 0 to High(Steps) do
    if (Steps[I].Call = ccSetParseKey) and (ParsePrivateExponent = '') then
    begin Err := 'runtime parse private exponent required'; Exit; end;
  Values := TStringList.Create;
  Values.CaseSensitive := True;
  Values.Values['parsePrivateExponent'] := ParsePrivateExponent;
  try
    for I := 0 to High(Steps) do
    begin
      Step := Steps[I];
      { Copy dynamic arguments before resolving; never mutate the parsed script. }
      SetLength(Step.Args, Length(Steps[I].Args));
      for J := 0 to High(Step.Args) do
      begin
        Step.Args[J] := Steps[I].Args[J];
        if (J < Length(Step.Variables)) and Step.Variables[J] then
        begin
          At := Values.IndexOfName(Step.Args[J]);
          if At < 0 then begin Err := 'undefined connector variable'; Exit; end;
          Step.Args[J] := Values.ValueFromIndex[At];
        end;
      end;
      case Step.Call of
        ccSetProtocol: Proto.SetProtocol(Step.Args[0]);
        ccSendRaw:
          begin
            if not Proto.SendRaw(Step.Args[0], Wire) or (Wire <> Step.Args[0]) then
            begin Err := 'sendRaw gained a header'; Exit; end;
            if Assigned(Sink) and not Sink(Wire) then
            begin Err := 'sendRaw could not write to the game socket'; Exit; end;
            Token := Step.Args[0];
          end;
        ccGenerateKey:
          begin
            if not GSecCrypto.RandomBytes(16, Value) then
            begin Err := 'OS entropy unavailable'; Exit; end;
            Values.Values[Step.Target] := Value;
          end;
        ccRsaEncrypt:
          begin
            if (Length(Step.Args[0]) <> 16) or not GSecCrypto.RandomBytes(237, Pad) then
            begin Err := 'invalid key or OS entropy unavailable'; Exit; end;
            Value := RsaWrapType2(Step.Args[1], Step.Args[0], Pad);
            if Length(Value) <> RsaBytes then begin Err := 'RSA key wrap failed'; Exit; end;
            Values.Values[Step.Target] := Value;
          end;
        ccSendKeyFrame:
          begin
            if (Proto.Enc = eoRc4) or (Proto.Counter <> 1) or
              (Length(Step.Args[0]) <> RsaBytes) then
            begin Err := 'key frame must precede encrypted stream'; Exit; end;
            Wire := BuildKeyFrame(Proto.Counter, Step.Args[0]);
            if Assigned(Sink) and not Sink(Wire) then
            begin Err := 'key frame write failed'; Exit; end;
          end;
        ccSetEncryptionOut:
          Proto.SetEncryptionOut(ArgAt(Step, 0), ArgAt(Step, 1), ArgAt(Step, 2));
        ccSetParseKey:
          begin
            if Step.Args[1] = '' then begin Err := 'runtime parse private exponent required'; Exit; end;
            if Project <> nil then Project.SetParseKey(Step.Args[0], Step.Args[1]);
          end;
      end;
    end;
    Result := True;
  finally Values.Free; end;
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
