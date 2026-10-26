# Phone Remote Privacy Policy

**Effective date:** October 26, 2026  
**Developer/publisher:** REPLACE WITH THE LEGAL NAME USED IN PLAY CONSOLE  
**Privacy contact:** REPLACE WITH A MONITORED EMAIL ADDRESS BEFORE RELEASE

Phone Remote connects the Android app directly to a Windows computer selected by the user on the user's local network. It does not use a Phone Remote cloud service or require an account.

## Information processed

- **Connection settings:** The Android app stores the selected laptop IP address, port, and TLS certificate fingerprint locally using Android app preferences. The one-time pairing code is used to authenticate a connection and is not saved by the app.
- **Remote-control events:** When the user presses an app key or uses a control, the corresponding key, text, mouse, or media event is transmitted to the selected Windows computer over a TLS-encrypted WebSocket. The app developer does not receive these events. The Windows companion injects them into the active Windows session and does not write their contents to logs or files.
- **Connection metadata:** The Windows companion may display the connecting device's IP address and connection status in its console. This metadata is not sent to the app developer or written to a log file by Phone Remote.
- **Windows server identity:** The Windows companion creates a TLS certificate and private key under the current Windows user's LocalAppData folder. The pairing code is held in memory for that server run and changes when the server restarts.

## Purpose and sharing

Connection settings are used to reconnect to the user's chosen computer. Remote-control events are sent only to that selected computer to perform the actions requested by the user. The app contains no advertising or analytics SDKs and does not intentionally share data with the developer or other parties.

The app sends data off the Android device to the Windows computer by design. Users should review the Google Play Data safety declaration for the final release, which must describe this transmission according to Google Play's definitions and account for all included libraries.

## Security

The Android app connects using TLS 1.2 or newer and verifies the Windows server certificate against a SHA-256 fingerprint provided out of band. The server also requires a per-start pairing code, limits failed pairing attempts, and permits one authenticated remote connection at a time. Users must compare the fingerprint shown on the Windows computer before connecting, keep the pairing code private, use a trusted local network, and allow the server through Windows Firewall only on Private networks.

No security measure can guarantee absolute security. Do not use Phone Remote to transmit passwords or other highly sensitive text.

## Retention and deletion

Connection settings remain in the Android app's private storage until the user clears app storage or uninstalls the app. The Windows TLS key and certificate remain in the current Windows user's LocalAppData folder until manually deleted. Remote-control event contents are not intentionally retained by the app or companion.

## Children's privacy

Phone Remote is a general-purpose remote-control utility and is not designed for children. The publisher must select the appropriate target audience and content rating in Play Console before release.

## Changes and contact

Changes to this policy will be reflected in the policy text in the app and at the public URL linked from Google Play. For privacy questions, contact the monitored email address listed at the top of this policy.
