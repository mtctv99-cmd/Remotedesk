@echo off
rem DeskAgent - build release client (cargo) + flutter windows
set "VCPKG_ROOT=C:\Users\chu.mai\Desktop\Remote\tools\vcpkg"
set "VCPKG_INSTALLED_ROOT=C:\Users\chu.mai\Desktop\Remote\DeskAgent\vcpkg_installed"
set "LIBCLANG_PATH=C:\Users\chu.mai\Desktop\Remote\tools\llvm-15\bin"
set "PATH=C:\Users\chu.mai\.cargo\bin;C:\Users\chu.mai\Desktop\Remote\tools\flutter\bin;%PATH%"
cd /d "C:\Users\chu.mai\Desktop\Remote\DeskAgent"
echo === cargo build --release ===
cargo build --release 2>&1
if errorlevel 1 exit /b 1
echo === flutter build windows --release ===
cd flutter
flutter build windows --release 2>&1
if errorlevel 1 exit /b 1
echo BUILD-OK
