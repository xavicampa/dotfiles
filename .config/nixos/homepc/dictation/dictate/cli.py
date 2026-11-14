"""dictate CLI — thin client for the daemon's unix socket."""

from __future__ import annotations

import os
import socket
import sys

from . import __version__

COMMANDS = {"start-capture": "start", "stop-capture": "stop", "status": "status"}


def socket_path() -> str:
    return os.environ.get(
        "DICTATE_SOCKET", os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "dictate.sock")
    )


def send(command: str) -> tuple[int, str]:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect(socket_path())
    except OSError:
        return 1, "daemon is not running (systemctl --user status dictate)"
    try:
        s.sendall(command.encode() + b"\n")
        reply = s.recv(65536).decode("utf-8", "replace").strip()
    except OSError as e:  # noqa: BLE001 - daemon died mid-command or reply timed out
        return 1, f"ERR communication with the daemon failed: {e}"
    finally:
        s.close()
    if not reply:  # daemon died between connect and reply
        return 1, "ERR no reply (daemon died mid-command?)"
    return (1 if reply.startswith("ERR") else 0), reply


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help"):
        print("usage: dictate {daemon|start-capture|stop-capture|status} [--version]")
        return 0
    if argv[0] == "--version":
        print(__version__)
        return 0
    if argv[0] == "daemon":
        from .daemon import run
        run()  # does not return
        return 0
    if argv[0] not in COMMANDS:
        print(f"unknown command: {argv[0]}", file=sys.stderr)
        return 2
    code, reply = send(COMMANDS[argv[0]])
    print(reply)
    return code


if __name__ == "__main__":
    sys.exit(main())
