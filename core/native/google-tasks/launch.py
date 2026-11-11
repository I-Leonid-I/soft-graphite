#!/usr/bin/env python3
"""Use private libkgapi Core/Tasks/Calendar for this Akonadi resource only."""
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

BASE = Path(__file__).resolve().parent
SG = BASE.parent.parent
# Override for an audit/build in the project scratch directory.
WORK = Path(os.environ.get('SOFT_GRAPHITE_GOOGLE_BUILD_DIR',
            str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'soft-graphite/google-tasks')))
LIB = BASE / 'lib'
STAMP = BASE / 'built.json'

def run(args, **kw):
    return subprocess.run([str(a) for a in args], check=True, **kw)

def versions():
    return subprocess.check_output(['pacman', '-Q', 'libkgapi', 'qt6-base', 'kcalendarcore', 'kwallet'], text=True)

def build():
    WORK.mkdir(parents=True, exist_ok=True)
    with (BASE / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = versions()
        if STAMP.exists() and json.loads(STAMP.read_text())['packages'] == current and json.loads(STAMP.read_text()).get('patchLevel') == 7402 and all((LIB / name).exists() for name in ['libKPim6GAPICore.so.6', 'libKPim6GAPITasks.so.6', 'libKPim6GAPICalendar.so.6']):
            return
        package = subprocess.check_output(['pacman', '-Q', 'libkgapi'], text=True).split()[1]
        upstream = package.split(':')[-1].rsplit('-', 1)[0]
        if not re.fullmatch(r'\d+\.\d+\.\d+', upstream):
            raise RuntimeError('Unsupported libkgapi version: ' + package)
        tag = 'v' + upstream
        source = BASE / 'source'
        source_tag = BASE / 'source-tag'
        if not source.is_dir() or not source_tag.exists() or source_tag.read_text().strip() != tag:
            checkout = WORK / 'upstream'
            shutil.rmtree(checkout, ignore_errors=True)
            run(['git', 'clone', '--depth', '1', '--branch', tag, 'https://github.com/KDE/libkgapi.git', checkout], timeout=180)
            # Retain the previous source until a matching upstream checkout exists.
            shutil.rmtree(source, ignore_errors=True)
            shutil.copytree(checkout, source, ignore=shutil.ignore_patterns('.git'))
            (BASE / 'source-tag').write_text(tag + '\n')
        target = source / 'src/tasks/taskfetchjob.cpp'
        code = target.read_text()
        if 'query.addQueryItem(QStringLiteral("showHidden")' not in code:
            anchor = '        if (d->updatedTimestamp > 0) {'
            if code.count(anchor) != 1:
                raise RuntimeError('Upstream changed; review the showHidden patch')
            code = code.replace(anchor, '        if (d->fetchCompleted) {\n            query.addQueryItem(QStringLiteral("showHidden"), QStringLiteral("true"));\n        }\n' + anchor)
            target.write_text(code)
        service = source / 'src/tasks/tasksservice.cpp'
        code = service.read_text()
        anchor = '            feedData.nextPageUrl = fetchAllTasksUrl(taskListId);\n            QUrlQuery query(feedData.nextPageUrl);'
        if anchor in code:
            code = code.replace(anchor, '            feedData.nextPageUrl = fetchAllTasksUrl(taskListId);\n            QUrlQuery query(feedData.requestUrl);\n            query.removeAllQueryItems(PageTokenParam);')
            service.write_text(code)
        elif 'QUrlQuery query(feedData.requestUrl);' not in code:
            raise RuntimeError('Upstream pagination changed; review query preservation')
        calendar = source / 'src/calendar/calendarservice.cpp'
        if 'SOFT_GRAPHITE_ICAL_RECURRENCE' not in calendar.read_text():
            run(['patch', '--batch', '--forward', '-p1', '-i', BASE / 'calendar-recurrence.patch'], cwd=source)
        if 'SOFT_GRAPHITE_JOB_RESOURCES' not in (source / 'src/core/job.cpp').read_text():
            run(['patch', '--batch', '--forward', '-p1', '-i', BASE / 'core-reliability.patch'], cwd=source)
        builddir = WORK / 'private-build'
        run(['cmake', '-S', source, '-B', builddir, '-G', 'Ninja',
             '-DCMAKE_MAKE_PROGRAM=' + str(SG / 'bin/ninja' if (SG / 'bin/ninja').is_file() else shutil.which('ninja') or 'ninja'),
             '-DCMAKE_PREFIX_PATH=' + str(SG / 'build-tools/usr'),
             '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_TESTING=OFF', '-DBUILD_SASL_PLUGIN=OFF',
             '-DCMAKE_SKIP_RPATH=ON'], timeout=180)
        run(['cmake', '--build', builddir, '--target', 'KPim6GAPICore', 'KPim6GAPITasks', 'KPim6GAPICalendar', '-j', '2'], timeout=600)
        if versions() != current:
            raise RuntimeError('Packages changed during the build; retry after update')
        LIB.mkdir(exist_ok=True)
        for name in ['libKPim6GAPICore', 'libKPim6GAPITasks', 'libKPim6GAPICalendar']:
            result = builddir / ('bin/' + name + '.so')
            temporary = LIB / ('.' + name + '.so.6.new')
            shutil.copy2(result.resolve(), temporary)
            os.replace(temporary, LIB / (name + '.so.6'))
        temporary = STAMP.with_suffix('.new')
        temporary.write_text(json.dumps({'packages': current, 'source': tag, 'patchLevel': 7402}, indent=2))
        os.replace(temporary, STAMP)

if __name__ == '__main__':
    try:
        build()
    except Exception as error:
        print('[Soft Graphite Google Tasks] private build unavailable:', error, file=sys.stderr)
        if '--build-only' in sys.argv:
            sys.exit(1)
        # A new upstream ABI must never load an old private library.
        os.execv('/usr/bin/akonadi_google_resource', ['akonadi_google_resource', *sys.argv[1:]])
    if '--build-only' not in sys.argv:
        env = dict(os.environ)
        env['LD_LIBRARY_PATH'] = str(LIB) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        os.execve('/usr/bin/akonadi_google_resource', ['akonadi_google_resource', *sys.argv[1:]], env)
