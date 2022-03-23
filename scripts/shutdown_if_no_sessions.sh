#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.0.1 2022-03-22
#

CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PARRENT_DIR="$(dirname -- "$CURRENT_DIR")"
. "$CURRENT_DIR/utils.sh"


ses_count="$(tmux ls | wc -l)"

log_it "check_shutdown.sh, session count [$ses_count]"

if [ "$ses_count" -eq 0 ]; then
    log_it "No remaining sessions, shutting down monitor process"
    "$PARRENT_DIR/packet-loss.tmux" stop
fi
