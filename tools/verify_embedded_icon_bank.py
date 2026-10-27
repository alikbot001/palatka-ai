#!/usr/bin/env python3
"""Verify built byte offsets and SHA-256 of every embedded PNG (desktop only)."""
from pathlib import Path
import base64
import hashlib
import json
import mmap
import re

ROOT = Path(__file__).resolve().parent.parent
meta = json.loads((ROOT / 'data/item_icons.json').read_text(encoding='utf-8'))
assets = dict(meta['items'])
assets.update(meta.get('named', {}))
with (ROOT / 'palatka_ai.lua').open('rb') as stream:
    with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as bank:
        head = bank[:2_000_000].decode('cp1251')
        match = re.search(r'DSP\.item_icon_blob_offset\s*=\s*(\d+)', head)
        assert match, 'missing blob offset'
        offset = int(match.group(1))
        start = head.index('DSP.item_icon_index = {')
        end = head.index('\n}', start)
        pairs = re.findall(r'^\[(\d+|"[^"]+")\]=\{(\d+),(\d+)\},$', head[start:end], re.M)
        assert len(pairs) == len(assets), ('index size', len(pairs), len(assets))
        for key, pos, size in pairs:
            key = json.loads(key) if key.startswith('"') else key
            raw = base64.b64decode(bank[offset + int(pos):offset + int(pos) + int(size)], validate=True)
            assert raw.startswith(b'\x89PNG\r\n\x1a\n'), ('non PNG', key)
            assert hashlib.sha256(raw).hexdigest() == assets[key]['sha256'], ('wrong SHA', key)
            assert len(raw) == assets[key]['bytes'], ('wrong size', key)
            assert bank[offset + int(pos) + int(size):offset + int(pos) + int(size) + 1] == b'\n', ('separator', key)
        assert bank[offset:].startswith(b'iVBOR')
        print(f'Embedded icon bank: {len(pairs)}/{len(assets)} exact PNG SHA-256 and byte offsets: OK')
