{ The 5.12 launcher's Players window and tray tip, drawn from what the
  engine reports (GEngineHost: ExternalPlayerlistUpdate / Delete and
  SetGraalStatusIcons).

  What the lab's 5.12 showed (2026-11-13, the real launcher under hooks):
  - the window is titled "Players: N online", N counting the player's own
    row; a player alone online sees "1 online" and no rows;
  - the rows sit under fixed groups, in this order: Staff, Buddies, Guild,
    Normal, Ignore, Offline; a row is the player's head and nick, with no
    columns;
  - three tab icons along the top ("Players on this server", "Global
    Guilds", "Servers"), and along the bottom the Status list, then the
    Profile and Options buttons;
  - the tray icon's tip reads "<server>: N online".

  The rebuild draws the list and the bottom bar in its own plain look (the
  original form is not carried): centred group names with an open toggle,
  text tabs where the original has icons, and a Status box with a drop-down
  arrow. Rows with flag $0001 go under Staff (the
  real engine set it on the NPC-Server), other players under Normal; the
  own row is counted but not shown. Buddies, Guild, Ignore and Offline stay
  empty: the launcher-side lists that fill them are not rebuilt. The tabs,
  Status list and buttons are drawn but do nothing yet. }
unit PlayerList512mac;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils, GSurface, GUiFont, GEngineHost;

const
  ListSelf = $4000;
  ListServer = $2000;
  ListStaff = $0001;
  PlayerListW = 240;
  PlayerListH = 420;
  { the fixed groups, in the order the lab's 5.12 showed them }
  PlayerGroups: array[0..5] of string = ('Staff', 'Buddies', 'Guild', 'Normal', 'Ignore', 'Offline');

type
  { Finds a head image (head0.png ...) for a row; nil when there is none.
    The window does not free it. }
  THeadLookup = function(const Name: string): TGSurface of object;

function PlayerListTitle(Online: Integer): string;
function TrayTip(const Server: string; Online: Integer): string;
{ The group a row is listed under (an index into PlayerGroups), -1 for the
  player's own row, which is counted but not listed. }
function PlayerGroup(Flags: Integer): Integer;
{ Draws the window into Dest (PlayerListW x PlayerListH). }
procedure DrawPlayerList(Dest: TGSurface; Host: TEngineHost; Heads: THeadLookup);

implementation

const
  Face = $FFF0F0F0;
  Ink = $FF000000;
  Grey = $FF808080;
  Edge = $FFA0A0A0;
  RowH = 20;
  TabsH = 28;
  BarH = 56;

function PlayerListTitle(Online: Integer): string;
begin
  Result := 'Players: ' + IntToStr(Online) + ' online';
end;

function TrayTip(const Server: string; Online: Integer): string;
begin
  Result := Server + ': ' + IntToStr(Online) + ' online';
end;

function PlayerGroup(Flags: Integer): Integer;
begin
  if (Flags and ListSelf) <> 0 then Result := -1
  else if (Flags and ListStaff) <> 0 then Result := 0
  else Result := 3;
end;

procedure Box(Dest: TGSurface; X, Y, W, H: Integer; Fill: Cardinal);
begin
  Dest.FillRect(X, Y, W, H, Edge);
  Dest.FillRect(X + 1, Y + 1, W - 2, H - 2, Fill);
end;

{ A small down-pointing triangle (the group toggles and the drop-down
  arrow), W pixels wide at the top. }
procedure DownArrow(Dest: TGSurface; X, Y, W: Integer; Color: Cardinal);
var
  R: Integer;
begin
  for R := 0 to W div 2 do
    Dest.FillRect(X + R, Y + R, W - 2 * R, 1, Color);
end;

procedure DrawPlayerList(Dest: TGSurface; Host: TEngineHost; Heads: THeadLookup);
const
  Tabs: array[0..2] of string = ('Players', 'Guilds', 'Servers');
var
  G, I, X, Y, TabW: Integer;
  Head: TGSurface;
  Status: string;
begin
  Dest.SetSize(PlayerListW, PlayerListH);
  Dest.Fill(Face);
  { the three tabs; the first is the one shown }
  TabW := PlayerListW div 3;
  for I := 0 to 2 do
  begin
    if I = 0 then Box(Dest, I * TabW, 0, TabW, TabsH, $FFFFFFFF)
    else Box(Dest, I * TabW, 2, TabW, TabsH - 2, Face);
    UiDrawText(Dest, I * TabW + (TabW - UiTextWidth(Tabs[I], ufRegular)) div 2, 6, Tabs[I], Ink, ufRegular);
  end;
  { the list }
  Box(Dest, 0, TabsH, PlayerListW, PlayerListH - TabsH - BarH, $FFFFFFFF);
  Y := TabsH + 4;
  for G := 0 to High(PlayerGroups) do
  begin
    if Y + RowH > PlayerListH - BarH then Break;
    { the group's name centred, with its open toggle (▽) before it }
    X := (PlayerListW - UiTextWidth(PlayerGroups[G], ufBold)) div 2;
    DownArrow(Dest, X - 14, Y + 6, 9, Grey);
    UiDrawText(Dest, X, Y, PlayerGroups[G], Grey, ufBold);
    Inc(Y, RowH);
    for I := 0 to High(Host.Players) do
    begin
      if PlayerGroup(Host.Players[I].Flags) <> G then Continue;
      if Y + RowH > PlayerListH - BarH then Break;
      Head := nil;
      if Assigned(Heads) and (Host.Players[I].Head <> '') then Head := Heads(Host.Players[I].Head);
      { the middle 16 x 16 of a head sheet's front-facing frame (32 x 32 at
        0, 64), so it fits the row }
      if Head <> nil then Dest.Blit(Head, 8, 64 + 4, 16, 16, 18, Y + 2);
      UiDrawText(Dest, 40, Y + 2, Host.Players[I].Nick, Ink, ufRegular);
      Inc(Y, RowH);
    end;
  end;
  { the bottom bar: the Status list, then Profile and Options }
  Y := PlayerListH - BarH + 6;
  Status := '';
  if Host.Statuses.Count > 0 then Status := Host.Statuses[0];
  Box(Dest, 6, Y, PlayerListW - 12, 20, $FFFFFFFF);
  UiDrawText(Dest, 10, Y + 2, Status, Ink, ufRegular);
  { the drop-down button at the right of the Status list }
  Box(Dest, PlayerListW - 6 - 18, Y + 1, 17, 18, Face);
  DownArrow(Dest, PlayerListW - 6 - 18 + 4, Y + 8, 9, Ink);
  Inc(Y, 24);
  Box(Dest, 6, Y, (PlayerListW - 18) div 2, 22, Face);
  UiDrawText(Dest, 6 + ((PlayerListW - 18) div 2 - UiTextWidth('Profile', ufRegular)) div 2, Y + 3, 'Profile', Ink, ufRegular);
  Box(Dest, 12 + (PlayerListW - 18) div 2, Y, (PlayerListW - 18) div 2, 22, Face);
  UiDrawText(Dest, 12 + (PlayerListW - 18) div 2 + ((PlayerListW - 18) div 2 - UiTextWidth('Options', ufRegular)) div 2,
    Y + 3, 'Options', Ink, ufRegular);
end;

end.
