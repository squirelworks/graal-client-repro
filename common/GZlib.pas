{ GZlib: zlib in and out of string buffers.

  2.05 links zlib 1.1.2 through Borland's ZLib unit (TCompressionStream /
  TDecompressionStream). Free Pascal ships the same classes in `zstream`,
  so the call sites are identical under both compilers. }
unit GZlib;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

function ZCompress(const Data: string): string;
{ Returns False if the data is not a valid zlib stream. }
function ZDecompress(const Data: string; out Plain: string): Boolean;

implementation

uses
  Classes, SysUtils,
{$IFDEF FPC}
  zstream;
{$ELSE}
  ZLib;
{$ENDIF}

function ZCompress(const Data: string): string;
var
  Dest: TMemoryStream;
  Z: TCompressionStream;
begin
  Dest := TMemoryStream.Create;
  try
{$IFDEF FPC}
    Z := TCompressionStream.Create(cldefault, Dest);
{$ELSE}
    Z := TCompressionStream.Create(clDefault, Dest);
{$ENDIF}
    try
      if Length(Data) > 0 then
        Z.WriteBuffer(Data[1], Length(Data));
    finally
      Z.Free; { flushes }
    end;
    SetLength(Result, Dest.Size);
    if Dest.Size > 0 then
      Move(Dest.Memory^, Result[1], Dest.Size);
  finally
    Dest.Free;
  end;
end;

function ZDecompress(const Data: string; out Plain: string): Boolean;
var
  Src: TMemoryStream;
  Z: TDecompressionStream;
  Buf: array[0..4095] of Byte;
  N, Old: Integer;
begin
  Plain := '';
  Result := False;
  if Data = '' then Exit;
  Src := TMemoryStream.Create;
  try
    Src.WriteBuffer(Data[1], Length(Data));
    Src.Position := 0;
    try
      Z := TDecompressionStream.Create(Src);
      try
        repeat
          N := Z.Read(Buf, SizeOf(Buf));
          if N > 0 then
          begin
            Old := Length(Plain);
            SetLength(Plain, Old + N);
            Move(Buf, Plain[Old + 1], N);
          end;
        until N <= 0;
      finally
        Z.Free;
      end;
      Result := True;
    except
      Plain := '';
      Result := False;
    end;
  finally
    Src.Free;
  end;
end;

end.
