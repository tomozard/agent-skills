#!/usr/bin/env bash
# Behaviour tests for .agents/extensions/role-guard.ts and auto-compact.ts.
# Node has to strip TypeScript on the fly; skip loudly rather than silently pass
# when the local node is too old to do that.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! node -e 'import("node:util").then(() => process.exit(0))' 2>/dev/null; then
  echo "extensions test: skipped (node missing)"
  exit 0
fi
if ! node --experimental-strip-types -e 'process.exit(0)' 2>/dev/null; then
  echo "extensions test: skipped (node $(node -v) cannot strip types)"
  exit 0
fi

node --experimental-strip-types "$ROOT/tests/extensions.test.mjs" "$ROOT/.agents/extensions"