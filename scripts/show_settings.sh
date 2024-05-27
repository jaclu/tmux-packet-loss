#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

#
#  Ensures terminals will use their own tmux config, and not the
#  one that might be cached in this instance of the plugin
#
use_param_cache=false

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="shw"

#  shellcheck source=scripts/utils.sh
source "$D_TPL_BASE_PATH"/scripts/utils.sh

#  shellcheck source=scripts/pidfile_handler.sh
source "$scr_pidfile_handler"

show_item() {
    local label="$1"
    local value="$2"
    local default="$3"
    if [[ "$label" = "headers" ]]; then
        echo "     default  user setting  config vairable"
        echo "------------  ------------  ---------------"

    else
        if [[ "$value" = "$default" ]]; then
            msg="$(printf "%13s               %-20s" \
                "$value" "$label")"
        else
            msg="$(printf "%13s %12s  %-20s" \
                "$default" "$value" "$label")"
        fi
        echo "$msg"
    fi
}

session="$(get_tmux_socket)"

echo "=====   Config for  session: $session   ====="
echo

if [[ "$session" != "standalone" ]]; then
    this_tmux_pid="$(get_tmux_pid)"
    folder_tmux_pid="$(pidfile_show_process "$pidfile_tmux")"

    if [[ -n "$folder_tmux_pid" ]]; then
        [[ "$this_tmux_pid" = "$folder_tmux_pid" ]] || {
            echo
            echo "***  ERROR: This is not the folder for the $plugin_name"
            echo "***         used by your tmux session"
            echo "***         this tmux: [$this_tmux_pid] folders tmux pid [$folder_tmux_pid]"
            echo
            exit 1
        }
    else
        echo
        echo "***  WARNING:  Failed to verify if this is the $plugin_name"
        echo "***            folder for your tmux session"
        echo
    fi
else
    echo
    echo "*** This is not inside any tmux session - only defaults will be displayed!"
    echo
fi

show_item "headers"
show_item cfg_ping_count "$cfg_ping_count" "$default_ping_count"

[[ "$session" != "standalone" ]] && {
    status_interval="$($TMUX_BIN show-option -gqv status-interval 2>/dev/null)"
    if [[ -n "$status_interval" ]]; then
        req_interval="$(echo "$cfg_ping_count - 1" | bc)"
        if [[ "$req_interval" != "$status_interval" ]]; then
            echo "
To better match this cfg_ping_count, tmux status-interval is recomended
to be: $req_interval  currently is: $status_interval
            "
            show_item "headers"
        fi
    fi
}

show_item cfg_ping_host "$cfg_ping_host" "$default_ping_host"
show_item cfg_history_size "$cfg_history_size" "$default_history_size"
echo
show_item cfg_weighted_average "$cfg_weighted_average" "$default_weighted_average"
show_item cfg_display_trend "$cfg_display_trend" "$default_display_trend"
show_item cfg_hist_avg_display "$cfg_hist_avg_display" "$default_hist_avg_display"
echo
show_item cfg_level_disp "$cfg_level_disp" "$default_level_disp"
show_item cfg_level_alert "$cfg_level_alert" "$default_level_alert"
show_item cfg_level_crit "$cfg_level_crit" "$default_level_crit"
echo
show_item cfg_hist_avg_minutes "$cfg_hist_avg_minutes" "$default_hist_avg_minutes"
show_item cfg_hist_separator "$cfg_hist_separator" "$default_hist_separator"
echo
show_item cfg_color_alert "$cfg_color_alert" "$default_color_alert"
show_item cfg_color_crit "$cfg_color_crit" "$default_color_crit"
show_item cfg_color_bg "$cfg_color_bg" "$default_color_bg"
echo
show_item cfg_prefix "$cfg_prefix" "$default_prefix"
show_item cfg_suffix "$cfg_suffix" "$default_suffix"

[[ -n "$cfg_log_file" ]] && {
    echo
    echo "log_file in use: $cfg_log_file"
}

[[ -f "$pidfile_monitor" ]] && {
    echo
    echo "Monitor running: $(pidfile_show_process "$pidfile_monitor")"
}
