#!/usr/bin/env python3
"""Rebuild the patched Claude Desktop copy (native KDE frame on Linux) from /usr/lib/claude-desktop.

Run by claude-autopatch.service after a package update and by ~/.local/bin/claude-desktop when
the copy is missing or stale. Reflink copy (Btrfs), patch, atomic swap, version stamp.
"""
import json, shutil, subprocess, sys
from pathlib import Path

base = Path(__file__).resolve().parent
source = Path('/usr/lib/claude-desktop')
apps_dir = base / 'apps'
target = apps_dir / 'claude-desktop'
staging = apps_dir / 'claude-desktop.staging'
backup = apps_dir / 'claude-desktop.old'
version_file = base / 'claude-version.json'
TRACKED = ['claude-desktop', 'resources/app.asar']

def stats(root):
    return {rel: [(root / rel).stat().st_size, (root / rel).stat().st_mtime_ns] for rel in TRACKED if (root / rel).exists()}

def log(msg):
    print(f'Soft Graphite: {msg}', file=sys.stderr, flush=True)

def rebuild():
    if not all((source / rel).is_file() for rel in TRACKED):
        log(f'{source} does not contain claude-desktop and app.asar')
        return False
    apps_dir.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(staging, ignore_errors=True)
    log(f'rebuilding patched Claude Desktop from {source}...')
    try:
        subprocess.run(['cp', '-a', '--reflink=auto', str(source), str(staging)], check=True, capture_output=True, text=True)
        res = subprocess.run([sys.executable, str(base / 'patch-claude-frame.py'), str(staging / 'resources/app.asar')],
                             check=True, capture_output=True, text=True)
        log(f'frame patch: {res.stdout.strip()}')
    except subprocess.CalledProcessError as e:
        log(f'rebuild failed: {(e.stderr or e.stdout or "").strip()}')
        shutil.rmtree(staging, ignore_errors=True)
        return False
    try:
        shutil.rmtree(backup, ignore_errors=True)
        if target.exists():
            target.rename(backup)
        staging.rename(target)
        shutil.rmtree(backup, ignore_errors=True)
    except OSError as e:
        log(f'failed to swap {staging} into {target}: {e}')
        if backup.exists() and not target.exists():
            backup.rename(target)
        return False
    version_file.write_text(json.dumps({'source': stats(source), 'patched': stats(target)}, indent=2))
    log('Claude Desktop rebuild completed.')
    return True

def current():
    """True when the patched copy matches the installed package."""
    try:
        stamp = json.loads(version_file.read_text())
        return stamp['source'] == stats(source) and stamp['patched'] == stats(target)
    except (OSError, ValueError, KeyError):
        return False

if __name__ == '__main__':
    import fcntl
    with open(base / f'.{Path(__file__).stem}.lock', 'w') as _lock:
        fcntl.flock(_lock, fcntl.LOCK_EX)
        if '--check' in sys.argv:
            sys.exit(0 if current() else 1)
        if '--if-stale' in sys.argv and current():
            sys.exit(0)
        sys.exit(0 if rebuild() else 1)
