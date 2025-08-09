#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Default ping parser
#
#  Either give file to read as a param, or pipe ping output into this
#

D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(dirname -- "$(realpath -- "$0")")")")"
log_prefix="png"
. "$D_TPL_BASE_PATH"/scripts/utils.sh

if [ -n "$1" ]; then
    ping_output="$(cat "$1")"
else
    # Read input from stdin
    ping_output="$(cat)"
fi

#
#  We can't rely on the absolute position of the %loss,
#  since sometimes it is prepended with stuff like: "+1 duplicates,"
#
#  To handle this we search for "packet loss" and use the word
#  just before it.
#
#  1 Only bother with the line containing the word loss
#  2 replace "packet loss" with ~, since cut needs a single char
#    delimiter
#  3 remove any % chars, we want loss as a float
#  4 only keep line up to not including ~ (packet loss)
#  5 display last remaining word - packet loss as a float with
#    no % sign!
#
avg_loss="$(echo "$ping_output" |
    grep "packet loss" | # Only process the summary line

    # get rid of % and make ~ indicate end of interesting part
    sed 's/%// ; s/packet loss/~/' |
    cut -d~ -f 1 | # only keep up to before ~
    awk 'NF>1{print $NF}')"

#
#  Normalize number of decimals to one for consistency
#
case $(echo "$avg_loss" | awk -F'.' '{ print length($2) }') in
1) ;;
0) # fake a decimal
    avg_loss="${avg_loss}.0"
    ;;
*) # only use one digit
    rounded_loss="$(echo "$avg_loss" | awk '{printf "%.1f", $0}')"
    avg_loss="$rounded_loss"
    ;;
esac

echo "$avg_loss"
