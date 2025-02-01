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

    #  needs leading space for compactness in the printf if empty
    socket=" $(get_tmux_socket)"
    #  only show socket name if not default
    # [[ "$socket" = " default" ]] && socket=""

    #
    #  In order to not have date on every line, date is just printed
    #  once/day in the end of monitor_packet_loss.sh
    #
    printf "%s%s %s %s%*s%s\n" "$(date +'%F %T')" "$socket" "$$" \
        "$log_prefix" "$log_indent" "" "$@" >>"$cfg_log_file"
}

error_msg() {
    #
    #  Display $1 as an error message in log and in a scrollback buffer
    #  unless do_display_message is false
    #
    #  If exit_code is set to -1, process is not exited
    #
    local msg="$1"
    local exit_code="${2:-1}"
    local do_display_message=${3:-true}

    if $log_interactive_to_stderr && [[ -t 0 ]]; then
        echo "ERROR: $msg" >/dev/stderr
    else
        local err_display

        log_it
        log_it "ERROR: $msg"
        log_it

        err_display="\nplugin: $plugin_name:$current_script [$$] - ERROR:\n\n"
        err_display+="$msg\n\nPress ESC to close this display"
        if [[ -n "$TMUX" ]]; then
            $do_display_message && $TMUX_BIN run-shell "printf '$err_display'"
        else
            # shellcheck disable=SC2059
            printf "$err_display" >/dev/stderr
        fi
    fi
    [[ "$exit_code" -gt -1 ]] && exit "$exit_code"
}

save_ping_issue() {
    #
    #  Save a ping output for later inspection
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

do_not_run_create() {
    # Set an indication that system is unable to run
    local reason="$1"
    mkdir -p "$d_data" # ensure it exists
    echo "$reason" >"$f_do_not_run"
    log_it "Do not run condition activated: $reason"
}

do_not_run_clear() {
    # Clear state
    rm -f "$f_do_not_run"
}

do_not_run_active() {
    # Returns true if the tools in this plugin should not be used
    [[ -f "$f_do_not_run" ]] && return 0 # init failed to complete
    return 1
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

get_digits_from_string() {
    # this is used to get "clean" integer version number. Examples:
    # `tmux 1.9` => `19`
    # `1.9a`     => `19`
    local string="$1"
    local only_digits no_leading_zero

    only_digits="$(echo "$string" | tr -dC '[:digit:]')"
    no_leading_zero=${only_digits#0}
    echo "$no_leading_zero"
}

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
    #  Loggs sqlite errors to $f_sqlite_error
    #
    #  Variables provided:
    #    sqlite_result    - Output from query
    #    sqlite_exit_code - exit code for latest sqlite3 action
    #                       if called as a function
    #
    local sql="$1"
    local recursion="${2:-1}"

    # log_it "sqlite_err_handling()"

    if $log_sql; then # set to true to log sql queries
        local sql_filtered

        # this does some filtering to give a more meaningful summary
        sql_filtered="$(echo "$sql" |
            sed 's/BEGIN TRANSACTION; -- Start the transaction//' |
            tr -d '\n' | tr -s ' ' | sed 's/^ //' | sed 's/ ;/;/g' |
            sed 's/; /;/g' | cut -c 1-50)"
        log_it "SQL:$sql_filtered"
    fi

    is_int "$recursion" || {
        error_msg \
            "sqlite_err_handling(): recursion param not int [$recursion]"
    }

    sqlite_result="$(sqlite3 "$f_sqlite_db" "$sql" 2>"$f_sqlite_error")"
    sqlite_exit_code=$?

    case "$sqlite_exit_code" in
    0) ;; # no error
    5 | 141)
        #
        # 5 SQLITE_BUSY - obvious candidate for a few retries
        # 141   is an odd one, I have gotten it a couple of times on iSH.
        #       GPT didn't give any suggestion. Either way allowing it to
        #       try a few times solved the issue.
        #
        if [[ "$recursion" -gt 2 ]]; then
            log_it "attempt $recursion sqlite error:$sqlite_exit_code - giving up SQL: $sql"
        else
            random_sleep 2 # give compeeting task some time to complete
            ((recursion++))
            log_it "WARNING: sqlite error:$sqlite_exit_code  attempt: $recursion"
            sqlite_err_handling "$sql" "$recursion"
        fi
        ;;
    *)
        local err_msg

        #  log error but leave handling error up to caller
        err_msg="sqlite_err_handling()\n$sql\nerror code: $sqlite_exit_code\n"
        err_msg+="error msg:  $(cat "$f_sqlite_error")"
        error_msg "$err_msg" -1

        [[ ! -s "$f_sqlite_db" ]] && [[ -f "$f_sqlite_db" ]] && {
            #
            #  If DB was removed, then a sql action would fail but lead
            #  to an empty DB. By removing such, next call to
            #  display_losses will recreate it and restart monitoring
            #
            rm -f "$f_monitor_suspended_no_clients"
            rm -f "$f_sqlite_db"
            error_msg "Removing empty DB, terminating monitor" 1 false
        }
        ;;
    esac

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

set_tmux_vers() {
    #
    #  Variables provided:
    #   tmux_vers - version of tmux used
    #
    # log_it "set_tmux_vers()"
    tmux_vers="$($TMUX_BIN -V | cut -d' ' -f2)"

    # Filter out devel prefix and release candidate suffix
    case "$tmux_vers" in
    next-*)
        # Remove "next-" prefix
        tmux_vers="${tmux_vers#next-}"
        ;;
    *-rc*)
        # Remove "-rcX" suffix, otherwise the number would mess up version
        # 3.4-rc2 would be read as 342
        tmux_vers="${tmux_vers%-rc*}"
        ;;
    *) ;;
    esac
}

tmux_vers_compare() {
    #
    #  This returns true if v_comp <= v_ref
    #  If only one param is given it is compared vs version of running tmux
    #
    local v_comp="$1"
    local v_ref="${2:-$tmux_vers}"
    local i_comp i_ref

    i_comp=$(get_digits_from_string "$v_comp")
    i_ref=$(get_digits_from_string "$v_ref")

    [[ "$i_comp" -le "$i_ref" ]]
}

is_tmux_option_defined() {
    $TMUX_BIN show-options -g | grep -q "^$1"
}

get_tmux_option() {
    local opt="$1"
    local def="$2"
    local value

    [[ -z "$opt" ]] && error_msg "get_tmux_option() param 1 empty!"
    [[ "$TMUX" = "" ]] && {
        # this is run standalone, just report the defaults
        echo "$def"
        return
    }

    if value="$($TMUX_BIN show-options -gv "$opt" 2>/dev/null)"; then
        #
        #  I haven't figured out if it is my asdf builds that have issues
        #  or something else, since I never heard of this issue before.
        #  On the other side, I don't think I have ever tried to assign ""
        #  to a user-option that has a non-empty default, so it might be
        #  an actual bug in tmux 3.0 - 3.2a
        #
        #  The problem is that with these versions tmux will will not
        #  report an error if show-options -gv is used on an undefined
        #  option starting with the char "@" as you should with
        #  user-options. For options starting with other chars,
        #  the normal error is displayed also with these versions.
        #
        [[ -z "$value" ]] && ! is_tmux_option_defined "$opt" && {
            #
            #  This is a workaround, checking if the variable is defined
            #  before assigning the default, preserving intentional
            #  "" assignments
            #
            value="$def"
        }
    else
        #  All other versions correctly fails on unassigned @options
        value="$def"
    fi

    echo "$value"
}

normalize_bool_param() {
    #
    #  Take a boolean style text param and convert it into an actual
    #  boolean that can be used in your code. Example of usage:
    #
    #  normalize_bool_param "@menus_without_prefix" "$default_no_prefix" &&
    #      cfg_no_prefix=true || cfg_no_prefix=false
    #
    local param="$1"
    local var_name
    local prefix
    local msg

    var_name=""
    # log_it "normalize_bool_param($param, $2)"

    [[ "${param%"${param#?}"}" = "@" ]] && {
        #
        #  If it starts with "@", assume it is tmux variable name, thus
        #  read its value from the tmux environment.
        #  In this case $2 must be given as the default value!
        #
        [[ -z "$2" ]] && {
            error_msg "normalize_bool_param($param) - no default"
        }
        var_name="$param"
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
        if [[ -n "$var_name" ]]; then
            prefix="$var_name=$param"
        else
            prefix="$param"
        fi
        msg="normalize_bool_param($param) \n"
        msg+="$prefix - should be yes/true or no/false"
        error_msg "$msg"
        ;;

    esac

    # Should never get here...
    return 2
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

get_tmux_pid() {
    local tmux_pid

    tmux_pid=$(echo "$TMUX" | cut -d',' -f 2)
    [[ -z "$tmux_pid" ]] && error_msg \
        "Failed to extract pid for tmux process!"
    # log_it "get_tmux_pid() - found $tmux_pid"
    echo "$tmux_pid"
}

#---------------------------------------------------------------
#
#   param cache handling
#
#---------------------------------------------------------------

param_cache_write() {
    # log_it "param_cache_write()"
    $use_param_cache || {
        log_it "param_cache_write() - aborted, not using param_cache"
        return
    }

    mkdir -p "$(dirname -- "$(realpath -- "$f_param_cache")")" # ensure it exists

    set_tmux_vers # always get the current
    # echo "><> saving params" >>/Users/jaclu/tmp/tmux-packet-loss-t2.log
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
    cfg_hist_avg_display="$cfg_hist_avg_display"
    cfg_run_disconnected="$cfg_run_disconnected"

    cfg_level_disp="$cfg_level_disp"
    cfg_level_alert="$cfg_level_alert"
    cfg_level_crit="$cfg_level_crit"

    cfg_hist_avg_minutes="$cfg_hist_avg_minutes"
    cfg_hist_separator="$cfg_hist_separator"

    cfg_color_alert="$cfg_color_alert"
    cfg_color_crit="$cfg_color_crit"
    cfg_color_bg="$cfg_color_bg"

    cfg_prefix="$cfg_prefix"
    cfg_suffix="$cfg_suffix"

    cfg_run_disconnected="$cfg_run_disconnected"

    cfg_log_file="$cfg_log_file"

    tmux_vers="$tmux_vers"
EOF
    #endregion

    #  Ensure param cache is current
    param_cache_written=true

}

get_defaults() {
    #
    #  Defaults for config variables
    #
    #  Variables provided:
    #    default_  variables
    #

    # log_it "get_defaults()"

    default_ping_host="8.8.8.8" #  Default host to ping
    #  how often to report packet loss statistics
    default_ping_count=6
    #  how many ping results to keep in the primary table
    default_history_size=6

    #  Use weighted average over averaging all data points
    default_weighted_average=true
    #  display ^/v prefix if value is increasing/decreasing
    default_display_trend=false
    default_hist_avg_display=false #  Display long term average
    default_run_disconnected=false #  continue to run when no client is connected

    default_level_disp=1   #  display loss if this or higher
    default_level_alert=18 #  this or higher triggers alert color
    default_level_crit=40  #  this or higher triggers critical color

    default_hist_avg_minutes=30 #  Minutes to keep historical average
    default_hist_separator='~'  #  Separaor between current and hist data

    default_color_alert="colour226" # bright yellow
    default_color_crit="colour196"  # bright red
    default_color_bg='black'        #  only used for alert/crit

    default_prefix='|'
    default_suffix='|'

}

get_plugin_params() {
    #
    #  Variables provided:
    #    cfg_  variables
    #

    get_defaults

    # log_it "get_plugin_params()"

    [[ -z "$tmux_vers" ]] && set_tmux_vers

    cfg_ping_host="$(get_tmux_option "@packet-loss-ping_host" \
        "$default_ping_host")"
    cfg_ping_count="$(get_tmux_option "@packet-loss-ping_count" \
        "$default_ping_count")"
    cfg_history_size="$(get_tmux_option "@packet-loss-history_size" \
        "$default_history_size")"

    #
    #  In order to assign a boolean to a variable this two line approach
    #  is needed
    #
    normalize_bool_param "@packet-loss-weighted_average" "$default_weighted_average" &&
        cfg_weighted_average=true || cfg_weighted_average=false
    normalize_bool_param "@packet-loss-display_trend" "$default_display_trend" &&
        cfg_display_trend=true || cfg_display_trend=false
    normalize_bool_param "@packet-loss-hist_avg_display" "$default_hist_avg_display" &&
        cfg_hist_avg_display=true || cfg_hist_avg_display=false
    normalize_bool_param "@packet-loss-run_disconnected" "$default_run_disconnected" &&
        cfg_run_disconnected=true || cfg_run_disconnected=false

    cfg_level_disp="$(get_tmux_option "@packet-loss-level_disp" \
        "$default_level_disp")"
    cfg_level_alert="$(get_tmux_option "@packet-loss-level_alert" \
        "$default_level_alert")"
    cfg_level_crit="$(get_tmux_option "@packet-loss-level_crit" \
        "$default_level_crit")"

    cfg_hist_avg_minutes="$(get_tmux_option \
        "@packet-loss-hist_avg_minutes" "$default_hist_avg_minutes")"
    cfg_hist_separator="$(get_tmux_option \
        "@packet-loss-hist_separator" "$default_hist_separator")"

    cfg_color_alert="$(get_tmux_option "@packet-loss-color_alert" \
        "$default_color_alert")"
    cfg_color_crit="$(get_tmux_option "@packet-loss-color_crit" \
        "$default_color_crit")"
    cfg_color_bg="$(get_tmux_option "@packet-loss-color_bg" \
        "$default_color_bg")"

    cfg_prefix="$(get_tmux_option "@packet-loss-prefix" "$default_prefix")"
    cfg_suffix="$(get_tmux_option "@packet-loss-suffix" "$default_suffix")"

    [[ -z "$cfg_log_file" ]] && {
        cfg_log_file="$(get_tmux_option "@packet-loss-log_file" "")"
        # echo "><> reading cfg_log_file=$cfg_log_file" >>/Users/jaclu/tmp/tmux-packet-loss-t2.log
    }
}

generate_param_cache() {
    #
    #  will also ensure current tmux conf is used, even if other
    #  settings has already been sourced
    #
    $use_param_cache || {
        # log_it "generate_param_cache() - aborted, not using param_cache"
        return
    }
    # log_it "generate_param_cache()"

    get_plugin_params
    param_cache_write
}

get_config() {
    #
    #  The plugin init .tmux script should NOT depend on this!
    #
    #  It should instead directly call generate_param_cache to ensure
    #  the cached configs match current tmux configuration
    #
    #  This is used by everything else sourcing utils.sh, then trusting
    #  that the param cache is valid if found
    #
    local b_d_data_missing=false

    # log_it "get_config()"

    [[ -d "$d_data" ]] || b_d_data_missing=true

    if $use_param_cache; then
        # param_cache missing, create it
        [[ -s "$f_param_cache" ]] || generate_param_cache

        # the SC1091 is needed to pass linting when use_param_cache is off
        # shellcheck source=data/param_cache disable=SC1091
        source "$f_param_cache"
    else
        get_plugin_params
    fi

    $skip_logging && unset cfg_log_file

    $b_d_data_missing && {
        local stray_monitors

        mkdir -p "$d_data"
        log_it "data/ was missing"
        get_tmux_pid >"$pidfile_tmux" # helper for show_settings.sh

        #
        #  If data dir was removed whilst a monitor was running,
        #  there is a risk running monitors will mess things up,
        #  the running monitor can't be killed via pidfile.
        #  Do it manually.
        #
        stray_monitors="$(pgrep -f "$scr_monitor")"
        [[ -n "$stray_monitors" ]] && {
            echo "$stray_monitors" | xargs kill
            log_it "Manually killed stray monitors[$stray_monitors]"
        }

        log_it "data/ is restored"
    }
}

#---------------------------------------------------------------
#
#   Other
#
#---------------------------------------------------------------

relative_path() {
    # remove D_TPL_BASE_PATH prefix

    # log_it "relative_path($1)"

    #  shellcheck disable=SC2001
    echo "$1" | sed "s|^$D_TPL_BASE_PATH/||"
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

    _pf_log "random_sleep($max_sleep, $min_sleep)"

    # multiply ny hundred, round to int
    min_sleep=$(printf "%.0f" "$(echo "$min_sleep * 100" | bc)")
    max_sleep=$(printf "%.0f" "$(echo "$max_sleep * 100" | bc)")

    # Generate random numbers
    rand_from_random=$((RANDOM % 100))
    rand_from_urandom=$(od -An -N2 -i /dev/urandom | awk '{print $1}')

    # Calculate random number between min_sleep and max_sleep with two decimal places
    random_integer=$(((rand_from_random + rand_from_urandom + pid) % (max_sleep - min_sleep + 1) + min_sleep))

    # Calculate the sleep time with two decimal places
    sleep_time=$(printf "%.2f" "$(echo "scale=2; $random_integer / 100" | bc)")

    # log_it "><> Sleeping for $sleep_time seconds"
    sleep "$sleep_time"
}

prepare_environment() {
    #
    #  For actions in utils log_prefix gets an u- prefix
    #  using local ensures it goes back to its original setting once
    #  code is run from the caller.
    #
    local log_prefix="u-$log_prefix"

    plugin_name="tmux-packet-loss"

    #  Should have been set in the calling script
    [[ -z "$D_TPL_BASE_PATH" ]] && {
        echo
        echo "ERROR: $plugin_name D_TPL_BASE_PATH is not defined!"
        echo
        exit 1
    }
    #  check one item to verify D_TPL_BASE_PATH
    [[ -f "$D_TPL_BASE_PATH"/scripts/monitor_packet_loss.sh ]] || {
        echo
        echo "ERROR: $plugin_name D_TPL_BASE_PATH seems invalid: [$D_TPL_BASE_PATH]"
        echo
        exit 1
    }

    #
    #  Sanity check that DB structure is current, if not it will be replaced
    #
    db_version=12

    #
    #  DB should be updated every $cfg_ping_count seconds, if it hasn't
    #  been changed in a while monitor is most likely not running, or has
    #  gotten stuck. Restarting it should solve the issue.
    #  Since this script is run at regular intervals, it is a good place
    #  to ensure it is operational.
    #
    db_max_age_mins=2

    log_indent=1 # check pidfile_handler.sh to see how this is used

    #
    #  I use an env var TMUX_BIN to point at the current tmux, defined in my
    #  tmux.conf, in order to pick the version matching the server running.
    #  This is needed when checking backwards compatibility with various versions.
    #  If not found, it is set to whatever is in path, so should have no negative
    #  impact. In all calls to tmux I use $TMUX_BIN instead in the rest of this
    #  plugin.
    #
    [[ -z "$TMUX_BIN" ]] && TMUX_BIN="tmux"

    #
    #  Convert script name to full actual path notation the path is used
    #  for caching, so save it to a variable as well
    #
    current_script="$(basename "$0")" # name without path
    d_current_script="$(dirname -- "$(realpath -- "$0")")"
    f_current_script="$d_current_script/$current_script"

    d_scripts="$D_TPL_BASE_PATH"/scripts
    d_data="$D_TPL_BASE_PATH"/data # location for all runtime data
    d_ping_issues="$d_data"/ping_issues

    #
    #  Shortands for some scripts that are called in various places
    #
    scr_prepare_db="$d_scripts"/prepare_db.sh
    scr_ctrl_monitor="$d_scripts"/ctrl_monitor.sh
    scr_display_losses="$d_scripts"/display_losses.sh
    scr_monitor="$d_scripts"/monitor_packet_loss.sh
    scr_pidfile_handler="$d_scripts"/pidfile_handler.sh

    #
    #  These files are assumed to be in the directory data
    #
    f_log_date="$d_data"/log_date
    f_param_cache="$d_data"/param_cache
    f_previous_loss="$d_data"/previous_loss
    f_sqlite_error="$d_data"/sqlite.err
    f_monitor_suspended_no_clients="$d_data"/no_clients
    f_sqlite_db="$d_data"/packet_loss.sqlite
    f_do_not_run="$d_data"/do_not_run

    pidfile_ctrl_monitor="$d_data"/ctrl_monitor.pid
    pidfile_monitor="$d_data"/monitor.pid

    #
    #  This one is just kept for show_settings.sh, in order to verify
    #  that the process running it is using the "right" tmux-packet-loss
    #  folder, if not an error is displayed.
    #
    pidfile_tmux="$d_data"/tmux.pid

    #  lists each time display_losses had to restart monitor
    db_restart_log="$d_data"/db_restarted.log

    param_cache_written=false

    #
    #  Set to defaults unless overridden (mostly) for debug purposes
    #
    [[ -z "$skip_time_elapsed" ]] && {
        # creates a lot of overhead so should normally be true
        skip_time_elapsed=true
    }
    [[ -z "$use_param_cache" ]] && {
        use_param_cache=true # makes gathering the params a lot faster!
    }
    [[ -z $log_interactive_to_stderr ]] && log_interactive_to_stderr=false
    [[ -z "$skip_logging" ]] && {
        # if true @packet-loss-log_file setting is ignored
        skip_logging=false
    }

    [[ -z "$log_sql" ]] && {
        #
        #  Defaults to false
        #  if true all SQL queries are logged
        #
        log_sql=false
    }

    #
    #  at this point plugin_params is trusted if found, menus.tmux will
    #  always always replace it with current tmux conf during plugin init
    #
    get_config
}

#===============================================================
#
#   Main
#
#===============================================================

#
#  Identifies the script triggering a log entry.
#  Since it is set outside main() this will remain in effect for
#  modules that didn't set it, during utils:main a prefix "u-" will be
#  added to show the log action happened as utils was sourced.
#
[[ -z "$log_prefix" ]] && log_prefix="???"

#---------------------------------------------
#
#   debugging overrides
#
#---------------------------------------------

#
#  Setting it here will allow for debugging utils setting up the env.
#  Not needed for normal usage of logging.
#
# cfg_log_file="$HOME/tmp/tmux-packet-loss-t2.log"

#
#  When this is used, a cfg_log_file must still be defined, since
#  log_it aborts if no cfg_log_file is defined.
#  Further non-interactive tasks will always use cfg_log_file
#
# log_interactive_to_stderr=true

# do_pidfile_handler_logging=true # will create ridiculous amounts of logs
# skip_logging=true # enforce no logging desipte tmux conf

#
# if true all SQL queries are logged - defaults to false
#
# log_sql=true

#
#  Disable caching
#
# use_param_cache=false

prepare_environment
