#!/usr/bin/env bash
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-menus
#
#   Version: 0.0.0a 2022-03-20
#


CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SCRIPTS_DIR="$CURRENT_DIR/scripts"

. "$SCRIPTS_DIR/utils.sh"

db="$SCRIPTS_DIR/$sqlite_db"

monitoring_process="$SCRIPTS_DIR/packet_loss_monitor.sh"
monitor_pidfile="$SCRIPTS_DIR/$monitor_pidfile"

keyboard_interpolation=(
    "\#{packet_loss_stat}"
)

keyboard_commands=(
    "#($SCRIPTS_DIR/check_packet_loss.sh)"
)


set_tmux_option() {
    local option="$1"
    local value="$2"

    tmux set-option -gq "$option" "$value"
}


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
    sql=" \
        DELETE FROM params; \
        INSERT INTO params (host, ping_count, hist_size) values ("
    sql="$sql"'"'"$ping_host"'"'", $ping_count, $hist_size);"
    sqlite3 "$db" "$sql"
    log_it "db params set"
}


do_interpolation() {
    local all_interpolated="$1"
    for ((i=0; i<${#keyboard_commands[@]}; i++)); do
        all_interpolated=${all_interpolated//${keyboard_interpolation[$i]}/${keyboard_commands[$i]}}
    done
}


update_tmux_option() {
    local option="$1"
    local option_value
    local new_option_value

    log_it "processing [$option]"
    option_value="$(get_tmux_option "$option")"
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}


#
#  By printing a NL and date, its easier to keep separate runs apart
#
log_it ""
log_it "$(date)"

if ! command -v sqlite3; then
    tmux display "tmux-packet-loss ERROR: missing dependency sqlite3"
    exit 1
fi

if [ -f "$monitor_pidfile" ]; then
    pid="$(cat $monitor_pidfile)"
    if [ -n "$(ps |grep "$monitoring_process" | grep "$pid" )" ]; then
        kill "$pid"
        log_it "killed running monitor"
    fi
fi

[ "$(sqlite3 "$db" "PRAGMA user_version")" != "$db_version" ] && create_db

# Should be done every time, since settings might have changed
set_db_params

"$monitoring_process" &
log_it "Started monitoring process"


update_tmux_option "status-left"
update_tmux_option "status-right"
