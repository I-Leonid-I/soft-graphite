#!/usr/bin/env python3
"""Apply resilient Linux native-frame and top menu integration to Antigravity app.asar."""
import hashlib, json, os, re, struct, sys
from pathlib import Path

p = Path(sys.argv[1])
raw = p.read_bytes()
head = struct.unpack('<4I', raw[:16])
tree = json.loads(raw[16:16+head[3]])
base = 8 + head[1]

script_dir = Path(__file__).resolve().parent
renderer = (script_dir / 'menu-renderer.js').read_text()
extra = (script_dir / 'soft-graphite-menu.js').read_bytes()

def walk(items, parent=''):
    for name, node in items.items():
        rel = parent + name
        if 'files' in node:
            yield from walk(node['files'], rel + '/')
        elif 'offset' in node:
            yield rel, node

payload = bytearray()
changed = []

for name, node in walk(tree['files']):
    old = raw[base+int(node['offset']):base+int(node['offset'])+node['size']]
    new = old

    if name == 'dist/preload.js':
        s = old.decode('utf-8', errors='ignore')
        if 'softGraphiteMenu' not in s:
            s += ("\nif (process.platform === 'linux' && process.isMainFrame) {\n"
                  "electron_1.contextBridge.exposeInMainWorld('softGraphiteMenu', { publish: groups => electron_1.ipcRenderer.invoke('soft-graphite:menu', groups), onAction: callback => { electron_1.ipcRenderer.on('soft-graphite:menu-action', (_event, data) => callback(data)); } });\n"
                  "window.addEventListener('DOMContentLoaded', () => { void electron_1.webFrame.executeJavaScript(" + json.dumps(renderer) + ").catch(() => {}); }, {once:true});\n}\n")
            new = s.encode('utf-8')
            changed.append(name)

    elif name == 'dist/utils.js':
        s = old.decode('utf-8', errors='ignore')
        modified = False
        s_new = re.sub(r"titleBarStyle:\s*['\"]hidden['\"]", "titleBarStyle: process.platform === 'linux' ? 'default' : 'hidden'", s)
        if s_new != s:
            s = s_new
            modified = True
        s_new = re.sub(r"titleBarOverlay:\s*isMacOS\(\)", "titleBarOverlay: isMacOS() || process.platform === 'linux'", s)
        if s_new != s:
            s = s_new
            modified = True
        if "require('./soft-graphite-menu')" not in s:
            s += "\nrequire('./soft-graphite-menu').install();\n"
            modified = True
        if modified:
            new = s.encode('utf-8')
            changed.append(name)

    elif name.startswith('dist/') and name.endswith('.js'):
        s = old.decode('utf-8', errors='ignore')
        if "titleBarStyle: 'hidden'" in s or 'titleBarStyle: "hidden"' in s:
            s_new = re.sub(r"titleBarStyle:\s*['\"]hidden['\"]", "titleBarStyle: process.platform === 'linux' ? 'default' : 'hidden'", s)
            if s_new != s:
                new = s_new.encode('utf-8')
                changed.append(name)

    node['offset'] = str(len(payload))
    node['size'] = len(new)

    if 'integrity' in node:
        info = node['integrity']
        if info.get('algorithm') == 'SHA256':
            info['hash'] = hashlib.sha256(new).hexdigest()
            bs = info.get('blockSize', 4194304)
            info['blocks'] = [hashlib.sha256(new[i:i+bs]).hexdigest() for i in range(0, len(new), bs)]

    payload.extend(new)

# Inject extra soft-graphite-menu.js into dist/
dist_node = tree['files'].setdefault('dist', {'files': {}})
if 'files' not in dist_node:
    dist_node['files'] = {}
dist_node['files']['soft-graphite-menu.js'] = {
    'size': len(extra),
    'offset': str(len(payload))
}
payload.extend(extra)

header = json.dumps(tree, separators=(',', ':'), ensure_ascii=False).encode()
aligned = (len(header) + 3) // 4 * 4
out = struct.pack('<4I', 4, 8 + aligned, 4 + aligned, len(header)) + header + b'\0' * (aligned - len(header)) + payload
tmp = p.with_suffix('.asar.new')
tmp.write_bytes(out)
tmp.chmod(p.stat().st_mode)
os.replace(tmp, p)
print(json.dumps({'patched': changed, 'sha256': hashlib.sha256(out).hexdigest()}))
