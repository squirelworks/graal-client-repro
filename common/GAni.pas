{ GAni: GANI0001 sprite-mode animations (TGraalAni and friends in 2.05).

  Grammar: graal_analysis formats/gani.txt. A file is a sprite table
  (SPRITE id sheet x y w h description), header lines, then ANI .. ANIEND.
  Each step holds four direction rows (one with SINGLEDIRECTION); a row is
  comma-separated placements "spriteId x y". WAIT n lengthens the step
  before it; PLAYSOUND name x y cues a sound on it. Keywords are matched
  case-insensitively, as the parser lowercases each line.

  Movie mode (GANI0002) is not read: 2.05 plays player animations from
  sprite-mode files.

  ATTACHSPRITE parent child dx dy (2.1 on) hangs a sprite on another: every
  placement of the parent also places the child dx, dy pixels from it,
  over the parent; ATTACHSPRITE2 places it under the parent [inf: which of
  the two goes under is read from how the 2.2-era player ganis layer, not
  traced]. Attachments are expanded into the steps when the file is read,
  so a step's rows list every sprite to draw, in drawing order. }
unit GAni;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ParamSprite = -1000;

type
  TGraalAniSprite = record
    Id: Integer;
    Sheet: string;   { SPRITES, HEAD, BODY, SWORD, SHIELD, ATTR1..30, PARAMn or a file }
    X, Y, W, H: Integer;
  end;

  TGraalAniPart = record
    { a sprite id, or ParamSprite - n for a PARAMn placement (the sprite
      the caller passes as parameter n, e.g. the carried object) }
    Sprite: Integer;
    X, Y: Integer;
  end;

  TGraalAniPartList = array of TGraalAniPart;

  TGraalAniAttach = record
    Parent, Child, DX, DY: Integer;
    Under: Boolean;     { ATTACHSPRITE2 }
  end;

  TGraalAniStep = record
    Dirs: array[0..3] of TGraalAniPartList;
    Ticks: Integer;     { 1 + WAIT }
    Sound: string;
  end;

  TGraalAni = class
  private
    FSpriteIndex: array of Integer; { sprite id -> index into Sprites, or -1 }
  public
    Name: string;
    Sprites: array of TGraalAniSprite;
    Steps: array of TGraalAniStep;
    Attachments: array of TGraalAniAttach;
    Loop, Continuous, SingleDirection: Boolean;
    SetBackTo, DefaultHead, DefaultBody: string;
    DefaultAttr: array[1..30] of string; { #P1 to #P30 (2.16 added 10 to 30) }
    DefaultParam: array[1..20] of string;
    function LoadFromString(const Text: string): Boolean;
    { Parts with every attached sprite placed (see ATTACHSPRITE above). }
    function ExpandAttachments(const Parts: TGraalAniPartList): TGraalAniPartList;
    function LoadFromFile(const FileName: string): Boolean;
    function FindSprite(Id: Integer; out S: TGraalAniSprite): Boolean;
    function TotalTicks: Integer;
    { Step shown Tick ticks after the start (looping or holding the last). }
    function StepAt(Tick: Integer): Integer;
  end;

implementation

uses
  SysUtils, Classes;

function TGraalAni.LoadFromFile(const FileName: string): Boolean;
var
  L: TStringList;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Name := ChangeFileExt(ExtractFileName(FileName), '');
    Result := LoadFromString(L.Text);
  finally
    L.Free;
  end;
end;

procedure SplitWords(const S: string; Words: TStrings);
var
  I, St: Integer;
begin
  Words.Clear;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] <= ' ') do Inc(I);
    if I > Length(S) then Break;
    St := I;
    while (I <= Length(S)) and (S[I] > ' ') do Inc(I);
    Words.Add(Copy(S, St, I - St));
  end;
end;

function ParseRow(const Row: string; out Parts: TGraalAniPartList): Boolean;
var
  Pieces, W: TStringList;
  I, N, St: Integer;
begin
  Result := False;
  SetLength(Parts, 0);
  Pieces := TStringList.Create;
  W := TStringList.Create;
  try
    { split on commas by hand: StrictDelimiter is newer than Delphi 5 }
    St := 1;
    for I := 1 to Length(Row) + 1 do
      if (I > Length(Row)) or (Row[I] = ',') then
      begin
        Pieces.Add(Copy(Row, St, I - St));
        St := I + 1;
      end;
    for I := 0 to Pieces.Count - 1 do
    begin
      SplitWords(Pieces[I], W);
      if W.Count = 0 then Continue;
      if W.Count < 3 then Exit;
      N := Length(Parts);
      SetLength(Parts, N + 1);
      if (Copy(UpperCase(W[0]), 1, 5) = 'PARAM') and
        (StrToIntDef(Copy(W[0], 6, 2), 0) >= 1) then
        Parts[N].Sprite := ParamSprite - StrToIntDef(Copy(W[0], 6, 2), 0)
      else
        Parts[N].Sprite := StrToIntDef(W[0], -1);
      Parts[N].X := StrToIntDef(W[1], 0);
      Parts[N].Y := StrToIntDef(W[2], 0);
      if Parts[N].Sprite = -1 then Exit;
    end;
    Result := True;
  finally
    W.Free;
    Pieces.Free;
  end;
end;

function TGraalAni.ExpandAttachments(const Parts: TGraalAniPartList): TGraalAniPartList;
var
  Count: Integer;

  procedure Put(Sprite, X, Y, Depth: Integer);
  var
    J: Integer;
  begin
    { under, the sprite, over; a chain stops 4 deep (a loop in the file
      cannot run away) }
    if Depth < 4 then
      for J := 0 to High(Attachments) do
        if Attachments[J].Under and (Attachments[J].Parent = Sprite) then
          Put(Attachments[J].Child, X + Attachments[J].DX, Y + Attachments[J].DY, Depth + 1);
    if Count >= Length(Result) then SetLength(Result, Count * 2 + 4);
    Result[Count].Sprite := Sprite;
    Result[Count].X := X;
    Result[Count].Y := Y;
    Inc(Count);
    if Depth < 4 then
      for J := 0 to High(Attachments) do
        if not Attachments[J].Under and (Attachments[J].Parent = Sprite) then
          Put(Attachments[J].Child, X + Attachments[J].DX, Y + Attachments[J].DY, Depth + 1);
  end;

var
  I: Integer;
begin
  SetLength(Result, 0);
  Count := 0;
  for I := 0 to High(Parts) do
    Put(Parts[I].Sprite, Parts[I].X, Parts[I].Y, 0);
  SetLength(Result, Count);
end;

function TGraalAni.LoadFromString(const Text: string): Boolean;
var
  Lines, W: TStringList;
  I, D, N, K, MaxId: Integer;
  S, Key: string;
  InAni: Boolean;
  Step: TGraalAniStep;
  Parts: TGraalAniPartList;

  procedure FinishStep;
  var
    J: Integer;
  begin
    if D > 0 then
    begin
      N := Length(Steps);
      SetLength(Steps, N + 1);
      Steps[N] := Step;
    end;
    D := 0;
    Step.Ticks := 1;
    Step.Sound := '';
    for J := 0 to 3 do SetLength(Step.Dirs[J], 0);
  end;

begin
  Result := False;
  SetLength(Sprites, 0);
  SetLength(Steps, 0);
  SetLength(Attachments, 0);
  Lines := TStringList.Create;
  W := TStringList.Create;
  try
    Lines.Text := Text;
    InAni := False;
    D := 0;
    Step.Ticks := 1;
    Step.Sound := '';
    for I := 0 to Lines.Count - 1 do
    begin
      S := Lines[I];
      SplitWords(S, W);
      if W.Count = 0 then
      begin
        if InAni and (D > 0) then FinishStep;
        Continue;
      end;
      Key := LowerCase(W[0]);
      if not InAni then
      begin
        if (Key = 'sprite') and (W.Count >= 7) then
        begin
          N := Length(Sprites);
          SetLength(Sprites, N + 1);
          Sprites[N].Id := StrToIntDef(W[1], -1);
          Sprites[N].Sheet := W[2];
          Sprites[N].X := StrToIntDef(W[3], 0);
          Sprites[N].Y := StrToIntDef(W[4], 0);
          Sprites[N].W := StrToIntDef(W[5], 0);
          Sprites[N].H := StrToIntDef(W[6], 0);
        end
        else if ((Key = 'attachsprite') or (Key = 'attachsprite2')) and (W.Count >= 5) then
        begin
          N := Length(Attachments);
          SetLength(Attachments, N + 1);
          Attachments[N].Parent := StrToIntDef(W[1], -1);
          Attachments[N].Child := StrToIntDef(W[2], -1);
          Attachments[N].DX := StrToIntDef(W[3], 0);
          Attachments[N].DY := StrToIntDef(W[4], 0);
          Attachments[N].Under := Key = 'attachsprite2';
        end
        else if Key = 'loop' then Loop := True
        else if Key = 'continuous' then Continuous := True
        else if Key = 'singledirection' then SingleDirection := True
        else if (Key = 'setbackto') and (W.Count > 1) then SetBackTo := W[1]
        else if (Key = 'defaulthead') and (W.Count > 1) then DefaultHead := W[1]
        else if (Key = 'defaultbody') and (W.Count > 1) then DefaultBody := W[1]
        else if (Copy(Key, 1, 12) = 'defaultparam') and (W.Count > 1) then
        begin
          K := StrToIntDef(Copy(Key, 13, 2), 0);
          if (K >= 1) and (K <= 20) then DefaultParam[K] := W[1];
        end
        else if (Copy(Key, 1, 11) = 'defaultattr') and (W.Count > 1) then
        begin
          K := StrToIntDef(Copy(Key, 12, 2), 0);
          if (K >= 1) and (K <= 30) then DefaultAttr[K] := W[1];
        end
        else if Key = 'ani' then InAni := True;
        Continue;
      end;
      if Key = 'aniend' then
      begin
        FinishStep;
        InAni := False;
        Continue;
      end;
      if Key = 'wait' then
      begin
        { a WAIT belongs to the step just closed, or the one being read }
        if D > 0 then Inc(Step.Ticks, StrToIntDef(W[1], 0))
        else if Length(Steps) > 0 then
          Inc(Steps[High(Steps)].Ticks, StrToIntDef(W[1], 0));
        Continue;
      end;
      if Key = 'playsound' then
      begin
        if D > 0 then Step.Sound := W[1]
        else if Length(Steps) > 0 then Steps[High(Steps)].Sound := W[1];
        Continue;
      end;
      if ParseRow(S, Parts) then
      begin
        if D < 4 then Step.Dirs[D] := Parts;
        Inc(D);
        if SingleDirection or (D = 4) then
        begin
          if SingleDirection then
            for K := 1 to 3 do Step.Dirs[K] := Step.Dirs[0];
          FinishStep;
        end;
      end;
    end;
    if D > 0 then FinishStep;
    if Length(Attachments) > 0 then
      for I := 0 to High(Steps) do
        for K := 0 to 3 do
          Steps[I].Dirs[K] := ExpandAttachments(Steps[I].Dirs[K]);
    MaxId := -1;
    for I := 0 to High(Sprites) do
      if Sprites[I].Id > MaxId then MaxId := Sprites[I].Id;
    SetLength(FSpriteIndex, MaxId + 1);
    for I := 0 to High(FSpriteIndex) do FSpriteIndex[I] := -1;
    for I := 0 to High(Sprites) do
      if Sprites[I].Id >= 0 then FSpriteIndex[Sprites[I].Id] := I;
    Result := Length(Steps) > 0;
  finally
    W.Free;
    Lines.Free;
  end;
end;

function TGraalAni.FindSprite(Id: Integer; out S: TGraalAniSprite): Boolean;
begin
  Result := (Id >= 0) and (Id <= High(FSpriteIndex)) and (FSpriteIndex[Id] >= 0);
  if Result then S := Sprites[FSpriteIndex[Id]];
end;

function TGraalAni.TotalTicks: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Steps) do Inc(Result, Steps[I].Ticks);
end;

function TGraalAni.StepAt(Tick: Integer): Integer;
var
  T: Integer;
begin
  Result := 0;
  if Length(Steps) = 0 then Exit;
  T := TotalTicks;
  if Loop and (T > 0) then Tick := Tick mod T
  else if Tick >= T then
  begin
    Result := High(Steps);
    Exit;
  end;
  while (Result < High(Steps)) and (Tick >= Steps[Result].Ticks) do
  begin
    Dec(Tick, Steps[Result].Ticks);
    Inc(Result);
  end;
end;

end.
