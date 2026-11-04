{ StartScreen205: what 2.05 plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step and its character.

  2.05 asks the listserver for the list over a plain zlib link (no cipher),
  sending id 0 with "newmain"; the reply is id 0 with the list, 2 a status
  line, 4 an error (graal_analysis protocol/listserver.md). }
unit StartScreen205;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, Adventure;

type
  TListFetch205 = class(TListFetch)
  public
    Client: TGraalClient;
    StartMs: Int64;
    procedure Message(Id: Integer; const Data: string);
    procedure Start(const Host: string; Port: Integer); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter205 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

const
  Backgrounds205 = 'screenimg1.jpg;embedded/images/screenimg1.jpg;images/screenimg1.jpg';

implementation

uses
  SysUtils, GTypes;

procedure TListFetch205.Message(Id: Integer; const Data: string);
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

procedure TListFetch205.Start(const Host: string; Port: Integer);
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
  { 2.05 sends id 0 with the list name and waits; no account here }
  Client.SendPacket(0, 'newmain');
  Client.Flush;
end;

procedure TListFetch205.Poll;
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

destructor TListFetch205.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter205.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
