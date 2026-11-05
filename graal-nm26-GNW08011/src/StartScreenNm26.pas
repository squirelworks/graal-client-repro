{ StartScreenNm26: what the NewMain 26 client plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step and its character.

  2.05 asks the listserver for the list over a plain zlib link (no cipher),
  sending id 0 with "newmain" and id 1 with the account and password; the
  reply is id 0 with the list, 2 a status line, 4 an error (graal_analysis
  protocol/listserver.md). }
unit StartScreenNm26;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, ClientNm26, Adventure;

type
  TListFetchNm26 = class(TListFetch)
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
  TCharacterNm26 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, GTypes;

procedure TListFetchNm26.Message(Id: Integer; const Data: string);
begin
  case Id of
    0:
      begin
        Servers := ParseServerList(Data);
        Done := True;
        Status := Format('%d servers', [Length(Servers)]);
      end;
    2:
      begin
        Status := StringReplace(Data, #13, ' ', [rfReplaceAll]);
        { kept line by line for the list's message box (Label11) }
        StatusLines := StringReplace(Data, #13, #10, [rfReplaceAll]);
      end;
    4:
      begin
        Status := 'listserver: ' + Data;
        Failed := True;
      end;
  end;
end;

procedure TListFetchNm26.Start(const Host: string; Port: Integer;
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
    account and password. A stock NewMain sends id 0 alone (to
    www.graalonline.com, port 14921), but the public
    listserver's legacy port (14923) answers only once id 1 has come
    (graal_analysis manual/06-listserver.md, the login-type matrix). }
  Client.SendPacket(0, 'newmain');
  Client.SendPacket(1, GString(Account) + GString(Password));
  Client.Flush;
end;

procedure TListFetchNm26.Poll;
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

destructor TListFetchNm26.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacterNm26.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
