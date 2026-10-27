#!/usr/bin/env python3
"""Write db.json.zip for MiSTer's downloader from a checkout of the `db` branch.

Usage: make_db.py <db checkout> <commit sha holding the files>
Tags follow the DB-Template scheme: every file is tagged `arcadecores`, rbfs also `cores` and
`arcaderbfsonly`, MRAs `mra`, and each rbf and its MRAs share a per-core tag `arcade<rbf name>`
(e.g. `arcadetomsvresd`), so update_all's download filter can pick single cores.
"""
import hashlib, json, os, re, sys, time, zipfile

REPO = 'TomSVR-Mister/TomSVR-Arcade-Cores'
root, sha = sys.argv[1], sys.argv[2]
MRA_DIR, CORE_DIR = '_Arcade/_TomSVR', '_Arcade/cores'

tags = {}
def tag(name):
    return tags.setdefault(name, len(tags))

def core_tag(rbf):
    return tag('arcade' + re.sub(r'[^a-z0-9]', '', rbf.lower()))

files = {}
def add(path, tag_list):
    data = open(os.path.join(root, path), 'rb').read()
    files[path] = {'hash': hashlib.md5(data).hexdigest(), 'size': len(data), 'tags': tag_list}

for f in sorted(os.listdir(os.path.join(root, CORE_DIR))):
    name = re.sub(r'_\d{8}$', '', f[:-4])           # TomSVR_esd_20261017.rbf -> TomSVR_esd
    add(f'{CORE_DIR}/{f}', [tag('arcadecores'), core_tag(name), tag('cores'), tag('arcaderbfsonly')])

for f in sorted(os.listdir(os.path.join(root, MRA_DIR))):
    xml = open(os.path.join(root, MRA_DIR, f), encoding='utf-8').read()
    rbf = re.search(r'<rbf>\s*([^<\s]+)\s*</rbf>', xml).group(1)
    add(f'{MRA_DIR}/{f}', [tag('arcadecores'), tag('mra'), core_tag(rbf)])

# Scripts/ (installed to /media/fat/Scripts): the Mega-Tech / Mega Play cartridge file maker
SCRIPT_DIR = 'Scripts'
if os.path.isdir(os.path.join(root, SCRIPT_DIR)):
    for f in sorted(os.listdir(os.path.join(root, SCRIPT_DIR))):
        add(f'{SCRIPT_DIR}/{f}', [tag('arcadecores'), tag('scripts'), core_tag('TomSVR_megatech'), core_tag('TomSVR_megaplay')])

db = {
    'db_id': REPO,
    'db_url': f'https://raw.githubusercontent.com/{REPO}/db/db.json.zip',
    'base_files_url': f'https://raw.githubusercontent.com/{REPO}/{sha}/',
    'files': files,
    'folders': {'_Arcade': {'tags': [tag('arcadecores')]},
                MRA_DIR: {'tags': [tag('arcadecores'), tag('mra')]},
                CORE_DIR: {'tags': [tag('arcadecores'), tag('cores')]},
                **({SCRIPT_DIR: {'tags': [tag('arcadecores'), tag('scripts')]}} if os.path.isdir(os.path.join(root, SCRIPT_DIR)) else {})},
    'tag_dictionary': tags,
    'timestamp': int(time.time()),
    'v': 1,
}
with zipfile.ZipFile(os.path.join(root, 'db.json.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('db.json', json.dumps(db, indent=1))
print(len(files), 'files,', len(tags), 'tags')
