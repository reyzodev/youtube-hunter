@echo off
REM ===========================================================================
REM  build.bat  —  One-click build for YouTube Hunter (Windows)
REM  ---------------------------------------------------------------------------
REM  Produces:
REM     dist\YouTubeHunter\YouTubeHunter.exe    the app (opens on any Windows 10/11
REM                                       PC with no Python, no pip, no internet)
REM     Output\YouTubeHunter-Setup.exe       a single installer to send a customer
REM                                       (built automatically when Inno Setup
REM                                       is installed — see step 6)
REM
REM  Just double-click this file (or run it in a terminal). It will:
REM    1. create/refresh an isolated build environment
REM    2. install the exact dependencies
REM    3. verify every build input BEFORE spending minutes on PyInstaller
REM    4. run PyInstaller with the tuned .spec
REM    5. verify the OUTPUT (the Qt/QML modules and ffmpeg are the pieces that
REM       silently go missing and make a build fail only on someone else's PC)
REM    6. build the installer, if Inno Setup is available
REM ===========================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo(
echo === [1/6] Locating Python ===
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")
%PY% --version || (echo Python not found on PATH. Install Python 3.11+ first. & pause & exit /b 1)

echo(
echo === [2/6] Creating build virtual environment (.build-venv) ===
if not exist ".build-venv\Scripts\python.exe" (
    %PY% -m venv .build-venv || (echo venv creation failed & pause & exit /b 1)
)
set "VPY=.build-venv\Scripts\python.exe"

echo(
echo === [3/6] Installing dependencies into the build env ===
"%VPY%" -m pip install --upgrade pip
"%VPY%" -m pip install -r requirements.txt
REM extra deps needed for a fully self-contained build (offline video download)
"%VPY%" -m pip install yt-dlp imageio-ffmpeg pyinstaller
REM force imageio-ffmpeg to fetch its ffmpeg binary NOW so the spec can bundle it
"%VPY%" -c "import imageio_ffmpeg,os; p=imageio_ffmpeg.get_ffmpeg_exe(); print('ffmpeg ready:', os.path.exists(p), p)"

echo(
echo === [4/6] Verifying build inputs ===
if not exist "main_qml.py" (echo MISSING: main_qml.py ^(QML entry point^) & pause & exit /b 1)
if not exist "app\qml\Main.qml" (echo MISSING: app\qml\Main.qml & pause & exit /b 1)
if not exist "app\qml\qmldir" (echo MISSING: app\qml\qmldir ^(the Tokens singleton^) & pause & exit /b 1)
if not exist "fonts" (echo MISSING: fonts\ & pause & exit /b 1)
REM yt-dlp needs ffprobe for the "Audio only" mp3 conversion; imageio-ffmpeg
REM ships only ffmpeg, so the repo carries ffprobe in assets\bin. Without it the
REM audio download dies on the CUSTOMER's machine, not here.
if not exist "assets\bin\ffprobe.exe" (echo MISSING: assets\bin\ffprobe.exe ^(needed for mp3 downloads^) & pause & exit /b 1)
REM The JS runtime (deno) is bundled on purpose: YouTube gates its streams behind
REM a JS challenge, and fetching deno from GitHub at first use fails on a
REM filtered connection — which is exactly the "downloads work here but not on
REM the customer's PC" report. Shipping it makes the runtime a property of the
REM install, not of their network.
if not exist "assets\bin\deno.exe" (echo MISSING: assets\bin\deno.exe ^(JS runtime needed to download from YouTube^) & pause & exit /b 1)
REM The PO Token helper (bgutil-pot) is REQUIRED since v3.41.5 / 1.1.1: every
REM download, resume and YouTube cut-link is gated on it. Shipping it is the
REM difference between "downloads work out of the box" and "the app asks the
REM customer to fetch 45 MB from GitHub" - which fails on a filtered connection.
if not exist "assets\bin\bgutil-pot.exe" (echo MISSING: assets\bin\bgutil-pot.exe ^(PO Token helper, required for downloads^) & pause & exit /b 1)
if not exist "assets\app.ico" echo NOTE: assets\app.ico missing - the exe and installer will use the default icon.
"%VPY%" -c "import PySide6.QtQuick, PySide6.QtQml, PySide6.QtQuickControls2; print('QML runtime OK')" || (echo QML runtime missing in build env & pause & exit /b 1)
"%VPY%" -c "import googleapiclient, openpyxl, youtube_transcript_api, yt_dlp; print('core deps OK')" || (echo Core deps missing in build env & pause & exit /b 1)
"%VPY%" -c "import googleapiclient.discovery_cache as d, os; docs=os.path.join(os.path.dirname(d.__file__),'documents'); assert os.path.isdir(docs) and os.listdir(docs), 'no discovery docs'; print('discovery docs OK:', len(os.listdir(docs)), 'files')" || (echo Google discovery docs missing & pause & exit /b 1)
REM The version the exe will report must match the one the app shows.
"%VPY%" -c "from app.constants import APP_VERSION; print('app version:', APP_VERSION)" || (echo app.constants.APP_VERSION missing & pause & exit /b 1)

echo(
echo === [5/6] Building with PyInstaller ===
"%VPY%" -m PyInstaller --clean --noconfirm YoutubeScrapper.spec || (echo BUILD FAILED & pause & exit /b 1)

echo(
echo === [5b/6] Verifying the build output ===
if not exist "dist\YouTubeHunter\YouTubeHunter.exe" (echo MISSING: dist\YouTubeHunter\YouTubeHunter.exe & pause & exit /b 1)
REM The QML modules are the classic silent gap: PyInstaller collects them from
REM the Qt libraries it finds, and a missing one only shows up as
REM "module QtQuick.Dialogs is not installed" on a machine that has no Qt.
if not exist "dist\YouTubeHunter\_internal\PySide6\qml\QtQuick\Controls" (echo MISSING: QtQuick.Controls QML module & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\PySide6\qml\QtQuick\Dialogs" (echo MISSING: QtQuick.Dialogs QML module & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\PySide6\qml\QtQuick\Effects" (echo MISSING: QtQuick.Effects QML module & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\PySide6\qml\QtMultimedia" (echo MISSING: QtMultimedia QML module & pause & exit /b 1)
REM The QML module above is only half of it: video playback also needs the
REM backend PLUGIN, which PyInstaller does not collect on its own because
REM nothing imports PySide6.QtMultimedia from Python (the spec adds it by
REM hand). Without it Qt logs "No QtMultimedia backends found" and every
REM preview in the Cutter stays black.
if not exist "dist\YouTubeHunter\_internal\PySide6\plugins\multimedia" (echo MISSING: QtMultimedia backend plugin ^(video preview^) & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\app\qml\Main.qml" (echo MISSING: bundled app\qml & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\assets\bin\ffprobe.exe" (echo MISSING: bundled ffprobe & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\assets\bin\deno.exe" (echo MISSING: bundled JS runtime ^(deno^) & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\assets\bin\bgutil-pot.exe" (echo MISSING: bundled PO Token helper ^(bgutil-pot^) & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\fonts" (echo MISSING: bundled fonts & pause & exit /b 1)
if not exist "dist\YouTubeHunter\_internal\googleapiclient\discovery_cache\documents\youtube.v3.json" (echo MISSING: YouTube discovery document & pause & exit /b 1)
REM Chromium must NOT be in the build: the spec filters it out (see the trim step
REM there). If it reappears, the package silently grew by ~195 MB for nothing.
if exist "dist\YouTubeHunter\_internal\PySide6\Qt6WebEngineCore.dll" echo WARNING: Qt6WebEngineCore.dll is back in the build ^(~195 MB of dead weight^)
echo  Output verified:
dir /s "dist\YouTubeHunter" | findstr /C:"File(s)"

echo(
echo === [6/6] Building the installer ===
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles(x86)%\Inno Setup 7\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 7\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 7\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 7\ISCC.exe"
if defined ISCC (
    echo  Using: !ISCC!
    "!ISCC!" installer.iss || (echo INSTALLER BUILD FAILED & pause & exit /b 1)
) else (
    echo  Inno Setup not found - skipping the installer.
    echo  Install it from https://jrsoftware.org/isdl.php and run build.bat again,
    echo  or just zip the whole dist\YouTubeHunter folder and send that instead.
)

echo(
echo ===========================================================================
echo  DONE.
echo(
echo    App:        dist\YouTubeHunter\YouTubeHunter.exe
if exist "Output\YouTubeHunter-Setup.exe" echo    Installer:  Output\YouTubeHunter-Setup.exe
echo(
echo  To ship: send Output\YouTubeHunter-Setup.exe (recommended), or zip the WHOLE
echo  dist\YouTubeHunter folder - never the bare .exe, it needs the _internal
echo  folder beside it.
echo ===========================================================================
pause
