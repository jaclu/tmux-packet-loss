#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.0.5 2022-03-23
#

CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$CURRENT_DIR/utils.sh"

db="$CURRENT_DIR/$sqlite_db"
pidfile="$CURRENT_DIR/$monitor_pidfile"


#
#  Ensure only one instance is running.
#
if [ -e "$pidfile" ]; then
    msg="tmux-packet-loss ERROR: packet_loss_monitor.sh seems to already be running, aborting!"
    log_it "$msg"
    tmux display "$msg"
    exit 1
fi


#
#  Save pid for easier kill from packet-loss.tmux
#
log_it "Saving new pid [$$] into pidfile"
echo "$$" > "$pidfile"


#
#  Getting parameters from DB
#
ping_count="$(sqlite3 "$db" "SELECT ping_count FROM params")"
host="$(sqlite3 "$db" "SELECT host FROM params")"


#
#  Figuring out the nature of the available ping cmd
#

# Argh, even the position for % packet loss is not constant...
packet_loss_param_no="7"

# triggering an error printing valid parameters...
timeout_help="$(ping -h 2> /dev/stdout| grep timeout)"

if [ "${timeout_help#*-t}" != "$timeout_help" ]; then
    timeout_flag="t"
elif [ "${timeout_help#*-W}" != "$timeout_help" ]; then
    timeout_flag="W"
    packet_loss_param_no="6"
else
    timeout_flag=""
fi

if [ -n "$timeout_flag" ]; then
    ping_cmd="ping -$timeout_flag $ping_count"
else
    ping_cmd="ping"
fi

ping_cmd="$ping_cmd -c $ping_count $host"


#
#  Main
#
while : ; do
    output="$($ping_cmd  | grep loss)"
    if [ -n "$output" ]; then
        this_time_percent_loss=$(echo "$output" | awk -v percent_loss_param="$packet_loss_param_no" '{print $percent_loss_param}' | sed s/%// )
        if [ -z "$this_time_percent_loss" ]; then
            log_it "ERROR: Failed to parse ping output!"
            this_time_percent_loss="100"
        fi
    else
        #
        #  no output, assume no connection since not an error in this software,
        #  just log a notice
        #
        this_time_percent_loss="100"
        #
        #  Some pings instantly aborts on no connection, this will keep
        #  the poll rate kind of normal and avoid rapidly filling the DB with bad data
        #
        log_it "No ping output, will sleep $ping_count seconds"
        sleep "$ping_count"
    fi
    sqlite3 "$db" "INSERT INTO packet_loss (loss) values ($this_time_percent_loss);"
    log_it "stored [$this_time_percent_loss] in db"
done
