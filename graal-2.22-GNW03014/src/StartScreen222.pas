{ StartScreen222: what 2.22 plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step, its fallback hosts, its
  start-window art and its character.

  2.22 asks for the list with id 7 (key, GNW30123, newmain) in a plain zlib
  frame, then id 1 (account, password) in gen 5 (ListServer222). The hosts
  come from arrays2.dat: line 0, then the fallbacks on lines 5 and 6, tried
  in that order until one connects (graal_analysis protocol/listserver.md,
  "2.22 specifics"). 2.22 checks that file against arrays2.sig; this
  rebuild does not.

  The start screen is this project's own (common/GStartScreen.pas); the
  original start window and its pictures are never drawn. }
unit StartScreen222;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, ListServer222, Adventure;

type
  TListFetch222 = class(TListFetch)
  public
    Client: TListServerClient;
    StartMs: Int64;
    Fallbacks: array of string;
    { The arrays2.dat fallbacks, tried when the first host does not connect. }
    procedure SetFallbacks(const H: TListHosts);
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter222 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils, Classes, GTypes;

procedure TListFetch222.SetFallbacks(const H: TListHosts);
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

procedure TListFetch222.Start(const Host: string; Port: Integer;
  const Account, Password: string);
var
  I: Integer;
  Used, Errors: string;
begin
  FreeAndNil(Client);
  SetLength(Servers, 0);
  Done := False;
  Failed := False;
  StartMs := NowMs;
  Client := TListServerClient.Create;
  Used := Host;
  Status := Format('asking %s:%d for the server list...', [Host, Port]);
  if not Client.Connect(Host, Port) then
  begin
    { each host that failed is named with its own reason }
    Errors := Format('%s: %s', [Host, Client.LastError]);
    Used := '';
    for I := 0 to High(Fallbacks) do
      if Client.Connect(Fallbacks[I], Port) then
      begin
        Used := Fallbacks[I];
        Break;
      end
      else
        Errors := Errors + Format('; %s: %s', [Fallbacks[I], Client.LastError]);
    if Used = '' then
    begin
      Status := Format('no listserver on port %d (%s)', [Port, Errors]);
      Failed := True;
      Exit;
    end;
    Status := Format('asking %s:%d for the server list...', [Used, Port]);
  end;
  Client.SendRequest(Account, Password);
end;

procedure TListFetch222.Poll;
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

destructor TListFetch222.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter222.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
