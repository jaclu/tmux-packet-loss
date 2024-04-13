#!/bin/sh
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Displays current settings for plugin
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

log_prefix="show"
log_file="/dev/stdout"
show_settings
