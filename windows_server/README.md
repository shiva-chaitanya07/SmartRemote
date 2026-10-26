# Phone Remote Windows Server

Python WebSocket server that turns incoming phone events into real keyboard, mouse, and media key presses on Windows.

## Requirements

- Windows 10/11
- Python 3.7+ (3.8 or newer recommended)
- Phone and laptop on the **same Wi-Fi network**

## Setup (venv)

From this folder:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python server.py
```

Or double-click `run.bat`.

## Run

```powershell
python server.py
python server.py --port 8765
python server.py --no-tray
```

When it starts, the console prints your LAN IPv4. Enter that IP in the Android app (port `8765` unless you changed it).

A tray icon appears when `pystray` is available. Right-click it → **Quit Phone Remote**. Use `--no-tray` to keep a normal console window.

## Firewall

If the phone cannot connect, allow Python through Windows Defender Firewall on **Private** networks (inbound TCP `8765`).

## Protocol

JSON text frames over `ws://<ip>:8765`.

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

On connect the server sends `{ "type": "hello", "status": "ok" }`.

This server has **no authentication**. Use it only on a trusted home/office LAN.
