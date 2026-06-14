#!/bin/sh
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Reports current packet loss status for the plugin, suitable for tmux status bar
#

restart_monitor() {
    log_it "restarting monitor $1"
    $f_ctrl_monitor start || error_msg "ctrl_monitor gave error on start"
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
        [ -s "$f_sqlite_db" ] || {
            error_msg "$_vds_db_issue - DB could not be created - aborting"
        }
        log_it "$_vds_db_issue - monitor was restarted"
    elif [ -f "$f_monitor_suspended_no_clients" ]; then
        restart_monitor "- was suspended due to no clients"
    elif db_seems_inactive; then
        #
        #  If DB is over db_max_age_mins minutes old,
        #  assume the monitor is not running, so (re-)start it
        #
        restart_monitor "DB is over $db_max_age_mins minutes old"
    fi
}

get_current_loss() {
    #
    #  public variables defined
    #   current_loss_raw
    #

    # shellcheck disable=SC2154 # cfg_reactive defined via eval in utils.sh
    sql_current_loss "$cfg_reactive"
    current_loss_raw=$(printf "%.0f" "$sqlite_result") # float -> int
}

get_prev_loss() {
    #
    # Provides
    #   prev_loss
    #
    if [ -f "$f_previous_loss" ]; then
        read -r prev_loss <"$f_previous_loss" || {
            error_msg "get_prev_loss() - Failed to read $f_previous_loss"
        }
    else
        prev_loss=0
    fi
}

set_prev_loss() {
    [ -z "$prev_loss" ] && get_prev_loss # only needed to read this once

    echo "$current_loss_raw" >"$f_previous_loss" || {
        error_msg "set_prev_loss() - Failed to writ to $f_previous_loss"
    }
}

show_trend() {
    #
    # Prefix current_loss with:
    #   "+" if loss increased since previous sample
    #   "-" if loss decreased since previous sample
    #
    # Reads:
    #   current_loss_raw - current loss as float
    #
    # Writes:
    #   current_loss - current_loss_raw with trend prefix if changed
    #
    current_loss="$current_loss_raw" # default if no trend is displayed

    # shellcheck disable=SC2154 # cfg_display_trend defined via eval in utils.sh
    $cfg_display_trend || return

    [ -z "$prev_loss" ] && get_prev_loss # only needed to read this once

    if [ "$prev_loss" -ne "$current_loss_raw" ]; then
        if [ "$current_loss_raw" -gt "$prev_loss" ]; then
            current_loss="+$current_loss_raw"
        elif [ "$current_loss_raw" -lt "$prev_loss" ]; then
            current_loss="-$current_loss_raw"
        fi
    fi
    set_prev_loss # store this as previous for future calls
}

colorize_high_numbers() {
    #
    # Usage cases
    #   result=$(colorize_high_numbers value)
    #
    #   colorize_high_numbers value result

    # if _chn_variable is defined, this variable will be assigned the potentially
    # colorized value. Saving one fork,  Otherwise it will be echoed, for traditional assignment
    # colorized=$(colorize_high_numbers value)
    #  If loss is over trigger levels, display in appropriate color
    #
    _chn_value="${1:-0}"            # numerical value to check
    _chn_variable="${2:-undefined}" # if defined this variable resieves colorisation
    _chn_result="$_chn_value"       # potentially colorized value

    if awk -v val="$_chn_value" -v trig_lvl="$cfg_level_crit" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        _chn_result="#[fg=$cfg_color_crit,bg=$cfg_color_bg]${_chn_value}#[default]"
    elif awk -v val="$_chn_value" -v trig_lvl="$cfg_level_alert" \
        'BEGIN{exit !(val >= trig_lvl)}'; then
        _chn_result="#[fg=$cfg_color_alert,bg=$cfg_color_bg]${_chn_value}#[default]"
    fi
    if [ "$_chn_variable" != undefined ]; then
        # if variable name provided set it to _chn_result
        eval "$_chn_variable=\"\$_chn_result\""
    else
        echo "$_chn_result"
    fi
}

display_history() {
    #
    #  Include history in the display
    #  returns current and histoic average individually colorized
    #
    # Reads:
    #   current_loss - presentation format
    # Provides:
    #    result - result to be displayed displayed
    #
    _dh_sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER)"
    sqlite_err_handling "$_dh_sql" || {
        error_msg "sqlite3[$?] when retrieving historical losses"
    }
    _dh_avg_loss_raw="$sqlite_result"

    #
    #  If stats is over trigger levels, display in appropriate color
    #
    _dh_cur_loss=$(colorize_high_numbers "$current_loss")
    _dh_avg_loss=$(colorize_high_numbers "$_dh_avg_loss_raw")
    result="${_dh_cur_loss}${cfg_hist_separator}${_dh_avg_loss}"

    # fi
}

script_exit() {
    #
    #  wrap status in prefix/suffix if given and exit gracefully
    #
    status="$1"

    [ -n "$status" ] && echo "${cfg_prefix}${status}${cfg_suffix}"
    exit 0
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

result="" # indicating no losses

verify_db_status

get_current_loss                    # defines current_loss_raw
current_loss_float="$sqlite_result" # saved to only remove previous losses on actual 0

show_trend # updates current_loss with or without trend suffix

[ "$current_loss_raw" -lt "$cfg_level_disp" ] && {
    [ "$current_loss_float" = 0 ] && {
        # After a check with no losses, reset previous losses by deleting the file
        clear_previous_losses
    }
    script_exit
}

if $cfg_hist_avg_display; then
    display_history
else
    # Will colorize both current and historical values if relevant
    result=$(colorize_high_numbers "$current_loss")
fi

#
#  Display losses
#
script_exit "$result"
