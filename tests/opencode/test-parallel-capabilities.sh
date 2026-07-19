#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

node "$SCRIPT_DIR/test-parallel-capabilities.mjs" \
  "$REPO_ROOT/.opencode/plugins/joshix.js"
echo "STATUS: PASSED"
