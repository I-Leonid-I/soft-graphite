from pathlib import Path
import importlib.util,tempfile,json
import argparse
p=argparse.ArgumentParser();p.add_argument('--work-dir',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[1];work=args.work_dir or root/'scratch';work.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('sync',root/'core/sync-lockscreen-shell.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory(dir=work) as t:
 t=Path(t);src=t/'source';(src/'contents/lockscreen').mkdir(parents=True);(src/'contents/logout').mkdir();(src/m.MAIN).write_text('import QtQuick\n\nItem {\n implicitWidth: 800\n implicitHeight: 600\n}\n');(src/'contents/logout/Logout.qml').write_text('unchanged');dst=t/'dest';work=t/'work'
 from concurrent.futures import ThreadPoolExecutor
 with ThreadPoolExecutor(max_workers=3) as pool:
  answers=list(pool.map(lambda _:m.synchronize(src,dst,work),range(3)))
 assert sum('updated' in a for a in answers)==1,answers
 assert 'current' in m.synchronize(src,dst,work);assert (dst/'contents/logout/Logout.qml').read_text()=='unchanged';assert 'Screen.width' in (dst/m.MAIN).read_text();assert 'current' in m.synchronize(src,dst,work,True)
 (src/'contents/logout/Logout.qml').write_text('upstream update');assert 'updated' in m.synchronize(src,dst,work);assert (dst/'contents/logout/Logout.qml').read_text()=='upstream update'
 (dst/'contents/logout/Logout.qml').write_text('user edit')
 try:m.synchronize(src,dst,work);raise AssertionError('local edits overwritten')
 except RuntimeError:pass
 assert (dst/'contents/logout/Logout.qml').read_text()=='user edit'
 (dst/'contents/logout/Logout.qml').write_text('upstream update');(src/m.MAIN).write_text('import QtQuick\nItem { implicitWidth: 1920; implicitHeight: 1080 }\n');assert 'retired' in m.synchronize(src,dst,work);assert not dst.exists();assert 'no implicit' in m.synchronize(src,dst,work)
 (src/'bad-link').symlink_to('/usr/share')
 try:m.synchronize(src,dst,work);raise AssertionError('symlink accepted')
 except RuntimeError:pass
print('PASS: complete copy, serialized concurrent updates, implicit-size patch, idempotency, upstream refresh, local edit protection, retirement and symlink rejection')
