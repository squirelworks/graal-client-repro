{ Builtin3D: this build's own stand-in art, used when the player's Graal3D
  files are not there.

  Nothing here comes from Graal3D. The level is a plain field with a few
  blocks, a step, a ramp and a high platform, so walking, stepping, the
  wall rule and jumping can all be tried without the original files. The
  player is eight boxes in the slots of the eight original meshes (body,
  head, two arms, two hands, two feet). Everything is written out as .x
  text and read back through XFile3D, the same path the real files take. }
unit Builtin3D;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ The stand-in level as a .x file. }
function BuiltinLevel: string;
{ The stand-in for one of the eight model files (body.x, head.x,
  armleft.x, ...), or '' for any other name. }
function BuiltinModel(const Name: string): string;

implementation

uses
  SysUtils, Math3D;

type
  TBoxList = record
    Verts, Faces, Mats: string;
    NV, NF: Integer;
    FaceMat: string;
    MatCount: Integer;
  end;

function F(D: Double): string;
begin
  { Str is the same in every locale }
  Str(D:0:3, Result);
end;

procedure AddMat(var L: TBoxList; R, G, B, ER, EG, EB: Double);
begin
  L.Mats := L.Mats + ' Material {' + #10 + '  ' + F(R) + ';' + F(G) + ';' + F(B) +
    ';1.0;;' + #10 + '  1.0;' + #10 + '  0.0;0.0;0.0;;' + #10 + '  ' + F(ER) + ';' +
    F(EG) + ';' + F(EB) + ';;' + #10 + ' }' + #10;
  Inc(L.MatCount);
end;

{ One quad, wound so that its normal (XFile3D's rule) points along Out. }
procedure AddQuad(var L: TBoxList; const A, B, C, D, Out: TVec3; Mat: Integer);
var
  N: TVec3;
  P: array[0..3] of TVec3;
  I: Integer;
begin
  N := VCross(VSub(B, A), VSub(C, A));
  if VDot(N, Out) >= 0 then
  begin
    P[0] := A; P[1] := B; P[2] := C; P[3] := D;
  end
  else
  begin
    P[0] := D; P[1] := C; P[2] := B; P[3] := A;
  end;
  for I := 0 to 3 do
    L.Verts := L.Verts + ' ' + F(P[I].X) + ';' + F(P[I].Y) + ';' + F(P[I].Z) + ';,' + #10;
  L.Faces := L.Faces + ' 4;' + IntToStr(L.NV) + ',' + IntToStr(L.NV + 1) + ',' +
    IntToStr(L.NV + 2) + ',' + IntToStr(L.NV + 3) + ';,' + #10;
  if L.FaceMat <> '' then L.FaceMat := L.FaceMat + ',';
  L.FaceMat := L.FaceMat + IntToStr(Mat);
  Inc(L.NV, 4);
  Inc(L.NF);
end;

procedure AddBox(var L: TBoxList; X0, Y0, Z0, X1, Y1, Z1: Double; Mat, TopMat: Integer);
begin
  { top, bottom, then the four sides }
  AddQuad(L, V3(X0, Y1, Z0), V3(X0, Y1, Z1), V3(X1, Y1, Z1), V3(X1, Y1, Z0), V3(0, 1, 0), TopMat);
  AddQuad(L, V3(X0, Y0, Z0), V3(X1, Y0, Z0), V3(X1, Y0, Z1), V3(X0, Y0, Z1), V3(0, -1, 0), Mat);
  AddQuad(L, V3(X0, Y0, Z0), V3(X0, Y1, Z0), V3(X1, Y1, Z0), V3(X1, Y0, Z0), V3(0, 0, -1), Mat);
  AddQuad(L, V3(X0, Y0, Z1), V3(X1, Y0, Z1), V3(X1, Y1, Z1), V3(X0, Y1, Z1), V3(0, 0, 1), Mat);
  AddQuad(L, V3(X0, Y0, Z0), V3(X0, Y0, Z1), V3(X0, Y1, Z1), V3(X0, Y1, Z0), V3(-1, 0, 0), Mat);
  AddQuad(L, V3(X1, Y0, Z0), V3(X1, Y1, Z0), V3(X1, Y1, Z1), V3(X1, Y0, Z1), V3(1, 0, 0), Mat);
end;

function Finish(const L: TBoxList): string;
var
  UV: string;
  I: Integer;
begin
  UV := '';
  for I := 0 to L.NV - 1 do UV := UV + ' 0.0;0.0;,' + #10;
  Result := 'xof 0302txt 0064' + #10 +
    '// graal-delphi stand-in art, not from Graal3D' + #10 +
    'Mesh builtin {' + #10 + ' ' + IntToStr(L.NV) + ';' + #10 + L.Verts +
    ' ' + IntToStr(L.NF) + ';' + #10 + L.Faces +
    ' MeshMaterialList {' + #10 + ' ' + IntToStr(L.MatCount) + ';' + #10 + ' ' +
    IntToStr(L.NF) + ';' + #10 + ' ' + L.FaceMat + ';;' + #10 + L.Mats + ' }' + #10 +
    ' MeshTextureCoords {' + #10 + ' ' + IntToStr(L.NV) + ';' + #10 + UV + ' }' + #10 +
    '}' + #10;
end;

procedure Init(out L: TBoxList);
begin
  L.Verts := '';
  L.Faces := '';
  L.Mats := '';
  L.FaceMat := '';
  L.NV := 0;
  L.NF := 0;
  L.MatCount := 0;
end;

function BuiltinLevel: string;
var
  L: TBoxList;
begin
  Init(L);
  AddMat(L, 0.30, 0.55, 0.25, 0, 0, 0);  { 0 field }
  AddMat(L, 0.62, 0.60, 0.55, 0, 0, 0);  { 1 stone }
  AddMat(L, 0.75, 0.72, 0.62, 0.05, 0.05, 0.05); { 2 tops }
  AddMat(L, 0.45, 0.42, 0.40, 0, 0, 0);  { 3 dark stone }
  AddMat(L, 0.85, 0.65, 0.30, 0, 0, 0);  { 4 path }
  { the field: one quad, top only }
  AddQuad(L, V3(-4000, 0, -4000), V3(-4000, 0, 4000), V3(4000, 0, 4000),
    V3(4000, 0, -4000), V3(0, 1, 0), 0);
  { a path, a hair above the field }
  AddQuad(L, V3(-40, 0.5, -1200), V3(-40, 0.5, 1200), V3(40, 0.5, 1200),
    V3(40, 0.5, -1200), V3(0, 1, 0), 4);
  { a low step (20, can be walked onto) and a high one (60, a wall) }
  AddBox(L, 150, 0, 150, 350, 20, 350, 1, 2);
  AddBox(L, -350, 0, 150, -150, 60, 350, 3, 2);
  { stairs of 25 up to a platform at 100 }
  AddBox(L, 150, 0, -400, 350, 25, -350, 1, 2);
  AddBox(L, 150, 0, -450, 350, 50, -400, 1, 2);
  AddBox(L, 150, 0, -500, 350, 75, -450, 1, 2);
  AddBox(L, 150, 0, -750, 350, 100, -500, 3, 2);
  { a ring of pillars }
  AddBox(L, -600, 0, -600, -560, 200, -560, 3, 2);
  AddBox(L, -600, 0, 560, -560, 200, 600, 3, 2);
  AddBox(L, 560, 0, 560, 600, 200, 600, 3, 2);
  AddBox(L, 560, 0, -600, 600, 200, -560, 3, 2);
  { a long wall at the far end }
  AddBox(L, -800, 0, 1400, 800, 120, 1440, 1, 2);
  Result := Finish(L);
end;

function BuiltinModel(const Name: string): string;
var
  L: TBoxList;
  N: string;
begin
  Result := '';
  N := LowerCase(Name);
  Init(L);
  { the colourable parts are white so the colour props show as sent }
  if N = 'body.x' then
  begin
    AddMat(L, 0.25, 0.35, 0.80, 0, 0, 0);
    AddBox(L, -11, 4, -7, 11, 29, 4, 0, 0);
  end
  else if N = 'head.x' then
  begin
    AddMat(L, 0.95, 0.80, 0.62, 0, 0, 0);
    AddBox(L, -9, -3, -9, 9, 17, 9, 0, 0);
  end
  else if N = 'armleft.x' then
  begin
    AddMat(L, 1, 1, 1, 0, 0, 0);
    AddBox(L, 6, -13, -4, 11, 0, 4, 0, 0);
  end
  else if N = 'armright.x' then
  begin
    AddMat(L, 1, 1, 1, 0, 0, 0);
    AddBox(L, -11, -13, -4, -6, 0, 4, 0, 0);
  end
  else if N = 'handleft.x' then
  begin
    AddMat(L, 1, 1, 1, 0, 0, 0);
    AddBox(L, 6, -18, -3, 11, -13, 3, 0, 0);
  end
  else if N = 'handright.x' then
  begin
    AddMat(L, 1, 1, 1, 0, 0, 0);
    AddBox(L, -11, -18, -3, -6, -13, 3, 0, 0);
  end
  else if (N = 'footleft.x') or (N = 'footright.x') then
  begin
    AddMat(L, 1, 1, 1, 0, 0, 0);
    AddBox(L, -4, -8, -10, 4, -3, 6, 0, 0);
  end
  else
    Exit;
  Result := Finish(L);
end;

end.
