# Phone Remote

Use an Android phone as a wireless keyboard, touchpad, and media remote for a Windows laptop over the local Wi-Fi network.

## Requirements

- Windows 10/11 laptop with Python 3.8 or newer
- Flutter stable and Android SDK for building/installing the Android app
- Phone and laptop connected to the same Wi-Fi network

## Start the Windows server

Open PowerShell in `windows_server`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python server.py
```

The server prints the laptop's LAN IP and listens on port `8765`. `run.bat` creates/activates the virtual environment, installs dependencies, and starts the server. On Windows it also starts a tray icon; right-click the icon to quit. Pass `--no-tray` to keep the console process.

If Windows Firewall prompts, allow Python on Private networks. If no prompt appears and the phone cannot connect, allow inbound TCP port 8765 in Windows Defender Firewall.

## Start the Android app

Open `android_app` in Android Studio, or run:

```powershell
cd android_app
flutter pub get
flutter run
```

Enter the IP printed by the server and port `8765`. The app persists the address and automatically retries after the connection drops. To build a release APK, run `flutter build apk --release`; output is in `android_app\build\app\outputs\flutter-apk\app-release.apk`.

## Features

- Dark themed connection screen with connection status and saved laptop address
- QWERTY keyboard with symbol mode, shift, navigation keys, backspace, space, and enter
- Touchpad pointer movement, single-finger left click, two-finger right click, and two-finger scrolling
- Play/pause and volume controls
- WebSocket keepalive and automatic reconnect
- Optional Windows system tray icon

## Network and security

Both devices must be on a LAN that permits device-to-device connections. The server listens on all network interfaces and has no authentication or encryption. Run it only on a trusted local network. The Android app uses `ws://` for local connectivity.

## Project layout

```text
SmartController/
├── android_app/       # Flutter Android client
└── windows_server/    # Python WebSocket and pynput server
```

See [windows_server/README.md](windows_server/README.md) and [android_app/README.md](android_app/README.md) for component details.
