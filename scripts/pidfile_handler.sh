#!/usr/bin/env bash
#
#   Copyright (c) 2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Handling of pidfiles
#   pidfile_acquire() - call this early at startup, to ensure additional
#                        instances of same script can't be started
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
#   pidfile_proc - process owning the pid_file or ""
#

pidfile_show_process() {
    set_pidfile_env "$1"
    echo "$pidfile_proc"
}

pidfile_is_live() {
    #
    #  boolean
    #
    local log_indent=$log_indent
    local was_alive=false

    _pf_log "pidfile_is_live($1)"
    ((log_indent++)) # increase indent until this returns
    set_pidfile_env "$1"

    if [[ -f "$pid_file" ]]; then
        [[ -n "$pidfile_proc" ]] && {
            if [[ "$(uname)" = "Darwin" ]]; then
                #
                #  kill -0 doesn't kill, it just reports if the process is
                #  still around
                #
                kill -0 "$pidfile_proc" 2>/dev/null && was_alive=true
            else
                [[ -d /proc/"$pidfile_proc" ]] && was_alive=true
            fi
            $was_alive && {
                _pf_log "found process: $pidfile_proc"
                return 0
            }
        }
        _pf_log "pid_file was abandoned"
        return 1
    else
        _pf_log "no such pid_file"
        return 2
    fi
}

pidfile_is_mine() {
    #
    #  Returns true if this process is owning the pidfile, or if it
    #  is an abandoned pidfile
    #
    local log_indent=$log_indent

    _pf_log "pidfile_is_mine($1)"
    ((log_indent++)) # increase indent until this returns
    set_pidfile_env "$1"

    pidfile_is_live "$pid_file" && {
        [[ "$pidfile_proc" != "$$" ]] && {
            _pf_log "NOT my pidfile - owner: $pidfile_proc"
            return 1
        }
        _pf_log "was mine"
        return 0
    }
    _pf_log "no such pidfile"
    return 2
}

pidfile_acquire() {
    #
    #  An optional second param indicates how many times to try to
    #  acquire the pidfile, between each attempt, a randomized
    #  sleep 1-5 seconds is done
    #
    local log_indent=$log_indent
    local attempts="${2:-1}"
    local i
    local msg

    _pf_log "pidfile_acquire($1)"
    ((log_indent++)) # increase indent until this returns
    set_pidfile_env "$1"

    [[ -n "$pid_file" ]] && [[ ! -f "$pid_file" ]] && {
        #
        #  First attempting early grab, at this point it doesn't matter if
        #  if multiple paallel processes over-wrote each other, since
        #  the content of the file will be verified, and if the owner
        #  doesn't match, this instance will wait and retry until success
        #  or running out of attempts.
        #
        echo $$ 2>/dev/null >"$pid_file" || {
            msg="pidfile_acquire($pid_file) \n "
            msg+="Early grab failed to write pid_file"
            error_msg "$msg" -1
            return 1
        }
        _pf_log "Early acquire successful"
    }

    ! is_int "$attempts" && {
        msg="pidfile_acquire($pid_file) \n "
        msg+="2nd param must be int - got [$attempts]"
        error_msg "$msg"
    }

    pidfile_is_mine "$pid_file" && {
        #
        #  verification needed in case multiple early grabs happened
        #  at the same time
        #
        _pf_log "Acquire successful"
        return 0
    }

    for ((i = 1; i <= "$attempts"; i++)); do
        log_it "+++++ waiting for $pid_file_short $i/$attempts"
        random_sleep 5 1

        pidfile_is_live "$pid_file" || {
            echo $$ 2>/dev/null >"$pid_file" || {
                msg="pidfile_acquire($pid_file) \n "
                msg+="Failed to write pid_file"
                error_msg "$msg" -1
                return 2
            }
            _pf_log "pid_file created"

            # [[ "$i" -gt 1 ]] && {
            log_it "+++++ $pid_file_short available on attempt $i/$attempts"
            # }
            break
        }
    done

    #  Final verification
    pidfile_is_mine "$pid_file" || {
        msg="pidfile_acquire($pid_file) - Failed \n "
        msg+="it is used by process: $pidfile_proc"
        error_msg "$msg:" -1
        return 3
    }
    _pf_log "Acquire successful"
    return 0
}

pidfile_release() {
    #
    #  Calling this is optional, but it will remove the pid_file and
    #  thereby indicate the process exited gracefully.
    #
    #  It can be used to remove pid_files now owned by the running
    #  process if they are abandoned.
    #
    local log_indent=$log_indent
    local msg

    _pf_log "pidfile_release($1)"
    ((log_indent++)) # increase indent until this returns
    set_pidfile_env "$1"

    pidfile_is_live "$pid_file" && {
        pidfile_is_mine "$pid_file" || {
            msg="pidfile_release($pid_file) failed \n "
            msg+="in use by process: $pidfile_proc"
            error_msg "$msg" -1
            return 1
        }
    }
    [[ -f "$pid_file" ]] && {
        [[ -O "$pid_file" ]] || {
            error_msg "pidfile_release($pid_file) - not writeable" -1
            return 2
        }
        rm -f "$pid_file" 2>/dev/null || {
            error_msg "pidfile_release($pid_file) - failed to remove" -1
            return 3
        }
        _pf_log "Release successful"
    }
    return 0
}

#---------------------------------------------------------------
#
#   Other
#
#---------------------------------------------------------------

_pf_log() {
    #
    #  Uses log_it() after checking $do_pidfile_handler_logging
    #
    $do_pidfile_handler_logging && log_it "pf> ${*}"
}

set_pidfile_env() {
    #
    #  Variables provided:
    #    pid_file - based on name of current script name if nothing provided
    #    pid_file_short - shortened path without location of plugin
    #    pidfile_proc - process indicated in pidfile if file exists
    #
    # _pf_log "set_pidfile_env($1) pid_file: $pid_file"
    if [[ -n "$1" ]]; then
        pid_file="$1"
    elif [[ -z "$pid_file" ]]; then
        pid_file="$d_data/${current_script}.pid"
    fi
    #
    #  Handle plugin prefix
    #
    if [[ "${pid_file:0:1}" = "/" ]]; then
        pid_file_short="${pid_file#"$D_TPL_BASE_PATH"/}"
    else
        pid_file_short="$pid_file"
        pid_file="$d_data/$pid_file"
    fi
    if [[ -f "$pid_file" ]]; then
        pidfile_proc="$(cat "$pid_file" 2>/dev/null)"
    else
        pidfile_proc=""
    fi
}

#===============================================================
#
#   Main
#
#===============================================================

[[ -z "$D_TPL_BASE_PATH" ]] && {
    # If this was sourced this variable would already have been set

    D_TPL_BASE_PATH="$(dirname -- "$(dirname -- "$(realpath -- "$0")")")"
    log_prefix="pid"
    . "$D_TPL_BASE_PATH"/scripts/utils.sh
}

[[ -z "$do_pidfile_handler_logging" ]] && do_pidfile_handler_logging=false

#
# set to true to enable logging of pidfile tasks
#
# do_pidfile_handler_logging=true
