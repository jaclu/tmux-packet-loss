#!/bin/sh
#  shellcheck disable=SC2034
#
#   Copyright (c) 2026: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
# Displays almost a screenfull of loss stats
# If given a param it will loop, displaying every $1 seconds
#
fill_screen() {
    # clear

    # shellcheck disable=SC2154
    pane_height=$($TMUX_BIN display-message -p -t "$TMUX_PANE" '#{pane_height}')
    use_height=$((pane_height - 2))

    "$d_pkt_loss"/scripts/all-data.sh show | tail -n "$use_height"
}

loop_forever() {
    while true; do
        fill_screen
        sleep "$t_sleep" || {
            echo
            echo "Bad sleep time: [$t_sleep]"
            exit 1
        }
    done
    exit 0
}

#===============================================================
#
#   Main
#
#===============================================================

t_sleep="$1"
d_pkt_loss=$(cd "${0%/*}/.." && pwd)

[ -z "$TMUX_BIN" ] && {
    echo "ERROR: This can only be run inside tmux"
    exit 1
}

[ -n "$t_sleep" ] && loop_forever

fill_screen
exit 0
