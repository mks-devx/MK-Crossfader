#!/usr/bin/env python3
"""Check archive metadata that is not retained by payload extraction."""

from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET
import zlib


def audit_container(path):
    with Path(path).open('rb') as stream:
        header = stream.read(28)
        if len(header) != 28:
            raise ValueError('Truncated installer archive header.')
        magic, size, version, compressed, expanded, _ = struct.unpack('>4sHHQQI', header)
        limit = 16 * 1024 * 1024
        if magic != b'xar!' or version != 1 or size < 28 or size > limit:
            raise ValueError('Invalid installer archive header.')
        if not 0 < compressed <= limit or not 0 < expanded <= limit:
            raise ValueError('Invalid installer metadata size.')
        stream.seek(size)
        data = stream.read(compressed)
        if len(data) != compressed:
            raise ValueError('Truncated installer archive metadata.')
    decoder = zlib.decompressobj()
    xml = decoder.decompress(data, expanded + 1)
    if len(xml) != expanded or not decoder.eof or decoder.unused_data:
        raise ValueError('Invalid installer archive metadata stream.')
    root = ET.fromstring(xml)
    files = root.findall('.//file')
    if not files:
        raise ValueError('Installer archive has no files.')
    forbidden = {'user', 'group', 'uid', 'gid', 'deviceno', 'inode'}
    for entry in files:
        if forbidden.intersection(child.tag for child in entry):
            raise ValueError('Local ownership or filesystem identifiers remain in archive metadata.')
    return len(files)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: audit-installer-container.py PACKAGE')
    try:
        count = audit_container(sys.argv[1])
    except (OSError, ValueError, ET.ParseError, zlib.error) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    print(f'Installer container privacy passed for {count} archive entries.')
