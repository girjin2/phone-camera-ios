# CSUV wire contract (Android V3.8.7 compatible)

Header is exactly 24 bytes, big-endian:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | ASCII `CSUV` |
| 4 | 1 | version = 1 |
| 5 | 1 | type: CONFIG=1, VIDEO=2, STATUS=3 |
| 6 | 2 | flags; bit0 = keyframe |
| 8 | 4 | sequence (u32) |
| 12 | 8 | PTS microseconds (u64) |
| 20 | 4 | payload bytes (u32) |

Handshake before video:

- Host sends `HELO`; phone replies `HACK`.
- Host sends `PING` + 8-byte big-endian nonce; phone replies `PONG` + exact nonce.
- Phone then sends cached H.264 CONFIG (Annex-B SPS/PPS), requests an IDR, then VIDEO packets.

H.264 payloads use Annex-B start codes (`00 00 00 01`).
