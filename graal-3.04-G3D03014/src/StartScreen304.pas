{ StartScreen304: what 3.04 plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step, its fallback hosts and
  its character.

  3.04 asks for the list with id 7 (key, G3D30123, newmain) and id 1
  (account, password) in one plain zlib frame (ListServer304). The hosts
  come from license/license.graal: line 0, then the fallbacks on lines 5
  and 6, tried in that order until one connects (graal_analysis
  protocol/v3x-clients.md). 3.04 checks that file's RSA signature; this
  rebuild does not.

  The start screen is this project's own (common/GStartScreen.pas); the
  original start window and its pictures are never drawn. }
unit StartScreen304;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, ListServer304, Adventure;

type
  TListFetch304 = class(TListFetch)
  public
    Client: TListServerClient;
    StartMs: Int64;
    Fallbacks: array of string;
    { The next fallback to try, and what the request sends. }
    NextFallback, ListPort: Integer;
    ListAccount, ListPassword: string;
    { The license.graal fallbacks, tried in turn when a host does not
      connect, or connects and closes or stays silent before any reply. }
    procedure SetFallbacks(const H: TListHosts);
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  private
    function TryNextHost: Boolean;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter304 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

{ Where 3.04 asks for the server list: listserver.graal.in on 14922 first
  (the project's rule), then the license/license.graal hosts (line 0, then
  lines 5 and 6) on the same port; listserver.txt in Dir still wins for the
  first host. Hosts.Hosts[0] is the first host; SetFallbacks takes the rest. }
procedure ListHostsFor(const Dir: string; out Host: string; out Port: Integer;
  out Hosts: TListHosts);

implementation

uses
  SysUtils, Classes, GTypes, GAssetDirs;

procedure ListHostsFor(const Dir: string; out Host: string; out Port: Integer;
  out Hosts: TListHosts);
var
  I: Integer;
begin
  if AssetPath('license/license.graal') <> '' then
    Hosts := LoadListHosts(AssetPath('license/license.graal'))
  else
    Hosts := LoadListHosts(InstallPath(Dir, 'license' + PathDelim + 'license.graal'));
  SetLength(Hosts.Hosts, Length(Hosts.Hosts) + 1);
  for I := High(Hosts.Hosts) downto 1 do Hosts.Hosts[I] := Hosts.Hosts[I - 1];
  Hosts.Hosts[0] := DefaultListHost;
  Hosts.Port := DefaultListPort;
  ReadListServer(Dir, DefaultListHost, Hosts.Port, Host, Port);
end;

procedure TListFetch304.SetFallbacks(const H: TListHosts);
var
  I: Integer;
begin
  { line 0 is the first host the screen asks; the rest are fallbacks }
  SetLength(Fallbacks, 0);
  for I := 1 to High(H.Hosts) do
  begin
    SetLength(Fallbacks, Length(Fallbacks) + 1);
    Fallbacks[High(Fallbacks)] := H.Hosts[I];
  end;
end;

procedure TListFetch304.Start(const Host: string; Port: Integer;
  const Account, Password: string);
begin
  FreeAndNil(Client);
  SetLength(Servers, 0);
  Done := False;
  Failed := False;
  ListPort := Port;
  ListAccount := Account;
  ListPassword := Password;
  NextFallback := 0;
  StartMs := NowMs;
  Client := TListServerClient.Create;
  Status := Format('asking %s:%d for the server list...', [Host, Port]);
  if Client.Connect(Host, Port) then
    Client.SendRequest(Account, Password)
  else if not TryNextHost then
  begin
    Status := Format('no listserver at %s:%d (%s)', [Host, Port, Client.LastError]);
    Failed := True;
  end;
end;

{ Connects to the next fallback host that takes the connection and sends
  the request there. False when none is left. }
function TListFetch304.TryNextHost: Boolean;
begin
  Result := False;
  while NextFallback <= High(Fallbacks) do
  begin
    Inc(NextFallback);
    FreeAndNil(Client);
    Client := TListServerClient.Create;
    if Client.Connect(Fallbacks[NextFallback - 1], ListPort) then
    begin
      Status := Format('asking %s:%d for the server list...', [Fallbacks[NextFallback - 1], ListPort]);
      StartMs := NowMs;
      Client.SendRequest(ListAccount, ListPassword);
      Result := True;
      Exit;
    end;
  end;
end;

procedure TListFetch304.Poll;
begin
  if (Client = nil) or Done or Failed then Exit;
  Client.Poll;
  Client.CheckSecureList;
  if Client.Status <> '' then
    Status := StringReplace(Client.Status, #10, ' ', [rfReplaceAll]);
  if Client.Error <> '' then
  begin
    Status := 'listserver: ' + Client.Error;
    Failed := True;
    Exit;
  end;
  if Client.GotList then
  begin
    Servers := Client.Servers;
    Done := True;
    if Client.Status = '' then
      Status := Format('%d servers', [Length(Servers)]);
    Client.Disconnect;
    Exit;
  end;
  if not Client.Connected then
  begin
    Status := 'the listserver closed the link: ' + Client.LastError;
    if (Client.Status = '') and TryNextHost then Exit;
    Failed := True;
  end
  else if NowMs - StartMs > 8000 then
  begin
    Status := 'the listserver did not answer';
    Client.Disconnect;
    if (Client.Status = '') and TryNextHost then Exit;
    Failed := True;
  end;
end;

destructor TListFetch304.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter304.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
