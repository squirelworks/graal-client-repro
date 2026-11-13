{ TestPacks2100: the 2.1 updater's parts (src/Packs2100.pas): setup.ini,
  installed.db, version order, gunzip and tar. The gzip fixtures were made
  with Python's gzip and tarfile modules (mtime 0); they cover a stored, a
  fixed-Huffman and a dynamic-Huffman deflate block. }
program TestPacks2100;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  Classes, SysUtils,
  Packs2100 in '..\src\Packs2100.pas';

const
  { a tar (a folder and two files), dynamic Huffman codes }
  PackTarGz =
    #31#139#8#0#0#0#0#0#2#255#237#212#65#10#2#33#24#197#241#111#221#41#60#65#169#57#206#17#58#135#11#169#197#7#193#140#69#199#207#106 +
    #39#65#16#56#5#243#255#109#158#59#23#79#159#230#107#214#121#39#61#217#42#134#240#204#170#205#55#231#209#239#131#152#65#22#112#153#75#154#234#149 +
    #178#78#135#41#37#221#150#91#249#101#255#46#180#253#15#126#20#99#233#191#187#83#86#61#155#227#227#21#108#4#171#163#175#253#79#61#39#224#211#255 +
    #143#190#217#127#103#189#139#252#255#197#250#55#201#144#255#145#44#18#0#0#0#0#0#0#0#0#0#0#224#27#119#148#52#209#211#0#40#0#0;
  StoredGz =
    #31#139#8#0#0#0#0#0#0#255#1#17#0#238#255#115#116#111#114#101#100#32#98#108#111#99#107#32#116#101#120#116#123#49#216#51#17#0#0#0;
  FixedGz =
    #31#139#8#0#0#0#0#0#2#255#75#76#74#6#0#194#65#36#53#3#0#0#0;
  { fixed Huffman codes, 2 KB of text }
  BigGz =
    #31#139#8#0#0#0#0#0#2#255#11#201#72#85#40#44#205#76#206#86#72#42#202#47#207#83#72#203#175#80#200#42#205#45#40#86#200#47#75#45 +
    #82#40#1#74#231#36#86#85#42#164#228#167#235#41#132#140#42#30#85#60#170#120#84#241#168#226#81#197#195#75#49#3#35#19#51#11#43#27#59#7 +
    #39#23#55#15#47#31#191#128#160#144#176#136#168#152#184#132#164#148#180#140#172#156#188#130#162#146#178#138#170#154#186#134#166#150#182#142#174#158#190#129 +
    #161#145#177#137#169#153#185#133#165#149#181#141#173#157#189#131#163#147#179#139#171#155#187#135#167#151#183#143#175#159#127#64#96#80#112#72#104#88#120#68 +
    #100#84#116#76#108#92#124#66#98#82#114#74#106#90#122#70#102#86#118#78#110#94#126#65#97#81#113#73#105#89#121#69#101#85#117#77#109#93#125#67 +
    #99#83#115#75#107#91#123#71#103#87#119#79#111#95#255#132#137#147#38#79#153#58#109#250#140#153#179#102#207#153#59#111#254#130#133#139#22#47#89#186 +
    #108#249#138#149#171#86#175#89#187#110#253#134#141#155#54#111#217#186#109#251#142#157#187#118#239#217#187#111#255#129#131#135#14#31#57#122#236#248#137#147 +
    #167#78#159#57#123#238#252#133#139#151#46#95#185#122#237#250#141#155#183#110#223#185#123#239#254#131#135#143#30#63#121#250#236#249#139#151#175#94#191#121 +
    #251#238#253#135#143#159#62#127#249#250#237#251#143#159#191#126#255#249#251#239#63#0#233#147#153#255#8#8#0#0;
  BigLen = 2056;
  BigCrc = $FF9993E9;

  { setup.ini as archived from the 2001 site (2001-10-26 capture) }
  SetupIni =
    'setup-timestamp: 981332506'#10 +
    'setup-version: 1.01'#10 +
    ''#10 +
    '@ Executable'#10 +
    'version: 2.0.5-2'#10 +
    'install: graal/mainexe_2052.pack 1'#10 +
    '[prev]'#10 +
    'version: 2.0.5-1'#10 +
    'install: graal/mainexe_2051.pack 1'#10 +
    ''#10 +
    '@ Main'#10 +
    'version: 1.0.0-8'#10 +
    'install: graal/main_1008.pack 1'#10 +
    ''#10 +
    '@ -Developer'#10 +
    'version: 1.0.0-3'#10 +
    'install: graal/dev_1003.pack 1'#10;

var
  Passed, Failed: Integer;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
  begin
    Inc(Passed);
    WriteLn('ok    ', What);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', What);
  end;
end;

procedure TestSetupIni;
var
  S: TSetupIni;
  M: TMirrors;
begin
  S := ParseSetupIni(SetupIni);
  Check((S.SetupVersion = '1.01') and (S.Timestamp = '981332506'), 'setup.ini: header lines');
  Check(Length(S.Components) = 3, 'setup.ini: three components');
  Check((S.Components[0].Name = 'Executable') and (S.Components[0].Version = '2.0.5-2') and
    (S.Components[0].Install = 'graal/mainexe_2052.pack'), 'setup.ini: version and package, size dropped');
  Check((S.Components[0].PrevVersion = '2.0.5-1') and
    (S.Components[0].PrevInstall = 'graal/mainexe_2051.pack'), 'setup.ini: the [prev] lines');
  Check(not S.Components[1].Optional and S.Components[2].Optional and
    (S.Components[2].Name = 'Developer'), 'setup.ini: "@ -Name" is optional');
  M := ParseMirrors('# comment'#10'http://mirror.example/graal2001;mirror.example;Usa;'#10);
  Check((Length(M) = 1) and (M[0].Url = 'http://mirror.example/graal2001') and
    (M[0].Country = 'Usa'), 'mirrors.lst: URL;host;country;');
end;

procedure TestVersions;
begin
  Check(CompareVersions('1.0.0-8', '1.0.0-10') < 0, 'versions: 8 before 10');
  Check(CompareVersions('2.1.0-0', '2.0.5-2') > 0, 'versions: 2.1 after 2.0.5');
  Check(CompareVersions('1.0.0-3', '1.0.0-3') = 0, 'versions: equal');
  Check(PackBaseName('graal/main_1010.pack') = 'main_1010.pack', 'package file name');
end;

procedure TestInstalledDb;
var
  N, P, N2, P2: TStringList;
  T: string;
begin
  N := TStringList.Create;
  P := TStringList.Create;
  N2 := TStringList.Create;
  P2 := TStringList.Create;
  try
    N.Add('Executable'); P.Add('mainexe_2100.pack');
    N.Add('Main'); P.Add('main_1010.pack');
    T := InstalledDbText(N, P);
    Check(T = 'INSTALLED.DB 2'#10'Executable mainexe_2100.pack 0'#10'Main main_1010.pack 0'#10,
      'installed.db: the 2001 layout');
    Check(ParseInstalledDb(T, N2, P2) and (N2.Count = 2) and (P2[1] = 'main_1010.pack'),
      'installed.db: read back');
    Check(not ParseInstalledDb('something else'#10, N2, P2), 'installed.db: another file is refused');
  finally
    N.Free; P.Free; N2.Free; P2.Free;
  end;
end;

procedure TestGunzipTar;
var
  Plain: string;
  E: TTarEntries;
  Bad: string;
begin
  Check(Gunzip(StoredGz, Plain) and (Plain = 'stored block text'), 'gunzip: stored block');
  Check(Gunzip(FixedGz, Plain) and (Plain = 'abc'), 'gunzip: fixed Huffman, short');
  Check(Gunzip(BigGz, Plain) and (Length(Plain) = BigLen) and (Crc32Of(Plain) = BigCrc),
    'gunzip: fixed Huffman with matches');
  Bad := FixedGz;
  Bad[Length(Bad) - 5] := Chr(Ord(Bad[Length(Bad) - 5]) xor 1);
  Check(not Gunzip(Bad, Plain), 'gunzip: a wrong CRC is refused');
  Check(not Gunzip('not gzip at all, not gzip at all', Plain), 'gunzip: not a gzip stream');
  Check(not Gunzip(Copy(PackTarGz, 1, 60), Plain), 'gunzip: a cut stream');
  Check(Gunzip(PackTarGz, Plain), 'gunzip: dynamic Huffman (a .pack)');
  Check(ReadTar(Plain, E) and (Length(E) = 3), 'tar: three entries');
  Check(E[0].IsDir and (E[0].Name = 'levels/'), 'tar: a folder');
  Check((E[1].Name = 'Graal.txt') and (E[1].Data = 'hello graal'#10), 'tar: a file');
  Check((E[2].Name = 'levels/a.txt') and (Length(E[2].Data) = 400), 'tar: a file in a folder');
  Check(not ReadTar(Copy(Plain, 1, 700), E), 'tar: a cut archive');
  Check(SafeArchivePath('levels/a.txt') and not SafeArchivePath('../x') and
    not SafeArchivePath('/etc/x') and not SafeArchivePath('C:/x') and
    not SafeArchivePath('a/../../x'), 'tar: paths stay inside the install folder');
end;

begin
  Passed := 0;
  Failed := 0;
  TestSetupIni;
  TestVersions;
  TestInstalledDb;
  TestGunzipTar;
  WriteLn(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then Halt(1);
end.
