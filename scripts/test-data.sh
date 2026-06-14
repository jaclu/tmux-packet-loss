#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Used to feed test data into the DB, run without params to see help
#
#  If the monitor is running it will be terminated. One minute after
#  latest DB update the monitor will be automatically re-started, so no
#  risk of forgetting to resume the monitor - it is self correcting.
#

show_help() {
    echo "Usage: $current_script [--keep] tst_loss [history_loss]

Purpose: checking how statusbar displays various states.
Suspends monitor process and inserts given data.
Unless --keep is the first param, DB will be cleared. If keeping data in
order to observe falloff, the recommendation is to first run this once
without keep, in order to start with an empty DB.

Sample usages:
    $current_script 33.3      Simulate 33.3% loss with no average loss
    $current_script 33.3 5.4  Simulate 33.3% loss with 5.4% average loss
    $current_script --keep 10 Append a new 10% loss, keeping the DB"

    exit 0
}

tst_error() {
    echo
    echo "ERROR: $1"
    echo
    exit 1
}

insert_data() {
    [ -z "$percent_loss" ] && error_msg "$current_script:insert_data() - no param"

    $keep_db || {
        _msg="Clearing DB"
        echo "$_msg"
        log_it "$_msg"
        sql="
            DELETE FROM t_loss ;
            DELETE FROM t_1_min ;
            DELETE FROM t_stats;"
        sqlite_transaction "$sql" || {
            error_msg "sqlite3[$sqlite_exit_code] when clearing DB"
        }
    }

    sqlite_transaction "INSERT INTO t_loss (loss) VALUES ($percent_loss)" || {
        # shellcheck disable=SC2154
        error_msg "sqlite3[$sqlite_exit_code] when adding a loss"
    }
    log_it "Injected fake loss: $percent_loss"
    [ "$history" != 0 ] && {
        sqlite_transaction "DELETE FROM t_stats" || {
            error_msg "sqlite3[$sqlite_exit_code] when clearing losses"
        }
        sqlite_transaction "INSERT INTO t_stats (loss) VALUES ($history)" || {
            # shell check disable=SC2154
            error_msg "sqlite3[$sqlite_exit_code] when adding a loss"
        }
        log_it "Replaced history data"
    }
}

#===============================================================
#
#   Main
#
#===============================================================

#
#  Only source utils if params are valid, to avoid so
#

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="tst"

. "$D_TPL_BASE_PATH"/scripts/utils.sh

[ -z "$1" ] && show_help

if [ "$1" = "--keep" ]; then
    keep_db=true
    shift
else
    keep_db=false
fi

percent_loss="$1"
history="${2:-0}"

[ -n "$percent_loss" ] || tst_error "No loss param"
is_float "$percent_loss" || tst_error "param 1 [$percent_loss] - not a float"
is_float "$history" || tst_error "param 2 not a float"

[ -f "$pidfile_monitor" ] && {
    log_it "Shutting down monitor"
    $f_ctrl_monitor stop || error_msg "Failed to shut down: $f_ctrl_monitor"
    # log_it "monitor shut down by $current_script"
}

insert_data "$1" "$2"

printf "%s %s %s\n" \
    "Monitor will be restarted automatically" \
    "$db_max_age_mins" \
    "minutes after last db change."
echo "  To start monitor right away run: ./scripts/ctrl-monitor.sh"
