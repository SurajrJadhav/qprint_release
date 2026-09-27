@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM ============================================
REM  Qprint one-time setup after git clone
REM  - Idempotent: skips steps already done
REM  - Does NOT re-download Sumatra/LibreOffice if valid
REM  - Fails cleanly on partial downloads (no half-install)
REM
REM  Usage:
REM    setup.bat              full setup (deps + optional Windows bins)
REM    setup.bat deps         language deps only (go/npm/flutter)
REM    setup.bat bins         Sumatra + LibreOffice only (Windows)
REM    setup.bat env          copy .env examples only (never overwrite)
REM ============================================

set "SCOPE=%~1"
if "%SCOPE%"=="" set "SCOPE=full"

echo.
echo ========================================
echo   Qprint initial setup ^(%SCOPE%^)
echo ========================================
echo.

if /i "%SCOPE%"=="env" goto do_env
if /i "%SCOPE%"=="deps" goto do_deps
if /i "%SCOPE%"=="bins" goto do_bins
if /i "%SCOPE%"=="full" goto do_full
echo Unknown option "%SCOPE%". Use: full ^| deps ^| bins ^| env
exit /b 1

:do_full
call :do_env
if errorlevel 1 exit /b 1
call :check_prereqs
call :do_deps
if errorlevel 1 exit /b 1
call :do_bins
goto done

:do_env
echo -------- Env files (create if missing) --------
call :copy_if_missing "backend\.env.example" "backend\.env"
call :copy_if_missing "frontend\.env.example" "frontend\.env.local"
call :copy_if_missing "admin_frontend\.env.example" "admin_frontend\.env.local"
call :copy_if_missing "customer_app\android\app\google-services.json.example" "customer_app\android\app\google-services.json"
call :copy_if_missing "customer_app\android\local.properties.example" "customer_app\android\local.properties"
call :copy_if_missing "customer_app\android\key.properties.example" "customer_app\android\key.properties"
echo Edit backend\.env and frontend\.env.local with real values before running.
echo Replace google-services.json with your Firebase file before Android Google Sign-In.
if /i "%SCOPE%"=="env" goto done
exit /b 0

:do_deps
echo -------- Dependencies (skip if already present) --------

echo [backend] go mod download...
pushd backend
go mod download
if errorlevel 1 ( popd & echo ERROR: go mod download failed & exit /b 1 )
popd
echo [backend] OK

echo [frontend] npm install...
pushd frontend
if exist "node_modules\" (
  echo node_modules already present - skipping npm install
) else (
  call npm install
  if errorlevel 1 ( popd & echo ERROR: frontend npm install failed & exit /b 1 )
)
popd
echo [frontend] OK

echo [admin_frontend] npm install...
pushd admin_frontend
if exist "node_modules\" (
  echo node_modules already present - skipping npm install
) else (
  call npm install
  if errorlevel 1 ( popd & echo ERROR: admin npm install failed & exit /b 1 )
)
popd
echo [admin_frontend] OK

where flutter >nul 2>&1
if errorlevel 1 (
  echo [flutter] Flutter not in PATH - skip pub get. Install Flutter for customer/shopkeeper apps.
) else (
  echo [customer_app] flutter pub get...
  pushd customer_app
  call flutter pub get
  if errorlevel 1 ( popd & echo ERROR: customer flutter pub get failed & exit /b 1 )
  popd
  echo [customer_app] OK

  echo [shopkeeper_app] flutter pub get...
  pushd shopkeeper_app
  call flutter pub get
  if errorlevel 1 ( popd & echo ERROR: shopkeeper flutter pub get failed & exit /b 1 )
  popd
  echo [shopkeeper_app] OK
)

if /i "%SCOPE%"=="deps" goto done
exit /b 0

:do_bins
echo -------- Shopkeeper Windows binaries (one-time downloads) --------
if /i not "%OS%"=="Windows_NT" (
  echo Not Windows - skipping Sumatra/LibreOffice.
  if /i "%SCOPE%"=="bins" goto done
  exit /b 0
)

set "SUMATRA=shopkeeper_app\windows\runner\bin\SumatraPDF.exe"
set "SOFFICE=shopkeeper_app\windows\runner\bin\LibreOffice\App\libreoffice\program\soffice.exe"

if exist "%SUMATRA%" (
  echo SumatraPDF already present - skip
) else (
  echo Installing SumatraPDF ^(download only if missing^)...
  powershell -NoProfile -ExecutionPolicy Bypass -File "shopkeeper_app\scripts\setup_sumatra.ps1"
  if errorlevel 1 (
    echo WARNING: SumatraPDF setup failed. PDF print needs it later. Re-run: setup.bat bins
  )
)

if exist "%SOFFICE%" (
  echo LibreOffice already present - skip
) else (
  echo Installing LibreOffice ^(large, one-time, optional for Word/PPT^)...
  echo Press Ctrl+C to skip, or wait...
  powershell -NoProfile -ExecutionPolicy Bypass -File "shopkeeper_app\scripts\setup_libreoffice.ps1"
  if errorlevel 1 (
    echo WARNING: LibreOffice setup failed/skipped. PDF+images still work without it.
  )
)

if /i "%SCOPE%"=="bins" goto done
exit /b 0

:check_prereqs
echo -------- Prerequisites --------
where go >nul 2>&1 && (echo [OK] go) || echo [MISSING] go
where node >nul 2>&1 && (echo [OK] node) || echo [MISSING] node
where npm >nul 2>&1 && (echo [OK] npm) || echo [MISSING] npm
where flutter >nul 2>&1 && (echo [OK] flutter) || echo [MISSING] flutter ^(needed for apps^)
where psql >nul 2>&1 && (echo [OK] psql) || echo [OPTIONAL] psql
echo.
exit /b 0

:copy_if_missing
set "SRC=%~1"
set "DST=%~2"
if exist "%DST%" (
  echo keep  %DST%
  exit /b 0
)
if not exist "%SRC%" (
  echo skip  %DST% ^(no example %SRC%^)
  exit /b 0
)
copy /Y "%SRC%" "%DST%" >nul
echo created %DST%  ^(from example - edit me^)
exit /b 0

:done
echo.
echo ========================================
echo   Setup finished
echo ========================================
echo Next:
echo   1. Edit backend\.env and frontend\.env.local
echo   2. Create Postgres DB ^(see README^)
echo   3. manage.bat start     ^(dev servers^)
echo   4. build.bat debug^|release
echo.
echo Re-run is safe: existing deps/bins are not re-downloaded.
endlocal
exit /b 0
