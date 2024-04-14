#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.1 2022-09-15
#
#  If no more sessions are running, terminate background packet loss processes
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

echo ">>< $D_TPL_BASE_PATH"
exit 0
# #  shellcheck source=utils.sh
# . "$D_TPL_BASE_PATH/scripts/utils.sh"

log_prefix="hok"

this_app="$(basename "$0")"
ses_count="$($TMUX_BIN ls | wc -l)"

log_it "$this_app - ses_count: [$ses_count]"
log_it "$TMUX"
log_it "$this_app - session count [$ses_count]"

if [[ "$ses_count" -eq 0 ]]; then
    log_it "No remaining sessions, shutting down monitor process"
    "$scr_controler" stop
fi
