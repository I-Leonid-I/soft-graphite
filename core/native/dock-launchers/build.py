from pathlib import Path
import subprocess,shlex
p=Path(__file__).resolve().parent
includes=shlex.split(subprocess.check_output(['pkg-config','--cflags','Qt6Qml','Qt6Core'],text=True))
subprocess.run(['/usr/lib/qt6/moc',*includes,str(p/'launcher-sync.cpp'),'-o',str(p/'launcher-sync.moc')],check=True)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Qml','Qt6Core'],text=True))
subprocess.run(['g++','-std=c++20','-O2','-shared','-fPIC',str(p/'launcher-sync.cpp'),'-o',str(p/'libGraphiteLauncherSync.so'),'-I/usr/include/KF6/KConfig','-I/usr/include/KF6/KConfigCore',*flags,'-lKF6ConfigCore'],check=True)
