@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
chcp 65001 >nul 2>&1

echo ================================================
echo   XIAOMI PUSH FIX TOOL v1.1
echo   GitHub: https://github.com/kaantellioglu/xiaomi17-pro-max-push-fix-tool
echo ================================================
echo.

:: ── MENU ──────────────────────────────────────────
echo Select mode:
echo [1] VERIFY (diagnostics only)
echo [2] FIX (apply fixes)
echo [3] COMBO (fix + verify)
echo.
set /p MODE=Enter choice (1/2/3): 

if "%MODE%"=="1" goto VERIFY
if "%MODE%"=="2" goto FIX
if "%MODE%"=="3" goto COMBO

echo Invalid selection!
pause
exit /b

:: ── COMMON: ADB CHECK ─────────────────────────────
:ADB_CHECK
echo.
echo Checking ADB connection...
.\adb start-server >nul 2>&1
.\adb get-state 1>nul 2>nul
if errorlevel 1 (
    echo ERROR: Device not connected or USB debugging disabled!
    pause
    exit /b
)
echo Device connected.
exit /b

:: ── FIX MODE ──────────────────────────────────────
:FIX
call :ADB_CHECK

echo.
echo Applying PUSH FIX...

echo [1/4] Disabling Doze...
.\adb shell dumpsys deviceidle disable

echo [2/4] Removing background limits...
.\adb shell settings put global background_process_limit -1

echo [3/4] Whitelisting core services...
for %%P in (
    com.google.android.gms
    com.google.android.gsf
    com.android.vending
    com.google.android.gms.persistent
    com.google.firebase.iid
    com.xiaomi.xmsf
    com.xiaomi.channel
    com.miui.powerkeeper
) do (
    echo   -> %%P
    .\adb shell dumpsys deviceidle whitelist +%%P
    .\adb shell cmd appops set %%P RUN_ANY_IN_BACKGROUND allow >nul 2>&1
    .\adb shell cmd appops set %%P RUN_IN_BACKGROUND allow >nul 2>&1
)

echo [4/4] Auto scan: all installed apps...
for /f "tokens=2 delims=:" %%P in ('.\adb shell pm list packages -3 --user 0') do (
    .\adb shell dumpsys deviceidle whitelist +%%P >nul 2>&1
    .\adb shell cmd appops set %%P RUN_ANY_IN_BACKGROUND allow >nul 2>&1
)

echo.
echo FIX COMPLETED.
goto END

:: ── VERIFY MODE ───────────────────────────────────
:VERIFY
call :ADB_CHECK

set LOGFILE=verify_log_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%.txt
set LOGFILE=%LOGFILE: =0%

echo.
echo Running verification...
echo Log: %LOGFILE%

:: Doze check
echo Checking Doze...
.\adb shell dumpsys deviceidle > _doze.txt 2>&1
findstr /i "mEnabled" _doze.txt | findstr /i "false" >nul && (
    echo [OK] Doze disabled
) || (
    echo [WARNING] Doze enabled
)

:: Whitelist check
echo Checking whitelist...
set MISSING=0
for %%P in (
    com.google.android.gms
    com.whatsapp
    com.xiaomi.xmsf
) do (
    findstr /i "%%P" _doze.txt >nul || (
        echo   Missing: %%P
        set /a MISSING+=1
    )
)

:: Background limit
for /f "delims=" %%L in ('.\adb shell settings get global background_process_limit') do set BPL=%%L
if "%BPL%"=="-1" (
    echo [OK] Background unlimited
) else (
    echo [WARNING] Background limit active
)

echo.
if %MISSING%==0 (
    echo STATUS: OK
) else (
    echo STATUS: ISSUES FOUND
)

del _doze.txt >nul 2>&1
goto END

:: ── COMBO MODE ────────────────────────────────────
:COMBO
call :FIX
echo.
echo Running verification after fix...
goto VERIFY

:: ── END ───────────────────────────────────────────
:END
echo.
echo Done.
pause
endlocal
