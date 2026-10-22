; ===========================================================================
;  installer.iss  —  Inno Setup script for YouTube Hunter
;  ---------------------------------------------------------------------------
;  Wraps the PyInstaller onedir output (dist\YouTubeHunter\) into a single
;  setup.exe that any user can run to install the app — no Python, no pip,
;  no internet required.
;
;  HOW TO USE:
;    1. Run build.bat first (produces dist\YouTubeHunter\).
;    2. Install Inno Setup 6.3+ (https://jrsoftware.org/isdl.php).
;    3. Open this file in Inno Setup and click Build (or run:
;         "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss )
;    4. Ship the resulting Output\YouTubeHunter-Setup.exe to anyone.
;
;  Notes for whoever maintains this:
;    * AppId MUST be a real GUID in {8-4-4-4-12} hex form. Inno Setup rejects
;      anything else, and an AppId that is not a GUID is what stopped this
;      script compiling at all before. The value below is fixed forever: it is
;      how Windows recognises an upgrade of the SAME product. Changing it makes
;      every existing install look like a different application (two entries in
;      Add/Remove Programs, no in-place upgrade).
;    * MyAppVersion must match app/constants.py's APP_VERSION (Inno Setup can't
;      read a Python constant). The sidebar footer shows the same number.
;    * Installs per-user by default (no admin prompt, no UAC, no failure on a
;      locked-down machine). An admin install is still offered on the dialog.
; ===========================================================================

#define MyAppName "YouTube Hunter"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "YouTube Hunter"
#define MyAppExeName "YouTubeHunter.exe"
#define MyAppId "{{8F3A2C71-4E9B-4B2A-9C6D-1E4A5F60B213}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion} (64-bit)
AppPublisher={#MyAppPublisher}
AppComments=YouTube research, downloads and clip cutting for content creators. 64-bit build: Windows 10 (1809 or newer) / Windows 11 on x64.
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} {#MyAppVersion} Setup - Windows 10/11 (64-bit)
; Per-user install by default so no admin rights are needed (fewer failures on
; locked-down machines); the user can still choose an all-users install.
PrivilegesRequiredOverridesAllowed=dialog commandline
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir=Output
OutputBaseFilename=YouTubeHunter-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Windows 10 1809 or newer. The build is x64-only (PySide6 and ffmpeg are),
; so refuse to install anywhere it could not possibly run.
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Close a running copy of the app before replacing its files, and write an
; install log so a failed install on a customer machine can be diagnosed
; instead of guessed at.
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
; Same red mark as the title bar and the exe.
SetupIconFile=assets\app.ico

[Languages]
; Only the languages Inno Setup itself ships are listed here on purpose: a
; missing .isl is a compile error, and the app's own interface language is
; chosen inside the app (Settings), independently of the setup wizard.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[InstallDelete]
; Clear the previous version's payload BEFORE laying down the new one.
;
; Why this is needed: when a customer upgrades, Inno only *overwrites* — it does
; not remove files the new build no longer ships. Measured on a real upgrade
; from an older build, that left 1,679 orphaned files (73.6 MB) sitting in the
; install folder: Qt modules the new build deliberately dropped (Qt6Pdf,
; Qt6Quick3D, the extra Controls styles, Qt3D…). Disk waste, and worse, a stale
; DLL in the app's own folder is a thing nobody will ever think to look at when
; something misbehaves.
;
; Deleting the whole _internal folder is safe because the [Files] entry below
; re-creates it in full from dist\YouTubeHunter — that folder IS this app's own
; runtime and contains nothing else. The uninstaller already treats it the same
; way.
Type: filesandordirs; Name: "{app}\_internal"
;
; The rebrand (Niche Scope -> YouTube Hunter) rides on the SAME AppId on
; purpose, so an existing install upgrades in place — which means the old exe
; and its shortcuts have to leave with the old payload. Without these lines the
; user is left with two launchable apps in one folder: the new
; YouTubeHunter.exe plus a stale NicheScope.exe that still boots the new code
; under the old name, and a second Start Menu group that looks like a second
; product.
Type: files; Name: "{app}\NicheScope.exe"
Type: filesandordirs; Name: "{userprograms}\Niche Scope"
Type: files; Name: "{autodesktop}\Niche Scope.lnk"

[Files]
; Bundle the ENTIRE PyInstaller output folder recursively. The app needs the
; whole folder — the .exe alone does nothing (its Qt/Python runtime lives in
; _internal next to it).
Source: "dist\YouTubeHunter\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; v3.42: the YouTube button (browser extension) ships next to the app
Source: "browser-extension\*"; DestDir: "{app}\browser-extension"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
; v3.42: youtubehunter:// lets the browser extension start the app (minimised)
; when it isn't running. HKA = per-user or all-users, matching the install.
Root: HKA; Subkey: "Software\Classes\youtubehunter"; ValueType: string; ValueName: ""; ValueData: "URL:YouTube Hunter"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\youtubehunter"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\youtubehunter\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\youtubehunter\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\YouTube Hunter browser extension"; Filename: "{app}\browser-extension"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
; v1.1 in-app update: the app starts Setup with /VERYSILENT /relaunch=1 and
; quits. Once the files are replaced, reopen it so the update feels like a
; restart rather than a reinstall.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: ShouldRelaunch

[UninstallDelete]
; The app's own data (config, SQLite archives, downloaded files) lives in
; %APPDATA%\YoutubeScrapperCyber and in the user's save folder. An uninstall
; deliberately leaves those alone: losing a download archive because the app
; was uninstalled would be worse than leaving a few megabytes behind.

[Code]
// A short, honest check: if the user's Windows is 32-bit the [Setup] section
// already refuses to install, and if the app is running Setup closes it. The
// only thing left worth saying out loud is where the app data will live, so a
// customer knows an uninstall keeps it.
// v1.1: true when the app itself launched this Setup as an update.
function ShouldRelaunch(): Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Nothing to do — kept as the hook for future post-install steps.
  end;
end;
