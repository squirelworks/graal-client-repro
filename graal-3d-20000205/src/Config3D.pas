{ Config3D: graal3dconfig.txt, the client's settings file.

  key=value lines, read at start and written back when settings change
  (graal_analysis graal3d/formats.md). The file lives next to the program.
  The original keeps the nickname, account and (DES-hidden) password in the
  Windows registry; this build does not store them yet. }
unit Config3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

type
  TConfig3D = record
    ServerAddr: string;
    ServerPort: Integer;
    FixedPort: Boolean;
    FixedUdpPort: Integer;
    NoUdp: Boolean;
    BodyX, HeadX, BodyTex: string;
    ArmColor, ShoeColor, HandColor: Cardinal;
    AccountName, Password: string;
  end;

{ The defaults. The connect window's host starts as the community list
  server's host (this build is from before the server list; see the
  build's README), never a loopback address. }
procedure DefaultConfig(out C: TConfig3D);
procedure ParseConfig(const Text: string; var C: TConfig3D);
function ConfigText(const C: TConfig3D): string;
function LoadConfig(const FileName: string; var C: TConfig3D): Boolean;
procedure SaveConfig(const FileName: string; const C: TConfig3D);
function ParseColor(const S: string; Def: Cardinal): Cardinal;

const
  DefaultHost = 'listserver.graal.in';
  ConfigName = 'graal3dconfig.txt';

implementation

uses
  SysUtils, Classes, Codec3D;

procedure DefaultConfig(out C: TConfig3D);
begin
  C.ServerAddr := DefaultHost;
  C.ServerPort := DefaultPort;
  C.FixedPort := False;
  C.FixedUdpPort := DefaultUdpPort;
  C.NoUdp := False;
  C.BodyX := 'body.x';
  C.HeadX := 'head.x';
  C.BodyTex := 'body.bmp';
  C.ArmColor := $FF0000;
  C.ShoeColor := $800000;
  C.HandColor := $FDCC47;
  C.AccountName := 'guest';
  C.Password := 'guest';
end;

function ParseColor(const S: string; Def: Cardinal): Cardinal;
var
  T: string;
  V: Int64;
begin
  T := Trim(S);
  if (Length(T) > 2) and (T[1] = '0') and (UpCase(T[2]) = 'X') then
    T := '$' + Copy(T, 3, MaxInt);
  V := StrToInt64Def(T, -1);
  if (V < 0) or (V > $FFFFFF) then Result := Def else Result := Cardinal(V);
end;

function Bool(const S: string; Def: Boolean): Boolean;
begin
  if CompareText(Trim(S), 'true') = 0 then Result := True
  else if CompareText(Trim(S), 'false') = 0 then Result := False
  else Result := Def;
end;

procedure ParseConfig(const Text: string; var C: TConfig3D);
var
  L: TStringList;
  I, P: Integer;
  K, V: string;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    for I := 0 to L.Count - 1 do
    begin
      P := Pos('=', L[I]);
      if P = 0 then Continue;
      K := LowerCase(Trim(Copy(L[I], 1, P - 1)));
      V := Trim(Copy(L[I], P + 1, MaxInt));
      if K = 'serveraddr' then C.ServerAddr := V
      else if K = 'serverport' then C.ServerPort := StrToIntDef(V, C.ServerPort)
      else if K = 'fixedport' then C.FixedPort := Bool(V, C.FixedPort)
      else if K = 'fixedudpport' then C.FixedUdpPort := StrToIntDef(V, C.FixedUdpPort)
      else if K = 'noudp' then C.NoUdp := Bool(V, C.NoUdp)
      else if K = 'bodyx' then C.BodyX := V
      else if K = 'headx' then C.HeadX := V
      else if K = 'bodytex' then C.BodyTex := V
      else if K = 'armcolor' then C.ArmColor := ParseColor(V, C.ArmColor)
      else if K = 'shoecolor' then C.ShoeColor := ParseColor(V, C.ShoeColor)
      else if K = 'handcolor' then C.HandColor := ParseColor(V, C.HandColor)
      else if K = 'accountname' then C.AccountName := V
      else if K = 'password' then C.Password := V;
    end;
  finally
    L.Free;
  end;
end;

function BoolText(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

function ConfigText(const C: TConfig3D): string;
begin
  Result := 'serveraddr=' + C.ServerAddr + #13#10 +
    'serverport=' + IntToStr(C.ServerPort) + #13#10 +
    'fixedport=' + BoolText(C.FixedPort) + #13#10 +
    'fixedudpport=' + IntToStr(C.FixedUdpPort) + #13#10 +
    'noudp=' + BoolText(C.NoUdp) + #13#10 +
    'bodyx=' + C.BodyX + #13#10 +
    'headx=' + C.HeadX + #13#10 +
    'bodytex=' + C.BodyTex + #13#10 +
    'armcolor=0x' + IntToHex(C.ArmColor, 6) + #13#10 +
    'shoecolor=0x' + IntToHex(C.ShoeColor, 6) + #13#10 +
    'handcolor=0x' + IntToHex(C.HandColor, 6) + #13#10;
end;

function LoadConfig(const FileName: string; var C: TConfig3D): Boolean;
var
  L: TStringList;
begin
  Result := FileExists(FileName);
  if not Result then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      Result := False;
      Exit;
    end;
    ParseConfig(L.Text, C);
  finally
    L.Free;
  end;
end;

procedure SaveConfig(const FileName: string; const C: TConfig3D);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := ConfigText(C);
    try
      L.SaveToFile(FileName);
    except
      { a read-only folder: the settings stay for this run only }
    end;
  finally
    L.Free;
  end;
end;

end.
