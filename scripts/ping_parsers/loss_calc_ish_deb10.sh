#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
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
#  Either give file to read as a param, or pipe ping output into this
#  If read is first param ping settings are extracted from ping output
#

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(dirname -- "$(realpath -- "$0")")")")"
log_prefix="png-i"
. "$D_TPL_BASE_PATH"/scripts/utils.sh

if [ "$1" = "read" ]; then
    #  When testing, read settings from output to match sample
    shift
    extract_settings=true
else
    extract_settings=false
fi

if [ -n "$1" ]; then
    ping_output="$(cat "$1")"
else
    # Read input from stdin
    ping_output="$(cat)"
fi

$extract_settings && {
    cfg_ping_host="$(echo "$ping_output" | grep "^PING" | cut -d' ' -f 2)"
    cfg_ping_count="$(echo "$ping_output" | grep "packets transmitted" |
        cut -d' ' -f 1)"
    echo "Extracted"
    echo "cfg_ping_host:  $cfg_ping_host"
    echo "cfg_ping_count: $cfg_ping_count"
    echo
}

#
#  with most pings ' icmp_seq=' can be used to identify a reply
#  Obviously busybox uses ' seq=' ...
#
#  shellcheck disable=SC2126
result="$(echo "$ping_output" | grep -v DUP | grep "seq=" |
    grep "$cfg_ping_host" | wc -l)"
#  Trims white space
received_packets="${result#"${result%%[![:space:]*}"}"

if [ "$received_packets" -gt "$cfg_ping_count" ]; then
    #
    #  on iSH Deb10 ping sometimes reports more non DUP pings received
    #  than was actually sent, assume no losses in such cases
    #
    # log_it "got $received_packets pkts, expected $cfg_ping_count"
    save_ping_issue "$ping_output"
    echo 0.0
else
    #
    #  bc rounds 33.3333 to 33.4 to work around this, bc uses three digits
    #  in order to give the printf better source data as it rounds it down
    #  to one
    #
    echo "scale=3; 100 - 100 * $received_packets / $cfg_ping_count" |
        bc | awk '{printf "%.1f\n", $0}'
fi
