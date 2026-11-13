{ GetPacks2100: the 2.1 updater, rebuilt as a command-line program.

  Graal 2.1.0.0 came from a small setup program, not an installer: it read
  setup.ini from a mirror, fetched the packages (.pack, tar.gz) of the
  components it lists, unpacked them into the install folder and kept the
  installed versions in setup/installed.db (Packs2100 has the formats).
  This program does the same without the original's wizard pages:

    GetPacks2100 --site SITE [--root DIR] [--developer] [--list]

    --site SITE   where setup.ini and the packages are: a folder, or an
                  http:// address (HTTP/1.0 GET, as the original); the
                  package paths in setup.ini ("graal/main_1010.pack") are
                  under it
    --root DIR    the install folder (default: the current folder)
    --developer   also install the components setup.ini marks optional
                  ("@ -Developer": GraalShop, gif2mng, the level generator)
    --list        print the components, their versions and what is
                  installed, and change nothing

  A component is fetched when it is not in installed.db or setup.ini
  names a newer version of it. Log lines use the original's wording where
  it is known ("Installing file ...").

  Exit codes: 0 done (or nothing to do), 1 a download, a package or the
  install folder failed, 64 bad command line.

  Not as the original: no mirror list (mirrors.lst) or mirror pick, no
  proxy or FTP, no desktop or Start menu links, no uninstall of a
  component's old files, and the "[prev]" versions cannot be picked. }
program GetPacks2100;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}
{ Windows: the manifest and version info (src/GetPacks2100.rc). The
  program is not named "setup": Windows treats such a name as an installer
  and asks for administrator rights unless a manifest says otherwise, and a
  Delphi build carries no manifest. }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R GetPacks2100.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  GCompat in '..\..\common\GCompat.pas',
  GSocket in '..\..\common\GSocket.pas',
  Packs2100 in 'Packs2100.pas';

var
  Site, Root: string;
  Developer, ListOnly: Boolean;

procedure Fail(const S: string);
begin
  WriteLn(ErrOutput, S);
  Halt(1);
end;

{ ---- fetching ---- }

function SplitUrl(const Url: string; out Host: string; out Port: Word; out Path: string): Boolean;
var
  S: string;
  P, Q: Integer;
begin
  Result := False;
  if LowerCase(Copy(Url, 1, 7)) <> 'http://' then Exit;
  S := Copy(Url, 8, MaxInt);
  P := Pos('/', S);
  if P = 0 then
  begin
    Host := S;
    Path := '/';
  end
  else
  begin
    Host := Copy(S, 1, P - 1);
    Path := Copy(S, P, MaxInt);
  end;
  Port := 80;
  Q := Pos(':', Host);
  if Q > 0 then
  begin
    Port := StrToIntDef(Copy(Host, Q + 1, MaxInt), 0);
    Host := Copy(Host, 1, Q - 1);
    if Port = 0 then Exit;
  end;
  Result := Host <> '';
end;

function HttpGet(const Url: string; out Body: string; out Err: string): Boolean;
var
  Host, Path, Buf, Head: string;
  Port: Word;
  S: TGSocket;
  P, Code: Integer;
  Start: TDateTime;
begin
  Result := False;
  Body := '';
  if not SplitUrl(Url, Host, Port, Path) then
  begin
    Err := 'not an http:// address: ' + Url;
    Exit;
  end;
  S := TGSocket.Create;
  try
    if not S.Connect(Host, Port) then
    begin
      Err := Format('Can''t connect to %s:%d', [Host, Port]);
      Exit;
    end;
    if not S.Send('GET ' + Path + ' HTTP/1.0'#13#10 +
      'Host: ' + Host + ':' + IntToStr(Port) + #13#10#13#10) then
    begin
      Err := S.LastError;
      Exit;
    end;
    Buf := '';
    Start := Now;
    while S.Poll(Buf) do
    begin
      if Length(Buf) > 128 * 1024 * 1024 then
      begin
        Err := 'download too big';
        Exit;
      end;
      if (Now - Start) * 86400 > 120 then
      begin
        Err := 'download timed out';
        Exit;
      end;
      Sleep(5);
    end;
  finally
    S.Free;
  end;
  P := Pos(#13#10#13#10, Buf);
  if P = 0 then
  begin
    Err := 'no HTTP header';
    Exit;
  end;
  Head := Copy(Buf, 1, P - 1);
  Body := Copy(Buf, P + 4, MaxInt);
  { "HTTP/1.x 200 OK" }
  Code := StrToIntDef(Copy(Head, Pos(' ', Head) + 1, 3), 0);
  if Code <> 200 then
  begin
    Err := Format('%s: HTTP %d', [Url, Code]);
    Body := '';
    Exit;
  end;
  Result := True;
end;

function ReadWholeFile(const Name: string; out Data: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Data := '';
  if not FileExists(Name) then Exit;
  F := TFileStream.Create(Name, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, F.Size);
    if F.Size > 0 then F.ReadBuffer(Data[1], F.Size);
    Result := True;
  finally
    F.Free;
  end;
end;

procedure WriteWholeFile(const Name, Data: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Name, fmCreate);
  try
    if Data <> '' then F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
end;

{ A file of the site: setup.ini, or a package path from it. }
function Fetch(const Rel: string; out Data: string): Boolean;
var
  Err, Url, F: string;
begin
  if LowerCase(Copy(Site, 1, 7)) = 'http://' then
  begin
    Url := Site;
    if Url[Length(Url)] <> '/' then Url := Url + '/';
    Url := Url + Rel;
    Result := HttpGet(Url, Data, Err);
    if not Result then WriteLn(ErrOutput, Err)
    else WriteLn('Downloaded ', Url);
  end
  else
  begin
    F := IncludeTrailingPathDelimiter(Site) + StringReplace(Rel, '/', PathDelim, [rfReplaceAll]);
    Result := ReadWholeFile(F, Data);
    if not Result then WriteLn(ErrOutput, 'Can''t open ', F);
  end;
end;

{ ---- installing ---- }

function InstallPack(const Pack, Data: string): Boolean;
var
  Plain, Dest: string;
  E: TTarEntries;
  I: Integer;
begin
  Result := False;
  if not Gunzip(Data, Plain) then
  begin
    WriteLn(ErrOutput, 'Failed to extract the file ', Pack, ' (not a gzip package)');
    Exit;
  end;
  if not ReadTar(Plain, E) then
  begin
    WriteLn(ErrOutput, 'Failed to extract the file ', Pack, ' (bad tar archive)');
    Exit;
  end;
  for I := 0 to High(E) do
  begin
    if not SafeArchivePath(E[I].Name) then
    begin
      WriteLn(ErrOutput, 'Unable to install file ', E[I].Name, ' (outside the install folder)');
      Exit;
    end;
    Dest := IncludeTrailingPathDelimiter(Root) +
      StringReplace(E[I].Name, '/', PathDelim, [rfReplaceAll]);
    if E[I].IsDir then
    begin
      ForceDirectories(ExcludeTrailingPathDelimiter(Dest));
      Continue;
    end;
    if not ForceDirectories(ExtractFileDir(Dest)) then
    begin
      WriteLn(ErrOutput, 'Failed to make the path for ', Dest);
      Exit;
    end;
    try
      WriteWholeFile(Dest, E[I].Data);
    except
      WriteLn(ErrOutput, 'Failed to open ', Dest, ' for writing');
      Exit;
    end;
    WriteLn('Installing file ', E[I].Name);
  end;
  Result := True;
end;

var
  Ini: TSetupIni;
  IniText, Db, Data, Pack: string;
  Names, Packs: TStringList;
  I, K, Errors: Integer;
  Arg: string;
  Want: Boolean;
begin
  Site := '';
  Root := GetCurrentDir;
  Developer := False;
  ListOnly := False;
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '--site') and (I < ParamCount) then
    begin
      Inc(I);
      Site := ParamStr(I);
    end
    else if (Arg = '--root') and (I < ParamCount) then
    begin
      Inc(I);
      Root := ParamStr(I);
    end
    else if Arg = '--developer' then Developer := True
    else if Arg = '--list' then ListOnly := True
    else
    begin
      WriteLn(ErrOutput, 'usage: GetPacks2100 --site FOLDER|http://HOST[:PORT]/PATH [--root DIR] [--developer] [--list]');
      Halt(64);
    end;
    Inc(I);
  end;
  if Site = '' then
  begin
    WriteLn(ErrOutput, 'GetPacks2100: --site is needed (the folder or address holding setup.ini)');
    Halt(64);
  end;
  WriteLn('Starting Graal install, version 2.1.0.0 (graal-delphi rebuild)');
  if not Fetch('setup.ini', IniText) then Fail('no setup.ini at ' + Site);
  Ini := ParseSetupIni(IniText);
  if Length(Ini.Components) = 0 then Fail('setup.ini lists no components');
  WriteLn('setup.ini: version ', Ini.SetupVersion, ', ', Length(Ini.Components), ' components');
  Names := TStringList.Create;
  Packs := TStringList.Create;
  try
    if ReadWholeFile(IncludeTrailingPathDelimiter(Root) + 'setup' + PathDelim + 'installed.db', Db) then
      if not ParseInstalledDb(Db, Names, Packs) then
        WriteLn(ErrOutput, 'setup/installed.db: not an INSTALLED.DB 2 file, starting over');
    Errors := 0;
    for I := 0 to High(Ini.Components) do
      with Ini.Components[I] do
      begin
        Pack := PackBaseName(Install);
        K := Names.IndexOf(Name);
        Want := (not Optional or Developer) and (Install <> '') and
          ((K < 0) or (Packs[K] <> Pack));
        if ListOnly then
        begin
          if K >= 0 then Arg := Packs[K] else Arg := '-';
          if Optional then Arg := Arg + ' (optional)';
          WriteLn(Format('%-12s %-10s %-24s installed: %s', [Name, Version, Install, Arg]));
          Continue;
        end;
        if not Want then Continue;
        if not Fetch(Install, Data) then
        begin
          Inc(Errors);
          Continue;
        end;
        if not ForceDirectories(Root) or not InstallPack(Pack, Data) then
        begin
          Inc(Errors);
          Continue;
        end;
        if K < 0 then
        begin
          Names.Add(Name);
          Packs.Add(Pack);
        end
        else
          Packs[K] := Pack;
        WriteLn(Format('%s %s installed', [Name, Version]));
      end;
    if not ListOnly then
    begin
      ForceDirectories(IncludeTrailingPathDelimiter(Root) + 'setup');
      WriteWholeFile(IncludeTrailingPathDelimiter(Root) + 'setup' + PathDelim + 'installed.db',
        InstalledDbText(Names, Packs));
      WriteLn('Ending graal install');
    end;
  finally
    Names.Free;
    Packs.Free;
  end;
  if Errors > 0 then Halt(1);
end.
