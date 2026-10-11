#!/usr/bin/env python3
"""T16 scorer: deterministic rules of rubric.md over the agent's report text and make-trouble.ps1's truth.json.
Usage: score.py report.txt truth.json [--zip <blob or file name>] [--json]
Exit 0 = pass (>= 80 and every planted problem found). Standard library only."""
import argparse
import datetime as dt
import json
import re
import sys

TIME_RE = re.compile(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b')


def times_in(line):
    return [int(h) * 60 + int(m) for h, m, _ in TIME_RE.findall(line)]


def minute(ts):
    t = dt.datetime.fromisoformat(ts.replace('T', ' '))
    return t.hour * 60 + t.minute


def near(line, target, tol=2):
    return any(abs(t - target) <= tol or abs(t - target) >= 1440 - tol for t in times_in(line))


def windows(lines, k=2):
    for i in range(len(lines)):
        yield ' '.join(lines[i:i + k])


def rate_mb_h(text):
    out = []
    for v, unit in re.findall(r'(\d+(?:[.,]\d+)?)\s*(MB|MiB|GB|GiB)\s*(?:/|per)\s*(?:h\b|hr|hour)', text, re.I):
        x = float(v.replace(',', '.'))
        out.append(x * 1024 if unit.upper().startswith('G') else x)
    return out


def score(report, truth, zipname=None):
    lines = [l for l in report.splitlines()]
    low = report.lower()
    pts, notes = {}, {}
    probs = {p['id']: p for p in truth['problems']}
    # capture
    stem = (zipname or '').split('/')[-1].replace('.zip', '')
    pts['C1'] = 10 if stem and stem.lower() in low else 0
    pts['C2'] = 5 if truth['host'].lower() in low else 0
    first = minute(truth.get('capture_first', truth['started']))
    last = minute(truth.get('capture_last', truth.get('ended', truth['started'])))
    pts['C3'] = 5 if any(near(l, first, 5) for l in lines) and any(near(l, last, 5) for l in lines) else 0
    # leak
    lk = probs.get('leak')
    found = {}
    if lk:
        want = lk['per_hour_bytes'] / 1048576
        cand = [w for w in windows(lines) if 'bbleak' in w.lower()]
        ok = any(any(abs(r - want) <= 0.4 * want for r in rate_mb_h(w)) for w in cand)
        found['leak'] = ok; pts['P1'] = 15 if ok else 0
        notes['P1'] = f'planted {want:.0f} MB/h; rates near bbleak: {[rate_mb_h(w) for w in cand][:3]}'
    def episode(pid, words, pts_key, n):
        p = probs.get(pid)
        if not p:
            return
        tgt = minute(p['from'])
        ok = any(any(wd in w.lower() for wd in words) and near(w, tgt) for w in windows(lines))
        if pid == 'cpu':
            ok = ok and 'bbcpu' in low
        found[pid] = ok; pts[pts_key] = n if ok else 0
    episode('cpu', ('cpu', 'processor'), 'P2', 15)
    # disk: the line must name the disk AND a latency (not just any disk activity): P34 tightened
    d = probs.get('disk')
    if d:
        tgt = minute(d['from'])
        ok = any(re.search(r'disk|logicaldisk|C:', w, re.I) and re.search(r'latency|sec/(read|write)|\d+(\.\d+)?\s*ms\b|\d\.\d+\s*s\b', w, re.I)
                 and near(w, tgt) for w in windows(lines))
        found['disk'] = ok; pts['P3'] = 15 if ok else 0
    episode('nic', ('network', 'nic', 'bytes total', 'interface'), 'P4', 15)
    # verdict words
    bad = [l for l in lines if re.search(r'critical|severe', l, re.I) and re.search(r'stall|spike|bbleak|leak', l, re.I)
           and not re.search(r'cpu.*(1[0-9]|12) ?min|bbcpu', l, re.I)]
    pts['V1'] = 0 if bad else 5
    # a term counts as invented only on a line that does not call it fine / within / no / not (P34 scorer fix)
    neg = re.compile(r'\b(fine|within|ok|no|not|normal|healthy|pass(ed)?|under|below)\b', re.I)
    inv = [l for l in lines for r in (r'commit (is )?near (the )?limit', r'\bPTEs? (are )?(exhausted|low)', r'paging file (is )?filling',
                                      r'disk (is )?(nearly|almost) full') if re.search(r, l, re.I) and not neg.search(l)]
    pts['N1'] = 0 if inv else 5
    # a negated statement ("not caused by", "no causal link") is not a causal claim (T16 run 4)
    claims = [l for l in lines if re.search(r'caused by|because|drives', l, re.I)
              and not re.search(r'\b(not|no|never|cannot|can\'t)\b[^.|]{0,20}(caused by|because|drives)', l, re.I)]
    pts['R1'] = 5 if (not claims or 'LINK:' in report) else 0
    raw = [l for l in lines if len(re.findall(r'-?\d+(?:\.\d+)?', l)) > 30 and (l.count(',') > 30 or l.count('|') > 30)]
    pts['R2'] = 0 if raw else 5
    total = sum(pts.values())
    planted = [p for p in ('leak', 'cpu', 'disk', 'nic') if p in probs]
    ok = total >= 80 and all(found.get(p) for p in planted)
    return {'points': pts, 'total': total, 'found': found, 'pass': ok, 'notes': notes}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('report'); ap.add_argument('truth')
    ap.add_argument('--zip'); ap.add_argument('--json', action='store_true')
    a = ap.parse_args()
    with open(a.report, encoding='utf-8') as f:
        rep = f.read()
    with open(a.truth, encoding='utf-8-sig') as f:
        tr = json.load(f)
    r = score(rep, tr, a.zip)
    if a.json:
        print(json.dumps(r, indent=1))
    else:
        for k, v in r['points'].items():
            print(f'{k}: {v}')
        print(f"found: {r['found']}")
        print(f"TOTAL {r['total']}/100 -> {'PASS' if r['pass'] else 'FAIL'}")
    sys.exit(0 if r['pass'] else 1)


if __name__ == '__main__':
    main()
