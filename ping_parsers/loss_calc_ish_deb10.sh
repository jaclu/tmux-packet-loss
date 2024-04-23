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

#
#  with most pings ' icmp_seq=' can be used to identify a reply
#  Obviously busybox uses ' seq=' ...
#

#  shellcheck disable=SC2126
recieved_packets="$(echo "$ping_output" | grep -v DUP | grep "seq=" |
    grep "$cfg_ping_host" | wc -l)"

#
#  Sometimes this gets extra replies fom 8.8.8.8
#  If 8.8.4.4 is pinged filtering on $cfg_ping_host gets rid of them,
#  if 8.8.8.8 is the pinghost this will signal results over 100
#
#  Did a quick fix, but will leave it commented out for now to gather
#  some more stats on how often this happens.
#
# [[ "$recieved_packets" -gt "$cfg_ping_count" ]] && {
#     recieved_packets="$cfg_ping_count"
# }


#
#  bc rounds 33.3333 to 33.4 to work arround this, bc uses two digits
#  printf rounds it down to one
#
percent_loss="$(echo "scale=2;
    100 - 100 * $recieved_packets / $cfg_ping_count" | bc | 
    awk '{printf "%.1f", $0}')"

echo "$percent_loss"
