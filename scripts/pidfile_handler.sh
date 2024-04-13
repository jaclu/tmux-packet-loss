#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Handling of pidfiles
#   pidfile_acquire() - call this early at startup, to ensure additional
#                        instances of same script cant be started
#   pidfile_release() - Optional, call to clear pidfile.
#                        pidfile_acquire will ignore any pidfile if the
#                        listed process is gone, so leaving a pidfile
#                        will not cause issues.
#
#  Support functions, mostly for the above, but can be used
#   pidfile_is_live() - Reports if process pointed to still is running
#   pidfile_is_mine() - Ensures that the pidfile points to current process
#
#  The following variables are exposed and can be used by calling entity
#   pid_file - name of current pid_file
#   pidfile_proc - process owning the pid_file if any
#

_pf_log() {
    #
    #  Uses log_it() after checking $do_pidfile_handler_logging
    #
    $do_pidfile_handler_logging && log_it "pf> ${*}"
}

pidfile_is_live() {
    #
    #  boolean
    #
    local log_indent=$log_indent

    pid_file="${1:-"$d_data/pid.$(basename "$0")"}"
    pidfile_proc=""

    _pf_log "pidfile_is_live($pid_file)"
    ((log_indent++)) # increase indent until this returns

    if [[ -f "$pid_file" ]]; then
        pidfile_proc="$(cat "$pid_file")"
        ps -p "$pidfile_proc" >/dev/null && {
            _pf_log "[$pidfile_proc] still pressent"
            return 0
        }
        _pf_log "pid_file was abandoned"
    else
        _pf_log "no such pid_file"
    fi
    # dont delete it right away, owerwrite if you want to claim it.
    return 1
}

pidfile_is_mine() {
    local log_indent=$log_indent

    pid_file="${1:-"$d_data/pid.$(basename "$0")"}"

    _pf_log "pidfile_is_mine($pid_file)"
    ((log_indent++)) # increase indent until this returns

    if pidfile_is_live "$pid_file" && [[ "$pidfile_proc" = "$$" ]]; then
        _pf_log "was mine"
        _b=0
    else
        _pf_log "NOT my pidfile!"
        _b=1
    fi
    return "$_b"
}

pidfile_acquire() {
    local log_indent=$log_indent

    pid_file="${1:-"$d_data/pid.$(basename "$0")"}"

    _pf_log "pidfile_acquire($pid_file)"
    ((log_indent++)) # increase indent until this returns

    pidfile_is_live "$pid_file" && {
        # Could be called by some many different tasks, let them decide
        # if there is a need to document this failure
        return 1
    }
    echo $$ >"$pid_file" # claim it
    _pf_log "pid_file created"

    pidfile_is_mine "$pid_file" || {
        error_msg "Failed to create pid_file: [$pid_file]"
    }
    _pf_log "Aquire successfull"
    return 0
}

pidfile_release() {
    #
    #  Calling this is optional, but it will remove the pid_file and
    #  thereby indicate the process exited gracefully
    #
    local log_indent=$log_indent

    pid_file="${1:-"$d_data/pid.$(basename "$0")"}"

    _pf_log "pidfile_release($pid_file)"
    ((log_indent++)) # increase indent until this returns

    pidfile_is_mine "$pid_file" || {
        error_msg "pidfile_release($pid_file) failed, was owned by [$pidfile_proc]"
    }
    rm -r "$pid_file"
    _pf_log "Release successful"
}

#===============================================================
#
#   Main
#
#===============================================================

[[ -z "$D_TPL_BASE_PATH" ]] && {
    # If this was sourced this variable would already have been set

    D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath -- "$0")")")

    #  shellcheck source=utils.sh
    . "$D_TPL_BASE_PATH/scripts/utils.sh"
}

#
# set to true to enable logging
#
do_pidfile_handler_logging=false
