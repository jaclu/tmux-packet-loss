#!/usr/bin/env bash
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Version: 0.1.0 2022-03-25
#


# if adv_vers_compare $version "<" "3.1"; then


#
#  Version checker that handles numerical versions, like 3.2
#  without getting confused, and can compare it to items ending in an
#  letter, like 3.2a
#
# Compare a and b as version strings. Rules:
# R1: a and b : dot-separated sequence of items. Items are numeric. The last item can optionally end with letters, i.e., 2.5 or 2.5a.
# R2: Zeros are automatically inserted to compare the same number of items, i.e., 1.0 < 1.0.1 means 1.0.0 < 1.0.1 => yes.
# R3: op can be '=' '==' '!=' '<' '<=' '>' '>=' (lexicographic).
# R4: Unrestricted number of digits of any item, i.e., 3.0003 > 3.0000004.
# R5: Unrestricted number of items.
#
adv_vers_compare() { # $1-a $2-op $3-$b
    local a=$1 op=$2 b=$3 al=${1##*.} bl=${3##*.}
    while [[ $al =~ ^[[:digit:]] ]]; do al=${al:1}; done
    while [[ $bl =~ ^[[:digit:]] ]]; do bl=${bl:1}; done
    local ai=${a%$al} bi=${b%$bl}

    local ap=${ai//[[:digit:]]} bp=${bi//[[:digit:]]}
    ap=${ap//./.0} bp=${bp//./.0}

    local w=1 fmt=$a.$b x IFS=.
    for x in $fmt; do [ ${#x} -gt $w ] && w=${#x}; done
    fmt=${*//[^.]}; fmt=${fmt//./%${w}s}
    printf -v a $fmt $ai$bp; printf -v a "%s-%${w}s" $a $al
    printf -v b $fmt $bi$ap; printf -v b "%s-%${w}s" $b $bl

    # shellcheck disable=SC1009,SC1072,SC1073
    case $op in
        '<='|'>=' ) [ "$a" ${op:0:1} "$b" ] || [ "$a" = "$b" ] ;;
        * )         [ "$a" $op "$b" ] ;;
    esac
}
