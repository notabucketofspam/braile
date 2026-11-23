@echo off
setlocal EnableDelayedExpansion

:: --- Configuration ---
set "RESTIC_VER=0.19.1"
set "CONF_DIR=C:\restic-comp"
set "REPO_FILE=%CONF_DIR%\repo.txt"
set "KEY_FILE=%CONF_DIR%\key.txt"
set "RESTIC_EXE=%CONF_DIR%\restic.exe"

:: --- 1. Check for Administrator privileges ---
net session >nul 2>&1
if errorlevel 1 (
    echo [!] Run this from an elevated Command Prompt ^(Run as Administrator^).
    exit /b 1
)

if "%~2"=="" (
    echo Usage: %~nx0 "REPO_URL" "REPO_KEY" [path1 path2 ...]
    echo Example: %~nx0 "rest:https://borgar:PASS@example.tea-mobile.com/borgar/" "KEY123" C:\inetpub
    exit /b 1
)

set "REPO_URL=%~1"
set "REPO_KEY=%~2"
shift
shift

:: --- 2. Build target path list ---
set "TARGETS="
:parse_paths
if "%~1"=="" goto done_paths
if exist "%~1" set "TARGETS=!TARGETS! "%~1""
shift
goto parse_paths
:done_paths

if not defined TARGETS (
    for %%P in (
        "C:\inetpub"
        "C:\Windows\System32\drivers\etc"
        "C:\Windows\System32\inetsrv\config"
        "C:\Windows\System32\dns"
    ) do (
        if exist %%P set "TARGETS=!TARGETS! %%P"
    )
)

if not defined TARGETS (
    echo [!] None of the target paths exist on this host.
    exit /b 1
)

:: --- 3. Create locked-down directory (Administrators + SYSTEM only) ---
if not exist "%CONF_DIR%" mkdir "%CONF_DIR%"
icacls "%CONF_DIR%" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" >nul

:: --- 4. Install restic.exe (local copy first, otherwise download) ---
if exist "%~dp0restic.exe" (
    echo [*] Using local restic.exe...
    copy /y "%~dp0restic.exe" "%RESTIC_EXE%" >nul
) else if not exist "%RESTIC_EXE%" (
    where curl.exe >nul 2>&1 || (
        echo [!] curl.exe not found. Drop restic.exe next to this script and re-run.
        exit /b 1
    )
    where tar.exe >nul 2>&1 || (
        echo [!] tar.exe not found. Drop restic.exe next to this script and re-run.
        exit /b 1
    )

    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
        set "ARCH=arm64"
    ) else if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        set "ARCH=amd64"
    ) else (
        set "ARCH=386"
    )

    echo [*] Downloading restic v%RESTIC_VER% ^(!ARCH!^)...
    set "TMP_DIR=%TEMP%\restic_setup_%RANDOM%"
    mkdir "!TMP_DIR!"
    set "DL_URL=https://github.com/restic/restic/releases/download/v%RESTIC_VER%/restic_%RESTIC_VER%_windows_!ARCH!.zip"

    curl.exe -fsSL "!DL_URL!" -o "!TMP_DIR!\restic.zip"
    if errorlevel 1 (
        echo [!] Download failed. Check internet/firewall or drop restic.exe locally.
        rd /s /q "!TMP_DIR!"
        exit /b 1
    )

    tar.exe -xf "!TMP_DIR!\restic.zip" -C "!TMP_DIR!"
    move /y "!TMP_DIR!\restic_*.exe" "%RESTIC_EXE%" >nul
    rd /s /q "!TMP_DIR!"
)

:: --- 5. Store credentials on disk ---
> "%REPO_FILE%" echo !REPO_URL!
> "%KEY_FILE%" echo !REPO_KEY!

:: --- 6. Initialize repository (idempotent) ---
echo [*] Checking repository...
"%RESTIC_EXE%" --repository-file "%REPO_FILE%" --password-file "%KEY_FILE%" -o rest.connections=2 cat config >nul 2>&1
if errorlevel 1 (
    echo [*] Initializing new repository...
    "%RESTIC_EXE%" --repository-file "%REPO_FILE%" --password-file "%KEY_FILE%" -o rest.connections=2 init
    if errorlevel 1 exit /b 1
)

:: --- 7. Take Minute-0 Baseline Snapshot (using VSS) ---
echo [*] Taking baseline snapshot of:%TARGETS%
"%RESTIC_EXE%" --repository-file "%REPO_FILE%" --password-file "%KEY_FILE%" -o rest.connections=2 backup --use-fs-snapshot --tag baseline --exclude-caches %TARGETS%
if errorlevel 1 exit /b 1

:: --- 8. Install bkp.cmd into System32 ---
if exist "%~dp0bkp.cmd" (
    copy /y "%~dp0bkp.cmd" "C:\Windows\System32\bkp.cmd" >nul
    echo [+] Installed 'bkp' helper to C:\Windows\System32\bkp.cmd
) else (
    echo [!] Note: bkp.cmd was not found next to this script, so it was not installed.
)

echo [+] Done. Baseline uploaded.
endlocal