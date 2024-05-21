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
    #  once/day in the end of monitor_packet_loss.sh
    #
    printf "%s%s %s %s%*s%s\n" "$(date +%H:%M:%S)" "$socket" "$proc_id" \
        "$log_prefix" "$log_indent" "" "$@" >>"$cfg_log_file"
}

error_msg() {
    #
    #  Display $1 as an error message in log and as a tmux display-message
    #  If exit_code is set to -1, process is not exited
    #  if do_display_message is true, the error msg is displayed on
    #  the status bar
    #
    local msg="ERROR: $1"
    local exit_code="${2:-1}"
    local do_display_message=${3:-false}

    if $log_interactive_to_stderr && [[ -t 0 ]]; then
        echo "$msg" >/dev/stderr
    else
        log_it
        log_it "$msg"
        log_it
        #  display-message filters out \n
        msg="$(echo "$msg" | tr '\n' ' ')"
        $do_display_message && display_message_hold "$plugin_name $msg"
    fi
    [[ "$exit_code" -gt -1 ]] && exit "$exit_code"
}

display_message_hold() {
    #
    #  Display a message and hold until key-press
    #  Can't use tmux_error_handler in this func, since that could
    #  trigger recursion
    #
    local msg="$1"
    local org_display_time

    if tmux_vers_compare 3.2; then
        $TMUX_BIN display-message -d 0 "$msg"
    else
        # Manually make the error msg stay on screen a long time
        org_display_time="$($TMUX_BIN show-option -gv display-time)"
        $TMUX_BIN set -g display-time 120000 >/dev/null
        $TMUX_BIN display-message "$msg"

        posix_get_char >/dev/null # wait for keypress
        $TMUX_BIN set -g display-time "$org_display_time" >/dev/null
    fi
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

is_int() {
    case $1 in
    '' | *[!0-9]*) return 1 ;; # Contains non-numeric characters
    *) return 0 ;;             # Contains only digits
    esac
}

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

lowercase_it() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

posix_get_char() {
    #
    #  Configure terminal to read a single character without echoing,
    #  restoring the terminal and returning the char
    #
    local old_stty_cfg
    old_stty_cfg=$(stty -g)
    stty raw -echo
    dd bs=1 count=1 2>/dev/null
    stty "$old_stty_cfg"
}

#---------------------------------------------------------------
#
#   bool params
#
#---------------------------------------------------------------

#---------------------------------------------------------------
#
#   sqlite
#
#---------------------------------------------------------------

sqlite_err_handling() {
    #
    #  If SQLITE_BUSY is detected, two more attempt is done after a sleep
    #  other error handling should be done by the caller
    #
    #  Loggs sqlite errors to $f_sqlite_errors
    #
    #  Additional exit code:
    #    99  - still SQLITE_BUSY despite recursion
    #
    #  Variables provided:
    #    sqlite_exit_code - exit code for latest sqlite3 action
    #                       if called as a function
    #
    local sql="$1"
    local recursion="${2:-1}"

    is_int "$recursion" || {
        error_msg \
            "sqlite_err_handling(): recursion param not int [$recursion]"
    }

    sqlite3 "$sqlite_db" "$sql" 2>>"$f_sqlite_errors"
    sqlite_exit_code=$?

    [[ "$sqlite_exit_code" = 5 ]] && { #  SQLITE_BUSY
        if [[ "$recursion" -gt 2 ]]; then
            log_it "attempt $recursion also got SQLITE_BUSY - giving up"
            sqlite_exit_code=99 # repeated SQLITE_BUSY
        else
            #
            #  Make the sleep somewhat random, in order to not have two processes
            #  sleeping the same and coliding again
            #
            sleep $((RANDOM % 4 + 2)) #  2-5 seconds
            ((recursion++))
            log_it "SQLITE_BUSY - attempt: $recursion"
            sqlite_err_handling "$sql" "$recursion"
        fi
    }
    return "$sqlite_exit_code"
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
    #  this will exit true if $sqlite_err_handling is 0
    #  caller should check sqlite_exit_code or $? depending how this was
    #  called
    #
    return "$sqlite_exit_code"
}

sql_current_loss() {
    #
    #  Exported variables
    #    sql - the sql to get a weighted / average loss rate
    #
    local use_weighted="$1"

    [[ -z "$use_weighted" ]] && {
        error_msg "Call to sql_current_loss() without param"
    }
    # normalize_bool_param "$a" &&
    #     use_weighted=true || use_weighted=false
    # error_msg "use_weighted [$use_weighted]"

    if $use_weighted; then
        #
        #  To give loss a declining history weighting,
        #  it is displayed as the largest of:
        #    last value
        #    avg of last 2
        #    avg of last 3
        #    avg of last 4
        #    ...
        #
        sql="SELECT max(
        (SELECT loss FROM t_loss ORDER BY ROWID DESC limit 1      ),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 2  )),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 3  )),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 4  )),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 5  )),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 6  )),

        (SELECT avg(loss) FROM(
            SELECT loss FROM t_loss ORDER BY ROWID DESC limit 7  )),

        (SELECT avg(loss) FROM t_loss)
        )"
    else
        sql="SELECT avg(loss) FROM t_loss"
    fi
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

normalize_bool_param() {
    #
    #  Take a boolean style text param and convert it into an actual boolean
    #  that can be used in your code. Example of usage:
    #
    #  normalize_bool_param "@menus_without_prefix" "$default_no_prefix" &&
    #      cfg_no_prefix=true || cfg_no_prefix=false
    #

    param="$1"
    _variable_name=""
    # log_it "normalize_bool_param($param, $2)"

    [[ "${param%"${param#?}"}" = "@" ]] && {
        #
        #  If it starts with "@", assume it is tmux variable name, thus
        #  read its value from the tmux environment.
        #  In this case $2 must be given as the default value!
        #
        [[ -z "$2" ]] && {
            error_msg "normalize_bool_param($param) - no default" 1 true
        }
        _variable_name="$param"
        param="$(get_tmux_option "$param" "$2")"
    }

    param="$(lowercase_it "$param")"
    case "$param" in
    #
    #  First handle the unfortunate tradition by tmux to use
    #  1 to indicate selected / active.
    #  This means 1 is 0 and 0 is 1, how Orwellian...
    #
    1 | yes | true)
        #  Be a nice guy and accept some common positive notations
        return 0
        ;;

    0 | no | false)
        #  Be a nice guy and accept some common false notations
        return 1
        ;;

    *)
        if [[ -n "$_variable_name" ]]; then
            prefix="$_variable_name=$param"
        else
            prefix="$param"
        fi
        error_msg "$prefix - should be yes/true or no/false" 1 true
        ;;

    esac

    # Should never get here...
    return 2
}

param_cache_write() {
    log_it "Generating param cache: $f_param_cache"
    #region conf cache file
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
    #endregion
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
    normalize_bool_param "@packet-loss-weighted_average" "$default_weighted_average" &&
        cfg_weighted_average=true || cfg_weighted_average=false
    normalize_bool_param "@packet-loss-display_trend" "$default_display_trend" &&
        cfg_display_trend=true || cfg_display_trend=false

    cfg_level_disp="$(get_tmux_option "@packet-loss-level_disp" \
        "$default_level_disp")"
    cfg_level_alert="$(get_tmux_option "@packet-loss-level_alert" \
        "$default_level_alert")"
    cfg_level_crit="$(get_tmux_option "@packet-loss-level_crit" \
        "$default_level_crit")"
    normalize_bool_param "@packet-loss-hist_avg_display" "$default_hist_avg_display" &&
        cfg_hist_avg_display=true || cfg_hist_avg_display=false
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

    $use_param_cache && param_cache_write
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

    plugin_name="tmux-packet-loss"
    #
    #  For actions in utils log_prefix gets an u- prefix
    #  using local ensures it goes back to its original setting once
    #  code is run from the caller.
    #
    log_prefix="u-$log_prefix"

    log_indent=1 # check pidfile_handler.sh to see how this is used

    #
    #  Sanity check that DB structure is current, if not it will be replaced
    #
    db_version=12

    #
    #  DB should be updated every $cfg_ping_count seconds, if it hasnt
    #  been changed in a while monitor is most likely not running, or has
    #  gotten stuck. Restarting it should solve the issue.
    #  Since this script is run at regular intervalls, it is a good place
    #  to ensure it is operational.
    #
    db_max_age_mins=2

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
    #  Currently running script
    #
    this_app="$(basename "$0")"

    #
    #  Shortands for some scripts that are called in various places
    #
    scr_ctrl_monitor="$D_TPL_BASE_PATH"/scripts/ctrl_monitor.sh
    scr_display_losses="$D_TPL_BASE_PATH"/scripts/display_losses.sh
    scr_monitor="$D_TPL_BASE_PATH"/scripts/monitor_packet_loss.sh
    scr_pidfile_handler="$D_TPL_BASE_PATH"/scripts/pidfile_handler.sh

    #
    #  These files are assumed to be in the directory data
    #
    f_log_date="$d_data"/log_date
    f_param_cache="$d_data"/param_cache
    f_previous_loss="$d_data"/previous_loss
    f_sqlite_errors="$d_data"/sqlite.err

    sqlite_db="$d_data"/packet_loss.sqlite

    pidfile_ctrl_monitor="$d_data"/ctrl_monitor.pid
    pidfile_monitor="$d_data"/monitor.pid
    pidfile_tmux="$d_data"/tmux.pid

    #  lists each time display_losses had to restart monitor
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
    default_weighted_average=true

    #  display ^/v prefix if value is increasing/decreasing
    default_display_trend=false

    default_level_disp=1   #  display loss if this or higher
    default_level_alert=17 #  this or higher triggers alert color
    default_level_crit=40  #  this or higher triggers critical color

    #  Display long term average
    default_hist_avg_display=false
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
