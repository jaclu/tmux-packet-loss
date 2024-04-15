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

    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"

    log_it "hook_handler($action) - current tmux vers: $tmux_vers"
    if min_version 3.0a "$tmux_vers"; then
        hook_name="session-closed[$hook_idx]"
    elif min_version 2.4 "$tmux_vers"; then
        hook_name="session-closed"
    else
        error_msg "WARNING: previous to tmux 2.4 session-closed hook is " \
            "not available, so can not shut down monitor process when " \
            "tmux exits!" 0
    fi

    if [[ -n "$hook_name" ]]; then
        if [[ "$action" = "set" ]]; then
            $TMUX_BIN set-hook -g "$hook_name" "run $D_TPL_BASE_PATH/scripts/no_sessions_shutdown.sh"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [[ "$action" = "clear" ]]; then
            $TMUX_BIN set-hook -ug "$hook_name" >/dev/null
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!"
        fi
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

#  shellcheck source=vers_check.sh
. "$D_TPL_BASE_PATH/scripts/vers_check.sh"

log_prefix="ctr"
killed_monitor=false

pidfile_acquire "" || error_msg "pid_file - is owned by process [$pidfile_proc]"
log_it "aquire successfull"
log_it
db_monitor="$(basename "$scr_monitor")"

# check_pidfile_task
pidfile_is_live "$monitor_pidfile" && {
    log_it "Will kill [$pidfile_proc] $db_monitor"
    kill "$pidfile_proc"
    sleep 1
    pidfile_is_live "$monitor_pidfile" && {
        error_msg "Failed to kill [$pidfile_proc]"
    }
    log_it "$db_monitor is shutdown"
    killed_monitor=true
}
rm -f "$monitor_pidfile"

hook_handler clear

case "$1" in

"stop")
    if $killed_monitor; then
        echo "terminated $scr_monitor"
    else
        echo "Did not find any running instances of $scr_monitor"
    fi
    pidfile_release
    exit 0
    ;;

"start" | "") ;; # continue the startup

*) error_msg "Valid params: None or stop - got [$1]" ;;

esac

#
#  Starting a fresh monitor
#
nohup "$scr_monitor" >/dev/null 2>&1 &

sleep 1 # wait for monitor to start

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler set

pidfile_release ""
