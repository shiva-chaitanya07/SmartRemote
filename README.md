# Phone Remote

Use an Android phone as a wireless keyboard, touchpad, and media remote for a Windows laptop over the local Wi-Fi network.

## Requirements

- Windows 10/11 laptop with Python 3.11 or newer
- Flutter stable and Android SDK for building/installing the Android app
- Phone and laptop connected to the same Wi-Fi network

## Start the Windows server without shell commands

For a ready-to-run Windows executable, open `windows_server` and double-click `PhoneRemote.exe` (after it has been built once). It opens a small desktop window with **Start server** and **Stop server** buttons, a port field, the laptop's LAN IP, the pairing code, and the certificate fingerprint. Keep the window open while using the phone app. If port 8765 is already occupied, choose another unused port here and enter the same port in the Android app.

To build the executable on Windows, double-click `windows_server\build_launcher.bat`. It downloads the pinned Python dependencies and creates `windows_server\dist\PhoneRemote.exe`. This build script requires Python 3.11+ and an internet connection. The executable is currently unsigned; distribute it only through a trusted channel until you sign it with a code-signing certificate.

You can still start the server from PowerShell in `windows_server` with `python server.py --no-tray` if needed. The server prints the laptop's LAN IP, an 8-digit pairing code, and a SHA-256 certificate fingerprint. The code changes each time the server starts.

By default, the server listens only on detected private LAN IPv4 addresses. If Windows Firewall prompts, allow Phone Remote on **Private networks only** (default inbound TCP `8765`). Never allow it on Public networks. The optional advanced `--host` override can widen the bind scope; avoid `--host 0.0.0.0`.

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

## Tests

- Windows server unit and local TLS/WebSocket integration/security tests: from `windows_server`, run `python -m unittest discover -s tests -v`.
- Android protocol tests: from `android_app`, run `flutter test`.
- Static Flutter checks: from `android_app`, run `flutter analyze`.

These automated checks do not replace a full phone-to-PC test, independent penetration test, or Google Play review. See `windows_server/README.md` for the test coverage and manual device checklist.

## Project layout

```text
SmartController/
├── android_app/       # Flutter Android client
└── windows_server/    # Python WebSocket and pynput server
```

See [windows_server/README.md](windows_server/README.md) and [android_app/README.md](android_app/README.md) for component details.
