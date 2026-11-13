{ StartScreen131: what 1.31 plugs into the shared start screen
  (common/GStartScreen.pas): its connect step and its character.

  1.31 has no listserver. Its connect dialog holds one server address,
  pre-filled from graalconfig.txt (serveraddr=), and the player edits it.
  Here the server page shows that one address as its only row: Start
  "fetches" it at once, and Connect logs in there. The address comes from
  ReadServerAddr. }
unit StartScreen131;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface, GStartScreen, Adventure;

type
  TListFetch131 = class(TListFetch)
  public
    procedure Start(const Host: string; Port: Integer;
      const Account, Password: string); override;
    procedure Poll; override;
  end;

  { Draws G's player, idle and facing down, for the start screen. }
  TCharacter131 = class
  public
    G: TAdventure;
    procedure Draw(S: TGSurface; X, Y: Integer; const Nick: string);
  end;

{ The server the connect dialog is pre-filled with: graalconfig.txt next
  to the program (serveraddr=HOST or HOST:PORT, serverport=PORT), else
  listserver.txt (host, then port), else DefHost:DefPort. }
procedure ReadServerAddr(const Dir, DefHost: string; DefPort: Integer;
  out Host: string; out Port: Integer);

implementation

uses
  SysUtils, Classes;

procedure TListFetch131.Start(const Host: string; Port: Integer;
  const Account, Password: string);
begin
  SetLength(Servers, 1);
  Servers[0].Name := Host;
  Servers[0].Language := '';
  Servers[0].Description := 'This version has no server list. It connects ' +
    'to the address in graalconfig.txt (serveraddr=, serverport=) next to ' +
    'the program.';
  Servers[0].Url := '';
  Servers[0].Version := '';
  Servers[0].Players := '';
  Servers[0].Host := Host;
  Servers[0].Port := Port;
  Done := True;
  Failed := False;
  Status := Format('Connect to %s:%d', [Host, Port]);
end;

procedure TListFetch131.Poll;
begin
end;

procedure ReadServerAddr(const Dir, DefHost: string; DefPort: Integer;
  out Host: string; out Port: Integer);
var
  L: TStringList;
  I, C: Integer;
  Line, Key, Value: string;
begin
  ReadListServer(Dir, DefHost, DefPort, Host, Port);
  if not FileExists(Dir + 'graalconfig.txt') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(Dir + 'graalconfig.txt');
    for I := 0 to L.Count - 1 do
    begin
      Line := Trim(L[I]);
      C := Pos('=', Line);
      if C = 0 then Continue;
      Key := LowerCase(Trim(Copy(Line, 1, C - 1)));
      Value := Trim(Copy(Line, C + 1, MaxInt));
      if Value = '' then Continue;
      if Key = 'serveraddr' then
      begin
        { the real client writes the address in quotes: serveraddr="host" }
        if (Length(Value) >= 2) and (Value[1] = '"') and (Value[Length(Value)] = '"') then
          Value := Copy(Value, 2, Length(Value) - 2);
        C := Pos(':', Value);
        if C > 0 then
        begin
          Port := StrToIntDef(Copy(Value, C + 1, MaxInt), Port);
          Value := Copy(Value, 1, C - 1);
        end;
        Host := Value;
      end
      else if Key = 'serverport' then
        Port := StrToIntDef(Value, Port);
    end;
  finally
    L.Free;
  end;
end;

procedure TCharacter131.Draw(S: TGSurface; X, Y: Integer; const Nick: string);
begin
  G.Player.Nickname := Nick;
  G.Player.X := 0;
  G.Player.Y := 0;
  G.Player.Dir := 2;
  G.Player.AniName := 'idle';
  G.DrawPlayer(G.Player, -X, -Y);
end;

end.
