#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SmartController Windows server.

Listens for WebSocket connections from the Android app and injects
keyboard / mouse / media events with pynput.

Usage:
    python server.py
    python server.py --port 8765
    python server.py --no-tray
"""

from __future__ import print_function

import argparse
import asyncio
import json
import logging
import os
import signal
import socket
import sys
import threading
from typing import Any, Dict, Optional, Tuple

try:
    import websockets
    from websockets.exceptions import ConnectionClosed
    from websockets.server import WebSocketServerProtocol
except ImportError:
    print("Missing dependency: websockets. Run:  pip install -r requirements.txt")
    sys.exit(1)

try:
    from pynput.keyboard import Controller as KeyboardController
    from pynput.keyboard import Key
    from pynput.mouse import Button, Controller as MouseController
except ImportError:
    print("Missing dependency: pynput. Run:  pip install -r requirements.txt")
    sys.exit(1)

APP_NAME = "Phone Remote"
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8765
MAX_MESSAGE_BYTES = 32 * 1024
MAX_TEXT_CHARS = 500
MAX_MOUSE_DELTA = 4000
MAX_SCROLL = 50

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("smartcontroller")

keyboard = KeyboardController()
mouse = MouseController()

# Maps protocol key names (from the Flutter app) to pynput keys.
SPECIAL_KEYS = {
    "enter": Key.enter,
    "return": Key.enter,
    "backspace": Key.backspace,
    "tab": Key.tab,
    "esc": Key.esc,
    "escape": Key.esc,
    "space": Key.space,
    "shift": Key.shift,
    "shift_l": Key.shift_l,
    "shift_r": Key.shift_r,
    "ctrl": Key.ctrl,
    "ctrl_l": Key.ctrl_l,
    "ctrl_r": Key.ctrl_r,
    "alt": Key.alt,
    "alt_l": Key.alt_l,
    "alt_r": Key.alt_r,
    "cmd": Key.cmd,
    "win": Key.cmd,
    "up": Key.up,
    "down": Key.down,
    "left": Key.left,
    "right": Key.right,
    "delete": Key.delete,
    "home": Key.home,
    "end": Key.end,
    "page_up": Key.page_up,
    "page_down": Key.page_down,
    "caps_lock": Key.caps_lock,
    "insert": Key.insert,
    "media_play_pause": Key.media_play_pause,
    "media_volume_up": Key.media_volume_up,
    "media_volume_down": Key.media_volume_down,
    "media_volume_mute": Key.media_volume_mute,
    "media_next": Key.media_next,
    "media_previous": Key.media_previous,
}

for _i in range(1, 13):
    SPECIAL_KEYS["f%d" % _i] = getattr(Key, "f%d" % _i)

MEDIA_ACTIONS = {
    "play_pause": Key.media_play_pause,
    "volume_up": Key.media_volume_up,
    "volume_down": Key.media_volume_down,
    "volume_mute": Key.media_volume_mute,
    "next": Key.media_next,
    "previous": Key.media_previous,
}

MOUSE_BUTTONS = {
    "left": Button.left,
    "right": Button.right,
    "middle": Button.middle,
}


def get_lan_ipv4():
    """Best-effort LAN IPv4 so the phone can connect on the same Wi-Fi."""
    candidates = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                candidates.append(ip)
    except socket.error:
        pass

    # UDP trick: OS picks the interface used for outbound LAN traffic.
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        if ip and not ip.startswith("127."):
            candidates.insert(0, ip)
    except socket.error:
        pass
    finally:
        sock.close()

    seen = set()
    unique = []
    for ip in candidates:
        if ip not in seen:
            seen.add(ip)
            unique.append(ip)
    return unique


def _clamp(value, lo, hi):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return 0.0
    if n < lo:
        return lo
    if n > hi:
        return hi
    return n


def _resolve_key(name):
    # type: (str) -> Any
    if not isinstance(name, str) or not name:
        return None
    mapped = SPECIAL_KEYS.get(name.lower())
    if mapped is not None:
        return mapped
    if len(name) == 1:
        return name
    return None


def _tap_key(key):
    keyboard.press(key)
    keyboard.release(key)


def handle_event(payload):
    # type: (Dict[str, Any]) -> Tuple[bool, str]
    """Apply one client event. Returns (ok, error_message)."""
    event_type = payload.get("type")
    if not isinstance(event_type, str):
        return False, "missing event type"

    try:
        if event_type == "ping":
            return True, ""

        if event_type in ("key", "key_tap"):
            key = _resolve_key(payload.get("key", ""))
            if key is None:
                return False, "unknown key"
            _tap_key(key)
            return True, ""

        if event_type == "key_down":
            key = _resolve_key(payload.get("key", ""))
            if key is None:
                return False, "unknown key"
            keyboard.press(key)
            return True, ""

        if event_type == "key_up":
            key = _resolve_key(payload.get("key", ""))
            if key is None:
                return False, "unknown key"
            keyboard.release(key)
            return True, ""

        if event_type == "text":
            text = payload.get("text", "")
            if not isinstance(text, str) or not text:
                return False, "empty text"
            keyboard.type(text[:MAX_TEXT_CHARS])
            return True, ""

        if event_type == "mouse_move":
            dx = int(round(_clamp(payload.get("dx", 0), -MAX_MOUSE_DELTA, MAX_MOUSE_DELTA)))
            dy = int(round(_clamp(payload.get("dy", 0), -MAX_MOUSE_DELTA, MAX_MOUSE_DELTA)))
            if dx or dy:
                mouse.move(dx, dy)
            return True, ""

        if event_type == "mouse_click":
            button = MOUSE_BUTTONS.get(str(payload.get("button", "left")).lower())
            if button is None:
                return False, "unknown mouse button"
            mouse.click(button, 1)
            return True, ""

        if event_type == "mouse_down":
            button = MOUSE_BUTTONS.get(str(payload.get("button", "left")).lower())
            if button is None:
                return False, "unknown mouse button"
            mouse.press(button)
            return True, ""

        if event_type == "mouse_up":
            button = MOUSE_BUTTONS.get(str(payload.get("button", "left")).lower())
            if button is None:
                return False, "unknown mouse button"
            mouse.release(button)
            return True, ""

        if event_type == "mouse_scroll":
            dx = int(round(_clamp(payload.get("dx", 0), -MAX_SCROLL, MAX_SCROLL)))
            dy = int(round(_clamp(payload.get("dy", 0), -MAX_SCROLL, MAX_SCROLL)))
            if dx or dy:
                mouse.scroll(dx, dy)
            return True, ""

        if event_type == "media":
            action = str(payload.get("action", "")).lower()
            key = MEDIA_ACTIONS.get(action)
            if key is None:
                return False, "unknown media action"
            _tap_key(key)
            return True, ""

        return False, "unknown event type: %s" % event_type
    except Exception as exc:
        log.exception("Failed to inject event %s", event_type)
        return False, str(exc)


async def send_json(ws, data):
    await ws.send(json.dumps(data))


async def handle_client(ws, path):
    # type: (WebSocketServerProtocol, str) -> None
    peer = getattr(ws, "remote_address", None)
    log.info("Client connected from %s path=%s", peer, path)
    held_keys = []
    await send_json(
        ws,
        {
            "type": "hello",
            "status": "ok",
            "server": APP_NAME,
            "protocol": 1,
        },
    )
    try:
        async for raw in ws:
            if not isinstance(raw, str):
                await send_json(ws, {"type": "error", "message": "expected JSON text"})
                continue
            if len(raw) > MAX_MESSAGE_BYTES:
                await send_json(ws, {"type": "error", "message": "message too large"})
                continue
            try:
                payload = json.loads(raw)
            except ValueError:
                await send_json(ws, {"type": "error", "message": "invalid JSON"})
                continue
            if not isinstance(payload, dict):
                await send_json(ws, {"type": "error", "message": "JSON object required"})
                continue

            ok, err = handle_event(payload)
            event_type = payload.get("type")
            if ok and event_type == "key_down":
                held_key = _resolve_key(payload.get("key", ""))
                if held_key is not None and held_key not in held_keys:
                    held_keys.append(held_key)
            elif ok and event_type == "key_up":
                held_key = _resolve_key(payload.get("key", ""))
                if held_key in held_keys:
                    held_keys.remove(held_key)
            if event_type == "ping":
                await send_json(ws, {"type": "pong"})
            elif not ok:
                await send_json(ws, {"type": "error", "message": err})
    except ConnectionClosed as exc:
        log.info("Client disconnected (%s)", exc)
    except Exception:
        log.exception("Client handler crashed")
    finally:
        # Release modifiers if Wi-Fi drops while a key is held.
        for held_key in held_keys:
            try:
                keyboard.release(held_key)
            except Exception:
                log.exception("Could not release key held by disconnected client")
        log.info("Connection closed for %s", peer)


def print_banner(host, port):
    ips = get_lan_ipv4()
    line = "=" * 60
    print("")
    print(line)
    print("  %s  —  Phone Remote for Windows" % APP_NAME)
    print(line)
    print("")
    print("  Listening on  ws://%s:%s" % (host, port))
    print("")
    if ips:
        print("  Enter this IP on your phone (same Wi-Fi):")
        print("")
        for ip in ips:
            print("      >>>  %s  <<<" % ip)
        print("")
        print("  Example:  ws://%s:%s" % (ips[0], port))
    else:
        print("  Could not detect LAN IP. Run `ipconfig` and use your Wi-Fi IPv4.")
    print("")
    print("  Trusted local network only — there is no authentication.")
    print("  Allow Python through Windows Firewall if the phone cannot connect.")
    print("  Press Ctrl+C to quit.")
    print(line)
    print("")


def _make_tray_icon_image():
    from PIL import Image, ImageDraw

    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([8, 4, 56, 60], fill=(108, 99, 255, 255), outline=(255, 255, 255, 40))
    draw.rectangle([16, 14, 48, 36], fill=(20, 22, 32, 255))
    draw.rectangle([20, 42, 44, 48], fill=(230, 232, 240, 255))
    return img


def run_tray(stop_event):
    """Blocking system-tray loop. Returns False if tray is unavailable."""
    try:
        import pystray
        from PIL import Image  # noqa: F401  (import check)
    except ImportError:
        log.warning("pystray/Pillow not installed — running without tray.")
        return False

    def on_quit(icon, _item):
        stop_event.set()
        icon.stop()

    try:
        image = _make_tray_icon_image()
        menu = pystray.Menu(pystray.MenuItem("Quit SmartController", on_quit))
        icon = pystray.Icon("smartcontroller", image, APP_NAME, menu)
        log.info("System tray icon is running. Right-click it to quit.")
        icon.run()
        return True
    except Exception:
        log.exception("System tray failed — falling back to console.")
        return False


async def run_server(host, port, stop_event):
    print_banner(host, port)
    try:
        server = await websockets.serve(
            handle_client,
            host,
            port,
            max_size=MAX_MESSAGE_BYTES,
            ping_interval=20,
            ping_timeout=20,
        )
    except OSError as exc:
        log.error("Could not bind %s:%s — %s", host, port, exc)
        raise

    log.info("Server is ready.")
    try:
        while not stop_event.is_set():
            await asyncio.sleep(0.25)
    finally:
        server.close()
        await server.wait_closed()
        log.info("Server stopped.")


def start_asyncio_thread(host, port, stop_event):
    loop = asyncio.new_event_loop()

    def _runner():
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(run_server(host, port, stop_event))
        except Exception:
            log.exception("Server thread exited with an error")
            stop_event.set()
        finally:
            loop.stop()
            loop.close()

    thread = threading.Thread(target=_runner, name="ws-server", daemon=True)
    thread.start()
    return thread


def parse_args(argv):
    parser = argparse.ArgumentParser(description="%s Windows WebSocket server" % APP_NAME)
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind address (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Listen port (default 8765)")
    parser.add_argument(
        "--no-tray",
        action="store_true",
        help="Do not use the system tray; keep a console process",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    stop_event = threading.Event()

    def _request_stop(_signum=None, _frame=None):
        stop_event.set()

    try:
        signal.signal(signal.SIGINT, _request_stop)
        if hasattr(signal, "SIGTERM"):
            signal.signal(signal.SIGTERM, _request_stop)
    except (ValueError, OSError):
        pass

    use_tray = (not args.no_tray) and os.name == "nt"
    thread = start_asyncio_thread(args.host, args.port, stop_event)

    if use_tray:
        ran = run_tray(stop_event)
        if not ran:
            use_tray = False

    if not use_tray:
        try:
            while not stop_event.is_set() and thread.is_alive():
                thread.join(0.5)
        except KeyboardInterrupt:
            stop_event.set()

    stop_event.set()
    thread.join(timeout=3)
    return 0


if __name__ == "__main__":
    sys.exit(main())
