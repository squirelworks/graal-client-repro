{ GraalClient: TGraalClient and TAdventureClient, the game link of a
  generation-2 build (1.21 to 1.39).

  The split into TGraalClient and TAdventureClient is the 2.05 one
  (graal_analysis client-internals/client-architecture-205.md); this build
  was made from the 2.05 rebuild with the gen-3 step taken out.

  Send pipeline (generation 2):
    1. message = GCHAR(id) + data + #10; data holding #10 is dropped
    2. append to the out buffer (no cipher, no inserted byte)
    3. flush: zlib the whole buffer, prefix u16be length; at 0x1000 bytes
       or at the end of the tick; over 0x40000 queued drops the link
  Receive: u16be -> inflate -> split on #10, with the PLO_RAWDATA escape.
  Login line: id 0, the 8-byte token, GSTRING account, GSTRING password
  (seen in lab captures of 1.21, 1.28 beta 2 and 1.3 test; the 1.33 and
  1.39 profiles have the same shape). No key byte, no language packet. }
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
  public
    { Sends the login line. Language is not sent by a gen-2 build. }
    procedure SendLogin(const Account, Password, Language: string);
    procedure SendToAll(const Text: string);
  end;

{ The login line as it goes on the wire, before zlib: id 0 (chr 32), the
  token, the account and the password, then #10. For tests. }
function LoginLine(const Account, Password: string): string;

implementation

uses
  SysUtils, GTypes, GZlib, Protocol13test;

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
  Z := ZCompress(FOut);
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
    if not ZDecompress(Copy(FInRaw, P + 2, Len), Body) then
    begin
      Fail('bad zlib frame from the server');
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

function LoginLine(const Account, Password: string): string;
begin
  Result := GChar(ClientType) + ClientVersionToken + GString(Account) +
    GString(Password) + #10;
end;

procedure TAdventureClient.SendLogin(const Account, Password, Language: string);
begin
  { the type byte doubles as "id 0" of the first message }
  SendPacket(ClientType, ClientVersionToken + GString(Account) + GString(Password));
end;

procedure TAdventureClient.SendToAll(const Text: string);
var
  T: string;
begin
  T := Copy(Text, 1, 200);
  SendPacket(PLI_TOALL, GChar(Length(T)) + T);
end;

end.
