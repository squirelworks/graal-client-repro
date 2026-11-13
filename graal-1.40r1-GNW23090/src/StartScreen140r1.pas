{ StartScreen140r1: what 1.40 rev 1 plugs into its start window
  (StartWindow140r1.pas): its listserver step and its character.

  1.40 (as 1.41) opens a plain zlib link to the listserver (no cipher) and waits:
  it sends nothing, and the server sends the list (id 0), a status line
  (2) or an error (4). The public listserver answers its legacy port only
  to a classic login, so the rebuild sends one: id 0 with "newmain" and id
  1 with the account and password, as the 2.05 rebuild does. }
unit StartScreen140r1;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, StartWindow140r1, GraalClient, Adventure, GCompat;

type
  TListFetch140r1 = class(TListFetch)
  public
    Client: TGraalClient;
    StartMs: Int64;
    procedure Message(Id: Integer; const Data: string);
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter140r1 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, GTypes;

procedure TListFetch140r1.Message(Id: Integer; const Data: string);
begin
  case Id of
    0:
      begin
        Servers := ParseServerList(Data);
        Done := True;
        Status := Format('%d servers', [Length(Servers)]);
      end;
    2: Status := StringReplace(Data, #13, ' ', [rfReplaceAll]);
    4:
      begin
        Status := 'listserver: ' + Data;
        Failed := True;
      end;
  end;
end;

procedure TListFetch140r1.Start(const Host: string; Port: Integer;
  const Account, Password: string);
begin
  FreeAndNil(Client);
  SetLength(Servers, 0);
  Done := False;
  Failed := False;
  StartMs := NowMs;
  Client := TGraalClient.Create;
  Client.OnMessage := Message;
  Status := Format('asking %s:%d for the server list...', [Host, Port]);
  if not Client.Connect(Host, Port) then
  begin
    Status := Format('no listserver at %s:%d (%s)', [Host, Port, Client.LastError]);
    Failed := True;
    Exit;
  end;
  { One plain zlib frame: id 0 with the list name, then id 1 with the
    account and password. A stock 1.40 or 1.41 sends nothing, but the public
    listserver's legacy port (14923) answers only a classic login
    (graal_analysis manual/06-listserver.md, the login-type matrix). }
  Client.SendPacket(0, 'newmain');
  Client.SendPacket(1, GString(Account) + GString(Password));
  Client.Flush;
end;

procedure TListFetch140r1.Poll;
begin
  if (Client = nil) or Done or Failed then Exit;
  Client.Poll;
  if Done then
  begin
    Client.Disconnect;
    Exit;
  end;
  if not Client.Connected then
  begin
    if not Failed then Status := 'the listserver closed the link: ' + Client.LastError;
    Failed := True;
  end
  else if NowMs - StartMs > 8000 then
  begin
    Status := 'the listserver did not answer';
    Failed := True;
    Client.Disconnect;
  end;
end;

destructor TListFetch140r1.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter140r1.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
