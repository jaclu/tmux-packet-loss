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

#
#  log_it is used to display status to $log_file if it is defined.
#  Good for testing and monitoring actions.
#  Logging should normally be disabled, since it causes some overhead.
#  If $log_file is unset no output will happen.
#  this checks if the log file is present, if it is, logging is used
#  so will not be activated by default.
#
[[ -f /tmp/tmux-packet-loss.log ]] && log_file=/tmp/tmux-packet-loss.log

#
#  Since it is set outside main() this will remain in effect for
#  modules that didnt set it
#
[[ -z "$log_prefix" ]] && log_prefix="???"

get_tmux_socket() {
    if [[ -n "$TMUX" ]]; then
        echo "$TMUX" | sed 's#/# #g' | cut -d, -f 1 | awk 'NF>1{print $NF}'
    else
        echo "standalone"
    fi
}

#
#  If $log_file is empty or undefined, no logging will occur.
#
log_it() {
    local socket

    if $log_interactive_to_stderr && [[ -t 0 ]]; then
        printf "log: %s%*s%s\n" "$log_prefix" "$log_indent" "" "$@" >/dev/stderr
        return
    elif [[ -z "$log_file" ]]; then
        return
    fi

    if [[ "$log_ppid" = "true" ]]; then
        proc_id="$(tmux display -p "#{session_id}"):$PPID"
    else
        proc_id="$$"
    fi

    socket=" $(get_tmux_socket)"
    # only show socket name if not default
    # [[ "$socket" = " default" ]] && socket=""

    printf "%s%s %s %s%*s%s\n" "$(date '+%H:%M:%S')" "$socket" "$proc_id" "$log_prefix" "$log_indent" "" "$@" >>"$log_file"
}

#
#  Display $1 as an error message in log and as a tmux display-message
#  If $2 is set to 0, process is not exited
#
error_msg() {
    local msg="ERROR: $1"
    local exit_code="${2:-1}"
    local display_message=${3:-true}

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

#---------------------------------------------------------------
#
#   Datatype handling
#
#---------------------------------------------------------------

float_drop_digits() {
    #
    # float to int by dropping all digits
    #
    echo "$1" | sed 's/\./ /' | cut -d' ' -f 1
}

#---------------------------------------------------------------
#
#   bool params
#
#---------------------------------------------------------------

param_as_bool() {
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
        # log_it "Converted [$1] to boolean:  0"
        echo "true"
        ;;

    "0" | "no" | "No" | "NO" | "false" | "False" | "FALSE")
        #  Be a nice guy and accept some common false notations
        # log_it "Converted [$1] to boolean:  1"
        echo "false"
        ;;

    *)
        log_it "Invalid parameter normalize_bool_param($1)"
        error_msg "normalize_bool_param($1) - should be yes/true or no/false" 1
        ;;

    esac

    return 1
}

set_tmux_option() {
    local sto_option="$1"
    local sto_value="$2"

    [[ -z "$sto_option" ]] && error_msg "set_tmux_option() param 1 empty!"

    [[ "$TMUX" = "" ]] && return # this is run standalone

    $TMUX_BIN set -g "$sto_option" "$sto_value"
}

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

    #
    #  unofficial parameter, still in testing
    #
    #use_param_cache="$(normalize_bool_param "$(get_tmux_option \
    #    "@packet-loss-use_param_cache" "true")")"

    param_as_bool "$use_param_cache" && param_cache_write
}

safe_now() {
    #
    #  MacOS date only counts whole seconds, if gdate (GNU-date) is installed
    #  it can  display times with more precission
    #
    if [[ "$(uname)" = "Darwin" ]]; then
        if [[ -n "$(command -v gdate)" ]]; then
            gdate +%s.%N
        else
            date +%s
        fi
    else
        date +%s.%N
    fi
}

display_time_elapsed() {
    $skip_time_elapsed && return

    local t_start="$1"
    local label="$2"
    local duration

    # log_it "safe now:[$(safe_now)]"
    duration="$(echo "$(safe_now) - $t_start" | bc)"
    # log_it "duration [$duration]"
    log_it "Since start: $(printf "%.2f" "$duration") $label"
}

sqlite_err_handling() {
    local sql="$1"

    sqlite3 "$sqlite_db" "$sql" 2>>"$f_sqlite_errors"
}

#===============================================================
#
#   Main
#
#===============================================================

main() {
    local log_prefix="$log_prefix"

    #
    # for actions in utils log_prefix gets an u prefix
    # using local ensures it goes back to its original setting once
    # code is run from the caller.
    #
    log_prefix="u-$log_prefix"

    log_indent=1

    # if set tools run from commandline will print log entries to screen
    log_interactive_to_stderr=false

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

    #
    #  Should have been set in the calling script, must be done after
    #  log_file is (potentially) defined
    #
    [[ -z "$D_TPL_BASE_PATH" ]] && error_msg "D_TPL_BASE_PATH is not defined!"

    d_data="$D_TPL_BASE_PATH/data" # location for all runtime data

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
    sqlite_db="$d_data"/packet_loss.sqlite
    pidfile_tmux="$d_data"/tmux.pid
    pidfile_monitor="$d_data"/monitor.pid
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
    db_version=11

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

    #
    # override settings for easy debugging
    #
    # log_file=""
    # log_interactive_to_stderr=true # doesnt seem to work on iSH
    # use_param_cache=false
    # skip_time_elapsed=false

    get_settings
}

main
