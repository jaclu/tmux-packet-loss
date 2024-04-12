#!/bin/sh
# shellcheck disable=SC2154
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.1 2022-09-15
#
#  If no more sessions are running, terminate background packet loss processes
#

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

ses_count="$($TMUX_BIN ls | wc -l)"

log_it "$no_sessions_shutdown_scr - session count [$ses_count]"

if [ "$ses_count" -eq 0 ]; then
    log_it "No remaining sessions, shutting down monitor process"
    "$monitor_process_scr" stop
fi
