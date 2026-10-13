#!/bin/bash
set -euo pipefail
systemctl --failed --no-legend --no-pager
test -z "$(systemctl --failed --no-legend --no-pager)"
