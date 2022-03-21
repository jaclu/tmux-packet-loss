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


#
#  If log_file is empty or undefined, no logging will occur,
#  so comment it out for normal usage.
#
log_file="/tmp/tmux-packet-loss.log"  # Trigger LF to separate runs of this script



db_version=11  # Sanity check that DB structure is current
hist_size=100  # how many rounds of pings to keep in db for average calculations


#
#  how often to report packet loss statistics
#
default_ping_count=10

#
#  Default host to ping
#
default_host="8.8.4.4"


default_lvl_display=0.2 # float, display loss if this or higher
default_lvl_alert=1.0  # float, this or higher triggers alert
default_lvl_crit=5.0   # float, this or higher triggers critical
default_color_alert="yellow"
default_color_crit="red"
default_color_bg="black"  # only used for displaying alert/crit
default_prefix="| pkt loss: "
default_suffix=" | "

sqlite_db="packet_loss.sqlite" # assumed to be in scripts
monitor_pidfile="monitor.pid"  # assumed to be in scripts



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
