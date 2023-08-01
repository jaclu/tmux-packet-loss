#!/bin/sh
# Always sourced file - Fake bangpath to help editors
# shellcheck disable=SC2034
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.2.3 2022-09-15
#
#  Common stuff
#

#
#  If $log_file is empty or undefined, no logging will occur.
#
log_it() {
    if [ -z "$log_file" ]; then
        return
    fi
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$@" >>"$log_file"
}

set_tmux_option() {
    sto_option="$1"
    sto_value="$2"
    [ -z "$sto_option" ] && error_msg "set_tmux_option() param 1 empty!"
    $TMUX_BIN set -g "$sto_option" "$sto_value"
    unset sto_option
    unset sto_value
}

get_tmux_option() {
    gto_option="$1"
    gto_default="$2"

    [ -z "$gto_option" ] && error_msg "get_tmux_option() param 1 empty!"
    gto_value="$($TMUX_BIN show-option -gqv "$gto_option")"
    if [ -z "$gto_value" ]; then
        echo "$gto_default"
    else
        echo "$gto_value"
    fi
    unset gto_option
    unset gto_default
    unset gto_value
}

#
#  Display $1 as an error message in log and as a tmux display-message
#  If no $2 or set to 0, process is not exited
#
error_msg() {
    msg="ERROR: $1"
    exit_code="${2:-0}"

    log_it "$msg"
    $TMUX_BIN display-message "$plugin_name $msg"
    [ "$exit_code" -ne 0 ] && exit "$exit_code"
}

#
#  Aargh in shell boolean true is 0, but to make the boolean parameters
#  more relatable for users 1 is yes and 0 is no, so we need to switch
#  them here in order for assignment to follow boolean logic in caller
#
bool_param() {
    case "$1" in

    "0") return 1 ;;

    "1") return 0 ;;

    "yes" | "Yes" | "YES" | "true" | "True" | "TRUE")
        #  Be a nice guy and accept some common positives
        log_it "Converted incorrect positive [$1] to 1"
        return 0
        ;;

    "no" | "No" | "NO" | "false" | "False" | "FALSE")
        #  Be a nice guy and accept some common negatives
        log_it "Converted incorrect negative [$1] to 0"
        return 1
        ;;

    *)
        log_it "Invalid parameter bool_param($1)"
        error_msg "bool_param($1) - should be 0 or 1" 1
        ;;

    esac
    return 1
}

get_settings() {
    ping_host=$(get_tmux_option "@packet-loss-ping_host" "$default_host")
    ping_count=$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")
    history_size=$(get_tmux_option "@packet-loss-history_size" "$default_history_size")

    is_weighted_avg="$(get_tmux_option "@packet-loss-weighted_average" "$is_weighted_avg")" # new config
    display_trend="$(get_tmux_option "@packet-loss-display_trend" "$display_trend")"        # new config

    lvl_disp="$(get_tmux_option "@packet-loss-level_disp" "$lvl_disp")"    # new config
    lvl_alert="$(get_tmux_option "@packet-loss-level_alert" "$lvl_alert")" # new config
    lvl_crit="$(get_tmux_option "@packet-loss-level_crit" "$lvl_crit")"    # new config

    hist_avg_display="$(get_tmux_option "@packet-loss-hist_avg_display" "$hist_avg_display")" # new config
    hist_stat_mins=$(get_tmux_option "@packet-loss-hist_avg_minutes" "$hist_stat_mins")       # new config
    hist_separator=$(get_tmux_option "@packet-loss-hist_separator" "$hist_separator")         # new config

    color_alert="$(get_tmux_option "@packet-loss-color_alert" "$color_alert")" # new config
    color_crit="$(get_tmux_option "@packet-loss-color_crit" "$color_crit")"    # new config
    color_bg="$(get_tmux_option "@packet-loss-color_bg" "$color_bg")"          # new config

    loss_prefix="$(get_tmux_option "@packet-loss-prefix" "$loss_prefix")" # new config
    loss_suffix="$(get_tmux_option "@packet-loss-suffix" "$loss_suffix")" # new config

    hook_idx=$(get_tmux_option "@packet-loss-hook_idx" "$hook_idx") # new config
}

#
#  Shorthand, to avoid manually typing package name on multiple
#  locations, easily getting out of sync.
#
plugin_name="tmux-packet-loss"

#
#  log_it is used to display status to $log_file if it is defined.
#  Good for testing and monitoring actions. If $log_file is unset
#  no output will happen. This should be the case for normal operations.
#  So unless you want logging, comment the next line out.
#
# log_file="/tmp/$plugin_name.log"

#
#  I use an env var TMUX_BIN to point at the current tmux, defined in my
#  tmux.conf, in order to pick the version matching the server running.
#  This is needed when checking backwards compatability with various versions.
#  If not found, it is set to whatever is in path, so should have no negative
#  impact. In all calls to tmux I use $TMUX_BIN instead in the rest of this
#  plugin.
#
[ -z "$TMUX_BIN" ] && TMUX_BIN="tmux"

#
#  Sanity check that DB structure is current, if not it will be replaced
#
db_version=10

default_host="8.8.4.4" #  Default host to ping
default_ping_count=6   #  how often to report packet loss statistics
default_history_size=6 #  how many ping results to keep in the primary table

default_weighted_average=1 #  Use weighted average over averaging all data points
default_display_trend=1    #  display ^/v prefix if value is increasing/decreasing
default_lvl_display=1      #  display loss if this or higher
default_lvl_alert=17       #  this or higher triggers alert color
default_lvl_crit=40        #  this or higher triggers critical color

default_hist_avg_display=0    #  Display long term average
default_hist_avg_minutes=30   #  Minutes to keep historical average
default_hist_avg_separator=\~ #  Separaor between current and hist data

default_color_alert="colour226" # bright yellow
default_color_crit="colour196"  # bright red
default_color_bg="black"        #  only used when displaying alert/crit
default_prefix=" pkt loss: "
default_suffix=" "

default_session_closed_hook=41 #  array idx for session-closed hook

#
#  These files are assumed to be in the directory scripts, so depending
#  on location for the script using this, use the correct location prefix!
#  Since this is sourced, the prefix can not be determined here.
#
monitor_process_scr="packet_loss_monitor.sh"
no_sessions_shutdown_scr="shutdown_if_no_sessions.sh"

#
#  These files are assumed to be in the directory data, so depending
#  on location for the script using this, use the correct location prefix!
#  Since this is sourced, the prefix can not be determined here.
#
sqlite_db="packet_loss.sqlite"
monitor_pidfile="monitor.pid"
