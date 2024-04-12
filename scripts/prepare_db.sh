#!/bin/sh
# shellcheck disable=SC2154
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This can be called any number of times, if db exist and is of the
#   current $db_version, db itself is not touched.
#   The triggers are replaced on each run, to ensure they use current
#   settings.
#

create_db() {
    [ -f "$sqlite_db" ] && {
        rm -f "$sqlite_db"
        log_it "old_db removed"
    }
    #
    #  t_loss is limited to $history_size rows, in order to make statistics consistent
    #
    sql="
    CREATE TABLE t_loss (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    -- Ensures items in t_loss are kept long enough to get 1 min averages
    CREATE TABLE t_1_min (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    -- logs one min avgs for up to @packet-loss-hist_avg_minutes minutes
    CREATE TABLE t_stats (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    PRAGMA user_version = $db_version;  -- replace DB if out of date
    "
    sqlite3 "$sqlite_db" "$sql"
    log_it "Created db"

    unset sql
}

update_triggers() {
    #
    #  Always first drop the triggers if present, since they use
    #  a user defined setting, that might have changed since the DB
    #  was created
    #
    triggers="$(sqlite3 "$sqlite_db" "SELECT * FROM sqlite_master where type = 'trigger'")"

    if [ -n "$triggers" ]; then
        sqlite3 "$sqlite_db" "DROP TRIGGER new_data"
    fi

    sql="
    CREATE TRIGGER new_data AFTER INSERT ON t_loss
    BEGIN
        INSERT INTO t_1_min (loss) VALUES (NEW.loss);

        -- keep loss table within max length
        DELETE FROM t_loss
        WHERE ROWID <
            NEW.ROWID - $history_size + 1;

        -- only keep one min of loss checks
        DELETE FROM t_1_min WHERE time_stamp <= datetime('now', '-1 minutes');

        -- keep statistics table within specified size
        DELETE FROM t_stats WHERE time_stamp <= datetime('now', '-$hist_stat_mins minutes');
    END;
    "
    sqlite3 "$sqlite_db" "$sql"
    log_it "Created db-triggers"

    unset triggers
    unset sql
}

#===============================================================
#
#   Main
#
#===============================================================

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

mkdir -p "$D_TPL_BASE_PATH/data" # ensure folder exists

#
#  Create fresh database if it is missing or obsolete
#
[ "$(sqlite3 "$sqlite_db" "PRAGMA user_version")" != "$db_version" ] && {
    create_db
}

#
#  Depends on user settings, so should be updated each time this
#  starts
#
update_triggers
