"""Build the static Pages site with the same revision's public metadata and icons."""
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist' / 'site'

def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(ROOT / 'site', OUT)
    metadata = json.loads((ROOT / 'metadata/builtins.json').read_text(encoding='utf-8-sig'))
    if metadata.get('SchemaVersion') != 2 or not isinstance(metadata.get('Packages'), list):
        raise ValueError('Expected schema 2 built-in metadata')
    for entry in metadata['Packages']:
        if entry.get('IconUrl'):
            filename = entry['IconUrl'].rsplit('/', 1)[-1]
            if not (ROOT / 'metadata/icons' / filename).is_file():
                raise ValueError('Built-in icon is missing: ' + filename)
            entry['IconUrl'] = 'icons/' + filename
    (OUT / 'metadata').mkdir()
    (OUT / 'metadata/builtins.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    shutil.copytree(ROOT / 'metadata/icons', OUT / 'metadata/icons')
    (OUT / '.nojekyll').touch()
    print('Built static Pages site: ' + str(OUT))

if __name__ == '__main__':
    build()
