#!/usr/bin/env python3
"""Patch native frames in the application bundle, regardless of chunk names."""
import json
import re
import struct
import sys
from pathlib import Path
from asar_edit import edit

OVERLAY = re.compile(r'titleBarStyle:[`\"\x27]hidden[`\"\x27],titleBarOverlay:[A-Za-z0-9_$]+\([A-Za-z0-9_$]+\)')

def patch_source(old):
    s = old.decode('utf-8')
    s, frames = OVERLAY.subn('titleBarStyle:"default"', s)
    # Both minifier comparison orders occur in supported releases.
    for name, patterns in {
        'setWindowZoom': [r'\|\|process\.platform===[`\"\x27]linux[`\"\x27]', r'\|\|[`\"\x27]linux[`\"\x27]===process\.platform'],
        'installApplicationMenuTitleBarOverlaySync': [r'&&process\.platform!==[`\"\x27]linux[`\"\x27]', r'&&[`\"\x27]linux[`\"\x27]!==process\.platform'],
    }.items():
        match = re.search(r'\b' + name + r'\s*\([^)]*\)\s*\{', s)
        if match:
            end = s.index('}', match.end())
            chunk = s[match.start():end]
            for pattern in patterns:
                chunk = re.sub(pattern, '', chunk)
            s = s[:match.start()] + chunk + s[end:]
    s = re.sub(r',([A-Za-z0-9_$]+)\)\{this\.pendingRestoredMaximization\.add', r',0){this.pendingRestoredMaximization.add', s, count=1)
    s = s.replace('k&&R.once(`ready-to-show`', '0&&R.once(`ready-to-show`', 1)
    return s.encode('utf-8'), frames

def patch_frame(asar_path):
    changes = {}
    total = 0
    with Path(asar_path).open('rb') as f:
        h = struct.unpack('<4I', f.read(16))
        header = json.loads(f.read(h[3]))
        base = 8 + h[1]
        build = header['files']['.vite']['files']['build']['files']
        for name, entry in build.items():
            if not name.endswith('.js') or entry.get('unpacked') or 'offset' not in entry:
                continue
            f.seek(base + int(entry['offset']))
            old = f.read(entry['size'])
            if b'titleBarStyle:' not in old or b'installApplicationMenuTitleBarOverlaySync' not in old:
                continue
            new, frames = patch_source(old)
            if not frames and b'titleBarStyle:"default"' not in old:
                raise RuntimeError(f'Unrecognized window frame options in {name}')
            if new != old:
                changes['.vite/build/' + name] = lambda _old, result=new: result
            total += 1
    if total != 1:
        raise RuntimeError(f'Expected one window manager bundle, found {total}; archive unchanged')
    if changes:
        edit(asar_path, changes)
    print(json.dumps({'entries': list(changes), 'window_manager_bundles': total}))

if __name__ == '__main__':
    patch_frame(sys.argv[1])
