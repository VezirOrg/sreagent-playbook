"""Local tests of sql-mcp (no Azure, synthetic values only). Run: tests/run.sh L01 | L03 (from the playbook folder:
python3 -m unittest tests.local.test_local). L01 needs PowerShell 7 (`pwsh` on the PATH, or $PWSH)."""
import hashlib, json, os, re, shutil, subprocess, tempfile, unittest, uuid, zipfile

PB = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PKG = os.path.join(PB, 'package')
VIEWS = ['wait_stats', 'perf_counters', 'sys_memory', 'memory_clerks', 'sessions', 'requests', 'query_stats']


def pwsh():
    p = os.environ.get('PWSH') or shutil.which('pwsh')
    if not p:
        raise unittest.SkipTest('PowerShell 7 (pwsh) not found: set PWSH or put pwsh on the PATH')
    return p


class L01DabConfig(unittest.TestCase):
    """04-dab-config.ps1 writes the placeholder-root layout in the production auth shape."""

    def run_config(self, cfg, *extra):
        cmd = [pwsh(), '-NoProfile', '-NonInteractive', '-File', os.path.join(PKG, '04-dab-config.ps1'), *extra]
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120)

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.tenant, self.app = str(uuid.uuid4()), str(uuid.uuid4())   # synthetic, made up at run time
        self.servers = ['sql1', 'sql2', 'sql3']
        r = self.run_config(self.tmp, '-Servers', ','.join(self.servers), '-TenantId', self.tenant, '-AppId', self.app,
                            '-Domain', 'Contoso.Local', '-ConfigDir', self.tmp, '-AllowedHosts', 'vm1,vm1.contoso.local')
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def load(self, name):
        with open(os.path.join(self.tmp, name), encoding='utf-8') as f:
            raw = f.read()
        self.assertFalse(raw.startswith('﻿'), f'{name} has a BOM')
        return json.loads(raw)

    def test_root_is_a_placeholder(self):
        root = self.load('dab-config.json')
        ds = root['data-source']
        self.assertIn('Server=dab-placeholder.invalid;', ds['connection-string'])
        self.assertIs(ds['health']['enabled'], False)
        self.assertEqual(root['entities'], {})
        self.assertEqual(root['data-source-files'], [f'{s}.json' for s in self.servers])

    def test_runtime_is_read_only_mcp_with_entra_v2(self):
        rt = self.load('dab-config.json')['runtime']
        self.assertIs(rt['rest']['enabled'], False)
        self.assertIs(rt['graphql']['enabled'], False)
        self.assertIs(rt['cache']['enabled'], False)
        mcp = rt['mcp']
        self.assertEqual(mcp['path'], '/mcp')
        self.assertEqual(mcp['allowed-hosts'], ['vm1', 'vm1.contoso.local'])
        on = sorted(k for k, v in mcp['dml-tools'].items() if v)
        self.assertEqual(on, ['aggregate-records', 'describe-entities', 'read-records'])
        host = rt['host']
        self.assertEqual(host['mode'], 'production')
        self.assertEqual(host['authentication']['provider'], 'EntraId')
        self.assertEqual(host['authentication']['jwt'],
                         {'audience': self.app, 'issuer': f'https://login.microsoftonline.com/{self.tenant}/v2.0'})

    def test_one_file_per_server_with_seven_views_readable_only_by_the_role(self):
        for s in self.servers:
            doc = self.load(f'{s}.json')
            cs = doc['data-source']['connection-string']
            self.assertTrue(cs.startswith(f'Server={s}.contoso.local;Database=master;Integrated Security=True;'), cs)
            self.assertEqual(doc['data-source']['health']['name'], s)
            self.assertEqual(sorted(doc['entities']), sorted(f'{s}_{v}' for v in VIEWS))
            for name, e in doc['entities'].items():
                self.assertEqual(e['source']['type'], 'view')
                self.assertTrue(e['source']['object'].startswith('sys.dm_'))
                self.assertEqual(e['permissions'], [{'role': 'MCP.Read', 'actions': ['read']}], name)
                self.assertIs(e['cache']['enabled'], False)
                self.assertIsInstance(e['fields'], list)
                self.assertTrue(any(f.get('primary-key') for f in e['fields']), f'{name}: no key column')
            ws = doc['entities'][f'{s}_wait_stats']['fields']
            self.assertTrue(any(f['name'] == 'wait_type' and f.get('description') for f in ws))

    def test_no_anonymous_or_authenticated_role_anywhere(self):
        for n in ['dab-config.json'] + [f'{s}.json' for s in self.servers]:
            with open(os.path.join(self.tmp, n), encoding='utf-8') as f:
                raw = f.read()
            self.assertNotIn('"anonymous"', raw)
            self.assertNotIn('"authenticated"', raw)

    def test_second_run_backs_up_the_previous_files(self):
        r = self.run_config(self.tmp, '-Servers', 'sql1', '-TenantId', self.tenant, '-AppId', self.app,
                            '-Domain', 'contoso.local', '-ConfigDir', self.tmp, '-AllowedHosts', 'vm1')
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        baks = [d for d in os.listdir(self.tmp) if d.startswith('backup-')]
        self.assertEqual(len(baks), 1)
        self.assertEqual(sorted(os.listdir(os.path.join(self.tmp, baks[0]))),
                         sorted(['dab-config.json'] + [f'{s}.json' for s in self.servers]))
        self.assertEqual(self.load('dab-config.json')['data-source-files'], ['sql1.json'])

    def test_app_id_is_required(self):
        out = tempfile.mkdtemp()
        try:
            r = self.run_config(out, '-Servers', 'sql1', '-TenantId', self.tenant, '-Domain', 'contoso.local',
                                '-ConfigDir', out, '-AllowedHosts', 'vm1')
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(os.listdir(out), [])
        finally:
            shutil.rmtree(out, ignore_errors=True)


class L03Package(unittest.TestCase):
    """build.sh is deterministic and ships exactly the package files."""

    EXPECTED = sorted(['01-ad-prep.ps1', '02-sql-login.sql', '03-dab-install.ps1', '04-dab-config.ps1', 'README.txt',
                       'tools/mcp-call.ps1', 'admin/entra-setup.sh', 'admin/entra-setup.ps1',
                       'agent/connect-agent.sh', 'agent/connect-agent.ps1'])

    def build(self, out):
        r = subprocess.run(['sh', os.path.join(PKG, 'build.sh'), '0.0.0-test', out], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(out, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()

    def test_deterministic_and_complete(self):
        d = tempfile.mkdtemp()
        try:
            a = self.build(os.path.join(d, 'a.zip'))
            b = self.build(os.path.join(d, 'b.zip'))
            self.assertEqual(a, b)
            with zipfile.ZipFile(os.path.join(d, 'a.zip')) as z:
                self.assertEqual(sorted(z.namelist()), self.EXPECTED)
                readme = z.read('README.txt').decode()
                self.assertIn('Data API builder 2.1.5', readme)
                for n in z.namelist():   # nothing tenant-specific: no GUID, no private IPv4 in the package
                    t = z.read(n).decode()
                    self.assertIsNone(re.search(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', t), n)
                    self.assertIsNone(re.search(r'\b(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+\b', t), n)
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
