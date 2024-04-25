#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

clear_losses_in_t_loss() {
    [[ -n "$($scr_display_losses)" ]] && {
        log_it "Clearing losses - to ensure plugin isnt stuck alerting"
        sqlite_err_handling "DELETE FROM t_loss WHERE loss != 0" || {
            error_msg "sqlite3[$?] in clear_losses_in_t_loss()"
        }
    }
}

monitor_terminate() {
    local i

    db_monitor="$(basename "$scr_monitor")"

    # check_pidfile_task
    pidfile_is_live "$monitor_pidfile" && {
        log_it "Will kill [$pidfile_proc] $db_monitor"
        kill "$pidfile_proc"
        for ((i = 0; i < 10; i++)); do
            pidfile_is_live "$monitor_pidfile" || break
            sleep 1
            # log_it "waiting i[$i]"
        done
        [[ "$i" -gt 0 ]] && log_it "after loop: [$i]"
        pidfile_is_live "$monitor_pidfile" && {
            error_msg "Failed to terminate $db_monitor [$proc_id]"
        }
        clear_losses_in_t_loss
        log_it "$db_monitor is shutdown"
        killed_monitor=true
    }
    pidfile_release "$monitor_pidfile"
}

monitor_launch() {
    #
    #  Starting a fresh monitor
    #

    nohup "$scr_monitor" >/dev/null 2>&1 &

    sleep 1 # wait for monitor to start
}

packet_loss_shutdown() {
    # tmux has exited, do a cleanup

    pidfile_release "$pidfile_tmux"

    #
    #  remove some stat files that will be generated with
    #  fresh content on next run
    #
    rm -f "$f_param_cache"
    rm -f "$f_previous_loss"
    rm -f "$f_sqlite_errors"
    log_it "tmp files have been deleted"
    exit_script 0
}

exit_script() {
    #
    #  Terminate script doing cleanup
    #
    local exit_code="${1:-0}"

    pidfile_release ""
    log_it "$(basename "$0") - done!"
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
. "$D_TPL_BASE_PATH/scripts/utils.sh"

#  shellcheck source=scripts/vers_check.sh
. "$D_TPL_BASE_PATH/scripts/vers_check.sh"

#
#  Include pidfile handling
#
# shellcheck source=scripts/pidfile_handler.sh
. "$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh

pidfile_acquire "" || {
    error_msg "pid_file - is owned by process [$pidfile_proc]"
}

db_monitor="$(basename "$scr_monitor")"
killed_monitor=false

monitor_terminate

case "$1" in
"stop")
    $killed_monitor || {
        log_it "Did not find any running instances of $scr_monitor"
    }
    exit_script 0
    ;;
"start" | "") ;; # continue the startup
*) error_msg "Valid params: None/start or stop - got [$1]" ;;
esac

monitor_launch

exit_script
