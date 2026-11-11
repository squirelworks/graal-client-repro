{ StartScreen217: what 2.17.1 plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step, where it finds the
  listserver, and its character.

  2.17 asks for the list over a plain zlib link (no cipher, no version
  token) in one frame holding two messages: id 0 "newmain", then id 1 with
  the account and password as GSTRINGs. The reply is id 0 with the list
  (the 2.05 layout), then id 2 status text, 3 the site URL, 5 the donation
  URL; 4 is an error. The listserver host and port come from arrays2.dat
  (line 0 host, line 1 port) in the game folder (graal_analysis
  protocol/listserver.md, "2.17 flow"). 2.17 checks that file against
  arrays2.sig; this rebuild does not. }
unit StartScreen217;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, GraalClient, Adventure;

type
  TListFetch217 = class(TListFetch)
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
  TCharacter217 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

{ The listserver in Dir's arrays2.dat, when there is one: Host and Port
  are left as they are otherwise. }
procedure ReadArrays2(const Dir: string; var Host: string; var Port: Integer);

implementation

uses
  SysUtils, Classes, GTypes, GAssetDirs;

procedure TListFetch217.Message(Id: Integer; const Data: string);
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

procedure TListFetch217.Start(const Host: string; Port: Integer;
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
  { 2.17: id 0 and id 1 go out together in one frame }
  Client.SendPacket(0, 'newmain');
  Client.SendPacket(1, GString(Account) + GString(Password));
  Client.Flush;
end;

procedure TListFetch217.Poll;
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

destructor TListFetch217.Destroy;
begin
  Client.Free;
  inherited Destroy;
end;

procedure TCharacter217.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

procedure ReadArrays2(const Dir: string; var Host: string; var Port: Integer);
var
  L: TStringList;
  P: string;
begin
  P := AssetPath('arrays2.dat');
  if P = '' then P := InstallPath(Dir, 'arrays2.dat');
  if not FileExists(P) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(P);
    if (L.Count > 0) and (Trim(L[0]) <> '') then Host := Trim(L[0]);
    if L.Count > 1 then Port := StrToIntDef(Trim(L[1]), Port);
  finally
    L.Free;
  end;
end;

end.
