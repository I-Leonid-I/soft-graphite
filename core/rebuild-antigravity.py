#!/usr/bin/env python3
"""Automatically rebuild the patched Antigravity application from /opt/Antigravity."""
import json, os, shutil, subprocess, sys
from pathlib import Path

base = Path(__file__).resolve().parent
source = Path('/opt/Antigravity')
apps_dir = base / 'apps'
target = apps_dir / 'antigravity'
staging = apps_dir / 'antigravity.staging'
backup = apps_dir / 'antigravity.old'
version_file = base / 'antigravity-version.json'

TRACKED = ['antigravity', 'resources/app.asar', 'resources/bin/language_server']

def rebuild():
    if not (source / 'antigravity').is_file() or not (source / 'resources/app.asar').is_file():
        print(f"Soft Graphite: {source} does not contain antigravity or app.asar", file=sys.stderr)
        return False

    apps_dir.mkdir(parents=True, exist_ok=True)
    if staging.exists():
        shutil.rmtree(staging, ignore_errors=True)

    print(f"Soft Graphite: Rebuilding patched Antigravity from {source}...", file=sys.stderr)
    try:
        # Use reflink copy for fast and CoW disk storage
        subprocess.run(['cp', '-a', '--reflink=auto', str(source), str(staging)], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Soft Graphite: Failed to copy {source} to {staging}: {e.stderr}", file=sys.stderr)
        return False

    staging_asar = staging / 'resources/app.asar'
    if not staging_asar.is_file():
        print(f"Soft Graphite: {staging_asar} not found after copy", file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    # Apply frame and menu patch
    try:
        patch_py = base / 'native/antigravity/patch-antigravity.py'
        res = subprocess.run([sys.executable, str(patch_py), str(staging_asar)], check=True, capture_output=True, text=True)
        print(f"Soft Graphite: Antigravity patch output: {res.stdout.strip()}", file=sys.stderr)
    except Exception as e:
        print(f"Soft Graphite: Antigravity patch application failed: {e}", file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    # Atomic swap into target
    try:
        if backup.exists():
            shutil.rmtree(backup, ignore_errors=True)
        if target.exists():
            target.rename(backup)
        staging.rename(target)
        if backup.exists():
            shutil.rmtree(backup, ignore_errors=True)
    except Exception as e:
        print(f"Soft Graphite: Failed to swap staged directory into {target}: {e}", file=sys.stderr)
        if backup.exists() and not target.exists():
            backup.rename(target)
        return False

    # Record current version
    try:
        src_stats = {}
        for rel in TRACKED:
            f = source / rel
            if f.exists():
                src_stats[rel] = [f.stat().st_size, f.stat().st_mtime_ns]
        
        patched_stats = {}
        for rel in TRACKED:
            f = target / rel
            if f.exists():
                patched_stats[rel] = [f.stat().st_size, f.stat().st_mtime_ns]

        stamp = {'source': src_stats, 'patched': patched_stats}
        version_file.write_text(json.dumps(stamp, indent=2))
        print("Soft Graphite: Antigravity version stamp recorded.", file=sys.stderr)
    except Exception as e:
        print(f"Soft Graphite: Warning recording version stamp: {e}", file=sys.stderr)

    print("Soft Graphite: Antigravity rebuild completed successfully.", file=sys.stderr)
    return True

if __name__ == '__main__':
    import fcntl
    # The autopatch unit and the launcher can both start a rebuild; they share one staging dir.
    with open(base / f'.{Path(__file__).stem}.lock', 'w') as _lock:
        fcntl.flock(_lock, fcntl.LOCK_EX)
        ok = rebuild()
        sys.exit(0 if ok else 1)
