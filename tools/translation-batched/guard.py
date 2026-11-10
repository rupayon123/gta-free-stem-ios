"""Kill the single Linux trial process on time or memory limits."""
import json
import os
import subprocess
import sys
import time

if len(sys.argv) < 2 or sys.platform != 'linux':
    raise SystemExit('Linux command required')
started = time.monotonic()
p = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
peak = 0
reason = None
while p.poll() is None:
    if time.monotonic() - started > 120:
        reason = '120 second limit'; p.kill(); break
    try:
        with open(f'/proc/{p.pid}/status', encoding='ascii') as f:
            status = f.read()
        rss = next(int(x.split()[1]) * 1024 for x in status.splitlines() if x.startswith('VmRSS:'))
        peak = max(peak, rss)
        if rss >= 8_000_000_000:
            reason = '8 GB RSS limit'; p.kill(); break
    except (OSError, StopIteration, ValueError):
        if p.poll() is None:
            reason = 'RSS monitor unavailable'; p.kill()
        break
    time.sleep(0.1)
out, err = p.communicate()
if len(out) > 100000 or len(err) > 100000:
    raise SystemExit('process output exceeds bound')
print(json.dumps({'peakRSSBytes': peak, 'guardStop': reason, 'exitCode': p.returncode,
                  'elapsedSeconds': round(time.monotonic()-started, 3)}))
if p.returncode or reason:
    print(err[-4000:].decode('utf-8', 'replace'), file=sys.stderr)
    raise SystemExit(1)
print(out.decode('utf-8', 'strict'))
