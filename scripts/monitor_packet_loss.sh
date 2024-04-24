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
        sed 's/packet loss/~/ ; s/%//' | cut -d~ -f 1 | awk 'NF>1{print $NF}' |
        awk '{printf "%.1f", $0}')" # last line ensures it's correctly rounded
}

calculate_loss_ish_deb10() {
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
        100 - 100 * $recieved_packets / $cfg_ping_count" | bc |
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

d_ping_history="$d_data"/ping_issues

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile_handler.sh
. "$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh

pidfile_acquire "$monitor_pidfile" || {
    error_msg "$monitor_pidfile - is owned by process [$pidfile_proc]"
}

tmux_pid=$(echo "$TMUX" | sed 's/,/ /g' | cut -d' ' -f 2)
log_it "Will monitor pressence of master tmux pid: $tmux_pid"

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

define_ping_cmd # we need the ping_cmd in kill_any_strays

#
#  Check if special handling of output is needed
#
if [[ -d /proc/ish ]] && grep -q '10.' /etc/debian_version; then
    store_ping_issues=true
    loss_check=calculate_loss_ish_deb10
else
    loss_check=calculate_loss_default
fi
log_it "Checking losses using: $loss_check"

$store_ping_issues && log_it "Will save ping issues in $d_ping_history"

"$D_TPL_BASE_PATH"/scripts/prepare_db.sh

#
#  Main loop
#
log_it "Starting the monitoring loop"
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
        $loss_check

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
    #  A bit exessive in normal conditions
    [[ "$percent_loss" != "0.0" ]] && log_it "stored in DB: $percent_loss"

    $store_ping_issues && [[ "$percent_loss" != "0.0" ]] && {
        [[ "$loss_check" != "calculate_loss_default" ]] && {
            #
            #  an alternete check detected a loss
            #  compare result with what default check gives
            #  and log the output if they differ
            #
            alt_percentage_loss="$percent_loss"
            calculate_loss_default
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

    [[ -n "$tmux_pid" ]] && ! is_pid_alive "$tmux_pid" && {
        #
        #  If the socket isnt executable, the tmux starting this monitor
        #  has terminated, so monitor should shut down
        #
        log_it "*** tmux is gone - master process no longer writeable"

        # check how shutdown is handled on ish, dont exit right away
        sleep 5

        log_it "exiting due to missing tmux master process"
        break
    }
done
