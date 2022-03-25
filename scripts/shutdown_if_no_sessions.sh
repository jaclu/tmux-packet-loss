#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.0 2022-03-25
#
#  If no more sessions are running, terminate background packet loss processes
#

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PARRENT_DIR="$(dirname -- "$CURRENT_DIR")"
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"


ses_count="$(tmux ls | wc -l)"

# shellcheck disable=SC2154
log_it "$no_sessions_shutdown_scr - session count [$ses_count]"

if [ "$ses_count" -eq 0 ]; then
    log_it "No remaining sessions, shutting down monitor process"
    "$PARRENT_DIR/packet-loss.tmux" stop
fi
