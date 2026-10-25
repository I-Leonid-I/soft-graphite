#!/usr/bin/env python3
"""Automatically rebuild the patched Codex application from /usr/lib/chatgpt."""
import json, os, shutil, subprocess, sys
from pathlib import Path

base = Path(__file__).resolve().parent
source = Path('/usr/lib/chatgpt')
apps_dir = base / 'apps'
target = apps_dir / 'chatgpt-menu'
staging = apps_dir / 'chatgpt-menu.staging'
backup = apps_dir / 'chatgpt-menu.old'
version_file = base / 'codex-frame-version.json'

def rebuild():
    if not (source / 'ChatGPT').is_file() or not (source / 'resources/app.asar').is_file():
        print(f"Soft Graphite: {source} does not contain ChatGPT or app.asar", file=sys.stderr)
        return False

    apps_dir.mkdir(parents=True, exist_ok=True)
    if staging.exists():
        shutil.rmtree(staging, ignore_errors=True)

    print(f"Soft Graphite: Rebuilding patched Codex from {source}...", file=sys.stderr)
    try:
        # Use reflink copy for speed and zero duplicate disk consumption
        res = subprocess.run(['cp', '-a', '--reflink=auto', str(source), str(staging)], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Soft Graphite: Failed to copy {source} to {staging}: {e.stderr}", file=sys.stderr)
        return False

    staging_asar = staging / 'resources/app.asar'
    if not staging_asar.is_file():
        print(f"Soft Graphite: {staging_asar} not found after copy", file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    # Apply frame patch
    try:
        from pathlib import Path
        sys.path.insert(0, str(base))
        import importlib.util
        
        # Run patch-codex-frame
        frame_py = base / 'patch-codex-frame.py'
        res = subprocess.run([sys.executable, str(frame_py), str(staging_asar)], check=True, capture_output=True, text=True)
        print(f"Soft Graphite: Frame patch: {res.stdout.strip()}", file=sys.stderr)
        
        # Run patch-codex-menu
        menu_py = base / 'patch-codex-menu.py'
        res = subprocess.run([sys.executable, str(menu_py), str(staging_asar)], check=True, capture_output=True, text=True)
        if res.stdout.strip():
            print(f"Soft Graphite: Menu patch: {res.stdout.strip()}", file=sys.stderr)

    except Exception as e:
        print(f"Soft Graphite: Patch application failed: {e}", file=sys.stderr)
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
        current = {n: [(source / n).stat().st_size, (source / n).stat().st_mtime_ns] for n in ['ChatGPT', 'resources/app.asar']}
        version_file.write_text(json.dumps(current))
    except Exception as e:
        print(f"Soft Graphite: Warning recording version: {e}", file=sys.stderr)

    print("Soft Graphite: Codex rebuild completed successfully.", file=sys.stderr)
    return True

if __name__ == '__main__':
    import fcntl
    # The autopatch unit and the launcher can both start a rebuild; they share one staging dir.
    with open(base / f'.{Path(__file__).stem}.lock', 'w') as _lock:
        fcntl.flock(_lock, fcntl.LOCK_EX)
        ok = rebuild()
        sys.exit(0 if ok else 1)
