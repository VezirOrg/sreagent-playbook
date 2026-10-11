#!/usr/bin/env python3
"""Local tests L01-L04, L07 (test plan): no Azure, synthetic data only, Python standard library.

Run all:  python3 -m unittest discover -s tests/local -v      (from playbooks/perfmon-blackbox)
or one:   tests/run.sh L02
"""
import contextlib
import hashlib
import io
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile

PB = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SKILL = os.path.join(PB, 'skill', 'perfmon-triage')
SYNTH = os.path.join(PB, 'tests', 'synth', 'make_capture.py')
COLLECTOR = os.path.join(PB, 'package', 'collector')
FIX = os.path.join(PB, 'tests', 'fixtures', 'synthetic')
sys.dont_write_bytecode = True  # keep the skill folder flat (deploy-skill.sh uploads it)
sys.path.insert(0, SKILL)
import perfmon_fetch_latest as fetch  # noqa: E402


def run(*args):
    r = subprocess.run([sys.executable, '-I', *args], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def make(tmp, name, *opts):
    out = os.path.join(tmp, name + '.csv')
    truth = os.path.join(tmp, name + '.json')
    rc, log = run(SYNTH, '--out', out, '--truth', truth, *opts)
    assert rc == 0, log
    with open(truth) as f:
        return out, json.load(f)


def convert(tmp, name, *csvs, opts=()):
    db = os.path.join(tmp, name + '.db')
    rc, log = run(os.path.join(SKILL, 'perfmon_csv_to_sqlite.py'), *csvs, db, '--force', *opts)
    meta = dict(l.split(': ', 1) for l in log.splitlines() if ': ' in l)
    return rc, meta, db


def perfq():
    ns = {}
    with open(os.path.join(SKILL, 'perfq.py')) as f:
        exec(f.read(), ns)
    return ns


def quiet(fn, *a, **k):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = fn(*a, **k)
    return r, buf.getvalue()


class L01Converter(unittest.TestCase):
    """Converter on synthetic PDH-CSV: meta counts, day-first and month-first, two parts with overlap merged."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='l01-')

    def test_counts(self):
        csv_path, truth = make(self.tmp, 'm', '--hours', '1', '--procs', '10')
        rc, meta, _ = convert(self.tmp, 'm', csv_path)
        self.assertEqual(rc, 0)
        self.assertEqual(int(meta['rows']), truth['rows'])
        self.assertEqual(int(meta['counter_columns']), truth['columns'])
        for k in ('unparsed_paths', 'bad_cells', 'short_rows', 'overlap_rows_skipped'):
            self.assertEqual(meta[k], '0', k)
        self.assertEqual(meta['sample_interval_s'], '10')
        self.assertEqual(meta['first_ts'][:19], truth['first_ts'])
        self.assertEqual(meta['last_ts'][:19], truth['last_ts'])

    def test_dayfirst_and_monthfirst(self):
        # 13th of the month: day-first and month-first must both give the same times
        a, truth = make(self.tmp, 'df', '--hours', '0.5', '--procs', '4', '--start', '2026-10-13T08:00:00', '--dayfirst')
        b, _ = make(self.tmp, 'mf', '--hours', '0.5', '--procs', '4', '--start', '2026-10-13T08:00:00')
        _, ma, _ = convert(self.tmp, 'df', a)
        _, mb, _ = convert(self.tmp, 'mf', b)
        self.assertEqual(ma['timestamp_order'], 'day/month/year')
        self.assertEqual(mb['timestamp_order'], 'month/day/year')
        self.assertEqual(ma['first_ts'], mb['first_ts'])
        self.assertEqual(ma['first_ts'][:19], truth['first_ts'])

    def test_two_parts_with_overlap(self):
        p1, truth = make(self.tmp, 'p1', '--hours', '1', '--procs', '6', '--to-row', '200')
        p2, _ = make(self.tmp, 'p2', '--hours', '1', '--procs', '6', '--from-row', '180')
        rc, meta, _ = convert(self.tmp, 'parts', p2, p1)  # given out of order on purpose
        self.assertEqual(rc, 0)
        self.assertEqual(meta['source_files'], '2')
        self.assertEqual(int(meta['rows']), truth['rows'])
        self.assertEqual(meta['overlap_rows_skipped'], '20')
        self.assertEqual(meta['interval_histogram'], f"10s x{truth['rows'] - 1}")


class L02Perfq(unittest.TestCase):
    """perfq on the synthetic DB: triage finds the planted breaches (Processor Information, v2.1) and prints the
    right VERDICT CEILING; movers finds the leak; a quiet capture gets the WARNING ceiling."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='l02-')
        cls.csv, cls.truth = make(cls.tmp, 'all', '--hours', '2', '--procs', '20')
        rc, cls.meta, cls.db_path = convert(cls.tmp, 'all', cls.csv)
        assert rc == 0
        cls.q = perfq()
        cls.db = cls.q['open_db'](cls.db_path)

    def test_cpu_count_from_processor_information(self):
        self.assertEqual(self.q['n_cpu'](self.db), 4)
        self.assertEqual(self.q['cpu_object'](self.db), 'Processor Information')

    def test_triage_finds_planted(self):
        lines, out = quiet(self.q['triage'], self.db)
        hot = {(l[1], l[2]): l for l in lines if (l[6] or 0) >= 5}
        p = {x['id']: x for x in self.truth['problems']}
        cpu = hot[('Processor Information\\% Processor Time', '_Total')]
        self.assertEqual(cpu[7][:19], p['cpu']['from'])
        self.assertAlmostEqual(cpu[6], p['cpu']['minutes'], delta=0.5)
        disk = hot[('LogicalDisk\\Avg. Disk sec/Read', 'C:')]
        self.assertEqual(disk[7][:19], p['disk']['from'])
        self.assertAlmostEqual(disk[6], p['disk']['minutes'], delta=0.5)
        self.assertIn('VERDICT CEILING: critical is allowed', out)
        self.assertIn('CPU (Processor Information\\% Processor Time)', out)
        # no false System breach from a CPU count of 0 (v2.0 bug with this counter set)
        cs = [l for l in lines if l[1] == 'System\\Context Switches/sec'][0]
        self.assertEqual(cs[6], 0)
        nic = [l for l in lines if l[1] == 'Network Interface\\% of bandwidth (max)'][0]
        self.assertIn('BREACH', nic[8])

    def test_movers_finds_leak(self):
        _, out = quiet(self.q['movers'], self.db, 'Process', ('Private Bytes',), 3)
        first = [l for l in out.splitlines() if '|' in l][1]
        self.assertTrue(first.startswith('leaker |'), first)
        slope = float(first.split('|')[2].replace(',', ''))
        self.assertAlmostEqual(slope, 200e6, delta=10e6)

    def test_pid_change_seen(self):
        rows, _ = quiet(self.q['pid_changes'], self.db, 'w3wp')
        self.assertEqual(len(rows), 2)  # first sample + one restart

    def test_quiet_capture_ceiling(self):
        c, _ = make(self.tmp, 'quiet', '--hours', '1', '--procs', '8', '--plant', 'leak')
        _, _, dbp = convert(self.tmp, 'quiet', c)
        _, out = quiet(self.q['triage'], self.q['open_db'](dbp))
        self.assertIn('VERDICT CEILING: WARNING', out)

    def test_stalls_are_short(self):
        # OPEN-2 case: 20-40 s stalls stay below the 5-minute ceiling (rule unchanged until Emre decides)
        c, truth = make(self.tmp, 'stall', '--hours', '2', '--procs', '8', '--plant', 'stall')
        _, _, dbp = convert(self.tmp, 'stall', c)
        lines, out = quiet(self.q['triage'], self.q['open_db'](dbp))
        self.assertTrue(truth['problems'][0]['episodes'])
        self.assertIn('VERDICT CEILING: WARNING', out)
        cpu = [l for l in lines if l[1] == 'Processor Information\\% Processor Time' and l[2] == '_Total'][0]
        self.assertGreater(cpu[5], 0)  # the stalls are there, as % breach


class L03Masker(unittest.TestCase):
    """Masker (lab-side): a synthetic mapping masks a synthetic CSV; a planted denylist entry makes it exit 1
    without printing the name."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='l03-')
        self.csv, _ = make(self.tmp, 'c', '--hours', '0.1', '--procs', '4')
        self.map = os.path.join(self.tmp, 'map.csv')
        with open(self.map, 'w') as f:
            f.write('real,placeholder\nSYNTH01,HOST1\nsqlwriter,proc1\n')
        self.tool = os.path.join(PB, 'lab-tools', 'perfmon_mask_csv.py')

    def test_masks(self):
        deny = os.path.join(self.tmp, 'deny.txt')
        with open(deny, 'w') as f:
            f.write('# synthetic denylist\nNOTPRESENT99\n')
        out = os.path.join(self.tmp, 'masked.csv')
        rc, log = run(self.tool, self.csv, self.map, out, '--denylist', deny)
        self.assertEqual(rc, 0, log)
        text = open(out, encoding='utf-8').read()
        self.assertNotIn('SYNTH01', text)
        self.assertNotIn('sqlwriter', text)
        self.assertIn('\\\\HOST1\\', text)

    def test_denylist_hit_fails_silently(self):
        deny = os.path.join(self.tmp, 'deny.txt')
        with open(deny, 'w') as f:
            f.write('MsMpEng\n')  # present in the synthetic CSV, not in the mapping
        out = os.path.join(self.tmp, 'masked2.csv')
        rc, log = run(self.tool, self.csv, self.map, out, '--denylist', deny)
        self.assertEqual(rc, 1)
        self.assertNotIn('MsMpEng', log)


class L04FetchLatest(unittest.TestCase):
    """perfmon_fetch_latest selection: newest zip, other prefixes ignored, bad hash rejected."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(FIX, 'blob-listing.json')) as f:
            cls.fx = json.load(f)
        cls.blobs = [tuple(b) for b in cls.fx['blobs']]

    def test_newest(self):
        self.assertEqual(fetch.pick_latest(self.blobs, self.fx['prefix']), [self.fx['expect_latest']])

    def test_last_two(self):
        self.assertEqual(fetch.pick_latest(self.blobs, self.fx['prefix'], 2), self.fx['expect_last2'])

    def test_other_prefixes_ignored(self):
        got = fetch.pick_latest(self.blobs, self.fx['prefix'], 99)
        self.assertEqual(len(got), 3)
        self.assertTrue(all(g.startswith(self.fx['prefix'] + '/') for g in got))

    def test_tie_uses_last_modified(self):
        p = 'sub/rg/m'
        b = [(f'{p}/2026/10/01/m_20261001-000000_20261001-040000.zip', '20261001040100'),
             (f'{p}/2026/10/01/m_20261001-010000_20261001-040000.zip', '20261001050000')]
        self.assertEqual(fetch.pick_latest(b, p), [b[1][0]])

    def test_machines(self):
        ms = fetch.machines(n for n, _ in self.blobs)
        self.assertEqual(len(ms), 3)

    def _zip(self, good=True):
        tmp = tempfile.mkdtemp(prefix='l04-')
        csv_bytes = b'"(PDH-CSV 4.0) (Coordinated Universal Time)(0)","\\\\SYNTH01\\Memory\\Available MBytes"\r\n'
        man = {'csv_sha256': hashlib.sha256(csv_bytes if good else b'x').hexdigest(), 'complete': True, 'gaps': [],
               'rows': 0}
        path = os.path.join(tmp, 'm_20261001-000000_20261001-040000.zip')
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('m_20261001-000000_20261001-040000.csv', csv_bytes)
            z.writestr('manifest.json', json.dumps(man))
        return path

    def test_hash_ok(self):
        man, member = fetch.verify_zip(self._zip(True))
        self.assertTrue(member.endswith('.csv'))

    def test_hash_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            fetch.verify_zip(self._zip(False))

    def test_summary_quotes_gaps(self):
        man = {'complete': False, 'gaps': [{'from': 'a', 'to': 'b', 'seconds': 60, 'cause': 'buffer_overrun'}]}
        text = '\n'.join(fetch.summary(man, 'perfmon/x.zip'))
        self.assertIn('complete: False', text)
        self.assertIn('buffer_overrun', text)


class L07Template(unittest.TestCase):
    def test_server_scripts_ascii(self):
        # Windows PowerShell 5.1 reads a BOM-less UTF-8 script as ANSI: server code stays pure ASCII (P25)
        for d, _, fs in os.walk(os.path.join(PB, 'package')):
            for f in fs:
                if f.endswith(('.ps1', '.psm1', '.psd1', '.txt', '.xml')):
                    data = open(os.path.join(d, f), 'rb').read()
                    self.assertTrue(all(b < 128 for b in data), f)

    """The template holds exactly the 36 lines of the counter list, no location, date or machine field;
    placeholders only {{MaxSizeMB}} and {{SampleIntervalSeconds}}."""

    def read(self, name):
        with open(os.path.join(COLLECTOR, name), encoding='utf-8') as f:
            return f.read()

    def lines(self, name):
        return [l.strip() for l in self.read(name).splitlines() if l.strip() and not l.startswith('#')]

    def test_counters_equal_list(self):
        xml = self.read('PerfmonBlackbox.template.xml')
        got = [c.replace('&amp;', '&') for c in re.findall(r'<Counter>(.*?)</Counter>', xml)]
        self.assertEqual(got, self.lines('PerfmonBlackbox.counters.txt'))
        self.assertEqual(len(got), 36)

    def test_no_machine_or_dated_fields(self):
        xml = self.read('PerfmonBlackbox.template.xml')
        for tag in ('LatestOutputLocation', 'OutputLocation', 'ComputerName', 'Security'):
            self.assertNotIn(f'<{tag}>', xml)
        self.assertIsNone(re.search(r'\d{8}', xml), 'a dated path')
        self.assertEqual(sorted(set(re.findall(r'\{\{(\w+)\}\}', xml))), ['MaxSizeMB', 'SampleIntervalSeconds'])

    def test_groups(self):
        g1, g2, g3 = (self.lines(f'PerfmonBlackbox.counters-{g}.txt') for g in ('g1-system', 'g2-process', 'g3-web'))
        self.assertEqual((len(g1), len(g2), len(g3)), (12, 2, 6))
        base = set(self.lines('PerfmonBlackbox.counters.txt'))
        self.assertFalse(base & (set(g1) | set(g2) | set(g3)), 'a group repeats one of the 36')
        procs = [c for c in base | set(g2) if c.startswith('\\Process(*)\\')]
        self.assertEqual(len(procs), 10)  # P22: the 10 selected Process counters, never Process(*)\*
        self.assertNotIn('\\Process(*)\\*', base | set(g1) | set(g2) | set(g3))


class L08Policies(unittest.TestCase):
    """policy/build_policies.py: two definitions, one resource type each, the same parameters mapped to
    [BlackboxFiles]Files, contentUri/contentHash pinned, parameterHash in step with configurationParameter, and
    the per-machine writer role assignment with the ABAC prefix condition."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, os.path.join(PB, 'policy'))
        import build_policies as bp
        cls.d = {k: bp.definition(k, 'https://example.invalid/PerfmonBlackbox.zip', 'AB' * 32, '1.0.0') for k in ('vm', 'arc')}

    def test_one_type_each(self):
        self.assertEqual(self.d['vm']['properties']['policyRule']['if']['allOf'][0]['equals'], 'Microsoft.Compute/virtualMachines')
        self.assertEqual(self.d['arc']['properties']['policyRule']['if']['allOf'][0]['equals'], 'Microsoft.HybridCompute/machines')

    def test_same_parameters(self):
        pv, pa = self.d['vm']['properties']['parameters'], self.d['arc']['properties']['parameters']
        self.assertEqual(pv, pa)
        for p in ('MaxSizeMB', 'SampleIntervalSeconds', 'ExportEveryHours', 'StorageAccountResourceId', 'ContainerName', 'LocalKeepMB'):
            self.assertIn(p, pv)
        self.assertEqual((pv['MaxSizeMB']['defaultValue'], pv['SampleIntervalSeconds']['defaultValue'],
                          pv['ExportEveryHours']['defaultValue']), ('512', '10', '4'))

    def test_assignment_and_hash(self):
        for d in self.d.values():
            det = d['properties']['policyRule']['then']['details']
            gc = det['deployment']['properties']['template']['resources'][0]['properties']['guestConfiguration']
            self.assertEqual(gc['contentHash'], 'AB' * 32)
            self.assertEqual(gc['assignmentType'], 'ApplyAndAutoCorrect')
            names = [c['name'] for c in gc['configurationParameter']]
            self.assertTrue(all(n.startswith('[BlackboxFiles]Files;') for n in names))
            h = det['existenceCondition']['allOf'][1]['equals']
            self.assertEqual(re.findall(r"'(\[BlackboxFiles\][^']+)'", h), names)

    def test_writer_role_condition(self):
        det = self.d['vm']['properties']['policyRule']['then']['details']
        role = det['deployment']['properties']['template']['resources'][1]
        self.assertEqual(role['resourceGroup'], "[split(parameters('StorageAccountResourceId'), '/')[4]]")
        ra = role['properties']['template']['resources'][0]['properties']
        self.assertEqual(ra['conditionVersion'], '2.0')
        self.assertTrue(ra['condition'].endswith("StringStartsWith ''', parameters('prefix'), '/'))')]"))
        self.assertIn('blobs/write', ra['condition'])
        self.assertIn('toLower(', role['properties']['parameters']['prefix']['value'])


if __name__ == '__main__':
    unittest.main()
