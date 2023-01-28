#!/bin/sh
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 1.1.4 2022-04-06
#

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"

get_settings

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"
pidfile="$(dirname -- "$CURRENT_DIR")/data/$monitor_pidfile"

#
#  Since loss is treated as a float, indicate errors with results over 100
#  Not crucial to remember exactly what it means, enough to know is >100 means monitor error
#

#
#  Failed to find %loss in ping output, most likely temporary, some pings just report:
#    ping: sendto: Host is unreachable
#  if network is unreachable
#
error_no_ping_output="101"

# `ping_cmd | grep loss`  gave empty result, unlikely to self correct
error_unable_to_detect_loss="201"

#
#  Ensure only one instance is running.
#
if [ -e "$pidfile" ]; then
    error_msg "$monitor_process_scr seems to already be running, aborting!" 1
fi

#
#  Save pid for easier kill from packet-loss.tmux
#
log_it "Saving new pid [$$] into pidfile"
echo "$$" >"$pidfile"

#
#  Getting parameters from DB
#
ping_count="$(sqlite3 "$db" "SELECT ping_count FROM params")"
host="$(sqlite3 "$db" "SELECT host FROM params")"

#
#  Figuring out the nature of the available ping cmd
#

#
#  Detecting what ping command is present, in order to figure out the
#  right timeout param
#
timeout_help="$(ping -h 2>/dev/stdout | grep timeout)"

if [ "${timeout_help#*-t}" != "$timeout_help" ]; then
    timeout_parameter="t"
elif [ "${timeout_help#*-W}" != "$timeout_help" ]; then
    timeout_parameter="W"
else
    timeout_parameter=""
fi

if [ -n "$timeout_parameter" ]; then
    ping_cmd="ping -$timeout_parameter $ping_count"
else
    #
    #  Without a timeout flag and no response, ping might end up taking
    #  2 * ping_count seconds to complete...
    #
    ping_cmd="ping"
fi

ping_cmd="$ping_cmd -c $ping_count $host"

log_it "$monitor_process_scr will use ping cmd [$ping_cmd]"

#
#  Main
#
while :; do
    output="$($ping_cmd | grep loss)"
    if [ -n "$output" ]; then
        #
        #  We cant rely on the absolute position of the %loss, since sometimes it is prepended with stuff like:
        #  "+1 duplicates,"
        #  To handle this we search for "packet loss" and use the word just before it.
        #  1 Only bother with the line containing the word loss
        #  2 replace "packet loss" with ~, since cut needs a single char delimiter
        #  3 remove any % chars, we want loss as a float
        #  4 only keep line up to not including ~ (packet loss)
        #  5 display last remaining word - packet loss as a float with no % sign!
        #
        percent_loss="$(echo "$output" | sed 's/packet loss/~/ ; s/%//' | cut -d~ -f 1 | awk 'NF>1{print $NF}')"
        if [ -z "$percent_loss" ]; then
            error_msg "Failed to parse ping output, unlikely to self correct!"
            percent_loss="$error_unable_to_detect_loss"
        fi
    else
        #
        #  No output, usually no connection to the host
        #
        percent_loss="$error_no_ping_output"
        #
        #  Some pings instantly aborts on no connection, this will keep
        #  the poll rate kind of normal and avoid rapidly filling the DB with bad data,
        #  Worst case, this will delay monitoring a bit during an outage.
        #
        log_it "No ping output, will sleep $ping_count seconds"
        sleep "$ping_count"
    fi
    sqlite3 "$db" "INSERT INTO packet_loss (loss) values ($percent_loss)"

    #  Add one line in statistics each minute
    sql="SELECT COUNT(*) FROM statistics WHERE t_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))"
    items_this_minute="$(sqlite3 "$db" "$sql")"
    if [ "$items_this_minute" -eq 0 ]; then
        sqlite3 "$db" 'INSERT INTO statistics (loss) SELECT round(avg(loss),1) FROM log_1_min'
    fi

    log_it "stored in DB: $percent_loss"
done
