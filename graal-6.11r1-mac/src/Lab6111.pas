{ Lab6111: the lab-only continuation after the connector hello.

  verified-from-evidence:
    none for the lab session. The 6.11 client has no fixed hello: the
    first eight bytes come from the connector script, and this project's
    script sends the placeholder SEI00001.
  provisional adapter:
    the sockets are the Free Pascal sockets unit, the same family GSocket
    uses. No new library.
  lab-only fixture:
    every length-prefixed message below. The marker is the text LABONLY.
    This is not a 6.11 session and not a v7 session.

  TLabServer accepts only the SEI00001 hello. With Fixture set (the
  default) it then continues on the lab fixture; with Fixture off it
  records the hello and stays quiet, which is all a real server can do
  until SEI00001 handling lands in seihai-gserver-v2. TLabConnector
  answers GET /conf.gs with one reply given by the caller.

  The listeners bind 127.0.0.1 only. They do not open a datagram socket. }
unit Lab6111;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  LabReadyText = 'LABONLY';
  ltReady = 1;
  ltYourId = 2;
  ltSpawn = 3;
  ltMove = 4;
  ltProps = 5;
  ctMove = 1;
  LabSelfId = 1;
  LabOtherId = 2;

function U16BE(N: Integer): string;
function LabPack(const Payload: string): string;
function LabTryPop(var Buf: string; out Payload: string): Boolean;
function LabReadyMsg: string;
function LabYourIdMsg(Id: Integer): string;
function LabSpawnMsg(Id, Kind, X, Y: Integer; const Props: string): string;
function LabMoveMsg(Id, X, Y: Integer): string;
function LabPropsMsg(Id: Integer; const Props: string): string;
function LabClientMove(X, Y: Integer): string;

function LabOtherProps(Step: Integer): string;

type
  TLabServer = class
  public
    Port: Word;
    LastError: string;
    GotHello: Boolean;
    HelloCount: Integer;
    { The eight hello bytes the peer sent (SEI00001). }
    Hello: string;
    { Continue on the lab fixture after the hello. }
    Fixture: Boolean;
    { Bytes after an SEI00001 hello, kept and not parsed. }
    AfterSei: string;
    Moves: Integer;
    PlayerX, PlayerY: Integer;
    constructor Create;
    destructor Destroy; override;
    function Listen(APort: Word): Boolean;
    procedure Pump;
    procedure Close;
  private
    FListen: Integer;
    FPeer: Integer;
    FAcc: string;
    FBuf: string;
    procedure DropPeer;
    procedure TakePeerBytes(const Chunk: string);
    function SendAll(const Data: string): Boolean;
  end;

  { Plain HTTP/1.0 responder for GET /conf.gs on 127.0.0.1. One request
    per connection, then it closes. Reply is the body it serves. }
  TLabConnector = class
  public
    Port: Word;
    LastError: string;
    Reply: string;
    Requests: Integer;
    LastRequest: string;
    { The whole request head of the last request. }
    LastHeaders: string;
    constructor Create;
    destructor Destroy; override;
    function Listen(APort: Word): Boolean;
    procedure Pump;
    procedure Close;
  private
    FListen: Integer;
    FPeer: Integer;
    FReq: string;
    procedure DropPeer;
  end;

implementation

uses
  SysUtils, Frame6111, Props6111, Connector6111,
{$IFDEF FPC}
  {$IFDEF WINDOWS} WinSock2, {$ENDIF}
  sockets,
  {$IFDEF UNIX} BaseUnix, {$ENDIF}
{$ENDIF}
  Classes;

function U16BE(N: Integer): string;
begin
  Result := Chr((N shr 8) and 255) + Chr(N and 255);
end;

function RdU16(const S: string; At: Integer): Integer;
begin
  Result := Ord(S[At]) shl 8 + Ord(S[At + 1]);
end;

function LabPack(const Payload: string): string;
begin
  if (Length(Payload) < 0) or (Length(Payload) > 65535) then
    Result := ''
  else
    Result := U16BE(Length(Payload)) + Payload;
end;

function LabTryPop(var Buf: string; out Payload: string): Boolean;
var
  N: Integer;
begin
  Payload := '';
  Result := False;
  if Length(Buf) < 2 then Exit;
  N := RdU16(Buf, 1);
  if Length(Buf) < 2 + N then Exit;
  Payload := Copy(Buf, 3, N);
  Delete(Buf, 1, 2 + N);
  Result := True;
end;

function LabReadyMsg: string;
begin
  Result := LabPack(Chr(ltReady) + LabReadyText);
end;

function LabYourIdMsg(Id: Integer): string;
begin
  Result := LabPack(Chr(ltYourId) + U16BE(Id));
end;

function LabSpawnMsg(Id, Kind, X, Y: Integer; const Props: string): string;
begin
  Result := LabPack(Chr(ltSpawn) + U16BE(Id) + Chr(Kind) + U16BE(X) + U16BE(Y) +
    U16BE(Length(Props)) + Props);
end;

function LabMoveMsg(Id, X, Y: Integer): string;
begin
  Result := LabPack(Chr(ltMove) + U16BE(Id) + U16BE(X) + U16BE(Y));
end;

function LabPropsMsg(Id: Integer; const Props: string): string;
begin
  Result := LabPack(Chr(ltProps) + U16BE(Id) + U16BE(Length(Props)) + Props);
end;

function LabClientMove(X, Y: Integer): string;
begin
  Result := LabPack(Chr(ctMove) + U16BE(X) + U16BE(Y));
end;

function LabOtherProps(Step: Integer): string;
begin
  Result := LabEncodeProps('name=other' + #10 + 'ap=1' + #10 + 'step=' +
    IntToStr(Step));
end;

function LoopAddr: Cardinal;
begin
  Result := StrToNetAddr('127.0.0.1').s_addr;
end;

function WouldBlock: Boolean;
begin
{$IFDEF FPC}
{$IFDEF UNIX}
  Result := (SocketError = ESysEAGAIN) or (SocketError = ESysEWOULDBLOCK);
{$ELSE}
  Result := SocketError = WSAEWOULDBLOCK;
{$ENDIF}
{$ELSE}
  Result := False;
{$ENDIF}
end;

procedure SetNonBlock(S: Integer);
{$IFDEF WINDOWS}
var
  Arg: Cardinal;
{$ENDIF}
begin
{$IFDEF UNIX}
  fpfcntl(S, F_SETFL, fpfcntl(S, F_GETFL, 0) or O_NONBLOCK);
{$ENDIF}
{$IFDEF WINDOWS}
  Arg := 1;
  ioctlsocket(S, Longint(FIONBIO), Arg);
{$ENDIF}
end;

constructor TLabServer.Create;
begin
  inherited Create;
  Fixture := True;
  FListen := -1;
  FPeer := -1;
  PlayerX := 0;
  PlayerY := 0;
end;

destructor TLabServer.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TLabServer.DropPeer;
begin
  if FPeer >= 0 then
  begin
    CloseSocket(FPeer);
    FPeer := -1;
  end;
  FAcc := '';
  FBuf := '';
  GotHello := False;
  Hello := '';
end;

procedure TLabServer.Close;
begin
  DropPeer;
  if FListen >= 0 then
  begin
    CloseSocket(FListen);
    FListen := -1;
  end;
end;

function OpenLoopListener(APort: Word; out Sock: Integer; out BoundPort: Word;
  out Err: string): Boolean;
var
  SA: sockaddr_in;
  Len: TSockLen;
  Opt: Integer;
begin
  Result := False;
  Err := '';
  Sock := -1;
  BoundPort := 0;
{$IFNDEF FPC}
  Err := 'the lab listener needs Free Pascal sockets';
  Exit;
{$ENDIF}
  Sock := fpSocket(AF_INET, SOCK_STREAM, 0);
  if Sock < 0 then
  begin
    Err := 'socket() failed';
    Exit;
  end;
  Opt := 1;
  fpSetSockOpt(Sock, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));
  FillChar(SA, SizeOf(SA), 0);
  SA.sin_family := AF_INET;
  SA.sin_port := htons(APort);
  SA.sin_addr.s_addr := LoopAddr;
  if fpBind(Sock, @SA, SizeOf(SA)) <> 0 then
    Err := 'bind failed'
  else if fpListen(Sock, 1) <> 0 then
    Err := 'listen failed'
  else
  begin
    Len := SizeOf(SA);
    FillChar(SA, SizeOf(SA), 0);
    if fpGetSockName(Sock, @SA, @Len) <> 0 then
      Err := 'getsockname failed';
  end;
  if Err <> '' then
  begin
    CloseSocket(Sock);
    Sock := -1;
    Exit;
  end;
  BoundPort := ntohs(SA.sin_port);
  SetNonBlock(Sock);
  Result := True;
end;

{ Accepts one waiting loopback peer, non-blocking. -1 when none. }
function AcceptLoopPeer(Listener: Integer): Integer;
var
  SA: sockaddr_in;
  Len: TSockLen;
begin
  Len := SizeOf(SA);
  FillChar(SA, SizeOf(SA), 0);
  Result := fpAccept(Listener, @SA, @Len);
  if Result < 0 then Exit;
  if SA.sin_addr.s_addr <> LoopAddr then
  begin
    CloseSocket(Result);
    Result := -1;
    Exit;
  end;
  SetNonBlock(Result);
end;

function TLabServer.Listen(APort: Word): Boolean;
begin
  Close;
  LastError := '';
  Result := OpenLoopListener(APort, FListen, Port, LastError);
end;

function TLabServer.SendAll(const Data: string): Boolean;
var
  Done, N: Integer;
begin
  Result := False;
  if (FPeer < 0) or (Data = '') then Exit;
  Done := 0;
  while Done < Length(Data) do
  begin
    N := fpSend(FPeer, @Data[Done + 1], Length(Data) - Done, 0);
    if N > 0 then
      Inc(Done, N)
    else if (N < 0) and WouldBlock then
      Sleep(1)
    else
    begin
      LastError := 'lab send failed';
      DropPeer;
      Exit;
    end;
  end;
  Result := True;
end;

procedure TLabServer.TakePeerBytes(const Chunk: string);
var
  Payload: string;
  X, Y: Integer;
begin
  if not GotHello then
  begin
    FAcc := FAcc + Chunk;
    if Length(FAcc) < 8 then Exit;
    if Copy(FAcc, 1, 8) <> SeiToken then
    begin
      LastError := 'lab peer did not send the SEI00001 connector hello';
      DropPeer;
      Exit;
    end;
    GotHello := True;
    Hello := SeiToken;
    Inc(HelloCount);
    if not Fixture then
    begin
      { The game side of SEI00001 is pending in seihai-gserver-v2. }
      AfterSei := Copy(FAcc, 9, MaxInt);
      FAcc := '';
      Exit;
    end;
    FBuf := Copy(FAcc, 9, MaxInt);
    FAcc := '';
    if not SendAll(LabReadyMsg + LabYourIdMsg(LabSelfId) +
      LabSpawnMsg(LabOtherId, 2, 64, 48, LabOtherProps(1))) then Exit;
  end
  else if not Fixture then
  begin
    AfterSei := AfterSei + Chunk;
    Exit;
  end
  else
    FBuf := FBuf + Chunk;

  while LabTryPop(FBuf, Payload) do
  begin
    if (Length(Payload) >= 5) and (Ord(Payload[1]) = ctMove) then
    begin
      X := RdU16(Payload, 2);
      Y := RdU16(Payload, 4);
      PlayerX := X;
      PlayerY := Y;
      Inc(Moves);
      if not SendAll(LabMoveMsg(LabSelfId, X, Y) +
        LabPropsMsg(LabOtherId, LabOtherProps(2))) then Exit;
    end;
  end;
end;

procedure TLabServer.Pump;
var
  N, Peer: Integer;
  Buf: array[0..2047] of Byte;
  Chunk: string;
begin
  if FListen < 0 then Exit;
  if FPeer < 0 then
  begin
    Peer := AcceptLoopPeer(FListen);
    if Peer < 0 then Exit;
    FPeer := Peer;
    FAcc := '';
    FBuf := '';
    GotHello := False;
  end;
  N := fpRecv(FPeer, @Buf[0], SizeOf(Buf), 0);
  if N > 0 then
  begin
    SetString(Chunk, PAnsiChar(@Buf[0]), N);
    TakePeerBytes(Chunk);
  end
  else if N = 0 then
    DropPeer
  else if not WouldBlock then
    DropPeer;
end;

{ ---- TLabConnector ---- }

constructor TLabConnector.Create;
begin
  inherited Create;
  FListen := -1;
  FPeer := -1;
end;

destructor TLabConnector.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TLabConnector.DropPeer;
begin
  if FPeer >= 0 then
  begin
    CloseSocket(FPeer);
    FPeer := -1;
  end;
  FReq := '';
end;

procedure TLabConnector.Close;
begin
  DropPeer;
  if FListen >= 0 then
  begin
    CloseSocket(FListen);
    FListen := -1;
  end;
end;

function TLabConnector.Listen(APort: Word): Boolean;
begin
  Close;
  LastError := '';
  Result := OpenLoopListener(APort, FListen, Port, LastError);
end;

procedure TLabConnector.Pump;
var
  N, Done: Integer;
  Buf: array[0..2047] of Byte;
  Chunk, Line, Answer: string;
begin
  if FListen < 0 then Exit;
  if FPeer < 0 then
  begin
    FPeer := AcceptLoopPeer(FListen);
    if FPeer < 0 then Exit;
    FReq := '';
  end;
  N := fpRecv(FPeer, @Buf[0], SizeOf(Buf), 0);
  if N > 0 then
  begin
    SetString(Chunk, PAnsiChar(@Buf[0]), N);
    FReq := FReq + Chunk;
  end
  else if (N = 0) or not WouldBlock then
  begin
    DropPeer;
    Exit;
  end;
  if Pos(#13#10#13#10, FReq) = 0 then
  begin
    if Length(FReq) > 8192 then DropPeer;
    Exit;
  end;
  Inc(Requests);
  Line := Copy(FReq, 1, Pos(#13#10, FReq) - 1);
  LastRequest := Line;
  LastHeaders := Copy(FReq, 1, Pos(#13#10#13#10, FReq) - 1);
  if (Copy(Line, 1, Length('GET ' + ConfPath)) = 'GET ' + ConfPath) and (Reply <> '') then
    Answer := 'HTTP/1.0 200 OK' + #13#10 + 'Content-Type: application/octet-stream' +
      #13#10 + 'Content-Length: ' + IntToStr(Length(Reply)) + #13#10#13#10 + Reply
  else
    Answer := 'HTTP/1.0 404 Not Found' + #13#10 + 'Content-Length: 0' + #13#10#13#10;
  Done := 0;
  while Done < Length(Answer) do
  begin
    N := fpSend(FPeer, @Answer[Done + 1], Length(Answer) - Done, 0);
    if N > 0 then
      Inc(Done, N)
    else if (N < 0) and WouldBlock then
      Sleep(1)
    else
    begin
      LastError := 'connector send failed';
      Break;
    end;
  end;
  DropPeer;
end;

end.
