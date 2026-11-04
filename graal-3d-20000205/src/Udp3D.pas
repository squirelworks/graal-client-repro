{ Udp3D: the client-to-client UDP socket of Graal3D.

  The client binds one UDP socket (port 0, or the fixed port from the
  config) unless noudp is set, and tells the server its port in prop 15.
  Datagrams carry no length and no compression (graal_analysis
  graal3d/protocol.md, "UDP"). Addresses here are in_addr words as they
  lie in memory, read as little-endian integers: the same value prop 16
  carries on the wire. }
unit Udp3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TUdp3D = class
  private
    FHandle: Integer;
    FPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { Binds to Port (0 = any); False if that fails. }
    function Open(Port: Integer): Boolean;
    procedure Close;
    function SendTo(Addr: Cardinal; Port: Integer; const Data: string): Boolean;
    { One waiting datagram, or False when none is waiting. }
    function Receive(out Data: string; out Addr: Cardinal; out Port: Integer): Boolean;
    property Port: Integer read FPort;
    function Active: Boolean;
  end;

implementation

uses
  SysUtils,
{$IFDEF FPC}
  {$IFDEF WINDOWS} WinSock2, {$ENDIF} sockets {$IFDEF UNIX}, BaseUnix {$ENDIF};
{$ELSE}
  WinSock, Windows;
{$ENDIF}

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

constructor TUdp3D.Create;
begin
  inherited Create;
  FHandle := -1;
end;

destructor TUdp3D.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TUdp3D.Active: Boolean;
begin
  Result := FHandle >= 0;
end;

function TUdp3D.Open(Port: Integer): Boolean;
var
{$IFDEF FPC}
  SA: TInetSockAddr;
  Len: LongInt;
{$ELSE}
  SA: TSockAddrIn;
  Len: Integer;
{$ENDIF}
  Arg: Cardinal;
begin
  Result := False;
  Close;
{$IFDEF FPC}
  FHandle := fpSocket(AF_INET, SOCK_DGRAM, 0);
{$ELSE}
  EnsureWSA;
  FHandle := socket(AF_INET, SOCK_DGRAM, 0);
{$ENDIF}
  if FHandle < 0 then
  begin
    FHandle := -1;
    Exit;
  end;
  FillChar(SA, SizeOf(SA), 0);
  SA.sin_family := AF_INET;
  SA.sin_port := htons(Port);
  SA.sin_addr.s_addr := 0;
{$IFDEF FPC}
  if fpBind(FHandle, @SA, SizeOf(SA)) <> 0 then
{$ELSE}
  if bind(FHandle, SA, SizeOf(SA)) <> 0 then
{$ENDIF}
  begin
    Close;
    Exit;
  end;
  Len := SizeOf(SA);
{$IFDEF FPC}
  fpGetSockName(FHandle, @SA, @Len);
{$ELSE}
  getsockname(FHandle, SA, Len);
{$ENDIF}
  FPort := ntohs(SA.sin_port);
  Arg := 1;
{$IFDEF FPC}
{$IFDEF UNIX}
  fpfcntl(FHandle, F_SETFL, fpfcntl(FHandle, F_GETFL, 0) or O_NONBLOCK);
{$ENDIF}
{$IFDEF WINDOWS}
  ioctlsocket(FHandle, Integer(FIONBIO), Arg);
{$ENDIF}
{$ELSE}
  ioctlsocket(FHandle, FIONBIO, Integer(Arg));
{$ENDIF}
  if Arg = 0 then ;
  Result := True;
end;

procedure TUdp3D.Close;
begin
  if FHandle >= 0 then
    CloseSocket(FHandle);
  FHandle := -1;
  FPort := 0;
end;

function TUdp3D.SendTo(Addr: Cardinal; Port: Integer; const Data: string): Boolean;
var
{$IFDEF FPC}
  SA: TInetSockAddr;
{$ELSE}
  SA: TSockAddrIn;
{$ENDIF}
begin
  Result := False;
  if (FHandle < 0) or (Data = '') then Exit;
  FillChar(SA, SizeOf(SA), 0);
  SA.sin_family := AF_INET;
  SA.sin_port := htons(Port);
  SA.sin_addr.s_addr := Addr;
{$IFDEF FPC}
  Result := fpSendTo(FHandle, @Data[1], Length(Data), 0, @SA, SizeOf(SA)) = Length(Data);
{$ELSE}
  Result := WinSock.sendto(FHandle, Data[1], Length(Data), 0, SA, SizeOf(SA)) = Length(Data);
{$ENDIF}
end;

function TUdp3D.Receive(out Data: string; out Addr: Cardinal; out Port: Integer): Boolean;
var
{$IFDEF FPC}
  SA: TInetSockAddr;
  Len: LongInt;
{$ELSE}
  SA: TSockAddrIn;
  Len: Integer;
{$ENDIF}
  Buf: array[0..1023] of Char;
  N: Integer;
begin
  Result := False;
  Data := '';
  Addr := 0;
  Port := 0;
  if FHandle < 0 then Exit;
  Len := SizeOf(SA);
  FillChar(SA, SizeOf(SA), 0);
{$IFDEF FPC}
  N := fpRecvFrom(FHandle, @Buf[0], SizeOf(Buf), 0, @SA, @Len);
{$ELSE}
  N := WinSock.recvfrom(FHandle, Buf, SizeOf(Buf), 0, SA, Len);
{$ENDIF}
  if N <= 0 then Exit;
  SetLength(Data, N);
  Move(Buf[0], Data[1], N);
  Addr := SA.sin_addr.s_addr;
  Port := ntohs(SA.sin_port);
  Result := True;
end;

end.
