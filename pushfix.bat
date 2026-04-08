@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
chcp 65001 >nul 2>&1

set LOGFILE=verify_log_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%.txt
set LOGFILE=%LOGFILE: =0%

echo ================================================
echo   XIAOMI CHINA ROM - BILDIRIM DOGRULAMA ARACI
echo   %date% %time%
echo ================================================
echo. 
echo Rapor: %LOGFILE%
echo.

:: ── ADB BAGLANTI KONTROLU ──────────────────────────────────────────────
echo [1/8] ADB baglantisi kontrol ediliyor...
.\adb start-server >nul 2>&1
.\adb get-state 1>nul 2>nul
if errorlevel 1 (
    echo [HATA] Telefon bagli degil veya USB debugging kapali!
    echo        Telefonu tak, "Allow USB Debugging" iznini onayla, tekrar calistir.
    pause
    exit /b 1
)
echo [OK] Cihaz baglandi.
for /f "delims=" %%D in ('.\adb shell getprop ro.product.model 2^>nul') do set MODEL=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.build.version.release 2^>nul') do set ANDROID=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.miui.ui.version.name 2^>nul') do set MIUI=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.product.region 2^>nul') do set REGION=%%D
echo     Model   : %MODEL%
echo     Android : %ANDROID%
echo     MIUI    : %MIUI%
echo     Region  : %REGION%
echo.
echo [CIHAZ] %MODEL% Android=%ANDROID% MIUI=%MIUI% Region=%REGION% >> %LOGFILE%


:: ── DOZE DURUMU ───────────────────────────────────────────────────────
echo [2/8] Doze (deviceidle) durumu kontrol ediliyor...
.\adb shell dumpsys deviceidle > _doze_raw.txt 2>&1

findstr /i "mEnabled" _doze_raw.txt | findstr /i "false" >nul 2>&1
if not errorlevel 1 (
    echo [OK] Doze KAPALI  - push icin ideal durum
    echo [DOZE] KAPALI >> %LOGFILE%
) else (
    findstr /i "mEnabled" _doze_raw.txt | findstr /i "true" >nul 2>&1
    if not errorlevel 1 (
        echo [UYARI] Doze ACIK - reboot sonrasi fix.bat calistirmadiniz!
        echo [DOZE] ACIK - fix.bat gerekli >> %LOGFILE%
    ) else (
        echo [BILGI] Doze durumu tespit edilemedi - ham cikti asagida:
        findstr /i "mEnabled\|enabled\|disabled\|idle" _doze_raw.txt
    )
)
echo.

:: ── DOZE MODU (light/deep/active) ─────────────────────────────────────
echo [3/8] Doze modu ayrinti...
for /f "delims=" %%L in ('.\adb shell dumpsys deviceidle ^| findstr /i "mState\|mLightState\|mode"') do (
    echo     %%L
    echo [DOZE_DETAIL] %%L >> %LOGFILE%
)
echo.

:: ── WHİTELİST KONTROLU ────────────────────────────────────────────────
echo [4/8] Deviceidle whitelist kontrol ediliyor...

set MISSING=0
set FOUND=0

.\adb shell dumpsys deviceidle whitelist > _wl_raw.txt 2>&1

for %%P in (
    com.google.android.gms
    com.google.android.gms.persistent
    com.google.android.gsf
    com.android.vending
    com.google.firebase.iid
    com.xiaomi.xmsf
    com.xiaomi.channel
    com.miui.powerkeeper
    com.whatsapp
    com.whatsapp.w4b
) do (
    findstr /i "%%P" _wl_raw.txt >nul 2>&1
    if not errorlevel 1 (
        echo   [OK]      %%P
        echo [WL_OK] %%P >> %LOGFILE%
        set /a FOUND+=1
    ) else (
        echo   [EKSIK]   %%P  ^<-- fix.bat tekrar calistir
        echo [WL_EKSIK] %%P >> %LOGFILE%
        set /a MISSING+=1
    )
)
echo.
echo     Whitelist sonucu: %FOUND% tamam, %MISSING% eksik
echo [WL_OZET] FOUND=%FOUND% MISSING=%MISSING% >> %LOGFILE%
echo.

:: ── APPOPS RUN_IN_BACKGROUND ──────────────────────────────────────────
echo [5/8] AppOps arka plan izinleri kontrol ediliyor...

for %%P in (
    com.google.android.gms
    com.google.android.gsf
    com.xiaomi.xmsf
    com.whatsapp
) do (
    for /f "delims=" %%R in ('.\adb shell cmd appops get %%P RUN_ANY_IN_BACKGROUND 2^>nul') do (
        echo   [%%P]  RUN_ANY_IN_BACKGROUND: %%R
        echo [APPOPS] %%P RUN_ANY_IN_BACKGROUND=%%R >> %LOGFILE%
    )
)
echo.

:: ── NETWORK POLICY ────────────────────────────────────────────────────
echo [6/8] Arka plan veri politikasi kontrol ediliyor...

for /f "delims=" %%L in ('.\adb shell cmd netpolicy list global 2^>nul') do (
    echo   %%L
    echo [NETPOLICY] %%L >> %LOGFILE%
)

.\adb shell settings get global restricted_networking_mode > _rnm.txt 2>&1
set /p RNM=<_rnm.txt
if "%RNM%"=="0" (
    echo   [OK] restricted_networking_mode = 0
) else (
    echo   [UYARI] restricted_networking_mode = %RNM%  ^<-- 0 olmali
    echo [NETPOLICY] restricted_networking_mode=%RNM% UYARI >> %LOGFILE%
)
echo.

:: ── GOOGLE SERVİSLERİ DURUMU ──────────────────────────────────────────
echo [7/8] Google servisleri yukleme durumu...

for %%P in (
    com.google.android.gms
    com.google.android.gsf
    com.android.vending
    com.google.android.gms.persistent
) do (
    .\adb shell pm list packages %%P 2>nul | findstr /i "%%P" >nul 2>&1
    if not errorlevel 1 (
        for /f "delims=" %%V in ('.\adb shell dumpsys package %%P ^| findstr /i "versionName" 2^>nul') do (
            echo   [OK]  %%P  %%V
            echo [GMS] %%P %%V >> %LOGFILE%
        )
    ) else (
        echo   [YOK] %%P KURULU DEGIL - Bu ciddi push problemi yaratir!
        echo [GMS_YOK] %%P >> %LOGFILE%
    )
)
echo.

:: ── BACKGROUND PROCESS LIMIT ──────────────────────────────────────────
echo [8/8] Arka plan surec limiti...
for /f "delims=" %%L in ('.\adb shell settings get global background_process_limit 2^>nul') do (
    set BPL=%%L
)
if "%BPL%"=="-1" (
    echo   [OK] background_process_limit = -1  (limitsiz)
) else (
    echo   [UYARI] background_process_limit = %BPL%  ^<-- -1 olmali
    echo [BPL] %BPL% UYARI >> %LOGFILE%
)
echo.

:: ── GENEL SONUC ───────────────────────────────────────────────────────
echo ================================================
echo   SONUC OZETI
echo ================================================
if %MISSING%==0 (
    echo [BASARILI] Tum kritik paketler whitelist'te.
    echo [SONUC] BASARILI >> %LOGFILE%
) else (
    echo [UYARI] %MISSING% paket whitelist'te eksik.
    echo         fix.bat dosyasini tekrar calistirin!
    echo [SONUC] EKSIK=%MISSING% >> %LOGFILE%
)
echo.
echo Tam rapor kaydedildi: %LOGFILE%
echo.

:: Temp dosyalari temizle
del _doze_raw.txt _wl_raw.txt _rnm.txt >nul 2>&1

pause
endlocal