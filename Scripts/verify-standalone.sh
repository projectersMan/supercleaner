#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
CACHE=${PROJECT_ROOT}/.build
/bin/mkdir -p ${PROJECT_ROOT}/Tests/temporary
WORK=$(/usr/bin/mktemp -d ${PROJECT_ROOT}/Tests/temporary/standalone.XXXXXX)
HID_CACHE=0
cleanup() {
  if (( HID_CACHE )); then
    if [[ -e ${CACHE} ]]; then
      print -u2 "Cannot restore hidden cache; preserved at ${WORK}/cache"
      return 1
    fi
    /bin/mv ${WORK}/cache ${CACHE}
  fi
  /bin/rmdir ${WORK}
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -d ${CACHE} && ! -L ${CACHE} ]]; then
  /bin/mv ${CACHE} ${WORK}/cache
  HID_CACHE=1
fi

/bin/zsh ${SCRIPT_DIR}/verify-app.sh
/usr/bin/python3 - ${PROJECT_ROOT}/build/SuperCleaner.app <<'PY'
import json
import math
from pathlib import Path
import platform
import subprocess
import sys

if platform.machine() != 'arm64' or int(platform.mac_ver()[0].split('.')[0]) < 14:
    print('SKIP: bundled inference requires Apple Silicon and macOS 14 or later')
    raise SystemExit(0)
app = Path(sys.argv[1])
resources = app / 'Contents/Resources/SuperCleaner_AgentOverlapAI.bundle'
models = [resources / 'Models/embeddinggemma-2-Q8_0.gguf',
          resources / 'Contents/Resources/Models/embeddinggemma-2-Q8_0.gguf']
model = next(p for p in models if p.is_file())
result = subprocess.run([str(app / 'Contents/MacOS/AgentInference'), str(model)],
    input=json.dumps(['Verify bundled inference resources.']) + '\n',
    text=True, capture_output=True, check=True, timeout=120)
frames = [line.removeprefix('SUPERCLEANER_EMBEDDING:') for line in result.stdout.splitlines()
          if line.startswith('SUPERCLEANER_EMBEDDING:')]
assert len(frames) == 1, 'Missing inference response'
vectors = json.loads(frames[0])
assert len(vectors) == 1 and len(vectors[0]) == 768
assert all(math.isfinite(value) for value in vectors[0])
assert any(abs(value) > 1e-8 for value in vectors[0]), 'Empty embedding'
print('PASS: bundled model produced a finite 768-dimensional embedding without build resources')
PY
print 'PASS: packaged app runs without SwiftPM build resources; original cache restored on exit'
