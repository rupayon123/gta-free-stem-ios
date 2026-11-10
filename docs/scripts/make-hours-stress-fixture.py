#!/usr/bin/env python3
"""Create explicitly fictional, schema-valid near-limit input for a disposable simulator only.
Does not find a simulator, write app containers, activate a preview, or overwrite an existing file.
Validate through YouthHub.Notebook.decode before staging into the stopped disposable QA app.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
today = datetime.date.today()
completed = today - datetime.timedelta(days=1)
timestamp = today.isoformat() + 'T00:00:00Z'
entries = []
for index in range(2000):
    entries.append(dict(
        id=str(uuid.uuid5(uuid.NAMESPACE_URL, 'gta-qa-fictional-hours/' + str(index))),
        revision=1, provider='QA fictional provider', role=f'QA synthetic record {index:04d}',
        activityLocalDate=(completed - datetime.timedelta(days=index // 20)).isoformat(),
        actualMinutes=1, notes='Synthetic stress fixture; no real work or school credit.',
        createdAt=timestamp, updatedAt=timestamp))
archive = dict(schemaVersion=1, entries=entries)
data = json.dumps(archive, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
assert len(data) <= 2_000_000 and len(entries) == 2000
assert max(sum(e['actualMinutes'] for e in entries if e['activityLocalDate'] == day)
           for day in {e['activityLocalDate'] for e in entries}) == 20
with args.output.open('xb') as output:
    output.write(data)
print(json.dumps(dict(fictional=True, entries=2000, recordedMinutes=2000, bytes=len(data),
                     sha256=hashlib.sha256(data).hexdigest(), today=today.isoformat(),
                     nativeModelValidated=False, deviceStaged=False, ownerDataAccessed=False), indent=2))
