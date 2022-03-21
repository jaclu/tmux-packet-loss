#!/usr/bin/env bash
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-menus
#
#   Version: 0.0.0a 2022-03-20
#
#  Common stuff
#




db_version=2   # Sanity check that DB structure is correct
hist_size=100  # how many rounds of pings to keep in db for average calculations

#
#  how often to report packet loss statistics
#
default_ping_count=5

#
#  Default host to ping
#
default_host="8.8.4.4"


default_lvl_alert=1
default_lvl_crit=5
default_color_alert="yellow"
default_color_crit="red"
default_color_bg="black"
default_prefix="pkt loss: "

sqlite_db="packet_loss.sqlite" # in scripts
monitor_pidfile="monitor.pid"  # in scripts

#
#  If log_file is empty or undefined, no logging will occur,
#  so comment it out for normal usage.
#
log_file="/tmp/tmux-packet-loss.log"  # Trigger LF to separate runs of this script


#
#  If $log_file is empty or undefined, no logging will occur.
#
log_it() {
    if [ -z "$log_file" ]; then
        return
    fi
    printf "%s\n" "$@" >> "$log_file"
}


get_tmux_option() {
    gtm_option=$1
    gtm_default=$2
    gtm_value=$(tmux show-option -gqv "$gtm_option")
    if [ -z "$gtm_value" ]; then
        echo "$gtm_default"
    else
        echo "$gtm_value"
    fi
    unset gtm_option
    unset gtm_default
    unset gtm_value
}
