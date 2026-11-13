{ GraalClient: TGraalClient and TAdventureClient, the gen-4 game link of
  2.19 to 2.21. INVENTED, not observed: no binary of these builds is held
  and no type-4 login was ever captured, so this link is made up to work
  (Squirrel, 2026-11-13), following graal_analysis
  protocol/codec-and-framing.md's server-source gen 4 (client type 4).
  seihai-gserver serves the same invention:
    - login: type 4, the key, the token, account, password, in one frame of
      u16be + zlib with no XOR, as 2.22 sends its type-5 login;
    - every later frame, both ways: u16be + bzip2 body, its first 4 dword
      groups (a short last group too) XORed with the LCG of gen 5, one
      iterator per direction seeded 0x04A80B38 with the key; no compression
      byte (gen 5 added it) and no gen-3 insertion.
  The messages, PLI_LANGUAGE and PLI_TAMPERCHECK are 2.17.1's.

  Class names and split follow the 2.05 class list (graal_analysis
  client-internals/client-architecture-205.md):
    TGraalClient      socket, out buffer, zlib flush, u16be frame
    TAdventureClient  gen-3 insertion on send, the receive dispatcher,
                      the login line builder

  Send pipeline (protocol/codec-and-framing.md, "2.05 send pipeline"):
    1. message = GCHAR(id) + data + #10; data holding #10 is dropped
    2. from the second message of the session on, gen-3 inserts one byte
    3. append to the out buffer
    4. flush: zlib the whole buffer, prefix u16be length; at 0x1000 bytes
       or at the end of the tick; over 0x40000 queued drops the link
  Receive: u16be -> inflate -> split on #10, with the PLO_RAWDATA escape.
  Server -> client has no cipher for a gen-3 client. }
unit GraalClient;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSocket;

type
  TMessageEvent = procedure(Id: Integer; const Data: string) of object;
  TLogEvent = procedure(const Line: string) of object;

  TGraalClient = class
  protected
    FSocket: TGSocket;
    FOut: string;      { pending, uncompressed messages }
    FInRaw: string;    { bytes from the socket, not yet a whole frame }
    FInPlain: string;  { inflated stream, not yet whole messages }
    FRawPending: Integer; { > 0: the next n bytes are one message }
    FOnMessage: TMessageEvent;
    FOnLog: TLogEvent;
    FFramesIn, FFramesOut, FMessagesIn, FMessagesOut: Integer;
    FBytesIn, FBytesOut: Int64;
    procedure Log(const S: string);
    { Hook for the gen-3 step; the base class sends messages unchanged. }
    function EncodeMessage(const Msg: string): string; virtual;
    { Hooks for the frame codec; the base class is plain zlib both ways. }
    function EncodeFrame(const Plain: string): string; virtual;
    function DecodeFrame(const Body: string; out Plain: string): Boolean; virtual;
    procedure SplitMessages;
    procedure DeliverMessage(const Msg: string);
    { Logs Why, drops the link and the receive buffers. }
    procedure Fail(const Why: string);
  public
    LastError: string;
    constructor Create;
    destructor Destroy; override;
    function Connect(const Host: string; Port: Word): Boolean; virtual;
    procedure Disconnect;
    function Connected: Boolean;
    { Queues one message. Returns False if Data holds #10 (2.05 drops it). }
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

  TAdventureClient = class(TGraalClient)
  protected
    FIterator: Cardinal;  { Self+0x42C in 2.05 }
    FKey: Byte;           { Self+0x430: Random and $7F, raw }
    FLoginSent: Boolean;  { Self+0x434 }
    FLoginFrame: Boolean; { the next flush is the plain login frame }
    FOutIt, FInIt: Cardinal; { gen-4 XOR, one per direction }
    function EncodeMessage(const Msg: string): string; override;
    function EncodeFrame(const Plain: string): string; override;
    function DecodeFrame(const Body: string; out Plain: string): Boolean; override;
  public
    function Connect(const Host: string; Port: Word): Boolean; override;
    { Sends the login line (clean), then PLI_LANGUAGE. }
    procedure SendLogin(const Account, Password, Language: string);
    procedure SendToAll(const Text: string);
    property Key: Byte read FKey write FKey;
    property Iterator: Cardinal read FIterator write FIterator;
    { the gen-4 iterator of server frames }
    property InIterator: Cardinal read FInIt write FInIt;
  end;

{ One gen-3 step on a whole message (id byte .. #10), exposed for tests.
  Advances It, returns the message with the junk byte inserted. }
function Gen3Insert(var It: Cardinal; Key: Byte; const Msg: string): string;
{ The server's view: remove the byte at 0-based (it and $FFFF) mod len,
  len = the line without #10. Returns the clean line. }
function Gen3Remove(var It: Cardinal; Key: Byte; const Line: string): string;
{ The gen-4 XOR of a frame body (both ways; tests build server frames with it). }
procedure Gen4Xor(var It: Cardinal; Key: Byte; var Body: string);

implementation

uses
  SysUtils, GTypes, GZlib, GBzip2, Protocol221;

{ the iterator wraps at 32 bits on purpose }
{$IFOPT Q+}{$DEFINE OVERFLOW_WAS_ON}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE RANGE_WAS_ON}{$R-}{$ENDIF}
function Gen3Step(var It: Cardinal; Key: Byte): Cardinal;
begin
  It := It * Gen3Mul + Key;
  Result := It;
end;
{$IFDEF RANGE_WAS_ON}{$R+}{$ENDIF}
{$IFDEF OVERFLOW_WAS_ON}{$Q+}{$ENDIF}

function Gen3Insert(var It: Cardinal; Key: Byte; const Msg: string): string;
var
  P: Integer;
  Junk: Char;
begin
  Gen3Step(It, Key);
  P := Integer((It and $FFFF) mod Cardinal(Length(Msg))) + 1; { 1-based }
  Junk := Chr(((It shr 16) and $7F) + $20);
  Result := Copy(Msg, 1, P - 1) + Junk + Copy(Msg, P, MaxInt);
end;

function Gen3Remove(var It: Cardinal; Key: Byte; const Line: string): string;
var
  P: Integer;
begin
  Gen3Step(It, Key);
  P := Integer((It and $FFFF) mod Cardinal(Length(Line)));
  Result := Copy(Line, 1, P) + Copy(Line, P + 2, MaxInt);
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

{ gen 4/5 partial XOR: one LCG step per 4-byte group present, at most
  Gen4Groups groups; a short last group still steps }
{$IFOPT Q+}{$DEFINE OVERFLOW4_WAS_ON}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE RANGE4_WAS_ON}{$R-}{$ENDIF}
procedure Gen4Xor(var It: Cardinal; Key: Byte; var Body: string);
var
  Groups, G, J, P: Integer;
  K: Cardinal;
begin
  Groups := (Length(Body) + 3) div 4;
  if Groups > Gen4Groups then Groups := Gen4Groups;
  UniqueString(Body);
  for G := 0 to Groups - 1 do
  begin
    It := It * Gen3Mul + Key;
    K := It;
    for J := 0 to 3 do
    begin
      P := G * 4 + J + 1;
      if P > Length(Body) then Break;
      Body[P] := Chr(Ord(Body[P]) xor ((K shr (8 * J)) and $FF));
    end;
  end;
end;
{$IFDEF RANGE4_WAS_ON}{$R+}{$ENDIF}
{$IFDEF OVERFLOW4_WAS_ON}{$Q+}{$ENDIF}

function TGraalClient.EncodeFrame(const Plain: string): string;
begin
  Result := ZCompress(Plain);
end;

function TGraalClient.DecodeFrame(const Body: string; out Plain: string): Boolean;
begin
  Result := ZDecompress(Body, Plain);
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
end;

function TGraalClient.Connected: Boolean;
begin
  Result := FSocket.Connected;
end;

function TGraalClient.EncodeMessage(const Msg: string): string;
begin
  Result := Msg;
end;

function TGraalClient.SendPacket(Id: Integer; const Data: string): Boolean;
var
  Msg: string;
begin
  Result := False;
  if Pos(#10, Data) > 0 then Exit; { silently dropped, as in 2.05 }
  Msg := EncodeMessage(GChar(Id) + Data + #10);
  if Length(FOut) + Length(Msg) > OutFlushAt then
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
  FSocket.Send(Chr((Length(Z) shr 8) and $FF) + Chr(Length(Z) and $FF) + Z);
  Inc(FFramesOut);
  Inc(FBytesOut, Length(Z) + 2);
end;

procedure TGraalClient.Poll;
var
  Got: string;
begin
  if not Connected then Exit;
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

function TAdventureClient.Connect(const Host: string; Port: Word): Boolean;
begin
  FIterator := Gen3Seed;
  FKey := Random(256) and $7F;
  FLoginSent := False;
  FLoginFrame := True;
  FOutIt := Gen3Seed;
  FInIt := Gen3Seed;
  Result := inherited Connect(Host, Port);
end;

{ gen 4 has no per-message insertion: the frame codec does it all }
function TAdventureClient.EncodeMessage(const Msg: string): string;
begin
  FLoginSent := True;
  Result := Msg;
end;

function TAdventureClient.EncodeFrame(const Plain: string): string;
begin
  if FLoginFrame then
  begin
    { the login frame: zlib, no XOR, so the server can read the key }
    FLoginFrame := False;
    Result := ZCompress(Plain);
    Exit;
  end;
  Result := BZ2Compress(Plain);
  Gen4Xor(FOutIt, FKey, Result);
end;

function TAdventureClient.DecodeFrame(const Body: string; out Plain: string): Boolean;
var
  B: string;
begin
  B := Body;
  Gen4Xor(FInIt, FKey, B);
  Result := BZ2Decompress(B, Plain, InFrameMax);
end;

procedure TAdventureClient.SendLogin(const Account, Password, Language: string);
begin
  { GCHAR type, GCHAR key, token, GSTRING account, GSTRING password. The
    type byte doubles as "id 0" of the first message. }
  SendPacket(ClientType, GChar(FKey) + ClientVersionToken + GString(Account) +
    GString(Password));
  { the login goes alone in its plain frame; the rest is gen 4 }
  Flush;
  SendPacket(PLI_LANGUAGE, Language);
  { new in 2.17: the tamper check, once, right after the language }
  SendPacket(PLI_TAMPERCHECK, TamperCheck221);
end;

procedure TAdventureClient.SendToAll(const Text: string);
var
  T: string;
begin
  T := Copy(Text, 1, 200);
  SendPacket(PLI_TOALL, GChar(Length(T)) + T);
end;

end.
