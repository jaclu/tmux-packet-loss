#!/usr/bin/env bash
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.0.2 2022-03-22
#
#   This is the coordination script
#    - ensures the database is present and up to date
#    - sets params in the database
#    - ensures packet_loss_monitor is running
#    - binds  #{packet_loss} to check_packet_loss.sh
#


#
#  Dependency check
#
if ! command -v sqlite3 > /dev/null 2>&1; then
    tmux display "tmux-packet-loss ERROR: missing dependency sqlite3"
    exit 1
fi


CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS_DIR="$CURRENT_DIR/scripts"
. "$SCRIPTS_DIR/utils.sh"


db="$SCRIPTS_DIR/$sqlite_db"
monitor_proc_full_name="$SCRIPTS_DIR/$monitor_process"
pid_file="$SCRIPTS_DIR/$monitor_pidfile"


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
    sqlite3 "$db" " \
        CREATE TABLE packet_loss (loss float, datetime TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL); \
        CREATE TRIGGER delete_tail AFTER INSERT ON packet_loss \
        BEGIN \
            DELETE FROM packet_loss where rowid < NEW.rowid-(SELECT hist_size from params)+1; \
        END; \
        CREATE TABLE params (host text, ping_count int, hist_size int); \
        PRAGMA user_version=$db_version;"
    log_it "Created db"
}


set_db_params() {
    local ping_host
    local ping_count
    local sql

    ping_host=$(get_tmux_option "@packet-loss-ping_host" "$default_host")
    log_it "ping_host=[$ping_host]"

    ping_count=$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")
    log_it "ping_count=[$ping_count]"

    # First clear table to assure only one row is present
    sqlite3 "$db" "DELETE FROM params"

    sql="INSERT INTO params (host, ping_count, hist_size) values ("
    sql="$sql"'"'"$ping_host"'"'", $ping_count, $hist_size);"
    sqlite3 "$db" "$sql"
    log_it "db params set"
}


#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    local action="$1"
    local tmux_vers
    local hook_name

    tmux_vers="$(tmux -V | cut -d' ' -f2)"
    log_it "hook_handler($action) tmux vers: $tmux_vers"

    # needed to be able to handle versions like 3.2a
    . "$SCRIPTS_DIR/adv_vers_compare.sh"

    if adv_vers_compare $tmux_vers ">=" "3.0"; then
        hook_name="session-closed[$hook_array_idx]"
    elif adv_vers_compare $tmux_vers ">=" "2.4"; then
        hook_name="session-closed"
    else
        log_it "before tmux 2.4 session-closed hook is not available, so can not shut down monitor process when tmux exits"
    fi
    if [ -n "$hook_name" ]; then
        if [ "$action" = "set" ]; then
            tmux set-hook -g "$hook_name" "run $SCRIPTS_DIR/check_shutdown.sh"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [ "$action" = "clear" ]; then
            tmux set-hook -ug "$hook_name"
            log_it "releasing: $hook_name"
        else
            log_it "ERROR: set_hook_session_closed must be called with param set or clear!"
        fi
    fi
}


#
#  Removing any current monitor process.
#  monitor is always started with current settings due to the fact that
#  parameters might have changed since it was last started
#
kill_running_monitor() {
    local pid

    log_it "kill_running_monitor($pid_file)"

    if [ -e "$pid_file" ]; then
        pid="$(cat "$pid_file")"
        log_it "Killing $monitor_process: [$pid]"
        kill "$pid"
        rm -f "$pid_file"
    else
        log_it "pid_file not found, assuming no process running"
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
    #  By printing a NL and date, its easier to keep separate runs apart
    #
    log_it ""
    log_it "$(date)"


    #
    #  Always get rid of potentially running background process, since it might
    #  not use current params for host and ping_count
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
    log_it "Started $monitor_process"


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
