unit ListServer40211;

{ Where 4.02.11 starts, and the listserver step the rebuild asks first
  (graal_analysis protocol/v4x-clients.md, "Login server and
  license.graal").

  4.x has no listserver protocol. license/license.graal in the game folder
  is a short CRLF text file: line 0 the host, line 1 the port (14900 in the
  shipped file), lines 5 and 6 the fallback hosts. The client logs in
  there as an ordinary game server it names Login; the list is scripted
  GUI inside that session, and the server hands the client on with 178.
  The real client checks the file's RSA signature (license/sig.license);
  the rebuild does not.

  The rebuild's Start asks listserver.graal.in on 14922 first, with the
  listserver step of the 3.x clients, and offers the licence file's Login
  hosts only as extra rows after that list: id 7 V2ENCRYPTKEYCL = GCHAR key + token + 'newmain' and id 1
  SERVERLIST (account, password) together in one plain zlib frame; the
  replies are gen 5, keyed with that key. The token sent is 4.02.11's own.
  The reply ids are 0 (the list), 2 (status), 4 (error, the connection
  closes); 3 and 5 are read as 2.22 reads them. The id 0 layout is the
  2.05 one, read by GStartScreen.ParseServerList. }

interface

uses
  SysUtils, Classes, GTypes, Protocol40211, GraalClient, GStartScreen;

const
  ListToken = ClientVersionToken;
  ListVersion = 'newmain';
  LS_V2ENCRYPTKEYCL = 7;
  LS_SERVERLIST = 1;
  LSO_SVRLIST = 0;
  LSO_STATUS = 2;
  LSO_SITEURL = 3;
  LSO_ERROR = 4;
  LSO_UPGURL = 5;
  { the default listserver, and the port when the licence file names none }
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
  public
    constructor Create;
    { Queue and send id 7 then id 1. Call after Connect (or StartOffline). }
    procedure SendRequest(const Account, Password: string);
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
end;

procedure TListServerClient.SendRequest(const Account, Password: string);
begin
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
