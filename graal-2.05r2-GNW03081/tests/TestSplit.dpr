{ GSplit checks (#114): SplitDelimited must give the items TStringList's
  strict DelimitedText gives under Free Pascal, for every delimiter the
  clients use. }
program TestSplit;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Classes,
  GSplit in '../../common/GSplit.pas';

var
  Passed, Failed: Integer;

procedure Check(OK: Boolean; const Name: string);
begin
  if OK then
  begin
    Inc(Passed);
    WriteLn('ok    ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name);
  end;
end;

function Show(L: TStrings): string;
var
  I: Integer;
begin
  Result := IntToStr(L.Count) + ':';
  for I := 0 to L.Count - 1 do Result := Result + '[' + L[I] + ']';
end;

{ True if both ways split S alike }
function Same(const S: string; Delim: Char; out Got, Want: string): Boolean;
var
  A, B: TStringList;
begin
  A := TStringList.Create;
  B := TStringList.Create;
  try
    A.Add('stale');
    SplitDelimited(S, Delim, A);
    B.Delimiter := Delim;
    B.StrictDelimiter := True;
    B.DelimitedText := S;
    Got := Show(A);
    Want := Show(B);
    Result := Got = Want;
  finally
    A.Free;
    B.Free;
  end;
end;

procedure Expect(const S: string; Delim: Char; const Items: string);
var
  Got, Want: string;
begin
  Check(Same(S, Delim, Got, Want) and (Got = Items),
    Format('split %s at %s: %s (TStringList %s)', [QuotedStr(S), QuotedStr(Delim), Got, Want]));
end;

const
  Pieces: array[0..9] of string = ('a', 'bc', ' ', '"', '""', ',', '|', '', 'x y', #9);
  Delims: array[0..2] of Char = (',', '|', ' ');

procedure TestRandom;
var
  N, K, Bad: Integer;
  S, Got, Want, First: string;
begin
  RandSeed := 114;
  Bad := 0;
  First := '';
  for N := 1 to 5000 do
  begin
    S := '';
    for K := 1 to Random(8) do S := S + Pieces[Random(Length(Pieces))];
    if not Same(S, Delims[N mod 3], Got, Want) then
    begin
      Inc(Bad);
      if First = '' then First := QuotedStr(S) + ' ' + Got + ' vs ' + Want;
    end;
  end;
  Check(Bad = 0, 'random: 5000 lines split alike' + Copy(' (first: ' + First + ')', 1, Ord(Bad > 0) * MaxInt));
end;

begin
  Passed := 0;
  Failed := 0;
  Expect('', ',', '0:');
  Expect('a', ',', '1:[a]');
  Expect('a,b,c', ',', '3:[a][b][c]');
  Expect('a,,c', ',', '3:[a][][c]');
  Expect('a,', ',', '2:[a][]');
  Expect(',a', ',', '2:[][a]');
  Expect(',', ',', '2:[][]');
  Expect(' a , b ', ',', '2:[ a ][ b ]');
  Expect('ServerList|name|1.2.3.4|14900', '|', '4:[ServerList][name][1.2.3.4][14900]');
  Expect('say  it''s  me', ' ', '5:[say][][it''s][][me]');
  Expect('"a,b",c', ',', '2:[a,b][c]');
  Expect('"say ""hi""",x', ',', '2:[say "hi"][x]');
  Expect('"open', ',', '1:[open]');
  Expect('"a"b,c', ',', '3:[a][b][c]');
  Expect('x"y",z', ',', '2:[x"y"][z]');
  Expect('1,2.5,-3', ',', '3:[1][2.5][-3]');
  Expect('a'#9'b,c', ',', '2:[a'#9'b][c]');
  TestRandom;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
