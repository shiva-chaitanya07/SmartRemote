# Phone Remote

Use an Android phone as a wireless keyboard, touchpad, and media remote for a Windows laptop over the local Wi-Fi network.

## Requirements

- Windows 10/11 laptop with Python 3.11 or newer
- Flutter stable and Android SDK for building/installing the Android app
- Phone and laptop connected to the same Wi-Fi network

## Start the Windows server

Open PowerShell in `windows_server`:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python server.py --no-tray
```

The server prints the laptop's LAN IP, an 8-digit pairing code, and a SHA-256 certificate fingerprint. Enter the code and fingerprint in the app. The code changes each time the server starts. `run.bat` creates the Python 3.11 environment and starts the server.

If Windows Firewall prompts, allow Python on **Private networks only** (inbound TCP `8765`). Never allow it on Public networks.

## Start the Android app

Open `android_app` in Android Studio, or run:

```powershell
cd android_app
flutter pub get
flutter run
```

Enter the IP, pairing code, and certificate fingerprint printed by the server. The connection uses TLS with certificate pinning and a per-start pairing code. The app persists only the IP, port, and certificate fingerprint; it does not save the pairing code.

## Features

- Dark themed connection screen with connection status and saved laptop address
- QWERTY keyboard with symbol mode, shift, navigation keys, backspace, space, and enter
- Touchpad pointer movement, single-finger left click, two-finger right click, and two-finger scrolling
- Play/pause and volume controls
- WebSocket keepalive and automatic reconnect
- Optional Windows system tray icon

## Security

The phone uses `wss://` with TLS 1.2 or newer and verifies the server's SHA-256 certificate fingerprint. The server requires the 8-digit pairing code, limits failed pairing attempts, allows one controlling phone at a time, limits message size, and releases held input when a client disconnects. Its private TLS key stays in the Windows user's LocalAppData folder. Keep the server on trusted Wi-Fi and allow it through Windows Firewall on Private networks only.

Review [PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md) before a public release. The in-app privacy policy and [policy draft](PRIVACY_POLICY.md) still contain a contact placeholder that must be replaced before publication.

## Project layout

```text
SmartController/
├── android_app/       # Flutter Android client
└── windows_server/    # Python WebSocket and pynput server
```

See [windows_server/README.md](windows_server/README.md) and [android_app/README.md](android_app/README.md) for component details.
