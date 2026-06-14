#!/bin/sh
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This runs forever.
#
float_drop_digits() {
    #
    # float to int by dropping all digits
    #
    echo "$1" | sed 's/\./ /' | cut -d' ' -f 1
}

clear_out_old_losses() {
    # log_it clear_out_old_losses()"

    _cool_max_age="$(echo "$cfg_ping_count * $cfg_history_size" | bc)"
    _cool_sql="
        -- Remove old items remaining after a suspend-resume
        DELETE FROM t_loss
        WHERE time_stamp <= datetime('now', '-$_cool_max_age seconds');
        "
    sqlite_transaction "$_cool_sql" || {
        error_msg "clear_out_old_losses() - SQL Error in:: $_cool_sql"
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
    if is_busybox_ping; then
        ping_cmd="ping -W 1"
    else
        _dpc_timeout_help="$(ping -h 2>&1 | grep timeout | head -n 1)"
        case "$_dpc_timeout_help" in
            *-t*)
                # For Darwin (and I guees BSD) the timeout works as expected
                # and is the total amount of seconds allowed for the command
                # this is also usable when host is not responding
                ping_cmd="ping -t $cfg_ping_count"
                ;;
            *-W*)
                # On Linux timeout is per ping sent
                ping_cmd="ping -W 1"
                ;;
            *) ping_cmd="ping" ;; # no timeout param recognized
        esac
    fi

    ping_cmd="$ping_cmd -c $cfg_ping_count $cfg_ping_host"
    [ -f /proc/self/mountinfo ] && {
        # check if this is chrooted
        if ! grep -q " / / " /proc/self/mountinfo; then
            # when chrooted sudo is needed
            ping_cmd="sudo $ping_cmd"
        fi
    }
    log_it "ping cmd used: [$ping_cmd]"
}

ping_parse_error() {
    _ppe_err_code="$1"
    _ppe_err_msg="$2"

    parse_error=true

    log_it "*** ping parsing error - $_ppe_err_msg"
    percent_loss="$_ppe_err_code"
}

# compare_loss_parsers() {
#     #
#     #  When alternate loss calculations are used
#     #  this compares with what the default would give
#     #  and logs items that might need further inspection
#     #  It is not an error in it-self if they differ, but it is
#     #  quick way to gather sample data for testing.
#     #
#     # log_indent="$log_indent"

#     # #
#     # #  an alternete check detected a loss
#     # #  compare result with what default check gives
#     # #  and log the output if they differ
#     # #
#     # log_indent=$((log_indent + 1)) # increase indent until this returns

#     is_busybox_ping && {
#         #
#         #  busybox reports loss average as a rounded down int
#         #  the default ping parser detects this and appends a .0 to
#         #  ensure consistent notation.
#         #  to emulate this 1st round down to int, then append .0
#         #
#         percent_loss="$(float_drop_digits "$percent_loss").0"
#     }
#     _clp_alt_percentage_loss="$percent_loss"
#     percent_loss="$(echo "$ping_output" | $scr_loss_default)"

#     if [ "$percent_loss" != "$_clp_alt_percentage_loss" ]; then
#         _clp_msg="This alternate[$_clp_alt_percentage_loss] and"
#         _clp_msg="$_clp_msg default[$percent_loss] loss check differ"
#         log_it "$_clp_msg"
#         save_ping_issue "$ping_output"
#     else
#         log_it "both parsers agree on [$percent_loss]"
#     fi
# }

is_busybox_ping() {
    #
    #  Variables provided:
    #    b_this_is_busybox_ping
    #

    [ -z "$b_this_is_busybox_ping" ] && {
        log_it "Checking if ping is a BusyBox one"
        #
        #  By saving state, this check only needs to be done once
        #
        if realpath "$(command -v ping)" | grep -qi busybox; then
            log_it "This system uses a busybox ping"
            b_this_is_busybox_ping=true
        else
            b_this_is_busybox_ping=false
        fi
    }
    $b_this_is_busybox_ping #  return status
}

abort_conditions() {
    #
    #  Some checks to reduce the risk of having old instances that
    #  keep running in the background.
    #
    #  Will return
    #   0 (true) if everything seems fine
    #   1 If an error condition was observed
    #   2 If monitoring should be suspended for non-errror reasons, such
    #     as there is no tmux clients connected.
    #

    do_not_run_check # since this is run in a loop repeat the check

    pidfile_is_mine "$pidfile_monitor" || {
        #
        #  A new monitor has started and taken ownership of the pidfile.
        #
        #  Shouldn't normally happen, ctrl_monitor.sh would normally
        #  shut down previous monitors before starting a new one.
        #  One reason could be if somebody accidentally manually
        #  removed the pidfile
        #
        if [ -n "$pidfile_proc" ]; then
            msg="pidfile: $pid_file\nnow belongs to process: $pidfile_proc"
            error_msg "$msg \n$exit_msg"
        else
            # self healing, eventually monitor will be restarted
            error_msg "pidfile disappeared: $pid_file_short - $exit_msg" \
                1 false
        fi
    }

    #
    #  Check TMUX socket, to verify tmux server is still running
    #
    if [ "$kernel_name" = "Darwin" ]; then
        # macOS uses a different format for stat
        group_exec_permission=$(stat -F "$tmux_socket" | cut -c 7)
    else
        # Assume Linux
        group_exec_permission=$(stat -c "%A" "$tmux_socket" | cut -c 7)
    fi

    if [ "$group_exec_permission" != "x" ]; then
        # shellcheck disable=SC2154 # cfg_run_disconnected defined via eval in utils.sh
        if pidfile_is_live "$pidfile_tmux"; then
            $cfg_run_disconnected && return 0 # continue to run

            touch "$f_monitor_suspended_no_clients"
            log_it "No clients connected to tmux server"
        else
            log_it "tmux is no longer running"
            rm -f "$pidfile_tmux"
        fi
        return 2 # Not an error, shutting down due to policy
    fi

    # $parse_error && {
    #     #
    #     #  in order not to constantly loop and potentially
    #     #  flooding the log_file
    #     #
    #     log_it "Sleeping due to parse error"
    #     sleep 10
    # }
    return 0
}

do_monitor_loop() {
    #
    #  Main loop
    #
    err_count=0
    err_count_max=3 # terminate if this many errors have occurred
    exit_msg="exiting this process"

    log_it "Starting the monitoring loop"
    while true; do
        percent_loss=""
        parse_error=false
        [ "$err_count" -ge "$err_count_max" ] && {
            log_it "*** shutting down - error count reached: $err_count_max"
            break
        }

        [ ! -s "$f_sqlite_db" ] && {
            #
            #  If DB was removed, then a (failed) sql action was attempted
            #  this would lead to an empty DB, by removing such next call
            #  to display-losses will recreate it and restart monitoring
            #
            # rm -f "$f_sqlite_db"
            error_msg "database file gone $exit_msg" -1 false
            #  next call to $f_display_losses will start a new monitor
            break
        }
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
        if ping_output="$($ping_cmd 2>&1)"; then
            [ "$no_network" = 1 ] && {
                log_it "Network reachable"
                no_network=0
            }

            if [ -n "$ping_output" ]; then
                percent_loss="$(echo "$ping_output" | $loss_check)" || {
                    log_it "$(basename "$loss_check") returned error"
                    err_count=$((err_count + 1))
                    continue
                }
                if [ -z "$percent_loss" ]; then
                    msg="Failed to parse ping output, unlikely to self correct!"
                    ping_parse_error "$error_unable_to_detect_loss" "$msg"
                elif ! is_float "$percent_loss"; then
                    ping_parse_error "$error_invalid_number" "not a float"
                elif [ "$(echo "$percent_loss < 0.0 || $percent_loss > 100.0" \
                    | bc -l)" -eq 1 ]; then

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
        else
            ping_exit_code="$?"

            if [ "$kernel_name" = Darwin ]; then
                _nnc_pattern="No route to host" # exit 2
            elif [ -d /proc/ish ]; then
                _nnc_pattern="Host is unreachable" # iSH
            else
                _nnc_pattern="Network is unreachable" # Linux
            fi
            case "$ping_output" in
                *"$_nnc_pattern"*)
                    # Network at this end seems down
                    percent_loss="$error_ping_no_network"
                    no_network=1
                    log_it "No network"
                    ;;
                *)
                    # log_it "ping exit code: $ping_exit_code then output"
                    # log_it "$ping_output]"
                    case "$kernel_name:$ping_exit_code" in
                        Darwin:2 | Linux:1)
                            # Not error, just no response
                            percent_loss=100.0
                            log_it "No ping response from host: $cfg_ping_host"
                            ;;
                        *)
                            log_it "kernel: [$kernel_name] - ping [$ping_exit_code] output: [$ping_output]"
                            ping_parse_error "$error_ping_exit" "exit code: $ping_exit_code"
                            sleep "$cfg_ping_count"
                            ;;
                    esac
                    ;;
            esac
        fi

        #
        #  Many environments lists average losses with one decimal, but not all,
        #  BusyBox is one example. In the end, all that is needed is an
        #  agreement on what indicates no losses.
        #
        [ "$percent_loss" = 0.0 ] && percent_loss=0

        if sqlite_transaction "INSERT INTO t_loss (loss) VALUES ($percent_loss)"; then
            [ "$percent_loss" != 0 ] && {
                log_it "stored in DB: $percent_loss"

                $store_ping_issues \
                    && ! $parse_error \
                    && [ "$loss_check" != "$scr_loss_default" ] \
                    && compare_loss_parsers
            }
        else
            error_msg "sqlite3[$sqlite_exit_code] when adding a loss" -1 false
            err_count=$((err_count + 1))
        fi

        abort_conditions || break

        [ "$no_network" = 1 ] && [ "$kernel_name" = Linux ] && {
            # no network connection. On Linux, ping fails almost
            # instantly when no network, so add a sleep to keep a normalish
            # pace in order to not flood DB (and logfile if used)
            # Do this after updating losses, in order not to delay statusbar
            # notification of no network
            sleep "$cfg_ping_count"
        }

        # log_it "><> main loop has completed"
    done
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="mon"

. "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile-handler.sh
. "$f_pidfile_handler"

# log_it "+++++   Starting script: $(relative_path "$f_current_script"))   +++++"

pidfile_acquire "$pidfile_monitor" 3 || {
    error_msg "Could not acquire: $pid_file_short"
}

# Used to indicate that network seems to be down
no_network=0

kernel_name=$(uname -s)

tmux_socket="$(echo "$TMUX" | cut -d',' -f1)"

# If true, output of pings with issues will be saved
store_ping_issues=true

#
#  Since loss is always <=100, indicate errors with results over 100
#  Not crucial to remember exactly what it means,
#  enough to know is >100 means monitor error
#

#
#  This computer has no network connection
#
error_ping_no_network=101

#  Failed to find %loss in ping output, most likely temporary,
#  some pings just report:
#    ping: sendto: Host is unreachable
#  if network is unreachable
#
error_no_ping_output=102

#
#  If loss is < 0 or > 100 something went wrong, indicate error
#  hopefully a temporary issue.
#
error_invalid_number=103

#
#  ping returned an error, at least on iSH this happens when not
#  connected to the network
#
error_ping_exit=104

#  parsing output gave empty result, unlikely to self correct
error_unable_to_detect_loss=201

scr_loss_default="$D_TPL_BASE_PATH"/scripts/ping_parsers/loss_calc_default.sh
scr_loss_ish_deb10="$D_TPL_BASE_PATH"/scripts/ping_parsers/loss_calc_ish_deb10.sh

#  Ensure DB and all triggers are valid
$f_prepare_db

define_ping_cmd # we need the ping_cmd in kill_any_strays

#
#  Check if special handling of output is needed
#
if [ -d /proc/ish ] && grep -q '10.' /etc/debian_version 2>/dev/null; then
    store_ping_issues=true
    loss_check="$scr_loss_ish_deb10"
else
    loss_check="$scr_loss_default"
fi
log_it "Checking losses using: $(basename "$loss_check")"
$store_ping_issues && log_it "Will save ping issues in $d_ping_issues"

clear_out_old_losses

do_monitor_loop

pidfile_release "$pidfile_monitor"
log_it "$current_script - completed"
