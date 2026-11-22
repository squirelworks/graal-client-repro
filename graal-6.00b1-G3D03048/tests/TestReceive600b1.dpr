program TestReceive600b1;
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
uses SysUtils, Protocol600b1 in '../src/Protocol600b1.pas';
var Id, Count, Passed, Failed: Integer;
procedure Check(Cond: Boolean; const Name: string);
begin
  if Cond then begin Inc(Passed); WriteLn('ok ', Name); end
  else begin Inc(Failed); WriteLn('FAIL ', Name); end;
end;
begin
  { The published early-2010 receive switch has 97 entries. This is a
    direct test of the rebuild gate, not original-client execution. }
  Count := 0;
  for Id := 0 to 255 do if PLOKnown(Id) then Inc(Count);
  Check(Count = 97, 'documented receive count 97, actual ' + IntToStr(Count));
  Check(PLOKnown(41), 'receive 41');
  Check(PLOKnown(165), 'receive 165');
  Check(PLOKnown(169), 'receive 169');
  Check(PLOKnown(175), 'receive 175');
  Check(PLOKnown(181), 'receive 181');
  Check(PLOKnown(184), 'receive 184');
  Check(not PLOKnown(111), 'unlisted 111 stays ignored');
  Check(not PLOKnown(26), 'unlisted 26 stays ignored');
  Check(not PLOKnown(-1) and not PLOKnown(256), 'outside byte range ignored');
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed <> 0 then Halt(1);
end.
