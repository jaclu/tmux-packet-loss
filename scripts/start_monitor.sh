#!/bin/sh
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

#===============================================================
#
#   Main
#
#===============================================================

# shellcheck disable=SC1007
D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=/dev/null
. "$D_TPL_BASE_PATH/scripts/utils.sh"

# $monitor_process_scr stop
# shellcheck disable=SC2154
nohup "$monitor_process_scr" >/dev/null 2>&1 &
