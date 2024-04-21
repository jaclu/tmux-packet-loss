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

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$0")")
log_prefix="hok"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

ses_count="$($TMUX_BIN ls | wc -l)"

if [[ "$ses_count" -eq 0 ]]; then
    log_it "No remaining sessions, shutting down monitor process"
    $scr_controler stop
    #
    #  remove some stat files that will be generated with
    #  fresh content on next run
    #
    rm -f "$f_param_cache"
    rm -f "$f_previous_loss"
else
    log_it "Sessions remaining on this server"
fi
