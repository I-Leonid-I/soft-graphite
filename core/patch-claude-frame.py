#!/usr/bin/env python3
"""Claude Desktop: native (KDE) window frame on Linux.

Under XWayland (needed for the global menu) Electron draws its own translucent shadow and
resize margin around frameless windows (_GTK_FRAME_EXTENTS); the forced KDE frame then wraps
that margin and shows a see-through border. Use the default title bar style on Linux instead,
as done for ChatGPT/Codex and Antigravity. The transparent Quick Entry overlay (frame:false)
is left alone. Matches by pattern, so it survives minified-name changes; idempotent.

usage: patch-claude-frame.py <app.asar>
"""
import json, re, struct, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asar_edit import edit

LINUX = 'process.platform==="linux"'
RULES = [
    # main window
    (re.compile(rb'titleBarStyle:"hidden",titleBarOverlay:!0'),
     f'titleBarStyle:{LINUX}?"default":"hidden",titleBarOverlay:!({LINUX})'.encode()),
    # About and Buddy windows
    (re.compile(rb'titleBarStyle:"hiddenInset"'),
     f'titleBarStyle:{LINUX}?"default":"hiddenInset"'.encode()),
]

def scripts(asar):
    with open(asar, 'rb') as f:
        h = struct.unpack('<4I', f.read(16))
        tree = json.loads(f.read(h[3]))
    def walk(items, parent=''):
        for name, node in items.items():
            rel = parent + name
            if 'files' in node:
                yield from walk(node['files'], rel + '/')
            elif 'offset' in node and rel.startswith('.vite/build/') and rel.endswith('.js'):
                yield rel
    return list(walk(tree['files']))

def main(asar):
    hits = {}
    with open(asar, 'rb') as f:
        h = struct.unpack('<4I', f.read(16))
        tree = json.loads(f.read(h[3]))
        base = 8 + h[1]
        for rel in scripts(asar):
            e = tree
            for seg in rel.split('/'):
                e = e['files'][seg]
            f.seek(base + int(e['offset']))
            data = f.read(e['size'])
            if any(rx.search(data) for rx, _ in RULES):
                hits[rel] = None
    main_found = False
    def patch(old):
        nonlocal main_found
        new = old
        for rx, repl in RULES:
            new, n = rx.subn(repl, new)
            if n and rx is RULES[0][0]:
                main_found = True
        return new
    if hits:
        edit(asar, {rel: patch for rel in hits})
    already = not hits and any(LINUX.encode() + b'?"default"' in b for b in [Path(asar).read_bytes()])
    if not main_found and not already:
        sys.exit('Claude main window title bar pattern not found; leaving the frame unchanged')
    print(json.dumps({'patched': sorted(hits), 'already': already}))

if __name__ == '__main__':
    main(sys.argv[1])
