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
    parrent_dir="$(dirname "$CURRENT_DIR")"
    "$parrent_dir/packet-loss.tmux" stop
    "$parrent_dir/packet-loss.tmux"
    sleep 1 # give the first check time to complete
}

#===============================================================
#
#   Main
#
#===============================================================

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"

get_settings

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"

#
#  This is called once per active tmux session, so if multiple sessions
#  are used, this will be called multiple times in a row. Only check DB
#  once per tmux status bar update, in order to reduce expensive
#  DB calls.
#
prev_check_time="$(get_tmux_option "@packet-loss_tmp_last_check" 0)"
script_start_time="$(date +%s)"
seconds_since_last_check="$((script_start_time - prev_check_time))"
interval="$(tmux display -p "#{status-interval}")"
if [ "$seconds_since_last_check" -lt "$interval" ]; then
    # This will echo last retrieved value
    get_tmux_option "@packet-loss_tmp_last_result" ""
    # log_it "to soon, reporting cached value"
    exit 0
fi
set_tmux_option "@packet-loss_tmp_last_check" "$script_start_time"

#
#  Some sanity check, ensuring the monitor is running
#
if [ ! -e "$db" ]; then
    log_it "DB missing"

    #
    #  If DB is missing, try to start the monitor
    #
    restart_monitor
    if [ ! -e "$db" ]; then
        log_it "repeated fails DB missing"
        # still missing, something is failing
        error_msg "DB [$db] not found, and monitor failed to restart!" 1
    fi
fi

if [ -n "$(find "$db" -mmin +1)" ]; then
    log_it "DB is one minute old"
    #
    #  If DB is over a minute old,
    #  assume the monitor is not running, so start it
    #
    date >>"$log_file_db_old" # for now log actions
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
    #    avg of all
    #
    sql1="max( \
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
    # weighted_average=0

    # shellcheck disable=SC2034
    sql1="(SELECT avg(loss) FROM t_loss)"
fi

sql="SELECT CAST(($sql1) + .499 AS INTEGER)"
current_loss="$(sqlite3 "$db" "$sql")"

if [ "$(echo "$current_loss < $lvl_disp" | bc)" -eq 1 ]; then
    current_loss="" # no output if bellow threshold
fi

if [ -n "$current_loss" ]; then
    if bool_param "$display_trend"; then
        #
        #  Calculate trend, ie change since last update
        #
        prev_loss="$(get_tmux_option "@packet-loss_tmp_last_value" 0)"
        if [ "$prev_loss" -ne "$current_loss" ]; then
            set_tmux_option @packet-loss_tmp_last_value "$current_loss"
        fi

        if [ "$current_loss" -gt "$prev_loss" ]; then
            loss_trend="^"
        elif [ "$current_loss" -lt "$prev_loss" ]; then
            loss_trend="v"
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
        current_loss="#[fg=$color_crit,bg=$color_bg]$loss_trend$current_loss#[default]"
    elif awk -v val="$current_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
        current_loss="#[fg=$color_alert,bg=$color_bg]$loss_trend$current_loss#[default]"
    else
        current_loss="$loss_trend$current_loss"
    fi

    #
    #  If history is requested, include it in display
    #
    if bool_param "$hist_avg_display"; then
        sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER);"
        avg_loss="$(sqlite3 "$db" "$sql")"
        if [ ! "$avg_loss" = "0" ]; then
            if awk -v val="$avg_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_crit,bg=$color_bg]$avg_loss#[default]"
            elif awk -v val="$avg_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
                avg_loss="#[fg=$color_alert,bg=$color_bg]$avg_loss#[default]"
            fi
            current_loss="${current_loss}${hist_separator}${avg_loss}"
        fi
    fi

    current_loss="$loss_prefix$current_loss$loss_suffix"
    log_it "reported loss [$current_loss]"
else
    log_it "No packet loss"
fi

set_tmux_option "@packet-loss_tmp_last_result" "$current_loss"
echo "$current_loss"
