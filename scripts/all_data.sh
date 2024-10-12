#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Show / Clear content of all tables
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="a_d"

source "$D_TPL_BASE_PATH"/scripts/utils.sh

action="$1"

case "$action" in
show)
    #cmd="SELECT time_stamp,round(loss,1)"
    cmd="SELECT time_stamp || '  ' || round(loss, 1) AS formatted_output"
    ;;
avgs)
    cmd=""
    ;;
clear)
    cmd="DELETE"
    log_it "DB will be cleared"
    ;;
*)
    echo "usage: $current_script show/avgs/clear"
    exit 1
    ;;
esac

tables=(t_stats t_1_min t_loss)

for table in "${tables[@]}"; do
    echo "--------  Table: $table  --------"
    [[ -n "$cmd" ]] && sqlite3 "$f_sqlite_db" "$cmd FROM $table;"

    #
    #  Display averages - and for t_loss also weighted avg
    #
    if [[ "$table" = "t_loss" ]]; then
        sql_current_loss true
        sqlite_err_handling "$sql" || {
            sqlite_exit_code="$?"
            msg="sqlite3 exited with: $sqlite_exit_code \n"
            msg+="when retrieving current weighted losses for table $table"
            error_msg "$msg"
        }
        weighted="$sqlite_result"

        sql_current_loss false
        sqlite_err_handling "$sql" || {
            sqlite_exit_code="$?"
            msg="sqlite3 exited with: $sqlite_exit_code \n "
            msg+=" when retrieving current avg losses for table $table"
            error_msg "$msg"
        }
        printf "average: %5.1f  weighted: %5.1f\n" "$sqlite_result" "$weighted"
    else
        sql="SELECT round(avg(loss),1) FROM $table;"
        sqlite_err_handling "$sql" || {
            sqlite_exit_code="$?"
            msg="sqlite3 exited with: $sqlite_exit_code \n "
            msg+=" when retrieving current avg losses for table $table"
            error_msg "$msg"
        }
        printf "average: %5.1f\n" "$sqlite_result"
    fi
    echo
done
