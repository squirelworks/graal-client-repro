{ GraalClient: TGraalClient and TAdventureClient, the 5.12 game link.
  5.12's network code sits in a C++ engine library, not in Delphi, but
  on the wire it keeps the gen-5 codec of 2.22 to 4.20 (graal_analysis
  protocol/v5x-clients.md, "Cipher"): the same framing and compression
  thresholds, so the rebuild keeps the 2.22 class split. What 5.12 does
  at login (v5x-clients.md, "Login"; version-profiles/lab-v5-2026-10-30.md):
  the login line alone in the plain zlib frame, ending with the comma list
  "win" and three machine fields, then 37 (language) in its own gen-5
  frame. No tamper check follows, ever.
  The notes below are the 2.22 ones, which hold for 5.12 too.

  Same class split as 2.05 (graal_analysis client-internals/
  client-architecture-205.md; client-versions.md: "all four clients are
  Delphi builds with the same network classes"):
    TGraalClient      socket, out buffer, u16be frames, receive split
    TAdventureClient  the gen-5 frame codec, the login line builder

  What changed from 2.05 (protocol/codec-and-framing.md, "Gen 4/5 partial
  XOR", and protocol/client-versions.md, "Gen-5 send on the client"):
    - Messages are no longer touched one by one; the whole frame body is.
    - Login: type 5, the key, GNW03014, account, password. That one frame
      is u16be + zlib with no compression byte and no XOR, so the key can
      be read. It is flushed by itself, then the socket switches to gen 5.
    - Every later frame, both ways: u16be (body length + 1), a compression
      byte, the body. The client picks 2 (raw) under 0x30 bytes unless zlib
      is shorter, 4 (zlib) from 0x30, 6 (bz2) from 0x1000. Even codes are
      XORed: one LCG step per 4-byte group present, at most 12 groups raw or
      4 compressed; a short last group still steps. Each direction has its
      own iterator, seeded 0x04A80B38, with the same key.
  Receive: u16be -> undo XOR -> inflate / bunzip -> split on #10, with the
  PLO_RAWDATA escape, as in 2.05. }
unit GraalClient;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSocket, GSecLogin;

type
  TMessageEvent = procedure(Id: Integer; const Data: string) of object;
  TLogEvent = procedure(const Line: string) of object;

  TGraalClient = class
  protected
    FSocket: TGSocket;
    FOut: string;      { pending, uncompressed messages }
    FInRaw: string;    { bytes from the socket, not yet a whole frame }
    FInPlain: string;  { decoded stream, not yet whole messages }
    FRawPending: Integer; { > 0: the next n bytes are one message }
    FOnMessage: TMessageEvent;
    FOnLog: TLogEvent;
    FFramesIn, FFramesOut, FMessagesIn, FMessagesOut: Integer;
    FBytesIn, FBytesOut: Int64;
    procedure Log(const S: string);
    { Hooks for the frame codec; the base class is plain zlib both ways. }
    function EncodeFrame(const Plain: string): string; virtual;
    function DecodeFrame(const Body: string; out Plain: string): Boolean; virtual;
    procedure SplitMessages;
    procedure DeliverMessage(const Msg: string);
    { Logs Why, drops the link and the receive buffers. }
    procedure Fail(const Why: string);
  public
    LastError: string;
    { Tests: with Sink set, the client counts as connected and Flush
      appends each frame (length included) to Sent instead of a socket. }
    Sink: Boolean;
    Sent: string;
    constructor Create;
    destructor Destroy; override;
    function Connect(const Host: string; Port: Word): Boolean; virtual;
    procedure Disconnect;
    function Connected: Boolean;
    { Queues one message. Returns False if Data holds #10 (dropped). }
    function SendPacket(Id: Integer; const Data: string): Boolean; virtual;
    procedure Flush;
    { Called from the tick: read the socket, unpack frames, dispatch. }
    procedure Poll;
    { Takes bytes as if they came from the socket: frames, then messages.
      Poll uses it; tests and the fuzzer call it directly. }
    procedure FeedRaw(const Bytes: string);
    property OnMessage: TMessageEvent read FOnMessage write FOnMessage;
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property FramesIn: Integer read FFramesIn;
    property FramesOut: Integer read FFramesOut;
    property MessagesIn: Integer read FMessagesIn;
    property MessagesOut: Integer read FMessagesOut;
    { bytes on the wire, frame headers included }
    property BytesIn: Int64 read FBytesIn;
    property BytesOut: Int64 read FBytesOut;
    property Socket: TGSocket read FSocket;
  end;

  { One direction of the gen-5 codec. }
  TGen5 = class
  public
    Key: Byte;
    Iterator: Cardinal;
    constructor Create(AKey: Byte);
    { XORs Body in place for compression type CType (even codes only). }
    procedure Apply(var Body: string; CType: Integer);
  end;

  TAdventureClient = class(TGraalClient)
  protected
    FKey: Byte;
    FLoginFrame: Boolean; { the next flush is the fixed login frame }
    FOutCodec, FInCodec: TGen5;
    { Seihai secure login (GSecLogin), not in the original }
    FSec: TSecSession;
    FLanguage: string;
    { Queues one whole line (its first byte is the id) for the next flush. }
    procedure SendLine(const Line: string);
    { C1 in the plain login frame; S1 is then awaited. }
    procedure StartSecure(const Prefix, Inner, Suffix, Tail: string);
    { What the classic login sends after its line; sent after C2. }
    procedure SendAfterLogin; virtual;
    procedure AfterSealedLogin;
    procedure SecNote(const Line: string);
    function EncodeFrame(const Plain: string): string; override;
    function DecodeFrame(const Body: string; out Plain: string): Boolean; override;
    procedure ResetCodec;
  public
    destructor Destroy; override;
    { the secure login's settings and state (off by default) }
    function Sec: TSecSession;
    { Call each tick while Sec.Awaiting: drops a link silent for 5 s. }
    procedure CheckSecure;
    function Connect(const Host: string; Port: Word): Boolean; override;
    { The login as 5.12 sends it: the login line alone in the fixed
      plain zlib frame (flushed here), then 37 with the language, queued
      for the caller's flush, so it goes in the first gen-5 frame. }
    procedure SendLogin(const Account, Password, Language: string);
    { Sets up the codec state without a socket (tests, the fuzzer). }
    procedure StartOffline(AKey: Byte);
    procedure SendToAll(const Text: string);
    property Key: Byte read FKey write FKey;
    property OutCodec: TGen5 read FOutCodec;
    property InCodec: TGen5 read FInCodec;
  end;

{ The tail of the login line after the password: the platform, then the
  machine fields, comma-separated with no length prefix. }
function LoginTail: string;

{ The compression byte 5.12 (as 2.22) picks for an out buffer, and the body. }
function PackBody(const Plain: string; out CType: Integer): string;

implementation

uses
  SysUtils, GTypes, GZlib, GBzip2, Protocol512;

{ TGen5 }

constructor TGen5.Create(AKey: Byte);
begin
  inherited Create;
  Key := AKey;
  Iterator := CipherSeed;
end;

{ the iterator wraps at 32 bits on purpose }
{$IFOPT Q+}{$DEFINE OVERFLOW_WAS_ON}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE RANGE_WAS_ON}{$R-}{$ENDIF}
procedure TGen5.Apply(var Body: string; CType: Integer);
var
  Groups, Present, G, J, P: Integer;
  K: Cardinal;
begin
  if (CType and 1) <> 0 then Exit; { odd codes are not XORed }
  if CType = CompressNone then Groups := XorGroupsRaw
  else Groups := XorGroupsPacked;
  { 5.12 steps a packed body Length div 4 times, rounded down; a raw one
    rounded up, as every later build steps both (Graal_analysis
    protocol/v5v6-lab-play.md, "5.12's cipher step count"). }
  if CType = CompressNone then Present := (Length(Body) + 3) div 4
  else Present := Length(Body) div 4;
  if Present < Groups then Groups := Present;
  UniqueString(Body);
  for G := 0 to Groups - 1 do
  begin
    Iterator := Iterator * CipherMul + Key;
    K := Iterator;
    for J := 0 to 3 do
    begin
      P := G * 4 + J + 1;
      if P > Length(Body) then Break;
      Body[P] := Chr(Ord(Body[P]) xor ((K shr (8 * J)) and $FF));
    end;
  end;
end;
{$IFDEF RANGE_WAS_ON}{$R+}{$ENDIF}
{$IFDEF OVERFLOW_WAS_ON}{$Q+}{$ENDIF}

function PackBody(const Plain: string; out CType: Integer): string;
var
  Z: string;
begin
  if Length(Plain) >= Bz2From then
  begin
    CType := CompressBz2;
    Result := BZ2Compress(Plain);
  end
  else if Length(Plain) >= ZlibFrom then
  begin
    CType := CompressZlib;
    Result := ZCompress(Plain);
  end
  else
  begin
    { 5.12 sends even short bodies zlib-compressed
      (protocol/v5v6-windows-unpacked.md, "Cipher and framing") }
    Z := ZCompress(Plain);
    CType := CompressZlib;
    Result := Z;
  end;
end;

{ TGraalClient }

constructor TGraalClient.Create;
begin
  inherited Create;
  FSocket := TGSocket.Create;
end;

destructor TGraalClient.Destroy;
begin
  FSocket.Free;
  inherited Destroy;
end;

procedure TGraalClient.Log(const S: string);
begin
  if Assigned(FOnLog) then FOnLog(S);
end;

function TGraalClient.Connect(const Host: string; Port: Word): Boolean;
begin
  FOut := '';
  FInRaw := '';
  FInPlain := '';
  FRawPending := 0;
  Result := FSocket.Connect(Host, Port);
  if not Result then LastError := FSocket.LastError;
end;

procedure TGraalClient.Disconnect;
begin
  FSocket.Close;
  Sink := False;
end;

function TGraalClient.Connected: Boolean;
begin
  Result := FSocket.Connected or Sink;
end;

function TGraalClient.EncodeFrame(const Plain: string): string;
begin
  Result := ZCompress(Plain);
end;

function TGraalClient.DecodeFrame(const Body: string; out Plain: string): Boolean;
begin
  Result := ZDecompress(Body, Plain);
end;

function TGraalClient.SendPacket(Id: Integer; const Data: string): Boolean;
var
  Msg: string;
begin
  Result := False;
  if Pos(#10, Data) > 0 then Exit; { silently dropped }
  Msg := GChar(Id) + Data + #10;
  if (FOut <> '') and (Length(FOut) + Length(Msg) > OutFlushAt) then
    Flush;
  FOut := FOut + Msg;
  Inc(FMessagesOut);
  if Length(FOut) > OutDropAt then
  begin
    LastError := 'more than 256 KB queued';
    Disconnect;
    Exit;
  end;
  Result := True;
end;

procedure TGraalClient.Flush;
var
  Z: string;
begin
  if (FOut = '') or not Connected then Exit;
  Z := EncodeFrame(FOut);
  FOut := '';
  if Length(Z) > $FFFF then
  begin
    LastError := 'frame too long for its u16 length';
    Disconnect;
    Exit;
  end;
  if Sink then
    Sent := Sent + Chr((Length(Z) shr 8) and $FF) + Chr(Length(Z) and $FF) + Z
  else
    FSocket.Send(Chr((Length(Z) shr 8) and $FF) + Chr(Length(Z) and $FF) + Z);
  Inc(FFramesOut);
  Inc(FBytesOut, Length(Z) + 2);
end;

procedure TGraalClient.Poll;
var
  Got: string;
begin
  if not FSocket.Connected then Exit;
  Got := '';
  if not FSocket.Poll(Got) then
    LastError := FSocket.LastError;
  if Got <> '' then
  begin
    Inc(FBytesIn, Length(Got));
    FeedRaw(Got);
  end;
end;

procedure TGraalClient.FeedRaw(const Bytes: string);
var
  P, Len: Integer;
  Body: string;
begin
  FInRaw := FInRaw + Bytes;
  { frames are read by position and the used bytes dropped once, so a burst
    of many frames is linear, not quadratic }
  P := 1;
  while Length(FInRaw) - P + 1 >= 2 do
  begin
    Len := (Ord(FInRaw[P]) shl 8) or Ord(FInRaw[P + 1]);
    if Length(FInRaw) - P + 1 < Len + 2 then Break;
    if not DecodeFrame(Copy(FInRaw, P + 2, Len), Body) then
    begin
      Fail('bad frame from the server');
      Exit;
    end;
    if Length(Body) > InFrameMax then
    begin
      Fail('frame from the server inflates past the limit');
      Exit;
    end;
    Inc(P, Len + 2);
    Inc(FFramesIn);
    FInPlain := FInPlain + Body;
    SplitMessages;
    if FInRaw = '' then Exit; { Fail cleared the buffers }
  end;
  if P > 1 then Delete(FInRaw, 1, P - 1);
end;

procedure TGraalClient.Fail(const Why: string);
begin
  LastError := Why;
  Log(Why);
  Disconnect;
  FInRaw := '';
  FInPlain := '';
  FRawPending := 0;
end;

procedure TGraalClient.DeliverMessage(const Msg: string);
var
  Id: Integer;
begin
  if Msg = '' then Exit;
  Id := Ord(Msg[1]) - $20;
  Inc(FMessagesIn);
  if Assigned(FOnMessage) then
    FOnMessage(Id, Copy(Msg, 2, MaxInt));
end;

procedure TGraalClient.SplitMessages;
var
  P, E, N: Integer;
  Msg: string;
  R: TGReader;
begin
  P := 1;
  N := Length(FInPlain);
  while P <= N do
  begin
    if FRawPending > 0 then
    begin
      if N - P + 1 < FRawPending then Break;
      Msg := Copy(FInPlain, P, FRawPending);
      Inc(P, FRawPending);
      FRawPending := 0;
      if (Msg <> '') and (Msg[Length(Msg)] = #10) then
        SetLength(Msg, Length(Msg) - 1);
      DeliverMessage(Msg);
      Continue;
    end;
    E := P;
    while (E <= N) and (FInPlain[E] <> #10) do Inc(E);
    if E > N then Break;
    Msg := Copy(FInPlain, P, E - P);
    P := E + 1;
    if (Msg <> '') and (Ord(Msg[1]) - $20 = PLO_RAWDATA) then
    begin
      R := TGReader.Create(Copy(Msg, 2, MaxInt));
      try
        FRawPending := R.ReadGInt3;
      finally
        R.Free;
      end;
      { a GINT3 length is at most 3670015, under InPendingMax }
      Continue;
    end;
    DeliverMessage(Msg);
  end;
  if P > 1 then Delete(FInPlain, 1, P - 1);
  if Length(FInPlain) > InPendingMax then
    Fail('unfinished message from the server is past the limit');
end;

{ TAdventureClient }

destructor TAdventureClient.Destroy;
begin
  FSec.Free;
  FOutCodec.Free;
  FInCodec.Free;
  inherited Destroy;
end;

procedure TAdventureClient.ResetCodec;
begin
  FOutCodec.Free;
  FInCodec.Free;
  FOutCodec := TGen5.Create(FKey);
  FInCodec := TGen5.Create(FKey);
  FLoginFrame := True;
end;

procedure TAdventureClient.StartOffline(AKey: Byte);
begin
  FKey := AKey and $7F;
  ResetCodec;
  FOut := '';
  FInRaw := '';
  FInPlain := '';
  FRawPending := 0;
end;

function TAdventureClient.Connect(const Host: string; Port: Word): Boolean;
begin
  Sec.Reset(Host + ':' + IntToStr(Port));
  FKey := Random(256) and $7F;
  ResetCodec;
  Result := inherited Connect(Host, Port);
end;

function TAdventureClient.Sec: TSecSession;
begin
  if FSec = nil then
  begin
    FSec := TSecSession.Create;
    FSec.OnNote := SecNote;
  end;
  Result := FSec;
end;

procedure TAdventureClient.SecNote(const Line: string);
begin
  Log(Line);
end;

procedure TAdventureClient.SendLine(const Line: string);
begin
  if Line <> '' then SendPacket(Ord(Line[1]) - $20, Copy(Line, 2, MaxInt));
end;

procedure TAdventureClient.StartSecure(const Prefix, Inner, Suffix, Tail: string);
var
  C1: string;
begin
  if not Sec.Start(Prefix, Inner, Suffix, Tail, C1) then Exit;
  FOut := '';
  FLoginFrame := True;
  SendLine(C1);
  Flush;
end;

procedure TAdventureClient.AfterSealedLogin;
begin
  Flush;
  SendAfterLogin;
  Flush;
end;

procedure TAdventureClient.CheckSecure;
begin
  if Sec.Check(Connected) then Disconnect;
end;

function TAdventureClient.EncodeFrame(const Plain: string): string;
var
  CType: Integer;
begin
  if FLoginFrame then
  begin
    { the fixed "zlib, no cipher, no compression byte" login frame }
    FLoginFrame := False;
    Result := ZCompress(Plain);
    Exit;
  end;
  Result := PackBody(Plain, CType);
  FOutCodec.Apply(Result, CType);
  Result := Chr(CType) + Result;
end;

function TAdventureClient.DecodeFrame(const Body: string; out Plain: string): Boolean;
var
  CType: Integer;
  B: string;
  C2: string;
begin
  if (FSec <> nil) and FSec.Awaiting then
  begin
    { S1, or the refusal, comes in a plain zlib frame }
    Plain := '';
    Result := ZDecompress(Body, B);
    if not Result then Exit;
    if FSec.Answer(B, C2) then
    begin
      { C2 stands in for the classic login line, in its plain frame }
      FOut := '';
      FLoginFrame := True;
      SendLine(C2);
      AfterSealedLogin;
    end
    else
      Disconnect;
    Exit;
  end;
  Plain := '';
  Result := False;
  if (Body = '') or (FInCodec = nil) then Exit;
  CType := Ord(Body[1]);
  B := Copy(Body, 2, MaxInt);
  FInCodec.Apply(B, CType);
  case CType of
    1, 2: begin Plain := B; Result := True; end;
    3, 4: Result := ZDecompress(B, Plain);
    5, 6: Result := BZ2Decompress(B, Plain, InFrameMax);
  end;
end;

procedure TAdventureClient.SendLogin(const Account, Password, Language: string);
begin
  FLanguage := Language;
  { Seihai secure login (not in the original): C1 now, C2 and the rest
    once S1 has checked out }
  if Sec.Want then
  begin
    StartSecure(GChar(ClientType) + GChar(FKey), ClientVersionToken, '',
      GString(Account) + GString(Password) + LoginTail);
    Exit;
  end;
  { GCHAR type, GCHAR key, token, GSTRING account, GSTRING password, then
    the comma list, on one line (v5x-clients.md, "Login"). A password of
    0xE0 bytes or more goes as 0xFF and its first 0xDF bytes, which is
    what GString's cut at 223 bytes gives. }
  SendPacket(ClientType, GChar(FKey) + ClientVersionToken + GString(Account) + GString(Password) + LoginTail);
  Flush;
  SendAfterLogin;
end;

procedure TAdventureClient.SendAfterLogin;
begin
  SendPacket(PLI_LANGUAGE, FLanguage);
end;

function LoginTail: string;
begin
  Result := LoginPlatform + LoginMachineFields + ',"' + LoginOsVersion + '"';
end;

procedure TAdventureClient.SendToAll(const Text: string);
var
  T: string;
begin
  T := Copy(Text, 1, 200);
  SendPacket(PLI_TOALL, GChar(Length(T)) + T);
end;

end.
