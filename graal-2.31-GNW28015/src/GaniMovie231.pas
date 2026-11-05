{ GaniMovie231: the movie-mode ganis (GANI0002) that 2.3 added, enough for
  what the offline tutorial shows with them.

  A movie gani has the sprite table of a GANI0001 file, FRAMES n (the
  length of the loop), and a MOVIE .. MOVIEEND block of actors. Each
  ACTOR SPRITE or ACTOR TEXT .. ACTOREND lists key frames
  "FRAME n name=value,name=value,...": the first key frame sets every
  property, later ones only those that change. A property keeps its value
  until the next key frame changes it (the tutorial's bobbing arrow and
  "Touch to get information" text move between 0, 20 and 40).

  Read here: dx, dy, sprite #, visible, text, color, fontsize, centered,
  shaded, bold. Not read: layer (the actors are drawn over the character),
  zoom, italic, underline, strikeout, wordwrap, font (the install's
  TEMPSITC.TTF is the only font the rebuild has). }
unit GaniMovie231;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  Classes;

type
  TMovieSprite = record
    Id: Integer;
    Sheet: string;
    X, Y, W, H: Integer;
  end;

  TMovieKey = record
    Frame: Integer;
    Props: TStringList;
  end;

  TMovieActor = class
  public
    IsText: Boolean;
    Keys: array of TMovieKey;
    destructor Destroy; override;
    { every property as it stands at Frame }
    procedure At(Frame: Integer; Into: TStrings);
  end;

  TGaniMovie = class
  public
    Sprites: array of TMovieSprite;
    Actors: array of TMovieActor;
    Frames: Integer;
    destructor Destroy; override;
    function LoadFromString(const Text: string): Boolean;
    function LoadFromFile(const FileName: string): Boolean;
    function FindSprite(Id: Integer; out S: TMovieSprite): Boolean;
  end;

{ a FRAME line's "a=1,b=two" list into name=value lines; a text= value
  runs to the next ",name=" so it may hold commas only when no property
  follows }
procedure SplitProps(const S: string; Into: TStrings);

{ FFE080 (RRGGBB) as an ARGB colour; Default when it does not read }
function MovieColor(const S: string; Default: Cardinal): Cardinal;

implementation

uses
  SysUtils;

procedure SplitProps(const S: string; Into: TStrings);
var
  I, Start: Integer;
  Part: string;
begin
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ',') then
    begin
      Part := Trim(Copy(S, Start, I - Start));
      if Pos('=', Part) > 1 then
        Into.Values[LowerCase(Trim(Copy(Part, 1, Pos('=', Part) - 1)))] :=
          Copy(Part, Pos('=', Part) + 1, MaxInt);
      Start := I + 1;
    end;
end;

function MovieColor(const S: string; Default: Cardinal): Cardinal;
var
  V: Integer;
begin
  Result := Default;
  if (Length(Trim(S)) = 6) and TryStrToInt('$' + Trim(S), V) then
    Result := $FF000000 or Cardinal(V);
end;

destructor TMovieActor.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Keys) do Keys[I].Props.Free;
  inherited Destroy;
end;

procedure TMovieActor.At(Frame: Integer; Into: TStrings);
var
  I, J: Integer;
begin
  Into.Clear;
  for I := 0 to High(Keys) do
  begin
    if Keys[I].Frame > Frame then Break;
    for J := 0 to Keys[I].Props.Count - 1 do
      Into.Values[Keys[I].Props.Names[J]] := Keys[I].Props.ValueFromIndex[J];
  end;
end;

destructor TGaniMovie.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Actors) do Actors[I].Free;
  inherited Destroy;
end;

function TGaniMovie.FindSprite(Id: Integer; out S: TMovieSprite): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Sprites) do
    if Sprites[I].Id = Id then
    begin
      S := Sprites[I];
      Result := True;
      Exit;
    end;
end;

function TGaniMovie.LoadFromString(const Text: string): Boolean;
var
  L, W: TStringList;
  I, N: Integer;
  S, Low: string;
  Actor: TMovieActor;
  InMovie: Boolean;
begin
  Result := False;
  Frames := 1;
  InMovie := False;
  Actor := nil;
  L := TStringList.Create;
  W := TStringList.Create;
  try
    L.Text := Text;
    if (L.Count = 0) or (Trim(L[0]) <> 'GANI0002') then Exit;
    for I := 1 to L.Count - 1 do
    begin
      S := Trim(L[I]);
      Low := LowerCase(S);
      if S = '' then Continue;
      if not InMovie then
      begin
        W.Clear;
        ExtractStrings([' ', #9], [], PChar(S), W);
        if (Low = 'movie') then InMovie := True
        else if (W.Count >= 6) and (LowerCase(W[0]) = 'sprite') then
        begin
          N := Length(Sprites);
          SetLength(Sprites, N + 1);
          Sprites[N].Id := StrToIntDef(W[1], -1);
          Sprites[N].Sheet := W[2];
          Sprites[N].X := StrToIntDef(W[3], 0);
          Sprites[N].Y := StrToIntDef(W[4], 0);
          Sprites[N].W := StrToIntDef(W[5], 0);
          if W.Count > 6 then Sprites[N].H := StrToIntDef(W[6], 0);
        end
        else if (W.Count >= 2) and (LowerCase(W[0]) = 'frames') then
          Frames := StrToIntDef(W[1], 1);
        Continue;
      end;
      if Low = 'movieend' then
      begin
        InMovie := False;
        Continue;
      end;
      if Copy(Low, 1, 6) = 'actor ' then
      begin
        Actor := TMovieActor.Create;
        Actor.IsText := Pos(' text', Low) > 0;
        N := Length(Actors);
        SetLength(Actors, N + 1);
        Actors[N] := Actor;
      end
      else if Low = 'actorend' then
        Actor := nil
      else if (Actor <> nil) and (Copy(Low, 1, 6) = 'frame ') then
      begin
        S := Trim(Copy(S, 7, MaxInt));
        N := Length(Actor.Keys);
        SetLength(Actor.Keys, N + 1);
        Actor.Keys[N].Frame := StrToIntDef(Copy(S, 1, Pos(' ', S + ' ') - 1), 0);
        Actor.Keys[N].Props := TStringList.Create;
        SplitProps(Trim(Copy(S, Pos(' ', S + ' ') + 1, MaxInt)), Actor.Keys[N].Props);
      end;
    end;
    if Frames < 1 then Frames := 1;
    Result := True;
  finally
    W.Free;
    L.Free;
  end;
end;

function TGaniMovie.LoadFromFile(const FileName: string): Boolean;
var
  L: TStringList;
begin
  Result := False;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FileName);
    except
      Exit;
    end;
    Result := LoadFromString(L.Text);
  finally
    L.Free;
  end;
end;

end.
