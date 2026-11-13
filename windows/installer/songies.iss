; Songies Windows installer (Inno Setup 6).
;
; Build after `flutter build windows --release`:
;   iscc /DAppVersion=X.Y.Z /DSourceDir=<repo>\build\windows\x64\runner\Release windows\installer\songies.iss
; Output: songies-X.Y.Z-windows-setup.exe in /DOutputDir (default <repo>\build\installer).
;
; The in-app updater runs the setup file as
;   songies-X.Y.Z-windows-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
; while Songies is still running. CloseApplications closes it via the Restart
; Manager, and the [Run] entry starts the new version afterwards.

#ifndef AppVersion
  #error Pass the version: iscc /DAppVersion=X.Y.Z /DSourceDir=<release bundle> songies.iss
#endif
#ifndef SourceDir
  #error Pass the release bundle: iscc /DAppVersion=X.Y.Z /DSourceDir=<release bundle> songies.iss
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

#define AppName "Songies"
#define AppExeName "songies.exe"

[Setup]
; Fixed forever: Windows uses it to recognise an installed Songies as the
; same app, so updates install over it. Never change it.
AppId={{A8CFE96C-AB63-466F-A74C-803CD73FB97F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
AppPublisher=Denis Martonak
AppPublisherURL=https://github.com/DenisMartonak/Songie
AppSupportURL=https://github.com/DenisMartonak/Songie/issues
AppUpdatesURL=https://github.com/DenisMartonak/Songie/releases
; Per user: no UAC prompt, so the silent update never needs elevation.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Songies
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=songies-{#AppVersion}-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Close a running Songies (also when silent) but don't let the Restart
; Manager restart it: the [Run] entry below starts the new version.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Old Flutter assets must not linger after an update. User data lives in
; %APPDATA%\Songies, never under {app}.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; songies://room/<code> and songies://playlist/<code> links start Songies (or
; reach the running one).
Root: HKCU; Subkey: "Software\Classes\songies"; ValueType: string; ValueName: ""; ValueData: "URL:Songies"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\songies"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\songies\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Run]
; No skipifsilent and no unchecked: a postinstall entry whose checkbox is
; checked by default is also processed under /SILENT and /VERYSILENT, which
; is how the in-app update relaunches Songies.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall

[Code]
// Uninstalling keeps the library, downloads, settings and sign-in in
// %APPDATA%\Songies unless the user says Yes (the default button is No).
// The sign-in itself (flutter_secure_storage's encrypted files and the
// WebView2 profile) lives in the application-support folder
// %APPDATA%\com.songies\Songies (Runner.rc CompanyName\ProductName), so Yes
// deletes that too. A silent uninstall never deletes either.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
  SupportDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{userappdata}\Songies');
    SupportDir := ExpandConstant('{userappdata}\com.songies\Songies');
    if (DirExists(DataDir) or DirExists(SupportDir)) and (not UninstallSilent) then
    begin
      if MsgBox('Also delete your Songies library, downloads, settings and sign-in?' + #13#10#13#10 +
                'They are kept in ' + DataDir + '.' + #13#10#13#10 +
                'Choose No to keep them for a later reinstall.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DelTree(DataDir, True, True, True);
        DelTree(SupportDir, True, True, True);
      end;
    end;
  end;
end;
