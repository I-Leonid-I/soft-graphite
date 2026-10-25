#!/usr/bin/env python3
"""Launch the tested native-frame build; auto-rebuild after an update."""
import json, os, subprocess, sys
from pathlib import Path

base = Path(__file__).resolve().parent
source = Path('/usr/lib/chatgpt')
launcher = source / 'codex-launcher'
candidate = base / 'apps/chatgpt-menu/codex-launcher'

try:
    current = {n: [(source / n).stat().st_size, (source / n).stat().st_mtime_ns] for n in ['ChatGPT', 'resources/app.asar']}
    tested_file = base / 'codex-frame-version.json'
    tested = json.loads(tested_file.read_text()) if tested_file.is_file() else None

    if current == tested and candidate.is_file():
        launcher = candidate
    else:
        # Version mismatch or candidate missing: auto-rebuild
        print('Soft Graphite: Codex update or missing patch detected; auto-applying native frame and menu...', file=sys.stderr)
        rebuilder = base / 'rebuild-codex.py'
        if rebuilder.is_file():
            res = subprocess.run([sys.executable, str(rebuilder)], capture_output=True, text=True)
            if res.returncode == 0 and candidate.is_file():
                launcher = candidate
                print('Soft Graphite: Native window frame and menu successfully applied.', file=sys.stderr)
            else:
                print(f'Soft Graphite: Auto-rebuild failed:\n{res.stderr}\nUsing unmodified application.', file=sys.stderr)
        else:
            print('Soft Graphite: Rebuild script not found; using unmodified application.', file=sys.stderr)
except Exception as e:
    print(f'Soft Graphite: Launcher check error: {e}; using unmodified application.', file=sys.stderr)

args = [str(launcher)]
if launcher != source / 'codex-launcher':
    # The reviewed native-menu exporter attaches to the existing XWayland window.
    args.append('--ozone-platform=x11')
os.execv(str(launcher), [*args, *sys.argv[1:]])
