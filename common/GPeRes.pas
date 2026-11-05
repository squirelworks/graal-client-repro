{ GPeRes: reads one resource out of a Windows program file (PE32), so a
  rebuild can use what the original client carried in its resources (the
  2.22 offline tutorial levels, RCDATA TUTORIALA1 .. TUTORIALC3) when that
  program lies next to it. Nothing of the original is copied into this
  program. The layout is the PE/COFF format's: the resource table is data
  directory 2, a three-level tree (type, name, language) whose leaves give
  the data's RVA and size. }
unit GPeRes;

interface

const
  RT_RCDATA = 10;

{ The first language's data of resource Name (case-insensitive) of numeric
  type TypeId in the PE32 image Image; False if there is none. }
function PeResourceData(const Image: string; TypeId: Integer; const Name: string;
  out Data: string): Boolean;
{ The same, read from the file ExeFile. }
function PeResource(const ExeFile: string; TypeId: Integer; const Name: string;
  out Data: string): Boolean;

implementation

uses
  SysUtils, Classes;

function U16(const S: string; Off: Int64): Integer;
begin
  if (Off < 0) or (Off + 2 > Length(S)) then Result := -1
  else Result := Ord(S[Off + 1]) or (Ord(S[Off + 2]) shl 8);
end;

function U32(const S: string; Off: Int64): Int64;
begin
  if (Off < 0) or (Off + 4 > Length(S)) then Result := -1
  else
    Result := Int64(Ord(S[Off + 1])) or (Int64(Ord(S[Off + 2])) shl 8) or
      (Int64(Ord(S[Off + 3])) shl 16) or (Int64(Ord(S[Off + 4])) shl 24);
end;

function PeResourceData(const Image: string; TypeId: Integer; const Name: string;
  out Data: string): Boolean;
var
  PE, Opt, Sec, ResRva, ResOff, VA, VSize, RawOff, E, Dir, Leaf, DRva, DSize, DOff: Int64;
  NSec, OptSize, I: Integer;

  { RVA to file offset through the section table }
  function FileOff(Rva: Int64): Int64;
  var
    J: Integer;
    S: Int64;
  begin
    Result := -1;
    for J := 0 to NSec - 1 do
    begin
      S := Sec + J * 40;
      VA := U32(Image, S + 12);
      VSize := U32(Image, S + 8);
      if VSize < U32(Image, S + 16) then VSize := U32(Image, S + 16);
      RawOff := U32(Image, S + 20);
      if (VA >= 0) and (Rva >= VA) and (Rva < VA + VSize) then
      begin
        Result := RawOff + (Rva - VA);
        Exit;
      end;
    end;
  end;

  { the entry of directory D (offset in the resource section) matching
    Id, or Nm when Nm is not ''; '' and Id < 0 take the first entry }
  function Find(D: Int64; Id: Integer; const Nm: string): Int64;
  var
    Named, Ids, J, K, L: Integer;
    Ent, NOff: Int64;
    S: string;
  begin
    Result := -1;
    Named := U16(Image, ResOff + D + 12);
    Ids := U16(Image, ResOff + D + 14);
    if (Named < 0) or (Ids < 0) then Exit;
    for J := 0 to Named + Ids - 1 do
    begin
      Ent := ResOff + D + 16 + J * 8;
      NOff := U32(Image, Ent);
      if NOff < 0 then Exit;
      if (Nm = '') and (Id < 0) then
      begin
        Result := U32(Image, Ent + 4);
        Exit;
      end;
      if NOff and $80000000 <> 0 then
      begin
        if Nm = '' then Continue;
        NOff := ResOff + (NOff and $7FFFFFFF);
        L := U16(Image, NOff);
        if L <> Length(Nm) then Continue;
        SetLength(S, L);
        for K := 1 to L do S[K] := Chr(U16(Image, NOff + 2 * K) and $FF);
        if UpperCase(S) = UpperCase(Nm) then
        begin
          Result := U32(Image, Ent + 4);
          Exit;
        end;
      end
      else if (Nm = '') and (NOff = Id) then
      begin
        Result := U32(Image, Ent + 4);
        Exit;
      end;
    end;
  end;

begin
  Result := False;
  Data := '';
  if (Length(Image) < 64) or (Copy(Image, 1, 2) <> 'MZ') then Exit;
  PE := U32(Image, $3C);
  if (PE < 0) or (Copy(Image, PE + 1, 4) <> 'PE'#0#0) then Exit;
  NSec := U16(Image, PE + 6);
  OptSize := U16(Image, PE + 20);
  Opt := PE + 24;
  { PE32 only (0x10B): the resource directory at 96 + 2 * 8 }
  if U16(Image, Opt) <> $10B then Exit;
  ResRva := U32(Image, Opt + 112);
  if (ResRva <= 0) or (NSec <= 0) or (OptSize <= 0) then Exit;
  Sec := Opt + OptSize;
  ResOff := FileOff(ResRva);
  if ResOff < 0 then Exit;
  { type, name, language: the upper bit of each entry marks a subtree }
  E := Find(0, TypeId, '');
  if (E < 0) or (E and $80000000 = 0) then Exit;
  Dir := E and $7FFFFFFF;
  E := Find(Dir, 0, Name);
  if (E < 0) or (E and $80000000 = 0) then Exit;
  Dir := E and $7FFFFFFF;
  Leaf := Find(Dir, -1, '');
  if (Leaf < 0) or (Leaf and $80000000 <> 0) then Exit;
  DRva := U32(Image, ResOff + Leaf);
  DSize := U32(Image, ResOff + Leaf + 4);
  if (DRva < 0) or (DSize < 0) then Exit;
  DOff := FileOff(DRva);
  if (DOff < 0) or (DOff + DSize > Length(Image)) then Exit;
  Data := Copy(Image, DOff + 1, DSize);
  I := Length(Data);
  Result := I = DSize;
end;

function PeResource(const ExeFile: string; TypeId: Integer; const Name: string;
  out Data: string): Boolean;
var
  F: TFileStream;
  S: string;
begin
  Result := False;
  Data := '';
  if (ExeFile = '') or not FileExists(ExeFile) then Exit;
  try
    F := TFileStream.Create(ExeFile, fmOpenRead or fmShareDenyNone);
    try
      SetLength(S, F.Size);
      if F.Size > 0 then F.ReadBuffer(S[1], F.Size);
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  Result := PeResourceData(S, TypeId, Name, Data);
end;

end.
