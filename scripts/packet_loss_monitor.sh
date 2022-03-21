#!/bin/sh
# keep
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

. "$CURRENT_DIR/utils.sh"

db="$CURRENT_DIR/$sqlite_db"

echo "$$" > "$CURRENT_DIR/$monitor_pidfile"

ping_count="$(sqlite3 "$db" "SELECT ping_count FROM params")"
host="$(sqlite3 "$db" "SELECT host FROM params")"



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


while : ; do
    output="$($ping_cmd  | grep loss)"
    this_time_percent_loss=$(echo "$output" | awk -v a="$packet_loss_param_no" '{print $a}' | sed s/%// )
    sqlite3 "$db" "INSERT INTO packet_loss (loss) values ($this_time_percent_loss);"
    log_it "stored [$this_time_percent_loss] in db"
done
