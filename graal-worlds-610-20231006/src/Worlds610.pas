{ Worlds610: what the Worlds 610 image shows. A scaffold only.

  Worlds.exe is a Unity 2022.3.9f1 player. Its version resource is the Unity
  version, not a Graal version. The game code is an IL2CPP GameAssembly.dll
  beside it, and the native plugin is Graal3DEngine.dll (FileVersion 6.114).
  No eight-character token is stored in this build, so none is written. }
unit Worlds610;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  ScaffoldOnly = True;
  BuildLabel = '610';
  { Unity bundleVersion (Application.version), from data.unity3d. }
  BundleVersion = '610';
  BundleVersionProven = True;
  UnityVersion = '2022.3.9f1';
  { Graal3DEngine FileVersion. Empty: the plugin has no version resource. }
  PluginFileVersion = '6.114';
  { GameAssembly.dll PE time stamp, as a date. }
  BuildDate = '2023-10-06';
  CompanyName = 'toonslab';
  ProductName = 'GraalOnline Worlds';
  MainExe = 'Worlds.exe';
  HasGameAssembly = True;
  LinksTorque = False;
  StoresEightCharToken = False;
  TokenLiteral = '';

implementation

end.
