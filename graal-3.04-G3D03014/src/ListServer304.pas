unit ListServer304;

{ The 3.04 listserver step (graal_analysis protocol/v3x-clients.md,
  "Listserver", and version-profiles/lab-304-linux-2026-10-30.md).

  The hosts come from license/license.graal in the game folder, a short
  CRLF text file: line 0 the host, line 1 the port, lines 5 and 6 the
  fallback hosts, tried in that order. The real client checks the file's
  RSA signature (license/sig.license); the rebuild does not. The rebuild
  always asks listserver.graal.in on 14922 first and tries the licence
  file's hosts after it (the front end, Graal304.dpr).
  The client sends id 7 V2ENCRYPTKEYCL = GCHAR key + 'G3D30123' + 'newmain'
  and id 1 SERVERLIST (account, password) together in one plain zlib frame
  (the lab saw no flush between them); the replies are gen 5, keyed with
  that key. The reply ids are 0 (the list), 2 (status), 4 (error, the
  connection closes); 3 and 5 are read as 2.22 reads them.

  The id 0 layout is the 2.05 one, read by GStartScreen.ParseServerList. }

interface

uses
  SysUtils, Classes, GTypes, Protocol304, GraalClient, GSecLogin, GStartScreen;

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
  TListHosts = record
    Hosts: array of string;
    Port: Integer;
  end;

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

{ license.graal as text: line 0 host, line 1 port, lines 5 and 6
  fallbacks. Empty Hosts when the text has no host. }
function ParseLicense(const Text: string): TListHosts;
function LoadListHosts(const Path: string): TListHosts;

implementation

function ParseLicense(const Text: string): TListHosts;
var
  L: TStringList;
  procedure AddHost(const H: string);
  var
    T: string;
  begin
    T := Trim(H);
    if T = '' then Exit;
    SetLength(Result.Hosts, Length(Result.Hosts) + 1);
    Result.Hosts[High(Result.Hosts)] := T;
  end;
begin
  SetLength(Result.Hosts, 0);
  Result.Port := DefaultListPort;
  L := TStringList.Create;
  try
    L.Text := Text;
    if L.Count > 0 then AddHost(L[0]);
    if L.Count > 1 then Result.Port := StrToIntDef(Trim(L[1]), DefaultListPort);
    if (Result.Port <= 0) or (Result.Port > 65535) then
      Result.Port := DefaultListPort;
    if L.Count > 5 then AddHost(L[5]);
    if L.Count > 6 then AddHost(L[6]);
  finally
    L.Free;
  end;
end;

function LoadListHosts(const Path: string): TListHosts;
var
  F: TFileStream;
  S: string;
begin
  S := '';
  if FileExists(Path) then
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      if F.Size < 65536 then
      begin
        SetLength(S, F.Size);
        if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
      end;
    finally
      F.Free;
    end;
  except
    S := '';
  end;
  Result := ParseLicense(S);
end;

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
