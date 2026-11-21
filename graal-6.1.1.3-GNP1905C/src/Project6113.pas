{ Project6113: incremental project-only RSA/RC4 transport, not account admission.
  Uses the project CIPHER.md contract and RFC 8017. No stock key is used. }
unit Project6113;
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
interface
uses Frame6113;
type
  TProjectCipher = class
  private
    FProto: TProtocol;
    FPending, FModulus, FExponent: string;
    FReady, FFailed: Boolean;
  public
    constructor Create(Proto: TProtocol);
    procedure Reset;
    procedure SetParseKey(const Modulus, Exponent: string);
    function Feed(const Wire: string; out Plain, Err: string): Boolean;
    property Ready: Boolean read FReady;
  end;
implementation
uses SysUtils, Cipher6113, Rsa6113,
{$IFDEF FPC} paszlib {$ELSE} ZLib {$ENDIF};

{ One call with a fixed 263-byte output budget: reject before a key reply
  can allocate/decode beyond its exact 262-byte inner packet. Require the
  stream end/checksum and all compressed input consumed, not a valid prefix. }
function InflateKey(const Data: string; out Inner: string): Boolean;
var
{$IFDEF FPC} Z: TZStream; {$ELSE} Z: TZStreamRec; {$ENDIF}
  Buf: array[0..262] of Char;
  Code: Integer;
begin
  Result := False; Inner := '';
  if (Length(Data) < 2) or (Length(Data) > 4090) then Exit;
  FillChar(Z, SizeOf(Z), 0);
{$IFDEF FPC}
  Code := inflateInit(Z);
{$ELSE}
  Code := inflateInit_(Z, ZLIB_VERSION, SizeOf(Z));
{$ENDIF}
  if Code <> Z_OK then Exit;
  try
{$IFDEF FPC} Z.next_in := PByte(PChar(Data)); {$ELSE} Z.next_in := PChar(Data); {$ENDIF}
    Z.avail_in := Length(Data);
    Z.next_out := @Buf[0]; Z.avail_out := SizeOf(Buf);
    Code := inflate(Z, Z_FINISH);
    if (Code <> Z_STREAM_END) or (Z.avail_in <> 0) or (Z.total_out <> 262) then Exit;
    SetLength(Inner, 262); Move(Buf[0], Inner[1], 262);
    Result := True;
  finally inflateEnd(Z); end;
end;
constructor TProjectCipher.Create(Proto: TProtocol);
begin inherited Create; FProto := Proto; Reset; end;
procedure TProjectCipher.Reset;
begin
  FPending := ''; FModulus := ''; FExponent := '';
  FReady := False; FFailed := False;
  FreeAndNilRc(FProto.RcIn); FreeAndNilRc(FProto.RcOut);
  FProto.Enc := eoDefaultLcg; FProto.EncName := '';
  FProto.Counter := 1; FProto.LcgState := Gen5Seed;
end;
procedure TProjectCipher.SetParseKey(const Modulus, Exponent: string);
begin FModulus := Modulus; FExponent := Exponent; end;
function TProjectCipher.Feed(const Wire: string; out Plain, Err: string): Boolean;
var N, Kind: Integer; KeyPlain, Key, IV, Inner: string;
begin
  Result := False; Plain := ''; Err := '';
  if FFailed then begin Err := 'project cipher already failed'; Exit; end;
  if FReady then begin Plain := FProto.DecryptIn(Wire); Result := True; Exit; end;
  { Bound the clear prefix before concatenating. The key frame is RSA-2048. }
  if Length(FPending) + Length(Wire) > 1048576 then
    Err := 'project key reply exceeds receive limit'
  else begin
    FPending := FPending + Wire;
    if Length(FPending) < 6 then begin Result := True; Exit; end;
    N := (Ord(FPending[3]) shl 16) or (Ord(FPending[4]) shl 8) or Ord(FPending[5]);
    if (Ord(FPending[1]) <> 1) or (Ord(FPending[2]) <> 2) or
      (Ord(FPending[6]) <> KeyFrameOuter) or (N < 6) or (N > 4096) then
      Err := 'invalid project clear key header'
    else if Length(FPending) < N then begin Result := True; Exit; end
    else if not InflateKey(Copy(FPending, 7, N - 6), Inner) then
      Err := 'invalid or non-exact compressed project key packet'
    else if (Copy(Inner, 1, 6) <> #0#1#0#1#6#$fc) then
      Err := 'invalid project inner key header'
    else if not RsaUnwrapType2(FModulus, FExponent, Copy(Inner, 7, 256), KeyPlain) then
      Err := 'project key unwrap failed'
    else if not ParseServerKeyPlain(KeyPlain, Kind, Key, IV) or
      (Kind <> KeyTypeRc4) or (Length(Key) <> 16) or (IV <> '') then
      Err := 'project reply must select RC4 with 16-byte key and empty IV'
    else if not FProto.SetEncryptionIn(Kind, Key) then
      Err := 'project incoming cipher refused'
    else begin
      FReady := True;
      { Only bytes AFTER the whole clear outer packet enter RC4. }
      Plain := FProto.DecryptIn(Copy(FPending, N + 1, MaxInt));
      FPending := ''; Result := True; Exit;
    end;
  end;
  FPending := ''; FFailed := True;
end;
end.
