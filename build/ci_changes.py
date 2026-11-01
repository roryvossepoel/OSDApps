"""Select the icon-only CI fast path; unknown changes always require module tests."""
import json
import math
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def git(*args):
    return subprocess.check_output(['git', *args])


def commit(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{40}', value) or value == '0' * 40:
        raise ValueError('No usable comparison commit')
    return value


def changed_files(event_name, event):
    if event_name == 'pull_request':
        base = commit(event['pull_request']['base']['sha'])
        head = commit(event['pull_request']['head']['sha'])
        base = git('merge-base', base, head).decode().strip()
    elif event_name == 'push':
        base, head = commit(event['before']), commit(event['after'])
    else:
        return []  # Manual and unknown events run the full suite.
    # Disable rename detection: a move includes a deletion and must run full CI.
    parts = git('diff', '--name-status', '-z', '--no-renames', base, head, '--').split(b'\0')
    if parts[-1] != b'' or (len(parts) - 1) % 2:
        raise ValueError('Unexpected git diff output')
    return [(parts[i].decode(), parts[i + 1].decode()) for i in range(0, len(parts) - 1, 2)]


def icon_only(changes):
    return bool(changes) and all(
        status in ('A', 'M') and re.fullmatch(r'metadata/icons/[^/]+\.svg', path)
        for status, path in changes
    )


def validate_icons(directory):
    icons = sorted(directory.glob('*.svg'))
    if not icons:
        raise ValueError('No SVG icons found')
    for path in icons:
        if path.is_symlink():
            raise ValueError(f'{path}: expected a regular SVG file')
        data = path.read_bytes()
        if b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
            raise ValueError(f'{path}: DTD/entity declarations are not supported')
        root = ET.fromstring(data)
        if root.tag != '{http://www.w3.org/2000/svg}svg':
            raise ValueError(f'{path}: expected an SVG root element')
        if 'viewBox' in root.attrib:
            bounds = [float(x) for x in re.split(r'[\s,]+', root.get('viewBox', '').strip()) if x]
            if len(bounds) != 4 or not all(math.isfinite(x) for x in bounds) or min(bounds[2:]) <= 0:
                raise ValueError(f'{path}: expected a finite viewBox with positive dimensions')
        else:
            for name in ('width', 'height'):
                value = root.get(name, '')
                if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)?(?:px)?', value) or float(value.removesuffix('px')) <= 0:
                    raise ValueError(f'{path}: expected a viewBox or positive width and height')
    return len(icons)


def main():
    full = True
    try:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        changes = changed_files(os.environ.get('GITHUB_EVENT_NAME'), event)
        full = not icon_only(changes)
        reason = 'Full validation required' if full else 'Only SVG icons added or modified'
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        reason = f'Full validation required: cannot safely classify changes ({type(error).__name__})'
    count = validate_icons(Path('metadata/icons'))
    print(f'{reason}. Validated {count} SVG files.')
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'run_module={str(full).lower()}\n')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
            summary.write(f'{reason}. Checked {count} SVG files.\n\n')
            summary.write('PowerShell 7 and 5.1: **' + ('run' if full else 'skipped (icon-only change)') + '**.\n')


if __name__ == '__main__':
    main()
