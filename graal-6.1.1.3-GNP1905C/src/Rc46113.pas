{ Rc46113: plain RC4 for the 6.1x session cipher.

  The 6.11 clients encrypt everything after the clear key frame with plain
  RC4: the standard key schedule, no bytes dropped, one 16-byte key per
  direction per session (Graal_analysis protocol/v611-outgoing-cipher.md,
  protocol/connector-script.md section 4c). This unit is the textbook
  cipher; nothing here comes from a Graal image. }
unit Rc46113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$Q-}{$R-}

interface

type
  TRc4 = class
  private
    S: array[0..255] of Byte;
    I, J: Byte;
  public
    constructor Create(const Key: string);
    { Each call goes on from where the last one stopped. }
    function Crypt(const Data: string): string;
  end;

implementation

constructor TRc4.Create(const Key: string);
var
  K, L: Integer;
  T: Byte;
begin
  inherited Create;
  for K := 0 to 255 do S[K] := K;
  if Key = '' then Exit;
  L := 0;
  for K := 0 to 255 do
  begin
    L := (L + S[K] + Ord(Key[(K mod Length(Key)) + 1])) and 255;
    T := S[K];
    S[K] := S[L];
    S[L] := T;
  end;
  I := 0;
  J := 0;
end;

function TRc4.Crypt(const Data: string): string;
var
  K: Integer;
  T: Byte;
begin
  Result := Data;
  for K := 1 to Length(Result) do
  begin
    I := I + 1;
    J := J + S[I];
    T := S[I];
    S[I] := S[J];
    S[J] := T;
    Result[K] := Chr(Ord(Result[K]) xor S[Byte(S[I] + S[J])]);
  end;
end;

end.
