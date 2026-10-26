@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if errorlevel 1 (
    echo Python Launcher was not found. Install Python 3.11 or newer first.
    pause
    exit /b 1
)

if not exist ".build-venv\Scripts\python.exe" (
    py -3.11 -m venv .build-venv
    if errorlevel 1 goto :failed
)

call ".build-venv\Scripts\activate.bat"
python -m pip install --upgrade pip
if errorlevel 1 goto :failed
pip install -r requirements.txt -r requirements-build.txt
if errorlevel 1 goto :failed

python -m PyInstaller --noconfirm --clean --onefile --windowed ^
    --name PhoneRemote ^
    --collect-submodules pynput ^
    --collect-all cryptography ^
    --collect-all websockets ^
    launcher.py
if errorlevel 1 goto :failed

echo.
echo Build complete: %CD%\dist\PhoneRemote.exe
echo Keep this executable in a trusted folder. It is not code-signed.
pause
exit /b 0

:failed
echo.
echo Build failed. Check the error above, then run this file again.
pause
exit /b 1
