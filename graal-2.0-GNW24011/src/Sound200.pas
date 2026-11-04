{ Sound200: the sounds 2.0 plays by itself each tick.

  GSound does the playing; this unit decides what to play from the game
  state, so Adventure only needs one call a tick (TickSounds) and one-line
  PlaySound calls where an action makes a sound (chest, pickup, landing).

  - Gani PLAYSOUND: when a player's animation enters a step that names a
    sound, it plays at that player. The shipped ganis place their sounds
    at 1.5, 2 (the body's centre); GAni keeps only the name, so that offset
    is used for every gani here.
  - Leaving a level stops the looped effects, as 2.05 does.
  - The listener follows the player. }
unit Sound200;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Adventure;

{ Once per tick, after the game step: gani sounds, then feeds the device. }
procedure TickSounds(G: TAdventure);

implementation

uses
  SysUtils, GAni, GSound;

var
  LastLevel: string = '';

procedure StepSound(G: TAdventure; P: TServerPlayer);
var
  A: TGraalAni;
  St: Integer;
  Key: string;
begin
  A := G.Assets.Ani(P.AniName);
  if (A = nil) or (Length(A.Steps) = 0) then
  begin
    P.SoundKey := '';
    Exit;
  end;
  if P.FixedStep >= 0 then St := P.FixedStep
  else St := A.StepAt(G.Frame - P.AniStart);
  if (St < 0) or (St > High(A.Steps)) then Exit;
  Key := P.AniName + '/' + IntToStr(P.AniStart) + '/' + IntToStr(St);
  if Key = P.SoundKey then Exit;
  P.SoundKey := Key;
  if A.Steps[St].Sound <> '' then
    PlaySoundAt(A.Steps[St].Sound, P.X + 1.5, P.Y + 2);
end;

procedure TickSounds(G: TAdventure);
var
  I: Integer;
begin
  if SoundEnabled then
  begin
    SetListener(G.Player.X, G.Player.Y);
    if LowerCase(G.Level.Name) <> LastLevel then
    begin
      if LastLevel <> '' then StopLoopedSounds;
      LastLevel := LowerCase(G.Level.Name);
    end;
    StepSound(G, G.Player);
    for I := 0 to G.OtherCount - 1 do
      if not G.Others[I].Gone then StepSound(G, G.Others[I]);
  end;
  SoundTick;
end;

end.
