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
#   pidfile_proc - process owning the pid_file or ""
#

_pf_log() {
    #
    #  Uses log_it() after checking $do_pidfile_handler_logging
    #
    $do_pidfile_handler_logging && log_it "pf> ${*}"
}

random_sleep() {
    #
    #  Function to generate a random sleep time with improved randomness
    #
    #  When multiple processes start at the same time using something like
    #    sleep $((RANDOM % 4 + 1))
    #  it tends to leave them sleeping for the same amount of seconds
    #
    # Parameters:
    #   $1: max_sleep - maximum seconds of sleep, can be fractional
    #   $2: min_sleep - min seconds of sleep, default: 0.5
    #
    # Example usage:
    #   # Sleep for a random duration between 0.5 and 5 seconds
    #   random_sleep 5
    #
    local max_sleep="$1"
    local min_sleep="${2:-0.5}"
    local pid=$$
    local rand_from_random rand_from_urandom random_integer sleep_time

    # multiply ny hundred, round to int
    min_sleep=$(printf "%.0f" "$(echo "$min_sleep * 100" | bc)")
    max_sleep=$(printf "%.0f" "$(echo "$max_sleep * 100" | bc)")

    # Generate random numbers
    rand_from_random=$((RANDOM % 100))
    rand_from_urandom=$(od -An -N2 -i /dev/urandom | awk '{print $1}')

    # log_it "rand_from_random[$rand_from_random] rand_from_urandom[$rand_from_urandom]"

    # Calculate random number between min_sleep and max_sleep with two decimal places
    random_integer=$(((rand_from_random + rand_from_urandom + pid) % (max_sleep - min_sleep + 1) + min_sleep))

    # Calculate the sleep time with two decimal places
    sleep_time=$(printf "%.2f" "$(echo "scale=2; $random_integer / 100" | bc)")

    # log_it "><> Sleeping for $sleep_time seconds"
    sleep "$sleep_time"
}

is_pid_alive() {
    #
    #  Since this might run on iSH, and that platform does not do well
    #  if ps is called too much, this is a safe workarround,
    #  and obviously Darwin doesnt have /proc, so it needs it's own
    #  workarround
    #
    local pid="$1"

    [[ -z "$pid" ]] && {
        error_msg "is_pid_alive() called withot a parameter"
    }

    if [[ "$(uname)" = "Darwin" ]]; then
        #
        #  kill -0 doesnt kill, it just reports if the process is
        #  still arround
        #
        kill -0 "$pid" 2>/dev/null || return 1
    else
        [[ -d /proc/"$pid" ]] || return 1
    fi
    return 0
}

# shellcheck disable=SC2120 # called with param from other modules...
get_pidfile_process() {
    #
    #  Variables provided:
    #    pidfile_proc - process in this pidfile
    #
    set_pidfile_name "$1"
    pidfile_proc="$(cat "$pid_file" 2>/dev/null)"
    _pf_log "pid_file is now: [$pid_file] pidfile_proc is now: [$pidfile_proc]"
}

show_pidfile_process() {
    get_pidfile_process "$1"
    echo "$pidfile_proc"
}

show_pidfile_short() {
    set_pidfile_name "$1"
    echo "$pid_file_short"
}

set_pidfile_name() {
    #
    #  Variables provided:
    #    pid_file - based on name of current script if nothing provided
    #
    [[ -z "$1" ]] && [[ -z "$pid_file" ]] && {
        msg="call to set_pidfile_name() whithout param \n "
        msg+="and no default pid_file already set"
        error_msg "$msg"
    }
    # [[ -n "$pid_file" ]] && {
    #     # was already set
    #     return
    # }
    pid_file="${1:-"$d_data/$this_app.pid"}"
    pid_file_short="${pid_file#"$D_TPL_BASE_PATH"/}"
}

pidfile_is_live() {
    #
    #  boolean
    #
    local log_indent=$log_indent

    set_pidfile_name "$1"
    _pf_log "pidfile_is_live($pid_file)"
    ((log_indent++)) # increase indent until this returns

    if [[ -f "$pid_file" ]]; then
        get_pidfile_process "$pid_file"
        [[ -n "$pidfile_proc" ]] && {
            is_pid_alive "$pidfile_proc" && {
                _pf_log "[$pidfile_proc] still pressent"
                return 0
            }
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

    set_pidfile_name "$1"
    _pf_log "pidfile_is_mine($pid_file)"
    ((log_indent++)) # increase indent until this returns

    if pidfile_is_live "$pid_file" && [[ "$pidfile_proc" = "$$" ]]; then
        _pf_log "was mine"
        return 0
    else
        _pf_log "NOT my pidfile!"
        return 1
    fi
}

pidfile_acquire() {
    #
    #  An optional second param indicates how many times to try to
    #  aquire the pidfile, between each attempt, a randomized
    #  sleep 1-5 seconds is done
    #
    local log_indent=$log_indent
    local attempts="${2:-1}"
    local i
    local msg

    # First attempting early grab
    [[ -n "$1" ]] && [[ ! -f "$1" ]] && {
        echo $$ 2>/dev/null >"$1" || {
            set_pidfile_name "$1"
            msg="pidfile_acquire($pid_file) \n "
            msg+="Early grab failed to write pid_file"
            error_msg "$msg" -1
            return 1
        }
        _pf_log "Early aquire successfull"
    }

    set_pidfile_name "$1"
    _pf_log "pidfile_acquire($pid_file)"
    ((log_indent++)) # increase indent until this returns

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
        _pf_log "Aquire successfull"
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
        msg+="it is used by process: $(show_pidfile_process "$pid_file")"
        error_msg "$msg:" -1
        return 3
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
    local msg

    set_pidfile_name "$1"
    _pf_log "pidfile_release($pid_file)"
    ((log_indent++)) # increase indent until this returns

    pidfile_is_mine "$pid_file" || {
        pidfile_is_live "$pid_file" && {
            msg="pidfile_release($pid_file) failed \n "
            msg+="still in use by [$pidfile_proc]"
            error_msg "$msg" -1
            return 1
        }
        _pf_log "pid_file was a left-over"
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

#===============================================================
#
#   Main
#
#===============================================================

[[ -z "$D_TPL_BASE_PATH" ]] && {
    # If this was sourced this variable would already have been set

    D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
    log_prefix="pid"
    #  shellcheck source=scripts/utils.sh
    . "$D_TPL_BASE_PATH"/scripts/utils.sh
}

[[ -z "$do_pidfile_handler_logging" ]] && do_pidfile_handler_logging=false

#
# set to true to enable logging of pidfile tasks
#
# do_pidfile_handler_logging=true
