#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever unless it is given the option stop, so waiting for
#   it to complete might not be handy when called from other scripts.
#   This is how I use it:
#     nohup "$scr_monitor" >/dev/null 2>&1 &
#

define_ping_cmd() {
    #
    #  Figuring out the nature of the available ping cmd
    #  Variables provided:
    #    ping_cmd - options adjusted for the local environment
    #
    local timeout_help
    local timeout_parameter

    #
    #  Selecting the right timeout option
    #
    timeout_help="$(ping -h 2>/dev/stdout | grep timeout)"

    if [[ "${timeout_help#*-t}" != "$timeout_help" ]]; then
        timeout_parameter="t"
    elif [[ "${timeout_help#*-W}" != "$timeout_help" ]]; then
        timeout_parameter="W"
    else
        timeout_parameter=""
    fi

    if [[ -n "$timeout_parameter" ]]; then
        ping_cmd="ping -$timeout_parameter $ping_count"
    else
        #
        #  Without a timeout flag and no response, ping might end up taking
        #  2 * ping_count seconds to complete...
        #
        ping_cmd="ping"
    fi

    ping_cmd="$ping_cmd -c $ping_count $ping_host"
    log_it "ping cmd used: [$ping_cmd]"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")
log_prefix="mon"

#  shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

pidfile_acquire "$monitor_pidfile" || {
    error_msg "$monitor_pidfile - is owned by process [$pidfile_proc]"
}

#
#  Since loss is <=100, indicate errors with results over 100
#  Not crucial to remember exactly what it means,
#  enough to know is >100 means monitor error
#
#  Failed to find %loss in ping output, most likely temporary,
#  some pings just report:
#    ping: sendto: Host is unreachable
#  if network is unreachable
#
error_no_ping_output="101"

# ping_cmd | grep loss  gave empty result, unlikely to self correct
error_unable_to_detect_loss="201"

"$D_TPL_BASE_PATH"/scripts/db_prepare.sh

define_ping_cmd # we need the ping_cmd in kill_any_strays

#
#  Main loop
#
while :; do
    #
    #  Redirecting stderr is needed since on some platforms, like running
    #  Debian 10 on iSH, you get warning printouts, yet the ping still works:
    #
    #    WARNING: your kernel is veeery old. No problems.
    #    WARNING: setsockopt(IP_RETOPTS): Protocol not available
    #
    #  If the output gets garbled or no output, it is handled
    #  so in that sense such error msgs can be ignored.
    #
    output="$($ping_cmd 2>/dev/null | grep loss)"

    if [[ -n "$output" ]]; then
        #
        #  We cant rely on the absolute position of the %loss,
        #  since sometimes it is prepended with stuff like:
        #  "+1 duplicates,"
        #  To handle this we search for "packet loss" and use the word
        #  just before it.
        #  1 Only bother with the line containing the word loss
        #  2 replace "packet loss" with ~, since cut needs a single char
        #    delimiter
        #  3 remove any % chars, we want loss as a float
        #  4 only keep line up to not including ~ (packet loss)
        #  5 display last remaining word - packet loss as a float with
        #    no % sign!
        #
        percent_loss="$(echo "$output" | sed 's/packet loss/~/ ; s/%//' |
            cut -d~ -f 1 | awk 'NF>1{print $NF}')"
        if [[ -z "$percent_loss" ]]; then
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
        #  the poll rate kind of normal and avoid rapidly filling the DB
        #  with bad data. Worst case, this will delay monitoring a bit
        #  during an outage.
        #
        log_it "No ping output, will sleep $ping_count seconds"
        sleep "$ping_count"
    fi

    sqlite3 "$sqlite_db" "INSERT INTO t_loss (loss) VALUES ($percent_loss)"

    #  Add one line in statistics each minute
    sql="SELECT COUNT(*) FROM t_stats WHERE time_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))"
    items_this_minute="$(sqlite3 "$sqlite_db" "$sql")"
    if [[ "$items_this_minute" -eq 0 ]]; then
        sqlite3 "$sqlite_db" \
            'INSERT INTO t_stats (loss) SELECT avg(loss) FROM t_1_min'
    fi

    #  A bit exessive in normal conditions
    #[[ "$percent_loss" != "0.0" ]] && log_it "stored in DB: $percent_loss"
done
