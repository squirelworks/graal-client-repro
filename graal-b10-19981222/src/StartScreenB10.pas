{ StartScreenB10: what 10th Graal (V1.0) plugs into the shared start screen
  (common/GStartScreen.pas).

  The 1998 builds have no server list. Their connect dialog holds one
  relay host and port, pre-filled (graal_analysis protocol/relay-1998.md,
  "dialog_server" in version-profiles/v1998-v11.toml). The rebuild shows
  that one relay as the only row of the list page, from listserver.txt
  next to the program when there is one, else the build's dialog default.
  There is no account or password in gen 1: the fields are not sent. }
unit StartScreenB10;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, Adventure;

type
  TConnectDialogB10 = class(TListFetch)
  public
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacterB10 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

implementation

uses
  SysUtils;

procedure TConnectDialogB10.Start(const Host: string; Port: Integer;
  const Account, Password: string);
begin
  SetLength(Servers, 1);
  Servers[0].Name := 'Relay ' + Host;
  Servers[0].Language := 'English';
  Servers[0].Description := 'This build has no server list: it joins the relay ' +
    'server named in its connect dialog. Account and password are not used.';
  Servers[0].Url := '';
  Servers[0].Version := '1998 relay';
  Servers[0].Players := '';
  Servers[0].Host := Host;
  Servers[0].Port := Port;
  Status := Format('connect dialog: %s:%d', [Host, Port]);
  Done := True;
  Failed := False;
end;

procedure TConnectDialogB10.Poll;
begin
end;

procedure TCharacterB10.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
