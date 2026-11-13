{ GSecLogin: the client side of the Seihai secure login, version token
  SEI00001 (Seihai documentation/secure-login.md, revision 1).

  This is not part of any Graal client. A rebuild that talks to a server
  can first send C1 (its classic login prefix, SEI00001, its own token and
  a fresh X25519 key) in a plain zlib frame. A Seihai server answers S1
  (its X25519 key, its Ed25519 key and a signature over C1); the client
  checks the signature and the pinned key, derives one key with HKDF and
  sends C2: the account, the password and the rest of the classic login
  tail sealed with ChaCha20-Poly1305. After C2 the session goes on in the
  build's own coding. A server that does not know the token refuses it, and
  the client then logs in the original way (mode auto).

  Modes (graal-client-repro #148):
    off       the original login, byte for byte (side-by-side fidelity runs)
    auto      try SEI00001; on a refusal, a close or no answer, reconnect
              and log in the original way. A server whose key is pinned is
              never logged in to in the clear again (the sticky rule): the
              client stops and says so.
    required  never send a password in the clear.

  The pins and the refused-server list are shared by every rebuild of the
  player, in one per-user folder (PinDir): known_servers.txt holds
  "host:port key" lines in the same form as Seihai's own file, and
  refused_servers.txt the host:port of servers that refused the token, so
  auto skips the probe there next time (unless the server is pinned). }
unit GSecLogin;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  SeiToken = 'SEI00001';
  { the longest tail a C2 seals }
  SeiMaxTail = 1024;
  { how long auto and required wait for S1 before they give up }
  SeiWaitMs = 5000;

type
  TSecMode = (smOff, smAuto, smRequired);
  TPinResult = (prUnknown, prMatches, prMismatch);
  { Where one connection's secure login stands. }
  TSecState = (ssNone, ssAwaitS1, ssDone, ssRefused, ssNoAnswer, ssFailed);

  { One handshake, C1 to C2. }
  TSecHandshake = class
  private
    FSecret: string;
    FHello: string;
    FTh, FKey: string;
    FServerKey: string;
    FError: string;
  public
    { False if the inner token is not 8 bytes or no random bytes could be
      read (Error says which). Prefix is the client type and key byte for a
      game server (gen 2: the type alone), id 7 and the key byte for a list
      server; Suffix is the list name for a list server, else empty. }
    function Start(const Prefix, Inner, Suffix: string): Boolean;
    { Start with a given X25519 secret (tests). }
    function StartWith(const Prefix, Inner, Suffix, Secret: string): Boolean;
    { C1 without its line feed. }
    property Hello: string read FHello;
    { Checks S1 (one line, line feed optional): the token, the lengths, the
      signature, and a non-zero shared secret. The pin is the caller's. }
    function Finish(const S1: string): Boolean;
    { C2 without its line feed: SEI00001 and the sealed tail, base64. }
    function Seal(const Tail: string): string;
    property ServerKey: string read FServerKey;
    property Error: string read FError;
  end;

{ True when Line is S1 (it starts with the token). }
function IsServerHello(const Line: string): Boolean;

function ParseSecMode(const S: string; out Mode: TSecMode): Boolean;
function SecModeName(Mode: TSecMode): string;

{ SHA256: and the unpadded base64 of the key's SHA-256. }
function KeyFingerprint(const Key: string): string;
function EncodeKey(const Key: string): string;
function DecodeKey(const Text: string; out Key: string): Boolean;

{ The shared per-user folder: GRAAL_SECURE_DIR if set, else
  %APPDATA%\graal-delphi on Windows, $XDG_CONFIG_HOME/graal-delphi or
  ~/.config/graal-delphi elsewhere. }
function PinDir: string;
var
  { set by tests: used in place of PinDir's search when not empty }
  PinDirOverride: string = '';

function PinFile: string;
function RefusedFile: string;
function PinCheck(const Server, Key: string; out Pinned: string): TPinResult;
function IsPinned(const Server: string): Boolean;
procedure PinAppend(const Server, Key: string);
function WasRefused(const Server: string): Boolean;
procedure RememberRefused(const Server: string);

{ The player's setting: GRAAL_SECURE_LOGIN if set, else the first word of
  secure_login.txt in PinDir, else off (the original login). SetSecure
  (the --secure-login and --server-key options) overrides both. }
function ConfiguredSecMode: TSecMode;
function ConfiguredServerKey: string;
procedure SetSecure(Mode: TSecMode; const Key: string);
{ Back to the player's setting (tests). }
procedure ClearSecure;

{ Whether to send C1 to Server in this mode. }
function ShouldProbe(Mode: TSecMode; const Server: string): Boolean;
{ Whether a failed probe may fall back to the original login. }
function MayFallBack(Mode: TSecMode; const Server: string): Boolean;

{ The whole client check after S1: the handshake, then the pin (GivenKey,
  when not empty, is the only key trusted and the file is left alone).
  Logs the trust-on-first-use line through Note. False with Why set when
  nothing more may be sent. }
type
  TNoteProc = procedure(const Line: string) of object;
function AcceptServer(H: TSecHandshake; const S1, Server, GivenKey: string;
  Note: TNoteProc; out Why: string): Boolean;

type
  { One link's secure login, from the choice to probe to C2. The client
    sends the lines it hands out in its plain login frame and decodes
    frames as plain zlib while Awaiting. }
  TSecSession = class
  private
    FHandshake: TSecHandshake;
    FTail: string;
    FStartMs: Int64;
    FServer: string;
  public
    Mode: TSecMode;
    { --server-key: the only key trusted, the pin file left alone }
    ServerKey: string;
    { the next login is the original one (auto's fallback) }
    ForceClassic: Boolean;
    State: TSecState;
    { the server's refusal text, or why the handshake stopped }
    Why: string;
    OnNote: TNoteProc;
    destructor Destroy; override;
    { A new connection to Server (host:port, the name pins go by). }
    procedure Reset(const AServer: string);
    { Whether this login goes through SEI00001. }
    function Want: Boolean;
    { C1 for the plain login frame; False (State ssFailed) if it cannot
      start. Tail is what the classic line has after the token. }
    function Start(const Prefix, Inner, Suffix, Tail: string; out C1: string): Boolean;
    function Awaiting: Boolean;
    { The first line of the first plain frame after C1. True with C2 to send
      in the plain login frame; False when the server refused (ssRefused)
      or the check failed (ssFailed): drop the link. }
    function Answer(const Plain: string; out C2: string): Boolean;
    { Each tick: a close while waiting is a refusal, 5 s of silence is no
      answer. True when the link should be dropped. }
    function Check(Connected: Boolean): Boolean;
    { Forgets a finished or failed handshake (after it was reported). }
    procedure Finish;
    property Server: string read FServer;
  end;

implementation

uses
  SysUtils, GCompat, GPaths, GSecCrypto;

const
  SigContext = 'seihai-login-v1/server-hello'#0;
  KeyInfo = 'seihai-login-v1/c2s key';
  KeyB64 = 43;
  SigB64 = 86;
  PadTo = 64;

{ TSecHandshake }

function TSecHandshake.Start(const Prefix, Inner, Suffix: string): Boolean;
var
  S: string;
begin
  Result := False;
  if not RandomBytes(32, S) then
  begin
    FError := 'no random bytes from the system';
    Exit;
  end;
  Result := StartWith(Prefix, Inner, Suffix, S);
end;

function TSecHandshake.StartWith(const Prefix, Inner, Suffix, Secret: string): Boolean;
begin
  Result := False;
  FError := '';
  FServerKey := '';
  FTh := '';
  FKey := '';
  if Length(Inner) <> 8 then
  begin
    FError := 'inner token is not 8 bytes';
    Exit;
  end;
  if Length(Secret) <> 32 then
  begin
    FError := 'secret is not 32 bytes';
    Exit;
  end;
  FSecret := Secret;
  FHello := Prefix + SeiToken + Inner + B64Encode(X25519Base(FSecret)) + Suffix;
  Result := True;
end;

function U16LE(N: Integer): string;
begin
  Result := Chr(N and $FF) + Chr((N shr 8) and $FF);
end;

function TSecHandshake.Finish(const S1: string): Boolean;
var
  L, Rest, Eph, Id, Sig, Signed, Shared: string;
begin
  Result := False;
  FError := '';
  L := S1;
  if (L <> '') and (L[Length(L)] = #10) then SetLength(L, Length(L) - 1);
  if Copy(L, 1, 8) <> SeiToken then
  begin
    FError := 'server hello does not start with the token';
    Exit;
  end;
  if FHello = '' then
  begin
    FError := 'no hello was sent';
    Exit;
  end;
  Rest := Copy(L, 9, MaxInt);
  if Length(Rest) <> KeyB64 * 2 + SigB64 then
  begin
    FError := 'server hello has the wrong length';
    Exit;
  end;
  if not B64Decode(Copy(Rest, 1, KeyB64), Eph) or (Length(Eph) <> 32) or
    not B64Decode(Copy(Rest, KeyB64 + 1, KeyB64), Id) or (Length(Id) <> 32) or
    not B64Decode(Copy(Rest, KeyB64 * 2 + 1, SigB64), Sig) or (Length(Sig) <> 64) then
  begin
    FError := 'bad base64 in the server hello';
    Exit;
  end;
  Signed := SigContext + U16LE(Length(FHello)) + FHello + Eph + Id;
  if not Ed25519Verify(Sig, Signed, Id) then
  begin
    FError := 'the server''s signature on the secure login does not verify';
    Exit;
  end;
  Shared := X25519(FSecret, Eph);
  if IsZero32(Shared) then
  begin
    FError := 'the key exchange gave a weak shared secret';
    Exit;
  end;
  FTh := Sha256(Signed + Sig);
  FKey := HkdfSha256(FTh, Shared, KeyInfo, 32);
  FServerKey := Id;
  FSecret := StringOfChar(#0, 32);
  Result := True;
end;

function TSecHandshake.Seal(const Tail: string): string;
var
  P: string;
begin
  Result := '';
  if (FKey = '') or (Length(Tail) > SeiMaxTail) then Exit;
  P := U16LE(Length(Tail)) + Tail;
  if Length(P) mod PadTo <> 0 then P := P + StringOfChar(#0, PadTo - Length(P) mod PadTo);
  Result := SeiToken + B64Encode(AeadSeal(FKey, StringOfChar(#0, 12), FTh, P));
  { the key is used once }
  FKey := '';
end;

{ helpers }

function IsServerHello(const Line: string): Boolean;
begin
  Result := Copy(Line, 1, 8) = SeiToken;
end;

function ParseSecMode(const S: string; out Mode: TSecMode): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  Result := True;
  if L = 'off' then Mode := smOff
  else if L = 'auto' then Mode := smAuto
  else if L = 'required' then Mode := smRequired
  else Result := False;
end;

function SecModeName(Mode: TSecMode): string;
begin
  case Mode of
    smOff: Result := 'off';
    smRequired: Result := 'required';
  else
    Result := 'auto';
  end;
end;

function KeyFingerprint(const Key: string): string;
begin
  Result := 'SHA256:' + B64Encode(Sha256(Key));
end;

function EncodeKey(const Key: string): string;
begin
  Result := B64Encode(Key);
end;

function DecodeKey(const Text: string; out Key: string): Boolean;
begin
  Result := B64Decode(Trim(Text), Key) and (Length(Key) = 32);
  if not Result then Key := '';
end;

function PinDir: string;
begin
  Result := PinDirOverride;
  if Result = '' then Result := EnvVar('GRAAL_SECURE_DIR');
  if Result <> '' then Exit;
{$IFDEF MSWINDOWS}
  Result := EnvVar('APPDATA');
  if Result = '' then Result := ExtractFilePath(ParamStr(0));
  Result := WithTrailingSep(Result) + 'graal-delphi';
{$ELSE}
  Result := EnvVar('XDG_CONFIG_HOME');
  if Result = '' then
  begin
    Result := EnvVar('HOME');
    if Result = '' then Result := ExtractFilePath(ParamStr(0))
    else Result := WithTrailingSep(Result) + '.config';
  end;
  Result := WithTrailingSep(Result) + 'graal-delphi';
{$ENDIF}
end;

function PinFile: string;
begin
  Result := WithTrailingSep(PinDir) + 'known_servers.txt';
end;

function RefusedFile: string;
begin
  Result := WithTrailingSep(PinDir) + 'refused_servers.txt';
end;

{ the file's lines, or none if it cannot be read }
function ReadLines(const Path: string): TStringArray;
var
  F: TextFile;
  L: string;
  N: Integer;
begin
  SetLength(Result, 0);
  if not FileExists(Path) then Exit;
  AssignFile(F, Path);
  {$I-}
  Reset(F);
  {$I+}
  if IOResult <> 0 then Exit;
  N := 0;
  while not Eof(F) do
  begin
    ReadLn(F, L);
    L := Trim(L);
    if (L = '') or (L[1] = '#') then Continue;
    SetLength(Result, N + 1);
    Result[N] := L;
    Inc(N);
  end;
  CloseFile(F);
end;

procedure AppendLine(const Path, Line: string);
var
  F: TextFile;
begin
  MakeDirs(ExtractFileDir(Path));
  AssignFile(F, Path);
  {$I-}
  if FileExists(Path) then Append(F) else Rewrite(F);
  {$I+}
  if IOResult <> 0 then Exit;
  WriteLn(F, Line);
  CloseFile(F);
end;

function SplitPin(const Line: string; out Server, Key: string): Boolean;
var
  P: Integer;
begin
  P := Pos(' ', Line);
  if P = 0 then P := Pos(#9, Line);
  Result := P > 0;
  if not Result then Exit;
  Server := Copy(Line, 1, P - 1);
  Result := DecodeKey(Copy(Line, P + 1, MaxInt), Key);
end;

function PinCheck(const Server, Key: string; out Pinned: string): TPinResult;
var
  Lines: TStringArray;
  I: Integer;
  S, K: string;
begin
  Result := prUnknown;
  Pinned := '';
  Lines := ReadLines(PinFile);
  for I := 0 to High(Lines) do
    if SplitPin(Lines[I], S, K) and (S = Server) then
    begin
      Pinned := K;
      if K = Key then Result := prMatches else Result := prMismatch;
      Exit;
    end;
end;

function IsPinned(const Server: string): Boolean;
var
  Pinned: string;
begin
  Result := PinCheck(Server, '', Pinned) <> prUnknown;
end;

procedure PinAppend(const Server, Key: string);
begin
  AppendLine(PinFile, Server + ' ' + EncodeKey(Key));
end;

function WasRefused(const Server: string): Boolean;
var
  Lines: TStringArray;
  I: Integer;
begin
  Result := False;
  Lines := ReadLines(RefusedFile);
  for I := 0 to High(Lines) do
    if Lines[I] = Server then begin Result := True; Exit; end;
end;

procedure RememberRefused(const Server: string);
begin
  if not WasRefused(Server) then AppendLine(RefusedFile, Server);
end;

var
  ModeSet: Boolean = False;
  ModeGiven: TSecMode = smOff;
  KeyGiven: string = '';

procedure SetSecure(Mode: TSecMode; const Key: string);
begin
  ModeSet := True;
  ModeGiven := Mode;
  KeyGiven := Key;
end;

procedure ClearSecure;
begin
  ModeSet := False;
  ModeGiven := smOff;
  KeyGiven := '';
end;

function ConfiguredSecMode: TSecMode;
var
  Lines: TStringArray;
  W: string;
begin
  Result := smOff;
  if ModeSet then begin Result := ModeGiven; Exit; end;
  W := EnvVar('GRAAL_SECURE_LOGIN');
  if W = '' then
  begin
    Lines := ReadLines(WithTrailingSep(PinDir) + 'secure_login.txt');
    if Length(Lines) > 0 then W := Lines[0];
    if Pos(' ', W) > 0 then W := Copy(W, 1, Pos(' ', W) - 1);
  end;
  if not ParseSecMode(W, Result) then Result := smOff;
end;

function ConfiguredServerKey: string;
begin
  Result := KeyGiven;
end;

function ShouldProbe(Mode: TSecMode; const Server: string): Boolean;
begin
  case Mode of
    smOff: Result := False;
    smRequired: Result := True;
  else
    Result := IsPinned(Server) or not WasRefused(Server);
  end;
end;

function MayFallBack(Mode: TSecMode; const Server: string): Boolean;
begin
  Result := (Mode = smAuto) and not IsPinned(Server);
end;

function AcceptServer(H: TSecHandshake; const S1, Server, GivenKey: string;
  Note: TNoteProc; out Why: string): Boolean;
var
  Want, Pinned: string;
begin
  Result := False;
  Why := '';
  if not H.Finish(S1) then
  begin
    Why := H.Error;
    Exit;
  end;
  if GivenKey <> '' then
  begin
    if not DecodeKey(GivenKey, Want) then
    begin
      Why := 'the given server key is not a key';
      Exit;
    end;
    if Want <> H.ServerKey then
    begin
      Why := 'server key ' + KeyFingerprint(H.ServerKey) + ' is not the given key ' +
        KeyFingerprint(Want) + '; not sending the password';
      Exit;
    end;
    Result := True;
    Exit;
  end;
  case PinCheck(Server, H.ServerKey, Pinned) of
    prMatches: Result := True;
    prUnknown:
      begin
        PinAppend(Server, H.ServerKey);
        if Assigned(Note) then
          Note('secure login: trusting ' + Server + ' on first use, key ' +
            KeyFingerprint(H.ServerKey) + ' (saved in ' + PinFile + ')');
        Result := True;
      end;
    prMismatch:
      Why := 'server key ' + KeyFingerprint(H.ServerKey) + ' for ' + Server +
        ' is not the pinned key ' + KeyFingerprint(Pinned) + ' in ' + PinFile +
        '; not sending the password';
  end;
end;

{ TSecSession }

destructor TSecSession.Destroy;
begin
  FHandshake.Free;
  inherited Destroy;
end;

procedure TSecSession.Reset(const AServer: string);
begin
  FServer := AServer;
  State := ssNone;
  Why := '';
  FTail := '';
end;

function TSecSession.Want: Boolean;
begin
  Result := not ForceClassic and ShouldProbe(Mode, FServer);
end;

function TSecSession.Start(const Prefix, Inner, Suffix, Tail: string; out C1: string): Boolean;
begin
  Result := False;
  C1 := '';
  if FHandshake = nil then FHandshake := TSecHandshake.Create;
  if (Length(Tail) > SeiMaxTail) or not FHandshake.Start(Prefix, Inner, Suffix) then
  begin
    State := ssFailed;
    if FHandshake.Error <> '' then Why := FHandshake.Error
    else Why := 'the login is too long to seal';
    Exit;
  end;
  FTail := Tail;
  State := ssAwaitS1;
  FStartMs := GetTickCount64;
  C1 := FHandshake.Hello;
  if Assigned(OnNote) then OnNote('secure login: SEI00001 hello sent (inner ' + Inner + ')');
  Result := True;
end;

function TSecSession.Awaiting: Boolean;
begin
  Result := State = ssAwaitS1;
end;

function TSecSession.Answer(const Plain: string; out C2: string): Boolean;
var
  L, W: string;
begin
  Result := False;
  C2 := '';
  L := Plain;
  if Pos(#10, L) > 0 then SetLength(L, Pos(#10, L) - 1);
  if not IsServerHello(L) then
  begin
    State := ssRefused;
    Why := Copy(L, 2, MaxInt);
    if Assigned(OnNote) then OnNote('secure login refused: ' + Why);
    FTail := '';
    Exit;
  end;
  if not AcceptServer(FHandshake, L, FServer, ServerKey, OnNote, W) then
  begin
    State := ssFailed;
    Why := W;
    FTail := '';
    Exit;
  end;
  C2 := FHandshake.Seal(FTail);
  FTail := '';
  State := ssDone;
  if Assigned(OnNote) then
    OnNote('secure login: server key ' + KeyFingerprint(FHandshake.ServerKey) + ' verified; login sealed');
  Result := True;
end;

function TSecSession.Check(Connected: Boolean): Boolean;
begin
  Result := False;
  if State <> ssAwaitS1 then Exit;
  if not Connected then
  begin
    State := ssRefused;
    if Why = '' then Why := 'the server closed the link';
  end
  else if GetTickCount64 - FStartMs > SeiWaitMs then
  begin
    State := ssNoAnswer;
    Why := 'the server did not answer the secure login within 5 s (it may not support SEI00001)';
    Result := True;
  end;
end;

procedure TSecSession.Finish;
begin
  State := ssNone;
  FTail := '';
end;

end.
