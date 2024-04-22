#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  This is a weird one, sometimes gives all kinds of weird output
#  often negative loss numbers and sometimes gives replies
#  for other hosts - (def gw?)
#  and often replies tagged with DUP
#
#  Here we instead count the number of correct replies and do the
#  math ourself
#

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="png"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"


# Read input from stdin
ping_output=$(cat)

#  shellcheck disable=SC2126
recieved_packets="$(echo "$ping_output" | grep -v DUP | grep "icmp_seq=" |
    grep "$cfg_ping_host" | wc -l)"

#
#  bc rounds 33.3 to 33.4  to solve this let
#  bc use two digits and then round it to one with printf
#
percent_loss="$(echo "scale=2;
    100 - 100 * $recieved_packets / $cfg_ping_count" | bc | 
    awk '{printf "%.1f", $0}')"

echo "$percent_loss"
