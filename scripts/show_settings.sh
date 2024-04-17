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
log_prefix="shw"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

show_item() {
    local label="$1"
    local value="$2"
    local default="$3"
    local bool="$4"

    [[ "$bool" = "b" ]] && value="$(bool_printable "$value")"
    msg="$label [$value]"
    if [[ "$value" = "$default" ]]; then
        msg="$(printf "%-17s      (default) [%s]" "$label" "$value")"
    else
        msg="$(printf "%-17s [%s] - default: [%s]" "$label" "$value" \
            "$default")"
    fi
    echo "$msg"
}

echo "=====   All variables session: $(get_tmux_socket)  ====="
show_item ping_host "$ping_host" "$default_ping_host"
show_item ping_count "$ping_count" "$default_ping_count"
show_item history_size "$history_size" "$default_history_size"

show_item weighted_average "$weighted_average" "$default_weighted_average"
show_item display_trend "$display_trend" "$default_display_trend"

show_item level_disp "$level_disp" "$default_level_disp"
show_item level_alert "$level_alert" "$default_level_alert"
show_item level_crit "$level_crit" "$default_level_crit"

show_item hist_avg_display "$hist_avg_display" "$default_hist_avg_display"

show_item hist_avg_minutes "$hist_avg_minutes" "$default_hist_avg_minutes"
show_item hist_separator "$hist_separator" "$default_hist_separator"

show_item color_alert "$color_alert" "$default_color_alert"
show_item color_crit "$color_crit" "$default_color_crit"
show_item color_bg "$color_bg" "$default_color_bg"

show_item prefix "$prefix" "$default_prefix"
show_item suffix "$suffix" "$default_suffix"

show_item hook_idx "$hook_idx" "$default_hook_idx"

# The rest depends on a tmux session
[[ -z "$TMUX" ]] && exit 0

echo
echo "===   temp variables stored in tmux by scripts/packet_loss.sh   ==="

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
