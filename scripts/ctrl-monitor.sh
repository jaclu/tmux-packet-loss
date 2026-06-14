#!/bin/sh
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

clear_losses_in_t_loss() {
    log_it "Clearing losses - to ensure plugin isn't stuck alerting"
    sqlite_transaction "DELETE FROM t_loss WHERE loss != 0" no || {
        _m="sqlite3 exited with: $sqlite_exit_code \n"
        _m="${_m}when clearing losses for table t_loss"
        error_msg "$_m"
    }
}

monitor_terminate() {
    pidfile_is_live "$pidfile_monitor" && {
        log_it "Will kill [$pidfile_proc] $db_monitor"
        kill "$pidfile_proc"

        _mt_i=0
        while [ "$_mt_i" -lt 10 ]; do
            pidfile_is_live "$pidfile_monitor" || break
            log_it "waiting _mt_i[$_mt_i]"
            sleep 1
            _mt_i=$((_mt_i + 1))
            kill "$pidfile_proc"
        done

        [ "$_mt_i" -gt 0 ] && log_it "after loop: [$_mt_i]"
        pidfile_is_live "$pidfile_monitor" && {
            error_msg "Failed to terminate $db_monitor"
        }
        log_it "$db_monitor is shutdown"
        killed_monitor=true
    }

    # In case monitor has crashed, do some cleanup
    pidfile_release "$pidfile_monitor" || {
        error_msg "pidfile_releae($pid_file_short) reported error: [$?]"
    }
}

clear_out_monitor_tmp_files() {
    #
    #  Clear out env, some status files that will be created when needed
    #
    #  The d_data lines are semi temp, to get rid of files made obsolete by
    #  a general file name revwrite at 26-06-07, can eventually be removed
    #
    set -- "$f_log_date" "$f_previous_loss" "$f_sqlite_error" "$f_previous_loss" \
        "$f_monitor_suspended_no_clients" \
        "$d_data"/db_restarted.log "$d_data"/packet_loss.sqlite "$d_data"/param_cache

    _comtf_file_found=false
    for _comtf_f; do
        [ -f "$_comtf_f" ] && {
            _comtf_file_found=true
            log_it "Removing: $_comtf_f"
            rm -f "$_comtf_f" || error_msg "Failed to delete: $_comtf_f"
        }
    done
    # [ -d "$d_ping_issues" ] && {
    #     rm -rf "$d_ping_issues" || error_msg "Failed to delete: $d_ping_issues/"
    #     log_it "Cleared ping issues"
    # }
    if $_comtf_file_found; then
        log_it "All old tmp files have been deleted"
    else
        log_it "No old tmp files found"
    fi
}

monitor_launch() {
    clear_out_monitor_tmp_files

    get_tmux_pid >"$pidfile_tmux" # helper for show-settings.sh

    log_it "starting $db_monitor"
    $f_monitor >/dev/null 2>&1 &
    sleep 1 # wait for monitor to start
}

handle_param() {
    case "$1" in
        start | "")
            monitor_terminate # First kill any running instance
            monitor_launch || error_msg "Failed to launch monitor"
            ;;
        stop)
            killed_monitor=false
            monitor_terminate
            clear_losses_in_t_loss # only do on explicit stop
            $killed_monitor || {
                log_it "Did not find any running instances of $f_monitor"
            }
            ;;
        *)
            msg="Valid params: [None/start|stop] - got [$1]"
            echo "$msg"
            error_msg "$msg"
            ;;

    esac
}

exit_script() {
    #
    #  Terminate script doing cleanup
    #
    exit_code="${1:-0}"

    _m="$current_script - completed"
    [ "$exit_code" -ne 0 ] && _m="$_m exit code:$exit_code"
    log_it "$_m"
    exit "$exit_code"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="ctr"

. "$D_TPL_BASE_PATH"/scripts/utils.sh

# log_it "+++++   Starting script: $(relative_path "$f_current_script"))   +++++"

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile-handler.sh
. "$f_pidfile_handler"

db_monitor="$(basename "$f_monitor")"
log_it "-----   $current_script   -----"
handle_param "$1"
exit_script
