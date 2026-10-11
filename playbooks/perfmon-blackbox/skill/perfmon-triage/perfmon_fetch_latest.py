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

Usage:
  perfmon_fetch_latest.py --account <storage account> (--prefix <sub>/<rg>/<machine> | --machine <name>)
                          [--container perfmon] [--last N] [--out /tmp/perfmon]
  perfmon_fetch_latest.py --list-machines --account <storage account>
"""
import argparse
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
        picked = pick_latest(list_blobs(a.account, a.container, prefix + '/', token), prefix, a.last)
        if not picked:
            sys.exit(f'no capture zip under {a.container}/{prefix}/')
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
    print('csv: ' + ' '.join(reversed(csvs)))


if __name__ == '__main__':
    main()
