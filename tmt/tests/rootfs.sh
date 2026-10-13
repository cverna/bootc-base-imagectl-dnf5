#!/bin/bash
# Reuse the repository's read-only rootfs cases against the container
# under test (the tmt container provisioner starts our image).
set -euo pipefail
"${TMT_TREE}/tests/rootfs/run" /
