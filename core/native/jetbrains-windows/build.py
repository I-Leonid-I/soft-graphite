#!/usr/bin/env python3
"""Rebuild only the two already-audited IDEA classes; never patch an unknown update."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
APP = 'com.jetbrains.IntelliJ-IDEA-Ultimate'
JAR = Path('/var/lib/flatpak/app') / APP / 'current/active/files/lib/intellij.platform.ide.impl.jar'
CLASSES = [
    ('com/intellij/openapi/wm/impl/FrameInfo.class', 'eb6132d9bef4fbf682ef382d3f1f13ba30b9c3f8cd8c6e3bbd3a35e7e3025646', 'PrepareFrameInfo', 'FrameInfo.windowed.class'),
    ('com/intellij/ui/WindowRoundedCornersManager.class', '021fe9d821d2affbe1c219e0e4b808a07073e3681c79d565eb086f3ea81a9135', 'PrepareDialogCorners', 'WindowRoundedCornersManager.system.class'),
]

def java(command, *args):
    subprocess.run(['flatpak', 'run', '--command=/app/jbr/bin/' + command, APP, *map(str,args)], check=True)

with tempfile.TemporaryDirectory(prefix='build-', dir=ROOT) as directory:
    tmp = Path(directory)
    with zipfile.ZipFile(JAR) as archive:
        for entry, digest, tool, output in CLASSES:
            data = archive.read(entry)
            if hashlib.sha256(data).hexdigest() != digest:
                raise SystemExit('Unknown IDEA class: review the update before rebuilding: ' + entry)
            (tmp / Path(entry).name).write_bytes(data)
    java('javac', '-d', tmp, ROOT/'PrepareFrameInfo.java', ROOT/'PrepareDialogCorners.java')
    java('javac', '--release', '17', '-d', tmp, ROOT/'WindowedStartAgent.java')
    for entry, digest, tool, output in CLASSES:
        java('java', '-cp', str(tmp)+':/app/lib/*', tool, tmp/Path(entry).name, tmp/output)
    new = ROOT / 'windowed-start.jar.new'
    with zipfile.ZipFile(new, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nPremain-Class: WindowedStartAgent\n\n')
        for item in list(tmp.glob('WindowedStartAgent*.class')) + [tmp/output for _,_,_,output in CLASSES]:
            archive.write(item, item.name)
    new.replace(ROOT/'windowed-start.jar')
print('Rebuilt verified adapter. No running IDE or installed vmoptions were changed.')
