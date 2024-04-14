#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Reports current packet loss status for the plugin
#

restart_monitor() {
    log_it "restarting monitor"
    date >>"$db_restart_log" # log current time

    $scr_controler
}

script_exit() {
    # report status and exit gracefully
    local status="$1"

    log_it "result [$status]"
    [[ -n "$status" ]] && echo "${loss_prefix}${status}${loss_suffix}"
    exit 0
}

#===============================================================
#
#   Main
#
#===============================================================

#  Prevent tmux from running it every couple of seconds,
#  convenient during debugging
#
# [[ "$1" != "hepp" ]] && exit 0

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

# shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

log_prefix="chk"

# used to indicate trends
opt_last_value="@packet-loss_tmp_last_value"

# for caching
opt_last_check="@packet-loss_tmp_last_check"
opt_last_result="@packet-loss_tmp_last_result"

#
#  This is called once per active tmux session, so if multiple sessions
#  are used, this will be called multiple times in a row.
#  Using the cache feature makes generating a new result only happen
#  once per status bar update.
#
$cache_db_polls && {
    prev_check_time="$(get_tmux_option "$opt_last_check" 0)"
    t_now="$(date +%s)"
    interval="$($TMUX_BIN display -p "#{status-interval}")"
    age_last_check="$((t_now - prev_check_time))"

    # make it slightly less likely to return cached data
    age_last_check=$((age_last_check + 1))
    [[ "$age_last_check" -lt "$interval" ]] && {
        log_it "using cache age last check: $age_last_check"
        script_exit "$(get_tmux_option "$opt_last_result" "")"
    }
}

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
    log_it "DB is over one minute old - restarting monitor"
    #
    #  If DB is over a minute old,
    #  assume the monitor is not running, so (re-)start it
    #
    restart_monitor
    log_it "no db updates restart is done"
    script_exit "DB old"
fi

if bool_param "$is_weighted_avg"; then
    # weighted_average=1
    #
    #  To give loss a declining history weighting, it is displayed as the largest of:
    #    last value
    #    avg of last 2
    #    avg of last 3
    #    avg of last 4
    #    ...
    #    avg of last minute
    #
    sql_avg="max( \
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
    sql_avg="SELECT avg(loss) FROM t_loss"
fi

sql="SELECT CAST(( $sql_avg ) AS INTEGER)"
current_loss="$(sqlite3 "$sqlite_db" "$sql")"

$cache_db_polls && set_tmux_option "$opt_last_check" "$(date +%s)"

result="" # indicating no losses
[[ "$current_loss" -lt "$lvl_disp" ]] && current_loss=0

if [[ "$current_loss" -gt 0 ]]; then
    if bool_param "$display_trend"; then
        #
        #  Calculate trend, ie change since last update
        #
        prev_loss="$(get_tmux_option "$opt_last_value" 0)"
        if [[ "$prev_loss" -ne "$current_loss" ]]; then
            set_tmux_option "$opt_last_value" "$current_loss"
        fi

        if [[ "$current_loss" -gt "$prev_loss" ]]; then
            loss_trend="+"
        elif [[ "$current_loss" -lt "$prev_loss" ]]; then
            loss_trend="-"
        else
            loss_trend=""
        fi
    else
        loss_trend=""
    fi

    #
    #  If loss is over trigger levels, display in appropriate color
    #
    if awk -v val="$current_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
        result="#[fg=$color_crit,bg=$color_bg]$loss_trend$current_loss#[default]"
    elif awk -v val="$current_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
        result="#[fg=$color_alert,bg=$color_bg]$loss_trend$current_loss#[default]"
    else
        result="$loss_trend$current_loss"
    fi

    #
    #  If history is requested, include it in display
    #
    if bool_param "$hist_avg_display"; then
        sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER);"
        avg_loss="$(sqlite3 "$sqlite_db" "$sql")"
        if [[ ! "$avg_loss" = "0" ]]; then
            if awk -v val="$avg_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_crit,bg=$color_bg]$avg_loss#[default]"
            elif awk -v val="$avg_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_alert,bg=$color_bg]$avg_loss#[default]"
            fi
            result="${result}${hist_separator}${avg_loss}"
        fi
    fi
    #  typically comment out the next 3 lines unless you are debugging stuff
#     log_it "loss: $current_loss  avg: $avg_loss"
# else
#     log_it "no packet losses"
fi

$cache_db_polls && set_tmux_option "$opt_last_result" "$result"
script_exit "$result"
