#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This can be called any number of times, if db exist and is of the
#   current $db_version, db itself is not touched.
#
#   The new_data trigger is replaced on each run, to ensure they use
#   current tmux settings.
#
#   ---  DB history  ---
#   11 - Added minute_trigger
#
create_db() {
    [[ -f "$sqlite_db" ]] && {
        rm -f "$sqlite_db"
        log_it "old_db removed"
    }
    #
    #  t_loss is limited to $cfg_history_size rows, in order to make statistics consistent
    #
    local sql="
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
}

update_triggers() {
    #
    #  Always first drop the new_data trigger if present, since they use
    #  a user defined setting, that might have changed since the DB
    #  was created
    #
    local new_data_trigger_exists
    local sql

    new_data_trigger_exists=$(
        sqlite3 "$sqlite_db" \
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = 'new_data';"
    )

    [[ "$new_data_trigger_exists" != "0" ]] && sqlite3 "$sqlite_db" \
        "DROP TRIGGER new_data"

    # t_stats is updated aprox once/minute at the end of monitor_packet_loss.sh
    sql="
    CREATE TRIGGER IF NOT EXISTS new_data
    AFTER INSERT ON t_loss
    BEGIN
        INSERT INTO t_1_min (loss) VALUES (NEW.loss);

        -- keep loss table within max length
        DELETE FROM t_loss
        WHERE ROWID <
            NEW.ROWID - $cfg_history_size + 1;

        -- only keep one min of loss checks
        DELETE FROM t_1_min WHERE time_stamp <= datetime('now', '-1 minutes');

        -- keep statistics table within specified size
        DELETE FROM t_stats WHERE time_stamp <=
               datetime('now', '-$cfg_hist_avg_minutes minutes');
    END;

    CREATE TRIGGER IF NOT EXISTS minute_trigger
    AFTER INSERT ON t_1_min
    WHEN (
            SELECT COUNT(*)
            FROM t_stats
            WHERE time_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))
        ) = 0
    BEGIN
        INSERT INTO t_stats (loss) SELECT avg(loss) FROM t_1_min;
    END;
    "
    sqlite3 "$sqlite_db" "$sql"
    log_it "Created db-triggers"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")

log_prefix="prp"

# shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  Create fresh database if it is missing or obsolete
#
[[ "$(sqlite3 "$sqlite_db" "PRAGMA user_version")" != "$db_version" ]] && {
    create_db
}

#
#  Depends on user settings, so should be updated each time this
#  starts
#
update_triggers
