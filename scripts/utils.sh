#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.0.5 2022-03-24
#
#  Common stuff
#

#
#  log_it is used to display status to $log_file if it is defined.
#  Good for testing and monitoring actions. If $log_file is unset
#  no output will happen. This should be the case for normal operations.
#  So unless you want logging, comment the next line out.
#
# log_file="/tmp/tmux-packet-loss.log"


db_version=2         # Sanity check that DB structure is current
hook_array_idx=1819  # random hopefully unique id to avoid colliding with other
                     # hook handling utilities


default_host="8.8.4.4"   #  Default host to ping
default_ping_count=6     #  how often to report packet loss statistics
default_hist_size=10     # how many rounds of pings to keep in db for average calculations
default_lvl_display=0.1  # float, display loss if this or higher
default_lvl_alert=2.0    # float, this or higher triggers alert color
default_lvl_crit=8.0     # float, this or higher triggers critical color
default_color_alert="yellow"
default_color_crit="red"
default_color_bg="black"  # only used for displaying alert/crit
default_prefix=" pkt loss: "
default_suffix=" "


#
#  These files are assumed to be in scripts, so depending on location
#  for the script using this, use the correct location prefix!
#  Since this is sourced the prefix can not be determined here.
#
sqlite_db="packet_loss.sqlite"
monitor_process_scr="packet_loss_monitor.sh"
monitor_pidfile="monitor.pid"
no_sessions_shutdown_scr="shutdown_if_no_sessions.sh"

plugin_name="tmux-packet-loss"


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
