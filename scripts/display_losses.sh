#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Reports current packet loss status for the plugin
#

script_exit() {
    #
    #  wrap status in prefix/suffix and exit gracefully
    #
    local status="$1"

    [[ -n "$status" ]] && echo "${cfg_prefix}${status}${cfg_suffix}"

    [[ -n "$2" ]] && {
        # param check
        error_msg "script_exit() got 2nd unexpected param: [$2]"
    }
    # log_it "script_exit() - $current_script - completed"
    exit 0
}

restart_monitor() {
    log_date_change "restart_monitor" #OK
    log_it "restarting monitor $1"
    $scr_ctrl_monitor start || error_msg "ctrl_monitor gave error on start"
    date >>"$db_restart_log" # log current time
}

db_seems_inactive() {
    #
    #  New records should normally be written to the DB every cfg_ping_count
    #  seconds. If it hasn't happened, it can be assumed that the monitor
    #  is no longer oprtating normally.
    #  To allow for disabling the monitor shorter periods for example
    #  when using scripts/test_data.sh, wait a couple of minutes before
    #  restart.
    #
    [[ -n "$(find "$f_sqlite_db" -mmin +"$db_max_age_mins")" ]]
}

verify_db_status() {
    #
    #  Some sanity check, ensuring the monitor is running
    #

    if [[ ! -s "$f_sqlite_db" ]]; then
        #
        #  Since if the DB doesn't exist and a read is being done, an
        #  empty DB is created. This makes a check for existence of the
        #  DB invalid. The -s check ensures it is of size > 0 thus would
        #  catch empty DBs having been created by a read
        #
        local db_issue="DB missing or broken"

        log_date_change "$db_issue" #OK

        error_msg "$db_issue" -1 false
        #
        #  If DB is missing, try to start the monitor
        #
        restart_monitor "$db_issue"
        log_it "$db_issue - monitor was restarted"

        [[ -s "$f_sqlite_db" ]] || {
            error_msg "$db_issue - DB could not be created - aborting"
        }
    elif [[ -f "$f_monitor_suspended_no_clients" ]]; then
        restart_monitor "- was suspended due to no clients"
    elif db_seems_inactive; then
        #
        #  If DB is over a minute old,
        #  assume the monitor is not running, so (re-)start it
        #
        restart_monitor "DB is over $db_max_age_mins minutes old"
    fi
}

get_current_loss() {
    #
    #  public variables defined
    #   current_loss
    #
    local sql

    #  shellcheck disable=SC2086 # boolean - can't be quoted
    sql_current_loss $cfg_weighted_average

    # CAST seems to always round down...
    sqlite_err_handling "$sql" || {
        local sqlite_exit_code="$?"
        local msg

        msg="sqlite3 exited with: $sqlite_exit_code \n "
        msg+=" when retrieving current losses"
        error_msg "$msg"
    }
    current_loss=$(printf "%.0f" "$sqlite_result") # float -> int
}

get_prev_loss() {
    #
    #  public variables defined
    #   prev_loss
    #
    if [[ -f "$f_previous_loss" ]]; then
        read -r prev_loss <"$f_previous_loss"
    else
        prev_loss=0
    fi
}

set_prev_loss() {
    [[ -z "$prev_loss" ]] && get_prev_loss

    if [[ "$current_loss" -gt 0 ]]; then
        echo "$current_loss" >"$f_previous_loss"
    else
        rm -f "$f_previous_loss"
    fi

    # log loss changes
    $log_loss_changes && [[ "$prev_loss" -ne "$current_loss" ]] &&
        {
            if [[ "$current_loss" -gt 0 ]]; then
                log_it "$s_log_result"
            else
                log_it "no packet losses"
            fi
        }
}

show_trend() {
    #
    #  Indicate if losses are increasing / decreasing setting +/- prefix
    #
    #  public variables provided
    #    result
    #
    [[ -z "$prev_loss" ]] && get_prev_loss

    if [[ "$prev_loss" -ne "$current_loss" ]]; then
        if [[ "$current_loss" -gt "$prev_loss" ]]; then
            result="+$current_loss"
        elif [[ "$current_loss" -lt "$prev_loss" ]]; then
            result="-$current_loss"
        fi
    fi
}

colorize_high_numbers() {
    #
    #  If loss is over trigger levels, display in appropriate color
    #
    local number="$1" # numerical value to check
    local item="$2"   # string that might get color

    if awk -v val="$number" -v trig_lvl="$cfg_level_crit" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        item="#[fg=$cfg_color_crit,bg=$cfg_color_bg]${item}#[default]"
    elif awk -v val="$number" -v trig_lvl="$cfg_level_alert" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        item="#[fg=$cfg_color_alert,bg=$cfg_color_bg]${item}#[default]"
    fi
    echo "$item"
}

display_history() {
    #
    #  Display history
    #
    #  Outside variables modified:
    #    s_log_result - will be used by main to display current losses
    #
    local sql
    local avg_loss_raw

    sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER)"
    sqlite_err_handling "$sql" || {
        local sqlite_exit_code="$?"

        error_msg "sqlite3[$sqlite_exit_code] when retrieving history" \
            -1 false
        return
    }
    avg_loss_raw="$sqlite_result"

    if [[ "$avg_loss_raw" != "0" ]]; then
        local avg_loss

        #
        #  If stats is over trigger levels, display in appropriate color
        #
        avg_loss="$(
            colorize_high_numbers "$avg_loss_raw" "$avg_loss_raw"
        )"
        result="${result}${cfg_hist_separator}${avg_loss}"
        s_log_result="$s_log_result   avg: $avg_loss_raw"
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

#
#  Prevent tmux from running this every couple of seconds,
#  convenient during debugging
#
# [[ "$1" != "hepp" ]] && exit 0

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="dsp"

source "$D_TPL_BASE_PATH"/scripts/utils.sh

log_loss_changes=false # set to false to reduce logging from this module
result=""              # indicating no losses

verify_db_status

get_current_loss

[[ "$current_loss" -lt "$cfg_level_disp" ]] && current_loss=0

s_log_result="loss: $current_loss" # might get altered by display_history

if [[ "$current_loss" -gt 0 ]]; then
    result="$current_loss"

    #
    #  Check trend, ie change since last update
    #
    $cfg_display_trend && show_trend

    result="$(colorize_high_numbers "$current_loss" "$result")"

    $cfg_hist_avg_display && display_history

    #
    #  Set prefix & suffix for result and report to status bar
    #
    script_exit "$result"
fi

$cfg_display_trend && set_prev_loss

# log_it "$current_script - completed"

script_exit
