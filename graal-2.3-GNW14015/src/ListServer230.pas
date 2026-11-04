unit ListServer230;

{ The 2.22 listserver step, which 2.3 shares (graal_analysis protocol/listserver.md, "2.22
  specifics", and protocol/login-frames-by-version-2026-10-25.md, shape C).

  The hosts come from arrays2.dat in the game folder: line 0 the host,
  line 1 the port, lines 5 and 6 the fallback hosts, tried in that order.
  The client sends id 7 V2ENCRYPTKEYCL = GCHAR key + 'GNW30123' + 'newmain'
  in one plain zlib frame, then id 1 SERVERLIST (account, password) in a
  gen-5 frame keyed with that key; the replies are gen-5 as well. The
  reply ids are 0 (the list), 2 (status), 3 (site url), 4 (error, the
  connection closes) and 5 (upgrade url).

  The id 0 layout is the 2.05 one, read by GStartScreen.ParseServerList. }

interface

uses
  SysUtils, Classes, GTypes, Protocol230, GraalClient, GStartScreen;

const
  ListToken = 'GNW30123';
  ListVersion = 'newmain';
  LS_V2ENCRYPTKEYCL = 7;
  LS_SERVERLIST = 1;
  LSO_SVRLIST = 0;
  LSO_STATUS = 2;
  LSO_SITEURL = 3;
  LSO_ERROR = 4;
  LSO_UPGURL = 5;
  { With no arrays2.dat and no listserver.txt: listserver.graal.in on its
    supported port, 14922 (14923 is its legacy port). The original 2.22
    pointed at the GraalOnline listserver, which is gone. }
  DefaultListHost = 'listserver.graal.in';
  DefaultListPort = 14922;

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

{ arrays2.dat as text: line 0 host, line 1 port, lines 5 and 6 fallbacks.
  Empty Hosts when the text has no host. }
function ParseArrays2(const Text: string): TListHosts;
function LoadListHosts(const Path: string): TListHosts;

implementation

function ParseArrays2(const Text: string): TListHosts;
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
  Result := ParseArrays2(S);
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
  Flush;
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
