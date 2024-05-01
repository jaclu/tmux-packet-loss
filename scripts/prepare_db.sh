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
#   The data triggers are replaced on each run, to ensure they use
#   current tmux settings.
#
#   ---  DB revision history  ---
#   12 - Changed triggers
#   11 - Added minute_trigger
#
create_db() {
    [[ -f "$sqlite_db" ]] && {
        rm -f "$sqlite_db"
        log_it "old_db removed"
    }
    #
    #  t_loss is limited to $cfg_history_size records, in order to make
    #  statistics consistent
    #
    local sql="
    CREATE TABLE t_loss (
        time_stamp TIMESTAMP DEFAULT (datetime('now')) NOT NULL,
        loss DECIMAL(5,1)
    );

    -- Unless just starting, all items inserted into t_loss are also
    -- inserted here, to ensure we can get 1 min averages
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
    sqlite_transaction "$sql" || {
        error_msg "sqlite3[$?] when creating the DB"
    }
    log_it "Created DB - user_version: $db_version"
}

update_triggers() {
    #
    #  Always first drop the new_data trigger if present, since they use
    #  a user defined setting, that might have changed since the DB
    #  was created
    #
    local sql

    sql="
    DROP TRIGGER IF EXISTS new_loss;
    DROP TRIGGER IF EXISTS new_minute
    "
    sqlite_transaction "$sql" || {
        error_msg "sqlite3[$?] when dropping triggers"
    }

    #
    #  If a device wakes up from sleep it might take a while unitl the
    #  network connection is back online.
    #  To minimize getting crap into the statistics, the first 30 seconds
    #  of data is not stored in t_1_min
    #  Since all records older than one minute have just been erased from
    #  t_1_min previously in the trigger, its enough to count the number
    #  of records present in t_1_min to detect this condition.
    #  Normally ping count would be low, but if it is over 30, no such
    #  filtering will happen.
    #
    #  Since a 0 loss is inserted at end of this script, to ensure
    #  all tables have data, add one to compensate for this.
    #
    ignore_first_items=$(echo "1 + 30 / $cfg_ping_count" | bc)
    log_it "ignore_first_items: $ignore_first_items"

    sql="
    CREATE TRIGGER IF NOT EXISTS new_loss
    AFTER INSERT ON t_loss
    BEGIN
        -- Keep t_loss table within max size
        DELETE FROM t_loss
        WHERE ROWID < NEW.ROWID - $cfg_history_size + 1;

        -- Only keep one minute of records in t_1_min
        -- Clear old records before considering to insert, to ensure no
        -- unintended averages are saved after a sleep.
        DELETE FROM t_1_min
        WHERE time_stamp <= datetime('now', '-1 minutes');

        -- Insert new loss into t_1_min unless this is startup
        INSERT INTO t_1_min (loss)
        SELECT CASE
            -- If machine was just resuming, and network isn't up yet
            -- This prevents early losses to skew the stats
            WHEN (SELECT COUNT(*) FROM t_1_min) < $ignore_first_items THEN 0
            ELSE NEW.loss
        END;
    END;

    CREATE TRIGGER IF NOT EXISTS new_minute
        AFTER INSERT ON t_1_min
        WHEN (
            -- Check if no records for this minute are present
            (
                SELECT COUNT(*)
                FROM t_stats
                WHERE time_stamp >= datetime(strftime('%Y-%m-%d %H:%M'))
            ) = 0
        )
        AND (
            -- Check if the oldest record in t_1_min is older than 30 seconds
            (
                SELECT strftime('%s', 'now') - strftime('%s', MIN(time_stamp))
                FROM t_1_min
            ) > 30
        )
    BEGIN
        INSERT INTO t_stats (loss)
        SELECT COALESCE(avg(loss), 0)
        FROM t_1_min;

        -- Keep statistics table within specified age
        DELETE FROM t_stats
        WHERE time_stamp <= datetime('now', '-$cfg_hist_avg_minutes minutes');
    END;
    "
    sqlite_transaction "$sql" || {
        error_msg "sqlite3[$?] when creating triggers"
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
current_db_vers="$(sqlite_err_handling "PRAGMA user_version")"

[[ "$current_db_vers" != "$db_version" ]] && {
    log_it "DB incorrect user_version: $current_db_vers"
    create_db
}

#
#  Depends on user settings, so should be updated each time this
#  starts
#
update_triggers

# a lot of DB related code depends on there being at least one record
sqlite_transaction "INSERT INTO t_loss (loss) VALUES (0)"
