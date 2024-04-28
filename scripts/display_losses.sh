#!/usr/bin/env bash
#
#   Copyright (c) 2022-2024: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-packet-loss
#
#   Reports current packet loss status for the plugin
#

script_exit() {
    #
    #  wrap status in prefix/suffix and exit gracefully
    #
    local status="$1"

    [[ -n "$status" ]] && {
        # log_it "should not have pre/suf  $status"
        echo "${cfg_prefix}${status}${cfg_suffix}"
    }
    [[ -n "$2" ]] && {
        error_msg "script_exit() got 2nd unexpected param[$2]"
    }
    exit 0
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
        date +%s.%N
    fi
}

restart_monitor() {
    log_it "restarting monitor"
    date >>"$db_restart_log" # log current time

    $scr_ctrl_monitor
}

verify_db_status() {
    #
    #  Some sanity check, ensuring the monitor is running
    #
    local db_was_ok=true

    if [[ ! -e "$sqlite_db" ]]; then
        db_was_ok=false
        log_it "DB missing"

        #
        #  If DB is missing, try to start the monitor
        #
        restart_monitor
        log_it "DB missing - restart is done"

        [[ -e "$sqlite_db" ]] || {
            log_it "DB still missing - aborting"
            script_exit "DB missing"
        }
    elif [[ -n "$(find "$sqlite_db" -mmin +1)" ]]; then
        db_was_ok=false
        log_it "DB is over one minute old"
        #
        #  If DB is over a minute old,
        #  assume the monitor is not running, so (re-)start it
        #
        restart_monitor
        log_it "no db updates for one minute - restart is done"
    fi
    display_time_elapsed "$t_start" "verify_db_status($db_was_ok)"
}

get_current_loss() {
    #
    #  public variables defined
    #   current_loss
    #
    local sql
    local err_code
    local msg

    if param_as_bool "$cfg_weighted_average"; then
        #
        #  To give loss a declining history weighting,
        #  it is displayed as the largest of:
        #    last value
        #    avg of last 2
        #    avg of last 3
        #    avg of last 4
        #    ...
        #    avg of last minute
        #
        sql="max(
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

    sql="SELECT CAST(( $sql + 0.499 ) AS INTEGER)"
    current_loss="$(sqlite_err_handling "$sql")" || {
        err_code=$?
        [[ "$err_code" = 5 ]] && {
            msg="DB locked"
            log_it "---------------------  $msg"
            script_exit "$msg"
        }
        error_msg \
            "sqlite3[$err_code] when retrieving current losses" \
            1 false
    }
    display_time_elapsed "$t_start" "get_current_loss()"
}

get_prev_loss() {
    if [[ -f "$f_previous_loss" ]]; then
        read -r prev_loss <"$f_previous_loss"
    else
        prev_loss=0
    fi
}

show_trend() {
    #
    #  Indicate if losses are increasing / decreasing setting +/- prefix
    #
    #  public variables provided
    #    prev_loss
    #
    [[ -z "$prev_loss" ]] && get_prev_loss

    if [[ "$prev_loss" -ne "$current_loss" ]]; then
        if [[ "$current_loss" -gt "$prev_loss" ]]; then
            result="+$current_loss"
        elif [[ "$current_loss" -lt "$prev_loss" ]]; then
            result="-$current_loss"
        fi
    fi
    display_time_elapsed "$t_start" "show_trend($result)"
}

colorize_high_numbers() {
    #
    #  If loss is over trigger levels, display in appropriate color
    #
    local number="$1" # numerical value to check
    local item="$2"   # string that might get color

    if awk -v val="$number" -v trig_lvl="$cfg_level_crit" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        item="#[fg=$cfg_color_crit,bg=$cfg_color_bg]${item}#[default]"
    elif awk -v val="$number" -v trig_lvl="$cfg_level_alert" \
        'BEGIN{exit !(val >= trig_lvl)}'; then

        item="#[fg=$cfg_color_alert,bg=$cfg_color_bg]${item}#[default]"
    fi
    echo "$item"
    display_time_elapsed "$t_start" "colorize_high_numbers()"
}

display_history() {
    #
    #  Display history
    #
    #  Outside variables modified:
    #    s_log_msg - will be used by main to display current losses
    #
    local sql
    local avg_loss_raw
    local err_code
    local msg
    local avg_loss

    sql="SELECT CAST((SELECT AVG(loss) FROM t_stats) + .499 AS INTEGER)"
    avg_loss_raw="$(sqlite_err_handling "$sql")" || {
        err_code=$?
        msg="when retrieving history"
        if [[ "$err_code" = 5 ]]; then
            log_it "DB locked $msg"
        else
            #  log the issue as an error, then continue
            error_msg "sqlite3[$err_code] $msg" 0 false
        fi
        return
    }
    if [[ "$avg_loss_raw" != "0" ]]; then
        #
        #  If stats is over trigger levels, display in appropriate color
        #
        avg_loss="$(
            colorize_high_numbers "$avg_loss_raw" "$avg_loss_raw"
        )"
        result="${result}${cfg_hist_separator}${avg_loss}"
        s_log_msg="$s_log_msg   avg: $avg_loss_raw"
    fi
    display_time_elapsed "$t_start" "display_history($avg_loss_raw)"
}

handle_loss_changes() {

    [[ -z "$prev_loss" ]] && get_prev_loss

    if [[ "$current_loss" -gt 0 ]]; then
        echo "$current_loss" >"$f_previous_loss"
    else
        rm -f "$f_previous_loss"
    fi

    # log changes
    [[ "$prev_loss" -ne "$current_loss" ]] &&
        {
            if [[ "$current_loss" -gt 0 ]]; then
                log_it "$s_log_msg"
            else
                log_it "no packet losses"
            fi
        }
}

#===============================================================
#
#   Main
#
#===============================================================

#
#  Debug tools, if skip_time_elapsed is set to false, time elapsed
#  since t_start can be logged by calling display_time_elapsed
#
#skip_time_elapsed=false
$skip_time_elapsed || t_start="$(safe_now)"

#
#  Prevent tmux from running it every couple of seconds,
#  convenient during debugging
#
# [[ "$1" != "hepp" ]] && exit 0

D_TPL_BASE_PATH=$(dirname "$(dirname -- "$(realpath "$0")")")
log_prefix="dsp"

#  shellcheck source=scripts/utils.sh
. "$D_TPL_BASE_PATH"/scripts/utils.sh

$skip_time_elapsed || {
    log_it
    display_time_elapsed "$t_start" "script initialized"
}

result="" # indicating no losses

verify_db_status

get_current_loss

[[ "$current_loss" -lt "$cfg_level_disp" ]] && current_loss=0

s_log_msg="loss: $current_loss" # might get altered by display_history

if [[ "$current_loss" -gt 0 ]]; then
    result="$current_loss"

    #
    #  Check trend, ie change since last update
    #
    param_as_bool "$cfg_display_trend" && show_trend

    result="$(colorize_high_numbers "$current_loss" "$result")"

    param_as_bool "$cfg_hist_avg_display" && display_history

    #
    #  Set prefix & suffix for result and report to status bar
    #
    echo "${cfg_prefix}${result}${cfg_suffix}"
fi

handle_loss_changes

display_time_elapsed "$t_start" "display_losses.sh"
