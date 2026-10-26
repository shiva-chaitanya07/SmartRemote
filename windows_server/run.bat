@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Creating virtual environment...
    py -3.11 -m venv .venv
    if errorlevel 1 (
        echo Failed to create venv. Is Python installed?
        pause
        exit /b 1
    )
)

call ".venv\Scripts\activate.bat"
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)"
if errorlevel 1 (
    echo Phone Remote requires Python 3.11 or newer. Install it and recreate .venv.
    pause
    exit /b 1
)
python -m pip install --upgrade pip
pip install -r requirements.txt
echo.
python server.py %*
echo.
pause
