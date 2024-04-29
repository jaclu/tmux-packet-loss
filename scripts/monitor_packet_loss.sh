#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever.
#
is_int() {
    case $1 in
    '' | *[!0-9]*) return 1 ;; # Contains non-numeric characters
    *) return 0 ;;             # Contains only digits
    esac
}

float_drop_digits() {
    #
    # float to int by dropping all digits
    #
    echo "$1" | sed 's/\./ /' | cut -d' ' -f 1
}

define_ping_cmd() {
    #
    #  Figuring out the nature of the available ping cmd
    #  Variables provided:
    #    ping_cmd - options adjusted for the local environment
    #
    local timeout_help
    local timeout_parameter

    is_busybox_ping && log_it "system useses BusyBox ping"
    #
    #  Selecting the right timeout option
    #
    if is_busybox_ping; then
        timeout_parameter="-W"
    else
        timeout_help="$(ping -h 2>&1 | grep timeout | head -n 1)"
        if [[ $timeout_help == *-t* ]]; then
            timeout_parameter="-t"
        elif [[ $timeout_help == *-W* ]]; then
            timeout_parameter="-W"
        else
            timeout_parameter=""
        fi
    fi

    if [[ -n "$timeout_parameter" ]]; then
        ping_cmd="ping $timeout_parameter $cfg_ping_count"
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

ping_parse_error() {
    local err_code="$1"
    local err_msg="$2"

    parse_error=true

    log_it "*** ping parsing error - $err_msg [$percent_loss]"
    percent_loss="$err_code"
}

compare_loss_parsers() {
    #
    #  When alternate loss calculations are used
    #  this compares with what the default would give
    #  and logs items that might need further inspection
    #  It is not an error in it-self if they differ, but it is
    #  quick way to gather sample data for testing.
    #
    local log_indent=$log_indent
    local alt_percentage_loss
    local msg
    #
    #  an alternete check detected a loss
    #  compare result with what default check gives
    #  and log the output if they differ
    #
    ((log_indent++)) # increase indent until this returns

    is_busybox_ping && {
        #
        #  busybox reports loss average as a rounded down int
        #  the default ping parser detects this and appends a .0 to
        #  ensure consistent notation.
        #  to emulate this 1st round down to int, then append .0
        #
        percent_loss="$(float_drop_digits "$percent_loss").0"
    }
    alt_percentage_loss="$percent_loss"
    percent_loss="$(echo "$ping_output" | $scr_loss_default)"

    if [[ "$percent_loss" != "$alt_percentage_loss" ]]; then
        msg="This alternate[$alt_percentage_loss] and "
        msg+="default[$percent_loss] loss check differ"
        log_it "$msg"
        save_ping_issue "$ping_output"
    else
        log_it "both parsers agree on [$percent_loss]"
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="mon"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile_handler.sh
. "$scr_pidfile_handler"

pidfile_acquire "$pidfile_monitor" || {
    error_msg "$pidfile_monitor - is owned by process [$pidfile_proc]"
}

pidfile_is_live "$pidfile_tmux" || error_msg "tmux pidfile not found!"

# If true, output of pings with issues will be saved
store_ping_issues=false

#
#  Since loss is always <=100, indicate errors with results over 100
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

define_ping_cmd # we need the ping_cmd in kill_any_strays

scr_loss_default="$D_TPL_BASE_PATH"/scripts/ping_parsers/loss_calc_default.sh
scr_loss_ish_deb10="$D_TPL_BASE_PATH"/scripts/ping_parsers/loss_calc_ish_deb10.sh

#
#  Check if special handling of output is needed
#
if [[ -d /proc/ish ]] && grep -q '10.' /etc/debian_version 2>/dev/null; then
    store_ping_issues=true
    loss_check="$scr_loss_ish_deb10"
else
    loss_check="$scr_loss_default"
fi
log_it "Checking losses using: $(basename "$loss_check")"
$store_ping_issues && log_it "Will save ping issues in $d_ping_issues"

#  Ensure DB and all triggers are vallid
"$D_TPL_BASE_PATH"/scripts/prepare_db.sh

#
#  Main loop
#
log_it "Starting the monitoring loop"
while true; do
    percent_loss=""
    parse_error=false

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
    ping_output="$($ping_cmd 2>/dev/null)"
    if [[ -n "$ping_output" ]]; then
        percent_loss="$(echo "$ping_output" | $loss_check)" || {
            log_it "$(basename "$loss_check") returned error"
            exit 1
        }
        if [[ -z "$percent_loss" ]]; then
            msg="Failed to parse ping output, unlikely to self correct!"
            ping_parse_error "$error_unable_to_detect_loss" "$msg"
        elif ! is_float "$percent_loss"; then
            ping_parse_error "$error_invalid_number" "not a float"
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

    #
    #  Many environments lists average losses with one decimal, but not all,
    #  BusyBox is one example. In the end, all that is needed is an
    #  agreement on what indicates no losses.
    #
    [[ "$percent_loss" = 0.0 ]] && percent_loss=0

    sqlite_transaction "INSERT INTO t_loss (loss) VALUES ($percent_loss)" || {
        err_code=$?
        if [[ "$err_code" = 5 ]]; then
            log_it "DB locked when attmpting to insert loss:$percent_loss"
        else
            #  log the issue as an error, then §continue
            error_msg "sqlite3[$err_code] when adding a loss" 0 false
        fi
        continue
    }
    [[ "$percent_loss" != 0 ]] && {
        log_it "stored in DB: $percent_loss"

        $store_ping_issues &&
            ! $parse_error &&
            [[ "$loss_check" != "$scr_loss_default" ]] &&
            compare_loss_parsers
    }

    #
    #  Some checks to reduce the risk of having old instances that
    #  keep running in the background.
    #

    [[ -f "$pidfile_monitor" ]] || {
        log_it "*** pidfile has dissapeard - exiting this process"
        exit 1
    }

    pidfile_is_mine "$pidfile_monitor" || {
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

    pidfile_is_live "$pidfile_tmux" || {
        log_it "tmux has exited, terminating packet-loss monitor"

        #
        #  By calling this in the background, this process can kill itself
        #  reducing risk of iSH craching
        #
        $scr_ctrl_monitor shutdown &
        break
    }
    $parse_error && {
        #
        #  in order not to constantly loop and potentially
        #  flooding the log_file
        #
        log_it "Sleeping due to parse error"
        sleep 10
    }
done

pidfile_release "$pidfile_monitor"
