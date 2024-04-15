#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Common stuff
#

get_tmux_socket() {
    #  shellcheck disable=SC2154
    if [[ -n "$TMUX" ]]; then
        echo "$TMUX" | sed 's#/# #g' | cut -d, -f 1 | awk 'NF>1{print $NF}'
    else
        echo "standalone"
    fi
}

#
#  If $log_file is empty or undefined, no logging will occur.
#
log_it() {
    local socket

    if [[ -z "$log_file" ]]; then
        return
    fi
    socket=" $(get_tmux_socket)"
    # only show socket name if not default
    [[ "$socket" = " default" ]] && socket=""
    printf "%s%s $$ %s%*s%s\n" "$(date '+%H:%M:%S')" "$socket" "$log_prefix" "$log_indent" "" "$@" >>"$log_file"
}

#
#  Display $1 as an error message in log and as a tmux display-message
#  If no $2 or set to 0, process is not exited
#
error_msg() {
    local msg="ERROR: $1"
    local exit_code="${2:-1}"

    log_it
    log_it "$msg"
    log_it
    if [[ -t 0 ]]; then
        echo "$msg" # was run from the cmd line
    else
        $TMUX_BIN display-message -d 0 "$plugin_name $msg"
    fi
    [[ "$exit_code" -ne 0 ]] && exit "$exit_code"

}

#
#  Aargh in shell boolean true is 0, but to make the boolean parameters
#  more relatable for users 1 is yes and 0 is no, so we need to switch
#  them here in order for assignment to follow boolean logic in caller
#

bool_printable() {
    bool_param "$1" && echo "true" || echo "false"
}

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

set_tmux_option() {
    local sto_option="$1"
    local sto_value="$2"

    [[ -z "$sto_option" ]] && error_msg "set_tmux_option() param 1 empty!"

    [[ "$TMUX" = "" ]] && return # this is run standalone

    $TMUX_BIN set -g "$sto_option" "$sto_value"
}

get_tmux_option() {
    local gto_option="$1"
    local gto_default="$2"
    local gto_value

    # log_it "get_tmux_option($gto_option,$gto_default)"
    [[ -z "$gto_option" ]] && error_msg "get_tmux_option() param 1 empty!"
    [[ "$TMUX" = "" ]] && {
        # this is run standalone, just report the defaults
        echo "$gto_default"
        return
    }

    gto_value="$($TMUX_BIN show-option -gqv "$gto_option")"
    if [[ -z "$gto_value" ]]; then
        # log_it "get opt def : $gto_option = $gto_default"
        echo "$gto_default"
    else
        # log_it "get opt     : $gto_option = $gto_value"
        echo "$gto_value"
    fi
}

get_settings() {
    ping_host="$(get_tmux_option "@packet-loss-ping_host" "$default_ping_host")"
    ping_count="$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")"
    history_size="$(get_tmux_option "@packet-loss-history_size" "$default_history_size")"

    weighted_average="$(get_tmux_option "@packet-loss-weighted_average" "$default_weighted_average")"
    display_trend="$(get_tmux_option "@packet-loss-display_trend" "$default_display_trend")"

    level_disp="$(get_tmux_option "@packet-loss-level_disp" "$default_level_disp")"
    level_alert="$(get_tmux_option "@packet-loss-level_alert" "$default_level_alert")"
    level_crit="$(get_tmux_option "@packet-loss-level_crit" "$default_level_crit")"

    hist_avg_display="$(get_tmux_option "@packet-loss-hist_avg_display" "$default_hist_avg_display")"
    hist_avg_minutes="$(get_tmux_option "@packet-loss-hist_avg_minutes" "$default_hist_avg_minutes")"
    hist_separator="$(get_tmux_option "@packet-loss-hist_separator" "$default_hist_separator")"

    color_alert="$(get_tmux_option "@packet-loss-color_alert" "$default_color_alert")"
    color_crit="$(get_tmux_option "@packet-loss-color_crit" "$default_color_crit")"
    color_bg="$(get_tmux_option "@packet-loss-color_bg" "$default_color_bg")"

    prefix="$(get_tmux_option "@packet-loss-prefix" "$default_prefix")"
    suffix="$(get_tmux_option "@packet-loss-suffix" "$default_suffix")"

    hook_idx="$(get_tmux_option "@packet-loss-hook_idx" "$default_hook_idx")"
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

#  common folders
d_data="$D_TPL_BASE_PATH/data"

[[ -d "$d_data" ]] || {
    log_it "mkdir $d_data"
    mkdir -p "$d_data" # ensure it exists
}

# shellcheck source=pidfile_handler.sh
. "$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh

#
#  log_it is used to display status to $log_file if it is defined.
#  Good for testing and monitoring actions. If $log_file is unset
#  no output will happen. This should be the case for normal operations.
#  So unless you want logging, comment the next line out.
#
log_file="/tmp/$plugin_name.log"

log_prefix="???"
log_indent=1
#
#  Should have been set in the calling script, must be done after
#  log_file is (potentially) defined
#
[[ -z "$D_TPL_BASE_PATH" ]] && error_msg "D_TPL_BASE_PATH is not defined!"

#  shellcheck disable=SC2034
scr_controler="$D_TPL_BASE_PATH/scripts/ctrl_monitor.sh"
scr_monitor="$D_TPL_BASE_PATH/scripts/monitor_packet_loss.sh"

#
#  These files are assumed to be in the directory data, so depending
#  on location for the script using this, use the correct location prefix!
#  Since this is sourced, the prefix can not be determined here.
#
#  shellcheck disable=SC2034
sqlite_db="$d_data/packet_loss.sqlite"
#  shellcheck disable=SC2034
db_restart_log="$d_data/db_restarted.log"
#  shellcheck disable=SC2034
monitor_pidfile="$d_data/monitor.pid"

#  check one of the path items to verify D_TPL_BASE_PATH
[[ -f "$scr_monitor" ]] || {
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
[[ -z "$TMUX_BIN" ]] && TMUX_BIN="tmux" # -L $(get_socket)"
# ensure socket is included, in case TMUX_BIN didn't set it
# [[ -n "${TMUX_BIN##*-L*}" ]] && TMUX_BIN="$TMUX_BIN -L $(get_tmux_socket)"

#  shellcheck disable=SC2034
cache_db_polls=true

#
#  Sanity check that DB structure is current, if not it will be replaced
#
#  shellcheck disable=SC2034
db_version=10

default_ping_host="8.8.4.4" #  Default host to ping
default_ping_count=6        #  how often to report packet loss statistics
default_history_size=6      #  how many ping results to keep in the primary table

default_weighted_average=1 #  Use weighted average over averaging all data points
default_display_trend=0    #  display ^/v prefix if value is increasing/decreasing

default_level_disp=1   #  display loss if this or higher
default_level_alert=18 #  this or higher triggers alert color
default_level_crit=40  #  this or higher triggers critical color

default_hist_avg_display=0  #  Display long term average
default_hist_avg_minutes=30 #  Minutes to keep historical average
default_hist_separator='~'  #  Separaor between current and hist data

default_color_alert="colour226" # bright yellow
default_color_crit="colour196"  # bright red
default_color_bg='black'        #  only used when displaying alert/crit

default_prefix=' pkt loss: '
default_suffix=' '

default_hook_idx=41 #  array idx for session-closed hook

get_settings
