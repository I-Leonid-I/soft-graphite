#!/usr/bin/python3
from pathlib import Path
import shlex
import subprocess

p = Path(__file__).resolve().parent
packages = ['Qt6Quick', 'Qt6Widgets', 'Qt6DBus', 'KF6CoreAddons', 'KF6WindowSystem']
includes = shlex.split(subprocess.check_output(['pkg-config', '--cflags', *packages], text=True))
includes += ['-I/usr/include/kwin', '-I/usr/include/KF6/KConfig', '-I/usr/include/KF6/KConfigCore']
defines = ['-DKPLUGINFACTORY_PLUGIN_CLASS_INTERNAL_NAME=softgraphite_outline_resize_factory']
libs = shlex.split(subprocess.check_output(['pkg-config', '--libs', *packages], text=True))
subprocess.run(['/usr/lib/qt6/moc', *defines, *includes, str(p/'outline.cpp'), '-o', str(p/'outline.moc')], check=True)
subprocess.run(['g++', '-std=c++23', '-O2', '-fPIC', '-shared', *defines, *includes,
                str(p/'outline.cpp'), '-o', str(p/'softgraphite_outline_resize.so'), '-lkwin', '-lKF6ConfigCore', *libs], check=True)
print("Built softgraphite_outline_resize.so successfully!")
