unit ListServer6034;

{ The server list for the rebuild's start screen.

  6.0.3.4 itself has no listserver step: it logs into a game server it
  calls Login (three compiled-in hosts on port 14900 on the original), which
  shows the server list as scripted GUI and moves the client on with a
  server warp (178) (graal_analysis protocol/v6x-clients.md, "Login server").
  The rebuild cannot show that scripted list, so its start screen asks a
  Seihai listserver for the list instead, with the 3.x list request: id 7
  V2ENCRYPTKEYCL = GCHAR key + 'G3D30123' + 'newmain' and id 1 SERVERLIST
  (account, password) in one plain zlib frame; the replies are gen 5,
  keyed with that key. The reply ids are 0 (the list), 2 (status), 4
  (error, the connection closes); 3 and 5 are read as 2.22 reads them.
  listserver.txt next to the program names the listserver; with none it is
  listserver.graal.in on 14922.

  The id 0 layout is the 2.05 one, read by GStartScreen.ParseServerList. }

interface

uses
  SysUtils, Classes, GTypes, Protocol6034, GraalClient, GSecLogin, GStartScreen;

const
  ListToken = ListVersionToken;
  ListVersion = 'newmain';
  LS_V2ENCRYPTKEYCL = 7;
  LS_SERVERLIST = 1;
  LSO_SVRLIST = 0;
  LSO_STATUS = 2;
  LSO_SITEURL = 3;
  LSO_ERROR = 4;
  LSO_UPGURL = 5;
  DefaultListPort = 14922;
  DefaultListHost = 'listserver.graal.in';

type
  TListServerClient = class(TAdventureClient)
  private
    FServers: TListServers;
    FStatus, FSiteUrl, FUpgradeUrl, FError: string;
    FGotList: Boolean;
    procedure HandleMessage(Id: Integer; const Data: string);
    procedure ReadList(const Data: string);
  protected
    FAccount, FPassword: string;
    procedure SendAfterLogin; override;
  public
    constructor Create;
    { Queue and send id 7 then id 1. Call after Connect (or StartOffline). }
    procedure SendRequest(const Account, Password: string);
    { Call after Poll: the secure login's wait, and auto's fallback to the
      original request (a stop shows as Error). }
    procedure CheckSecureList;
    property Servers: TListServers read FServers;
    property Status: string read FStatus;
    property SiteUrl: string read FSiteUrl;
    property UpgradeUrl: string read FUpgradeUrl;
    property Error: string read FError;
    property GotList: Boolean read FGotList;
  end;

implementation

{ TListServerClient }

constructor TListServerClient.Create;
begin
  inherited Create;
  OnMessage := HandleMessage;
  Sec.Mode := ConfiguredSecMode;
  Sec.ServerKey := ConfiguredServerKey;
end;

procedure TListServerClient.SendAfterLogin;
begin
  { id 1 went in C2; the list server answers in gen 5 }
end;

procedure TListServerClient.CheckSecureList;
var
  H: string;
  P: Integer;
begin
  CheckSecure;
  if not (Sec.State in [ssRefused, ssNoAnswer, ssFailed]) then Exit;
  if (Sec.State <> ssFailed) and MayFallBack(Sec.Mode, Sec.Server) then
  begin
    { auto: this list server does not speak SEI00001; ask the original way }
    RememberRefused(Sec.Server);
    H := Sec.Server;
    P := LastDelimiter(':', H);
    Disconnect;
    Sec.ForceClassic := True;
    if Connect(Copy(H, 1, P - 1), StrToIntDef(Copy(H, P + 1, MaxInt), 0)) then
    begin
      SendRequest(FAccount, FPassword);
      Exit;
    end;
  end;
  FError := 'secure login: ' + Sec.Why;
  Sec.Finish;
end;

procedure TListServerClient.SendRequest(const Account, Password: string);
begin
  FAccount := Account;
  FPassword := Password;
  { Seihai secure login (not in the original): id 7 carries SEI00001 and
    the list token, and id 1's payload goes sealed in C2 }
  if Sec.Want then
  begin
    StartSecure(GChar(LS_V2ENCRYPTKEYCL) + GChar(Key), ListToken, ListVersion,
      GString(Account) + GString(Password));
    Exit;
  end;
  SendPacket(LS_V2ENCRYPTKEYCL, GChar(Key) + ListToken + ListVersion);
  SendPacket(LS_SERVERLIST, GString(Account) + GString(Password));
  Flush;
end;

procedure TListServerClient.ReadList(const Data: string);
begin
  FServers := ParseServerList(Data);
  FGotList := True;
end;

procedure TListServerClient.HandleMessage(Id: Integer; const Data: string);
begin
  case Id of
    LSO_SVRLIST: ReadList(Data);
    LSO_STATUS: FStatus := StringReplace(Data, #13, #10, [rfReplaceAll]);
    LSO_SITEURL: FSiteUrl := Data;
    LSO_UPGURL: FUpgradeUrl := Data;
    LSO_ERROR:
      begin
        FError := Data;
        Disconnect;
      end;
  end;
end;

end.
