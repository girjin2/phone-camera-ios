#!/usr/bin/env python3
import argparse, socket, struct, time, pathlib, sys

HDR = struct.Struct(">4sBBHIQI")
MAGIC=b"CSUV"
CONFIG=1; VIDEO=2; STATUS=3; KEY=1

def recv_exact(s,n):
    b=bytearray()
    while len(b)<n:
        x=s.recv(n-len(b))
        if not x: raise EOFError(f"socket closed with {len(b)}/{n}")
        b+=x
    return bytes(b)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--host",default="127.0.0.1")
    ap.add_argument("--port",type=int,default=39877)
    ap.add_argument("--seconds",type=int,default=30)
    ap.add_argument("--out",default="iphone_capture.h264")
    a=ap.parse_args()
    print(f"connect {a.host}:{a.port}")
    with socket.create_connection((a.host,a.port),timeout=5) as s:
        s.settimeout(5)
        s.sendall(b"HELO")
        if recv_exact(s,4)!=b"HACK": raise RuntimeError("HACK mismatch")
        nonce=struct.pack(">Q", time.time_ns() & 0xffffffffffffffff)
        s.sendall(b"PING"+nonce)
        if recv_exact(s,4)!=b"PONG" or recv_exact(s,8)!=nonce: raise RuntimeError("PONG mismatch")
        print("handshake PASS")
        start=time.monotonic(); config=video=key=status=0; last_seq=None; last_pts=None; bytes_video=0
        out=pathlib.Path(a.out)
        with out.open("wb") as f:
            while time.monotonic()-start < a.seconds:
                hdr=recv_exact(s,HDR.size)
                magic,version,typ,flags,seq,pts,size=HDR.unpack(hdr)
                if magic!=MAGIC or version!=1: raise RuntimeError(f"bad header {magic!r} v={version}")
                if size>2*1024*1024: raise RuntimeError(f"payload too large {size}")
                payload=recv_exact(s,size)
                if last_seq is not None and seq != ((last_seq+1)&0xffffffff):
                    print(f"WARN sequence gap {last_seq}->{seq}")
                last_seq=seq
                if typ==CONFIG:
                    config+=1; f.write(payload)
                    print(f"CONFIG seq={seq} bytes={size}")
                elif typ==VIDEO:
                    video+=1; bytes_video+=size; f.write(payload)
                    if flags&KEY: key+=1
                    if last_pts is not None and pts<=last_pts: print(f"WARN non-monotonic PTS {last_pts}->{pts}")
                    last_pts=pts
                elif typ==STATUS:
                    status+=1
                    print("STATUS", payload.decode("utf-8","replace"))
                else:
                    print("WARN unknown type",typ)
        elapsed=max(0.001,time.monotonic()-start)
        print(f"DONE seconds={elapsed:.1f} config={config} video={video} key={key} status={status} fps={video/elapsed:.1f} bitrate={bytes_video*8/elapsed/1e6:.2f}Mbps out={out}")
        if config < 1 or video < 1:
            return 2
        return 0

if __name__=="__main__":
    raise SystemExit(main())
