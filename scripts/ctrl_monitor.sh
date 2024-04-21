#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    local action="$1"
    local tmux_vers
    local hook_name

    [[ "$cfg_hook_idx" = "-1" ]] && {
        log_it "session-closed hook not used, due to cfg_hook_idx=-1"
        return
    }

    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"

    # log_it "hook_handler($action) - current tmux vers: $tmux_vers"
    if min_version 3.0a "$tmux_vers"; then
        hook_name="session-closed[$cfg_hook_idx]"
    elif min_version 2.4 "$tmux_vers"; then
        hook_name="session-closed"
    else
        error_msg "WARNING: previous to tmux 2.4 session-closed hook is " \
            "not available, so can not shut down monitor process when " \
            "tmux exits!" 0
    fi

    [[ -n "$hook_name" ]] && {
        if [[ "$action" = "set" ]]; then
            $TMUX_BIN set-hook -g "$hook_name" \
                "run $D_TPL_BASE_PATH/scripts/no_sessions_shutdown.sh"
            log_it "binding $db_monitor shutdown to: $hook_name"
        elif [[ "$action" = "clear" ]]; then
            $TMUX_BIN set-hook -ug "$hook_name" >/dev/null
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!"
        fi
    }
}

clear_losses_in_t_loss() {
    [[ -n "$($scr_display_losses)" ]] && {
        log_it "Clearing losses - to ensure plugin isnt stuck alerting"
        sqlite3 data/packet_loss.sqlite "DELETE FROM t_loss WHERE loss != 0"
    }
}

monitor_terminate() {
    local i

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
        log_it
        killed_monitor=true
    }
    pidfile_release "$monitor_pidfile"
    hook_handler clear
}

monitor_launch() {
    #
    #  Starting a fresh monitor
    #
    # [[ -t 0 ]] && {
    #     log_it "$db_monitor runs in the background, so cant print it's output here"
    #     [[ -n "$log_file" ]] && log_it " it is sent to log_file: $log_file"
    # }
    nohup "$scr_monitor" >/dev/null 2>&1 &

    sleep 1 # wait for monitor to start

    #
    #  When last session terminates, shut down monitor process in order
    #  not to leave any trailing processes once tmux is shut down.
    #
    hook_handler set
}

exit_script() {
    #
    #  Terminate script doing cleanup
    #
    local exit_code="${1:-0}"

    pidfile_release ""
    exit "$exit_code"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$0")")
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
    exit_script
    ;;
"start" | "") ;; # continue the startup
*) error_msg "Valid params: None or stop - got [$1]" ;;
esac

monitor_launch

exit_script 0
