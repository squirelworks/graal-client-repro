{ StartScreen411lx: what 4.11 Linux plugs into the shared start screen
  (common/GStartScreen.pas): where it starts and its character.

  Start asks listserver.graal.in on 14922 for a list (a listserver.txt
  next to the program names another), with the listserver step in
  ListServer411lx. The real 4.11 Linux has no listserver: it logs in to the
  Login server named in license/license.graal (graal_analysis
  protocol/v4x-clients.md). When the install has that file, its Login
  host and fallbacks are added as extra rows after the list; picking one
  logs in there as a game server named Login, which hands the client on
  with 178. They are never the default.

  The start screen is this project's own (common/GStartScreen.pas); the
  original start window and its pictures are never drawn. }
unit StartScreen411lx;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, ListServer411lx, Adventure, Protocol411lx;

type
  TListFetch411lx = class(TListFetch)
  public
    Client: TListServerClient;
    StartMs: Int64;
    { license.graal's Login hosts and port, added as rows after the list }
    LoginHosts: TListHosts;
    procedure AddLoginRows;
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter411lx = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, Classes, GTypes;

{ The licence file's Login hosts, as rows after whatever the list gave.
  Ends the fetch: Done when there is any row, else Failed. }
procedure TListFetch411lx.AddLoginRows;
var
  I, N: Integer;
begin
  N := Length(Servers);
  SetLength(Servers, N + Length(LoginHosts.Hosts));
  for I := 0 to High(LoginHosts.Hosts) do
  begin
    FillChar(Servers[N + I], SizeOf(Servers[N + I]), 0);
    Servers[N + I].Name := LoginServerName;
    Servers[N + I].Description := 'license.graal';
    Servers[N + I].Host := LoginHosts.Hosts[I];
    Servers[N + I].Port := LoginHosts.Port;
  end;
  if Length(Servers) > 0 then Done := True else Failed := True;
end;

procedure TListFetch411lx.Start(const Host: string; Port: Integer;
  const Account, Password: string);
begin
  FreeAndNil(Client);
  SetLength(Servers, 0);
  Done := False;
  Failed := False;
  StartMs := NowMs;
  Client := TListServerClient.Create;
  Status := Format('asking %s:%d for the server list...', [Host, Port]);
  if not Client.Connect(Host, Port) then
  begin
    Status := Format('no listserver at %s:%d (%s)', [Host, Port, Client.LastError]);
    AddLoginRows;
    Exit;
  end;
  Client.SendRequest(Account, Password);
end;

procedure TListFetch411lx.Poll;
begin
  if (Client = nil) or Done or Failed then Exit;
  Client.Poll;
  if Client.Status <> '' then
    Status := StringReplace(Client.Status, #10, ' ', [rfReplaceAll]);
  if Client.Error <> '' then
  begin
    Status := 'listserver: ' + Client.Error;
    AddLoginRows;
    Exit;
  end;
  if Client.GotList then
  begin
    Servers := Client.Servers;
    if Client.Status = '' then
      Status := Format('%d servers', [Length(Servers)]);
    Client.Disconnect;
    AddLoginRows;
    Done := True;
    Exit;
  end;
  if not Client.Connected then
  begin
    Status := 'the listserver closed the link: ' + Client.LastError;
    AddLoginRows;
  end
  else if NowMs - StartMs > 8000 then
  begin
    Status := 'the listserver did not answer';
    Client.Disconnect;
    AddLoginRows;
  end;
end;

destructor TListFetch411lx.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter411lx.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
