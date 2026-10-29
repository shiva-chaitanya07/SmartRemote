# Phone Remote Android app

Flutter Android client for Phone Remote. It supports the established Wi-Fi server mode and an experimental native Bluetooth HID mode that may let compatible phones control Windows without the companion server.

## Requirements

- Flutter stable with Android SDK and platform tools installed
- Android phone or emulator. Wi-Fi mode requires the same LAN as the Windows PC; Bluetooth HID mode requires compatible Bluetooth HID support on the phone and Bluetooth on the laptop.

## Run

```powershell
flutter pub get
flutter run
```

For a local debug APK, use `flutter build apk --debug`. A Play Store submission must be a signed Android App Bundle (AAB).

## Prepare a Play Store release

The app targets API 36 and uses application ID `com.shivachaitanya07.phoneremote`. Confirm that this ID is available and keep it unchanged after publishing.

Create an upload keystore in this `android` folder, keep it backed up securely, and never commit it:

```powershell
cd android
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
Copy-Item key.properties.example key.properties
```

Edit `android\key.properties` with the passwords and alias you chose. Confirm `storeFile=upload-keystore.jks` points to the keystore in the `android` folder. The keystore and `key.properties` are excluded from Git.

Then build the Play bundle:

```powershell
cd ..
flutter pub get
flutter build appbundle --release
```

The signed bundle is written to `build\app\outputs\bundle\release\app-release.aab`.

See the repository's `PLAY_STORE_CHECKLIST.md` and `PRIVACY_POLICY.md` before submission. Replace the privacy contact placeholder and host the policy at a public HTTPS URL.
