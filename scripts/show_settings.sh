#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$0")")
log_prefix="shw"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

show_item() {
    local label="$1"
    local value="$2"
    local default="$3"

    msg="$label [$value]"
    if [[ "$value" = "$default" ]]; then
        msg="$(printf "%-17s      (default) [%s]" "$label" "$value")"
    else
        msg="$(printf "%-17s [%s] - default: [%s]" "$label" "$value" \
            "$default")"
    fi
    echo "$msg"
}

echo "=====   Config for  session: $(get_tmux_socket)   ====="
ping_count="$(show_item cfg_ping_count "$cfg_ping_count" "$default_ping_count")"
echo "$ping_count"

status_interval="$($TMUX_BIN display -p "#{status-interval}")"
msg_interval="status bar update frequency = $status_interval"
req_interval="$(echo "$cfg_ping_count - 1" | bc)"
if [[ "$req_interval" != "$status_interval" ]]; then
    msg_interval="$msg_interval  - tmux status-interval is recomended to be arround: $req_interval"
fi
echo "$msg_interval"
echo

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

# The rest depends on a tmux session
[[ -z "$TMUX" ]] && exit 0

echo
echo "===   temp variables stored in tmux by scripts/display_losses.sh   ==="

# used to indicate trends
opt_last_value="@packet-loss_tmp_last_value"

# for caching
opt_last_check="@packet-loss_tmp_last_check"
opt_last_result="@packet-loss_tmp_last_result"

echo "last_check  [$(get_tmux_option "$opt_last_check" \
    "$opt_last_check unset")]"
echo "last_value  [$(get_tmux_option "$opt_last_value" \
    "$opt_last_value unset")]"
echo "last_result [$(get_tmux_option "$opt_last_result" \
    "$opt_last_result unset")]"
