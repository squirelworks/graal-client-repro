{ GTypes: the Graal "G" integer types and a message reader/writer.

  Every value on the wire is split into 7-bit groups, each offset by 0x20,
  so a message never holds a #10 byte. Sources: graal_analysis
  protocol/codec-and-framing.md (GCHAR, GSHORT, GINT3, GINT4, GINT5, GSTRING).

  Strings are used as byte buffers, the way Delphi 4/5 code of the time did:
  `string` is an AnsiString, one byte per character. }
unit GTypes;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  { Reads one message payload, front to back. Reading past the end yields 0
    or '' and sets Overrun, the way the original treats a short message. }
  TGReader = class
  private
    FData: string;
    FPos: Integer; { 1-based }
  public
    Overrun: Boolean;
    constructor Create(const AData: string);
    function Remaining: Integer;
    function Eof: Boolean;
    function ReadByte: Byte;
    function ReadGChar: Integer;
    function ReadGShort: Integer;
    function ReadGInt3: Integer;
    function ReadGInt4: Cardinal;
    function ReadGInt5: Cardinal;
    function ReadChars(Count: Integer): string;
    function ReadGString: string;
    function ReadRest: string;
    property Position: Integer read FPos;
  end;

function GChar(V: Integer): Char;
function GShort(V: Integer): string;
function GInt3(V: Integer): string;
function GInt4(V: Cardinal): string;
function GInt5(V: Cardinal): string;
function GString(const S: string): string;

implementation

function Clamp(V, Lo, Hi: Integer): Integer;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

function GChar(V: Integer): Char;
begin
  Result := Chr(Clamp(V, 0, 223) + $20);
end;

function GShort(V: Integer): string;
begin
  V := Clamp(V, 0, 28671); { high group at most 223 }
  Result := Chr((V shr 7) + $20) + Chr((V and $7F) + $20);
end;

function GInt3(V: Integer): string;
begin
  V := Clamp(V, 0, 3670015); { high group at most 223 }
  Result := Chr((V shr 14) + $20) + Chr(((V shr 7) and $7F) + $20) +
    Chr((V and $7F) + $20);
end;

function GInt4(V: Cardinal): string;
begin
  Result := Chr(((V shr 21) and $7F) + $20) + Chr(((V shr 14) and $7F) + $20) +
    Chr(((V shr 7) and $7F) + $20) + Chr((V and $7F) + $20);
end;

function GInt5(V: Cardinal): string;
begin
  Result := Chr(((V shr 28) and $0F) + $20) + GInt4(V and $0FFFFFFF);
end;

function GString(const S: string): string;
var
  T: string;
begin
  T := Copy(S, 1, 223);
  Result := GChar(Length(T)) + T;
end;

{ TGReader }

constructor TGReader.Create(const AData: string);
begin
  inherited Create;
  FData := AData;
  FPos := 1;
end;

function TGReader.Remaining: Integer;
begin
  Result := Length(FData) - FPos + 1;
  if Result < 0 then Result := 0;
end;

function TGReader.Eof: Boolean;
begin
  Result := FPos > Length(FData);
end;

function TGReader.ReadByte: Byte;
begin
  if FPos > Length(FData) then
  begin
    Overrun := True;
    Result := 0;
    Exit;
  end;
  Result := Ord(FData[FPos]);
  Inc(FPos);
end;

function TGReader.ReadGChar: Integer;
begin
  Result := ReadByte - $20;
  if Result < 0 then Result := 0;
end;

function TGReader.ReadGShort: Integer;
begin
  Result := ReadGChar shl 7;
  Result := Result + ReadGChar;
end;

function TGReader.ReadGInt3: Integer;
begin
  Result := ReadGChar shl 14;
  Result := Result + ReadGChar shl 7;
  Result := Result + ReadGChar;
end;

function TGReader.ReadGInt4: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to 4 do
    Result := (Result shl 7) or Cardinal(ReadGChar and $7F);
end;

function TGReader.ReadGInt5: Cardinal;
begin
  Result := Cardinal(ReadGChar and $0F) shl 28;
  Result := Result or ReadGInt4;
end;

function TGReader.ReadChars(Count: Integer): string;
begin
  if Count < 0 then Count := 0;
  if Count > Remaining then
  begin
    Overrun := True;
    Count := Remaining;
  end;
  Result := Copy(FData, FPos, Count);
  Inc(FPos, Count);
end;

function TGReader.ReadGString: string;
begin
  Result := ReadChars(ReadGChar);
end;

function TGReader.ReadRest: string;
begin
  Result := ReadChars(Remaining);
end;

end.
