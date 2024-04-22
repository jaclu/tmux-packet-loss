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

not_calculate_loss_default() {
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
        cut -d~ -f 1 | awk 'NF>1{print $NF}' |
        awk '{printf "%.1f", $0}')"

}

ping_parse_error() {
    local err_code="$1"
    local err_msg="$2"

    log_it "*** ping parsing error - $err_msg [$percent_loss]"
    percent_loss="$err_code"
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

scr_loss_default="$D_TPL_BASE_PATH"/scripts/loss_calc_default.sh
scr_loss_ish_deb10="$D_TPL_BASE_PATH"/scripts/loss_calc_ish_deb10.sh

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
error_no_ping_output=101

#
#  If loss is < 0 or > 100 something went wrong, indicate error
#  hopefully a temporary issue.
#
error_invalid_number=102

#  parsing output gave empty result, unlikely to self correct
error_unable_to_detect_loss=201

"$D_TPL_BASE_PATH"/scripts/db_prepare.sh

define_ping_cmd # we need the ping_cmd in kill_any_strays

#
#  Check if special handling of output is needed
#
if [[ -d /proc/ish ]] && grep -q '10.' /etc/debian_version; then
    store_ping_issues=true
    loss_check="$scr_loss_ish_deb10"
else
    loss_check="$scr_loss_default"
fi
log_it "Checking losses using: $(basename "$loss_check")"

$store_ping_issues && log_it "Will save ping issues in $d_ping_history"

#
#  Main loop
#
while true; do
    percent_loss=""
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
    #  the ping output is saved to a variable, so that it can be
    #  saved to a file in case the output gives issues
    #
    output="$($ping_cmd 2>/dev/null)"
    if [[ -n "$output" ]]; then
        percent_loss="$(echo "$output" | $loss_check)"

        if [[ -z "$percent_loss" ]]; then
            msg="Failed to parse ping output, unlikely to self correct!"
            ping_parse_error "$error_unable_to_detect_loss" "$msg"
        elif [[ $(echo "$percent_loss" | wc -w) -gt 1 ]]; then
            ping_parse_error "$error_invalid_number" "multipple words"
        elif (($(echo "$percent_loss < 0.0 || $percent_loss > 100.0" |
            bc -l))); then

            ping_parse_error "$error_invalid_number" "invalid loss rate"
        fi
    else
        #
        #  No output, usually no connection to the host
        #
        ping_parse_error "$error_no_ping_output" "no output"
        #
        #  Some pings instantly aborts on no connection, this will keep
        #  the poll rate kind of normal and avoid rapidly filling the DB
        #  with bad data. Worst case, this will delay monitoring a bit
        #  during an outage.
        #
        sleep "$cfg_ping_count"
    fi

    sqlite3 "$sqlite_db" "INSERT INTO t_loss (loss) VALUES ($percent_loss)" || {
        error_msg "sqlite3 reported error:[$?] when adding a loss"
    }
    #  A bit exessive in normal conditions
    [[ "$percent_loss" != "0.0" ]] && log_it "stored in DB: $percent_loss"

    $store_ping_issues && [[ "$percent_loss" != "0.0" ]] && {
        [[ "$loss_check" != "$scr_loss_default" ]] && {
            #
            #  an alternete check detected a loss
            #  compare result with what default check gives
            #  and log the output if they differ
            #
            alt_percentage_loss="$percent_loss"
            percent_loss="$(echo "$output" | $scr_loss_default)"
            [[ "$percent_loss" != "$alt_percentage_loss" ]] && {
                msg="This alternate[$alt_percentage_loss] and "
                msg+="default[$percent_loss] loss check differ"
                log_it "$msg"
                mkdir -p "$d_ping_history"
                iso_datetime=$(date +'%Y-%m-%d_%H-%M-%S')
                f_ping_issue="$d_ping_history/$iso_datetime"
                log_it "Saving ping issue at: $f_ping_issue"
                echo "$output" >"$f_ping_issue"
            }
        }
    }

    #
    #  Some checks to reduce the risk of having old instances that
    #  keep running in the background.
    #
    [[ -f "$monitor_pidfile" ]] || {
        log_it "*** pidfile has dissapeard - exiting this process"
        exit 1
    }
    pidfile_is_mine "$monitor_pidfile" || {
        #
        #  A new monitor has started and taken ownership of the pidfile.
        #
        #  Shouldn't normally happen, ctrl_monitor.sh would normally
        #  shut down previous monitors before starting a new one.
        #  One reason could be if somebody accidentally manually
        #  removed the pidfile
        #
        log_it "*** pidfile is no longer mine - exiting this process"
        exit 1
    }

done
