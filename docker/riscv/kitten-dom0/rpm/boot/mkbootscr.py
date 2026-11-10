#!/usr/bin/python3
"""Wrap a U-Boot script in a legacy image header, as
`mkimage -A riscv -O linux -T script -C none -n NAME` does, for boot.scr.
Kitten has mkimage only in its devel repository, so the builder writes
the header itself. Layout: struct legacy_img_hdr in U-Boot's
include/image.h; a script image's data is a table of image sizes (one
here) ended by a zero, then the script. The timestamp comes from
SOURCE_DATE_EPOCH, as in mkimage, so the output is reproducible."""

import argparse
import os
import struct
import time
import zlib

IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_RISCV = 26
IH_TYPE_SCRIPT = 6
IH_COMP_NONE = 0
HDR = ">IIIIIIIBBBB32s"


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("-n", "--name", default="", help="image name, 31 bytes max")
    p.add_argument("input")
    p.add_argument("output")
    a = p.parse_args()

    name = a.name.encode()
    if len(name) > 31:
        p.error("name longer than 31 bytes")
    with open(a.input, "rb") as f:
        script = f.read()
    data = struct.pack(">II", len(script), 0) + script
    stamp = int(os.environ.get("SOURCE_DATE_EPOCH", time.time()))
    fields = [
        IH_MAGIC,
        0,
        stamp,
        len(data),
        0,
        0,
        zlib.crc32(data),
        IH_OS_LINUX,
        IH_ARCH_RISCV,
        IH_TYPE_SCRIPT,
        IH_COMP_NONE,
        name,
    ]
    fields[1] = zlib.crc32(struct.pack(HDR, *fields))
    with open(a.output, "wb") as f:
        f.write(struct.pack(HDR, *fields) + data)


if __name__ == "__main__":
    main()
