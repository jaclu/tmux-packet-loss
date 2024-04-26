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
#  since we have to filter out any 8.8.8.8 results
#  this ping parser can not use ping host 8.8.8.8!
#
#  Here we instead count the number of correct replies and do the
#  math ourself
#

#
#  sourcing utils.sh is needed, scine This one needs to use some
#  config variables:
#    cfg_ping_host $recieved_packets  $cfg_ping_count
#
D_TPL_BASE_PATH=$(dirname "$(dirname "$(dirname -- "$(realpath "$0")")")")
log_prefix="png"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

[[ "$cfg_ping_host" = "8.8.8.8" ]] && {
    this_app="$(basename "$0")"
    msg="$this_app cant use 8.8.8.8 as ping host"
    if [[ -n "$log_file" ]]; then
        log_it "$msg"
    else
        error_msg "$msg" 1
    fi
}

if [[ -n "$1" ]]; then
    ping_output="$1"
else
    # Read input from stdin
    ping_output=$(cat)
fi

#
#  with most pings ' icmp_seq=' can be used to identify a reply
#  Obviously busybox uses ' seq=' ...
#

#  shellcheck disable=SC2126
recieved_packets="$(echo "$ping_output" | grep -v DUP | grep "seq=" |
    grep "$cfg_ping_host" | wc -l)"

#
#  Sometimes this gets extra replies
#  Did a quick fix, but will leave it commented out for now to gather
#  some more stats on how often this happens.
#
# [[ "$recieved_packets" -gt "$cfg_ping_count" ]] && {
#     recieved_packets="$cfg_ping_count"
# }

#
#  bc rounds 33.3333 to 33.4 to work arround this, bc uses three digits
#  in order to give the printf better source data as it rounds it down to one
#
echo "scale=3; 100 - 100 * $recieved_packets / $cfg_ping_count" | bc |
    awk '{printf "%.1f", $0}'
