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
        error_msg \
            "sqlite3[$sqlite_exit_code] in clear_losses_in_t_loss()" 1 false
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
            error_msg "Failed to terminate $db_monitor [$proc_id]" 1 false
        }
        log_it "$db_monitor is shutdown"
        killed_monitor=true
    }
    pidfile_release "$pidfile_monitor"
    clear_losses_in_t_loss
    rm -f "$f_previous_loss"
}

monitor_launch() {

    #
    #  Starting a fresh monitor
    #
    log_it "starting $db_monitor"
    $scr_monitor >/dev/null 2>&1 &
    sleep 1 # wait for monitor to start
}

packet_loss_plugin_shutdown() {
    # tmux has exited, do a cleanup

    pidfile_is_live "$pidfile_tmux" && {
        error_msg "$this_app shutdown called when tmux is running" 1 false
    }

    sleep 1 #  monitor should have exited by now
    pidfile_is_live "$pidfile_monitor" && {
        error_msg \
            "$this_app shutdown failed - monitor still running" 1 false
    }

    #
    #  remove some stat files that will be generated with
    #  fresh content on next run
    #
    pidfile_release "$pidfile_tmux"
    rm -f "$f_previous_loss"
    rm -f "$f_sqlite_errors"
    rm -f "$db_restart_log"
    rm -f "$pidfile_tmux"
    log_it "tmp files have been deleted"
    exit_script 0
}

exit_script() {
    #
    #  Terminate script doing cleanup
    #
    local exit_code="${1:-0}"

    pidfile_release "$pidfile_ctrl_monitor"
    msg="$this_app - done!"
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

pidfile_acquire "$pidfile_ctrl_monitor" || {
    error_msg "$this_app is already running - process [$pidfile_proc]"
}

log_it # empty log line to make it easier to see where this starts

case "$1" in
start | "")
    monitor_terminate # First kill any running instance
    monitor_launch
    ;;
stop)
    killed_monitor=false
    monitor_terminate
    $killed_monitor || {
        log_it "Did not find any running instances of $scr_monitor"
    }
    exit_script 0
    ;;
shutdown) packet_loss_plugin_shutdown ;;

*)
    msg="Valid params: [None/start|stop|shutdown] - got [$1]"
    echo "$msg"
    error_msg "$msg"
    ;;

esac

exit_script
