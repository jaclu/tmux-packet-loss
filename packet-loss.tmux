#!/usr/bin/env bash
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.3 2022-03-31
#
#   This is the coordination script
#    - ensures the database is present and up to date
#    - sets parameters in the database
#    - ensures packet_loss_monitor is running
#    - binds  #{packet_loss} to check_packet_loss.sh
#



# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS_DIR="$CURRENT_DIR/scripts"
DATA_DIR="$CURRENT_DIR/data"
# shellcheck disable=SC1091
. "$SCRIPTS_DIR/utils.sh"


monitor_proc_full_name="$SCRIPTS_DIR/$monitor_process_scr"
no_sessions_shutdown_full_name="$SCRIPTS_DIR/$no_sessions_shutdown_scr"

db="$DATA_DIR/$sqlite_db"
pid_file="$DATA_DIR/$monitor_pidfile"


#
#  Removal of obsolete files, will be removed eventually.
#
rm -f "$SCRIPTS_DIR/$sqlite_db"
rm -f "$SCRIPTS_DIR/$monitor_pidfile"


#
#  Dependency check
#
if ! command -v sqlite3 > /dev/null 2>&1; then
    error_msg "Missing dependency sqlite3" 1
fi


#
#  Match tag with polling script
#
pkt_loss_interpolation=(
    "\#{packet_loss}"
)

pkt_loss_commands=(
    "#($SCRIPTS_DIR/check_packet_loss.sh)"
)


#
#  Functions only used here are kept here, in order to minimize overhead
#  for sourcing utils.sh in the other scripts.
#



create_db() {
    rm -f "$db"
    log_it "old_db removed"
    #
    #  packet_loss is limited to $hist_size rows, in order to make statistics consistent
    #
    # datetime TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, \
    sqlite3 "$db" " \
        CREATE TABLE packet_loss ( \
            datetime TIMESTAMP DEFAULT (datetime('now','localtime')) NOT NULL, \
            loss float \
        ); \
        CREATE TRIGGER delete_tail AFTER INSERT ON packet_loss \
        BEGIN \
            DELETE FROM packet_loss where rowid < NEW.rowid-(SELECT hist_size from params)+1; \
        END; \
        CREATE TABLE params (host text, ping_count int, hist_size int); \
        PRAGMA user_version=$db_version;"
    log_it "Created db"
}


#
#  Each time the monitor process will be started the params table is
#  populated from current settings.
#
set_db_params() {
    local ping_host
    local ping_count
    local sql

    ping_host=$(get_tmux_option "@packet-loss-ping_host" "$default_host")
    log_it "ping_host=[$ping_host]"

    ping_count=$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")
    log_it "ping_count=[$ping_count]"

    hist_size=$(get_tmux_option "@packet-loss-history_size" "$default_hist_size")
    log_it "hist_size=[$hist_size]"


    # First clear table to assure only one row is present
    sqlite3 "$db" "DELETE FROM params"

    sql="INSERT INTO params (host, ping_count, hist_size) values ("
    sql="$sql"'"'"$ping_host"'"'", $ping_count, $hist_size);"
    sqlite3 "$db" "$sql"
    log_it "db params set"

    # Routine maintenance, should be done every now and then
    # This is run each time tmux is started or sourced, so seems like a good place for it!
    sqlite3 "$db" "PRAGMA optimize; VACUUM"
}


#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    local action="$1"
    local tmux_vers
    local hook_name
    local msg

    tmux_vers="$(tmux -V | cut -d' ' -f2)"
    log_it "hook_handler($action) tmux vers: $tmux_vers"

    # needed to be able to handle versions like 3.2a
    # shellcheck disable=SC1091
    . "$SCRIPTS_DIR/adv_vers_compare.sh"

    if adv_vers_compare "$tmux_vers" ">=" "3.0"; then
        hook_name="session-closed[$hook_array_idx]"
    elif adv_vers_compare "$tmux_vers" ">=" "2.4"; then
        hook_name="session-closed"
    else
        log_it "WARNING: previous to tmux 2.4 session-closed hook is not available, so can not shut down monitor process when tmux exits!"
    fi
    if [ -n "$hook_name" ]; then
        if [ "$action" = "set" ]; then
            tmux set-hook -g "$hook_name" "run $no_sessions_shutdown_full_name"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [ "$action" = "clear" ]; then
            tmux set-hook -ug "$hook_name"
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!" 1
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
    local pid_param
    local remaining_procs
    local msg

    log_it "kill_running_monitor($pid_file)"

    if [ -e "$pid_file" ]; then
        pid="$(cat "$pid_file")"
        log_it "Killing $monitor_process_scr: [$pid]"
        kill "$pid" 2&> /dev/null
        rm -f "$pid_file"
    fi


    #
    #  Each time ping is run, a process with $monitor_process_scr name is spawned.
    #  Kill that one and sometimes left overs if packet_loss.tmux
    #  was run repeatedly in quick succession
    #
    if [ -n "$monitor_process_scr" ]; then
        #
        #  Figure our what ps is available, in order to determine
        #  which param is the pid
        #
        if readlink "$(command -v ps)" | grep -q busybox; then
            log_it "ps param: 1"
            pid_param=1
        else
            log_it "ps param: 2"
            pid_param=2
        fi

        # shellcheck disable=SC2009
        remaining_procs="$(ps axu | grep "$monitor_process_scr" | grep -v grep | awk -v p=$pid_param '{ print $p }' )"
        if [ -n "$remaining_procs" ]; then
            # log_it "### About to kill: [$remaining_procs]"
            echo "$remaining_procs" | xargs kill 2&> /dev/null
        fi
    else
        error_msg "monitor_process_scr not defined, can NOT attempt to kill remaining background processes!" 1
    fi
}


set_tmux_option() {
    local option="$1"
    local value="$2"

    tmux set-option -gq "$option" "$value"
}


do_interpolation() {
    local all_interpolated="$1"
    for ((i=0; i<${#pkt_loss_commands[@]}; i++)); do
        all_interpolated=${all_interpolated//${pkt_loss_interpolation[$i]}/${pkt_loss_commands[$i]}}
    done
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


main() {
    #
    #  By printing some empty lines its easier to keep separate runs apart
    #
    log_it ""
    log_it ""


    #
    #  Always get rid of potentially running background process, since it might
    #  not use current parameters for host and ping_count
    #
    kill_running_monitor


    #
    #  Check if shutdown is requested.
    #
    if [ "$1" = "stop" ]; then
        echo "Requested to shut-down"
        hook_handler clear
        exit 1
    fi


    #
    #  Create fresh database if it is missing or obsolete
    #
    [ "$(sqlite3 "$db" "PRAGMA user_version")" != "$db_version" ] && create_db


    # Should be done every time, since settings might have changed
    set_db_params


    #
    #  Starting a fresh monitor, will use current db_params to define operation
    #
    nohup "$monitor_proc_full_name" > /dev/null 2>&1 &
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
}


main "$*"
