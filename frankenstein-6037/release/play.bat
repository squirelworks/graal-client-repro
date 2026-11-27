@echo off
rem Frankenstein 6.037 launcher for Windows. Asks for the server, the account
rem and the password, then starts the client. Extra arguments go to the
rem client as is, e.g.  play.bat --renderer software
rem Set FRANK_ASSETS to your Graal folder to use its files (default: data\).
setlocal
cd /d "%~dp0"
if "%FRANK_SERVER%"=="" set /p FRANK_SERVER=Server (host:port): 
if "%FRANK_ACCOUNT%"=="" set /p FRANK_ACCOUNT=Account: 
if "%FRANK_PASSWORD%"=="" set /p FRANK_PASSWORD=Password (shown as you type): 
if "%FRANK_ASSETS%"=="" set FRANK_ASSETS=%~dp0data
if not exist "%FRANK_ASSETS%" mkdir "%FRANK_ASSETS%"
set NAMEARG=
if not "%FRANK_SERVER_NAME%"=="" set NAMEARG=--server-name "%FRANK_SERVER_NAME%"
frankenstein-6037.exe --connect %FRANK_SERVER% --account %FRANK_ACCOUNT% --password-env FRANK_PASSWORD --assets "%FRANK_ASSETS%" --download-files %NAMEARG% %*
if errorlevel 1 pause
