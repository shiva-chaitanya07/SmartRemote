# Phone Remote security and test report

**Assessment date:** October 26, 2026  
**Scope:** Repository code, local Windows packaging, Android protocol helpers, and the Python server over loopback.  
**Result:** Automated checks passed after one static finding was fixed. This report is not a certification or an independent professional penetration-test report.

## Changes made

- Added a Windows desktop launcher with start/stop controls, a selectable port, and copyable LAN address, pairing code, and certificate fingerprint.
- Changed the server's default bind behavior from all interfaces to detected RFC1918 private IPv4 interfaces. The advanced `--host` option remains; `--host 0.0.0.0` intentionally listens on every interface and is not recommended.
- Added protocol parsing, certificate pin comparison, and LAN address validation tests in Flutter.
- Added Python unit and local TLS/WebSocket integration tests using fake keyboard and mouse controllers, so tests never inject input into the real desktop.

## Checks performed

- Python `unittest`: 15 tests passed. Coverage includes authentication allow/deny, lockout, single-controller policy, pending-connection cap, endpoint and payload validation, frame size limits, TLS identity/fingerprint persistence, bounded input values, and release of held keys/buttons after disconnect.
- Flutter `flutter test`: 8 tests passed for event serialization, malformed server messages, certificate pin comparison, and LAN address validation.
- Flutter `flutter analyze`: no issues.
- `pip-audit -r requirements.txt`: no known vulnerabilities reported for the pinned Windows server runtime requirements at scan time.
- Bandit static scan: initially flagged the all-interface bind default. That finding was addressed by binding to discovered RFC1918 addresses by default. The final scan reported no findings.
- PyInstaller produced `windows_server/dist/PhoneRemote.exe`. The window opened, started the server on a selected test port, and displayed connection details. Windows then showed its Firewall permission dialog. The assessment did not change Firewall settings or accept that prompt; the test process was terminated afterward.

## Not covered / release blockers

- No Android debug APK could be built in this environment: Gradle failed with `Unable to establish loopback connection` before compiling the app.
- No real Android phone-to-laptop session or input injection was tested. The WebSocket integration suite runs only on loopback and uses fake input devices.
- No external-network scan, router/firewall penetration test, fuzz campaign, or independent professional penetration test was performed.
- The Windows executable is unsigned. Build and distribute it only from a trusted source; obtain code signing before public distribution.
- Windows Firewall permission must be reviewed by the user and limited to Private networks. Do not permit Public network access or forward the server port from the router.
- A Python process was already listening on `0.0.0.0:8765` before the launcher test. It was left untouched; identify that process before relying on the old listener. The new launcher can use a different port.

## Conclusion

The tests provide useful evidence that the protocol rejects common malformed and unauthorized inputs and that the server's TLS/pairing flow works in a controlled local environment. They do not establish that the application is safe against all attacks. Complete physical-device testing and an independent security assessment before public release.
