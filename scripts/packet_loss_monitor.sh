#!/bin/sh

CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$CURRENT_DIR/utils.sh"

db="$CURRENT_DIR/$sqlite_db"


#
#  Getting params from DB
#
ping_count="$(sqlite3 "$db" "SELECT ping_count FROM params")"
host="$(sqlite3 "$db" "SELECT host FROM params")"


#
#  Save pid for easier kill from packet-loss.tmux
#
echo "$$" > "$CURRENT_DIR/$monitor_pidfile"



#
#  Figuring out the nature of the available ping cmd
#

#
# Argh, even the position for % packet loss is not constant...
#
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
    echo "will ping"
    output="$($ping_cmd  | grep loss)"
    echo "ping [$output] done!"
    if [ -n "$output" ]; then
        this_time_percent_loss=$(echo "$output" | awk -v a="$packet_loss_param_no" '{print $a}' | sed s/%// )
        if [ -z "$this_time_percent_loss" ]; then
            log_it "ERROR: Failed to parse ping output!"
            this_time_percent_loss="100"
        fi
    else
        this_time_percent_loss="100"
        #
        #  no output assume no connection, since not an error in this software
        #  just log a notice
        #
        log_it "No ping outpput, will sleep $ping_count seconds"
        #
        #  Some pings instantly aborts on no connection, this will keep
        #  the poll rate normal and rapidly fill the DB with bad data
        #
        sleep "$ping_count"
    fi
    sqlite3 "$db" "INSERT INTO packet_loss (loss) values ($this_time_percent_loss);"
    log_it "stored [$this_time_percent_loss] in db"
done
