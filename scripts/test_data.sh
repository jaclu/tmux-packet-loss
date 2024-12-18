#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
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

tst_error() {
    echo
    echo "ERROR: $1"
    echo
    exit 1
}

insert_data() {
    [[ -f "$pidfile_monitor" ]] && {
        "$scr_ctrl_monitor" stop
        echo "Terminated the monitor."
    }
    echo "Monitor will be restarted automatically"
    echo "$db_max_age_mins minute(-s) after last db change."
    echo

    [[ -z "$loss" ]] && return
    if $keep_db; then
        sql="INSERT INTO t_loss (loss) VALUES ($loss)"
    else
        log_it "Clearing DB"
        sql="
            DELETE FROM t_loss ;
            DELETE FROM t_1_min ;
            INSERT INTO t_loss (loss) VALUES ($loss);
            DELETE FROM t_stats;
            INSERT INTO t_stats (loss) VALUES ($history);"
    fi
    sqlite_transaction "$sql" || {
        msg="sqlite3 exited with: $sqlite_exit_code \n "
        msg+=" when running \n$sql"
        error_msg "$msg"
    }

    # "$D_TPL_BASE_PATH"/scripts/all_data.sh show
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

source "$D_TPL_BASE_PATH"/scripts/utils.sh

[[ -z "$1" ]] && {
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

keep_db=false
[[ "$1" = "--keep" ]] && {
    keep_db=true
    shift
}

loss="$1"
history="${2:-0}"

is_float "$loss" || tst_error "param 1 [$loss] - not a float"

$keep_db && [[ "$history" != "0" ]] && {
    tst_error "When using --keep, history_loss can not be provided"
}

is_float "$history" || tst_error "param 2 not a float"

insert_data "$1" "$2"
