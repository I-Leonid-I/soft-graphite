#!/usr/bin/env python3
"""Keep the patched Global Menu plugin linked into every JetBrains IDE (IDEA, CLion, PyCharm, ...).

Runs from jetbrains-plugin-sync.path (new IDE directories), start-kwin.py and rebuild-all.py.
- ~/.local/share/JetBrains/<Product><Year>.<N>/globalmenu -> soft-graphite/plugins/globalmenu
- if an IDE replaced the link with its own copy (plugin update), that copy is patched too
- the plugin id is removed from disabled_plugins.txt of each IDE config
"""
import re, subprocess, sys
from pathlib import Path

HOME = Path.home()
BASE = HOME / '.local/share/soft-graphite'
MASTER = BASE / 'plugins/globalmenu'
PATCHER = BASE / 'native/jetbrains-globalmenu/patch-globalmenu.py'
JB_SHARE = HOME / '.local/share/JetBrains'
JB_CONFIG = HOME / '.config/JetBrains'
PLUGIN_ID = 'io.gitlab.jfronny.globalmenu'
IDE_DIR = re.compile(r'^[A-Za-z]+\d{4}\.\d+$')  # IntelliJIdea2026.2, CLion2026.1, PyCharm2026.2 ...

def ide_dirs(root):
    return [d for d in root.iterdir() if d.is_dir() and IDE_DIR.match(d.name)] if root.is_dir() else []

def patch(plugin_dir):
    r = subprocess.run([sys.executable, str(PATCHER), str(plugin_dir)], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    if out:
        print(out, file=sys.stderr if r.returncode else sys.stdout)

def main():
    if not MASTER.is_dir():
        sys.exit(f'Master plugin directory not found: {MASTER}')
    patch(MASTER)
    for ide in ide_dirs(JB_SHARE):
        link = ide / 'globalmenu'
        if link.is_symlink():
            if link.resolve() != MASTER.resolve():
                link.unlink()
                link.symlink_to(MASTER)
                print(f'Relinked {link}')
        elif link.is_dir():
            patch(link)  # the IDE installed its own (possibly updated) copy
        else:
            link.symlink_to(MASTER)
            print(f'Linked {link}')
    for ide in ide_dirs(JB_CONFIG):
        disabled = ide / 'disabled_plugins.txt'
        if disabled.is_file():
            lines = disabled.read_text().splitlines()
            kept = [l for l in lines if l.strip() != PLUGIN_ID]
            if kept != lines:
                disabled.write_text(''.join(l + '\n' for l in kept))
                print(f'Enabled {PLUGIN_ID} in {ide.name}')

if __name__ == '__main__':
    main()
