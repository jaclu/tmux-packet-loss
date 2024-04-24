#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  If no more sessions are running, terminate monitor_packet_loss.sh
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="nos"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

ses_count="$($TMUX_BIN ls | wc -l)"

if [[ "$ses_count" -eq 0 ]]; then
    log_it "No remaining sessions, shutting down monitor process"
    $scr_ctrl_monitor stop || {
        echo "*** $(basename "$scr_ctrl_monitor") Failed to shut down monitor"
        exit 1
    }
    #
    #  remove some stat files that will be generated with
    #  fresh content on next run
    #
    rm -f "$f_param_cache"
    rm -f "$f_previous_loss"
    log_it "$plugin_name - monitoring has shutdown, tmp files have been deleted"
else
    log_it "Sessions remaining on this server"
fi
