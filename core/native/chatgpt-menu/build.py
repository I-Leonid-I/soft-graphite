import subprocess,shlex
from pathlib import Path
p=Path(__file__).resolve().parent;flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Core','Qt6DBus','xcb'],text=True));subprocess.run(['/usr/lib/qt6/moc',str(p/'menu-bridge.cpp'),'-o',str(p/'menu-bridge.moc')],check=True);subprocess.run(['g++','-std=c++20','-O2','-fPIC',str(p/'menu-bridge.cpp'),'-o',str(p/'menu-bridge'),*flags],check=True)
