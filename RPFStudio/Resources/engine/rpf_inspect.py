#!/usr/bin/env python3
"""Initial RPF file inspector. This is not an RPF7 extractor or writer."""

import hashlib
import os
import struct
import sys


def inspect(path: str) -> None:
    if not os.path.isfile(path):
        raise FileNotFoundError(path)

    size = os.path.getsize(path)
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        first = stream.read(64)
        digest.update(first)
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)

    print("RPF STUDIO / PYTHON RUNTIME")
    print("=" * 34)
    print("Python:", sys.version.split()[0])
    print("File:", os.path.basename(path))
    print("Size:", f"{size:,}", "bytes")
    print("SHA256:", digest.hexdigest())
    print("First 16 bytes:", first[:16].hex(" "))
    if len(first) >= 16:
        magic = first[:4]
        print("Magic bytes:", magic.hex(" "))
        if magic == b"7FPR":
            words = struct.unpack("<III", first[4:16])
            print("Header words (raw LE):", ", ".join(hex(x) for x in words))
            print("Recognized signature: RPF7")
            print("Note: header fields are reported raw; no TOC parsing is claimed.")
        else:
            print("Recognized signature: not RPF7")
    print()
    print("Inspection complete. No archive data was modified.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: rpf_inspect.py <file.rpf>")
    inspect(sys.argv[1])
