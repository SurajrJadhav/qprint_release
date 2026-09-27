@echo off
REM Project Manager for Windows
REM Usage: manage.bat [start|stop|restart|status]

setlocal enabledelayedexpansion

set BACKEND_DIR=backend
set FRONTEND_DIR=frontend
set ADMIN_FRONTEND_DIR=admin_frontend
set PID_FILE=project.pid

if "%1"=="" goto help
if "%1"=="start" goto start
if "%1"=="stop" goto stop
if "%1"=="restart" goto restart
if "%1"=="status" goto status
if "%1"=="admin" goto admin
if "%1"=="fix-db" goto fixdb
if "%1"=="help" goto help
goto unknown

:start
echo.
echo ========================================
echo   Starting File Sharing Application
echo ========================================
echo.

REM Check if already running
netstat -aon | find ":8080" | find "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Backend is already running on port 8080!
    echo Use 'manage.bat stop' to stop it first
    goto end
)

netstat -aon | find ":3000" | find "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo [WARNING] Frontend is already running on port 3000!
    echo Use 'manage.bat stop' to stop it first
    goto end
)

REM Start backend in new window
echo [INFO] Starting backend server in new window...
cd %BACKEND_DIR%
start "Backend Server" cmd /k "go run cmd/api/main.go"
cd ..
timeout /t 3 /nobreak >nul

echo [SUCCESS] Backend started in separate window
echo [INFO] Backend running on http://localhost:8080

REM Check if node_modules exists
if not exist "%FRONTEND_DIR%\node_modules" (
    echo.
    echo [WARNING] node_modules not found. Installing dependencies...
    echo [INFO] This may take a few minutes...
    cd %FRONTEND_DIR%
    call npm install
    if errorlevel 1 (
        echo [ERROR] Failed to install dependencies
        echo [INFO] Please run 'npm install' manually in the frontend directory
        cd ..
        goto end
    )
    cd ..
    echo [SUCCESS] Dependencies installed
)

REM Start frontend in new window
echo.
echo [INFO] Starting frontend server in new window...
cd %FRONTEND_DIR%
start "Frontend Server" cmd /k "npm run dev"
cd ..
timeout /t 5 /nobreak >nul

echo [SUCCESS] Frontend started in separate window
echo [INFO] Frontend running on http://localhost:3000

REM Check if admin_frontend exists and start it
if exist "%ADMIN_FRONTEND_DIR%" (
    echo.
    echo [INFO] Starting admin frontend...
    cd %ADMIN_FRONTEND_DIR%
    if not exist "node_modules" (
        echo [INFO] Installing admin frontend dependencies...
        call npm install
    )
    start "Admin Frontend Server" cmd /k "npm run dev"
    cd ..
    timeout /t 3 /nobreak >nul
    echo [SUCCESS] Admin frontend started on http://localhost:3001
)

REM Save marker file
echo started > %PID_FILE%

echo.
echo ========================================
echo   Application Started Successfully
echo ========================================
echo.
echo [SUCCESS] Backend: http://localhost:8080 (check Backend Server window)
echo [SUCCESS] Frontend: http://localhost:3000 (check Frontend Server window)
if exist "%ADMIN_FRONTEND_DIR%" (
    echo [SUCCESS] Admin Frontend: http://localhost:3001 (if started)
)
echo.
echo [INFO] Windows opened:
echo   1. Backend Server (Go)
echo   2. Frontend Server (Next.js)
if exist "%ADMIN_FRONTEND_DIR%" (
    echo   3. Admin Frontend Server (Next.js) - if started
)
echo.
echo [INFO] To stop: manage.bat stop
echo [INFO] To check status: manage.bat status
echo.

REM Open browser
echo [INFO] Opening browser...
timeout /t 3 /nobreak >nul
start http://localhost:3000

echo.
echo [INFO] Keep the server windows open!
echo [INFO] Close this window - servers will keep running.
echo.

goto end

:stop
echo.
echo ========================================
echo   Stopping File Sharing Application
echo ========================================
echo.

set STOPPED=0

REM Kill backend (Go processes on port 8080)
echo [INFO] Stopping backend...
for /f "tokens=5" %%a in ('netstat -aon ^| find ":8080" ^| find "LISTENING"') do (
    taskkill /F /PID %%a >nul 2>&1
    if not errorlevel 1 (
        echo [SUCCESS] Backend stopped (PID: %%a)
        set STOPPED=1
    )
)

REM Kill frontend (Node processes on port 3000)
echo [INFO] Stopping frontend...
for /f "tokens=5" %%a in ('netstat -aon ^| find ":3000" ^| find "LISTENING"') do (
    taskkill /F /PID %%a >nul 2>&1
    if not errorlevel 1 (
        echo [SUCCESS] Frontend stopped (PID: %%a)
        set STOPPED=1
    )
)

REM Kill admin frontend (Node processes on port 3001)
echo [INFO] Stopping admin frontend...
for /f "tokens=5" %%a in ('netstat -aon ^| find ":3001" ^| find "LISTENING"') do (
    taskkill /F /PID %%a >nul 2>&1
    if not errorlevel 1 (
        echo [SUCCESS] Admin frontend stopped (PID: %%a)
        set STOPPED=1
    )
)

REM Clean up
if exist %PID_FILE% del %PID_FILE%

if %STOPPED%==1 (
    echo.
    echo ========================================
    echo   Application Stopped
    echo ========================================
    echo.
) else (
    echo.
    echo [WARNING] No running processes found
    echo.
)

goto end

:restart
echo.
echo ========================================
echo   Restarting File Sharing Application
echo ========================================
echo.

call :stop
timeout /t 2 /nobreak >nul
call :start

goto end

:status
echo.
echo ========================================
echo   Application Status
echo ========================================
echo.

REM Check backend
netstat -aon | find ":8080" | find "LISTENING" >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=5" %%a in ('netstat -aon ^| find ":8080" ^| find "LISTENING"') do (
        echo [SUCCESS] Backend is running (PID: %%a)
        echo [INFO]   URL: http://localhost:8080
    )
) else (
    echo [ERROR] Backend is not running
)

echo.

REM Check frontend
netstat -aon | find ":3000" | find "LISTENING" >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=5" %%a in ('netstat -aon ^| find ":3000" ^| find "LISTENING"') do (
        echo [SUCCESS] Frontend is running (PID: %%a)
        echo [INFO]   URL: http://localhost:3000
    )
) else (
    echo [ERROR] Frontend is not running
)

echo.

REM Check admin frontend
netstat -aon | find ":3001" | find "LISTENING" >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=5" %%a in ('netstat -aon ^| find ":3001" ^| find "LISTENING"') do (
        echo [SUCCESS] Admin Frontend is running (PID: %%a)
        echo [INFO]   URL: http://localhost:3001
    )
) else (
    echo [INFO] Admin Frontend is not running (optional)
)

echo.

goto end

:admin
echo.
echo ========================================
echo   Create Admin Account
echo ========================================
echo.

REM Check if arguments provided
if "%~2"=="" (
    echo [ERROR] Username is required
    echo.
    echo Usage:
    echo   manage.bat admin ^<username^> ^<password^> [email] [full_name]
    echo.
    echo Example:
    echo   manage.bat admin admin mypassword123 admin@qprint.com "Admin User"
    echo.
    goto end
)

if "%~3"=="" (
    echo [ERROR] Password is required
    echo.
    echo Usage:
    echo   manage.bat admin ^<username^> ^<password^> [email] [full_name]
    echo.
    echo Example:
    echo   manage.bat admin admin mypassword123 admin@qprint.com "Admin User"
    echo.
    goto end
)

set ADMIN_USERNAME=%~2
set ADMIN_PASSWORD=%~3
set ADMIN_EMAIL=%~4
set ADMIN_NAME=%~5

REM If email not provided, set to empty
if "%ADMIN_EMAIL%"=="" set ADMIN_EMAIL=

REM If name not provided, set to default
if "%ADMIN_NAME%"=="" set ADMIN_NAME=Admin User

echo [INFO] Creating admin account...
echo [INFO] Username: %ADMIN_USERNAME%
if not "%ADMIN_EMAIL%"=="" echo [INFO] Email: %ADMIN_EMAIL%
echo [INFO] Full Name: %ADMIN_NAME%
echo.

cd %BACKEND_DIR%

REM Build command with arguments - use quotes for values with spaces
go run cmd/create_admin/main.go -username "%ADMIN_USERNAME%" -password "%ADMIN_PASSWORD%" -email "%ADMIN_EMAIL%" -name "%ADMIN_NAME%"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to create admin account
    echo [INFO] Make sure the database is running and accessible
    cd ..
    goto end
)

cd ..

echo.
echo [SUCCESS] Admin account created successfully!
echo [INFO] You can now login at http://localhost:3000/login
echo.

goto end

:fixdb
echo.
echo ========================================
echo   Fix Database Schema
echo ========================================
echo.
echo [INFO] Checking and creating missing database tables...
echo.

cd %BACKEND_DIR%
go run cmd/fix_schema/main.go

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to fix database schema
    echo [INFO] Make sure the database is running and accessible
    cd ..
    goto end
)

cd ..

echo.
echo [SUCCESS] Database schema fixed!
echo [INFO] You can now access the admin panel
echo.

goto end

:help
echo.
echo ========================================
echo   File Sharing Application Manager
echo ========================================
echo.
echo Usage:
echo   manage.bat [command]
echo.
echo Commands:
echo   start     - Start backend and frontend servers in separate windows
echo   stop      - Stop all running servers
echo   restart   - Restart all servers
echo   status    - Check status of servers
echo   admin     - Create admin account
echo   fix-db    - Fix database schema (create missing tables)
echo   help      - Show this help message
echo.
echo Admin Account Creation:
echo   manage.bat admin ^<username^> ^<password^> [email] [full_name]
echo.
echo   Example: manage.bat admin admin mypassword123 admin@qprint.com "Admin User"
echo.
echo Database Fix:
echo   manage.bat fix-db
echo.
echo   This creates missing tables (payment_orders, shopkeeper_payouts) if they don't exist
echo.
echo Note:
echo   - Backend and frontend run in separate windows
echo   - Keep those windows open while using the app
echo   - You can close this window after starting
echo.

goto end

:unknown
echo [ERROR] Unknown command: %1
echo.
call :help
goto end

:end
endlocal
