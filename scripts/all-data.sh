#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Show / Clear content of all tables
#

show_help() {
    echo "usage: $current_script show | avgs | clear"
    echo
    echo "  show   Display all stored data"
    echo "  avgs   Show averages"
    echo "  clear  Clear all data"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="a_d"

. "$D_TPL_BASE_PATH"/scripts/utils.sh

[ -f "$f_sqlite_db" ] || {
    error_msg "Database not found - aborting"
}

action="$1"

case "$action" in
    show)
        #cmd="SELECT time_stamp,round(loss,1)"
        cmd="SELECT time_stamp || '  ' || round(loss, 1) AS formatted_output"
        ;;
    avgs)
        db_seems_inactive && {
            error_msg "Database > 2 minutes old, so monitor is assumed to be inactive"
        }
        cmd=""
        ;;
    clear)
        cmd="DELETE"
        log_it "DB will be cleared"
        ;;
    *)
        show_help
        exit 1
        ;;
esac

old_ifs="$IFS"
IFS=','
set -- t_stats t_1_min t_loss
# set -- t_loss
for table; do
    echo "--------  Table: $table  --------"
    [ -n "$cmd" ] && {
        # log_sql=true
        sqlite_err_handling "$cmd FROM $table"
        echo "$sqlite_result"
    }

    #
    #  Display averages - and for t_loss also weighted avg
    #
    if [ "$table" = "t_loss" ]; then
        sql_current_loss true
        weighted="$sqlite_result"

        sql_current_loss false
        printf "average: %5.1f  weighted: %5.1f\n" "$sqlite_result" "$weighted"
    else
        sql="SELECT round(avg(loss),1) FROM $table;"
        sqlite_err_handling "$sql"
        printf "average: %5.1f\n" "$sqlite_result"
    fi
    echo
done
IFS="$old_ifs"
