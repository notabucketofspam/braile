@echo off
setlocal EnableDelayedExpansion

set "CONF_DIR=C:\restic-comp"
set "RESTIC="%CONF_DIR%\restic.exe" --repository-file "%CONF_DIR%\repo.txt" --password-file "%CONF_DIR%\key.txt" -o rest.connections=2"

if "%~1"=="" goto usage
if /i "%~1"=="snap" goto do_snap
if /i "%~1"=="list" goto do_list
if /i "%~1"=="diff" goto do_diff
if /i "%~1"=="restore" goto do_restore
goto usage

:do_snap
shift
set "PATHS="
:snap_loop
if "%~1"=="" goto snap_run
set "PATHS=!PATHS! "%~1""
shift
goto snap_loop
:snap_run
if not defined PATHS (
    echo Usage: bkp snap ^<path1^> [path2 ...]
    exit /b 1
)
%RESTIC% backup --use-fs-snapshot --exclude-caches %PATHS%
exit /b %errorlevel%

:do_list
%RESTIC% snapshots
exit /b %errorlevel%

:do_diff
set "BASE_ID="
set "LATEST_ID="
for /f "tokens=1" %%A in ('%RESTIC% snapshots --tag baseline --compact ^| findstr /r "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] "') do (
    if not defined BASE_ID set "BASE_ID=%%A"
)
for /f "tokens=1" %%A in ('%RESTIC% snapshots --compact ^| findstr /r "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] "') do (
    set "LATEST_ID=%%A"
)
if not defined BASE_ID (
    echo [!] Could not find a 'baseline' snapshot.
    exit /b 1
)
echo [*] Diffing baseline ^(!BASE_ID!^) -^> latest ^(!LATEST_ID!^)
%RESTIC% diff !BASE_ID! !LATEST_ID!
exit /b %errorlevel%

:do_restore
if "%~2"=="" (
    echo Usage: bkp restore ^<path-to-restore^>
    echo Example: bkp restore C:\Windows\System32\drivers\etc\hosts
    exit /b 1
)
set "BASE_ID="
for /f "tokens=1" %%A in ('%RESTIC% snapshots --tag baseline --compact ^| findstr /r "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] "') do (
    if not defined BASE_ID set "BASE_ID=%%A"
)
if not defined BASE_ID (
    echo [!] Could not find a 'baseline' snapshot.
    exit /b 1
)
if not exist "C:\restore" mkdir "C:\restore"
%RESTIC% restore !BASE_ID! --target "C:\restore" --include "%~2"
echo [*] Restored into C:\restore
exit /b %errorlevel%

:usage
echo Usage: bkp {snap ^<paths...^> ^| list ^| diff ^| restore ^<path^>}
exit /b 1