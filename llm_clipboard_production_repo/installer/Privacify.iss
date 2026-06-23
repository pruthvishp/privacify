#define MyAppName "Privacify"
#define MyAppVersion "1.0.0"

[Setup]
AppId={{F7B5E161-CC1D-4B92-A8E2-0F98A62C7FE0}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Privacify
DefaultDirName={autopf}\Privacify
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PrivacifySetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Uninstallable=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\*"; DestDir: "{tmp}\PrivacifyPayload"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "dist\*;.git\*"

[Run]
Filename: "{cmd}"; Parameters: "/C powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""{tmp}\PrivacifyPayload\install.ps1"" -StartAtLogin"; StatusMsg: "Installing Privacify, required local runtimes, and the selected model..."; Flags: waituntilterminated

[Code]
function InitializeSetup(): Boolean;
begin
  Result := MsgBox(
    'Privacify runs locally on this Windows PC. Setup installs AutoHotkey, Ollama, a local model, and the manager UI. Downloads may take several minutes.',
    mbInformation, MB_OKCANCEL) = IDOK;
end;
