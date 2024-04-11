#!/usr/bin/env bash
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.2.1 2022-09-15
#
#   This is the coordination script
#    - ensures the database is present and up to date
#    - sets parameters in the database
#    - ensures packet_loss_monitor is running
#    - binds  #{packet_loss} to check_packet_loss.sh
#

#
#  Functions only used here are kept here, in order to minimize overhead
#  for sourcing utils.sh in the other scripts.
#

create_db() {
    local sql

    rm -f "$sqlite_db"
    mkdir -p "$D_TPL_BASE_PATH/data"
    log_it "old_db removed"

    #
    #  t_loss is limited to $history_size rows, in order to make statistics consistent
    #
    sql="
    CREATE TABLE t_loss (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    -- Ensures items in t_loss are kept long enough to get 1 min averages
    CREATE TABLE t_1_min (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    -- logs one min avgs for up to @packet-loss-hist_avg_minutes minutes
    CREATE TABLE t_stats (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    PRAGMA user_version = $db_version;  -- replace DB if out of date
    "
    sqlite3 "$sqlite_db" "$sql"
    log_it "Created db"
}

update_triggers() {
    local sql

    #
    #  Always first drop the triggers if present, since they use
    #  a user defined setting, that might have changed since the DB
    #  was created
    #
    triggers="$(sqlite3 "$sqlite_db" "SELECT * FROM sqlite_master where type = 'trigger'")"

    if [[ -n "$triggers" ]]; then
        sqlite3 "$sqlite_db" "DROP TRIGGER new_data"
    fi

    sql="
    CREATE TRIGGER new_data AFTER INSERT ON t_loss
    BEGIN
        INSERT INTO t_1_min (loss) VALUES (NEW.loss);

        -- keep loss table within max length
        DELETE FROM t_loss
        WHERE ROWID <
            NEW.ROWID - $history_size + 1;

        -- only keep one min of loss checks
        DELETE FROM t_1_min WHERE time_stamp <= datetime('now', '-1 minutes');

        -- keep statistics table within specified size
        DELETE FROM t_stats WHERE time_stamp <= datetime('now', '-$hist_stat_mins minutes');
    END;
    "
    sqlite3 "$sqlite_db" "$sql"
    log_it "Created db-triggers"
}

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    local action="$1"
    local tmux_vers
    local hook_name

    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"
    log_it "hook_handler($action) tmux vers: $tmux_vers"

    # needed to be able to handle versions like 3.2a
    #  shellcheck source=/dev/null
    . "$D_TPL_BASE_PATH/scripts/adv_vers_compare.sh"

    if adv_vers_compare "$tmux_vers" ">=" "3.0"; then
        hook_name="session-closed[$hook_idx]"
    elif adv_vers_compare "$tmux_vers" ">=" "2.4"; then
        hook_name="session-closed"
    else
        error_msg "WARNING: previous to tmux 2.4 session-closed hook is " \
            "not available, so can not shut down monitor process when " \
            "tmux exits!" 0
    fi

    if [[ -n "$hook_name" ]]; then
        if [[ "$action" = "set" ]]; then
            $TMUX_BIN set-hook -g "$hook_name" "run $no_sessions_shutdown_scr"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [[ "$action" = "clear" ]]; then
            $TMUX_BIN set-hook -ug "$hook_name"
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!"
        fi
    fi
}

#
#  Removing any current monitor process.
#  monitor will always be restarted with current settings due to the fact that
#  parameters might have changed since it was last started
#
kill_running_monitor() {
    local pid
    local proc_to_check
    local pid_param
    local remaining_procs

    if [[ -e "$monitor_pidfile" ]]; then
        log_it "kill_running_monitor($monitor_pidfile)"
        pid="$(cat "$monitor_pidfile")"
        log_it "Killing $monitor_process_scr: [$pid]"
        kill "$pid" 2 &>/dev/null
        rm -f "$monitor_pidfile"
    fi

    #
    #  Each time ping is run, a process with $monitor_process_scr name is spawned.
    #  Kill that one and sometimes left overs if packet_loss.tmux
    #  was run repeatedly in quick succession
    #
    if [[ -n "$monitor_process_scr" ]]; then
        [[ -e "$monitor_process_scr" ]] || {
            error_msg "monitor_process_scr [$monitor_process_scr] not found!"
        }

        #
        #  Kill any remaining running instances of $monitor_process_scr
        #  that were not caught via the pidfile
        #
        proc_to_check="/bin/sh $monitor_process_scr"
        if [[ -n "$(command -v pkill)" ]]; then
            pkill -f "$proc_to_check"
        else
            #
            #  Figure our what ps is available, in order to determine
            #  which param is the pid
            #
            if readlink "$(command -v ps)" | grep -q busybox; then
                pid_param=1
            else
                pid_param=2
            fi

            # shellcheck disable=SC2009
            remaining_procs="$(ps axu | grep "$proc_to_check" |
                grep -v grep | awk -v p="$pid_param" '{ print $p }')"
            if [[ -n "$remaining_procs" ]]; then
                # log_it " ### About to kill: [$remaining_procs]"
                echo "$remaining_procs" | xargs kill 2 &>/dev/null
            fi
        fi
        if [[ -n "$(command -v pgrep)" ]]; then
            remaining_procs="$(pgrep -f "$proc_to_check")"
        else
            # shellcheck disable=SC2009
            remaining_procs="$(ps ax | grep "$proc_to_check" | grep -v grep)"
        fi
        [[ -n "$remaining_procs" ]] && {
            error_msg "Failed to kill all monitoring procs [$remaining_procs]"
        }
    else
        error_msg "monitor_process_scr not defined, can NOT attempt to kill remaining background processes!"
    fi
}

do_interpolation() {
    local all_interpolated="$1"

    all_interpolated=${all_interpolated//$pkt_loss_interpolation/$pkt_loss_command}
    echo "$all_interpolated"
}

update_tmux_option() {
    local option="$1"
    local option_value
    local new_option_value

    option_value="$(get_tmux_option "$option")"
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

#===============================================================
#
#   Main
#
#===============================================================

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname -- "$(realpath -- "$0")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

#
#  Match tag with polling script
#
pkt_loss_interpolation="\#{packet_loss}"
pkt_loss_command="#($D_TPL_BASE_PATH/scripts/check_packet_loss.sh)"

#
#  Dependency check
#
if ! command -v sqlite3 >/dev/null 2>&1; then
    error_msg "Missing dependency sqlite3"
fi

#
#  By printing some empty lines its easier to keep separate runs apart
#
log_it
log_it
show_settings

#
#  Always get rid of potentially running background process, since it might
#  not use current parameters for host and ping count and might use an
#  old DB deffinition
#
kill_running_monitor

case "$1" in

"start" | "") ;; # continue the startup

"stop")
    echo "Requested to shut-down"
    hook_handler clear
    exit 1
    ;;

*) error_msg "Valid params: None or stop - got [$1]" ;;

esac

#
#  Create fresh database if it is missing or obsolete
#
[[ "$(sqlite3 "$sqlite_db" "PRAGMA user_version")" != "$db_version" ]] && {
    create_db
}

#
#  Depends on user settings, so should be updated each time this
#  starts
#
update_triggers

#
#  Starting a fresh monitor
#
# a="$(sqlite3 $sqlite_db 'PRAGMA user_version')"
# echo "
# outputL  [$a]
# sqlite_db[$sqlite_db]"
# exit 1

nohup "$monitor_process_scr" >/dev/null 2>&1 &
log_it "Started background process: $monitor_process_scr"

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler set

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
