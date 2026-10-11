#!/usr/bin/env bash
# scrub-check.sh: fail if anything about to enter this PUBLIC repo looks like a secret, a forbidden file or a
# real name from the private denylist. Used by the git hooks (.githooks/) and by CI.
#
#   scripts/scrub-check.sh                 every tracked file plus untracked, not-ignored files (working tree)
#   scripts/scrub-check.sh --staged        the index: staged file names and staged contents (pre-commit)
#   scripts/scrub-check.sh --range A..B    every commit in the range: file names, diffs, messages (pre-push)
#   scripts/scrub-check.sh --msg FILE      one commit message (commit-msg)
#   scripts/scrub-check.sh --self-test     prove each check fires on a planted hit (no real name used)
#
# Denylist (private, never committed): $SCRUB_DENYLIST, else files/source-data/denylist.txt. One name per line,
# '#' for comments. Matched like the masker (rule b): case-insensitive; a name of 5+ characters anywhere, a shorter
# one only as a whole word. No denylist = FAIL, unless SCRUB_ALLOW_NO_DENYLIST=1 (CI only: it has no denylist).
#
# Output never contains a hit's text: only the check, the place (file:line or commit) and, for the denylist,
# the entry number and its length. Exit 0 = clean, 1 = hits, 2 = usage or setup error.
set -u
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "scrub-check: not in a git repo"; exit 2; }
cd "$root" || exit 2
exec python3 -I - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = os.getcwd()
SELF = 'scripts/scrub-check.sh'
ALLOW = 'scripts/scrub-allow.txt'

# --- forbidden file names (path relative to the repo root) ---
SYNTH_OK = re.compile(r'^playbooks/[^/]+/tests/fixtures/synthetic/')
BAD_NAMES = [
    ('env file', re.compile(r'(^|/)\.env(\.[^/]*)?$|(^|/)\.envrc$')),
    ('files/ (Drive, private)', re.compile(r'^files(/|$)')),
    ('key or certificate', re.compile(r'\.(pem|pfx|p12|key|cer|crt|publishsettings|kdbx)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$', re.I)),
    ('capture or data file', re.compile(r'\.(blg|etl|db|sqlite|sqlite3|zip|7z|bak)$', re.I)),
    ('mapping or denylist file', re.compile(r'(mapping|denylist)[^/]*\.(csv|txt)$', re.I)),
    ('az/azd config dir', re.compile(r'(^|/)\.(azure|azure-cli|azd-config)/')),
]
CSV = re.compile(r'\.(csv|tsv)$', re.I)

# --- secret patterns (built from parts so this file does not match itself) ---
def rx(*parts, flags=0):
    return re.compile(''.join(parts), flags)

SECRETS = [
    ('storage account key / conn string', rx('Account', 'Key', r'\s*=\s*[A-Za-z0-9+/]{20,}')),
    ('SAS signature', rx(r'[?&]s', r'ig=[A-Za-z0-9%+/=]{20,}')),
    ('shared access signature', rx('SharedAccess', 'Signature', r'\s*=\s*\S{10,}')),
    ('JWT', rx('ey', r'J[A-Za-z0-9_-]{10,}\.ey', r'J[A-Za-z0-9_-]{10,}')),
    ('private key block', rx('-----BEGIN ', r'[A-Z ]*PRIVATE ', 'KEY-----')),
    ('GitHub token', rx(r'\b(gh[pousr]_|github_', r'pat_)[A-Za-z0-9_]{20,}')),
    ('AWS key id', rx(r'\bAK', r'IA[0-9A-Z]{16}\b')),
    ('Entra client secret', rx(r'\b[A-Za-z0-9_~.-]{3}8Q', r'~[A-Za-z0-9_~.-]{31,34}\b')),
    ('password/secret assignment',
     rx(r'(?i)\b(pass', r'word|pwd|client_?sec', r'ret|api_?key)\b["\']?\s*[:=]\s*["\']?(?!<|\$|\{|%|\[|\(|os\.|env)[^\s"\'<>]{6,}')),
    ('GUID', rx(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b')),
    ('private IPv4', rx(r'\b(10\.\d{1,3}|172\.(1[6-9]|2\d|3[01])|192\.168)\.\d{1,3}\.\d{1,3}\b')),
    ('email address', rx(r'\b[A-Za-z0-9._%+-]+@(?!anthropic\.com\b|users\.noreply\.github\.com\b)', r'[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')),
]


def load_allow():
    """Public, allowed values (e.g. built-in role definition GUIDs), one per line in scripts/scrub-allow.txt."""
    p = os.path.join(ROOT, ALLOW)
    if not os.path.exists(p):
        return set()
    with open(p, encoding='utf-8') as f:
        return {l.split('#', 1)[0].strip().lower() for l in f if l.split('#', 1)[0].strip()}


def name_pattern(real, min_len=5):
    if len(real) >= min_len:
        return re.escape(real)
    return r'(?<![A-Za-z0-9])' + re.escape(real) + r'(?![A-Za-z0-9])'


def load_deny():
    path = os.environ.get('SCRUB_DENYLIST') or os.path.join(ROOT, 'files', 'source-data', 'denylist.txt')
    if not os.path.isfile(path):
        if os.environ.get('SCRUB_ALLOW_NO_DENYLIST') == '1':
            print('scrub-check: NOTE no denylist (SCRUB_ALLOW_NO_DENYLIST=1): real names NOT checked')
            return []
        print('scrub-check: FAILED no denylist found (set SCRUB_DENYLIST or put it at files/source-data/denylist.txt)')
        sys.exit(1)
    with open(path, encoding='utf-8') as f:
        deny = [l.strip() for l in f if l.strip() and not l.lstrip().startswith('#')]
    return [(i, len(d), re.compile(name_pattern(d), re.I)) for i, d in enumerate(deny, start=1)]


ALLOWED = load_allow()
hits = []


def scan_text(where, text, deny, secrets=True):
    for n, line in enumerate(text.splitlines(), start=1):
        if secrets:
            for label, pat in SECRETS:
                for m in pat.finditer(line):
                    if m.group(0).lower() in ALLOWED:
                        continue
                    hits.append(f'{where}:{n}: {label}')
                    break
        for i, ln, pat in deny:
            if pat.search(line):
                hits.append(f'{where}:{n}: denylist entry {i} (length {ln})')


def check_name(path, deny):
    for label, pat in BAD_NAMES:
        if pat.search(path):
            hits.append(f'{path}: forbidden file ({label})')
    if CSV.search(path) and not SYNTH_OK.search(path):
        hits.append(f'{path}: forbidden file (CSV outside playbooks/*/tests/fixtures/synthetic/)')
    scan_text(f'{path} (file name)', path, deny, secrets=False)


def git(*a, inp=None):
    return subprocess.run(['git', *a], capture_output=True, input=inp, check=True).stdout


def decode(b):
    if b'\x00' in b[:8000]:
        return None
    return b.decode('utf-8', errors='replace')


def scan_file(path, data, deny):
    check_name(path, deny)
    text = decode(data)
    if text is None:
        hits.append(f'{path}: binary file (not allowed; nothing binary enters this repo)')
        return
    scan_text(path, text, deny, secrets=(path != SELF))


def mode_tree(deny):
    out = git('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    for p in sorted({x for x in out.decode().split('\0') if x}):
        if os.path.isfile(p):
            with open(p, 'rb') as f:
                scan_file(p, f.read(), deny)


def mode_staged(deny):
    out = git('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR')
    for p in [x for x in out.decode().split('\0') if x]:
        scan_file(p, git('show', f':{p}'), deny)


def mode_range(rng, deny):
    for c in git('rev-list', rng).decode().split():
        msg = git('log', '-1', '--format=%B', c).decode('utf-8', 'replace')
        scan_text(f'commit {c[:12]} (message)', msg, deny)
        names = git('diff-tree', '--root', '--no-commit-id', '-r', '--name-only', '-z', '--diff-filter=ACMR', c)
        for p in [x for x in names.decode().split('\0') if x]:
            data = git('show', f'{c}:{p}')
            check_name(f'{p} @{c[:12]}', deny)
            text = decode(data)
            if text is None:
                hits.append(f'{p} @{c[:12]}: binary file')
            else:
                scan_text(f'{p} @{c[:12]}', text, deny, secrets=(p != SELF))


def self_test():
    """Planted values are assembled at run time; none of them is a real secret or a real name."""
    global hits
    deny = [(1, 7, re.compile(name_pattern('Zq' + 'xwvut'), re.I)), (2, 3, re.compile(name_pattern('Q' + 'zx'), re.I))]
    cases = [
        ('Account' + 'Key=' + 'A' * 40, True), ('?sv=1&s' + 'ig=' + 'B' * 30, True),
        ('-----BEGIN ' + 'RSA PRIVATE ' + 'KEY-----', True), ('pass' + 'word = ' + 'hunter2xyz', True),
        ('pass' + 'word = <from .env>', False), ('ab12cd34-' + 'ab12-ab12-ab12-' + 'ab12cd34ef56', True),
        ('10.' + '1.2.3', True), ('server ' + 'zqXWVUT' + '01 is slow', True), ('the qzx pool', True),
        ('qzxy is fine', False), ('plain text', False),
    ]
    bad = 0
    for text, want in cases:
        hits = []
        scan_text('t', text, deny)
        if bool(hits) != want:
            bad += 1
            print(f'self-test FAIL: case expected {"hit" if want else "clean"}')
    for name, want in [('.env', True), ('a/.envrc', True), ('files/x', True), ('x.blg', True),
                       ('playbooks/p/tests/fixtures/synthetic/a.csv', False), ('data/a.csv', True), ('README.md', False)]:
        hits = []
        check_name(name, [])
        if bool(hits) != want:
            bad += 1
            print(f'self-test FAIL: file name {name}')
    print('scrub-check self-test: ' + ('PASS' if not bad else f'FAILED ({bad})'))
    sys.exit(1 if bad else 0)


args = sys.argv[1:]
if args[:1] == ['--self-test']:
    self_test()
deny = load_deny()
if not args:
    mode_tree(deny)
elif args[0] == '--staged':
    mode_staged(deny)
elif args[0] == '--range' and len(args) == 2:
    mode_range(args[1], deny)
elif args[0] == '--msg' and len(args) == 2:
    with open(args[1], encoding='utf-8', errors='replace') as f:
        scan_text('commit message', ''.join(l for l in f if not l.startswith('#')), deny)
else:
    print('usage: scrub-check.sh [--staged | --range A..B | --msg FILE | --self-test]')
    sys.exit(2)
for h in hits:
    print('  ' + h)
print(f'scrub-check: {"clean" if not hits else f"FAILED ({len(hits)} hits)"}'
      f' [{len(deny)} denylist entries]')
sys.exit(1 if hits else 0)
PY
