#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Show / Clear content of all tables
#
app_name=$(basename "$0")

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="a_d"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

action="$1"

case "$action" in
show)
    cmd="SELECT *"
    ;;
stats)
    cmd=""
    ;;
clear)
    cmd="DELETE"
    log_it "DB will be cleared"
    ;;
*)
    echo "usage: $app_name show/stats/clear"
    exit 1
    ;;
esac

tables=$(sqlite3 "$sqlite_db" ".tables")
for table in $tables; do
    echo "-----  Table: $table"
    [[ -n "$cmd" ]] && sqlite3 "$sqlite_db" "$cmd FROM $table;"
    echo "average: $(
        sqlite3 "$sqlite_db" "SELECT round(avg(loss),1) FROM $table;"
    )"
    echo
done
