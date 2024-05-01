#!/usr/bin/env bash
#  shellcheck disable=SC2034
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#  Common stuff
#

#---------------------------------------------------------------
#
#   Logging and error msgs
#
#---------------------------------------------------------------

log_it() {
    [[ -z "$cfg_log_file" ]] && return #  early abort if no logging
    #
    #  If @packet-loss-log_file is defined, it will be read into the
    #  cfg_log_file variable and used for logging.
    #
    #  Logging should normally be disabled, since it causes some overhead.
    #
    local socket

    $log_interactive_to_stderr && [[ -t 0 ]] && {
        printf "log: %s%*s%s\n" "$log_prefix" "$log_indent" "" \
            "$@" >/dev/stderr
        return
    }

    if [[ "$log_ppid" = "true" ]]; then
        proc_id="$(tmux display -p "#{session_id}"):$PPID"
    else
        proc_id="$$"
    fi

    #  needs leading space for compactness in the printf if empty
    socket=" $(get_tmux_socket)"
    #  only show socket name if not default
    # [[ "$socket" = " default" ]] && socket=""

    #
    #  In order to not have date on every line, date is just printed
    #  once/day
    #
    today="$(date +%Y-%m-%d)"
    last_log_date="$(cat "$f_log_date" 2>/dev/null)"
    [[ "$last_log_date" != "$today" ]] && {
        # since we got here $cfg_log_file is defined
        (
            echo
            echo "===============  $today  ==============="
            echo
        ) >>"$cfg_log_file"
        echo "$today" >"$f_log_date"
    }

    printf "%s%s %s %s%*s%s\n" "$(date +%H:%M:%S)" "$socket" "$proc_id" \
        "$log_prefix" "$log_indent" "" "$@" >>"$cfg_log_file"
}

error_msg() {
    #
    #  Display $1 as an error message in log and as a tmux display-message
    #  If $2 is set to 0, process is not exited
    #
    local msg="ERROR: $1"
    local exit_code="${2:-1}"
    local display_message=${3:-false}

    if $log_interactive_to_stderr && [[ -t 0 ]]; then
        echo "$msg" >/dev/stderr
    else
        log_it
        log_it "$msg"
        log_it
        $display_message && {
            # only display exit triggering errors on status bar
            $TMUX_BIN display-message -d 0 "packet-loss $msg"
        }
    fi
    [[ "$exit_code" -gt 0 ]] && exit "$exit_code"
}

save_ping_issue() {
    #
    #  Save a ping outout for later inspection
    #
    local ping_output="$1"
    local iso_datetime
    local f_ping_issue

    mkdir -p "$d_ping_issues" # ensure it exists
    iso_datetime=$(date +'%Y-%m-%d_%H:%M:%S')
    f_ping_issue="$d_ping_issues/$iso_datetime"
    log_it "Saving ping issue at: $f_ping_issue"
    echo "$ping_output" >"$f_ping_issue"
}

#---------------------------------------------------------------
#
#   Datatype handling
#
#---------------------------------------------------------------

is_float() {
    local input="$1"
    local strict_check="${2:-}"
    local float_pattern

    if [[ -n "$strict_check" ]]; then
        # must be a number with a .
        float_pattern='^[-+]?[0-9]*\.[0-9]+([eE][-+]?[0-9]+)?$'
    else
        # accepts both ints and floats
        float_pattern='^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$'
    fi

    # Check if the input matches the float pattern
    if [[ $input =~ $float_pattern ]]; then
        return 0 # Input is a floating-point number
    else
        return 1 # Input is not a floating-point number
    fi
}

#---------------------------------------------------------------
#
#   bool params
#
#---------------------------------------------------------------

param_as_bool() {
    #  Used to parse variables assigned "true" or "false" as booleans
    [[ "$1" = "true" ]] && return 0
    return 1
}

normalize_bool_param() {
    #
    #  Ensure boolean style params use consistent states
    #
    case "$1" in
    #
    #  First handle the mindboggling tradition by tmux to use
    #  1 to indicate selected / active.
    #  This means 1 is 0 and 0 is 1, how Orwellian...
    #
    "1" | "yes" | "Yes" | "YES" | "true" | "True" | "TRUE")
        #  Be a nice guy and accept some common positive notations
        echo "true"
        ;;

    "0" | "no" | "No" | "NO" | "false" | "False" | "FALSE")
        #  Be a nice guy and accept some common false notations
        echo "false"
        ;;

    *)
        log_it "Invalid parameter normalize_bool_param($1)"
        error_msg \
            "normalize_bool_param($1) - should be yes/true/1 or no/false/0" \
            1 true
        ;;

    esac

    return 1
}

#---------------------------------------------------------------
#
#   tmux env handling
#
#---------------------------------------------------------------
get_tmux_option() {
    local gto_option="$1"
    local gto_default="$2"
    local gto_value

    [[ -z "$gto_option" ]] && error_msg "get_tmux_option() param 1 empty!"
    [[ "$TMUX" = "" ]] && {
        # this is run standalone, just report the defaults
        echo "$gto_default"
        return
    }

    gto_value="$($TMUX_BIN show-option -gqv "$gto_option")"
    if [[ -z "$gto_value" ]]; then
        echo "$gto_default"
    else
        echo "$gto_value"
    fi
}

param_cache_write() {
    log_it "Generating param cache: $f_param_cache"
    cat <<EOF >"$f_param_cache"
    #
    # param cache, should always be removed on startup when
    # packet-loss.tmux is run
    #
    cfg_ping_host="$cfg_ping_host"
    cfg_ping_count="$cfg_ping_count"
    cfg_history_size="$cfg_history_size"
    cfg_weighted_average="$cfg_weighted_average"
    cfg_display_trend="$cfg_display_trend"
    cfg_level_disp="$cfg_level_disp"
    cfg_level_alert="$cfg_level_alert"
    cfg_level_crit="$cfg_level_crit"
    cfg_hist_avg_display="$cfg_hist_avg_display"
    cfg_hist_avg_minutes="$cfg_hist_avg_minutes"
    cfg_hist_separator="$cfg_hist_separator"
    cfg_color_alert="$cfg_color_alert"
    cfg_color_crit="$cfg_color_crit"
    cfg_color_bg="$cfg_color_bg"
    cfg_prefix="$cfg_prefix"
    cfg_suffix="$cfg_suffix"
    cfg_log_file="$cfg_log_file"

EOF
}

get_settings() {
    # log_it "get_settings()"
    $use_param_cache && [[ -f "$f_param_cache" ]] && {
        # log_it "using param cache"

        # shellcheck source=/dev/null
        source "$f_param_cache"
        return
    }

    cfg_ping_host="$(get_tmux_option "@packet-loss-ping_host" \
        "$default_ping_host")"
    cfg_ping_count="$(get_tmux_option "@packet-loss-ping_count" \
        "$default_ping_count")"
    cfg_history_size="$(get_tmux_option "@packet-loss-history_size" \
        "$default_history_size")"

    # in order to assign a boolean to a variable this two line aproach is needed

    cfg_weighted_average="$(normalize_bool_param "$(get_tmux_option \
        "@packet-loss-weighted_average" "$default_weighted_average")")"
    cfg_display_trend="$(normalize_bool_param "$(get_tmux_option \
        "@packet-loss-display_trend" "$default_display_trend")")"

    cfg_level_disp="$(get_tmux_option "@packet-loss-level_disp" \
        "$default_level_disp")"
    cfg_level_alert="$(get_tmux_option "@packet-loss-level_alert" \
        "$default_level_alert")"
    cfg_level_crit="$(get_tmux_option "@packet-loss-level_crit" \
        "$default_level_crit")"

    cfg_hist_avg_display="$(normalize_bool_param "$(get_tmux_option \
        "@packet-loss-hist_avg_display" "$default_hist_avg_display")")"
    cfg_hist_avg_minutes="$(get_tmux_option "@packet-loss-hist_avg_minutes" \
        "$default_hist_avg_minutes")"
    cfg_hist_separator="$(get_tmux_option "@packet-loss-hist_separator" \
        "$default_hist_separator")"

    cfg_color_alert="$(get_tmux_option "@packet-loss-color_alert" \
        "$default_color_alert")"
    cfg_color_crit="$(get_tmux_option "@packet-loss-color_crit" \
        "$default_color_crit")"
    cfg_color_bg="$(get_tmux_option "@packet-loss-color_bg" "$default_color_bg")"

    cfg_prefix="$(get_tmux_option "@packet-loss-prefix" "$default_prefix")"
    cfg_suffix="$(get_tmux_option "@packet-loss-suffix" "$default_suffix")"

    cfg_log_file="$(get_tmux_option "@packet-loss-log_file" "")"

    param_as_bool "$use_param_cache" && param_cache_write
}

get_tmux_socket() {
    #
    #  returns name of tmux socket being used
    #
    if [[ -n "$TMUX" ]]; then
        echo "$TMUX" | sed 's#/# #g' | cut -d, -f 1 | awk 'NF>1{print $NF}'
    else
        echo "standalone"
    fi
}

#---------------------------------------------------------------
#
#   sqlite
#
#---------------------------------------------------------------

sqlite_err_handling() {
    #
    #  If SQLITE_BUSY is detected, one more attempt is done after a sleep
    #  other error handling should be done by the caller
    #
    #  Loggs sqlite errors to $f_sqlite_errors
    #
    #  Variables provided:
    #    sqlite_exit_code - exit code for latest sqlite3 action
    #
    local sql="$1"
    local recursing=false

    [[ -n "$2" ]] && recursing=true

    sqlite3 "$sqlite_db" "$sql" 2>>"$f_sqlite_errors"
    sqlite_exit_code=$?
    [[ "$sqlite_exit_code" = 5 ]] && { #  SQLITE_BUSY
        $recursing && return

        log_it "SQLITE_BUSY"
        #
        #  Make the sleep somewhat random, in order to not have two processes
        #  sleeping the same and coliding again
        #
        sleep $((RANDOM % 4 + 2)) #  2-5 seconds
        sqlite_err_handling "$sql" recursing
        [[ "$sqlite_exit_code" = 5 ]] && {
            log_it "2nd attempt also got SQLITE_BUSY -giving up"
        }
    }
    #
    #  this will exit true if it is 0, false otherwise
    #  caller should check sqlite_exit_code
    #
    [[ "$sqlite_exit_code" -eq 0 ]] || false
}

sqlite_transaction() {
    local sql_original="$1"
    local sql

    sql="
        BEGIN TRANSACTION; -- Start the transaction

        $sql_original ;

        COMMIT; -- Commit the transaction
        "
    sqlite_err_handling "$sql"

    #
    #  this will exit true if it is 0, false otherwise
    #  caller should check sqlite_exit_code
    #
    [[ "$sqlite_exit_code" -eq 0 ]] || false
}

#---------------------------------------------------------------
#
#   Other
#
#---------------------------------------------------------------
is_busybox_ping() {
    [[ -z "$this_is_busybox_ping" ]] && {
        log_it "Checking if ping is a BusyBox one"
        #
        #  By saving state, this check only needs to be done once
        #
        if realpath "$(command -v ping)" | grep -qi busybox; then
            this_is_busybox_ping=true
        else
            this_is_busybox_ping=false
        fi
    }
    $this_is_busybox_ping
}

safe_now() {
    #
    #  This one is in utils, but since it is called before sourcing utils
    #  it needs to be duplicated here
    #
    #  MacOS date only counts whole seconds, if gdate (GNU-date) is
    #  installed, it can  display times with more precission
    #
    if [[ "$(uname)" = "Darwin" ]]; then
        if [[ -n "$(command -v gdate)" ]]; then
            gdate +%s.%N
        else
            date +%s
        fi
    else
        #  On Linux the native date suports sub second precission
        date +%s.%N
    fi
}

display_time_elapsed() {
    $skip_time_elapsed && return # quick abort if not used

    local t_start="$1"
    local label="$2"
    local duration

    [[ -z "$t_start" ]] && {
        error_msg "display_time_elapsed() t_start unset"
    }
    duration="$(echo "$(safe_now) - $t_start" | bc)"
    log_it "Since start: $(printf "%.2f" "$duration") $label"
}

#===============================================================
#
#   Main
#
#===============================================================

main() {
    local log_prefix="$log_prefix"

    #
    #  For actions in utils log_prefix gets an u- prefix
    #  using local ensures it goes back to its original setting once
    #  code is run from the caller.
    #
    log_prefix="u-$log_prefix"

    log_indent=1 # check pidfile_handler.sh to see how this is used

    #
    #  Debug help, should not normally be used
    #

    [[ -z $log_interactive_to_stderr ]] && log_interactive_to_stderr=false

    # set to true if session-id & ppid should be displayed instead of pid
    [[ -z "$log_ppid" ]] && log_ppid="false"

    #
    #  I use an env var TMUX_BIN to point at the current tmux, defined in my
    #  tmux.conf, in order to pick the version matching the server running.
    #  This is needed when checking backwards compatability with various versions.
    #  If not found, it is set to whatever is in path, so should have no negative
    #  impact. In all calls to tmux I use $TMUX_BIN instead in the rest of this
    #  plugin.
    #
    [[ -z "$TMUX_BIN" ]] && TMUX_BIN="tmux"

    #  Should have been set in the calling script
    [[ -z "$D_TPL_BASE_PATH" ]] && error_msg "D_TPL_BASE_PATH is not defined!"

    d_data="$D_TPL_BASE_PATH"/data # location for all runtime data
    d_ping_issues="$d_data"/ping_issues

    #
    #  Shortands for some scripts that are called in various places
    #
    scr_ctrl_monitor="$D_TPL_BASE_PATH"/scripts/ctrl_monitor.sh
    scr_monitor="$D_TPL_BASE_PATH"/scripts/monitor_packet_loss.sh
    scr_display_losses="$D_TPL_BASE_PATH"/scripts/display_losses.sh
    scr_pidfile_handler="$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh
    #
    #  These files are assumed to be in the directory data
    #
    f_param_cache="$d_data"/param_cache
    f_previous_loss="$d_data"/previous_loss
    f_sqlite_errors="$d_data"/sqlite.err
    f_log_date="$d_data"/log_date

    sqlite_db="$d_data"/packet_loss.sqlite

    pidfile_ctrl_monitor="$d_data"/ctrl_monitor.pid
    pidfile_monitor="$d_data"/monitor.pid
    pidfile_tmux="$d_data"/tmux.pid

    # lits each time display_losses had to restart monitor
    db_restart_log="$d_data"/db_restarted.log

    #  check one of the path items to verify D_TPL_BASE_PATH
    [[ -f "$scr_monitor" ]] || {
        error_msg "D_TPL_BASE_PATH seems invalid: [$D_TPL_BASE_PATH]"
    }

    [[ -d "$d_data" ]] || {
        #
        #  If data dir was removed whilst a monitor was running,
        #  the running monitor cant be killed via pidfile.
        #  Do it manually.
        #
        stray_monitors="$(pgrep -f "$scr_monitor")"
        [[ -n "$stray_monitors" ]] && {
            echo "$stray_monitors" | xargs kill
            log_it "Mannually killed stray monitor(-s)"
        }

        log_it "Creating $d_data"
        mkdir -p "$d_data" # ensure it exists
    }

    #
    #  Sanity check that DB structure is current, if not it will be replaced
    #
    db_version=12

    [[ -z "$skip_time_elapsed" ]] && {
        # creates a lot of overhead so should normally be true
        skip_time_elapsed=true
    }
    [[ -z "$use_param_cache" ]] && {
        use_param_cache=true # makes gathering the params a lot faster!
    }

    #
    #  Defaults for config variables
    #
    default_ping_host="8.8.8.8" #  Default host to ping
    default_ping_count=6        #  how often to report packet loss statistics
    default_history_size=6      #  how many ping results to keep in the primary table

    #  Use weighted average over averaging all data points
    default_weighted_average="$(normalize_bool_param "true")"

    #  display ^/v prefix if value is increasing/decreasing
    default_display_trend="$(normalize_bool_param "false")"

    default_level_disp=1   #  display loss if this or higher
    default_level_alert=17 #  this or higher triggers alert color
    default_level_crit=40  #  this or higher triggers critical color

    #  Display long term average
    default_hist_avg_display="$(normalize_bool_param "false")"
    default_hist_avg_minutes=30 #  Minutes to keep historical average
    default_hist_separator='~'  #  Separaor between current and hist data

    default_color_alert="colour226" # bright yellow
    default_color_crit="colour196"  # bright red
    default_color_bg='black'        #  only used when displaying alert/crit

    default_prefix='|'
    default_suffix='|'

    get_settings
}

#
#  Identifies the script triggering a log entry.
#  Since it is set outside main() this will remain in effect for
#  modules that didnt set it, during utils:main a prefix "u-" will be
#  added to show the log action happened as utils was sourced.
#
[[ -z "$log_prefix" ]] && log_prefix="???"

#
# override settings for easy debugging
#
# cfg_log_file=""
# log_interactive_to_stderr=true # doesnt seem to work on iSH
# use_param_cache=false

main
