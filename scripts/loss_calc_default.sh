#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Default loss calculator
#
#  We cant rely on the absolute position of the %loss,
#  since sometimes it is prepended with stuff like:
#  "+1 duplicates,"
#  To handle this we search for "packet loss" and use the word
#  just before it.
#  1 Only bother with the line containing the word loss
#  2 replace "packet loss" with ~, since cut needs a single char
#    delimiter
#  3 remove any % chars, we want loss as a float
#  4 only keep line up to not including ~ (packet loss)
#  5 display last remaining word - packet loss as a float with
#    no % sign!
#

# Read input from stdin
ping_output=$(cat)

percent_loss="$(echo "$ping_output" |
     grep "packet loss" |
     sed 's/packet loss/~/ ; s/%//' |
     cut -d~ -f 1 | awk 'NF>1{print $NF}' |
     awk '{printf "%.1f", $0}' )"

echo "$percent_loss"

