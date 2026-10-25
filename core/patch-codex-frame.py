#!/usr/bin/env python3
"""Resilient window-frame patcher for ChatGPT / Codex desktop client."""
import json, struct, hashlib, sys, shutil, os, re
from pathlib import Path

def patch_frame(asar_path):
    p = Path(asar_path)
    temp = p.with_suffix('.asar.new')
    with p.open('rb') as f:
        hdr = struct.unpack('<4I', f.read(16))
        j = json.loads(f.read(hdr[3]))
        base = 8 + hdr[1]

        # Locate main entry script
        main_entry = None
        main_name = None
        build_files = j.get('files', {}).get('.vite', {}).get('files', {}).get('build', {}).get('files', {})
        for name in build_files:
            if name.startswith('main-') and name.endswith('.js'):
                main_entry = build_files[name]
                main_name = name
                break

        if not main_entry:
            def search_main(d, path=""):
                for k, v in d.items():
                    if 'files' in v:
                        res = search_main(v['files'], f"{path}/{k}" if path else k)
                        if res: return res
                    elif (k.startswith('main-') or k == 'main.js') and k.endswith('.js'):
                        return v, f"{path}/{k}" if path else k
                return None
            found = search_main(j.get('files', {}))
            assert found, "Could not find main-*.js in app.asar"
            main_entry, main_name = found

        f.seek(base + int(main_entry['offset']))
        old = f.read(main_entry['size'])
        s = old.decode('utf-8', errors='surrogateescape')

        changes = 0

        # 1. Patch titleBarStyle: 'hidden', titleBarOverlay: ... -> 'default'
        overlay_pattern = re.compile(r"titleBarStyle:[`\x22\x27]hidden[`\x22\x27],titleBarOverlay:[A-Za-z0-9_$]+\([A-Za-z0-9_$]+\)")
        matches = list(overlay_pattern.finditer(s))
        if matches:
            for m in reversed(matches):
                chunk = m.group(0)
                replacement = 'titleBarStyle:`default`'.ljust(len(chunk))
                s = s[:m.start()] + replacement + s[m.end():]
                changes += 1

        # 2. Patch setWindowZoom (disable overlay for Linux)
        for m in re.finditer(r"setWindowZoom\s*\([^)]*\)\s*\{", s):
            start = m.start()
            end = s.find("}", start)
            chunk = s[start:end]
            m_linux = re.search(r"\|\|process\.platform===[`\x22\x27]linux[`\x22\x27]", chunk)
            if m_linux:
                l_start = start + m_linux.start()
                l_end = start + m_linux.end()
                s = s[:l_start] + (' ' * len(m_linux.group(0))) + s[l_end:]
                changes += 1
                break

        # 3. Patch installApplicationMenuTitleBarOverlaySync (disable overlay for Linux)
        for m in re.finditer(r"installApplicationMenuTitleBarOverlaySync\s*\([^)]*\)\s*\{", s):
            start = m.start()
            end = s.find("}", start)
            chunk = s[start:end]
            m_linux = re.search(r"&&process\.platform!==[`\x22\x27]linux[`\x22\x27]", chunk)
            if m_linux:
                l_start = start + m_linux.start()
                l_end = start + m_linux.end()
                s = s[:l_start] + (' ' * len(m_linux.group(0))) + s[l_end:]
                changes += 1
                break

        # 4. Suppress forced maximized on launch
        m_max = re.search(r",([a-zA-Z0-9_$]+)\)\{this\.pendingRestoredMaximization\.add", s)
        if m_max:
            var_name = m_max.group(1)
            repl = '0'.ljust(len(var_name))
            target = f",{var_name}){{this.pendingRestoredMaximization.add"
            replacement = f",{repl}){{this.pendingRestoredMaximization.add"
            s = s.replace(target, replacement, 1)
            changes += 1
        elif 'k&&R.once(`ready-to-show`' in s:
            s = s.replace('k&&R.once(`ready-to-show`', '0&&R.once(`ready-to-show`', 1)
            changes += 1

        new = s.encode('utf-8', errors='surrogateescape')
        assert len(old) == len(new), f"Length mismatch: {len(old)} != {len(new)}"

        integrity = main_entry.get('integrity')
        if integrity and integrity.get('algorithm') == 'SHA256':
            integrity['hash'] = hashlib.sha256(new).hexdigest()
            bs = integrity['blockSize']
            integrity['blocks'] = [hashlib.sha256(new[i:i+bs]).hexdigest() for i in range(0, len(new), bs)]

        js = json.dumps(j, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
        aligned = (len(js) + 3) // 4 * 4
        header = struct.pack('<4I', 4, 8 + aligned, 4 + aligned, len(js)) + js + b'\0' * (aligned - len(js))

        with temp.open('wb') as out:
            out.write(header)
            f.seek(base)
            shutil.copyfileobj(f, out)
            out.seek(len(header) + int(main_entry['offset']))
            out.write(new)

        os.chmod(temp, p.stat().st_mode)
        temp.replace(p)
        print(json.dumps({'entry': main_name, 'changes': changes}))

if __name__ == '__main__':
    patch_frame(sys.argv[1])
