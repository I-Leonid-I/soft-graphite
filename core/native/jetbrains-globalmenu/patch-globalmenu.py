#!/usr/bin/env python3
"""Soft Graphite fixes for the JetBrains "Global Menu and Decoration" plugin (io.gitlab.jfronny.globalmenu).

usage: patch-globalmenu.py <plugin dir containing lib/>

1. dbusmenu4j WaylandPanama: bind org_kde_kwin_appmenu_manager on a private Wayland queue.
   Upstream 1.4.1 creates the registry on the display's default queue, which the JBR toolkit
   thread dispatches concurrently; the global events are often lost, so the menu never exports.
   The class is replaced only when it matches the known 1.4.1 build (sha256 below).
2. globalmenu IdeFrameKt.introspect: resolve the native peer of the JFrame instead of its
   lightweight JRootPane (aload_2 -> aload_1). Applied only when the exact byte pattern is found.
3. FrameActivationExport (our class, added to the globalmenu jar and plugin.xml) replaces the
   upstream ApplicationActivationListener registration and exports the menu whenever an IDE frame
   becomes active. Application activation is skipped by IDEA for the first project frame and for
   switches between IDE frames; running both services side by side made them unexport each other.

Idempotent; jars are replaced atomically, so a running IDE keeps its open copy.
"""
import hashlib, os, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
WP_ENTRY = 'dev/jfronny/dbusmenu4j/WaylandPanama.class'
WP_BROKEN = {'bd7f685640e846fcea28da192d4277f85f371d1d40ee26de1dba0b86930cb803'}  # dbusmenu4j 1.4.1
IFK_ENTRY = 'dev/jfronny/globalmenu/reflect/IdeFrameKt.class'
IFK_OLD = bytes.fromhex('bb0014592cc0')  # new IdeFrameIntrospection; dup; aload_2 (JRootPane); checkcast Component
IFK_NEW = bytes.fromhex('bb0014592bc0')  # ... aload_1 (JFrame)
FAE_ENTRY = 'dev/softgraphite/globalmenu/FrameActivationExport.class'
FAE_LISTENER = '<listener class="dev.softgraphite.globalmenu.FrameActivationExport" topic="com.intellij.ide.AppLifecycleListener" />'
GMS_LISTENER = '<listener class="dev.jfronny.globalmenu.GlobalMenuService" topic="com.intellij.openapi.application.ApplicationActivationListener" />'
GMS_DISABLED = f'<!-- Soft Graphite: replaced by FrameActivationExport. {GMS_LISTENER} -->'

def log(msg):
    print(f'globalmenu-patch: {msg}', flush=True)

def javac():
    cands = sorted(Path('/opt').glob('*/jbr/bin/javac')) + [Path('/usr/bin/javac')]
    for c in cands:
        if c.is_file():
            return str(c)
    return None

def fixed_class(lib):
    cls = HERE / 'classes' / WP_ENTRY
    src = HERE / 'WaylandPanama.java'
    if cls.is_file() and cls.stat().st_mtime >= src.stat().st_mtime:
        return cls.read_bytes()
    jc = javac()
    if not jc:
        raise RuntimeError('no javac found to build the fixed WaylandPanama')
    cp = ':'.join(str(j) for j in sorted(lib.glob('*.jar')))
    env = {k: v for k, v in os.environ.items() if k != '_JAVA_OPTIONS'}
    subprocess.run([jc, '--release', '25', '-cp', cp, '-d', str(HERE / 'classes'), str(src)], check=True, env=env)
    return cls.read_bytes()

def ide_classpath():
    for info in sorted(Path('/opt').glob('*/product-info.json')):
        jars = sorted((info.parent / 'lib').glob('*.jar'))
        if jars:
            return jars
    raise RuntimeError('no JetBrains IDE found under /opt to compile against')

def frame_activation_class(lib):
    cls = HERE / 'classes' / FAE_ENTRY
    src = HERE / 'FrameActivationExport.java'
    if cls.is_file() and cls.stat().st_mtime >= src.stat().st_mtime:
        return cls.read_bytes()
    jc = javac()
    if not jc:
        raise RuntimeError('no javac found to build FrameActivationExport')
    cp = ':'.join(str(j) for j in [*ide_classpath(), *sorted(lib.glob('*.jar'))])
    env = {k: v for k, v in os.environ.items() if k != '_JAVA_OPTIONS'}
    subprocess.run([jc, '--release', '21', '-cp', cp, '-d', str(HERE / 'classes'), str(src)], check=True, env=env)
    return cls.read_bytes()

def rewrite(jar, entry, transform, add=None):
    """Return True if the jar was changed. transform(bytes) -> bytes or None (no change).
    add: optional {name: bytes} entries written when missing or different."""
    with zipfile.ZipFile(jar) as zin:
        names = set(zin.namelist())
        data = zin.read(entry)
        new = transform(data)
        extra = {n: b for n, b in (add or {}).items() if n not in names or zin.read(n) != b}
        if (new is None or new == data) and not extra:
            return False
        if new is None:
            new = data
        fd, tmp = tempfile.mkstemp(prefix='.' + jar.name, dir=jar.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(tmp, 'w') as zout:
                for item in zin.infolist():
                    if item.filename in extra:
                        continue
                    zout.writestr(item, new if item.filename == entry else zin.read(item.filename))
                for n, b in extra.items():
                    zout.writestr(zipfile.ZipInfo(n, date_time=(2026, 10, 23, 0, 0, 0)), b, zipfile.ZIP_DEFLATED)
            shutil.copymode(jar, tmp)
            os.replace(tmp, jar)
        except BaseException:
            os.unlink(tmp)
            raise
    return True

def patch(plugin_dir):
    lib = Path(plugin_dir) / 'lib'
    for jar in sorted(lib.glob('dbusmenu4j-*.jar')):
        def t(data):
            h = hashlib.sha256(data).hexdigest()
            if h in WP_BROKEN:
                return fixed_class(lib)
            if data == fixed_class(lib):
                return None
            log(f'{jar.name}: unknown WaylandPanama ({h[:12]}), left unchanged — check whether upstream fixed the queue race')
            return None
        if rewrite(jar, WP_ENTRY, t):
            log(f'{jar.name}: WaylandPanama replaced (private Wayland queue)')
    for jar in sorted(lib.glob('globalmenu-*.jar')):
        if 'searchableOptions' in jar.name:
            continue
        def t(data):
            if IFK_NEW in data and IFK_OLD not in data:
                return None
            if data.count(IFK_OLD) == 1:
                return data.replace(IFK_OLD, IFK_NEW)
            log(f'{jar.name}: IdeFrameKt pattern not found, left unchanged')
            return None
        if rewrite(jar, IFK_ENTRY, t):
            log(f'{jar.name}: IdeFrameKt now resolves the JFrame peer')
        def t(xml):
            text = xml.decode('utf-8')
            if GMS_LISTENER not in text.replace(GMS_DISABLED, ''):
                if FAE_LISTENER not in text:
                    log(f'{jar.name}: upstream listener not found in plugin.xml, frame activation not added')
                return None
            text = text.replace(GMS_LISTENER, GMS_DISABLED, 1)
            if FAE_LISTENER not in text:
                text = text.replace('</applicationListeners>', f'  {FAE_LISTENER}\n  </applicationListeners>', 1)
            return text.encode('utf-8')
        if rewrite(jar, 'META-INF/plugin.xml', t, add={FAE_ENTRY: frame_activation_class(lib)}):
            log(f'{jar.name}: menu export on every IDE frame activation added')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    patch(sys.argv[1])
