{ StartScreen222: what 2.22 plugs into the shared start screen
  (common/GStartScreen.pas): its listserver step, its fallback hosts, its
  start-window art and its character.

  2.22 asks for the list with id 7 (key, GNW30123, newmain) in a plain zlib
  frame, then id 1 (account, password) in gen 5 (ListServer222). The hosts
  come from arrays2.dat: line 0, then the fallbacks on lines 5 and 6, tried
  in that order until one connects (graal_analysis protocol/listserver.md,
  "2.22 specifics"). 2.22 checks that file against arrays2.sig; this
  rebuild does not.

  The start window's pictures were built into Graal_222.exe (screenimg1.jpg,
  screenimg2.jpg); they are not in this repository. Dropped next to the
  program (or in builtin/ there, as the assets zip has them) they replace
  the drawn backdrop. }
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

{ The 2.22 start window (TConnectFrame, caption "Graal 2001"): 577 x 416
  with SCREENIMG1 behind it. From its form: the "Welcome to Graal!" label
  at (80, 208, 281 x 25), Nick Name at (72, 246) with its field at (200,
  241, 177 x 24), Language at (72, 274) with its box at (200, 269, 177 x
  24), and Account / Password at (76, 332) / (76, 364) with fields at (204,
  329) / (204, 361), 173 x 24. FormShow places four TPaintButtons with lime
  MS Sans Serif captions: Start Online at (423, 345), Training at (423,
  215), Options at (423, 245), all 105 x 26 with the button1 face, and
  "Get an account" at (408, 275), 145 x 26 with the button2 face (not
  built: a click says so). }
procedure Classic222(var L: TClassicLayout);

const
  Backgrounds222 = 'screenimg1.jpg;builtin/screenimg1.jpg;screenimg2.jpg;' +
    'builtin/screenimg2.jpg;images/screenimg1.jpg';

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
  Used: string;
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

procedure Classic222(var L: TClassicLayout);
begin
  L.Used := True;
  L.FormW := 577;
  L.FormH := 416;
  L.ButtonImages := 'button1.bmp;builtin/button1.bmp;images/button1.bmp';
  L.Training := StartRect(423, 215, 105, 26);
  L.Options := StartRect(423, 245, 105, 26);
  L.Start := StartRect(423, 345, 105, 26);
  L.TrainingText := 'Training';
  L.OptionsText := 'Options';
  L.StartText := 'Start Online';
  L.Welcome := StartRect(80, 208, 281, 25);
  L.WelcomeText := 'Welcome to Graal!';
  L.NickLabel := StartRect(72, 246, 81, 16);
  L.NickField := StartRect(200, 241, 177, 24);
  L.LanguageLabel := StartRect(72, 274, 74, 16);
  L.LanguageField := StartRect(200, 269, 177, 24);
  { FormShow's captions are lime ($00FF00); the welcome label is centred }
  L.CaptionColor := $00FF00;
  L.WelcomeCentered := True;
  L.Extra := StartRect(408, 275, 145, 26);
  L.ExtraText := 'Get an account';
  L.ExtraImages := 'button2.bmp;builtin/button2.bmp;images/button2.bmp';
  L.AccountLabel := StartRect(76, 332, 60, 16);
  L.PasswordLabel := StartRect(76, 364, 73, 16);
  L.AccountField := StartRect(204, 329, 173, 24);
  L.PasswordField := StartRect(204, 361, 173, 24);
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
