#!/bin/sh
# shellcheck disable=SC2154
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.3.0 2022-06-10
#

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$CURRENT_DIR/utils.sh"

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"

log_file_base="/tmp/packet-loss"
log_file_db_missing="${log_file_base}-missing.log"
log_file_db_old="${log_file_base}-old.log"

restart_monitor() {
    parrent_dir="$(dirname "$CURRENT_DIR")"
    "$parrent_dir/packet-loss.tmux" stop
    "$parrent_dir/packet-loss.tmux"
    sleep 1  # give the first check time to complete
}


#
#  Some sanity check, ensuring the monitor is running
#
if [ ! -e "$db" ]; then
    #
    #  If DB is missing, try to start the monitor
    #
    date >> "$log_file_db_missing" # for now log actions
    restart_monitor
    if [ ! -e "$db" ]; then
        # still missing, something is failing
        error_msg "DB [$db] not found!" 1
    fi
fi


if [ -n "$(find "$db" -mmin +1)" ]; then
    #
    #  If DB is over a minute old,
    #  assume the monitor is not running, so start it
    #
    date >> "$log_file_db_old" # for now log actions
    restart_monitor
fi



if bool_param "$(get_tmux_option "@packet-loss_weighted_average" "$default_weighted_average")"; then
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
    sql="max( \
      (select loss from packet_loss Order By Rowid desc limit 1), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 2)), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 3)), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 4)), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 5)), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 6)), \
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 7)), \
      (select avg(loss) from packet_loss) \
     )"
else
    # shellcheck disable=SC2034
    # weighted_average=0
    sql="(select avg(loss) from packet_loss)"
fi
# log_it "weighted_average [$weighted_average]"
# unset weighted_average


current_loss="$(sqlite3 "$db" "select round($sql,1)")"
# log_it "raw loss [$current_loss]"


lvl_disp="$(get_tmux_option "@packet-loss_level_disp" "$default_lvl_display")"
# log_it "lvl_disp [$lvl_disp]"


if [ "$(echo "$current_loss < $lvl_disp" | bc)" -eq 1 ]; then
    # log_it "$current_loss is below threshold $lvl_disp"
    current_loss="" # no output if bellow threshold
fi

#
#  To minimize CPU hogging, only fetch options when needed
#
if [ -n "$current_loss" ]; then
    lvl_crit="$(get_tmux_option "@packet-loss_level_crit" "$default_lvl_crit")"
    # log_it "lvl_crit [$lvl_crit]"

    lvl_alert="$(get_tmux_option "@packet-loss_level_alert" "$default_lvl_alert")"
    # log_it "lvl_alert [$lvl_alert]"
    #
    #  If loss over trigger levels, display in appropriate color
    #
    if awk -v val="$current_loss" -v trig_lvl="$lvl_crit" 'BEGIN{exit !(val >= trig_lvl)}'; then
        color_crit="$(get_tmux_option "@packet-loss_color_crit" "$default_color_crit")"
        # log_it "color_crit [$color_crit]"
        color_bg="$(get_tmux_option "@packet-loss_color_bg" "$default_color_bg")"
        # log_it "color_bg [$color_bg]"
        current_loss="#[fg=$color_crit,bg=$color_bg]$current_loss%#[default]"
    elif awk -v val="$current_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
        color_alert="$(get_tmux_option "@packet-loss_color_alert" "$default_color_alert")"
        # log_it "color_alert [$color_alert]"
        color_bg="$(get_tmux_option "@packet-loss_color_bg" "$default_color_bg")"
        # log_it "color_bg [$color_bg]"
        current_loss="#[fg=$color_alert,bg=$color_bg]$current_loss%#[default]"
    else
        current_loss="$current_loss%"
    fi

    loss_prefix="$(get_tmux_option "@packet-loss_prefix" "$default_prefix")"
    # log_it "loss_prefix [$loss_prefix]"

    loss_suffix="$(get_tmux_option "@packet-loss_suffix" "$default_suffix")"
    # log_it "loss_suffix [$loss_suffix]"

    current_loss="$loss_prefix$current_loss$loss_suffix"
    log_it "reported loss [$current_loss]"
fi

echo "$current_loss"
