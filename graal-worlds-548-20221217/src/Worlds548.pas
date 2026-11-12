{ Worlds548: what the Worlds 548 image shows. A scaffold only.

  Worlds.exe is a Unity 2021.3.8f1 player. Its version resource is the Unity
  version, not a Graal version. The game code is an IL2CPP GameAssembly.dll
  beside it, and the native plugin is Graal3DEngine.dll (FileVersion 6.114).
  No eight-character token is stored in this build, so none is written. }
unit Worlds548;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ScaffoldOnly = True;
  BuildLabel = '548';
  { Unity bundleVersion (Application.version), from data.unity3d. }
  BundleVersion = '548';
  BundleVersionProven = True;
  UnityVersion = '2021.3.8f1';
  { Graal3DEngine FileVersion. Empty: the plugin has no version resource. }
  PluginFileVersion = '6.114';
  { GameAssembly.dll PE time stamp, as a date. }
  BuildDate = '2022-12-17';
  CompanyName = 'toonslab';
  ProductName = 'Graal Worlds';
  MainExe = 'Worlds.exe';
  HasGameAssembly = True;
  LinksTorque = False;
  StoresEightCharToken = False;
  TokenLiteral = '';

implementation

end.
