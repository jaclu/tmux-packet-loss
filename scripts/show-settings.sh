#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

show_item() {
    _si_label="$1"
    _si_value="$2"
    _si_default="$3"
    case "$_si_label" in
        @packet-loss-prefix | @packet-loss-suffix)
            [ -n "$_si_value" ] && _si_value="[$_si_value]"
            [ -n "$_si_default" ] && _si_default="[$_si_default]"
            ;;
        *) ;;
    esac
    if [ "$_si_label" = "headers" ]; then
        echo "      Default   user setting  config variable"
        echo "      -------   ------------  ---------------"

    else
        if [ "$_si_value" = "$_si_default" ]; then
            msg="$(printf "%13s                 %s" \
                "$_si_value" "$_si_label")"
        else
            msg="$(printf "%13s  %13s  %s" \
                "$_si_default" "$_si_value" "$_si_label")"
        fi
        echo "$msg"
    fi
}

get_tmux_socket_name() {
    #
    #  returns name of tmux socket being used
    #
    if [ -n "$TMUX" ]; then
        echo "$TMUX" | sed 's#/# #g' | cut -d, -f 1 | awk 'NF>1{print $NF}'
    else
        echo "standalone"
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

#
#  Ensures terminals will use their own tmux config, and not the
#  one that might be cached in this instance of the plugin
#
use_param_cache=false

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="shw"

# shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

# shellcheck source=scripts/pidfile-handler.sh
. "$f_pidfile_handler"

session="$(get_tmux_socket_name)"

echo "=====   Config for  session: $session   ====="
echo

if [ "$session" != "standalone" ]; then
    this_tmux_pid="$(get_tmux_pid)"
    folder_tmux_pid="$(pidfile_show_process "$pidfile_tmux")"

    if [ -n "$folder_tmux_pid" ]; then
        [ "$this_tmux_pid" = "$folder_tmux_pid" ] || {
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
    echo "*** This is not inside any tmux session - only defaults will be displayed!"
    echo
fi

show_item "headers"
show_item "@packet-loss-ping_host" "$cfg_ping_host" "$default_ping_host"
show_item @packet-loss-ping_count "$cfg_ping_count" "$default_ping_count"
show_item "@packet-loss-history_size" "$cfg_history_size" "$default_history_size"
echo
show_item @packet-loss-reactive "$cfg_reactive" "$default_reactive"
show_item @packet-loss-display_trend "$cfg_display_trend" "$default_display_trend"
show_item @packet-loss-hist_avg_display "$cfg_hist_avg_display" "$default_hist_avg_display"
show_item @packet-loss-run_disconnected "$cfg_run_disconnected" "$default_run_disconnected"
echo
show_item @packet-loss-level_disp "$cfg_level_disp" "$default_level_disp"
show_item @packet-loss-level_alert "$cfg_level_alert" "$default_level_alert"
show_item @packet-loss-level_crit "$cfg_level_crit" "$default_level_crit"
echo
show_item @packet-loss-hist_avg_minutes "$cfg_hist_avg_minutes" "$default_hist_avg_minutes"
show_item @packet-loss-hist_separator "$cfg_hist_separator" "$default_hist_separator"
echo
show_item @packet-loss-color_alert "$cfg_color_alert" "$default_color_alert"
show_item @packet-loss-color_crit "$cfg_color_crit" "$default_color_crit"
show_item @packet-loss-color_bg "$cfg_color_bg" "$default_color_bg"
echo
show_item @packet-loss-prefix "$cfg_prefix" "$default_prefix"
show_item @packet-loss-suffix "$cfg_suffix" "$default_suffix"
[ -n "$cfg_log_file" ] && {
    echo
    echo "log_file in use: $cfg_log_file"
}

[ -n "$TMUX" ] && [ -f "$pidfile_monitor" ] && {
    echo
    echo "Monitor process running: $folder_tmux_pid"
}
