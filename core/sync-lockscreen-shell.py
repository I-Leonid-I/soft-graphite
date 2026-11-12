#!/usr/bin/env python3
"""Keep a managed, link-free Plasma shell override for Qt's initial view sizing.

No locker, authentication service, watcher or timer is started. The existing
login/rebuild entry points run this once. User-modified overrides are protected.
"""
import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

MARKER = '.soft-graphite-lockscreen.json'
MAIN = 'contents/lockscreen/LockScreen.qml'


def files(root):
    result = {}
    for p in sorted(root.rglob('*')):
        if p.is_symlink():
            raise RuntimeError('Shell packages must contain real files, not symlinks')
        if p.is_file() and p.name != MARKER:
            result[p.relative_to(root).as_posix()] = p.read_bytes()
    return result


def hashes(data):
    return {name: hashlib.sha256(value).hexdigest() for name, value in data.items()}


def expected(source):
    data = files(source)
    qml = data[MAIN].decode('utf-8')
    qml, width = re.subn(r'(?m)^([ \t]*)implicitWidth:[ \t]*800[ \t]*$', r'\1implicitWidth: Screen.width', qml)
    qml, height = re.subn(r'(?m)^([ \t]*)implicitHeight:[ \t]*600[ \t]*$', r'\1implicitHeight: Screen.height', qml)
    if width == height == 0:
        if re.search(r'implicitWidth:\s*800\b|implicitHeight:\s*600\b', qml):
            raise RuntimeError('Unrecognized formatting of legacy implicit size')
        return None  # Upstream no longer has the legacy implicit size.
    if width != 1 or height != 1:
        raise RuntimeError('Unrecognized lockscreen root; refusing a partial patch')
    if not re.search(r'(?m)^import QtQuick\.Window\b', qml):
        qml, count = re.subn(r'(?m)^(import QtQuick(?:[ \t]+\d+(?:\.\d+)?)?)[ \t]*$', r'\1\nimport QtQuick.Window', qml, count=1)
        if count != 1:
            raise RuntimeError('Cannot locate the QtQuick import')
    data[MAIN] = qml.encode('utf-8')
    return data


def _synchronize(source, destination, work, check):
    want = expected(source)
    exists = destination.exists() or destination.is_symlink()
    if exists:
        if destination.is_symlink():
            raise RuntimeError('Existing shell override is a symlink; refusing to replace it')
        try:
            manifest = json.loads((destination / MARKER).read_text())
        except (OSError, ValueError):
            raise RuntimeError('Existing shell override is not managed by Soft Graphite') from None
        if manifest.get('schema') != 1 or hashes(files(destination)) != manifest.get('files'):
            raise RuntimeError('Existing shell override has local edits; preserving them')
    if want is None and not exists:
        return 'upstream shell needs no implicit-size override'
    if want is not None and exists and hashes(want) == manifest['files']:
        return 'managed lockscreen shell is current'
    if check:
        raise RuntimeError('Managed lockscreen shell needs synchronization')
    work = work or Path(__file__).resolve().parent / 'build-tools'
    work.mkdir(parents=True, exist_ok=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lockscreen-shell-', dir=work) as tmp:
        tmp = Path(tmp)
        stage, old = tmp / 'package', tmp / 'previous'
        if want is not None:
            shutil.copytree(source, stage, symlinks=False)
            (stage / MAIN).write_bytes(want[MAIN])
            (stage / MARKER).write_text(json.dumps({'schema': 1, 'files': hashes(want)}, sort_keys=True, indent=2) + '\n')
        if exists:
            os.replace(destination, old)
        try:
            if want is not None:
                os.replace(stage, destination)
        except BaseException:
            if exists:
                os.replace(old, destination)
            raise
    return 'updated complete lockscreen shell' if want is not None else 'retired override after upstream change'


def synchronize(source, destination, work=None, check=False):
    work = work or Path(__file__).resolve().parent / 'build-tools'
    if check:
        return _synchronize(source, destination, work, True)
    # Login and a package rebuild may overlap. Serialize the directory swap,
    # then re-read the manifest while holding the lock.
    work.mkdir(parents=True, exist_ok=True)
    with (work / 'lockscreen-shell.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _synchronize(source, destination, work, False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, default=Path('/usr/share/plasma/shells/org.kde.plasma.desktop'))
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    p.add_argument('--destination', type=Path, default=data / 'plasma/shells/org.kde.plasma.desktop')
    p.add_argument('--work-dir', type=Path)
    p.add_argument('--check', action='store_true')
    args = p.parse_args()
    try:
        print('Soft Graphite:', synchronize(args.source, args.destination, args.work_dir, args.check))
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        p.exit(1, f'Soft Graphite lockscreen shell: {error}\n')


if __name__ == '__main__':
    main()
