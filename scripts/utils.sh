#!/bin/sh
# shellcheck disable=SC2034
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.2.0 2022-03-29
#
#  Common stuff
#

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
log_file="/tmp/$plugin_name.log"


db_version=2         # Sanity check that DB structure is current
hook_array_idx=1819  # random hopefully unique id to avoid colliding with other
                     # hook handling utilities


default_host="8.8.4.4"     #  Default host to ping
default_ping_count=6       #  how often to report packet loss statistics
default_hist_size=6        #  how many rounds of pings to keep in db for average calculations
default_weighted_average=1 #  Use weighted average over averaging all data points
default_lvl_display=0.1    #  float, display loss if this or higher
default_lvl_alert=2.0      #  float, this or higher triggers alert color
default_lvl_crit=8.0       #  float, this or higher triggers critical color
default_color_alert="yellow"
default_color_crit="red"
default_color_bg="black"   # only used when displaying alert/crit
default_prefix=" pkt loss: "
default_suffix=" "


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


#
#  If $log_file is empty or undefined, no logging will occur.
#
log_it() {
    if [ -z "$log_file" ]; then
        return
    fi
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$@" >> "$log_file"
}


get_tmux_option() {
    gtm_option=$1
    gtm_default=$2
    gtm_value="$(tmux show-option -gqv "$gtm_option")"
    if [ -z "$gtm_value" ]; then
        echo "$gtm_default"
    else
        echo "$gtm_value"
    fi
    unset gtm_option
    unset gtm_default
    unset gtm_value
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

        "yes" | "Yes" | "YES" | "true" | "True" | "TRUE" )
            #  Be a nice guy and accept some common positives
            log_it "Converted incorrect positive [$1] to 1"
            return 0
            ;;

        "no" | "No" | "NO" | "false" | "False" | "FALSE" )
            #  Be a nice guy and accept some common negatives
            log_it "Converted incorrect negative [$1] to 0"
            return 1
            ;;

        *)
            log_it "Invalid parameter bool_param($1)"
            tmux display "ERROR: bool_param($1) - should be 0 or 1"

    esac
    return 1
}
