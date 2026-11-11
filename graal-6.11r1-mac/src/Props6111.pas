{ Props6111: property stores.

  verified-from-evidence:
    the 6.11 Mac exposes tclient_setplayerprops, tclient_setotherplayerprops,
    tclient_setnpcprops and tclient_setbaddyprops to script
    (protocol/v6x-clients.md "What the script controls"). Each setter here
    stores one string. The 6.11 property id tables were not read, so no id
    table is copied from the 6.1.1.3 folder.
  provisional adapter:
    none.
  lab-only fixture:
    a LABPROP1 text block. It is not a 6.11 property stream. }
unit Props6111;

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
