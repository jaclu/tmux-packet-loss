#!/bin/sh
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
#    - binds  #{packet_loss} to display-losses.sh
#

#
#  Functions only used here are kept here, in order to minimize overhead
#  for sourcing utils.sh in the other scripts.
#

do_interpolation() {
    # printf '%s\n' "$1" | sed "s|$(printf '%s' "$pkt_loss_interpolation" | \
    #     sed 's/[&/\]/\\&/g')|$(printf '%s' "$pkt_loss_command" | sed 's/[&/\]/\\&/g')|g"
    _di_s=$1
    #
    #  Match tag with polling script, do this after monitor is started,
    #  to avoid getting failed script warnings in status bar
    #
    pkt_loss_interpolation="\#{packet_loss}"
    pkt_loss_command="#($f_display_losses)"

    echo "$_di_s" | sed "s|$pkt_loss_interpolation|$pkt_loss_command|g"
}

set_tmux_option() {
    _sto_option="$1"
    _sto_value="$2"

    [ -z "$_sto_option" ] && {
        error_msg "set_tmux_option() param 1 empty!"
    }
    [ "$TMUX" = "" ] && {
        echo "No tmux session detected, unable to update status line"
        return
    }
    $TMUX_BIN set -g "$_sto_option" "$_sto_value"
}

update_tmux_option() {
    _uto_option="$1"
    _uto_value="$(get_tmux_option "$_uto_option")"
    _uto_new_value="$(do_interpolation "$_uto_value")"
    set_tmux_option "$_uto_option" "$_uto_new_value"
}

do_not_run_clear() {
    # Clear state
    rm -f "$f_do_not_run"
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH="$(dirname -- "$(realpath -- "$0")")"
log_prefix="plg" # plugin handler

. "$D_TPL_BASE_PATH"/scripts/utils.sh

log_it "-----   $current_script   -----"

. "$D_TPL_BASE_PATH"/scripts/tmux-plugin-tools.sh
# Override tmux-plugin-tools log routine to use ours
tpt_log_it() {
    log_it "$@"
}

tpt_dependency_check "sqlite3" || {
    do_not_run_create "Failed dependencies: $tpt_missing_dependencies"
    log_it "Aborting plugin init - dependency fail: $tpt_missing_dependencies"
    exit 1
}

do_not_run_clear      # in case it was set previously
clear_previous_losses # remove if presssent

#  Ensure a fresh param_cache has been created during plugin init
$param_cache_written || {
    generate_param_cache
    get_config # to ensure some custom stuff like skip_logging is applied
}

#  Ensure it points to current tmux
get_tmux_pid >"$pidfile_tmux" # helper for show-settings.sh

#
#  Start monitor
#
log_it "starting monitor"
$f_ctrl_monitor start

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
log_it "$current_script - completed"
