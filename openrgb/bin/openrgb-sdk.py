#!/usr/bin/env python3
"""Talk to the resident OpenRGB server (port 6743).
  openrgb-sdk.py wait [seconds]            wait until the server has finished device detection
  openrgb-sdk.py load NAME [wait-seconds]  load a saved OpenRGB profile (waits for the server first)
Exit code 0 = ok, 1 = server not reachable/ready in time."""
import socket, struct, sys, time

PORT = 6743
H = struct.Struct('<4sIII')


def rx_exact(s, n):
    buf = b''
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise IOError('closed')
        buf += chunk
    return buf


def ready_count(timeout=3):
    """Number of devices the server reports, or 0/None if it is not answering yet."""
    try:
        s = socket.create_connection(('127.0.0.1', PORT), timeout=timeout)
        s.settimeout(timeout)
        s.sendall(H.pack(b'ORGB', 0, 0, 0))
        _, _, _, n = H.unpack(rx_exact(s, 16))
        data = rx_exact(s, n)
        s.close()
        return struct.unpack('<I', data)[0]
    except (OSError, struct.error):
        return None


def wait_ready(seconds):
    end = time.time() + seconds
    while time.time() < end:
        if (ready_count() or 0) >= 3:      # board + RAM + mouse(s) detected
            return True
        time.sleep(1)
    return False


def load(name):
    s = socket.create_connection(('127.0.0.1', PORT), timeout=10)
    s.sendall(H.pack(b'ORGB', 0, 50, 7) + b'setter\0')
    data = name.encode() + b'\0'
    s.sendall(H.pack(b'ORGB', 0, 152, len(data)) + data)   # REQUEST_LOAD_PROFILE
    time.sleep(0.3)
    s.close()


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'wait':
        sys.exit(0 if wait_ready(int(sys.argv[2]) if len(sys.argv) > 2 else 120) else 1)
    if cmd == 'load':
        if not wait_ready(int(sys.argv[3]) if len(sys.argv) > 3 else 5):
            sys.exit(1)
        load(sys.argv[2])
        sys.exit(0)
    print(__doc__); sys.exit(2)
