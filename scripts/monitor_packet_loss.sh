#!/bin/sh
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever unless it is given the option stop, so waiting for
#   it to complete might not be handy when called from other scripts.
#   This is how I use it:
#     nohup "$monitor_process_scr" >/dev/null 2>&1 &
#

check_pidfile_task() {
    #
    #  Check if pidfile is relevant
    #
    #  Variables defined:
    #   pid - what pid was listed in monitor_pidfile
    #

    # log_it "check_pidfile_task()"
    _result=1 # false
    [ -z "$monitor_pidfile" ] && error_msg "monitor_pidfile is not defined!"
    if [ -e "$monitor_pidfile" ]; then
        pid="$(cat "$monitor_pidfile")"
        ps -p "$pid" >/dev/null && _result=0 # true
    fi
    return "$_result"
}

stray_instances() {

    #
    #  Find any other stray monitoring processes
    #
    # log_it "stray_instances()"
    proc_to_check="/bin/sh $monitor_process_scr"
    if [ -n "$(command -v pgrep)" ]; then
        pgrep -f "$proc_to_check" | grep -v "$my_pid"
    else
        #
        #  Figure our what ps is available, in order to determine
        #  which param is the pid
        #
        if readlink "$(command -v ps)" | grep -q busybox; then
            pid_param=1
        else
            pid_param=2
        fi

        # shellcheck disable=SC2009
        ps axu | grep "$proc_to_check" | grep -v grep | awk -v p="$pid_param" '{ print $p }' | grep -v "$my_pid"
    fi
}

kill_any_strays() {
    # log_it "kill_any_strays()"
    strays="$(stray_instances)"
    [ -n "$strays" ] && {
        # error_msg "Found strays: $strays"
        echo "$strays" | xargs kill
        remaing_strays="$(stray_instances)"
        [ -n "$remaing_strays" ] && {
            error_msg "Remaining strays: [$remaing_strays]"
        }
    }
}

define_ping_cmd() {
    #
    #  Figuring out the nature of the available ping cmd
    #  Variables provided:
    #    ping_cmd - options adjusted for the local environment
    #

    #
    #  Selecting the right timeout option
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

    ping_cmd="$ping_cmd -c $ping_count $ping_host"
    log_it "$monitor_process_scr will use ping cmd [$ping_cmd]"

    unset timeout_help
    unset timeout_parameter
}

#===============================================================
#
#   Main
#
#===============================================================

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

this_app="$(basename "$0")"
my_pid="$$"

mkdir -p "$D_TPL_BASE_PATH/data" # ensure folder exists

#
#  Since loss is <=100, indicate errors with results over 100
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

check_pidfile_task && {
    if [ "$1" = "stop" ]; then
        log_it "Will kill [$my_pid] $this_app"
        kill "$pid"
        check_pidfile_task && error_mg "Failed to kill [$my_pid] $this_app"
    else
        error_msg "This is already running [$pid]"
    fi
}
rm -f "$monitor_pidfile"
kill_any_strays
[ "$1" = "stop" ] && exit 0

log_it "[$my_pid] $this_app - starting"
echo "$my_pid" >"$monitor_pidfile"

"$D_TPL_BASE_PATH"/scripts/prepare_db.sh

define_ping_cmd

#
#  Main loop
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
            error_msg "Failed to parse ping output, unlikely to self correct!" 0
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
    sqlite3 "$sqlite_db" "INSERT INTO t_loss (loss) VALUES ($percent_loss)"

    #  Add one line in statistics each minute
    sql="SELECT COUNT(*) FROM t_stats WHERE time_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))"
    items_this_minute="$(sqlite3 "$sqlite_db" "$sql")"
    if [ "$items_this_minute" -eq 0 ]; then
        sqlite3 "$sqlite_db" 'INSERT INTO t_stats (loss) SELECT avg(loss) FROM t_1_min'
    fi

    #  A bit exessive in normal conditions
    log_it "stored in DB: $percent_loss"
done