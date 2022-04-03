#!/bin/sh
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.2 2022-04-03
#


# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"
pidfile="$(dirname -- "$CURRENT_DIR")/data/$monitor_pidfile"

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
echo "$$" > "$pidfile"


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
timeout_help="$(ping -h 2> /dev/stdout| grep timeout)"

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
while : ; do
    output="$($ping_cmd  | grep loss)"
    if [ -n "$output" ]; then
        #
        #  We cant rely on the absolute position of the %loss, since sometimes it is prepended with stuff like:
        #  "+1 duplicates,"
        #  To handle this we search for "packet loss" and use the word just before it.
        #
        percent_loss="$(echo "$output" | sed 's/packet loss/\|/' | cut -d\| -f 1 | awk 'NF>1{print $NF}' | sed s/%// )"
        if [ -z "$percent_loss" ]; then
            error_msg "Failed to parse ping output!"
            percent_loss="101"  #  indicate this error by giving high value
        fi
    else
        #
        #  No output, usually no connection to the host
        #
        percent_loss="102"  #  indicate this error by giving high value
        #
        #  Some pings instantly aborts on no connection, this will keep
        #  the poll rate kind of normal and avoid rapidly filling the DB with bad data
        #
        log_it "No ping output, will sleep $ping_count seconds"
        sleep "$ping_count"
    fi
    sqlite3 "$db" "INSERT INTO packet_loss (loss) values ($percent_loss)"
    log_it "stored in DB [$percent_loss]"
done
