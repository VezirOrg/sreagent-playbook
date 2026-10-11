#!/usr/bin/env python3
r"""Fetch the latest PerfMon capture(s) of one machine from the perfmon-blackbox storage account.

The recorder uploads one zip per export to
  <container>/<subscriptionId>/<resourceGroup>/<machine>/<yyyy>/<mm>/<dd>/<machine>_<from>_<to>.zip
(lower case; <from>/<to> = yyyymmdd-hhmmss of the first and last sample). Each zip holds one PerfMon CSV and
manifest.json (window, rows, sha256 of the CSV, complete flag, gaps[]).

This script lists the machine's prefix, picks the newest zip by the window end in its name (ties: Last-Modified),
downloads it, checks the CSV against the manifest's SHA-256, unzips it and prints a short summary: which zip, the
window, complete or not, every gap. The CSV then goes to perfmon_csv_to_sqlite.py (step 0).

Authentication (first that works): env PERFMON_STORAGE_TOKEN (a bearer token for https://storage.azure.com/),
the Azure CLI (`az account get-access-token`), a managed identity (IDENTITY_ENDPOINT / MSI_ENDPOINT / IMDS).
Read access is enough (Storage Blob Data Reader on the container). Python standard library only.

Default: the latest zip. Range mode (--from/--to, or --last-hours N): every zip whose window overlaps the range, in
time order, with a coverage report (the part of the range before the oldest zip, after the newest, or between zips that
no zip covers). Times are the machine's local time as in the zip names (yyyy-mm-dd hh:mm[:ss]).

Usage:
  perfmon_fetch_latest.py --account <storage account> (--prefix <sub>/<rg>/<machine> | --machine <name>)
                          [--container perfmon] [--last N | --from <t> --to <t> | --last-hours N] [--out /tmp/perfmon]
  perfmon_fetch_latest.py --list-machines --account <storage account>
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

API_VERSION = '2023-11-03'
RESOURCE = 'https://storage.azure.com/'
NAME_RE = re.compile(r'^(?P<machine>.+)_(?P<from>\d{8}-\d{6})_(?P<to>\d{8}-\d{6})\.zip$')


# ---- selection (pure, tested by L04) ----

def parse_blob(name, prefix):
    """(to_stamp, from_stamp) for a capture zip directly under <prefix>/yyyy/mm/dd/, else None."""
    pre = prefix.strip('/').lower() + '/'
    if not name.lower().startswith(pre):
        return None
    rest = name[len(pre):].split('/')
    if len(rest) != 4 or not all(p.isdigit() for p in rest[:3]):
        return None
    m = NAME_RE.match(rest[3])
    if not m:
        return None
    return m.group('to'), m.group('from')


def pick_latest(blobs, prefix, last=1):
    """blobs: iterable of (name, last_modified_sortable). The `last` newest capture zips of the prefix, newest first.
    Other prefixes (including a machine whose name starts with this one) and non-capture blobs are ignored."""
    keyed = []
    for name, modified in blobs:
        k = parse_blob(name, prefix)
        if k:
            keyed.append((k[0], modified or '', k[1], name))
    keyed.sort(reverse=True)
    return [k[3] for k in keyed[:max(1, last)]]


STAMP = '%Y%m%d-%H%M%S'


def _window(name):
    m = NAME_RE.match(name.split('/')[-1])
    return (dt.datetime.strptime(m.group('from'), STAMP), dt.datetime.strptime(m.group('to'), STAMP)) if m else None


def parse_time(text):
    """'2026-10-11 14:00' / '2026-10-11T14:00:30' -> datetime (machine local time, as in the zip names)."""
    t = text.strip().replace('T', ' ')
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d'):
        try:
            return dt.datetime.strptime(t, fmt)
        except ValueError:
            pass
    raise ValueError(f'unrecognised time {text!r} (use yyyy-mm-dd hh:mm)')


def pick_range(blobs, prefix, start, end):
    """Every capture zip of the prefix whose window [from, to] overlaps [start, end], oldest first."""
    out = []
    for name, _ in blobs:
        if parse_blob(name, prefix):
            w = _window(name)
            if w and w[1] >= start and w[0] <= end:
                out.append((w[0], name))
    return [n for _, n in sorted(out)]


def coverage(names, start, end, slack_s=30):
    """What part of [start, end] no zip covers: [(from, to, why)], why = before_oldest | after_newest | missing.
    Holes up to slack_s between consecutive zips are the export's own roll and are not listed."""
    holes = []
    if not names:
        return [(start, end, 'no_zip')]
    ws = [_window(n) for n in names]
    if ws[0][0] > start:
        holes.append((start, ws[0][0], 'before_oldest'))
    for (a0, a1), (b0, b1) in zip(ws, ws[1:]):
        if (b0 - a1).total_seconds() > slack_s:
            holes.append((a1, b0, 'missing'))
    if ws[-1][1] < end:
        holes.append((ws[-1][1], end, 'after_newest'))
    return holes


def machines(blob_names):
    """Distinct <sub>/<rg>/<machine> prefixes in a container listing."""
    out = set()
    for n in blob_names:
        p = n.split('/')
        if len(p) == 7 and NAME_RE.match(p[6]):
            out.add('/'.join(p[:3]))
    return sorted(out)


def verify_zip(path):
    """Open a capture zip, check manifest.json and the CSV's SHA-256. Returns (manifest, csv member name)."""
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if 'manifest.json' not in names:
            raise ValueError('no manifest.json in the zip')
        man = json.loads(z.read('manifest.json'))
        csvs = [n for n in names if n.lower().endswith('.csv')]
        if len(csvs) != 1:
            raise ValueError(f'expected one CSV in the zip, found {len(csvs)}')
        h = hashlib.sha256()
        with z.open(csvs[0]) as f:
            for chunk in iter(lambda: f.read(1 << 20), b''):
                h.update(chunk)
        if h.hexdigest().lower() != str(man.get('csv_sha256', '')).lower():
            raise ValueError('CSV SHA-256 does not match the manifest')
        return man, csvs[0]


def summary(man, blob):
    gaps = man.get('gaps') or []
    lines = [f"zip: {blob}",
             f"window: {man.get('window_from')} .. {man.get('window_to')} (first sample {man.get('first_sample')}, "
             f"last {man.get('last_sample')}, local time of the machine, UTC offset {man.get('utc_offset')})",
             f"rows: {man.get('rows')}  interval: {man.get('interval_s')} s  complete: {man.get('complete')}  "
             f"buffer hours: {man.get('buffer_hours')}",
             f"gaps: {len(gaps)}"]
    for g in gaps[:10]:
        lines.append(f"  gap {g.get('from')} .. {g.get('to')} ({g.get('seconds')} s): {g.get('cause')}")
    if len(gaps) > 10:
        lines.append(f'  ... {len(gaps) - 10} more gaps')
    return lines


# ---- Azure (REST, bearer token) ----

def _http(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_token():
    tok = os.environ.get('PERFMON_STORAGE_TOKEN')
    if tok:
        return tok, 'env'
    az = shutil.which('az')
    if az:
        try:
            out = subprocess.run([az, 'account', 'get-access-token', '--resource', RESOURCE, '--query', 'accessToken',
                                  '-o', 'tsv'], capture_output=True, text=True, timeout=60)
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip(), 'azure-cli'
        except (OSError, subprocess.SubprocessError):
            pass
    q = urllib.parse.urlencode({'resource': RESOURCE})
    ep, hdr = os.environ.get('IDENTITY_ENDPOINT'), os.environ.get('IDENTITY_HEADER')
    if ep and hdr:
        try:
            body = _http(f'{ep}?api-version=2019-08-01&{q}', {'X-IDENTITY-HEADER': hdr})
            return json.loads(body)['access_token'], 'managed-identity'
        except (OSError, ValueError, KeyError):
            pass
    ep = os.environ.get('MSI_ENDPOINT')
    if ep:
        try:
            body = _http(f'{ep}?api-version=2017-09-01&{q}', {'Secret': os.environ.get('MSI_SECRET', '')})
            return json.loads(body)['access_token'], 'managed-identity'
        except (OSError, ValueError, KeyError):
            pass
    try:
        body = _http(f'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&{q}',
                     {'Metadata': 'true'}, timeout=5)
        return json.loads(body)['access_token'], 'imds'
    except (OSError, ValueError, KeyError):
        pass
    sys.exit('no token for storage: set PERFMON_STORAGE_TOKEN, log in with az, or run with a managed identity')


def list_blobs(account, container, prefix, token):
    base = f'https://{account}.blob.core.windows.net/{container}'
    marker, out = '', []
    while True:
        q = {'restype': 'container', 'comp': 'list', 'prefix': prefix}
        if marker:
            q['marker'] = marker
        body = _http(f'{base}?{urllib.parse.urlencode(q)}',
                     {'Authorization': f'Bearer {token}', 'x-ms-version': API_VERSION})
        root = ET.fromstring(body)
        for b in root.iter('Blob'):
            lm = b.findtext('Properties/Last-Modified') or ''
            out.append((b.findtext('Name'), _sortable(lm)))
        marker = root.findtext('NextMarker') or ''
        if not marker:
            return out


def _sortable(http_date):
    try:
        from email.utils import parsedate_to_datetime
        return parsedate_to_datetime(http_date).strftime('%Y%m%d%H%M%S')
    except (TypeError, ValueError):
        return ''


def download(account, container, name, token, dest):
    url = f'https://{account}.blob.core.windows.net/{container}/{urllib.parse.quote(name)}'
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}', 'x-ms-version': API_VERSION})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, 'wb') as f:
        shutil.copyfileobj(r, f, 1 << 20)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--account', required=True)
    ap.add_argument('--container', default='perfmon')
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--prefix', help='<subscriptionId>/<resourceGroup>/<machine>')
    g.add_argument('--machine', help='machine name; the prefix is looked up in the container')
    g.add_argument('--list-machines', action='store_true')
    ap.add_argument('--last', type=int, default=1, help='how many of the newest zips (default 1)')
    ap.add_argument('--from', dest='start', help='range mode: start, machine local time (yyyy-mm-dd hh:mm)')
    ap.add_argument('--to', dest='end', help='range mode: end (default: the newest zip\'s end)')
    ap.add_argument('--last-hours', type=float, help='range mode: the last N hours before the newest zip\'s end')
    ap.add_argument('--out', default='/tmp/perfmon')
    a = ap.parse_args()
    token, source = get_token()
    print(f'token source: {source}')
    try:
        if a.list_machines or a.machine:
            ms = machines(n for n, _ in list_blobs(a.account, a.container, '', token))
            if a.list_machines:
                print('\n'.join(ms) or 'no captures in the container')
                return
            hits = [m for m in ms if m.split('/')[2] == a.machine.lower()]
            if len(hits) != 1:
                sys.exit(f'machine {a.machine!r}: {len(hits)} prefixes match' + (': ' + ', '.join(hits) if hits else ''))
            prefix = hits[0]
        else:
            prefix = a.prefix.strip('/').lower()
        blobs = list_blobs(a.account, a.container, prefix + '/', token)
        holes = None
        if a.start or a.last_hours:
            newest = pick_latest(blobs, prefix, 1)
            if not newest:
                sys.exit(f'no capture zip under {a.container}/{prefix}/')
            end = parse_time(a.end) if a.end else _window(newest[0])[1]
            start = parse_time(a.start) if a.start else end - dt.timedelta(hours=a.last_hours)
            picked = pick_range(blobs, prefix, start, end)
            holes = coverage(picked, start, end)
            print(f'range: {start:%Y-%m-%d %H:%M:%S} .. {end:%Y-%m-%d %H:%M:%S} (machine local time); zips: {len(picked)}')
        else:
            picked = list(reversed(pick_latest(blobs, prefix, a.last)))   # oldest first
        if not picked:
            sys.exit(f'no capture zip under {a.container}/{prefix}/' + (' in that range' if holes is not None else ''))
        os.makedirs(a.out, exist_ok=True)
        csvs = []
        for name in picked:
            local = os.path.join(a.out, os.path.basename(name))
            download(a.account, a.container, name, token, local)
            man, member = verify_zip(local)
            with zipfile.ZipFile(local) as z:
                z.extract(member, a.out)
            csvs.append(os.path.join(a.out, member))
            for line in summary(man, f'{a.container}/{name}'):
                print(line)
            print('sha256: OK')
    except urllib.error.HTTPError as e:
        sys.exit(f'storage request failed: HTTP {e.code} {e.reason}')
    if holes is not None:
        why = {'before_oldest': 'not covered: before the oldest zip (captures older than the lifecycle limit are deleted)',
               'after_newest': 'not covered: after the newest zip (the next export has not run yet)',
               'missing': 'not covered: no zip between these two exports (a missing export)', 'no_zip': 'not covered: no zip'}
        print(f'coverage: {"complete" if not holes else str(len(holes)) + " hole(s)"}')
        for f, t, w in holes:
            print(f'  {f:%Y-%m-%d %H:%M:%S} .. {t:%Y-%m-%d %H:%M:%S}: {why[w]}')
    print('csv: ' + ' '.join(csvs))


if __name__ == '__main__':
    main()
