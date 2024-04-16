#!/usr/bin/env bash
#  Directives for shellcheck directly after bang path are global
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.2.1 2022-09-15
#
#   This is the coordination script
#    - ensures the database is present and up to date
#    - sets parameters in the database
#    - ensures packet_loss_monitor is running
#    - binds  #{packet_loss} to check_packet_loss.sh
#

#
#  Functions only used here are kept here, in order to minimize overhead
#  for sourcing utils.sh in the other scripts.
#

do_interpolation() {
    local all_interpolated="$1"

    all_interpolated=${all_interpolated//$pkt_loss_interpolation/$pkt_loss_command}
    echo "$all_interpolated"
}

update_tmux_option() {
    local option="$1"
    local option_value
    local new_option_value

    option_value="$(get_tmux_option "$option")"
    new_option_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_option_value"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname -- "$(realpath -- "$0")")

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

#
#  Dependency check
#
if ! command -v sqlite3 >/dev/null 2>&1; then
    error_msg "Missing dependency sqlite3"
fi

#
#  stop any running monitor instances
#  create DB if needed
#  update triggers baesd on tmux plgin config
#  start monitoring
#
$scr_controler

#
#  Match tag with polling script
#
pkt_loss_interpolation="\#{packet_loss}"
pkt_loss_command="#($D_TPL_BASE_PATH/scripts/packet_loss.sh)"

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
