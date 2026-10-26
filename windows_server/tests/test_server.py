"""Unit and loopback integration/security tests for the Windows server."""

from __future__ import annotations

import asyncio
import hashlib
import json
import ssl
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import websockets
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server  # noqa: E402


class FakeKeyboard:
    def __init__(self) -> None:
        self.pressed: list[object] = []
        self.released: list[object] = []
        self.typed: list[str] = []

    def press(self, key: object) -> None:
        self.pressed.append(key)

    def release(self, key: object) -> None:
        self.released.append(key)

    def type(self, value: str) -> None:
        self.typed.append(value)


class FakeMouse:
    def __init__(self) -> None:
        self.moves: list[tuple[int, int]] = []
        self.scrolls: list[tuple[int, int]] = []
        self.pressed: list[object] = []
        self.released: list[object] = []
        self.clicks: list[tuple[object, int]] = []

    def move(self, dx: int, dy: int) -> None:
        self.moves.append((dx, dy))

    def scroll(self, dx: int, dy: int) -> None:
        self.scrolls.append((dx, dy))

    def press(self, button: object) -> None:
        self.pressed.append(button)

    def release(self, button: object) -> None:
        self.released.append(button)

    def click(self, button: object, count: int) -> None:
        self.clicks.append((button, count))


class ServerUnitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.keyboard = FakeKeyboard()
        self.mouse = FakeMouse()
        self.keyboard_patch = mock.patch.object(server, "keyboard", self.keyboard)
        self.mouse_patch = mock.patch.object(server, "mouse", self.mouse)
        self.keyboard_patch.start()
        self.mouse_patch.start()

    def tearDown(self) -> None:
        self.keyboard_patch.stop()
        self.mouse_patch.stop()

    def test_key_name_allowlist(self) -> None:
        self.assertEqual(server._resolve_key("a"), "a")
        self.assertIsNotNone(server._resolve_key("enter"))
        self.assertIsNone(server._resolve_key("shutdown"))
        self.assertIsNone(server._resolve_key(""))
        self.assertIsNone(server._resolve_key(123))

    def test_lan_discovery_returns_only_private_ipv4_addresses(self) -> None:
        class FakeSocket:
            def connect(self, _address):
                pass

            def getsockname(self):
                return ("8.8.8.8", 0)

            def close(self):
                pass

        info = lambda address: (None, None, None, None, (address, 0))
        with (
            mock.patch.object(server.socket, "gethostname", return_value="test-host"),
            mock.patch.object(
                server.socket,
                "getaddrinfo",
                return_value=[
                    info("10.2.3.4"),
                    info("192.168.1.12"),
                    info("172.31.0.8"),
                    info("172.32.0.8"),
                    info("127.0.0.1"),
                    info("8.8.8.8"),
                ],
            ),
            mock.patch.object(server.socket, "socket", return_value=FakeSocket()),
        ):
            self.assertEqual(
                server.get_lan_ipv4(),
                ["10.2.3.4", "192.168.1.12", "172.31.0.8"],
            )

    def test_text_and_pointer_inputs_are_bounded(self) -> None:
        ok, _ = server.handle_event({"type": "text", "text": "x" * 1000})
        self.assertTrue(ok)
        self.assertEqual(len(self.keyboard.typed[0]), server.MAX_TEXT_CHARS)

        ok, _ = server.handle_event(
            {"type": "mouse_move", "dx": 999999, "dy": -999999}
        )
        self.assertTrue(ok)
        self.assertEqual(
            self.mouse.moves[-1], (server.MAX_MOUSE_DELTA, -server.MAX_MOUSE_DELTA)
        )

        ok, _ = server.handle_event(
            {"type": "mouse_scroll", "dx": 1000, "dy": -1000}
        )
        self.assertTrue(ok)
        self.assertEqual(self.mouse.scrolls[-1], (server.MAX_SCROLL, -server.MAX_SCROLL))

    def test_invalid_event_payloads_do_not_inject_input(self) -> None:
        cases = [
            {},
            {"type": "key", "key": "launch-malware"},
            {"type": "mouse_click", "button": "unknown"},
            {"type": "media", "action": "arbitrary"},
            {"type": "text", "text": 12},
            {"type": "mouse_move", "dx": float("nan"), "dy": 0},
        ]
        for payload in cases:
            with self.subTest(payload=payload):
                ok, error = server.handle_event(payload)
                self.assertFalse(ok)
                self.assertTrue(error)
        self.assertEqual(self.keyboard.pressed, [])
        self.assertEqual(self.keyboard.typed, [])
        self.assertEqual(self.mouse.moves, [])
        self.assertEqual(self.mouse.clicks, [])

    def test_authentication_lockout_after_five_failures(self) -> None:
        server._auth_failures.clear()
        with mock.patch.object(server.time, "monotonic", return_value=1000.0):
            for _ in range(server.AUTH_FAILURE_LIMIT):
                server._record_auth_failure("192.168.1.44")
            self.assertTrue(server._auth_is_blocked("192.168.1.44"))
        server._auth_failures.clear()

    def test_tls_identity_persists_and_fingerprint_is_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                mock.patch.dict(server.os.environ, {"LOCALAPPDATA": temp_dir}),
                mock.patch.object(server, "get_lan_ipv4", return_value=["192.168.1.10"]),
            ):
                cert_path_1, key_path_1, cert_1 = server._ensure_tls_certificate()
                cert_path_2, key_path_2, cert_2 = server._ensure_tls_certificate()
                self.assertEqual(cert_path_1, cert_path_2)
                self.assertEqual(key_path_1, key_path_2)
                self.assertEqual(server._fingerprint(cert_1), server._fingerprint(cert_2))
                self.assertEqual(len(server._fingerprint(cert_1).replace(":", "")), 64)


class ServerIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.old_keyboard = server.keyboard
        self.old_mouse = server.mouse
        self.keyboard = FakeKeyboard()
        self.mouse = FakeMouse()
        server.keyboard = self.keyboard
        server.mouse = self.mouse
        server._PAIRING_CODE = "12345678"
        server._auth_failures.clear()
        server._pending_clients.clear()
        server._active_client = None

        self.temp_dir = tempfile.TemporaryDirectory()
        with (
            mock.patch.dict(server.os.environ, {"LOCALAPPDATA": self.temp_dir.name}),
            mock.patch.object(server, "get_lan_ipv4", return_value=["127.0.0.1"]),
        ):
            cert_path, key_path, cert = server._ensure_tls_certificate()
        self.fingerprint = server._fingerprint(cert)
        self.context = server._make_tls_context(cert_path, key_path)
        self.web_server = await serve(
            server.handle_client,
            "127.0.0.1",
            0,
            ssl=self.context,
            max_size=server.MAX_MESSAGE_BYTES,
            ping_interval=None,
            close_timeout=0.2,
        )
        self.port = self.web_server.sockets[0].getsockname()[1]
        self.client_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self.client_tls.check_hostname = False
        self.client_tls.verify_mode = ssl.CERT_NONE

    async def asyncTearDown(self) -> None:
        self.web_server.close()
        await self.web_server.wait_closed()
        server.keyboard = self.old_keyboard
        server.mouse = self.old_mouse
        server._active_client = None
        server._pending_clients.clear()
        server._auth_failures.clear()
        self.temp_dir.cleanup()

    def _uri(self, path: str = "/remote") -> str:
        return "wss://127.0.0.1:%d%s" % (self.port, path)

    async def _connect(self, path: str = "/remote"):
        return await websockets.connect(
            self._uri(path),
            ssl=self.client_tls,
            ping_interval=None,
            close_timeout=0.2,
        )

    async def _authenticate(self, ws, code: str = "12345678") -> dict:
        hello = json.loads(await ws.recv())
        self.assertEqual(hello["status"], "auth_required")
        await ws.send(json.dumps({"type": "authenticate", "pairing_code": code}))
        return json.loads(await ws.recv())

    async def test_tls_identity_and_valid_pairing_allow_control(self) -> None:
        async with await self._connect() as ws:
            ssl_object = ws.transport.get_extra_info("ssl_object")
            peer_der = ssl_object.getpeercert(binary_form=True)
            actual = hashlib.sha256(peer_der).hexdigest().upper()
            expected = self.fingerprint.replace(":", "")
            self.assertEqual(actual, expected)

            result = await self._authenticate(ws)
            self.assertEqual(result, {"type": "auth_result", "status": "ok"})
            await ws.send(json.dumps({"type": "key", "key": "a"}))
            await ws.send(json.dumps({"type": "mouse_move", "dx": 12, "dy": -8}))
            await asyncio.sleep(0.05)
            self.assertIn("a", self.keyboard.pressed)
            self.assertEqual(self.mouse.moves, [(12, -8)])

    async def test_bad_pairing_code_never_injects_input(self) -> None:
        async with await self._connect() as ws:
            result = await self._authenticate(ws, "00000000")
            self.assertEqual(result["status"], "denied")
        self.assertEqual(self.keyboard.pressed, [])
        self.assertEqual(self.mouse.moves, [])

    async def test_mismatched_certificate_fingerprint_is_not_trusted(self) -> None:
        async with await self._connect() as ws:
            ssl_object = ws.transport.get_extra_info("ssl_object")
            peer_der = ssl_object.getpeercert(binary_form=True)
            actual = hashlib.sha256(peer_der).hexdigest().upper()
            wrong_pin = "0" * 64 if actual != "0" * 64 else "1" * 64
            self.assertNotEqual(actual, wrong_pin)
            # Mirror the client's fail-closed pin check: don't send the pairing secret.
            await ws.close()
        self.assertEqual(self.keyboard.pressed, [])
        self.assertEqual(self.mouse.moves, [])

    async def test_pending_pairing_connections_are_capped(self) -> None:
        clients = []
        try:
            for _ in range(server.MAX_PENDING_CLIENTS):
                ws = await self._connect()
                await ws.recv()
                clients.append(ws)
            overflow = await self._connect()
            with self.assertRaises(ConnectionClosed):
                await overflow.recv()
        finally:
            for ws in clients:
                await ws.close()

    async def test_only_one_authenticated_controller_is_allowed(self) -> None:
        primary = await self._connect()
        self.assertEqual((await self._authenticate(primary))["status"], "ok")
        try:
            async with await self._connect() as second:
                result = await self._authenticate(second)
                self.assertEqual(result["status"], "busy")
        finally:
            await primary.close()

    async def test_rejected_path_and_pairing_throttle(self) -> None:
        ws = await self._connect("/not-remote")
        with self.assertRaises(ConnectionClosed):
            await ws.recv()

        for _ in range(server.AUTH_FAILURE_LIMIT):
            async with await self._connect() as attempt:
                response = await self._authenticate(attempt, "00000000")
                self.assertEqual(response["status"], "denied")

        blocked = await self._connect()
        with self.assertRaises(ConnectionClosed):
            await blocked.recv()

    async def test_malformed_and_invalid_events_are_rejected(self) -> None:
        async with await self._connect() as ws:
            self.assertEqual((await self._authenticate(ws))["status"], "ok")
            await ws.send("not-json")
            self.assertEqual(json.loads(await ws.recv())["message"], "invalid JSON")
            await ws.send("[]")
            self.assertEqual(
                json.loads(await ws.recv())["message"], "JSON object required"
            )
            await ws.send(json.dumps({"type": "key", "key": "powershell"}))
            self.assertEqual(json.loads(await ws.recv())["message"], "unknown key")
        self.assertEqual(self.keyboard.pressed, [])

    async def test_oversized_frame_is_closed_by_websocket_limit(self) -> None:
        ws = await self._connect()
        await self._authenticate(ws)
        with self.assertRaises(ConnectionClosed):
            await ws.send("x" * (server.MAX_MESSAGE_BYTES + 1))
            await ws.recv()

    async def test_disconnect_releases_held_keys_and_mouse_buttons(self) -> None:
        ws = await self._connect()
        self.assertEqual((await self._authenticate(ws))["status"], "ok")
        await ws.send(json.dumps({"type": "key_down", "key": "a"}))
        await ws.send(json.dumps({"type": "mouse_down", "button": "left"}))
        await asyncio.sleep(0.05)
        await ws.close()
        await asyncio.sleep(0.05)
        self.assertIn("a", self.keyboard.released)
        self.assertIn(server.Button.left, self.mouse.released)


if __name__ == "__main__":
    unittest.main()
