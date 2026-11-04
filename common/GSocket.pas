{ GSocket: the TCP link under TGraalClient.

  2.05 polls its socket from the 50 ms game tick rather than blocking on it.
  This unit gives the same shape: a blocking connect, then a non-blocking
  socket that Poll drains into a string. Free Pascal's `sockets` unit is used
  on every platform it supports; Delphi builds use WinSock directly. }
unit GSocket;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TGSocket = class
  private
    FHandle: Integer;
    FConnected: Boolean;
    FLastError: string;
  public
    constructor Create;
    destructor Destroy; override;
    { Host is a dotted IPv4 address or a name. }
    function Connect(const Host: string; Port: Word): Boolean;
    procedure Close;
    { Sends all of Data; returns False and closes the link on error. }
    function Send(const Data: string): Boolean;
    { Appends whatever is waiting to Buffer. Returns False when the peer
      closed the link or an error happened. }
    function Poll(var Buffer: string): Boolean;
    property Connected: Boolean read FConnected;
    property LastError: string read FLastError;
  end;

implementation

uses
  SysUtils,
{$IFDEF FPC}
  sockets, {$IFDEF UNIX} BaseUnix, netdb, {$ENDIF} {$IFDEF WINDOWS} WinSock2, {$ENDIF}
{$ELSE}
  WinSock, Windows,
{$ENDIF}
  Classes;

{$IFNDEF FPC}
var
  WSAReady: Boolean = False;

procedure EnsureWSA;
var
  D: TWSAData;
begin
  if not WSAReady then
    WSAReady := WSAStartup($0101, D) = 0;
end;
{$ENDIF}

function ResolveIPv4(const Host: string; out Addr: Cardinal): Boolean;
{$IFDEF FPC}
{$IFDEF UNIX}
var
  H: THostEntry;
  A: in_addr;
begin
  A := StrToNetAddr(Host);
  if A.s_addr <> 0 then
  begin
    Addr := A.s_addr;
    Result := True;
    Exit;
  end;
  Result := ResolveHostByName(Host, H);
  if Result then
    Addr := htonl(H.Addr.s_addr);
end;
{$ELSE}
var
  A: in_addr;
begin
  A := StrToNetAddr(Host);
  Addr := A.s_addr;
  Result := Addr <> 0;
end;
{$ENDIF}
{$ELSE}
var
  P: PHostEnt;
begin
  EnsureWSA;
  Addr := inet_addr(PChar(Host));
  Result := Addr <> Cardinal(INADDR_NONE);
  if not Result then
  begin
    P := gethostbyname(PChar(Host));
    Result := P <> nil;
    if Result then
      Addr := PCardinal(P^.h_addr_list^)^;
  end;
end;
{$ENDIF}

{ TGSocket }

constructor TGSocket.Create;
begin
  inherited Create;
  FHandle := -1;
end;

destructor TGSocket.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TGSocket.Connect(const Host: string; Port: Word): Boolean;
var
{$IFDEF FPC}
  SA: TInetSockAddr;
{$ELSE}
  SA: TSockAddrIn;
  Arg: Integer;
{$ENDIF}
  Addr: Cardinal;
begin
  Result := False;
  Close;
  if not ResolveIPv4(Host, Addr) then
  begin
    FLastError := 'cannot resolve ' + Host;
    Exit;
  end;
{$IFDEF FPC}
  FHandle := fpSocket(AF_INET, SOCK_STREAM, 0);
  if FHandle < 0 then
  begin
    FLastError := 'socket() failed';
    Exit;
  end;
  FillChar(SA, SizeOf(SA), 0);
  SA.sin_family := AF_INET;
  SA.sin_port := htons(Port);
  SA.sin_addr.s_addr := Addr;
  if fpConnect(FHandle, @SA, SizeOf(SA)) <> 0 then
  begin
    FLastError := Format('connect to %s:%d failed (%d)', [Host, Port, SocketError]);
    CloseSocket(FHandle);
    FHandle := -1;
    Exit;
  end;
{$IFDEF UNIX}
  fpfcntl(FHandle, F_SETFL, fpfcntl(FHandle, F_GETFL, 0) or O_NONBLOCK);
{$ENDIF}
{$IFDEF WINDOWS}
  Addr := 1;
  ioctlsocket(FHandle, Integer(FIONBIO), Addr);
{$ENDIF}
{$ELSE}
  EnsureWSA;
  FHandle := socket(AF_INET, SOCK_STREAM, 0);
  if FHandle = Integer(INVALID_SOCKET) then
  begin
    FLastError := 'socket() failed';
    FHandle := -1;
    Exit;
  end;
  FillChar(SA, SizeOf(SA), 0);
  SA.sin_family := AF_INET;
  SA.sin_port := htons(Port);
  SA.sin_addr.S_addr := Integer(Addr);
  if WinSock.connect(FHandle, SA, SizeOf(SA)) <> 0 then
  begin
    FLastError := Format('connect to %s:%d failed (%d)', [Host, Port, WSAGetLastError]);
    closesocket(FHandle);
    FHandle := -1;
    Exit;
  end;
  Arg := 1;
  ioctlsocket(FHandle, FIONBIO, Arg);
{$ENDIF}
  FConnected := True;
  Result := True;
end;

procedure TGSocket.Close;
begin
  if FHandle >= 0 then
  begin
{$IFDEF FPC}
    CloseSocket(FHandle);
{$ELSE}
    closesocket(FHandle);
{$ENDIF}
  end;
  FHandle := -1;
  FConnected := False;
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
  Result := WSAGetLastError = WSAEWOULDBLOCK;
{$ENDIF}
end;

function TGSocket.Send(const Data: string): Boolean;
var
  Done, N: Integer;
begin
  Result := False;
  if not FConnected then Exit;
  Done := 0;
  while Done < Length(Data) do
  begin
{$IFDEF FPC}
    N := fpSend(FHandle, @Data[Done + 1], Length(Data) - Done, 0);
{$ELSE}
    N := WinSock.send(FHandle, Data[Done + 1], Length(Data) - Done, 0);
{$ENDIF}
    if N > 0 then
      Inc(Done, N)
    else if (N < 0) and WouldBlock then
      Sleep(1)
    else
    begin
      FLastError := 'send failed';
      Close;
      Exit;
    end;
  end;
  Result := True;
end;

function TGSocket.Poll(var Buffer: string): Boolean;
var
  Chunk: array[0..8191] of Char;
  N, Old: Integer;
begin
  Result := False;
  if not FConnected then Exit;
  repeat
{$IFDEF FPC}
    N := fpRecv(FHandle, @Chunk[0], SizeOf(Chunk), 0);
{$ELSE}
    N := WinSock.recv(FHandle, Chunk, SizeOf(Chunk), 0);
{$ENDIF}
    if N > 0 then
    begin
      Old := Length(Buffer);
      SetLength(Buffer, Old + N);
      Move(Chunk[0], Buffer[Old + 1], N);
    end
    else if N = 0 then
    begin
      FLastError := 'connection closed by the server';
      Close;
      Exit;
    end
    else if WouldBlock then
      Break
    else
    begin
      FLastError := 'recv failed';
      Close;
      Exit;
    end;
  until False;
  Result := True;
end;

end.
