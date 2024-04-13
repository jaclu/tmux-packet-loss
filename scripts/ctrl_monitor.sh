#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#

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

    local ap=${ai//[[:digit:]]/} bp=${bi//[[:digit:]]/}
    ap=${ap//./.0} bp=${bp//./.0}

    local w=1 fmt=$a.$b x IFS=.
    for x in $fmt; do [ ${#x} -gt $w ] && w=${#x}; done
    fmt=${*//[^.]/}
    fmt=${fmt//./%${w}s}
    printf -v a $fmt $ai$bp
    printf -v a "%s-%${w}s" $a $al
    printf -v b $fmt $bi$ap
    printf -v b "%s-%${w}s" $b $bl

    # shellcheck disable=SC1009,SC1072,SC1073
    case $op in
    '<=' | '>=') [ "$a" ${op:0:1} "$b" ] || [ "$a" = "$b" ] ;;
    *) [ "$a" $op "$b" ] ;;
    esac
}

check_pidfile_task() {
    #
    #  Check if pidfile is relevant
    #
    #  Variables defined:
    #   pid - what pid was listed in monitor_pidfile
    #

    # log_it "check_pidfile_task()"
    _result=1 # false
    [ -z "$monitor_pidfile" ] && error_msg "monitor_pidfile is not defined!"
    if [ -e "$monitor_pidfile" ]; then
        pid="$(cat "$monitor_pidfile")"
        ps -p "$pid" >/dev/null && _result=0 # true
    fi
    return "$_result"
}

stray_instances() {

    #
    #  Find any other stray monitoring processes
    #
    log_it "stray_instances()"
    proc_to_check="/bin/sh $scr_monitor"
    if [ -n "$(command -v pgrep)" ]; then
        # log_it "procs before pgrep [$(ps ax)]"
        pgrep -f "$proc_to_check" | grep -v $$
    else
        #
        #  Figure our what ps is available, in order to determine
        #  which param is the pid
        #
        if readlink "$(command -v ps)" | grep -q busybox; then
            pid_param=1
        else
            pid_param=2
        fi

        ps axu | grep "$proc_to_check" | grep -v grep | awk -v p="$pid_param" '{ print $p }' | grep -v $$
    fi
}

all_procs_but_me() {
    echo
    ps ax | grep "$scr_monitor" | grep -v grep | grep -v $$
    echo
}

kill_any_strays() {
    log_it "kill_any_strays()"
    [ -f "$f_proc_error" ] && {
        log_it "proc error detected, skipping stray killing"
        return
    }

    strays="$(stray_instances)"
    [ -n "$strays" ] && {
        log_it "Found stray processes[$strays]"
        log_it "procs before: $(all_procs_but_me)"
        echo "$strays" | xargs kill
        log_it "procs after: $(all_procs_but_me)"
        # remaing_strays="$(stray_instances)"
        # [ -n "$remaing_strays" ] && {
        #     log_it "remaining strays: [$remaing_strays] [$(ps -p "$remaing_strays")]"
        #     touch "$f_proc_error"
        #     error_msg "Created: $f_proc_error"
        # }
    }
}

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler() {
    action="$1"

    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"
    # log_it "hook_handler($action) tmux vers: $tmux_vers"

    if adv_vers_compare "$tmux_vers" ">=" "3.0"; then
        hook_name="session-closed[$hook_idx]"
    elif adv_vers_compare "$tmux_vers" ">=" "2.4"; then
        hook_name="session-closed"
    else
        error_msg "WARNING: previous to tmux 2.4 session-closed hook is " \
            "not available, so can not shut down monitor process when " \
            "tmux exits!" 0
    fi

    if [ -n "$hook_name" ]; then
        if [ "$action" = "set" ]; then
            $TMUX_BIN set-hook -g "$hook_name" "run $D_TPL_BASE_PATH/scripts/no_sessions_shutdown.sh"
            log_it "binding packet-loss shutdown to: $hook_name"
        elif [ "$action" = "clear" ]; then
            $TMUX_BIN set-hook -ug "$hook_name" >/dev/null
            log_it "releasing hook: $hook_name"
        else
            error_msg "hook_handler must be called with param set or clear!"
        fi
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

#  shellcheck source=utils.sh
. "$D_TPL_BASE_PATH/scripts/utils.sh"

log_prefix="ctr"
db_monitor="$(basename "$scr_monitor")"

check_pidfile_task && {
    # if [ "$1" = "stop" ]; then
    log_it "Will kill [$pid] $db_monitor"
    kill "$pid"
    check_pidfile_task && error_mg "Failed to kill [$pid]"
    # else
    #     error_msg "[$db_monitor] Is already running [$pid]"
    # fi
}
rm -f "$monitor_pidfile"

# kill_any_strays
# [ "$1" = "stop" ] && exit 0

hook_handler clear

case "$1" in

"stop")
    log_it "$db_monitor is shutdown"
    exit 0
    ;;

"start" | "") ;; # continue the startup

*) error_msg "Valid params: None or stop - got [$1]" ;;

esac

#
#  Starting a fresh monitor
#
nohup "$scr_monitor" >/dev/null 2>&1 &

sleep 1 # wait for monitor to start

#
#  When last session terminates, shut down monitor process in order
#  not to leave any trailing processes once tmux is shut down.
#
hook_handler set
