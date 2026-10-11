#!/bin/sh
# Run once per clone: point git at the versioned hooks in .githooks/ and self-test the scrub check.
set -eu
cd "$(git rev-parse --show-toplevel)"
chmod +x .githooks/* scripts/*.sh
git config core.hooksPath .githooks
echo "hooks installed: $(git config core.hooksPath)"
scripts/scrub-check.sh --self-test
