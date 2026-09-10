#!/usr/bin/env python3
"""Single-pass RAM pattern test. Usage: ram-test.py [MB=512].

Fills memory with zeros, ones, checkerboards and random data (all C-speed
memset/memcmp via bytearray) and verifies every byte. Catches stuck bits
and bad cells; not a replacement for memtest86+, but a real test.
Prints one RAMTEST line for easy parsing. Exit 0 pass, 1 fail.
"""
import os
import sys
import time


def fail(msg):
    print("RAMTEST FAIL " + msg)
    sys.exit(1)


def main():
    mb = int(sys.argv[1]) if len(sys.argv) > 1 else 512
    total = mb * 1024 * 1024
    chunk = 128 * 1024 * 1024
    t0 = time.time()
    tested = 0
    try:
        off = 0
        while off < total:
            size = min(chunk, total - off)
            for pat in (b"\x00", b"\xff", b"\x55", b"\xaa"):
                b = bytearray(pat * size)
                if bytes(b) != pat * size:
                    fail("mismatch pattern %s at %dMB" % (pat.hex(), off // 1048576))
            r = os.urandom(size)
            b = bytearray(r)
            if bytes(b) != r:
                fail("mismatch random at %dMB" % (off // 1048576))
            tested += size
            off += size
    except MemoryError:
        fail("out of memory")
    dt = time.time() - t0
    print("RAMTEST PASS %dMB in %.0fs" % (tested // 1048576, dt))


main()
