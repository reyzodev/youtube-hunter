# Rebrand: Niche Scope -> YouTube Hunter

- New logo (transparent PNG): assets/logo.png (1024px), assets/logo_256.png, assets/logo_glow.png (with neon glow, for marketing)
- assets/app.ico regenerated from the new logo (16..256 px) -> exe, installer, taskbar
- assets/favicon.png (48px) -> HTML deep reports
- app/qml/components/brand_logo.png -> title-bar mark (TitleBar.qml now shows the logo image)
- main_qml.py: setWindowIcon + app name + Windows AppUserModelID
- Name "YouTube Hunter" in UI, window title, Persian strings (یوتیوب هانتر), spec, build.bat, installer.iss, version_info.txt
- exe / installer: YouTubeHunter.exe, YouTubeHunter-Setup.exe
- Kept on purpose: QML module name `NicheScope` (internal import), runtime folder name `NicheScope`, config folder, installer AppId GUID (so it upgrades existing installs)
