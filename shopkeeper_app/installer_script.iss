; Inno Setup script for Qprint Shop (classic installer)
; Build: run "flutter build windows" then compile this with Inno Setup.
; Gives user: choice of install directory (default Program Files), option to create desktop shortcut.

#define MyAppName "Qprint Shop"
#define MyAppExe "shopkeeper_app.exe"
#define MyAppPublisher "Qprint"

; Flutter Windows build output: set to x64 path or runner path to match your "flutter build windows" output
#define BuildPath "build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion=1.0.0
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; User can change the install directory in the wizard
AllowNoIcons=yes
OutputDir=build\windows\installer
OutputBaseFilename=QprintShop_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: checkedonce

[Files]
; Copy entire Release folder contents (exe, dlls, data, flutter_assets, etc.)
Source: "{#BuildPath}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Pack our existing extra bin into the setup — we only extract it on install (no separate dependency install = no version mismatch).
; Same SumatraPDF/LibreOffice we use in dev; run scripts\setup_sumatra.ps1 (and optionally setup_libreoffice.ps1) before building.
Source: "windows\runner\bin\SumatraPDF.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "windows\runner\bin\LibreOffice\*"; DestDir: "{app}\LibreOffice"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

