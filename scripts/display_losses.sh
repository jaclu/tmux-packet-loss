#!/bin/sh
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
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
    status="$1"

    [ -n "$status" ] && echo "${cfg_prefix}${status}${cfg_suffix}"

    [ -n "$2" ] && {
        # param check
        error_msg "script_exit() got 2nd unexpected param: [$2]"
    }
    # log_it "script_exit() - $current_script - completed"
    exit 0
}

restart_monitor() {
    log_it "restarting monitor $1"
    $scr_ctrl_monitor start || error_msg "ctrl_monitor gave error on start"
    date >>"$db_restart_log" # log current time
}

verify_db_status() {
    #
    #  Some sanity check, ensuring the monitor is running
    #

    if [ ! -s "$f_sqlite_db" ]; then
        #
        #  Since if the DB doesn't exist and a read is being done, an
        #  empty DB is created. This makes a check for existence of the
        #  DB invalid. The -s check ensures it is of size > 0 thus would
        #  catch empty DBs having been created by a read
        #
        _vds_db_issue="DB missing or broken"

        error_msg "$_vds_db_issue" -1 false
        #
        #  If DB is missing, try to start the monitor
        #
        restart_monitor "$_vds_db_issue"
        log_it "$_vds_db_issue - monitor was restarted"

        [ -s "$f_sqlite_db" ] || {
            error_msg "$_vds_db_issue - DB could not be created - aborting"
        }
    elif [ -f "$f_monitor_suspended_no_clients" ]; then
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
    #  shellcheck disable=SC2086 # boolean - can't be quoted
    sql_current_loss $cfg_weighted_average

    # CAST seems to always round down...
    sqlite_err_handling "$sql" || {
        sqlite_exit_code="$?"

        _m="sqlite3 exited with: $sqlite_exit_code \n"
        _m="$_m  when retrieving current losses"
        error_msg "$_m"
    }
    current_loss=$(printf "%.0f" "$sqlite_result") # float -> int
}

get_prev_loss() {
    #
    #  public variables defined
    #   prev_loss
    #
    if [ -f "$f_previous_loss" ]; then
        read -r prev_loss <"$f_previous_loss"
    else
        prev_loss=0
    fi
}

set_prev_loss() {
    [ -z "$prev_loss" ] && get_prev_loss

    if [ "$current_loss" -gt 0 ]; then
        echo "$current_loss" >"$f_previous_loss"
    else
        rm -f "$f_previous_loss"
    fi

    # log loss changes
    $log_loss_changes && [ "$prev_loss" -ne "$current_loss" ] &&
        {
            if [ "$current_loss" -gt 0 ]; then
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
    [ -z "$prev_loss" ] && get_prev_loss

    if [ "$prev_loss" -ne "$current_loss" ]; then
        if [ "$current_loss" -gt "$prev_loss" ]; then
            result="+$current_loss"
        elif [ "$current_loss" -lt "$prev_loss" ]; then
            result="-$current_loss"
        fi
    fi
}

colorize_high_numbers() {
    #
    #  If loss is over trigger levels, display in appropriate color
    #
    _chn_number="$1" # numerical value to check
    _chn_item="$2"   # string that might get color

    if awk -v val="$_chn_number" -v trig_lvl="$cfg_level_crit" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        _chn_item="#[fg=$cfg_color_crit,bg=$cfg_color_bg]${_chn_item}#[default]"
    elif awk -v val="$_chn_number" -v trig_lvl="$cfg_level_alert" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        _chn_item="#[fg=$cfg_color_alert,bg=$cfg_color_bg]${_chn_item}#[default]"
    fi
    echo "$_chn_item"
}

display_history() {
    #
    #  Display history
    #
    #  Outside variables modified:
    #    s_log_result - will be used by main to display current losses
    #
    _dh_sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER)"
    sqlite_err_handling "$_dh_sql" || {
        error_msg "sqlite3[$?] when retrieving history" \
            -1 false
        return
    }
    _dh_avg_loss_raw="$sqlite_result"

    if [ "$_dh_avg_loss_raw" != "0" ]; then
        #
        #  If stats is over trigger levels, display in appropriate color
        #
        _dh_avg_loss="$(
            colorize_high_numbers "$_dh_avg_loss_raw" "$_dh_avg_loss_raw"
        )"
        result="${result}${cfg_hist_separator}${_dh_avg_loss}"
        s_log_result="$s_log_result   avg: $_dh_avg_loss_raw"
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
# [ "$1" != "hepp" ] && exit 0

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
log_prefix="dsp"

. "$D_TPL_BASE_PATH"/scripts/utils.sh

# do_not_run_active && exit 1
do_not_run_active && {
    log_it "do_not_run triggered abort"
    exit 1
}

log_loss_changes=false # set to false to reduce logging from this module
result=""              # indicating no losses

verify_db_status

get_current_loss

[ "$current_loss" -lt "$cfg_level_disp" ] && current_loss=0

s_log_result="loss: $current_loss" # might get altered by display_history

if [ "$current_loss" -gt 0 ]; then
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
