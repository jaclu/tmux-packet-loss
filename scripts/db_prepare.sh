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
    sqlite3 "$sqlite_db" "$sql" || {
        error_msg "sqlite3 reported error:[$?] when creating the DB"
    }
    log_it "Created db"
}

update_triggers() {
    #
    #  Always first drop the new_data trigger if present, since they use
    #  a user defined setting, that might have changed since the DB
    #  was created
    #
    local sql

    sql="DROP TRIGGER IF EXISTS new_loss; DROP TRIGGER IF EXISTS new_minute"
    sqlite3 "$sqlite_db" "$sql" || {
        error_msg "sqlite3 reported error:[$?] when dropping triggers"
    }

    #
    #  If a device wakes up from sleep it might take a while unitl the
    #  network connection is back online.
    #  To minimize getting crap into the statistics the first 30 seconds
    #  of data is not stored in t_1_min
    #  Since all records older than one minute has just been erased from
    #  t_1_min previously in the trigger, its enough to count the number
    #  of records present in t_1_min to detect this condition.
    #  Normally ping count would be low, but if it is over 30, no such
    #  filtering will happen.
    #
    ignore_first_items=$(echo "30 / $cfg_ping_count" | bc)

    sql="
    CREATE TRIGGER IF NOT EXISTS new_loss
    AFTER INSERT ON t_loss
    BEGIN
        -- keep loss table within max length
        DELETE FROM t_loss
        WHERE ROWID <
            NEW.ROWID - $cfg_history_size + 1;

        -- Insert new loss into t_1_min unless this is startup
        INSERT INTO t_1_min (loss)
        SELECT CASE
            -- if machine was just resuming, and network isnt up yet
            -- this prevents early losses to skew the stats
            WHEN (SELECT COUNT(*) FROM t_1_min) < $ignore_first_items THEN 0
            ELSE NEW.loss
        END;

        -- only keep one min of records in t_1_min
        DELETE FROM t_1_min WHERE time_stamp <= datetime('now', '-1 minutes');
    END;

    CREATE TRIGGER IF NOT EXISTS new_minute
    AFTER INSERT ON t_1_min
    WHEN (
            SELECT COUNT(*)
            FROM t_stats
            WHERE time_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))
        ) = 0
    BEGIN
        INSERT INTO t_stats (loss) SELECT avg(loss) FROM t_1_min;

        -- keep statistics table within specified age
        DELETE FROM t_stats WHERE time_stamp <=
        datetime('now', '-$cfg_hist_avg_minutes minutes');
    END;
    "
    sqlite3 "$sqlite_db" "$sql" || {
        error_msg "sqlite3 reported error:[$?] when creating triggers"
    }
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
