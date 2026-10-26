# Phone Remote Android app

Flutter Android client for the Phone Remote Windows server.

## Requirements

- Flutter stable with Android SDK and platform tools installed
- Android phone or emulator with network access to the same LAN as the Windows PC

## Run

```powershell
flutter pub get
flutter run
```

For a release APK:

```powershell
flutter build apk --release
```

The APK is written to `build\app\outputs\flutter-apk\app-release.apk`.

On the connection screen, enter the IPv4 address printed by the Windows server and port `8765`. The app remembers the last address and reconnects automatically after a Wi-Fi interruption.
