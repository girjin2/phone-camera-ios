#!/usr/bin/env python3
"""Reusable iPhone CSUV transport adapter for ChurchStudio READY8R5 integration.

This module owns only the iPhone localhost TCP/usbmux side:
  HELO/HACK -> PING/PONG -> CSUV packet stream.
It deliberately does not replace READY8R5's MF decoder/GPU path.
"""
from __future__ import annotations
from dataclasses import dataclass
import socket, struct, time
from typing import Iterator, Optional

_HEADER = struct.Struct(">4sBBHIQI")
_MAGIC = b"CSUV"
_MAX_PAYLOAD = 2 * 1024 * 1024

@dataclass(frozen=True)
class CsuvPacket:
    version: int
    packet_type: int
    flags: int
    sequence: int
    pts_us: int
    payload: bytes

    @property
    def keyframe(self) -> bool:
        return self.packet_type == 2 and bool(self.flags & 1)

class IPhoneCsuvClient:
    def __init__(self, host: str = "127.0.0.1", port: int = 39877, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None
        self.last_sequence: Optional[int] = None

    def connect(self) -> None:
        self.close()
        sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        sock.settimeout(self.timeout)
        sock.sendall(b"HELO")
        if self._recv_exact(sock, 4) != b"HACK":
            sock.close(); raise RuntimeError("iPhone HACK mismatch")
        nonce = struct.pack(">Q", time.time_ns() & 0xFFFFFFFFFFFFFFFF)
        sock.sendall(b"PING" + nonce)
        if self._recv_exact(sock, 4) != b"PONG" or self._recv_exact(sock, 8) != nonce:
            sock.close(); raise RuntimeError("iPhone PONG mismatch")
        self.sock = sock
        self.last_sequence = None

    def close(self) -> None:
        if self.sock is not None:
            try: self.sock.close()
            finally: self.sock = None
        self.last_sequence = None

    def packets(self) -> Iterator[CsuvPacket]:
        if self.sock is None:
            raise RuntimeError("connect() first")
        sock = self.sock
        while True:
            raw = self._recv_exact(sock, _HEADER.size)
            magic, version, typ, flags, seq, pts_us, size = _HEADER.unpack(raw)
            if magic != _MAGIC or version != 1:
                raise RuntimeError(f"bad CSUV header magic={magic!r} version={version}")
            if size > _MAX_PAYLOAD:
                raise RuntimeError(f"CSUV payload too large: {size}")
            payload = self._recv_exact(sock, size)
            packet = CsuvPacket(version, typ, flags, seq, pts_us, payload)
            self.last_sequence = seq
            yield packet

    @staticmethod
    def _recv_exact(sock: socket.socket, size: int) -> bytes:
        out = bytearray()
        while len(out) < size:
            chunk = sock.recv(size - len(out))
            if not chunk:
                raise EOFError(f"socket closed at {len(out)}/{size}")
            out.extend(chunk)
        return bytes(out)

    def __enter__(self):
        self.connect(); return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
