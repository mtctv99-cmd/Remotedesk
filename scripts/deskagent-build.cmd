@echo off
rem DeskAgent - build release client (cargo) + flutter windows
set "REPO=%~dp0.."
set "TOOLS=%~dp0..\..\tools"
set "VCPKG_ROOT=%TOOLS%\vcpkg"
set "VCPKG_INSTALLED_ROOT=%TOOLS%\vcpkg\installed"
set "LIBCLANG_PATH=%TOOLS%\llvm-15\bin"
set "PATH=%USERPROFILE%\.cargo\bin;%TOOLS%\flutter\bin;%PATH%"
cd /d "%REPO%"
echo === UI baseline guard ===
git diff --exit-code deskagent-ui-stable-20261124 -- flutter/lib >nul
if errorlevel 1 (
    echo UI has drifted from deskagent-ui-stable-20261124. Restore it or create a new baseline tag before building.
    exit /b 1
)
for /f %%f in ('git ls-files --others --exclude-standard flutter/lib') do (
    echo Untracked UI file: %%f
    exit /b 1
)
echo === cargo build --release ===
rem hwcodec tam thoi loai (C++ build script fail - backlog); software codec VP9/AV1 van day du
cargo build --locked --lib --features flutter --release 2>&1
if errorlevel 1 exit /b 1
echo === flutter build windows --release ===
cd flutter
flutter build windows --release 2>&1
if errorlevel 1 exit /b 1
set "REL_DIR=%REPO%\flutter\build\windows\x64\runner\Release"
if defined DESKAGENT_IDD_SOURCE if defined DESKAGENT_IDD_MANIFEST_SHA256 (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-idd.ps1" -Source "%DESKAGENT_IDD_SOURCE%" -ManifestSha256 "%DESKAGENT_IDD_MANIFEST_SHA256%" -Destination "%REL_DIR%"
    if errorlevel 1 exit /b 1
)

echo BUILD-OK
