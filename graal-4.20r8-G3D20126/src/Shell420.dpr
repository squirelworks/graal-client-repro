{ Shell420: the Delphi-shaped shell for the 4.2.0.8 engine host.

  The original launcher is Delphi. The residual Torque surface is the
  C++ program common/torque/host4208. This shell finds that program and
  runs it. It does not speak the wire itself. }
program Shell420;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}
{ Windows: version info and manifest (src/Shell420.rc), and the DEP and ASLR
  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR
  in the Windows build flags). }
{$IFDEF MSWINDOWS}{$IFDEF FPC}{$R Shell420.rc}{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}

uses
  SysUtils;

function HostPath: string;
var
  Dir, Candidate: string;
  I: Integer;
begin
  Result := '';
  Dir := ExtractFilePath(ParamStr(0));
  for I := 1 to 8 do
  begin
    Candidate := ExpandFileName(Dir + 'common/torque/host4208/build/host4208');
    if FileExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
    Dir := Dir + '../';
  end;
end;

var
  Exe: string;
  Args: array of RawByteString;
  I: Integer;
begin
  WriteLn('shell 4.2.0.8 Delphi');
  Flush(Output);
  Exe := HostPath;
  if Exe = '' then
  begin
    WriteLn('engine host missing');
    Halt(1);
  end;
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  Halt(ExecuteProcess(Exe, Args));
end.
