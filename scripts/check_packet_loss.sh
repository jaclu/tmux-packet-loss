#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.0.5 2022-03-24
#

CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$CURRENT_DIR/utils.sh"

db="$(dirname -- "$CURRENT_DIR")/data/$sqlite_db"


if [ ! -e "$db" ]; then
    msg="ERROR: DB [$db] not found!"
    log_it "$msg"
    tmux display "$plugin_name $msg"
    exit 1
fi



# display last poll
# current_loss="$(sqlite3 "$db" "SELECT loss from packet_loss ORDER BY rowid DESC LIMIT 1")"

# display average over hist_size polls
current_loss="$(sqlite3 "$db" "SELECT round(avg(loss),1) from packet_loss")"

# log_it "raw loss [$current_loss]"


lvl_disp="$(get_tmux_option "@packet-loss_level_disp" "$default_lvl_display")"
# log_it "lvl_disp [$lvl_disp]"


if [ $(echo "$current_loss < $lvl_disp" | bc) -eq 1 ]; then
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
        color_bg="$(get_tmux_option "@packet-loss_color_bg" "$default_color_bg")"
        current_loss="#[fg=$color_crit,bg=$color_bg]$current_loss%#[default]"
    elif awk -v val="$current_loss" -v trig_lvl="$lvl_alert" 'BEGIN{exit !(val >= trig_lvl)}'; then
        color_alert="$(get_tmux_option "@packet-loss_color_alert" "$default_color_alert")"
        color_bg="$(get_tmux_option "@packet-loss_color_bg" "$default_color_bg")"
        current_loss="#[fg=$color_alert,bg=$color_bg]$current_loss%#[default]"
    else
        current_loss="$current_loss%"
    fi

    loss_prefix="$(get_tmux_option "@packet-loss_prefix" "$default_prefix")"
    # log_it "loss_prefix [$loss_prefix]"
    loss_suffix="$(get_tmux_option "@packet-loss_suffix" "$default_suffix")"
    # log_it "loss_suffix [$loss_suffix]"
    current_loss="$loss_prefix$current_loss$loss_suffix"
fi

log_it "reported loss [$current_loss]"
echo "$current_loss"
