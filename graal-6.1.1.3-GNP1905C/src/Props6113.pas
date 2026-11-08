{ Props6113: property stores and the one parsed incoming event.

  verified-from-evidence:
    tclient_setplayerprops, tclient_setotherplayerprops, tclient_setnpcprops
    and tclient_setbaddyprops each store one string and do not switch on a
    property id. The player encoder walks 0..83 and has no case for twelve
    ids. An id that does have a case is stored plus 32 on the wire. The
    value bytes after that id were not recovered, so they are not written.
    onToall reads a player id and a text length when the body is long enough.
  provisional adapter:
    none.
  lab-only fixture:
    a LABPROP1 text block. It is not a 6.1.1.3 property stream.

  Sources: protocol/v6-props.md, protocol/v6-repro-facts.md, manual section
  2.3.7. }
unit Props6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  LabPropMagic = 'LABPROP1';

type
  TPropBag = class
  public
    Player, Other, Npc, Baddy: string;
    procedure SetPlayer(const S: string);
    procedure SetOther(const S: string);
    procedure SetNpc(const S: string);
    procedure SetBaddy(const S: string);
  end;

function PlayerIdHasCase(Id: Integer): Boolean;
function BaddyIdHasCase(Id: Integer): Boolean;
function NpcIdHasCase(Id: Integer): Boolean;
function PropIdPrefix(Id: Integer; HasCase: Boolean; out Wire: Byte;
  out Err: string): Boolean;
function ParseOnToall(const Body: string; out PlayerId: Integer;
  out Text: string): Boolean;

function LabEncodeProps(const Body: string): string;
function LabDecodeProps(const Stored: string; out Body: string): Boolean;

implementation

uses
  SysUtils;

procedure TPropBag.SetPlayer(const S: string);
begin
  Player := S;
end;

procedure TPropBag.SetOther(const S: string);
begin
  Other := S;
end;

procedure TPropBag.SetNpc(const S: string);
begin
  Npc := S;
end;

procedure TPropBag.SetBaddy(const S: string);
begin
  Baddy := S;
end;

function PlayerIdHasCase(Id: Integer): Boolean;
begin
  Result := (Id >= 0) and (Id <= 83) and (Id <> 3) and (Id <> 25) and
    (Id <> 27) and (Id <> 28) and (Id <> 29) and (Id <> 30) and (Id <> 34) and
    (Id <> 36) and (Id <> 50) and (Id <> 51) and (Id <> 77) and (Id <> 83);
end;

function BaddyIdHasCase(Id: Integer): Boolean;
begin
  Result := (Id >= 0) and (Id <= 10);
end;

function NpcIdHasCase(Id: Integer): Boolean;
begin
  { No numbered NPC property-id table was found. }
  Result := False;
  if Id < 0 then Result := False;
end;

function PropIdPrefix(Id: Integer; HasCase: Boolean; out Wire: Byte;
  out Err: string): Boolean;
begin
  Wire := 0;
  Err := '';
  Result := False;
  if not HasCase then
  begin
    Err := 'no encoder case';
    Exit;
  end;
  if (Id < 0) or (Id > 255 - 32) then
  begin
    Err := 'id prefix was not recovered for this id';
    Exit;
  end;
  Wire := Byte(Id + 32);
  Result := True;
end;

function ParseOnToall(const Body: string; out PlayerId: Integer;
  out Text: string): Boolean;
var
  N: Integer;
begin
  PlayerId := 0;
  Text := '';
  Result := False;
  if Length(Body) <= 2 then Exit;
  if Ord(Body[3]) < 32 then Exit;
  N := Ord(Body[3]) - 32;
  if Length(Body) < 3 + N then Exit;
  PlayerId := (Ord(Body[1]) - 32) * 128 + (Ord(Body[2]) - 32);
  Text := Copy(Body, 4, N);
  Result := True;
end;

function LabEncodeProps(const Body: string): string;
begin
  Result := LabPropMagic + #10 + Body;
end;

function LabDecodeProps(const Stored: string; out Body: string): Boolean;
var
  N: Integer;
begin
  Body := '';
  N := Length(LabPropMagic);
  Result := (Length(Stored) >= N) and (Copy(Stored, 1, N) = LabPropMagic);
  if not Result then Exit;
  if (Length(Stored) > N) and (Stored[N + 1] = #10) then
    Body := Copy(Stored, N + 2, MaxInt)
  else
    Body := Copy(Stored, N + 1, MaxInt);
end;

end.
