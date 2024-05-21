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

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

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
    echo "usage: $this_app show/avgs/clear"
    exit 1
    ;;
esac

tables=(t_stats t_1_min t_loss)

for table in "${tables[@]}"; do
    echo "--------  Table: $table  --------"
    [[ -n "$cmd" ]] && sqlite3 "$sqlite_db" "$cmd FROM $table;"

    #
    #  Display averages - and for t_loss also weighted avg
    #
    if [[ "$table" = "t_loss" ]]; then
        sql_current_loss true
        weighted="$(sqlite_err_handling "$sql")" || {
            sqlite_exit_code="$?"
            error_msg "sqlite3[$sqlite_exit_code] when retrieving current weighted losses" 1 false
        }
        sql_current_loss false
        avg="$(sqlite_err_handling "$sql")" || {
            sqlite_exit_code="$?"
            error_msg "sqlite3[$sqlite_exit_code] when retrieving current avg losses" 1 false
        }
        printf "average: %5.1f  weighted: %5.1f\n" "$avg" "$weighted"
    else
        sql="SELECT round(avg(loss),1) FROM $table;"
        avg="$(sqlite_err_handling "$sql")" || {
            sqlite_exit_code="$?"
            error_msg "sqlite3[$sqlite_exit_code] when retrieving current avg losses" 1 false
            printf "average: %-6s  weighted: %-6s\n" "$avg" "$ weighted"
        }
        printf "average: %5.1f\n" "$avg"
    fi
    echo
done
