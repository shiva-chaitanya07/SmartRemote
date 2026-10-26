#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Phone Remote Windows server.

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
from collections import deque
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import ipaddress
import json
import logging
import os
from pathlib import Path
import secrets
import signal
import socket
import ssl
import sys
import threading
import time
from typing import Any, Dict, Tuple

if sys.version_info < (3, 11):
    print("Phone Remote requires Python 3.11 or newer. Install a current Python 3 release.")
    sys.exit(1)

try:
    from websockets.asyncio.server import serve
    from websockets.exceptions import ConnectionClosed
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
DEFAULT_PORT = 8765
PRIVATE_IPV4_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
MAX_MESSAGE_BYTES = 32 * 1024
MAX_TEXT_CHARS = 500
MAX_MOUSE_DELTA = 4000
MAX_SCROLL = 50
AUTH_TIMEOUT_SECONDS = 8
AUTH_FAILURE_LIMIT = 5
AUTH_FAILURE_WINDOW_SECONDS = 60
AUTH_LOCKOUT_SECONDS = 60
MAX_PENDING_CLIENTS = 4
MAX_AUTH_FAILURE_IPS = 256

if sys.stderr is None:
    # A windowed PyInstaller build has no console stream; its GUI reports startup errors.
    logging.basicConfig(level=logging.INFO, handlers=[logging.NullHandler()])
else:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )
log = logging.getLogger("smartcontroller")

keyboard = KeyboardController()
mouse = MouseController()
_auth_failures = {}  # peer IP -> deque of monotonic failure times
_active_client = None
_pending_clients = set()
_PAIRING_CODE = ""

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
except ImportError:
    print("Missing dependency: cryptography. Run:  pip install -r requirements.txt")
    sys.exit(1)

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

    def add_private_address(value):
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            return
        if address.version == 4 and any(
            address in network for network in PRIVATE_IPV4_NETWORKS
        ):
            candidates.append(str(address))

    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            add_private_address(info[4][0])
    except socket.error:
        pass

    # UDP trick: OS picks the interface used for outbound LAN traffic.
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        if ip:
            add_private_address(ip)
            if candidates and candidates[-1] == ip:
                candidates.insert(0, candidates.pop())
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


def _local_data_dir():
    """Return a per-user directory for the private TLS key and certificate."""
    base = os.environ.get("LOCALAPPDATA")
    if not base:
        base = str(Path.home() / "AppData" / "Local")
    directory = Path(base) / "Phone Remote"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def _ensure_tls_certificate():
    """Create or load the server identity; only the certificate fingerprint is shared."""
    directory = _local_data_dir()
    key_path = directory / "server-key.pem"
    cert_path = directory / "server-cert.pem"

    if key_path.exists() and cert_path.exists():
        try:
            cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
            private_key = serialization.load_pem_private_key(
                key_path.read_bytes(), password=None
            )
            if private_key.public_key().public_numbers() != cert.public_key().public_numbers():
                raise ValueError("TLS key does not match certificate")
        except Exception as exc:
            log.warning("Stored TLS identity is invalid; generating a new one: %s", exc)
        else:
            return str(cert_path), str(key_path), cert

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [x509.NameAttribute(NameOID.COMMON_NAME, "Phone Remote local server")]
    )
    now = datetime.now(timezone.utc)
    san_entries = [x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]
    for address in get_lan_ipv4():
        try:
            parsed = ipaddress.ip_address(address)
            if parsed not in [entry.value for entry in san_entries]:
                san_entries.append(x509.IPAddress(parsed))
        except ValueError:
            continue

    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=1825))
        .add_extension(x509.SubjectAlternativeName(san_entries), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(private_key, hashes.SHA256())
    )

    key_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    cert_bytes = cert.public_bytes(serialization.Encoding.PEM)
    key_path.write_bytes(key_bytes)
    cert_path.write_bytes(cert_bytes)
    try:
        os.chmod(str(key_path), 0o600)
    except OSError:
        pass  # Windows protects files under the user's LocalAppData ACL.
    return str(cert_path), str(key_path), cert


def _fingerprint(cert):
    digest = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest().upper()
    return ":".join(digest[index : index + 2] for index in range(0, len(digest), 2))


def _make_tls_context(cert_path, key_path):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certfile=cert_path, keyfile=key_path)
    return context


def _auth_is_blocked(peer_ip):
    entry = _auth_failures.get(peer_ip)
    if not entry:
        return False
    now = time.monotonic()
    if entry["locked_until"] > now:
        return True
    while entry["failures"] and now - entry["failures"][0] > AUTH_FAILURE_WINDOW_SECONDS:
        entry["failures"].popleft()
    if entry["locked_until"]:
        entry["locked_until"] = 0
    if not entry["failures"]:
        _auth_failures.pop(peer_ip, None)
    return False


def _record_auth_failure(peer_ip):
    now = time.monotonic()
    for old_ip, old_entry in list(_auth_failures.items()):
        while (
            old_entry["failures"]
            and now - old_entry["failures"][0] > AUTH_FAILURE_WINDOW_SECONDS
        ):
            old_entry["failures"].popleft()
        if not old_entry["failures"] and old_entry["locked_until"] <= now:
            _auth_failures.pop(old_ip, None)
    if peer_ip not in _auth_failures and len(_auth_failures) >= MAX_AUTH_FAILURE_IPS:
        _auth_failures.pop(next(iter(_auth_failures)))
    entry = _auth_failures.setdefault(
        peer_ip, {"failures": deque(), "locked_until": 0}
    )
    while entry["failures"] and now - entry["failures"][0] > AUTH_FAILURE_WINDOW_SECONDS:
        entry["failures"].popleft()
    entry["failures"].append(now)
    if len(entry["failures"]) >= AUTH_FAILURE_LIMIT:
        entry["locked_until"] = now + AUTH_LOCKOUT_SECONDS


def _clear_auth_failures(peer_ip):
    _auth_failures.pop(peer_ip, None)


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


async def handle_client(ws):
    """Authenticate a certificate-pinned client before accepting control events."""
    global _active_client

    peer = getattr(ws, "remote_address", None)
    peer_ip = str(peer[0]) if isinstance(peer, tuple) and peer else "unknown"
    path = getattr(getattr(ws, "request", None), "path", "")
    log.info("Connection attempt from %s", peer_ip)

    held_keys = []
    held_buttons = []
    authenticated = False
    try:
        if path != "/remote":
            await ws.close(code=1008, reason="Unsupported endpoint")
            return
        if _auth_is_blocked(peer_ip):
            await ws.close(code=1008, reason="Pairing temporarily locked")
            return
        if len(_pending_clients) >= MAX_PENDING_CLIENTS:
            await ws.close(code=1013, reason="Too many pending pairing attempts")
            return
        _pending_clients.add(ws)

        await send_json(
            ws,
            {"type": "hello", "status": "auth_required", "server": APP_NAME, "protocol": 2},
        )
        try:
            raw_auth = await asyncio.wait_for(ws.recv(), timeout=AUTH_TIMEOUT_SECONDS)
            auth = json.loads(raw_auth) if isinstance(raw_auth, str) else None
        except (asyncio.TimeoutError, ValueError, ConnectionClosed):
            auth = None

        supplied_code = auth.get("pairing_code") if isinstance(auth, dict) else None
        if (
            not isinstance(supplied_code, str)
            or auth.get("type") != "authenticate"
            or not hmac.compare_digest(supplied_code, _PAIRING_CODE)
        ):
            _record_auth_failure(peer_ip)
            await send_json(ws, {"type": "auth_result", "status": "denied"})
            await ws.close(code=1008, reason="Pairing failed")
            return

        if _active_client is not None:
            await send_json(ws, {"type": "auth_result", "status": "busy"})
            await ws.close(code=1013, reason="Another remote is already connected")
            return

        _clear_auth_failures(peer_ip)
        _active_client = ws
        authenticated = True
        await send_json(ws, {"type": "auth_result", "status": "ok"})
        log.info("Authenticated remote connected from %s", peer_ip)

        async for raw in ws:
            if not isinstance(raw, str):
                await send_json(ws, {"type": "error", "message": "expected JSON text"})
                continue
            if len(raw.encode("utf-8")) > MAX_MESSAGE_BYTES:
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
            elif ok and event_type == "mouse_down":
                held_button = MOUSE_BUTTONS.get(str(payload.get("button", "left")).lower())
                if held_button is not None and held_button not in held_buttons:
                    held_buttons.append(held_button)
            elif ok and event_type == "mouse_up":
                held_button = MOUSE_BUTTONS.get(str(payload.get("button", "left")).lower())
                if held_button in held_buttons:
                    held_buttons.remove(held_button)

            if event_type == "ping":
                await send_json(ws, {"type": "pong"})
            elif not ok:
                await send_json(ws, {"type": "error", "message": err})
    except ConnectionClosed as exc:
        log.info("Client disconnected (%s)", exc)
    except Exception:
        log.exception("Client handler crashed")
    finally:
        _pending_clients.discard(ws)
        for held_key in held_keys:
            try:
                keyboard.release(held_key)
            except Exception:
                log.exception("Could not release key held by disconnected client")
        for held_button in held_buttons:
            try:
                mouse.release(held_button)
            except Exception:
                log.exception("Could not release mouse button held by disconnected client")
        if authenticated and _active_client is ws:
            _active_client = None
        log.info("Connection closed for %s", peer_ip)


def print_banner(port, fingerprint, pairing_code, ips):
    line = "=" * 60
    print("")
    print(line)
    print("  %s  —  Phone Remote for Windows" % APP_NAME)
    print(line)
    print("")
    print("  Encrypted WebSocket: wss://<laptop-ip>:%s/remote" % port)
    print("")
    if ips:
        print("  Enter one of these IP addresses on your phone (same Wi-Fi):")
        print("")
        for ip in ips:
            print("      >>>  %s  <<<" % ip)
        print("")
        print("  Example:  wss://%s:%s/remote" % (ips[0], port))
    else:
        print("  Could not detect LAN IP. Run `ipconfig` and use your Wi-Fi IPv4.")
    print("")
    print("  Pairing code (changes every time the server starts): %s" % pairing_code)
    print("  Server certificate SHA-256 fingerprint (enter exactly in the app):")
    print("      %s" % fingerprint)
    print("  Allow Python through Windows Firewall on Private networks only.")
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
        menu = pystray.Menu(pystray.MenuItem("Quit Phone Remote", on_quit))
        icon = pystray.Icon("phone-remote", image, APP_NAME, menu)
        log.info("System tray icon is running. Right-click it to quit.")
        icon.run()
        return True
    except Exception:
        log.exception("System tray failed — falling back to console.")
        return False


async def run_server(
    host,
    port,
    stop_event,
    tls_context,
    fingerprint,
    pairing_code,
    ready_event=None,
    show_banner=True,
):
    bind_hosts = [host] if host else get_lan_ipv4()
    if not bind_hosts:
        raise OSError(
            "No private LAN IPv4 address was found. Connect to Wi-Fi or provide --host."
        )
    if show_banner:
        print_banner(port, fingerprint, pairing_code, bind_hosts)
    listeners = []
    try:
        for bind_host in bind_hosts:
            listener = await serve(
                handle_client,
                bind_host,
                port,
                ssl=tls_context,
                max_size=MAX_MESSAGE_BYTES,
                ping_interval=20,
                ping_timeout=20,
                max_queue=8,
                open_timeout=10,
                close_timeout=3,
            )
            listeners.append(listener)
    except OSError as exc:
        for listener in listeners:
            listener.close()
        if listeners:
            await asyncio.gather(*(listener.wait_closed() for listener in listeners))
        log.error("Could not bind Phone Remote on port %s — %s", port, exc)
        raise

    log.info("Server is ready.")
    if ready_event is not None:
        ready_event.set()
    try:
        while not stop_event.is_set():
            await asyncio.sleep(0.25)
    finally:
        for listener in listeners:
            listener.close()
        await asyncio.gather(*(listener.wait_closed() for listener in listeners))
        log.info("Server stopped.")


def start_asyncio_thread(
    host,
    port,
    stop_event,
    tls_context,
    fingerprint,
    pairing_code,
    ready_event=None,
    error_callback=None,
    show_banner=True,
):
    loop = asyncio.new_event_loop()

    def _runner():
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(
                run_server(
                    host,
                    port,
                    stop_event,
                    tls_context,
                    fingerprint,
                    pairing_code,
                    ready_event=ready_event,
                    show_banner=show_banner,
                )
            )
        except Exception as exc:
            log.exception("Server thread exited with an error")
            if error_callback is not None:
                error_callback(exc)
            if ready_event is not None:
                ready_event.set()
            stop_event.set()
        finally:
            loop.stop()
            loop.close()

    thread = threading.Thread(target=_runner, name="ws-server", daemon=True)
    thread.start()
    return thread


def prepare_server_session(port=DEFAULT_PORT):
    """Create the TLS identity and fresh in-memory pairing code for a session."""
    global _PAIRING_CODE

    if port < 1 or port > 65535:
        raise ValueError("Port must be between 1 and 65535")
    cert_path, key_path, cert = _ensure_tls_certificate()
    tls_context = _make_tls_context(cert_path, key_path)
    fingerprint = _fingerprint(cert)
    _PAIRING_CODE = "%08d" % secrets.randbelow(100000000)
    return tls_context, fingerprint, _PAIRING_CODE


def parse_args(argv):
    parser = argparse.ArgumentParser(description="%s Windows WebSocket server" % APP_NAME)
    parser.add_argument(
        "--host",
        default=None,
        help="Bind to this address instead of detected private LAN IPv4 interfaces",
    )
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Listen port (default 8765)")
    parser.add_argument(
        "--no-tray",
        action="store_true",
        help="Do not use the system tray; keep a console process",
    )
    return parser.parse_args(argv)


def main(argv=None):
    global _PAIRING_CODE

    args = parse_args(argv if argv is not None else sys.argv[1:])
    if args.port < 1 or args.port > 65535:
        print("Port must be between 1 and 65535.")
        return 2

    try:
        tls_context, fingerprint, pairing_code = prepare_server_session(args.port)
    except Exception as exc:
        log.exception("Could not prepare the TLS server identity")
        print("TLS setup failed: %s" % exc)
        return 1

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
    thread = start_asyncio_thread(
        args.host, args.port, stop_event, tls_context, fingerprint, pairing_code
    )

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
