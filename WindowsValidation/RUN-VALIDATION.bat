@echo off
setlocal
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
  echo [FAIL] Python 3 is required.
  pause
  exit /b 1
)
echo.
echo 1. Keep the iPhone app open.
echo 2. In another window run: iproxy.exe 39877 39877
echo 3. This test connects through that USB tunnel.
echo.
python csuv_receiver.py --seconds 30
set RC=%ERRORLEVEL%
echo.
if %RC%==0 (echo [PASS] CSUV stream received.) else (echo [FAIL] receiver exit=%RC%)
pause
exit /b %RC%
