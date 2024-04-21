#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever.
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
        ping_cmd="ping -$timeout_parameter $cfg_ping_count"
    else
        #
        #  Without a timeout flag and no response, ping might end up taking
        #  2 * cfg_ping_count seconds to complete...
        #
        ping_cmd="ping"
    fi

    ping_cmd="$ping_cmd -c $cfg_ping_count $cfg_ping_host"
    log_it "ping cmd used: [$ping_cmd]"
}

calculate_loss_default() {
    #
    #  Default loss calculation
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
    #
    #  External variables:
    #    output - result of ping cmd
    #    percent_loss - the number in the summary preceeding "packet loss"
    #                   as a float, I.E. sans "%" suffix
    #
    percent_loss="$(echo "$output" | sed 's/packet loss/~/ ; s/%//' |
        cut -d~ -f 1 | awk 'NF>1{print $NF}')"

}

calculate_loss_ish_deb10() {
    #
    #  This is a weird one, gives all kinds of weird output
    #  often negative loss numbers and sometimes gives replies
    #  for other hosts - (def gw?)
    #  Here we instead count the number of correct replies and do the
    #  math ourself
    #
    local recieved_packets

    #  shellcheck disable=SC2126
    recieved_packets="$(echo "$raw_output" | grep -v DUP |
        grep "icmp_seq=" | grep "$cfg_ping_host" | wc -l)"

    percent_loss="$(echo "scale=2;
        100 - 100 * $recieved_packets / $cfg_ping_count" | bc)"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="mon"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

# If true, output of pings with issues will be saved
store_ping_issues=false

d_ping_history="$d_data"/ping_issues

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile_handler.sh
. "$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh

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
#  Check if special handling of output is needed
#
if [[ -d /proc/ish ]] && grep -q '10.' /etc/debian_version; then
    log_it "Checking losses using: calculate_loss_ish_deb10"
    store_ping_issues=true
    loss_check=calculate_loss_ish_deb10
else
    loss_check=calculate_loss_default
fi

$store_ping_issues && log_it "Will save ping issues in $d_ping_history"

#
#  Main loop
#
while true; do
    #
    #  Redirecting stderr is needed since on some platforms, like
    #  running Debian 10 on iSH, you get warning printouts,
    #  yet the ping still works:
    #
    #    WARNING: your kernel is veeery old. No problems.
    #    WARNING: setsockopt(IP_RETOPTS): Protocol not available
    #
    #  If the output gets garbled or no output, it is handled
    #  so in that sense such error msgs can be ignored.
    #
    raw_output="$($ping_cmd 2>/dev/null)"
    output="$(echo "$raw_output" | grep loss)"

    if [[ -n "$output" ]]; then
        $loss_check

        if [[ -z "$percent_loss" ]]; then
            error_msg "Failed to parse ping output," \
                " unlikely to self correct!" \
                0
            percent_loss="$error_unable_to_detect_loss"
        fi
        #
        #  zero % loss is displayed somewhat differently depending on
        #  platform this standardizes no losses into 0
        #
        [[ "$percent_loss" = "0.0" ]] && percent_loss=0 # macos
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
        log_it "No ping output, will sleep $cfg_ping_count seconds"
    fi

    $store_ping_issues && [[ "$percent_loss" != "0" ]] && {
        mkdir -p "$d_ping_history"
        iso_datetime=$(date +'%Y-%m-%d_%H-%M-%S')
        f_ping_issue="$d_ping_history/$iso_datetime"
        log_it "Saving ping issue at: $f_ping_issue"
        echo "$raw_output" >"$f_ping_issue"
    }

    sqlite3 "$sqlite_db" "INSERT INTO t_loss (loss) VALUES ($percent_loss)"
    #  A bit exessive in normal conditions
    [[ "$percent_loss" != "0" ]] && log_it "stored in DB: $percent_loss"
done
