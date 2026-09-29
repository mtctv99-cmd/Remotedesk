@echo off
rem DeskAgent check: rust client + manager + flutter analyze
setlocal
set "VCPKG_ROOT=C:\Users\chu.mai\Desktop\Remote\tools\vcpkg"
set "VCPKG_INSTALLED_ROOT=C:\Users\chu.mai\Desktop\Remote\rustdesk\vcpkg_installed"
set "LIBCLANG_PATH=C:\Users\chu.mai\Desktop\Remote\tools\llvm-15\bin"
set "PATH=C:\Users\chu.mai\.cargo\bin;C:\Users\chu.mai\Desktop\Remote\tools\flutter\bin;%PATH%"
cd /d "C:\Users\chu.mai\Desktop\Remote\rustdesk"
cargo check
if errorlevel 1 exit /b 1
cargo check --manifest-path manager\Cargo.toml
if errorlevel 1 exit /b 1
cd /d "C:\Users\chu.mai\Desktop\Remote\rustdesk\flutter"
flutter pub get
if errorlevel 1 exit /b 1
flutter analyze --no-pub
if errorlevel 1 exit /b 1
exit /b 0
