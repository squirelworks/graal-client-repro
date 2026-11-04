{ StartScreen420: what 4.20r8 plugs into the shared start screen
  (common/GStartScreen.pas): where it starts and its character.

  With a licence file (license/license.graal) the list page offers the
  Login server it names, and each fallback host; Connect logs in there as
  a game server named Login, which hands the client on with 178
  (graal_analysis protocol/v4x-clients.md). The real client shows the
  list as scripted GUI inside that session; the rebuild shows the Login
  session's backdrop level and waits for 178. With no licence file the
  rebuild asks a listserver for a list instead (ListServer420).

  The start screen is this project's own (common/GStartScreen.pas); the
  original start window and its pictures are never drawn. }
unit StartScreen420;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, ListServer420, Adventure, Protocol420;

type
  TListFetch420 = class(TListFetch)
  public
    Client: TListServerClient;
    StartMs: Int64;
    Fallbacks: array of string;
    { True: offer the licence file's Login hosts instead of asking a
      listserver. }
    LoginMode: Boolean;
    { The license.graal fallbacks, tried when the first host does not connect. }
    procedure SetFallbacks(const H: TListHosts);
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter420 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, Classes, GTypes;

procedure TListFetch420.SetFallbacks(const H: TListHosts);
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

procedure TListFetch420.Start(const Host: string; Port: Integer;
  const Account, Password: string);
var
  I: Integer;
  Used: string;
begin
  FreeAndNil(Client);
  SetLength(Servers, 0);
  Done := False;
  Failed := False;
  StartMs := NowMs;
  if LoginMode then
  begin
    SetLength(Servers, 1 + Length(Fallbacks));
    for I := 0 to High(Servers) do
    begin
      Servers[I].Name := LoginServerName;
      if I = 0 then Servers[I].Host := Host
      else Servers[I].Host := Fallbacks[I - 1];
      Servers[I].Port := Port;
      Servers[I].Players := '';
    end;
    Status := 'the Login server from license.graal';
    Done := True;
    Exit;
  end;
  Client := TListServerClient.Create;
  Used := Host;
  Status := Format('asking %s:%d for the server list...', [Host, Port]);
  if not Client.Connect(Host, Port) then
  begin
    Used := '';
    for I := 0 to High(Fallbacks) do
      if Client.Connect(Fallbacks[I], Port) then
      begin
        Used := Fallbacks[I];
        Break;
      end;
    if Used = '' then
    begin
      Status := Format('no listserver at %s:%d (%s)', [Host, Port, Client.LastError]);
      Failed := True;
      Exit;
    end;
    Status := Format('asking %s:%d for the server list...', [Used, Port]);
  end;
  Client.SendRequest(Account, Password);
end;

procedure TListFetch420.Poll;
begin
  if (Client = nil) or Done or Failed then Exit;
  Client.Poll;
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
    Failed := True;
  end
  else if NowMs - StartMs > 8000 then
  begin
    Status := 'the listserver did not answer';
    Failed := True;
    Client.Disconnect;
  end;
end;

destructor TListFetch420.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter420.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
