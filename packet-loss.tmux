#!/usr/bin/env bash
# shellcheck disable=SC2154
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

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    local action="$1"
    local tmux_vers
    local hook_name

    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"
    log_it "hook_handler($action) tmux vers: $tmux_vers"

    # needed to be able to handle versions like 3.2a
    #  shellcheck source=/dev/null
    . scripts/adv_vers_compare.sh

    if adv_vers_compare "$tmux_vers" ">=" "3.0"; then
        hook_name="session-closed[$hook_idx]"
    elif adv_vers_compare "$tmux_vers" ">=" "2.4"; then
        hook_name="session-closed"
    else
        error_msg "WARNING: previous to tmux 2.4 session-closed hook is " \
            "not available, so can not shut down monitor process when " \
            "tmux exits!" 0
    fi

    if [[ -n "$hook_name" ]]; then
        if [[ "$action" = "set" ]]; then
            $TMUX_BIN set-hook -g "$hook_name" "run $no_sessions_shutdown_scr"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [[ "$action" = "clear" ]]; then
            $TMUX_BIN set-hook -ug "$hook_name" >/dev/null
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!"
        fi
    fi
}

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

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname -- "$(realpath -- "$0")")

#  shellcheck source=/dev/null
. scripts/utils.sh

#
#  Match tag with polling script
#
pkt_loss_interpolation="\#{packet_loss}"
pkt_loss_command="#($D_TPL_BASE_PATH/scripts/check_packet_loss.sh)"

log_it "running $0"
#
#  Dependency check
#
if ! command -v sqlite3 >/dev/null 2>&1; then
    error_msg "Missing dependency sqlite3"
fi

#
#  By printing some empty lines its easier to keep separate runs apart
#
# log_it
# log_it
# show_settings

# stop any running instances
$monitor_process_scr stop

hook_handler clear

case "$1" in

"start" | "") ;; # continue the startup

"stop")
    exit 0
    ;;

*) error_msg "Valid params: None or stop - got [$1]" ;;

esac

#
#  Starting a fresh monitor
#
nohup "$monitor_process_scr" >/dev/null 2>&1 &
log_it "Started background process: $monitor_process_scr"

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler set

#
#  Activate #{packet_loss} tag if used
#
update_tmux_option "status-left"
update_tmux_option "status-right"
