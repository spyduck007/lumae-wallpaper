#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
BUILD="${2:-}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || {
  echo "usage: $0 <version, e.g. 0.2.0> <integer build>" >&2
  exit 1
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "usage: $0 <version> <integer build>" >&2
  exit 1
}

python3 - "$VERSION" "$BUILD" <<'PY'
from pathlib import Path
import re, sys
version, build = sys.argv[1:]
p = Path('project.yml')
s = p.read_text()
s, n1 = re.subn(r'MARKETING_VERSION: .*', f'MARKETING_VERSION: {version}', s, count=1)
s, n2 = re.subn(r'CURRENT_PROJECT_VERSION: .*', f'CURRENT_PROJECT_VERSION: {build}', s, count=1)
if n1 != 1 or n2 != 1:
    raise SystemExit('Could not update project versions')
p.write_text(s)
PY

./scripts/generate-project.sh

echo "Prepared Lumae $VERSION ($BUILD)."
echo "Review changes, commit them, then build and publish the release."
