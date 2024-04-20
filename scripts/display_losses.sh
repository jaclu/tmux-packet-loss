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

    [[ -n "$status" ]] && {
        # log_it "should not have pre/suf  $status"
        echo "${cfg_prefix}${status}${cfg_suffix}"
    }
    exit 0
}

restart_monitor() {
    log_it "restarting monitor"
    date >>"$db_restart_log" # log current time

    $scr_controler
}

verify_db_status() {
    #
    #  Some sanity check, ensuring the monitor is running
    #
    if [[ ! -e "$sqlite_db" ]]; then
        log_it "DB missing"

        #
        #  If DB is missing, try to start the monitor
        #
        restart_monitor
        log_it "db missing restart is done"

        [[ -e "$sqlite_db" ]] || {
            script_exit "DB missing"
            #error_msg "DB not found, and monitor failed to restart!"
        }
    elif [[ -n "$(find "$sqlite_db" -mmin +1)" ]]; then
        log_it "DB is over one minute old"
        #
        #  If DB is over a minute old,
        #  assume the monitor is not running, so (re-)start it
        #
        restart_monitor
        log_it "no db updates restart is done"
        script_exit "DB old"
    fi
}

check_cache_age() {
    #
    #  This is called once per active tmux session, so if multiple sessions
    #  are used, this will be called multiple times in a row.
    #  Using the cache feature makes generating a new result only happen
    #  once per status bar update.
    #
    local prev_check_time
    local interval
    local age_last_check

    prev_check_time="$(get_tmux_option "$opt_last_check" 0)"
    interval="$($TMUX_BIN display -p "#{status-interval}")"
    age_last_check="$(printf "%.0f" "$(echo "$t_start - $prev_check_time" | bc)")"

    # make it slightly less likely to return cached data
    age_last_check=$((age_last_check + 1))
    [[ "$age_last_check" -lt "$interval" ]] && {
        log_it "cache age: ${age_last_check}"
        get_tmux_option "$opt_last_result" ""
        exit 0
    }
    display_time_elapsed "$t_start" "check_cache_age"
}

get_current_loss() {
    local sql

    if param_as_bool "$cfg_weighted_average"; then
        #
        #  To give loss a declining history weighting, it is displayed as the largest of:
        #    last value
        #    avg of last 2
        #    avg of last 3
        #    avg of last 4
        #    ...
        #    avg of last minute
        #
        sql="max( \
        (SELECT loss FROM t_loss ORDER BY ROWID DESC limit 1), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 2)), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 3)), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 4)), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 5)), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 6)), \
        (SELECT avg(loss) FROM(SELECT loss FROM t_loss ORDER BY ROWID DESC limit 7)), \
        (SELECT avg(loss) FROM t_loss) \
        )"
    else
        sql="SELECT avg(loss) FROM t_loss"
    fi

    sql="SELECT CAST(( $sql ) AS INTEGER)"
    sqlite3 "$sqlite_db" "$sql"
    display_time_elapsed "$t_start" "get_current_loss"
}

show_trend() {
    local prev_loss

    prev_loss="$(get_tmux_option "$opt_last_value" 0)"
    if [[ "$prev_loss" -ne "$current_loss" ]]; then
        set_tmux_option "$opt_last_value" "$current_loss"
        if [[ "$current_loss" -gt "$prev_loss" ]]; then
            # loss_trend="+"
            result="+$current_loss"
        elif [[ "$current_loss" -lt "$prev_loss" ]]; then
            # loss_trend="-"
            result="-$current_loss"
        fi
    fi
    display_time_elapsed "$t_start" "show_trend"
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
    display_time_elapsed "$t_start" "colorize_high_numbers"
}

display_history() {
    #
    #  Display history
    #
    #  Exposed variables:
    #    s_log_msg - will be used by main to display current losses
    #
    local sql
    local avg_loss_raw
    local avg_loss

    sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER)"
    avg_loss_raw="$(sqlite3 "$sqlite_db" "$sql")"
    if [[ "$avg_loss_raw" != "0" ]]; then
        #
        #  If stats is over trigger levels, display in appropriate color
        #
        avg_loss="$(colorize_high_numbers "$avg_loss_raw" "$avg_loss_raw")"
        echo "${cfg_hist_separator}${avg_loss}"
        s_log_msg="$s_log_msg   avg: $avg_loss_raw"
    fi
    display_time_elapsed "$t_start" "display_history"
}

#===============================================================
#
#   Main
#
#===============================================================
t_start=$(date +%s.%N)

#
#  Prevent tmux from running it every couple of seconds,
#  convenient during debugging
#
# [[ "$1" != "hepp" ]] && exit 0

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")
log_prefix="chk"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"
display_time_elapsed "$t_start" "sourced utils"

# log_ppid="true"

#  for caching
opt_last_check="@packet-loss_tmp_last_check"
opt_last_result="@packet-loss_tmp_last_result"

#
#  Used to indicate trends, unlike opt_last_result above,
#  this only uses the numerical loss value.
#
opt_last_value="@packet-loss_tmp_last_value"

display_time_elapsed "$t_start" "script initialized"

verify_db_status

$cache_db_polls && check_cache_age

current_loss="$(get_current_loss)"

$cache_db_polls && set_tmux_option "$opt_last_check" "$t_start"

result="" # indicating no losses
[[ "$current_loss" -lt "$cfg_level_disp" ]] && current_loss=0

if [[ "$current_loss" -gt 0 ]]; then
    result="$current_loss"
    s_log_msg="loss: $current_loss"

    #
    #  Check trend, ie change since last update
    #
    param_as_bool "$cfg_display_trend" && show_trend

    result="$(colorize_high_numbers "$current_loss" "$result")"

    param_as_bool "$cfg_hist_avg_display" && result="${result}$(display_history)"

    #
    #  Set prefix & suffix to result and report to status bar
    #
    result="${cfg_prefix}${result}${cfg_suffix}"
    echo "$result"

    #
    #  comment out the next 3 lines unless you are debugging stuff
    #

#    log_it "$s_log_msg"
# else
#     log_it "no packet losses"

fi

$cache_db_polls && set_tmux_option "$opt_last_result" "$result"
display_time_elapsed "$t_start" "display_losses.sh"
sleep 2
log_it "$$ exiting"
