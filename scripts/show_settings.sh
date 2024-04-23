#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="shw"

#
# ensures terminals from other sessions will read their own tmux config
# if the cwd happens to be in another instance of this plugin
#
use_param_cache=false

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

show_item() {
    local label="$1"
    local value="$2"
    local default="$3"
    if [[ "$label" = "headers" ]]; then
        echo "     default  user setting config vairable"
        echo "------------  ------------ ---------------"

    else
        msg="$label [$value]"
        if [[ "$value" = "$default" ]]; then
            msg="$(printf "%13s              %-20s" \
                "[$value]" "$label")"
        else
            msg="$(printf "%13s %12s %-20s" \
                "[$default]" "[$value]" "$label")"
        fi
        echo "$msg"
    fi
}

session="$(get_tmux_socket)"

echo "=====   Config for  session: $session   ====="

[[ "$session" = "standalone" ]] && {
    echo
    echo "*** This is not inside any tmux session - only defaults will be displayed!"
    echo

    use_param_cache=false
    get_settings
}

show_item "headers"
show_item cfg_ping_count "$cfg_ping_count" "$default_ping_count"

[[ "$session" != "standalone" ]] && {
    status_interval="$($TMUX_BIN display -p "#{status-interval}" 2>/dev/null)"
    if [[ -n "$status_interval" ]]; then
        msg_interval="status bar update frequency = [$status_interval]"
        req_interval="$(echo "$cfg_ping_count - 1" | bc)"
        if [[ "$req_interval" != "$status_interval" ]]; then
            msg_interval="$msg_interval  - tmux status-interval is recomended to be arround: $req_interval"
        fi
        echo "$msg_interval"
        echo
    fi
    show_item "headers"
}

show_item cfg_ping_host "$cfg_ping_host" "$default_ping_host"
show_item cfg_history_size "$cfg_history_size" "$default_history_size"

show_item cfg_weighted_average "$cfg_weighted_average" "$default_weighted_average"
show_item cfg_display_trend "$cfg_display_trend" "$default_display_trend"

show_item cfg_level_disp "$cfg_level_disp" "$default_level_disp"
show_item cfg_level_alert "$cfg_level_alert" "$default_level_alert"
show_item cfg_level_crit "$cfg_level_crit" "$default_level_crit"

show_item cfg_hist_avg_display "$cfg_hist_avg_display" "$default_hist_avg_display"

show_item cfg_hist_avg_minutes "$cfg_hist_avg_minutes" "$default_hist_avg_minutes"
show_item cfg_hist_separator "$cfg_hist_separator" "$default_hist_separator"

show_item cfg_color_alert "$cfg_color_alert" "$default_color_alert"
show_item cfg_color_crit "$cfg_color_crit" "$default_color_crit"
show_item cfg_color_bg "$cfg_color_bg" "$default_color_bg"

show_item cfg_prefix "$cfg_prefix" "$default_prefix"
show_item cfg_suffix "$cfg_suffix" "$default_suffix"

show_item cfg_hook_idx "$cfg_hook_idx" "$default_hook_idx"

[[ -n "$log_file" ]] && {
    echo
    echo "log_file in use: $log_file"
}
