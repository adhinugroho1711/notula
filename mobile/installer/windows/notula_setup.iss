; Inno Setup script untuk Notula (Windows)
; Build dulu app-nya di Windows: flutter build windows --release
; Lalu buka file ini di Inno Setup (https://jrsoftware.org/isdl.php) -> Compile.
; Hasil: Output\Notula-Setup-1.0.0.exe

#define AppName "Notula"
#define AppVersion "1.13.2"
#define AppExe "notula.exe"
; Folder hasil build flutter (relatif terhadap lokasi file .iss ini).
#define SrcDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Bank Jateng
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=Output
OutputBaseFilename={#AppName}-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "id"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Buat ikon di Desktop"; GroupDescription: "Tambahan:"

[Files]
; Sertakan SELURUH isi folder Release (exe + dll + folder data)
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Jalankan {#AppName}"; Flags: nowait postinstall skipifsilent
