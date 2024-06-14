#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

clear_losses_in_t_loss() {
    log_it "Clearing losses - to ensure plugin isnt stuck alerting"
    sqlite_err_handling "DELETE FROM t_loss WHERE loss != 0" || {
        local msg

        msg="sqlite3 exited with: $sqlite_exit_code \n "
        msg+=" when retrieving Clearing losses for table t_loss"
        error_msg "$msg"
    }
}

monitor_terminate() {
    local i

    db_monitor="$(basename "$scr_monitor")"

    pidfile_is_live "$pidfile_monitor" && {
        log_it "Will kill [$pidfile_proc] $db_monitor"
        kill "$pidfile_proc"
        for ((i = 0; i < 10; i++)); do
            pidfile_is_live "$pidfile_monitor" || break
            sleep 1
            # log_it "waiting i[$i]"
        done
        [[ "$i" -gt 0 ]] && log_it "after loop: [$i]"
        pidfile_is_live "$pidfile_monitor" && {
            error_msg "Failed to terminate $db_monitor"
        }
        log_it "$db_monitor is shutdown"
        killed_monitor=true
    }

    pidfile_release "$pidfile_monitor" || {
        error_msg "pidfile_releae($pid_file_short) reported error: [$?]"
    }
}

monitor_launch() {

    #  Clear out env, some status files that will be created when needed
    rm -f "$f_previous_loss"
    rm -f "$f_sqlite_errors"
    rm -f "$db_restart_log"
    rm -f "$f_monitor_suspended_no_clients"
    log_it "tmp files have been deleted"

    get_tmux_pid >"$pidfile_tmux" # helper for show_settings.sh

    log_it "starting $db_monitor"
    $scr_monitor >/dev/null 2>&1 &
    sleep 1 # wait for monitor to start
}

handle_param() {
    case "$1" in
    start | "")
        monitor_terminate # First kill any running instance
        monitor_launch
        ;;
    stop)
        killed_monitor=false
        monitor_terminate
        clear_losses_in_t_loss # only do on explicit stop
        $killed_monitor || {
            log_it "Did not find any running instances of $scr_monitor"
        }
        exit_script 0
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
    local exit_code="${1:-0}"
    local msg

    pidfile_release "$pidfile_ctrl_monitor"
    msg="$current_script - completed"
    [[ "$exit_code" -ne 0 ]] && msg+=" exit code:$exit_code"
    log_it "$msg"
    exit "$exit_code"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="ctr"

#  shellcheck source=scripts/utils.sh
source "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile_handler.sh
source "$scr_pidfile_handler"

pidfile_acquire "$pidfile_ctrl_monitor" 3 || {
    error_msg "Could not acquire: $pid_file_short"
}

log_it # empty log line to make it easier to see where this starts

handle_param "$1"

exit_script
