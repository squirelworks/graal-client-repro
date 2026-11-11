{ Frame6113: the 6.1.1.3 framer this folder can actually check.

  verified-from-evidence:
    sendraw appends the caller's bytes and writes no header and no counter.
    setprotocol fills T, then I, then E, then L, big-endian. L is the header
    length plus the body length. A numbered send is refused until the
    template has both L and T. E is 1 (zlib) or 2 (bzip2) only for the one
    compression id stored on the connection, at the documented sizes.
    Generation-5 is the starting framer: newline refusal, flush at 4096,
    and the LCG seed from the unpacked wire note. setencryptionout accepts
    the names AES and RC4 and clears any other name.
  provisional adapter:
    zlib and bzip2 go through the repo units. The bzip2 block-size digit
    is set to 5. The bit stream is not libbzip2.
  lab-only fixture:
    none. This unit does not invent a session cipher, a template, or the
    id-50 byte order.

  Sources: protocol/v6113-hello.md, protocol/v6-repro-facts.md,
  protocol/unpacked-6113-wire.md, protocol/v6113-pli.md. }
unit Frame6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { Observed on the wire. Not a string in the image. }
  ClearHello = 'GNP1905C';
  { The connect path stops after those eight bytes. The session cipher
    was not identified, so loopback and stress must not demand a gserver
    login and must not pad the hello. }
  ClearHelloStop = True;
  CannotSend = 'Cannot send data, socket is not in a state where data can be sent';
  IllegalChars = 'Illegal characters in the outgoing data';
  Id50Gap = 'id 50 prefix byte order was not recovered';
  { protocol/unpacked-6113-wire.md. Decimal so the constant is not written
    as an address. }
  Gen5Seed = 78121784;
  Gen5Mul = 134777861;
  ZlibAt = 48;
  BzipAt = 4096;
  Gen5FlushAt = 4096;
  BzipBlockBytes = 500000;

type
  TEncOut = (eoDefaultLcg, eoNamedUnused, eoCleared);

  TField = record
    At: Integer; { 0-based index in the header, -1 if the letter is absent }
    Width: Integer;
  end;

  TProtocol = class
  public
    OnGen5: Boolean;
    HeaderLen: Integer;
    FI, FL, FT, FE: TField;
    Counter: Integer;
    CompressId: Integer;
    BzipGlobal, BzipConn: Boolean;
    ForceCompressFail: Boolean;
    Mode: Integer;
    LcgState: Cardinal;
    Enc: TEncOut;
    EncName: string;
    Buffered: Integer;
    Flushes: Integer;
    constructor Create;
    procedure SetProtocol(const Template: string);
    function HasL: Boolean;
    function HasT: Boolean;
    function SendRaw(const Data: string; out Wire: string): Boolean;
    function SendData(Id: Integer; const Body: string; out Wire, Err: string): Boolean;
    function Compression(Id: Integer; const Body: string): Integer;
    function Gen5Reject(Id: Integer; const Body: string): string;
    procedure SetEncryptionOut(const Name, Key, IV: string);
    function LcgStepPlusOne: Cardinal;
    function LcgStepPlusKey(Key7: Integer): Cardinal;
  end;

function HeaderPlusBody(HeaderLen, BodyLen: Integer): Integer;

implementation

uses
  SysUtils,
  GZlib, GBzip2;

function HeaderPlusBody(HeaderLen, BodyLen: Integer): Integer;
begin
  Result := HeaderLen + BodyLen;
end;

function BlankField: TField;
begin
  Result.At := -1;
  Result.Width := 0;
end;

function Fits(Value: Int64; Width: Integer): Boolean;
begin
  if (Width < 1) or (Width > 4) or (Value < 0) then
    Result := False
  else if Width = 4 then
    Result := Value <= $FFFFFFFF
  else
    Result := Value < (Int64(1) shl (Width * 8));
end;

procedure Poke(var H: string; At, Width: Integer; Value: Int64);
var
  I: Integer;
begin
  for I := 0 to Width - 1 do
    H[At + 1 + I] := Chr((Value shr ((Width - 1 - I) * 8)) and 255);
end;

{ The repo encoder writes a block-size digit of 9 and chunks at 500000
  bytes, which is the size-5 budget. Bodies that fit in one such block get
  the documented digit. Larger bodies are refused so the framer sends them
  uncompressed. }
function BzipBlock5(const Data: string): string;
begin
  Result := '';
  if (Length(Data) = 0) or (Length(Data) > BzipBlockBytes) then Exit;
  Result := BZ2Compress(Data);
  if (Length(Result) >= 4) and (Copy(Result, 1, 3) = 'BZh') then
    Result[4] := '5';
end;

constructor TProtocol.Create;
begin
  inherited Create;
  OnGen5 := True;
  FI := BlankField;
  FL := BlankField;
  FT := BlankField;
  FE := BlankField;
  Counter := 1;
  CompressId := -1;
  Mode := 3;
  LcgState := Gen5Seed;
  Enc := eoDefaultLcg;
end;

function TProtocol.HasL: Boolean;
begin
  Result := FL.At >= 0;
end;

function TProtocol.HasT: Boolean;
begin
  Result := FT.At >= 0;
end;

procedure TProtocol.SetProtocol(const Template: string);
var
  I, W, Width: Integer;
  C: Char;
  Field: ^TField;
begin
  OnGen5 := False;
  HeaderLen := Length(Template);
  FI := BlankField;
  FL := BlankField;
  FT := BlankField;
  FE := BlankField;
  Counter := 1;
  I := 1;
  while I <= Length(Template) do
  begin
    C := Template[I];
    W := 1;
    while (I + W <= Length(Template)) and (Template[I + W] = C) do
      Inc(W);
    Field := nil;
    if C = 'I' then Field := @FI
    else if C = 'L' then Field := @FL
    else if C = 'T' then Field := @FT
    else if C = 'E' then Field := @FE;
    if (Field <> nil) and (Field^.At < 0) then
    begin
      Width := W;
      if Width > 4 then Width := 4;
      Field^.At := I - 1;
      Field^.Width := Width;
    end;
    Inc(I, W);
  end;
end;

function TProtocol.SendRaw(const Data: string; out Wire: string): Boolean;
begin
  { id -1: the caller's bytes, no header, no new counter value. }
  Wire := Data;
  if OnGen5 then
  begin
    Inc(Buffered, Length(Data));
    while Buffered >= Gen5FlushAt do
    begin
      Dec(Buffered, Gen5FlushAt);
      Inc(Flushes);
    end;
  end;
  Result := True;
end;

function TProtocol.Compression(Id: Integer; const Body: string): Integer;
begin
  Result := 0;
  if FE.At < 0 then Exit;
  if Id <> CompressId then Exit;
  if BzipGlobal and BzipConn and (Length(Body) >= BzipAt) then
    Result := 2
  else if Length(Body) >= ZlibAt then
    Result := 1;
end;

function TProtocol.SendData(Id: Integer; const Body: string; out Wire, Err: string): Boolean;
var
  Header, OutBody, Comp: string;
  Ev: Integer;
  Total: Int64;
begin
  Wire := '';
  Err := '';
  Result := False;
  if OnGen5 then
  begin
    Err := Gen5Reject(Id, Body);
    if Err = '' then
      Err := 'generation-5 numbered send is not used after the clear hello';
    Exit;
  end;
  if not HasL or not HasT then
  begin
    Err := CannotSend;
    Exit;
  end;
  if not Fits(Id, FT.Width) then
  begin
    Err := 'packet id does not fit the T field';
    Exit;
  end;
  if (FI.At >= 0) and not Fits(Counter, FI.Width) then
  begin
    Err := 'packet counter does not fit the I field';
    Exit;
  end;

  Ev := Compression(Id, Body);
  OutBody := Body;
  if Ev = 1 then
  begin
    if ForceCompressFail then Comp := '' else Comp := ZCompress(Body);
    if Comp = '' then
    begin
      Ev := 0;
      OutBody := Body;
    end
    else
      OutBody := Comp;
  end
  else if Ev = 2 then
  begin
    if ForceCompressFail then Comp := '' else Comp := BzipBlock5(Body);
    if Comp = '' then
    begin
      Ev := 0;
      OutBody := Body;
    end
    else
      OutBody := Comp;
  end;

  Total := HeaderPlusBody(HeaderLen, Length(OutBody));
  if not Fits(Total, FL.Width) then
  begin
    Err := 'length does not fit the L field';
    Exit;
  end;
  if (FE.At >= 0) and not Fits(Ev, FE.Width) then
  begin
    Err := 'compression field does not fit E';
    Exit;
  end;

  SetLength(Header, HeaderLen);
  if HeaderLen > 0 then FillChar(Header[1], HeaderLen, 0);
  { Write order from protocol/v6-repro-facts.md. }
  Poke(Header, FT.At, FT.Width, Id);
  if FI.At >= 0 then
  begin
    Poke(Header, FI.At, FI.Width, Counter);
    Inc(Counter);
  end;
  if FE.At >= 0 then
    Poke(Header, FE.At, FE.Width, Ev);
  Poke(Header, FL.At, FL.Width, Total);
  Wire := Header + OutBody;
  Result := True;
end;

function TProtocol.Gen5Reject(Id: Integer; const Body: string): string;
begin
  Result := '';
  if not OnGen5 then Exit;
  if (Pos(#10, Body) > 0) and (Id <> 93) and (Id <> 163) then
    Result := IllegalChars
  else if (Id = 93) or (Id = 163) then
    Result := Id50Gap;
end;

procedure TProtocol.SetEncryptionOut(const Name, Key, IV: string);
begin
  { The key and the initial value are the caller's. No session in the notes
    shows which pair was used, so neither value is stored or applied. }
  if (Length(Key) < 0) or (Length(IV) < 0) then Exit;
  if (Name = 'AES') or (Name = 'RC4') then
  begin
    Enc := eoNamedUnused;
    EncName := Name;
  end
  else
  begin
    Enc := eoCleared;
    EncName := '';
    LcgState := Gen5Seed;
    Mode := 3;
  end;
end;

function TProtocol.LcgStepPlusOne: Cardinal;
begin
  { protocol/unpacked-6113-wire.md: state times the multiplier, plus 1. }
  LcgState := Cardinal((UInt64(LcgState) * UInt64(Gen5Mul) + 1) and $FFFFFFFF);
  Result := LcgState;
end;

function TProtocol.LcgStepPlusKey(Key7: Integer): Cardinal;
var
  K: Integer;
begin
  { protocol/v6113-hello.md adds the key instead of 1. The two notes
    disagree. This step is not applied on the socket. }
  K := Key7 and 127;
  LcgState := Cardinal((UInt64(LcgState) * UInt64(Gen5Mul) + UInt64(K)) and $FFFFFFFF);
  Result := LcgState;
end;

end.
