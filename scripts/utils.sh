#!/bin/sh
#  shellcheck disable=SC2034
#
#   Copyright (c) 2022-2025: Jacob.Lundqvist@gmail.com
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
    [ -z "$cfg_log_file" ] && return #  early abort if no logging
    #
    #  If @packet-loss-log_file is defined, it will be read into the
    #  cfg_log_file variable and used for logging.
    #
    #  Logging should normally be disabled, since it causes some overhead.
    #

    $log_interactive_to_stderr && [ -t 0 ] && {
        # printf "log: %s%*s%s\n" "$log_prefix" "$log_indent" "" "$@" >/dev/stderr
        printf "log: %s %s\n" "$log_prefix" "$@" >/dev/stderr
        return
    }

    _li_prefix="$(date +'%F %T') [$$] $log_prefix"
    printf '%s %s\n' "$_li_prefix" "$@" >>"$cfg_log_file" 2>/dev/null
}

error_msg() {
    #
    #  Display $1 as an error message in log and in a scrollback buffer
    #  unless _em_do_display_message is false
    #
    #  If exit_code is set to -1, process is not exited
    #
    _em_msg="$1"
    _em_exit_code="${2:-1}"
    _em_do_display_message="${3:-true}"

    if $log_interactive_to_stderr && [ -t 0 ]; then
        echo "ERROR: $_em_msg" >/dev/stderr
    else
        log_it
        log_it "ERROR: $_em_msg"
        log_it

        err_display="\nplugin: $plugin_name:$current_script [$$] - ERROR:\n\n"
        err_display="${err_display}${_em_msg}\n\nPress ESC to close this display"
        if [ -n "$TMUX" ]; then
            $_em_do_display_message && $TMUX_BIN run-shell "printf \"$err_display\""
        else
            # shellcheck disable=SC2059 # allow formatted error msgs
            printf "$err_display" >/dev/stderr
        fi
    fi
    [ "$_em_exit_code" -gt -1 ] && exit "$_em_exit_code"
}

save_ping_issue() {
    #
    #  Save a ping output for later inspection
    #
    _spi_ping_output="$1"

    [ -d "$d_ping_issues" ] || mkdir -p "$d_ping_issues"
    _spi_iso_datetime=$(date +'%Y-%m-%d_%H:%M:%S')
    _spi_f_ping_issue="$d_ping_issues/$_spi_iso_datetime"
    log_it "Saving ping issue at: $_spi_f_ping_issue"
    echo "$_spi_ping_output" >"$_spi_f_ping_issue" || {
        error_msg "Failed to save ping issue"
    }
}

do_not_run_create() {
    log_it "do_not_run_create()"
    # Set an indication that system is unable to run
    _dnrc_reason="$1"
    [ -d "$d_data" ] || mkdir -p "$d_data"
    echo "$_dnrc_reason" >"$f_do_not_run"
    log_it "Do-not-run condition activated: $_dnrc_reason"
}

do_not_run_check() {
    # Aborts with reason if f_do_not_run is present
    [ -f "$f_do_not_run" ] && {
        _msg="ERROR: plugin is in a do_not_run state:"
        echo "$_msg"
        log_it "$_msg"
        cat "$f_do_not_run"
        exit 1
    }
}

#---------------------------------------------------------------
#
#   Datatype handling
#
#---------------------------------------------------------------

is_bool() {
    case "$1" in
        true | false) return 0 ;;
        *) ;;
    esac
    return 1
}

is_float() {
    _if_input=$1

    if awk -v val="$_if_input" '
        BEGIN {
            pat="^[-+]?[0-9]+(\\.[0-9]*)?([eE][-+]?[0-9]+)?$|^[-+]?\\.[0-9]+([eE][-+]?[0-9]+)?$"
            exit !(val ~ pat)
        }'; then

        return 0
    fi
    return 1
}

lowercase_it() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_bool_param() {
    #
    #  If _nbp_param starts with "@", assume it is tmux variable name, thus
    #  read its value from the tmux environment.
    #  In this case $3 must be given as the default value!
    #
    # log_it "normalize_bool_param() [$1] [$2] [$3]"
    _nbp_param="$1"
    _nbp_var_name="$2"
    _nbp_tmux_default="$3"

    [ "${_nbp_param%"${_nbp_param#?}"}" = "@" ] && {
        # log_it "normalize_bool_param($_nbp_param) - is tmux variable"
        #
        #  If it starts with "@", assume it is tmux variable name, thus
        #  read its value from the tmux environment.
        #  In this case $2 must be given as the default value!
        #
        [ -z "$_nbp_tmux_default" ] && {
            error_msg "normalize_bool_param($_nbp_param) - no default"
        }
        # replace with actual value
        _nbp_param=$(get_tmux_option "$_nbp_param" "$_nbp_tmux_default")
    }

    case $(lowercase_it "$_nbp_param") in
        #
        #  First handle the unfortunate tradition by tmux to use
        #  1 to indicate selected / active.
        #  This means 1 is 0 and 0 is 1, how Orwellian...
        #
        1 | yes | true)
            #  Be a nice guy and accept some common positive notations
            _nbp_result=true
            _nbp_return=0
            ;;

        0 | no | false)
            #  Be a nice guy and accept some common false notations
            _nbp_result=false
            _nbp_return=1
            ;;

        *)
            if [ -n "$_nbp_var_name" ]; then
                _nbp_prefix="$_nbp_var_name=$_nbp_param"
            else
                _nbp_prefix="$_nbp_param"
            fi
            _nbp_msg="normalize_bool_param($_nbp_param) \n"
            _nbp_msg="${_nbp_msg}${_nbp_prefix} - should be yes/true/1 or no/false/0\n"
            _nbp_msg="${_nbp_msg}was: $_nbp_result"
            error_msg "$_nbp_msg"
            ;;

    esac

    [ -n "$_nbp_var_name" ] && {
        # if variable name provided set it to _nbp_result
        eval "$_nbp_var_name=\"\$_nbp_result\""
    }

    # Should never get here...
    return "$_nbp_return"
}

db_seems_inactive() {
    #
    #  New records should normally be written to the DB every cfg_ping_count
    #  seconds. If it hasn't happened, it can be assumed that the monitor
    #  is no longer opertating normally.
    #  To allow for disabling the monitor shorter periods for example
    #  when using scripts/test_data.sh, wait a couple of minutes before
    #  restart (db_max_age_mins).
    #
    # log_it "db_seems_inactive()"
    [ -f "$f_sqlite_db" ] || return 0 # db not available
    [ -n "$(find "$f_sqlite_db" -mmin +"$db_max_age_mins")" ]
}

#---------------------------------------------------------------
#
#   sqlite
#
#---------------------------------------------------------------

sqlite_err_handling() {
    #
    #  param 1 is SQL statement
    #  param 2 is exit on error - defaults to true
    #
    #  Loggs sqlite errors to $f_sqlite_error
    #
    #  Variables provided:
    #    sqlite_result    - Output from query
    #    sqlite_exit_code - exit code for latest sqlite3 action
    #                       if _seh_exit_on_error is false

    # log_it "sqlite_err_handling() [$1] [$2]"

    _seh_sql="$1"
    _seh_exit_on_error="${2:-yes}"
    if $log_sql; then # set to true to log sql queries
        log_it "SQL: $_seh_sql"
    fi

    if normalize_bool_param "$_seh_exit_on_error"; then
        _seh_error_exit=1
        _seh_display_error=false
    else
        _seh_error_exit=-1
        _seh_display_error=true
    fi

    if [ "$cfg_sql_timeout" -gt 0 ]; then
        # log_it "sqlite .timeout: $cfg_sql_timeout"
        sqlite_result="$(
            sqlite3 \
                -cmd ".timeout $cfg_sql_timeout" \
                "$f_sqlite_db" \
                "$_seh_sql" \
                2>"$f_sqlite_error"
        )"
        sqlite_exit_code=$?
    else
        sqlite_result="$(sqlite3 "$f_sqlite_db" "$_seh_sql" 2>"$f_sqlite_error")"
        sqlite_exit_code=$?
    fi

    case "$sqlite_exit_code" in
        0) ;; # no error
        *)
            [ ! -s "$f_sqlite_db" ] && [ -f "$f_sqlite_db" ] && {
                #
                #  If DB was removed, then a sql action would fail but lead
                #  to an empty DB. By removing such, next call to
                #  display-losses will recreate it and restart monitoring
                #
                rm -f "$f_monitor_suspended_no_clients"
                rm -f "$f_sqlite_db"
                error_msg "Removing empty DB, terminating monitor" \
                    "$_seh_error_exit" false
            }
            err_msg="sqlite_err_handling()  - error code: $sqlite_exit_code\n"
            err_msg="${err_msg}  $(cat "$f_sqlite_error")\n"
            # err_msg="${err_msg}  SQL:\n$_seh_sql"
            error_msg "$err_msg" "$_seh_error_exit" "$_seh_display_error"
            ;;
    esac

    log_sql=false # disable logging after each call
    return "$sqlite_exit_code"
}

sqlite_transaction() {
    # log_it "sqlite_transaction() [$1] [$2]"

    _st_sql_original="$1"
    _st_exit_on_error="${2:-yes}"

    _st_sql="
        BEGIN TRANSACTION; -- Start the transaction
        $_st_sql_original ;
        COMMIT; -- Commit the transaction"
    sqlite_err_handling "$_st_sql" "$(normalize_bool_param "$_st_exit_on_error")"

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
    #    sqlite_result - current loss, weigted/average depending on $2 true/false
    #
    # log_it "sql_current_loss() [$1]"
    _scl_use_reactive="$1"
    [ -z "$_scl_use_reactive" ] && {
        error_msg "Call to sql_current_loss() without param"
    }

    if normalize_bool_param "$_scl_use_reactive"; then
        #
        # To make loss more sensitive to recent spikes while allowing them to decay,
        # it is displayed as the largest of:
        #    last value
        #    avg of last 2
        #    avg of last 3
        #    avg of last 4
        #    ...
        #
        _sck_sql="
SELECT max(
"
        _sck_i=1
        while [ "$_sck_i" -lt "$cfg_history_size" ]; do
            _sck_sql="$_sck_sql  (SELECT avg(loss) FROM(
    SELECT loss FROM t_loss ORDER BY ROWID DESC limit $_sck_i  )),
"
            _sck_i=$((_sck_i + 1))
            [ "$_sck_i" -gt 100 ] && {
                # run-away loop
                error_msg "run-away loop"
            }
        done
        # last item, average of all items in t_loss
        _sck_sql="$_sck_sql  (SELECT avg(loss) FROM t_loss)
)"
    else
        _sck_sql="SELECT avg(loss) FROM t_loss"
    fi
    sqlite_err_handling "$_sck_sql" || {
        log_it "=====   SHOULD NEVER GET HERE!   ====="
        log_it "sql_current_loss($_scl_use_reactive) [$sqlite_result]"
    }
}

#---------------------------------------------------------------
#
#   tmux env handling
#
#---------------------------------------------------------------

is_tmux_option_defined() {
    [ -n "$TMUX" ] || return 1 # abort false if not inside a tmux session
    $TMUX_BIN show-options -g | grep -q "^$1"
}

get_tmux_option() {
    _gto_opt="$1"
    _gto_def="$2"

    [ -z "$_gto_opt" ] && error_msg "get_tmux_option() param 1 empty!"
    [ "$TMUX" = "" ] && {
        # this is run standalone, just report the defaults
        echo "$_gto_def"
        return
    }

    if _gto_value="$($TMUX_BIN show-options -gv "$_gto_opt" 2>/dev/null)"; then
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
        [ -z "$_gto_value" ] && ! is_tmux_option_defined "$_gto_opt" && {
            #
            #  This is a workaround, checking if the variable is defined
            #  before assigning the default, preserving intentional
            #  "" assignments
            #
            _gto_value="$_gto_def"
        }
    else
        #  All other versions correctly fails on unassigned @options
        _gto_value="$_gto_def"
    fi

    echo "$_gto_value"
}

get_tmux_pid() {
    tmux_pid=$(echo "$TMUX" | cut -d',' -f 2)
    [ -z "$tmux_pid" ] && error_msg "Failed to extract pid for tmux process!"
    # log_it "get_tmux_pid() - found $tmux_pid"
    echo "$tmux_pid"
}

#---------------------------------------------------------------
#
#   param cache handling
#
#---------------------------------------------------------------

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
    #  how many ping results to keep in the primary table for approx 30s cut-off
    default_history_size=7

    # To make loss more sensitive to recent spikes while allowing them to decay
    default_reactive=true
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
    # log_it "get_plugin_params()"

    get_defaults

    cfg_ping_host="$(get_tmux_option "@packet-loss-ping_host" \
        "$default_ping_host")"
    cfg_ping_count="$(get_tmux_option "@packet-loss-ping_count" \
        "$default_ping_count")"
    cfg_history_size="$(get_tmux_option "@packet-loss-history_size" \
        "$default_history_size")"

    #
    #  2026-06-14
    #
    #  Compatibility handling for renamed option:
    #    @packet-loss-weighted_average  ->  @packet-loss-reactive
    #
    #  Precedence rules:
    #    1. If @packet-loss-weighted_average is set, its value is used as the
    #       default for @packet-loss-reactive (backward compatibility).
    #    2. If both are set, @packet-loss-reactive takes precedence.
    #    3. If only @packet-loss-reactive is set, it is used as-is.
    #
    #  This ensures:
    #    - old configs continue working unchanged
    #    - new configs behave as documented
    #    - mixed configs prefer the new option
    #
    is_tmux_option_defined "@packet-loss-weighted_average" && {
        normalize_bool_param "@packet-loss-weighted_average" obsolete_param \
            "$default_reactive"

        # shellcheck disable=SC2154 # obsolete_param defined above via eval
        default_reactive="$obsolete_param"
    }
    normalize_bool_param "@packet-loss-reactive" cfg_reactive "$default_reactive"

    normalize_bool_param "@packet-loss-display_trend" cfg_display_trend \
        "$default_display_trend"
    normalize_bool_param "@packet-loss-hist_avg_display" cfg_hist_avg_display \
        "$default_hist_avg_display"
    normalize_bool_param "@packet-loss-run_disconnected" cfg_run_disconnected \
        "$default_run_disconnected"
    cfg_level_disp="$(get_tmux_option "@packet-loss-level_disp" "$default_level_disp")"
    cfg_level_alert="$(get_tmux_option "@packet-loss-level_alert" "$default_level_alert")"
    cfg_level_crit="$(get_tmux_option "@packet-loss-level_crit" "$default_level_crit")"

    cfg_hist_avg_minutes="$(get_tmux_option \
        "@packet-loss-hist_avg_minutes" "$default_hist_avg_minutes")"
    cfg_hist_separator="$(get_tmux_option \
        "@packet-loss-hist_separator" "$default_hist_separator")"

    cfg_color_alert="$(get_tmux_option "@packet-loss-color_alert" "$default_color_alert")"
    cfg_color_crit="$(get_tmux_option "@packet-loss-color_crit" "$default_color_crit")"
    cfg_color_bg="$(get_tmux_option "@packet-loss-color_bg" "$default_color_bg")"

    cfg_prefix="$(get_tmux_option "@packet-loss-prefix" "$default_prefix")"
    cfg_suffix="$(get_tmux_option "@packet-loss-suffix" "$default_suffix")"

    [ -z "$cfg_log_file" ] && {
        cfg_log_file="$(get_tmux_option "@packet-loss-log_file" "")"
    }
}

param_cache_write() {
    log_it "param_cache_write()"
    # extra check, to ensure nothing is written if param cache is not used
    $use_param_cache || {
        log_it "param_cache_write() - aborted, not using param_cache"
        return
    }
    [ -d "$d_data" ] || mkdir -p "$d_data"

    # shellcheck disable=SC2154 # variables below defined via eval
    cat <<EOF >"$f_param_cache"
#
# param cache - This is used to avoid having to poll tmux for config variables
# each time any script in this plugin is run.
# If removed, it will automatically be re-created, by polling from tmux
#
cfg_ping_host="$cfg_ping_host"
cfg_ping_count="$cfg_ping_count"
cfg_history_size="$cfg_history_size"

cfg_reactive="$cfg_reactive"
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

cfg_log_file="$cfg_log_file"

#
# Not derived from tmux variables, if .sql-timeout is found in the repo top folder,
# this overrides the default timeout value. If set to 0 no timeout is used.
#
cfg_sql_timeout="$cfg_sql_timeout"

EOF
    #endregion

    #  Ensure param cache is current
    param_cache_written=true

}

generate_param_cache() {
    #
    #  will ensure current tmux conf is used
    #
    get_plugin_params
    f_sql_timeout="$D_TPL_BASE_PATH"/.sql-timeout
    [ -f "$f_sql_timeout" ] && cfg_sql_timeout=$(cat "$f_sql_timeout")
    param_cache_write

    # Stop monitor if active, ensuring any temporary cache changes are no longer used.
    rm -f "$pidfile_monitor" || err_msg "Failed to remove: $pidfile_monitor"
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
    # log_it "get_config()"

    b_d_data_missing=false

    [ -d "$d_data" ] || b_d_data_missing=true

    if $use_param_cache; then
        # if f_param_cache is missing, create it
        [ -s "$f_param_cache" ] || generate_param_cache

        # the SC1091 is needed to pass linting when the param-cache has
        # not yet been generated
        # shellcheck source=data/param-cache disable=SC1091
        . "$f_param_cache"
    else
        get_plugin_params # Use defaults
    fi

    $skip_logging && unset cfg_log_file

    $b_d_data_missing && {
        [ -d "$d_data" ] || mkdir -p "$d_data"
        log_it "data/ was missing"
        get_tmux_pid >"$pidfile_tmux" # helper for show-settings.sh

        #
        #  If data dir was removed whilst a monitor was running,
        #  there is a risk running monitors will mess things up,
        #  the running monitor can't be killed via pidfile.
        #  Do it manually.
        #
        _gc_stray_monitors="$(pgrep -f "$f_monitor")"
        [ -n "$_gc_stray_monitors" ] && {
            echo "$_gc_stray_monitors" | xargs kill
            log_it "Manually killed stray monitors[$_gc_stray_monitors]"
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

prepare_environment() {
    #
    #  For actions in utils _pe_log_prefix gets an u- prefix
    #  using local ensures it goes back to its original setting once
    #  code is run from the caller.
    #
    _pe_log_prefix="u-$_pe_log_prefix"

    plugin_name="tmux-packet-loss"

    #  Should have been set in the calling script
    [ -z "$D_TPL_BASE_PATH" ] && {
        echo
        echo "ERROR: $plugin_name D_TPL_BASE_PATH is not defined!"
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

    #
    # Set to true per call to sqlite_err_handling, to enable logging of that call
    # this is disabled again at the end of the call
    #
    log_sql=false

    # log_indent=1 # check pidfile-handler.sh to see how this is used

    #
    #  I use an env var TMUX_BIN to point at the current tmux, defined in my
    #  tmux.conf, in order to pick the version matching the server running.
    #  This is needed when checking backwards compatibility with various versions.
    #  If not found, it is set to whatever is in path, so should have no negative
    #  impact. In all calls to tmux I use $TMUX_BIN instead in the rest of this
    #  plugin.
    #
    [ -z "$TMUX_BIN" ] && TMUX_BIN="tmux"

    #
    #  Convert script name to full actual path notation the path is used
    #  for caching, so save it to a variable as well
    #

    current_script="${0##*/}" # same but faster than "$(basename "$0")"

    d_current_script="$(dirname -- "$(realpath -- "$0")")"
    f_current_script="$d_current_script/$current_script"

    d_scripts="$D_TPL_BASE_PATH"/scripts
    d_data="$D_TPL_BASE_PATH"/data # location for all runtime data
    d_ping_issues="$d_data"/ping-issues

    #
    #  Shortands for some scripts that are called in various places
    #
    f_prepare_db="$d_scripts"/prepare-db.sh
    f_ctrl_monitor="$d_scripts"/ctrl-monitor.sh
    f_display_losses="$d_scripts"/display-losses.sh
    f_monitor="$d_scripts"/monitor-packet-loss.sh
    f_pidfile_handler="$d_scripts"/pidfile-handler.sh

    #  check one item that should be there, to verify D_TPL_BASE_PATH
    [ -f "$f_monitor" ] || {
        echo
        echo "ERROR: $plugin_name D_TPL_BASE_PATH seems invalid: [$D_TPL_BASE_PATH]"
        echo
        exit 1
    }

    #
    #  These files are assumed to be in the directory data
    #
    f_param_cache="$d_data"/param-cache      # to reduce overhead tmux params are only read once
    f_do_not_run="$d_data"/do-not-run        # dependency or other issue making plugin unusable
    f_sqlite_db="$d_data"/packet-loss.sqlite # the actual DB
    f_sqlite_error="$d_data"/sqlite.err      # contains latest sql error msg if any
    f_previous_loss="$d_data"/previous_loss  # used if @packet-loss-display_trend is true

    f_log_date="$d_data"/log-date                       # ensure date is only printed once in log file
    f_monitor_suspended_no_clients="$d_data"/no-clients # monitor exited due to no tmux clients

    pidfile_monitor="$d_data"/monitor.pid # used to ensure only one monitor is running

    #
    #  This one is just kept for show-settings.sh, in order to verify
    #  that the process running it is using the "right" tmux-packet-loss
    #  folder, if not an error is displayed.
    #
    pidfile_tmux="$d_data"/tmux.pid

    #  lists each time display-losses had to restart monitor
    db_restart_log="$d_data"/db-restarted.log

    param_cache_written=false

    #
    #  Set to defaults unless overridden (mostly) for debug purposes
    #
    [ -z "$skip_time_elapsed" ] && {
        # creates a lot of overhead so should normally be true
        skip_time_elapsed=true
    }
    [ -z "$use_param_cache" ] && {
        # unless overridden elsewhere, assume cache should be used
        use_param_cache=true # makes gathering the params a lot faster!
    }
    [ -z "$log_interactive_to_stderr" ] && log_interactive_to_stderr=false
    [ -z "$skip_logging" ] && {
        # if true @packet-loss-log_file setting is ignored
        skip_logging=false
    }

    cfg_sql_timeout=200 # store deviating timeout in <repo folder>/.sql-timeout
    #
    #  at this point plugin_params is trusted if found, menus.tmux will
    #  always always replace it with current tmux conf during plugin init
    #
    get_config

    do_not_run_check
}

clear_previous_losses() {
    rm -f "$f_previous_loss" || error_msg "Failed to remove: $f_previous_loss"
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
[ -z "$log_prefix" ] && log_prefix="???"

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

# Pad5 debug
# [ "$(tty)" = "/dev/pts/3" ] && log_interactive_to_stderr=true

# do_pidfile_handler_logging=true # will create ridiculous amounts of logs
# skip_logging=true # enforce no logging desipte tmux conf

#
#  Disable caching globally
#
# use_param_cache=false

prepare_environment
