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

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"

restart_monitor() {
    log_it "restarting monitor"
    parrent_dir="$(dirname "$CURRENT_DIR")"
    "$parrent_dir/packet-loss.tmux" stop
    "$parrent_dir/packet-loss.tmux"
    sleep 1 # give the first check time to complete
}

get_settings

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"

log_file_base="/tmp/packet-loss"
log_file_db_missing="${log_file_base}-missing.log"
log_file_db_old="${log_file_base}-old.log"

#
#  Some sanity check, ensuring the monitor is running
#
if [ ! -e "$db" ]; then
    log_it "DB missing"

    #
    #  If DB is missing, try to start the monitor
    #
    date >>"$log_file_db_missing" # for now log actions
    restart_monitor
    if [ ! -e "$db" ]; then
        log_it "repeated fails DB missing"
        # still missing, something is failing
        error_msg "DB [$db] not found!" 1
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
      (SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 1), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 2)), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 3)), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 4)), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 5)), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 6)), \
      (SELECT avg(loss) FROM(SELECT loss FROM packet_loss ORDER BY ROWID DESC limit 7)), \
      (SELECT avg(loss) FROM packet_loss) \
     )"
else
    # weighted_average=0

    # shellcheck disable=SC2034
    sql1="(SELECT avg(loss) FROM packet_loss)"
fi

sql="SELECT CAST(($sql1) + .499 AS INTEGER)"
current_loss="$(sqlite3 "$db" "$sql")"
# log_it "raw loss [$current_loss]"

if [ "$(echo "$current_loss < $lvl_disp" | bc)" -eq 1 ]; then
    # log_it "$current_loss is below threshold $lvl_disp"
    current_loss="" # no output if bellow threshold
fi

#
#  To minimize CPU hogging, only fetch options when needed
#
if [ -n "$current_loss" ]; then
    #
    #  If loss over trigger levels, display in appropriate color
    #
    if awk -v val="$current_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
        current_loss="#[fg=$color_crit,bg=$color_bg]$current_loss#[default]"
    elif awk -v val="$current_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
        current_loss="#[fg=$color_alert,bg=$color_bg]$current_loss#[default]"
    fi

    if bool_param "$hist_avg_display"; then
        sql="SELECT CAST((SELECT AVG(loss) FROM statistics) + .499 AS INTEGER);"
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

fi

echo "$current_loss"
