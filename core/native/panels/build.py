#!/usr/bin/python3
from pathlib import Path
import shlex
import subprocess
p=Path(__file__).resolve().parent
packages=['Qt6Quick','Qt6Widgets','Qt6DBus','KF6WindowSystem']
includes=shlex.split(subprocess.check_output(['pkg-config','--cflags',*packages],text=True))
includes.extend(["-I/usr/include/KF6/KConfig", "-I/usr/include/KF6/KConfigCore"])
libs=shlex.split(subprocess.check_output(['pkg-config','--libs',*packages],text=True))
subprocess.run(['/usr/lib/qt6/moc',*includes,str(p/'panel-tools.cpp'),'-o',str(p/'panel-tools.moc')],check=True)
subprocess.run(['g++','-std=c++20','-O2','-fPIC','-shared',*includes,str(p/'panel-tools.cpp'),'-o',str(p/'libGraphitePanelTools.so'),*libs,'-lLayerShellQtInterface','-lKF6ConfigCore'],check=True)
