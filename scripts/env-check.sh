#!/bin/sh
# env-check.sh: the ONLY vetted way to check that credentials load (R15). Prints, per variable: name, set/unset,
# length. Never a value, never part of a value.
#   direnv exec . scripts/env-check.sh AZURE_CLIENT_ID AZURE_CLIENT_SECRET ...
# With no arguments it checks the usual lab names.
exec python3 -I - "$@" <<'PY'
import os, sys
names = sys.argv[1:] or ['AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
                         'AZURE_LOCATION', 'AZURE_CONFIG_DIR', 'AZD_CONFIG_DIR']
for n in names:
    v = os.environ.get(n)
    print(f'{n}: ' + ('unset' if v is None else f'set, length {len(v)}'))
PY
