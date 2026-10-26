# Phone Remote Windows Server

TLS-protected WebSocket server that injects authenticated phone keyboard, mouse, and media events on Windows.

## Requirements

- Windows 10/11
- Python 3.11 or newer
- Phone and laptop on the **same Wi-Fi network**

## Setup (venv)

From this folder:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python server.py --no-tray
```

Or double-click `run.bat`.

## Run

```powershell
python server.py
python server.py --port 8765
python server.py --no-tray
```

When it starts, the console prints your LAN IPv4 addresses, a one-time 8-digit pairing code, and the server certificate's SHA-256 fingerprint. Enter these in the Android app and compare the fingerprint exactly. The code changes every time the server starts; the certificate fingerprint remains stable unless its identity files are removed.

A tray icon appears when `pystray` is available. Right-click it → **Quit Phone Remote**. Use `--no-tray` to keep a normal console window.

## Firewall

If the phone cannot connect, allow Python through Windows Defender Firewall on **Private** networks (inbound TCP `8765`). Never enable this rule on Public networks.

## Protocol

TLS-encrypted JSON text frames over `wss://<ip>:8765/remote`. The phone pins the server certificate by SHA-256 fingerprint and authenticates using the per-start pairing code. Five failed pairing attempts from one IP cause a temporary lockout. Only one authenticated phone can control the PC at a time.

The server first sends `{"type":"hello","status":"auth_required","protocol":2}`. The app replies with `{"type":"authenticate","pairing_code":"<8 digits>"}`. Control events are accepted only after `{"type":"auth_result","status":"ok"}`.

| type | fields | effect |
|------|--------|--------|
| `key` / `key_tap` | `key` | tap a key (`a`, `enter`, `backspace`, …) |
| `key_down` / `key_up` | `key` | hold / release |
| `text` | `text` | type a short string |
| `mouse_move` | `dx`, `dy` | relative cursor move |
| `mouse_click` | `button`: left/right/middle | click |
| `mouse_down` / `mouse_up` | `button` | press / release |
| `mouse_scroll` | `dx`, `dy` | wheel scroll |
| `media` | `action`: play_pause, volume_up, volume_down, volume_mute | media keys |
| `ping` | | replies with `pong` |

The TLS private key and certificate are stored under `%LOCALAPPDATA%\Phone Remote`; they are not stored in the repository. The pairing code stays in memory and is never written to disk. The server logs connection metadata but does not log typed text or key contents.

Keyboard and mouse events are intentionally injected into the active Windows session. Keep the pairing code private and use the server only on a trusted local network.
