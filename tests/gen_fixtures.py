#!/usr/bin/env python3
"""Generate synthetic PBZX test fixtures.

PBZX stream format:
  "pbzx"           (4 bytes magic)
  flags            (8 bytes big-endian uint64; bit 24 set = chunks follow)
  [per chunk]:
    flags          (8 bytes; bit 24 set = more chunks after this one)
    length         (8 bytes; 0x1000000 = plain data, else LZMA-compressed)
    data           (length bytes)
"""

import lzma
import os
import struct

FIXTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
BIT24 = 1 << 24


def write_file(name, data):
    path = os.path.join(FIXTURES_DIR, name)
    with open(path, "wb") as f:
        f.write(data)


def u64be(val):
    return struct.pack(">Q", val)


def make_pbzx_stream(chunks):
    """Build a PBZX stream from a list of (is_plain, data_bytes) tuples.

    For LZMA chunks, data_bytes is the raw payload to be XZ-compressed.
    For plain chunks, data_bytes is written directly (length forced to 0x1000000).
    """
    parts = [b"pbzx"]
    if not chunks:
        # No chunks: initial flags without bit 24
        parts.append(u64be(0))
        return b"".join(parts)

    # Initial flags with bit 24 set to enter the loop
    parts.append(u64be(BIT24))

    for i, (is_plain, payload) in enumerate(chunks):
        is_last = (i == len(chunks) - 1)
        # Chunk flags: bit 24 set unless this is the last chunk
        chunk_flags = 0 if is_last else BIT24
        parts.append(u64be(chunk_flags))

        if is_plain:
            # Plain chunks use length == 0x1000000
            parts.append(u64be(0x1000000))
            parts.append(payload)
        else:
            compressed = lzma.compress(payload, format=lzma.FORMAT_XZ)
            parts.append(u64be(len(compressed)))
            parts.append(compressed)

    return b"".join(parts)


def gen_valid_single_lzma():
    """D1: Valid stream with a single LZMA-compressed chunk."""
    payload = b"Hello, pbzx world!\n"
    stream = make_pbzx_stream([(False, payload)])
    write_file("valid_single_lzma.pbzx", stream)
    write_file("valid_single_lzma.expected", payload)


def gen_valid_plain():
    """D2: Valid stream with a single plain chunk.

    The parser reads plain chunks in XBSZ (4096 byte) increments and keeps
    consuming data until the full declared length has been read. Because the
    format uses `length == 0x1000000` to identify a plain chunk, we cannot
    generate a smaller plain fixture without changing the format semantics.

    This fixture therefore intentionally creates the full 16 MiB payload, but
    uses a simple repeating pattern so the data remains deterministic and easy
    to generate.
    """
    # Use a small repeating pattern to keep things manageable
    # 16 MiB = 16777216 bytes
    pattern = b"ABCDEFGHIJKLMNOP"  # 16 bytes
    payload = pattern * (0x1000000 // len(pattern))
    stream = make_pbzx_stream([(True, payload)])
    write_file("valid_plain.pbzx", stream)
    write_file("valid_plain.expected", payload)


def gen_valid_multi_lzma():
    """D3: Valid stream with multiple LZMA-compressed chunks."""
    payloads = [b"chunk one data\n", b"chunk two data\n", b"chunk three data\n"]
    chunks = [(False, p) for p in payloads]
    stream = make_pbzx_stream(chunks)
    write_file("valid_multi_lzma.pbzx", stream)
    write_file("valid_multi_lzma.expected", b"".join(payloads))


def gen_invalid_magic():
    """D4: Stream with wrong magic bytes."""
    data = b"XXXX" + u64be(0)
    write_file("bad_magic.pbzx", data)


def gen_bad_lzma_header():
    """D5: Valid pbzx framing but the LZMA chunk has a wrong XZ header."""
    parts = [b"pbzx"]
    parts.append(u64be(BIT24))
    # One chunk with bad header
    parts.append(u64be(0))  # last chunk flags
    fake_data = b"\x00\x00\x00\x00\x00\x00" + b"\x00" * 50  # not a valid XZ header
    parts.append(u64be(len(fake_data)))
    parts.append(fake_data)
    write_file("bad_lzma_header.pbzx", b"".join(parts))


def gen_bad_lzma_footer():
    """D6: Valid XZ data but with corrupted footer (last 2 bytes != "YZ")."""
    payload = b"test data for footer check\n"
    compressed = lzma.compress(payload, format=lzma.FORMAT_XZ)
    # Corrupt the last 2 bytes (which should be "YZ")
    corrupted = compressed[:-2] + b"XX"

    parts = [b"pbzx"]
    parts.append(u64be(BIT24))
    parts.append(u64be(0))  # last chunk
    parts.append(u64be(len(corrupted)))
    parts.append(corrupted)
    write_file("bad_lzma_footer.pbzx", b"".join(parts))


def gen_empty_payload():
    """D7: Flags without bit 24 set = no chunks."""
    data = b"pbzx" + u64be(0)
    write_file("empty_payload.pbzx", data)


def gen_large_chunk():
    """D10: LZMA chunk with decompressed data larger than XBSZ (4096 bytes).

    This tests the inner while(length) loop that reads in XBSZ increments.
    We create compressed data that is itself larger than 4096 bytes.
    """
    # 32 KB of data to ensure multiple read iterations
    payload = bytes(range(256)) * 128  # 32768 bytes
    stream = make_pbzx_stream([(False, payload)])
    write_file("large_chunk.pbzx", stream)
    write_file("large_chunk.expected", payload)


def gen_corrupt_lzma_body():
    """E2: Valid XZ header but garbage body."""
    xz_header = b"\xfd7zXZ\x00"
    garbage = xz_header + b"\x00" * 100 + b"YZ"

    parts = [b"pbzx"]
    parts.append(u64be(BIT24))
    parts.append(u64be(0))  # last chunk
    parts.append(u64be(len(garbage)))
    parts.append(garbage)
    write_file("corrupt_lzma_body.pbzx", b"".join(parts))


def main():
    os.makedirs(FIXTURES_DIR, exist_ok=True)
    gen_valid_single_lzma()
    gen_valid_plain()
    gen_valid_multi_lzma()
    gen_invalid_magic()
    gen_bad_lzma_header()
    gen_bad_lzma_footer()
    gen_empty_payload()
    gen_large_chunk()
    gen_corrupt_lzma_body()
    print(f"Generated fixtures in {FIXTURES_DIR}")


if __name__ == "__main__":
    main()
