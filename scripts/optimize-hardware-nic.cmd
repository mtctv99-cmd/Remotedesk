@echo off
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [DeskAgent] Requesting Administrator privileges for Hardware Driver Tuning...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

echo [DeskAgent] Running Hardware NIC & Driver Optimization...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimize-hardware-nic.ps1" %*

echo.
pause
