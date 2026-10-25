#!/usr/bin/env python3
"""Launch patched Antigravity with native frame & global menu, auto-rebuilding on upstream update."""
import json, os, subprocess, sys
from pathlib import Path

base = Path(__file__).resolve().parent
source = Path('/opt/Antigravity')
target = source / 'antigravity'
patched = base / 'apps/antigravity'
candidate = patched / 'antigravity'
version_file = base / 'antigravity-version.json'

needs_rebuild = False

try:
    if not candidate.is_file() or not version_file.is_file():
        needs_rebuild = True
    else:
        manifest = json.loads(version_file.read_text())
        expected = manifest.get('source', {})
        current = {n: [(source / n).stat().st_size, (source / n).stat().st_mtime_ns] for n in expected if (source / n).exists()}
        actual_copy = {n: [(patched / n).stat().st_size, (patched / n).stat().st_mtime_ns] for n in manifest.get('patched', {}) if (patched / n).exists()}
        if current != expected or actual_copy != manifest.get('patched', {}):
            needs_rebuild = True
except Exception:
    needs_rebuild = True

if needs_rebuild:
    rebuild_py = base / 'rebuild-antigravity.py'
    if rebuild_py.is_file():
        try:
            print("Soft Graphite: Antigravity update detected; rebuilding patched app...", file=sys.stderr)
            res = subprocess.run([sys.executable, str(rebuild_py)], capture_output=True, text=True)
            if res.returncode == 0 and candidate.is_file():
                target = candidate
            else:
                print(f"Soft Graphite: Rebuild failed ({res.stderr.strip()}); falling back to upstream.", file=sys.stderr)
        except Exception as e:
            print(f"Soft Graphite: Rebuild execution error ({e}); falling back to upstream.", file=sys.stderr)
    else:
        print("Soft Graphite: rebuild-antigravity.py not found; using upstream build.", file=sys.stderr)
elif candidate.is_file():
    target = candidate

env = os.environ.copy()
if not Path('/usr/lib/libdbusmenu-glib.so.4').exists():
    private = str(base / 'appmenu/lib')
    prior = env.get('LD_LIBRARY_PATH')
    env['LD_LIBRARY_PATH'] = private + (':' + prior if prior else '')

os.execve(str(target), [str(target), '--ozone-platform=x11', *sys.argv[1:]], env)
