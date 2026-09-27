@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM ============================================
REM  Qprint unified build script
REM  Usage:
REM    build.bat                     interactive
REM    build.bat debug               all targets, debug/test
REM    build.bat release             all targets, release
REM    build.bat debug frontend      one target
REM    build.bat release customer aab
REM  Targets: all | backend | frontend | admin | customer | shopkeeper
REM  Extra for customer: apk (default) | aab
REM ============================================

set "MODE=%~1"
set "TARGET=%~2"
set "CUSTOMER_FMT=%~3"
if "%CUSTOMER_FMT%"=="" set "CUSTOMER_FMT=apk"

if exist "scripts\google_oauth.config.bat" call "scripts\google_oauth.config.bat"

if "%MODE%"=="" goto interactive
goto resolve_mode

:interactive
echo.
echo ========================================
echo   Qprint Build
echo ========================================
echo.
echo Mode:
echo   1^) debug / test
echo   2^) release
set /p mode_choice="Enter choice [1-2]: "
if "%mode_choice%"=="2" (set "MODE=release") else (set "MODE=debug")

echo.
echo Target:
echo   1^) all
echo   2^) backend
echo   3^) frontend
echo   4^) admin_frontend
echo   5^) customer_app ^(Android^)
echo   6^) shopkeeper_app ^(Windows^)
set /p target_choice="Enter choice [1-6]: "
if "%target_choice%"=="2" set "TARGET=backend"
if "%target_choice%"=="3" set "TARGET=frontend"
if "%target_choice%"=="4" set "TARGET=admin"
if "%target_choice%"=="5" set "TARGET=customer"
if "%target_choice%"=="6" set "TARGET=shopkeeper"
if "%TARGET%"=="" set "TARGET=all"

if /i "%TARGET%"=="customer" (
  echo.
  echo Customer package:
  echo   1^) APK
  echo   2^) Play Store AAB
  set /p fmt_choice="Enter choice [1-2]: "
  if "!fmt_choice!"=="2" set "CUSTOMER_FMT=aab"
)
goto resolve_mode

:resolve_mode
if /i "%MODE%"=="debug" goto mode_ok
if /i "%MODE%"=="test" (
  set "MODE=debug"
  goto mode_ok
)
if /i "%MODE%"=="release" goto mode_ok
echo Unknown mode "%MODE%". Use debug or release.
exit /b 1

:mode_ok
if "%TARGET%"=="" set "TARGET=all"
echo.
echo Mode=%MODE%  Target=%TARGET%
if /i "%TARGET%"=="customer" echo Customer format=%CUSTOMER_FMT%
echo.

if /i "%TARGET%"=="all" goto build_all
if /i "%TARGET%"=="backend" (
  call :build_backend
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="frontend" (
  call :build_frontend
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="admin" (
  call :build_admin
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="admin_frontend" (
  call :build_admin
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="customer" (
  call :build_customer
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="customer_app" (
  call :build_customer
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="shopkeeper" (
  call :build_shopkeeper
  if errorlevel 1 exit /b 1
  goto done
)
if /i "%TARGET%"=="shopkeeper_app" (
  call :build_shopkeeper
  if errorlevel 1 exit /b 1
  goto done
)
echo Unknown target "%TARGET%".
exit /b 1

:build_all
call :build_backend
if errorlevel 1 exit /b 1
call :build_frontend
if errorlevel 1 exit /b 1
call :build_admin
if errorlevel 1 exit /b 1
call :build_customer
if errorlevel 1 exit /b 1
call :build_shopkeeper
if errorlevel 1 exit /b 1
goto done

:build_backend
echo -------- Backend ^(Go^) [%MODE%] --------
pushd backend
if /i "%MODE%"=="release" (
  go build -o qprint-api.exe ./cmd/api
) else (
  go build -o qprint-api-debug.exe ./cmd/api
)
set "err=!errorlevel!"
popd
if not "%err%"=="0" (
  echo Backend build failed.
  exit /b 1
)
echo Backend OK.
exit /b 0

:build_frontend
echo -------- Frontend ^(Next.js^) [%MODE%] --------
pushd frontend
if not exist "node_modules" call npm install
if /i "%MODE%"=="release" (
  call npm run build
) else (
  call npm run lint
  if errorlevel 1 echo Lint warnings ignored for debug/test.
  echo Debug/test: use manage.bat start or npm run dev - no production bundle.
)
set "err=!errorlevel!"
popd
if not "%err%"=="0" (
  if /i "%MODE%"=="release" (
    echo Frontend build failed.
    exit /b 1
  )
)
echo Frontend OK.
exit /b 0

:build_admin
echo -------- Admin frontend ^(Next.js^) [%MODE%] --------
pushd admin_frontend
if not exist "node_modules" call npm install
if /i "%MODE%"=="release" (
  call npm run build
) else (
  call npm run lint
  if errorlevel 1 echo Lint warnings ignored for debug/test.
  echo Debug/test: npm run dev -p 3001
)
set "err=!errorlevel!"
popd
if not "%err%"=="0" (
  if /i "%MODE%"=="release" (
    echo Admin frontend build failed.
    exit /b 1
  )
)
echo Admin frontend OK.
exit /b 0

:build_customer
echo -------- Customer app ^(Flutter Android^) [%MODE%] --------
pushd customer_app
call flutter pub get
if errorlevel 1 (
  popd
  echo flutter pub get failed.
  exit /b 1
)
set "BASE_URL=%PROD_BASE_URL%"
if /i "%MODE%"=="debug" set "BASE_URL=http://10.0.2.2:8080"

if /i "%MODE%"=="release" (
  if /i "%CUSTOMER_FMT%"=="aab" (
    call flutter build appbundle --release --dart-define=BASE_URL=!BASE_URL! --dart-define=GOOGLE_SERVER_CLIENT_ID=!GOOGLE_SERVER_CLIENT_ID!
  ) else (
    call flutter build apk --release --dart-define=BASE_URL=!BASE_URL! --dart-define=GOOGLE_SERVER_CLIENT_ID=!GOOGLE_SERVER_CLIENT_ID!
  )
) else (
  call flutter build apk --debug --dart-define=BASE_URL=!BASE_URL! --dart-define=GOOGLE_SERVER_CLIENT_ID=!GOOGLE_SERVER_CLIENT_ID!
)
set "err=!errorlevel!"
popd
if not "%err%"=="0" (
  echo Customer app build failed.
  exit /b 1
)
echo Customer app OK.
if /i "%MODE%"=="release" (
  if /i "%CUSTOMER_FMT%"=="aab" (
    echo Output: customer_app\build\app\outputs\bundle\release\app-release.aab
  ) else (
    echo Output: customer_app\build\app\outputs\flutter-apk\app-release.apk
  )
) else (
  echo Output: customer_app\build\app\outputs\flutter-apk\app-debug.apk
)
exit /b 0

:build_shopkeeper
echo -------- Shopkeeper app ^(Flutter Windows^) [%MODE%] --------
pushd shopkeeper_app

REM SumatraPDF / LibreOffice: install once via setup.bat bins (not every build)
if not exist "windows\runner\bin\SumatraPDF.exe" (
  echo WARNING: SumatraPDF.exe missing. Run from repo root: setup.bat bins
  echo PDF printing will not work until it is installed.
)
if not exist "windows\runner\bin\LibreOffice\App\libreoffice\program\soffice.exe" (
  echo NOTE: LibreOffice not found. Optional for Word/PPT. Run: setup.bat bins
)

call flutter pub get
if errorlevel 1 (
  popd
  echo flutter pub get failed.
  exit /b 1
)

set "BASE_URL=%PROD_BASE_URL%"
if /i "%MODE%"=="debug" set "BASE_URL=http://localhost:8080"

if /i "%MODE%"=="release" (
  call flutter build windows --release --dart-define=BASE_URL=!BASE_URL! --dart-define=GOOGLE_DESKTOP_CLIENT_ID=!GOOGLE_DESKTOP_CLIENT_ID!
) else (
  call flutter build windows --debug --dart-define=BASE_URL=!BASE_URL! --dart-define=GOOGLE_DESKTOP_CLIENT_ID=!GOOGLE_DESKTOP_CLIENT_ID!
)
set "err=!errorlevel!"
popd
if not "%err%"=="0" (
  echo Shopkeeper app build failed.
  exit /b 1
)
echo Shopkeeper app OK.
if /i "%MODE%"=="release" (
  echo Output: shopkeeper_app\build\windows\x64\runner\Release\
) else (
  echo Output: shopkeeper_app\build\windows\x64\runner\Debug\
)
exit /b 0

:done
echo.
echo ========================================
echo   Build finished ^(%MODE%^)
echo ========================================
endlocal
exit /b 0
