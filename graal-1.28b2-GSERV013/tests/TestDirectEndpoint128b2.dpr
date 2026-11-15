program TestDirectEndpoint128b2;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses
  SysUtils, Classes,
  Protocol128b2 in '../src/Protocol128b2.pas',
  StartScreen128b2 in '../src/StartScreen128b2.pas';

procedure Check(OK: Boolean; const What: string);
begin
  if not OK then raise Exception.Create(What);
  WriteLn('ok ', What);
end;

procedure TestDestination;
var
  Dir, Host: string;
  Port: Integer;
  Lines: TStringList;
  Fetch: TListFetch128b2;

  procedure Destination(const ExpectedHost: string; ExpectedPort: Integer;
    const What: string);
  begin
    { The production selector used by both GUI front ends, followed by
      the production single-row adapter. No listserver request is made. }
    ReadServerAddr(Dir, DefaultServerHost, DefaultServerPort, Host, Port);
    Check((Host = ExpectedHost) and (Port = ExpectedPort), What);
    Fetch.Start(Host, Port, 'generated-account', 'generated-password');
    Fetch.Poll;
    Check(Fetch.Done and not Fetch.Failed and (Length(Fetch.Servers) = 1),
      What + ': one immediate direct destination');
    Check((Fetch.Servers[0].Host = ExpectedHost) and
      (Fetch.Servers[0].Port = ExpectedPort),
      What + ': connect row retains exact host and port');
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    'direct128b2-' + IntToStr(Random(1000000000)) + PathDelim;
  ForceDirectories(Dir);
  Lines := TStringList.Create;
  Fetch := TListFetch128b2.Create;
  try
    Destination('127.0.0.1', 14802, 'unconfigured rebuild game endpoint');
    Lines.Add('localhost');
    Lines.Add('14803');
    Lines.SaveToFile(Dir + 'listserver.txt');
    Destination('localhost', 14803, 'legacy filename overrides default directly');
    Lines.Clear;
    Lines.Add('serveraddr="127.0.0.1:14804"');
    Lines.SaveToFile(Dir + 'graalconfig.txt');
    Destination('127.0.0.1', 14804, 'quoted inline port overrides legacy file');
    Lines.Clear;
    Lines.Add('serveraddr="127.0.0.1"');
    Lines.Add('serverport=14805');
    Lines.SaveToFile(Dir + 'graalconfig.txt');
    Destination('127.0.0.1', 14805, 'separate configured port overrides legacy file');
    Lines.Clear;
    Lines.Add('serveraddr="127.0.0.1"');
    Lines.SaveToFile(Dir + 'graalconfig.txt');
    Destination('127.0.0.1', 14803, 'host-only override retains configured fallback port');
    DeleteFile(Dir + 'listserver.txt');
    Destination('127.0.0.1', 14802, 'host-only override retains direct default port');
  finally
    Fetch.Free;
    Lines.Free;
    DeleteFile(Dir + 'graalconfig.txt');
    DeleteFile(Dir + 'listserver.txt');
    RemoveDir(Dir);
  end;
end;

begin
  Randomize;
  TestDestination;
end.

