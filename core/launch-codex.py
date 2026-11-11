#!/usr/bin/env python3
"""Serialize launch with autopatch; never replace files under a running Codex."""
import fcntl
import importlib.util
import os
import sys
from pathlib import Path

base = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sg_codex_rebuild', base / 'rebuild-codex.py')
rebuilder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rebuilder)
launcher = rebuilder.source / 'codex-launcher'
candidate = rebuilder.target / 'codex-launcher'
with open(base / '.rebuild-codex.lock', 'w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        if not rebuilder.is_current():
            if rebuilder.running_main_pids() and candidate.is_file():
                print('Soft Graphite: Opening existing Codex; updated files will apply on next full launch.', file=sys.stderr)
                launcher = candidate
            elif rebuilder.rebuild() and rebuilder.is_current():
                launcher = candidate
        else:
            launcher = candidate
    except Exception as error:
        print(f'Soft Graphite: Patch check failed: {error}; using original app.', file=sys.stderr)
    args = [str(launcher)]
    if launcher == candidate:
        args.append('--ozone-platform=x11')
    # flock has close-on-exec: release it only as the new executable starts.
    os.execv(str(launcher), [*args, *sys.argv[1:]])
