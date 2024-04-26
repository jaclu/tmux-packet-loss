#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever.
#
float_digits() {
    local value="$1"
    local digits="$2"

    [[ -z "$digits" ]] && {
        error_msg "rouns_float($value,) - missing digits param" 1 false
    }
    printf "%.${digits}f" "$value"
}

float_2_int() {
    float_digits "$1" 0
}

float_drop_digits() {
    #
    # float to int by dropping all digits
    #
    echo "$1" | sed 's/\./ /' | cut -d' ' -f 1
}

is_int() {
    case $1 in
    '' | *[!0-9]*) return 1 ;; # Contains non-numeric characters
    *) return 0 ;;             # Contains only digits
    esac
}

define_ping_cmd() {
    #
    #  Figuring out the nature of the available ping cmd
    #  Variables provided:
    #    ping_cmd - options adjusted for the local environment
    #    is_busybox_ping - true if it was busybox
    #
    local timeout_help
    local timeout_parameter

    if realpath "$(command -v ping)" | grep -qi busybox; then
        is_busybox_ping=true
    else
        is_busybox_ping=false
    fi
    $is_busybox_ping && log_it "system useses BusyBox ping"

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
    percent_loss="$(echo "$output" | grep "packet loss" |
        sed 's/packet loss/~/ ; s/%//' | cut -d~ -f 1 | awk 'NF>1{print $NF}')"
}

not_calculate_loss_ish_deb10() {
    #
    #  with most pings ' icmp_seq=' can be used to identify a reply
    #  Obviously busybox uses ' seq=' ...
    #

    #  shellcheck disable=SC2126
    recieved_packets="$(echo "$output" | grep -v DUP | grep "seq=" |
        grep "$cfg_ping_host" | wc -l)"

    #
    #  Sometimes this gets extra replies fom 8.8.8.8
    #  If 8.8.4.4 is pinged filtering on $cfg_ping_host gets rid of them,
    #  if 8.8.8.8 is the pinghost this will signal results over 100
    #
    #  Did a quick fix, but will leave it commented out for now to gather
    #  some more stats on how often this happens.
    #
    # [[ "$recieved_packets" -gt "$cfg_ping_count" ]] && {
    #     recieved_packets="$cfg_ping_count"
    # }

    #
    #  bc rounds 33.3333 to 33.4 to work arround this, bc uses two digits
    #  printf rounds it down to one
    #
    percent_loss="$(echo "scale=2;
    100 - 100 * $recieved_packets / $cfg_ping_count" | bc)"
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
    local alt_percentage_loss
    local msg
    local iso_datetime
    local f_ping_issue
    #
    #  an alternete check detected a loss
    #  compare result with what default check gives
    #  and log the output if they differ
    #
    log_it "Double checking loss calculation"
    alt_percentage_loss="$percent_loss"
    ! is_busybox_ping && [[ "$loss_check" = "$scr_loss_ish_deb10" ]] && {
        #  in the summary ping is sometimes given with 4 digits...
        percent_loss=$(float_digits "$(echo "$output" | $scr_loss_default)" 1)
    }
    is_int "$percent_loss" && {
        #
        #  if default used no digits, round the alt to int in order to
        #  avoid irrelevant differences
        #
        if $is_busybox_ping; then
            #
            #  Allways round it down by dropping digits,
            #  busybox ping is one of a kind...
            #
            alt_percentage_loss=$(float_drop_digits "$alt_percentage_loss")
        else
            alt_percentage_loss=$(float_2_int "$alt_percentage_loss")
        fi
    }
    [[ "$percent_loss" != "$alt_percentage_loss" ]] && {
        msg="This alternate[$alt_percentage_loss] and "
        msg+="default[$percent_loss] loss check differ"
        log_it "$msg"
        mkdir -p "$d_ping_history"
        iso_datetime=$(date +'%Y-%m-%d_%H:%M:%S')
        f_ping_issue="$d_ping_history/$iso_datetime"
        log_it "Saving ping issue at: $f_ping_issue"
        echo "$output" >"$f_ping_issue"
    }
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

d_ping_history="$d_data"/ping_issues

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
$store_ping_issues && log_it "Will save ping issues in $d_ping_history"

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
    output="$($ping_cmd 2>/dev/null)"
    if [[ -n "$output" ]]; then
        percent_loss="$(echo "$output" | $loss_check)" || {
            log_it "$(basename "$loss_check") returned error"
            exit 1
        }
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

    #
    #  Many environments lists average losses with one decimal, but not all,
    #  BusyBox is one example. In the end, all that is needed is an agreement
    #  on what describes no losses.
    #
    [[ "$percent_loss" = 0.0 ]] && percent_loss=0

    sqlite_err_handling "INSERT INTO t_loss (loss) VALUES ($percent_loss)" || {
        err_code=$?
        if [[ "$err_code" = 5 ]]; then
            log_it "DB locked"
        else
            #  log the issue as an error, then continue
            error_msg "sqlite3[$err_code] when adding a loss" 0 false
        fi
        continue
    }
    [[ "$percent_loss" != 0 ]] && {
        log_it "stored in DB: $percent_loss"

        $store_ping_issues && ! $parse_error &&
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
