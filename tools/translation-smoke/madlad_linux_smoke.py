"""Public-runner fixed synthetic smoke only; no feed, user data or publishing."""
import json
import os
import struct
import subprocess
import sys
import threading
import time

MAX_RSS_BYTES = 6_000_000_000
MAX_WALL_SECONDS = 180
CASES = ('Free science workshop for children aged 6 to 12.', 'Register by November 20.', 'A parent must attend.')


def frame(text):
    value = text.encode('utf-8')
    return struct.pack('>I', len(value)) + value


def rss_bytes(status):
    for line in status.splitlines():
        if line.startswith('VmRSS:'):
            fields = line.split()
            if len(fields) != 3 or fields[2] != 'kB':
                break
            return int(fields[1]) * 1024
    raise ValueError('Linux process RSS unavailable')


def sanitized_stderr(raw, worker, model, backend):
    """Bound synthetic-only diagnostics; never include environment dumps."""
    text = raw[-8192:].decode('utf-8', 'replace')
    for value, label in ((worker, '<worker>'), (model, '<model>'), (backend, '<cpu-backend>')):
        if value:
            text = text.replace(value, label)
    return text


def main(worker, model, backend):
    request = b''.join(frame('pa') + frame(text) for text in CASES)
    start = time.monotonic()
    process = subprocess.Popen([worker, model, backend], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stop = threading.Event()
    state = {'peakRSSBytes': 0, 'guardStop': None}

    def watch():
        while not stop.is_set() and process.poll() is None:
            if time.monotonic() - start >= MAX_WALL_SECONDS:
                state['guardStop'] = 'wall limit'; process.kill(); return
            try:
                with open('/proc/' + str(process.pid) + '/status', encoding='ascii') as stream:
                    rss = rss_bytes(stream.read())
                state['peakRSSBytes'] = max(state['peakRSSBytes'], rss)
                if rss >= MAX_RSS_BYTES:
                    state['guardStop'] = 'RSS limit'; process.kill(); return
            except (OSError, ValueError):
                if process.poll() is None:
                    state['guardStop'] = 'RSS monitor unavailable'; process.kill()
                return
            stop.wait(0.1)

    thread = threading.Thread(target=watch, daemon=True); thread.start()
    try:
        stdout, stderr = process.communicate(request, timeout=MAX_WALL_SECONDS + 2)
    except subprocess.TimeoutExpired:
        state['guardStop'] = 'communication timeout'; process.kill(); stdout, stderr = process.communicate()
    finally:
        stop.set(); thread.join(timeout=2)
    try:
        if len(stdout) > 1_000_000:
            rows, parse_error = [], 'worker output exceeds bound'
        else:
            rows = [json.loads(line) for line in stdout.decode('utf-8', 'strict').splitlines()]
            parse_error = None
    except (ValueError, UnicodeError):
        rows = []
        parse_error = 'worker returned invalid JSON/UTF-8'
    okay = process.returncode == 0 and not state['guardStop'] and len(rows) == len(CASES) and all(
        isinstance(row, dict) and row.get('ok') is True and row.get('locale') == 'pa' and row.get('targetPrefix') == '<2pa>' and
        row.get('prefixTokenID') == 112 and row.get('endedNormally') is True and row.get('hitTokenLimit') is False and
        isinstance(row.get('text'), str) and bool(row['text'].strip()) for row in rows)
    result = {'scope': 'synthetic CPU structural smoke only; translation meaning not certified',
              'passed': okay, 'exitCode': process.returncode, 'wallSeconds': round(time.monotonic()-start, 3),
              **state, 'ready': next((line for line in stderr.decode('utf-8', 'replace').splitlines() if line.startswith('READY ')), None),
              'results': [{'source': source, 'output': row} for source, row in zip(CASES, rows)],
              'parseError': parse_error, 'failureStderrTail': None if okay else sanitized_stderr(stderr, worker, model, backend)}
    print(json.dumps(result, ensure_ascii=False))
    if not okay:
        raise SystemExit(1)


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.platform != 'linux':
        raise SystemExit('usage on Linux: python3 madlad_linux_smoke.py WORKER MODEL CPU_PLUGIN_DIR')
    main(*sys.argv[1:])
