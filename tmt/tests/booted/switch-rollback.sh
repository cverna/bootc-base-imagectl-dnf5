#!/bin/bash
# Upgrade with `bootc switch` (to a locally derived image) and downgrade with
# `bootc rollback`, rebooting between the stages. Mirrors bootc's own
# test-rollback. Unlike a reinstall, switch/rollback keep /var (it is state),
# so tmt's workdir survives the reboots.
#
# TMT_REBOOT_COUNT selects the stage: 0 stages the upgrade, 1 verifies it and
# queues the rollback, 2 verifies the downgrade.
set -euo pipefail

marker=/usr/share/bootc-base-imagectl-upgrade
base=localhost/bootc
derived=localhost/bootc-derived

img() { bootc status --json | jq -r '.status.booted.image.image'; }
rollback_queued() { bootc status --json | jq -r '.status.rollbackQueued'; }

case "${TMT_REBOOT_COUNT:-0}" in
0)
    # Don't let the automatic update agent undo our rollback.
    systemctl mask --now bootc-fetch-apply-updates.timer >/dev/null 2>&1 || true

    # Stage an "upgrade": a derived image built from the running one.
    bootc image copy-to-storage
    test ! -e "$marker"
    tmp=$(mktemp -d)
    printf 'FROM %s\nRUN touch %s\n' "$base" "$marker" > "$tmp/Containerfile"
    podman build -t "$derived" -f "$tmp/Containerfile" "$tmp"
    test "$(rollback_queued)" = false
    bootc switch --transport containers-storage "$derived"
    tmt-reboot
    ;;
1)
    # We must be running the upgraded image.
    test -e "$marker"
    case "$(img)" in
        *bootc-derived*) ;;
        *) echo "unexpected image after switch: $(img)" >&2; exit 1 ;;
    esac
    test "$(rollback_queued)" = false
    # Downgrade: queue a rollback to the previous deployment.
    bootc rollback
    test "$(rollback_queued)" = true
    tmt-reboot
    ;;
2)
    # We must be back on the original image.
    test ! -e "$marker"
    case "$(img)" in
        *bootc-derived*) echo "still on the derived image: $(img)" >&2; exit 1 ;;
        *localhost/bootc*) ;;
        *) echo "unexpected image after rollback: $(img)" >&2; exit 1 ;;
    esac
    test "$(rollback_queued)" = false
    ;;
*)
    echo "unexpected TMT_REBOOT_COUNT=${TMT_REBOOT_COUNT:-}" >&2
    exit 1
    ;;
esac
