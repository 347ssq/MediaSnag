; MediaSnag Inno Setup Script
; Compile with: ISCC.exe mediasnag.iss

#define MyAppName "MediaSnag"
#define MyAppVersion "1.0.3"
#define MyAppPublisher "MediaSnag"
#define MyAppExeName "MediaSnag.exe"

[Setup]
AppId={{A7D3E5F1-8B2C-4D6A-9F1E-3C5A7B9D2E4F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\MediaSnag
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer\windows\output
OutputBaseFilename=MediaSnag-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64bitMode=x64compatible
AppMutex=MediaSnagAppMutex

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Bundled Python runtime
Source: "staging\python\*"; DestDir: "{app}\python"; Flags: ignoreversion recursesubdirs createallsubdirs
; Binary tools
Source: "staging\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
; App source code
Source: "staging\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
; Userscript
Source: "staging\userscript.user.js"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\launcher.pyw"""; WorkingDir: "{app}"; IconFilename: "{app}\python\python.exe"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\launcher.pyw"""; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\python\python.exe"

[Run]
; Install Tampermonkey from Edge Add-ons store (works in China)
Filename: "https://microsoftedge.microsoft.com/addons/detail/tampermonkey/iikmkjmpaadaobahmlepeloendndfphd"; Description: "安装 Tampermonkey"; Flags: shellexec skipifsilent unchecked
; Create first-run marker so app opens userscript install page
Filename: "cmd.exe"; Parameters: "/c echo 1 > ""{app}\first_run"""; Flags: runhidden skipifsilent
; Launch MediaSnag
Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\launcher.pyw"""; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
; ytdl:// URL scheme → video download
Root: HKCU; Subkey: "Software\Classes\ytdl"; ValueType: "string"; ValueData: "URL:MediaSnag Video"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdl"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdl\DefaultIcon"; ValueType: "string"; ValueData: "{app}\python\python.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdl\shell\open\command"; ValueType: "string"; ValueData: """{app}\python\pythonw.exe"" ""{app}\app\launcher.pyw"" ""%1"""; Flags: uninsdeletekey

; ytdla:// URL scheme → audio download
Root: HKCU; Subkey: "Software\Classes\ytdla"; ValueType: "string"; ValueData: "URL:MediaSnag Audio"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdla"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdla\DefaultIcon"; ValueType: "string"; ValueData: "{app}\python\python.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ytdla\shell\open\command"; ValueType: "string"; ValueData: """{app}\python\pythonw.exe"" ""{app}\app\launcher.pyw"" ""%1"""; Flags: uninsdeletekey

[Code]
// Terminate a running MediaSnag server before files are replaced, so an
// upgrade never leaves a stale instance serving old code on the port.
// The app writes its PID to {app}\data\mediasnag.pid at startup.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PidFile: String;
  Pid: AnsiString;
begin
  if CurStep = ssInstall then
  begin
    PidFile := ExpandConstant('{localappdata}\MediaSnag\data\mediasnag.pid');
    if LoadStringFromFile(PidFile, Pid) then
    begin
      if Length(Pid) > 0 then
        Exec('taskkill.exe', '/f /pid ' + Pid, '', SW_HIDE,
          ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
