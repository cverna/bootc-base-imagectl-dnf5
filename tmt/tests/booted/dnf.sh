#!/bin/bash
set -euo pipefail
dnf -y makecache
dnf repoquery bootc >/dev/null
