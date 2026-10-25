#!/usr/bin/env python3
"""Resilient menu injector for ChatGPT / Codex desktop client."""
import json, struct, sys
from pathlib import Path
from asar_edit import edit

base = Path(__file__).resolve().parent
module = base / 'native/chatgpt-menu/chatgpt-menu.js'

def patch_menu(asar_path):
    p = Path(asar_path)
    main_script = '.vite/build/early-bootstrap.js'
    try:
        with p.open('rb') as f:
            hdr = struct.unpack('<4I', f.read(16))
            j = json.loads(f.read(hdr[3]))
            base_offset = 8 + hdr[1]
            pkg_e = j.get('files', {}).get('package.json')
            if pkg_e:
                f.seek(base_offset + int(pkg_e['offset']))
                pkg = json.loads(f.read(pkg_e['size']))
                main_script = pkg.get('main', main_script)
    except Exception as e:
        print(f"Warning resolving main script from package.json: {e}", file=sys.stderr)

    def patch(old):
        if b'chatgpt-menu.js' in old:
            return old
        return old + ('\n;try{require(' + json.dumps(str(module)) + ').install()}catch(e){console.error("Soft Graphite: native menu adapter unavailable; retaining internal menus.")}\n').encode()

    edit(str(p), {main_script: patch})

if __name__ == '__main__':
    patch_menu(sys.argv[1])
