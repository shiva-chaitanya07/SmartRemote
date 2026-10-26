"""Simple Windows desktop launcher for the Phone Remote server."""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from tkinter import messagebox, ttk

import server


class PhoneRemoteLauncher:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Phone Remote")
        self.root.geometry("600x570")
        self.root.minsize(520, 530)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self.status = tk.StringVar(value="Stopped")
        self.port = tk.StringVar(value=str(server.DEFAULT_PORT))
        self.active_port = server.DEFAULT_PORT
        self.addresses: list[str] = []
        self.pairing_code = ""
        self.fingerprint = ""
        self.stop_event: threading.Event | None = None
        self.ready_event: threading.Event | None = None
        self.server_thread: threading.Thread | None = None
        self.events: queue.Queue[tuple[str, str]] = queue.Queue()
        self.closing = False

        self._build_ui()
        self.root.after(150, self._poll_server)

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=22)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text="Phone Remote", font=("Segoe UI", 22, "bold")).pack(
            anchor="w"
        )
        ttk.Label(
            outer,
            text="Start the secure local server, then enter these details in the Android app.",
            wraplength=540,
        ).pack(anchor="w", pady=(4, 18))

        status_row = ttk.Frame(outer)
        status_row.pack(fill="x", pady=(0, 14))
        ttk.Label(status_row, text="Server status:", font=("Segoe UI", 10, "bold")).pack(
            side="left"
        )
        ttk.Label(status_row, textvariable=self.status).pack(side="left", padx=(8, 0))
        self.start_button = ttk.Button(
            status_row, text="Start server", command=self.start_server
        )
        self.start_button.pack(side="right")
        self.stop_button = ttk.Button(
            status_row, text="Stop server", command=self.stop_server, state="disabled"
        )
        self.stop_button.pack(side="right", padx=(0, 8))

        details = ttk.LabelFrame(outer, text="Connection details", padding=14)
        details.pack(fill="x")
        port_row = ttk.Frame(details)
        port_row.pack(fill="x", pady=5)
        ttk.Label(port_row, text="Server port", width=22).pack(side="left", anchor="w")
        self.port_entry = ttk.Entry(port_row, textvariable=self.port, width=10)
        self.port_entry.pack(side="left", anchor="w")
        self.ip_label = self._detail_row(details, "Laptop IP", "Start the server")
        self.code_label = self._detail_row(details, "Pairing code", "—")
        self.fingerprint_label = self._detail_row(details, "SHA-256 fingerprint", "—")

        ttk.Label(
            outer,
            text=(
                "On your phone, enter the laptop IP, port, pairing code, and fingerprint in "
                "Phone Remote. Compare the fingerprint before connecting. The pairing "
                "code changes each time you start the server."
            ),
            wraplength=540,
            justify="left",
        ).pack(anchor="w", pady=(16, 10))
        ttk.Label(
            outer,
            text=(
                "Use a trusted Wi-Fi network. If Windows Firewall asks, allow this app "
                "on Private networks only. Never expose the selected port to the public internet."
            ),
            wraplength=540,
            justify="left",
        ).pack(anchor="w")
        ttk.Label(
            outer,
            text="Closing this window stops the server. Keep this window open while connected.",
            wraplength=540,
        ).pack(anchor="w", pady=(12, 0))

    def _detail_row(self, parent: ttk.Frame, title: str, initial: str) -> ttk.Label:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=5)
        ttk.Label(row, text=title, width=22).pack(side="left", anchor="n")
        value = ttk.Label(row, text=initial, wraplength=370, justify="left")
        value.pack(side="left", fill="x", expand=True, anchor="w")
        copy_button = ttk.Button(
            row,
            text="Copy",
            command=lambda label=value: self._copy(label.cget("text")),
            state="disabled",
        )
        copy_button.pack(side="right", padx=(8, 0))
        setattr(self, "_copy_" + title.lower().replace(" ", "_"), copy_button)
        return value

    def _copy(self, value: str) -> None:
        if not value or value in ("—", "Start the server"):
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(value)
        self.status.set("Copied to clipboard")

    def start_server(self) -> None:
        if self.server_thread is not None and self.server_thread.is_alive():
            return
        self.start_button.configure(state="disabled")
        self.status.set("Starting…")
        try:
            port = int(self.port.get().strip())
            if port < 1 or port > 65535:
                raise ValueError("Port must be between 1 and 65535")
            tls_context, self.fingerprint, self.pairing_code = (
                server.prepare_server_session(port)
            )
            self.addresses = server.get_lan_ipv4()
            if not self.addresses:
                raise RuntimeError(
                    "No LAN address was found. Connect the laptop to Wi-Fi and try again."
                )
        except Exception as exc:
            self.start_button.configure(state="normal")
            self.status.set("Could not start")
            messagebox.showerror("Phone Remote", str(exc), parent=self.root)
            return

        self.active_port = port
        self.port_entry.configure(state="disabled")
        self.stop_event = threading.Event()
        self.ready_event = threading.Event()
        self.server_thread = server.start_asyncio_thread(
            None,
            self.active_port,
            self.stop_event,
            tls_context,
            self.fingerprint,
            self.pairing_code,
            ready_event=self.ready_event,
            error_callback=lambda error: self.events.put(("error", str(error))),
            show_banner=False,
        )

    def stop_server(self) -> None:
        if self.stop_event is not None:
            self.status.set("Stopping…")
            self.stop_button.configure(state="disabled")
            self.stop_event.set()

    def _poll_server(self) -> None:
        while True:
            try:
                kind, message = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "error":
                self.status.set("Server failed")
                self.start_button.configure(state="normal")
                self.stop_button.configure(state="disabled")
                self.port_entry.configure(state="normal")
                messagebox.showerror("Phone Remote server error", message, parent=self.root)

        if (
            self.ready_event is not None
            and self.ready_event.is_set()
            and not (self.stop_event is not None and self.stop_event.is_set())
        ):
            if self.server_thread is not None and self.server_thread.is_alive():
                self.ip_label.configure(text="  •  ".join(self.addresses))
                self.code_label.configure(text=self.pairing_code)
                self.fingerprint_label.configure(text=self.fingerprint)
                self.status.set("Running")
                self.stop_button.configure(state="normal")
                self.port_entry.configure(state="disabled")
                for title in ("laptop_ip", "pairing_code", "sha-256_fingerprint"):
                    getattr(self, "_copy_" + title).configure(state="normal")
            elif self.status.get() not in ("Server failed", "Stopped"):
                self.status.set("Stopped")
                self.start_button.configure(state="normal")
                self.port_entry.configure(state="normal")
                self._clear_details()

        if self.server_thread is not None and not self.server_thread.is_alive():
            if not self.closing and self.status.get() not in ("Server failed", "Stopped"):
                self.status.set("Stopped")
                self.start_button.configure(state="normal")
                self.stop_button.configure(state="disabled")
                self.port_entry.configure(state="normal")
                self._clear_details()

        if self.closing:
            if self.server_thread is None or not self.server_thread.is_alive():
                self.root.destroy()
                return
        self.root.after(150, self._poll_server)

    def _clear_details(self) -> None:
        self.ip_label.configure(text="Start the server")
        self.code_label.configure(text="—")
        self.fingerprint_label.configure(text="—")
        for title in ("laptop_ip", "pairing_code", "sha-256_fingerprint"):
            getattr(self, "_copy_" + title).configure(state="disabled")
        self.pairing_code = ""
        self.fingerprint = ""

    def close(self) -> None:
        self.closing = True
        if self.stop_event is not None:
            self.stop_event.set()
        if self.server_thread is None or not self.server_thread.is_alive():
            self.root.destroy()


def main() -> None:
    root = tk.Tk()
    PhoneRemoteLauncher(root)
    root.mainloop()


if __name__ == "__main__":
    main()
