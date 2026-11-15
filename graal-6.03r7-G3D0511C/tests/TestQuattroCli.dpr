program TestQuattroCli;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

uses SysUtils, Classes{$IFDEF LINUX}, Process, BaseUnix, Sockets{$ENDIF};

{$IFDEF LINUX}
procedure Check(OK: Boolean; const What: string);
begin
  if not OK then raise Exception.Create(What);
  WriteLn('ok ', What);
end;

procedure TestDispatch;
var
  Dir, Player, Client, Receipt, HeapLog: string;
  Text, Seen: TStringList;
  Input, Output: TFileStream;
  RunNumber: Integer;
  ReservedSocket: LongInt;
  Address: TInetSockAddr;
  AddressSize: TSockLen;
  ClosedTarget: string;

  procedure Run(const Args: array of string; Handoff: Boolean;
    const Secure: string = 'off'; const Display: Boolean = True;
    const PascalGame: Boolean = False);
  var
    P: TProcess;
    I: Integer;
    E: string;
  begin
    DeleteFile(Receipt);
    Inc(RunNumber);
    HeapLog := Dir + 'child-' + IntToStr(RunNumber) + '.heap';
    P := TProcess.Create(nil);
    try
      P.Executable := Client;
      for I := 0 to High(Args) do P.Parameters.Add(Args[I]);
      for I := 1 to GetEnvironmentVariableCount do
      begin
        E := GetEnvironmentString(I);
        if (Pos('DISPLAY=', E) <> 1) and (Pos('GRAAL_PASCAL_GAME=', E) <> 1) and
          (Pos('GRAAL_SECURE_LOGIN=', E) <> 1) and (Pos('HEAPTRC=', E) <> 1) and
          (Pos('GRAAL_PW=', E) <> 1) and (Pos('GRAAL_QUATTRO_PW=', E) <> 1) then
          P.Environment.Add(E);
      end;
      P.Environment.Add('QUATTRO_CLI_RECEIPT=' + Receipt);
      P.Environment.Add('GRAAL_PW=generated-cli-password');
      P.Environment.Add('GRAAL_QUATTRO_PW=stale-parent-password');
      P.Environment.Add('GRAAL_SECURE_LOGIN=' + Secure);
      P.Environment.Add('HEAPTRC=log=' + HeapLog);
      if Display then P.Environment.Add('DISPLAY=:123');
      if PascalGame then P.Environment.Add('GRAAL_PASCAL_GAME=1');
      P.Options := [poWaitOnExit];
      P.Execute;
      Check(FileExists(Receipt) = Handoff, 'actual client routing');
      if Handoff then Check(P.ExitStatus = 23, 'child exit status returned')
      else Check(P.ExitStatus <> 23, 'Pascal fallback did not launch child');
    finally
      P.Free;
      DeleteFile(HeapLog);
    end;
  end;

begin
  RunNumber := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'quattro-cli-' + IntToStr(GetProcessID);
  ForceDirectories(Dir);
  Dir := IncludeTrailingPathDelimiter(Dir);
  Client := Dir + 'Graal603';
  Player := Dir + 'quattro-play';
  Receipt := Dir + 'receipt';
  Text := TStringList.Create;
  Seen := TStringList.Create;
  try
    { Reserve a loopback port without listening: connection is refused,
      and another CI process cannot acquire this test's destination. }
    ReservedSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    Check(ReservedSocket >= 0, 'reserve loopback destination');
    FillChar(Address, SizeOf(Address), 0);
    Address.sin_family := AF_INET;
    Address.sin_addr := StrToNetAddr('127.0.0.1');
    Check(fpBind(ReservedSocket, @Address, SizeOf(Address)) = 0, 'bind loopback destination');
    AddressSize := SizeOf(Address);
    Check(fpGetSockName(ReservedSocket, @Address, @AddressSize) = 0, 'read reserved port');
    ClosedTarget := '127.0.0.1:' + IntToStr(ntohs(Address.sin_port));
    Input := TFileStream.Create(ExtractFilePath(ParamStr(0)) + 'Graal603', fmOpenRead);
    try
      Output := TFileStream.Create(Client, fmCreate);
      try Output.CopyFrom(Input, 0); finally Output.Free; end;
    finally Input.Free; end;
    Check(fpChmod(PChar(Client), &700) = 0, 'copied actual client executable');
    Text.Add('#!/bin/sh');
    Text.Add('printf ''%s\n'' "$@" > "$QUATTRO_CLI_RECEIPT"');
    Text.Add('printf ''password=%s\n'' "$GRAAL_QUATTRO_PW" >> "$QUATTRO_CLI_RECEIPT"');
    Text.Add('exit 23');
    Text.SaveToFile(Player);
    Check(fpChmod(PChar(Player), &700) = 0, 'generated fake player executable');
    ForceDirectories(Dir + 'data folder');

    Run(['--window', '--level', 'generated missing.nw', '--x', '12.5', '--y', '9',
      '--data', Dir + 'data folder', '--seconds', '2'], True);
    Seen.LoadFromFile(Receipt);
    Check((Seen[0] = '--build') and (Seen[1] = '6.03r7'), 'exact build forwarded');
    Check((Seen.IndexOf('--offline') >= 0) and (Seen.IndexOf('generated missing.nw') >= 0), 'offline path preserved');
    Check((Seen.IndexOf('12.5') >= 0) and (Seen.IndexOf('9') >= 0) and
      (Seen.IndexOf('--asset-root') >= 0) and
      (Seen.IndexOf(Dir + 'data folder') >= 0) and
      (Seen.IndexOf('--seconds') >= 0), 'coordinates roots and duration forwarded');
    Check(Seen[Seen.IndexOf('--assets') + 1] = ExcludeTrailingPathDelimiter(Dir), 'program assets retain first priority');

    Run(['--window', '--server', '127.0.0.1:14802', '--account', 'generated',
      '--server-name', 'Generated world', '--secure-login', 'off'], True, 'required');
    Seen.LoadFromFile(Receipt);
    Check((Seen.IndexOf('--connect') >= 0) and (Seen.IndexOf('Generated world') >= 0), 'online arguments forwarded');
    Check(Seen.IndexOf('password=generated-cli-password') >= 0, 'password supplied only in child environment');
    Check((Seen.IndexOf('generated-cli-password') < 0) and
      (Seen.IndexOf('stale-parent-password') < 0), 'password absent from command arguments');

    Run(['--window', '--level', 'missing.nw'], False, 'off', True, True);
    Run(['--window', '--level', 'missing.nw'], False, 'off', False);
    Run(['--window', '--headless', '--level', 'missing.nw'], False);
    Run(['--window', '--level', 'missing.nw', '--frames', '1'], False);
    Run(['--window', '--level', 'missing.nw', '--dump', 'unused.bmp'], False);
    Run(['--window', '--level', 'missing.nw', '--unknown-option'], False);
    Run(['--window', '--level', 'missing.nw', '--x', '12,5'], False);
    Run(['--window', '--level', 'missing.nw', '--y', 'NaN'], False);
    ForceDirectories(Dir + '_clients');
    Run(['--window', '--level', 'missing.nw'], False);
    RemoveDir(Dir + '_clients');
    Run(['--window', '--server', ClosedTarget, '--account', 'generated',
      '--secure-login', 'required'], False);
    Run(['--window', '--server', ClosedTarget, '--account', 'generated'], False, 'required');
    Run(['--window', '--server', ClosedTarget, '--account', 'generated',
      '--server-key', 'generated-invalid-key'], False);
    DeleteFile(Player);
    Run(['--window', '--level', 'missing.nw'], False);
  finally
    Text.Free;
    Seen.Free;
    DeleteFile(Client);
    DeleteFile(Player);
    DeleteFile(Receipt);
    if ReservedSocket >= 0 then fpClose(ReservedSocket);
    RemoveDir(Dir + 'data folder');
    RemoveDir(Dir);
  end;
end;
{$ENDIF}

begin
{$IFDEF LINUX}
  TestDispatch;
{$ELSE}
  WriteLn('ok windowed CLI Quattro handoff is Linux-only');
{$ENDIF}
end.
