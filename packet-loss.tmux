#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   This is the coordination script
#    - ensures the database is present and up to date
#    - sets parameters in the database
#    - ensures packet_loss_monitor is running
#    - binds  #{packet_loss} to display_losses.sh
#

#
#  Functions only used here are kept here, in order to minimize overhead
#  for sourcing utils.sh in the other scripts.
#

set_tmux_option() {
    local sto_option="$1"
    local sto_value="$2"

    [[ -z "$sto_option" ]] && {
        error_msg "set_tmux_option() param 1 empty!" 1 true
    }
    [[ "$TMUX" = "" ]] && return # this is run standalone

    $TMUX_BIN set -g "$sto_option" "$sto_value"
}

update_tmux_option() {
    local option="$1"
    local option_value
    local new_option_value

    option_value="$(get_tmux_option "$option")"
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

do_interpolation() {
    local all_interpolated="$1"

    all_interpolated=${all_interpolated//$pkt_loss_interpolation/$pkt_loss_command}
    echo "$all_interpolated"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname -- "$(realpath "$0")")
log_prefix="plg" # plugin handler

use_param_cache=false # one-off just for this souring
#  shellcheck source=scripts/utils.sh
source "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  Ensure (potentially) outdated param cache is first removed
#  depending on other settings it will be re-created if needed
#
rm -f "$f_param_cache"

#
#  Dependency check
#
command -v sqlite3 >/dev/null 2>&1 || {
    error_msg "Missing dependency sqlite3" 1 true
}

#
#  stop any running monitor instances
#  create DB if needed
#  update triggers baesd on tmux plgin config
#  start monitoring
#
log_it #  if log is used, create a LF to better isolate init
log_it "starting monitor"
$scr_ctrl_monitor start

#
#  Match tag with polling script
#
pkt_loss_interpolation="\#{packet_loss}"
pkt_loss_command="#($scr_display_losses)"

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
log_it "packet-loss.tmux completed"
