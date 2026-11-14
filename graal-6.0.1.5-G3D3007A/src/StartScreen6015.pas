{ StartScreen6015: what 6.0.1.5 plugs into the shared start screen
  (common/GStartScreen.pas): its list step and its character.

  The list comes from a Seihai listserver (ListServer6015), since the
  rebuild cannot show the Login server's scripted list. The name of the
  server picked there becomes the client's server name, as if the Login
  server had already warped it there, so the player is drawn from the
  start.

  The start screen is this project's own (common/GStartScreen.pas); the
  original start window and its pictures are never drawn. }
unit StartScreen6015;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, ListServer6015, Adventure;

type
  TListFetch6015 = class(TListFetch)
  public
    Client: TListServerClient;
    StartMs: Int64;
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter6015 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, Classes, GTypes;

procedure TListFetch6015.Start(const Host: string; Port: Integer;
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
    Failed := True;
    Exit;
  end;
  Client.SendRequest(Account, Password);
end;

procedure TListFetch6015.Poll;
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
    Failed := True;
  end
  else if NowMs - StartMs > 8000 then
  begin
    Status := 'the listserver did not answer';
    Failed := True;
    Client.Disconnect;
  end;
end;

destructor TListFetch6015.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter6015.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
