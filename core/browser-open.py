#!/usr/bin/python3
"""Preserve explicit external-link activation across windows and monitors.

Only the launch request is passed to KWin, never the URL. All arguments and the
original environment are forwarded verbatim to the packaged browser launcher.
If the optional desktop component is unavailable, normal launching still works.
"""
import os
import subprocess
import sys

def main():
    # Fixed fields are supplied by the desktop entry, before the argument boundary.
    if len(sys.argv) < 5 or sys.argv[3] != '--':
        raise SystemExit('Usage: browser-open.py DESKTOP_ID WM_CLASS -- EXEC [ARG...]')
    app_id, wm_class = sys.argv[1:3]
    command = sys.argv[4:]
    if any(value.lower().startswith(('https://', 'http://')) for value in command[1:]):
        try:
            subprocess.run(['qdbus6', 'org.kde.KWin', '/SoftGraphiteLayers',
                            'org.leonid.GraphiteLayers.PrepareBrowserOpen', app_id, wm_class],
                           timeout=.7, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
    os.execv(command[0], command)

if __name__ == '__main__':
    main()
