#!/usr/bin/env python3
"""Merge a KConfig fragment (config/*.ini) into a KDE config file key by key.

    tools/merge-kconfig.py config/kwinrc.ini kwinrc            # ~/.config/kwinrc
    tools/merge-kconfig.py --dry-run config/kwinrc.ini kwinrc  # only print

Keys not in the fragment are left untouched. Nested groups are written as
[A][B] in the fragment. Uses kwriteconfig6, so KDE's own escaping applies.
"""
import argparse
import configparser
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument('fragment')
ap.add_argument('target', help='file name in ~/.config or an absolute path')
ap.add_argument('--dry-run', action='store_true')
ap.add_argument('--notify', action='store_true', help='let running KDE apps reload the key')
args = ap.parse_args()

cfg = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=('=',),
                                   comment_prefixes=('#',), empty_lines_in_values=False)
cfg.optionxform = str
cfg.read(args.fragment, encoding='utf-8')

for section in cfg.sections():
    groups = section.split('][')
    for key, value in cfg.items(section):
        value = value.replace('\\t', '\t')
        cmd = ['kwriteconfig6', '--file', args.target]
        for g in groups:
            cmd += ['--group', g]
        cmd += ['--key', key]
        if args.notify:
            cmd.append('--notify')
        cmd.append(value)
        if args.dry_run:
            print(f'[{section}] {key}={value!r}')
        else:
            subprocess.run(cmd, check=True)
