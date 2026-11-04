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
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
    destructor Destroy; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter205 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

{ The 2.05 start window (TConnectFrame): a 476 x 330 dialog with
  SCREENIMG1 behind it, the welcome label, the language and nick name
  fields from its form, and three TPaintButtons of 105 x 26 with the
  BUTTON1 face that FormShow places: Training at (336, 240), Start Online
  at (336, 280), Options at (200, 280) (graal_analysis: TConnectFrame.dfm,
  TConnectFrame.FormShow). Used when screenimg1.jpg and button1.bmp lie
  next to the program, as in the assets zip. }
procedure Classic205(var L: TClassicLayout);

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

procedure TListFetch205.Start(const Host: string; Port: Integer;
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

procedure Classic205(var L: TClassicLayout);
begin
  L.Used := True;
  L.FormW := 476;
  L.FormH := 330;
  L.ButtonImages := 'button1.bmp;embedded/images/button1.bmp;images/button1.bmp';
  L.Training := StartRect(336, 240, 105, 26);
  L.Start := StartRect(336, 280, 105, 26);
  L.Options := StartRect(200, 280, 105, 26);
  L.TrainingText := 'Training';
  L.StartText := 'Start Online';
  L.OptionsText := 'Options';
  L.Welcome := StartRect(24, 136, 153, 153);
  L.WelcomeText := 'Welcome to Graal! Select your character, then press ''Training'' ' +
    'for some offline training levels, and ''Start'' for the online mode.';
  L.LanguageLabel := StartRect(208, 148, 64, 16);
  L.NickLabel := StartRect(208, 178, 70, 16);
  L.LanguageField := StartRect(312, 145, 145, 24);
  L.NickField := StartRect(312, 173, 145, 24);
end;

end.
