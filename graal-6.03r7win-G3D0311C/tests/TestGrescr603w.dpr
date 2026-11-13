{ Checks the 6.037 GRESCR01 accept path and the want-script stubs.
  The token is not changed. No numeric packet id is invented. }
program TestGrescr603w;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils,
  Protocol603w in '../src/Protocol603w.pas',
  Grescr603w in '../src/Grescr603w.pas';

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

procedure TestToken;
begin
  Check(ClientVersionToken = 'G3D0311C', 'folder keeps G3D0311C');
  Check(not LinksTorque, 'quattro_lib, not a Torque link');
end;

procedure TestGrescr;
var
  I: Integer;
  Buf: AnsiString;
begin
  for I := 0 to Length(GrescrMagic) - 1 do
    Check(not GrescrLoad(Copy(GrescrMagic, 1, I)),
      Format('truncated magic of %d bytes rejected', [I]));
  for I := 1 to Length(GrescrMagic) do
  begin
    Buf := GrescrMagic;
    Buf[I] := #0;
    Check(not GrescrLoad(Buf), 'each magic byte is checked');
  end;
  Check(GrescrLoad(GrescrMagic + #0#128#255), 'binary tail passes probe');
  Check(GrescrPayloadLen = 3, 'binary tail length counts bytes');
  Check(not GrescrAccepted(''), 'empty file rejected');
  Check(not GrescrAccepted('GRESCR0'), 'seven bytes rejected');
  Check(not GrescrAccepted('GRESCR00'), 'wrong magic rejected');
  Check(GrescrLog = '', 'a wrong magic does not log a payload');
  Check(GrescrAccepted(GrescrMagic), 'eight-byte magic accepted');
  Check(GrescrPayloadLen = 0, 'magic alone has an empty payload');
  Check(GrescrAccepted(GrescrMagic + 'tail'), 'magic plus a body accepted');
  WriteLn(GrescrLog);
  Check(GrescrPayloadLen = 4, 'payload length is the bytes after the magic');
  Check(GrescrLog = 'GRESCR01 payload 4', 'accept path logs the payload length');
  Check(not GrescrAccepted('short'), 'a short buffer is still rejected');
  Check(GrescrPayloadLen = -1, 'a reject clears the payload length');
  Check(GrescrLog = '', 'a reject does not log a payload');
  Check(GrescrCrcStart = 9, 'CRC covers the bytes after the magic');
  Check(Copy(GrescrMagic + 'tail', GrescrCrcStart, MaxInt) = 'tail',
    'covered bytes are the tail');
end;

procedure TestSend;
var
  Line: string;
begin
  Line := SendWantClassScript('abc');
  WriteLn(Line);
  Check(Line = 'onSendWantClassScript id=unknown len=3',
    'class-script send writes the name and the length');
  Check(SendWantWeaponScript('') = 'onSendWantWeaponScript id=unknown len=0',
    'weapon-script send allows an empty payload');
  Check(SendWantGaniScript('gani') = 'onSendWantGaniScript id=unknown len=4',
    'gani-script send writes the name and the length');
  Check(Pos('id=23', SendWantClassScript('abc')) = 0,
    'the outgoing table id is not invented');
end;


begin
  Passed := 0;
  Failed := 0;
  TestToken;
  TestGrescr;
  TestSend;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
