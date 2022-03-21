#!/bin/sh
# keep
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$CURRENT_DIR/utils.sh"

db="$CURRENT_DIR/$sqlite_db"


# last poll
#current_loss="$(sqlite3 "$db" "SELECT loss from packet_loss ORDER BY rowid DESC LIMIT 1")"

# average over hist_size polls
current_loss="$(sqlite3 "$db" "SELECT round(avg(loss),1) from packet_loss")"

# log_it "raw loss [$current_loss]"
[ "$current_loss" = "0.0" ] && current_loss="" # no output if zero loss


#
#  To minimize cpu hogging, only fetch options when needed
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
    current_loss="$loss_prefix$current_loss"
fi

log_it "[$(date)] reported loss [$current_loss]"
echo "$current_loss"




