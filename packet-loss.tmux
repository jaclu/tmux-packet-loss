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
#    - binds  #{packet_loss_stat} to check_packet_loss.sh
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
    "\#{packet_loss_stat}"
)

pkt_loss_commands=(
    "#($SCRIPTS_DIR/check_packet_loss.sh)"
)


create_db() {
    rm -f "$db"
    log_it "old_db removed"
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
    ping_host=$(get_tmux_option "@packet-loss-ping_host" "$default_host")
    log_it "ping_host=[$ping_host]"

    ping_count=$(get_tmux_option "@packet-loss-ping_count" "$default_ping_count")
    log_it "ping_count=[$ping_count]"

    # First clear table to assure only one row present
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
set_hook_session_closed() {
    tmux_vers="$(tmux display -p '#{version}')"
    log_it "set_hook_session_closed($tmux_vers)"

    if [ $(echo "$tmux_vers >= 3.0" | bc) -eq 1 ]; then
        # hook arrays are available, use a random number in order not to
        # collide with other stuff using the same hook
        tmux set-hook -g session-closed[1819] "run $SCRIPTS_DIR/check_shutdown.sh"
    elif [ $(echo "$tmux_vers >= 2.4" | bc) -eq 1 ]; then
        log_it "Using non array hook, might have overwritten other hook action"
        tmux set-hook -g session-closed "run $SCRIPTS_DIR/check_shutdown.sh"
    else
        log_it "before tmux 2.4 session-closed hook is not available, so can not shut down monitor process when tmux exits"
    fi
}


#
#  Removing any current monitor process.
#  monitor is always started with current settings due to the fact that
#  parameters might have changed since it was last started
#
kill_running_monitor() {
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


    kill_running_monitor


    #
    #  Check if shutdown is requested.
    #
    if [ "$1" = "stop" ]; then
        echo "Requested to shut-down"
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
    set_hook_session_closed


    #
    #  Activate #{packet_loss_stat} tag if used
    #
    update_tmux_option "status-left"
    update_tmux_option "status-right"
}

main "$*"
