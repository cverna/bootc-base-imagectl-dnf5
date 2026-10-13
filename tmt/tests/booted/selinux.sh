#!/bin/bash
set -euo pipefail
test "$(getenforce)" = Enforcing
