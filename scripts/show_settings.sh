#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

log_prefix="show"

show_item() {
    local label="$1"
    local value="$2"
    local default="$3"
    local bool="$4"

    [[ "$bool" = "b" ]] && {
        value="$(bool_param "$value" printable)"
        default="$(bool_param "$default" printable)"
    }
    msg="$label [$value]"
    if [[ "$value" = "$default" ]]; then
        msg="$(printf "%-17s      (default) [%s]" "$label" "$value")"
    else
        msg="$(printf "%-17s [%s] - default: [%s]" "$label" "$value" "$default")"
    fi
    echo "$msg"
}

echo "=====   All variables   ====="
show_item ping_host "$ping_host" "$default_host"
show_item ping_count "$ping_count" "$default_ping_count"
show_item history_size "$history_size" "$default_history_size"

show_item is_weighted_avg "$is_weighted_avg" "$default_weighted_average" b
show_item display_trend "$display_trend" "$default_display_trend" b

show_item lvl_disp "$lvl_disp" "$default_lvl_display"
show_item lvl_alert "$lvl_alert" "$default_lvl_alert"
show_item lvl_crit "$lvl_crit" "$default_lvl_crit"

show_item hist_avg_display "$hist_avg_display" "$default_hist_avg_display" b

show_item hist_stat_mins "$hist_stat_mins" "$default_hist_avg_minutes"
show_item hist_separator "$hist_separator" "$default_hist_avg_separator"

show_item color_alert "$color_alert" "$default_color_alert"
show_item color_crit "$color_crit" "$default_color_crit"
show_item color_bg "$color_bg" "$default_color_bg"

show_item loss_prefix "$loss_prefix" "$default_prefix"
show_item loss_suffix "$loss_suffix" "$default_suffix"

show_item hook_idx "$hook_idx" "$default_session_closed_hook"

echo
echo "===   temp variables stored in tmux by scripts/packet_loss.sh   ==="

# used to indicate trends
opt_last_value="@packet-loss_tmp_last_value"

# for caching
opt_last_check="@packet-loss_tmp_last_check"
opt_last_result="@packet-loss_tmp_last_result"

echo "last_check  [$(get_tmux_option "$opt_last_check" "$opt_last_check unset")]"
echo "last_value  [$(get_tmux_option "$opt_last_value" "$opt_last_value unset")]"
echo "last_result [$(get_tmux_option "$opt_last_result" "$opt_last_result unset")]"
