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

do_interpolation() {
    local all_interpolated="$1"

    all_interpolated=${all_interpolated//$pkt_loss_interpolation/$pkt_loss_command}
    echo "$all_interpolated"
}

set_tmux_option() {
    local sto_option="$1"
    local sto_value="$2"

    [[ -z "$sto_option" ]] && {
        error_msg "set_tmux_option() param 1 empty!"
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

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname -- "$(realpath "$0")")
log_prefix="plg" # plugin handler

#  shellcheck source=scripts/utils.sh
source "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  By printing a NL and date, its easier to keep separate runs apart
#
log_it
log_it "$(date)"

#  Ensure a fresh param_cache has been created during plugin init
$param_cache_written || {
    generate_param_cache
    get_config # to ensure some custom stuff like skip_logging is applied
}

#  Ensure it points to current tmux
get_tmux_pid >"$pidfile_tmux"

#
#  Dependency check
#
command -v sqlite3 >/dev/null 2>&1 || {
    error_msg "Missing dependency sqlite3"
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
log_it "$this_app - completed"
