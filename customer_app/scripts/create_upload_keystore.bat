@echo off
REM Creates the upload keystore (.jks) for Play Store release signing.
REM Run from customer_app folder:  scripts\create_upload_keystore.bat
REM The .jks file is created in customer_app\upload-keystore.jks (back it up safely).

set SCRIPT_DIR=%~dp0
set CUSTOMER_APP=%SCRIPT_DIR%..
set JKS=%CUSTOMER_APP%\upload-keystore.jks

if exist "%JKS%" (
    echo upload-keystore.jks already exists at %JKS%
    echo Delete it first if you want to create a new one.
    pause
    exit /b 1
)

echo Creating upload keystore for Play Store...
echo You will be asked for: keystore password, key password, and your name.
echo Use the SAME passwords in android\key.properties (storePassword and keyPassword).
echo.

set KEYTOOL=keytool
where keytool >nul 2>&1
if %ERRORLEVEL% neq 0 (
  if exist "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" set KEYTOOL="C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
  if exist "C:\Program Files\Java\jre1.8.0_471\bin\keytool.exe" set KEYTOOL="C:\Program Files\Java\jre1.8.0_471\bin\keytool.exe"
  if not defined KEYTOOL set KEYTOOL=keytool
)

%KEYTOOL% -genkey -v -keystore "%JKS%" -keyalg RSA -keysize 2048 -validity 10000 -alias upload

if %ERRORLEVEL% neq 0 (
    echo keytool failed. Make sure Java JDK is installed and on your PATH.
    pause
    exit /b 1
)

echo.
echo Done. Keystore saved to: %JKS%
echo 1) Back up this file and the passwords in a safe place.
echo 2) Edit customer_app\android\key.properties and set storePassword and keyPassword to the passwords you just used.
echo 3) Run: flutter build appbundle
pause
