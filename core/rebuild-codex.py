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

def source_version():
    return {n: [(source / n).stat().st_size, (source / n).stat().st_mtime_ns]
            for n in ['ChatGPT', 'resources/app.asar']}

def is_current():
    try:
        return (target / 'codex-launcher').is_file() and json.loads(version_file.read_text()) == source_version()
    except (OSError, ValueError):
        return False

def running_main_pids():
    # Inspect processes once on rebuild/launch, never poll in the background.
    executable = str(target / 'ChatGPT')
    found = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            if os.readlink(proc / 'exe').removesuffix(' (deleted)') == executable and not any(b'--type=' in a for a in args):
                found.append(int(proc.name))
        except (OSError, PermissionError):
            pass
    return found

def rebuild():
    if Path('/var/lib/pacman/db.lck').exists():
        print('Soft Graphite: Package transaction is active; rebuild deferred until transaction completes.', file=sys.stderr)
        return True
    if is_current():
        print('Soft Graphite: Codex patch is current; no rebuild needed.', file=sys.stderr)
        return True
    running = running_main_pids()
    if running:
        print(f'Soft Graphite: Codex is running (PID {running}); update deferred until next full launch.', file=sys.stderr)
        return True
    if not (source / 'ChatGPT').is_file() or not (source / 'resources/app.asar').is_file():
        print(f"Soft Graphite: {source} does not contain ChatGPT or app.asar", file=sys.stderr)
        return False

    expected_version = source_version()
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

    if source_version() != expected_version:
        print('Soft Graphite: Package changed during copy; retaining previous build.', file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    staging_asar = staging / 'resources/app.asar'
    if not staging_asar.is_file():
        print(f"Soft Graphite: {staging_asar} not found after copy", file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    # Apply frame patch
    try:
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
        detail = getattr(e, "stderr", "")
        print(f"Soft Graphite: Patch application failed: {e}\n{detail}", file=sys.stderr)
        shutil.rmtree(staging, ignore_errors=True)
        return False

    if source_version() != expected_version or running_main_pids():
        print('Soft Graphite: Source or running state changed; retaining previous build.', file=sys.stderr)
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
        version_temp = version_file.with_suffix('.json.new')
        version_temp.write_text(json.dumps(expected_version))
        version_temp.replace(version_file)
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
