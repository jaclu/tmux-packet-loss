#!/usr/bin/env bash

sqlite_cmd() {
    local sql="$1"

    echo "Will run: $sql"
    sqlite3 "$D_TPL_BASE_PATH"/data//packet_loss.sqlite "$sql"

}

clear_db() {
    sql="
        INSERT INTO t_loss (loss) VALUES (0);"
    # INSERT INTO t_stats (loss) VALUES(0);"
    sqlite_cmd "$sql"
}

insert_data() {
    local loss="$1"
    local history="${2:-0}"

    [[ -z "$loss" ]] && return
    sql="DELETE FROM t_loss ;
        DELETE FROM t_1_min ;
        INSERT INTO t_loss (loss) VALUES ($loss);
        DELETE FROM t_stats;
        INSERT INTO t_stats (loss) VALUES ($history);"
    sqlite_cmd "$sql"
}

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")

# clear_db

insert_data "$1" "$2"
