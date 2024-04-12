#!/bin/sh
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.3.3 2022-06-10
#

restart_monitor() {
    log_it "restarting monitor"
    mkdir -p "$D_TPL_BASE_PATH/data" # ensure folder exists
    date >>"$db_restart_log"         # for now log actions
    "$D_TPL_BASE_PATH"/packet-loss.tmux stop
    "$D_TPL_BASE_PATH"/packet-loss.tmux
    sleep 1 # give the first check time to complete
}

#===============================================================
#
#   Main
#
#===============================================================

# script_start_time="$(date +%s)"

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

#
#  Prevent tmux from running it every couple of seconds,
#  convenient during debugging
#
# [ "$1" != "hepp" ] && exit 0

#
#  This is called once per active tmux session, so if multiple sessions
#  are used, this will be called multiple times in a row. Only check DB
#  once per tmux status bar update, in order to reduce expensive
#  DB calls.
#
# prev_check_time="$(get_tmux_option "@packet-loss_tmp_last_check" 0)"
# seconds_since_last_check="$((script_start_time - prev_check_time))"
# interval="$(tmux display -p "#{status-interval}")"
# set_tmux_option "@packet-loss_tmp_last_check" "$script_start_time"

#
#  Some sanity check, ensuring the monitor is running
#
if [ ! -e "$sqlite_db" ]; then
    log_it "DB missing"

    #
    #  If DB is missing, try to start the monitor
    #
    restart_monitor
    if [ ! -e "$sqlite_db" ]; then
        log_it "repeated fails DB missing"
        # still missing, something is failing
        error_msg "DB [$sqlite_db] not found, and monitor failed to restart!"
    fi
elif [ -n "$(find "$sqlite_db" -mmin +1)" ]; then
    log_it "DB is one minute old"
    #
    #  If DB is over a minute old,
    #  assume the monitor is not running, so (re-)start it
    #
    restart_monitor
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
    # shellcheck disable=SC2034
    sql_avg="SELECT avg(loss) FROM t_loss"
fi

sql="SELECT CAST(( $sql_avg ) AS INTEGER)"

# if [ "$seconds_since_last_check" -lt "$interval" ]; then
#     # This will echo last retrieved value
#     log_it "to soon, reporting cached value"
#     current_loss="$(get_tmux_option "@packet-loss_tmp_last_result" "0")"
# else
current_loss="$(sqlite3 "$sqlite_db" "$sql")"
# fi

result="" # indicating no losses

[ "$current_loss" -lt "$lvl_disp" ] && current_loss=0

if [ "$current_loss" -gt 0 ]; then
    if bool_param "$display_trend"; then
        #
        #  Calculate trend, ie change since last update
        #
        prev_loss="$(get_tmux_option "@packet-loss_tmp_last_value" 0)"
        if [ "$prev_loss" -ne "$current_loss" ]; then
            set_tmux_option @packet-loss_tmp_last_value "$current_loss"
        fi

        if [ "$current_loss" -gt "$prev_loss" ]; then
            loss_trend="+"
        elif [ "$current_loss" -lt "$prev_loss" ]; then
            loss_trend="-"
        else
            loss_trend=""
        fi
    else
        loss_trend=""
    fi

    #
    #  If loss over trigger levels, display in appropriate color
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
        if [ ! "$avg_loss" = "0" ]; then
            if awk -v val="$avg_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_crit,bg=$color_bg]$avg_loss#[default]"
            elif awk -v val="$avg_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_alert,bg=$color_bg]$avg_loss#[default]"
            fi
            result="${result}${hist_separator}${avg_loss}"
        fi
    fi

    result="${loss_prefix}${result}${loss_suffix}"

    #  typically comment out the next 3 lines unless you are debugging stuff
#    log_it "checker detected loss:$current_loss avg:$avg_loss]"
#else
#    log_it "checker detected no packet losses"
fi

set_tmux_option "@packet-loss_tmp_last_result" "$current_loss"
echo "$result"
