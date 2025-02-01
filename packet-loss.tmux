#!/usr/bin/env bash
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
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

D_TPL_BASE_PATH="$(dirname -- "$(realpath -- "$0")")"
log_prefix="plg" # plugin handler

. "$D_TPL_BASE_PATH"/scripts/utils.sh

#
#  By printing a NL, its easier to keep separate runs apart
#
log_it

"$D_TPL_BASE_PATH"/scripts/tmux-plugin-tools.sh dependency-check "sqlite32" || {
    # shellcheck disable=SC2154
    do_not_run_create "Failed dependencies: $tpt_missing_dependencies"
    log_it "Aborting plugin init - dependency fail: $tpt_missing_dependencies"
    exit 1
}
do_not_run_clear # in case it was set previously

#  Ensure a fresh param_cache has been created during plugin init
$param_cache_written || {
    generate_param_cache
    get_config # to ensure some custom stuff like skip_logging is applied
}

#  Ensure it points to current tmux
get_tmux_pid >"$pidfile_tmux" # helper for show_settings.sh

#
#  Start monitor
#
log_it "starting monitor"
$scr_ctrl_monitor start

#
#  Match tag with polling script, do this after monitor is started,
#  to avoid getting failed script warnings in status bar
#
pkt_loss_interpolation="\#{packet_loss}"
pkt_loss_command="#($scr_display_losses)"

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
log_it "$current_script - completed"
