#!/bin/sh

[ -z "$TMUX_BIN" ] && {
    echo "ERROR: This can only be run inside tmux"
    exit 1
}

d_pkt_loss=$(cd "${0%/*}/.." && pwd)

# shellcheck disable=SC2154
pane_height=$($TMUX_BIN display-message -p -t "$TMUX_PANE" '#{pane_height}')
use_height=$((pane_height - 2))

"$d_pkt_loss"/scripts/all-data.sh show | tail -n "$use_height"
