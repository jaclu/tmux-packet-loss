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
        # log_it "get opt def : $gto_option = $gto_default"
        echo "$gto_default"
    else
        # log_it "get opt     : $gto_option = $gto_value"
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
    exit_code="${2:-1}"

    if [ -t 0 ]; then
        echo "$plugin_name $msg" # was run from the cmd line
    else
        log_it
        log_it "$msg"
        log_it
        $TMUX_BIN display-message "$plugin_name $msg"
    fi
    [ "$exit_code" -ne 0 ] && exit "$exit_code"

    unset msg
    unset exit_code
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
    ping_host="$(get_tmux_option "@packet-loss-ping_host" "$default_host")"
    ping_count="$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")"
    history_size="$(get_tmux_option "@packet-loss-history_size" "$default_history_size")"

    is_weighted_avg="$(get_tmux_option "@packet-loss-weighted_average" "$default_weighted_average")"
    display_trend="$(get_tmux_option "@packet-loss-display_trend" "$default_display_trend")"

    lvl_disp="$(get_tmux_option "@packet-loss-level_disp" "$default_lvl_display")"
    lvl_alert="$(get_tmux_option "@packet-loss-level_alert" "$default_lvl_alert")"
    lvl_crit="$(get_tmux_option "@packet-loss-level_crit" "$default_lvl_crit")"

    hist_avg_display="$(get_tmux_option "@packet-loss-hist_avg_display" "$default_hist_avg_display")"
    hist_stat_mins="$(get_tmux_option "@packet-loss-hist_avg_minutes" "$default_hist_avg_minutes")"
    hist_separator="$(get_tmux_option "@packet-loss-hist_separator" "$default_hist_avg_separator")"

    color_alert="$(get_tmux_option "@packet-loss-color_alert" "$default_color_alert")"
    color_crit="$(get_tmux_option "@packet-loss-color_crit" "$default_color_crit")"
    color_bg="$(get_tmux_option "@packet-loss-color_bg" "$default_color_bg")"

    loss_prefix="$(get_tmux_option "@packet-loss-prefix" "$default_prefix")"
    loss_suffix="$(get_tmux_option "@packet-loss-suffix" "$default_suffix")"

    hook_idx="$(get_tmux_option "@packet-loss-hook_idx" "$default_session_closed_hook")"
}

show_settings() {
    [ -z "$log_file" ] && return # if no logging, no need to continue

    log_it "=====   All variables   ====="
    log_it "ping_host=[$ping_host]"
    log_it "ping_count=[$ping_count]"
    log_it "history_size=[$history_size]"

    if bool_param "$is_weighted_avg"; then
        log_it "is_weighted_avg=true"
    else
        log_it "is_weighted_avg=false"
    fi
    if bool_param "$display_trend"; then
        log_it "display_trend=true"
    else
        log_it "display_trend=false"
    fi

    log_it "lvl_disp [$lvl_disp]"
    log_it "lvl_alert [$lvl_alert]"
    log_it "lvl_crit [$lvl_crit]"

    if bool_param "$hist_avg_display"; then
        log_it "hist_avg_display=true"
    else
        log_it "hist_avg_display=false"
    fi
    log_it "hist_stat_mins=[$hist_stat_mins]"
    log_it "hist_separator [$hist_separator]"

    log_it "color_alert [$color_alert]"
    log_it "color_crit [$color_crit]"
    log_it "color_bg [$color_bg]"

    log_it "loss_prefix [$loss_prefix]"
    log_it "loss_suffix [$loss_suffix]"

    log_it "hook_idx [$hook_idx]"
    log_it
}

#===============================================================
#
#   Main
#
#===============================================================

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
#  Should have been set in the calling script, must be done after
#  log_file is (potentially) defined
#
[ -z "$D_TPL_BASE_PATH" ] && error_msg "D_TPL_BASE_PATH is not defined!"

#
#  These files are assumed to be in the directory scripts, so depending
#  on location for the script using this, use the correct location prefix!
#  Since this is sourced, the prefix can not be determined here.
#
monitor_process_scr="$D_TPL_BASE_PATH/scripts/packet_loss_monitor.sh"
no_sessions_shutdown_scr="$D_TPL_BASE_PATH/scripts/shutdown_if_no_sessions.sh"

#
#  These files are assumed to be in the directory data, so depending
#  on location for the script using this, use the correct location prefix!
#  Since this is sourced, the prefix can not be determined here.
#
sqlite_db="$D_TPL_BASE_PATH/data/packet_loss.sqlite"
db_restart_log="$D_TPL_BASE_PATH/data/db_restarted.log"
monitor_pidfile="$D_TPL_BASE_PATH/data/monitor.pid"

#  check one of the path items to verify D_TPL_BASE_PATH
[ -f "$monitor_process_scr" ] || {
    error_msg "D_TPL_BASE_PATH seems invalid: [$D_TPL_BASE_PATH]"
}

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

default_hist_avg_display=0     #  Display long term average
default_hist_avg_minutes=30    #  Minutes to keep historical average
default_hist_avg_separator='~' #  Separaor between current and hist data

default_color_alert="colour226" # bright yellow
default_color_crit="colour196"  # bright red
default_color_bg='black'        #  only used when displaying alert/crit
default_prefix=' pkt loss: '
default_suffix=' '

default_session_closed_hook=41 #  array idx for session-closed hook

get_settings
