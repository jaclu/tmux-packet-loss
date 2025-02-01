#!/bin/sh
#
#   Copyright (c) 2024-2025: Jacob.Lundqvist@gmail.com
#   License: MIT
#
_tpt_release="2025-02-01 v5"
#
#   Checks running tmux version and can do dependency checks, the latter part
#   is mostly for tmux-plugins etc
#
# To make this safer to include in other code, functions and variables
# believed to be of use outside this are prefixed with tpt_
# except for tmux_vers_ok
# all other variables use _ prefix to clearly list them as temporary.
# This should ensure this will not collide with any other namespaces.
#
# Dependency check Usage:
#
#  1. if the version checker is also desired th better option is to source this
#     to get both functionalities:
#
#    . path/to/tmux-plugin-tools.sh
#    tpt_dependency_check "ruby fzf" || exit 1
#    tmux_vers_ok 3.2 && {
#        # tmux display-popup can be used
#    }
#
#  2. In case only dependency check is needed, it can be called directly.
#     Use something like this in the plugin init script - usually with
#     a .tmux suffix.
#
#    path/to/tmux-plugin-tools.sh dependency-check "ruby fzf" || exit 1
#
# Env variables that can be set:
#   tpt_debug_mode - if set to 1 tpt_dependency_check will print progress to /dev/stderr
#
# Variables defined, that might be useful outside of this:
#   tpt_missing_dependencies - Lists all failed dependencies found
#
# The following will only be set if this was sourced by a script running inside
# a tmux plugin, otherwise unset
#   tpt_d_plugin             - the name of the folder containing the plugin
#   tpt_plugin_name          - the name of the plugin
#

#===============================================================
#
#   Primary functions provided
#
#===============================================================

# Checks if the running tmux version is at least the specified version.
tmux_vers_ok() {
    _v_comp="$1" # Desired minimum version to check against
    # echo "><> tmux_vers_ok($_v_comp)" >/dev/stderr

    # Retrieve and cache the current tmux version on the first call
    [ -z "$tpt_current_vers" ] && tpt_retrieve_running_tmux_vers

    # Compare numeric parts first for quick decisions.
    _i_comp="$(tpt_digits_from_string "$_v_comp")"
    [ "$_i_comp" -lt "$tpt_current_vers_i" ] && return 0
    [ "$_i_comp" -gt "$tpt_current_vers_i" ] && return 1

    # Compare suffixes only if numeric parts are equal.
    _suf="$(tpt_tmux_vers_suffix "$_v_comp")"
    # - If no suffix is required or suffix matches, return success
    [ -z "$_suf" ] || [ "$_suf" = "$tpt_current_vers_suffix" ] && return 0
    # If the desired version has a suffix but the running version doesn't, fail
    [ -n "$_suf" ] && [ -z "$tpt_current_vers_suffix" ] && return 1
    # Perform lexicographical comparison of suffixes only if necessary
    [ "$(printf '%s\n%s\n' "$_suf" "$tpt_current_vers_suffix" |
        LC_COLLATE=C sort | head -n 1)" = "$_suf" ] && return 0

    # If none of the above conditions are met, the version is insufficient
    return 1
}

tpt_dependency_check() {
    # Function Purpose:
    #  This function checks if all required tools are installed on the system.
    #  If any tools are missing, it displays a notification listing the missing
    #  dependencies and returns false.
    #
    # It is designed to simplify dependency checks, particularly for tmux plugins,
    # and includes version-aware reporting to ensure compatibility with different
    # tmux versions.
    #
    # Key Features:
    # 1. Tool Availability Check:
    #    Each listed tool or alternative (e.g., fzf|sk) is checked using `command -v`.
    #    If a tool isn't available, the function handles the failure gracefully.
    #
    # 2. Version-Specific Notifications:
    #    - For tmux 3.2 or newer, missing dependencies are displayed using
    #      display-popup, which stays open until manually closed. This ensures users
    #      see and address all issues before continuing.
    #    - For older tmux versions, it falls back to display-message, which doesn't
    #      persist as reliably but still informs users of missing dependencies.
    #
    # 3. Better User Awareness:
    #    - By pausing on display-popup, the function ensures all dependency issues
    #      are shown without being overwritten by other plugin notifications.
    #    - This avoids the common issue where multiple plugin messages overlap
    #      or disappear quickly during tmux initialization.
    #
    # Parameters:
    #   $1: A space-separated list of tools to check for.
    #       Use a|b to indicate that either tool `a` OR tool `b` can satisfy the
    #       requirement (e.g., "sqlite3 fzf|sk ruby").
    #   $2: If set to skip-notifications, this will just report dependency the
    #       failure and provide a list of the fails in tpt_missing_dependencies.
    #       If not set this will handle the notification.
    #
    # Defined Variables:
    #   tpt_missing_dependencies - Holds a list of missing tools if any are found.
    #
    _dependencies="$1"

    tpt_log_it "dependency_check($_dependencies, $2)"
    tpt_define_plugin_env
    # shellcheck disable=SC2154
    [ "$tpt_debug_mode" = "1" ] && tpt_display_env

    if tpt_verify_dependencies "$_dependencies"; then
        tpt_log_it "no missing dependencies!"
    else
        tpt_log_it "Failed  deps: $tpt_missing_dependencies"
        [ "$2" = "$_surpress_notification" ] && {
            # Caller handles notification
            return 1
        }
	set_popup_size_based_on_window_size
        if [ -z "$TMUX" ]; then
            # run outside tmux, respond in text
            echo "Failed dependencies: $tpt_missing_dependencies"
        elif [ ! -d /proc/ish ] && tmux_vers_ok 3.2; then
            # display-popup is buggy on the iSH platform, so use fallback

            if [ "$_height_adjusted" -ge 8 ]; then
                _line_split="$(echo "$tpt_missing_dependencies" |
                                   sed 's/ /\n /g' | sed 's/|/ or /g')"
                _popup_content="$(printf '\n%s:\n\n %s\n\n%s ' \
                                          "$_failed_dep_popup_line_1" \
                                            "$_line_split" \
                                            'Press Escape to close this popup')"
            else
		# Compact view, to fit on a tight screen
                _popup_content="$(printf '%s:\n\n%s ' \
					 "$_failed_dep_popup_line_1" \
                                         "$tpt_missing_dependencies")"
            fi
            $TMUX_BIN display-popup -h "$_popup_h" -w 95% \
                      -T "$_failed_dep_popup_label" \
                      printf '%s' "$_popup_content"
        else
            # if the shell changes it's prompt after a short delay, it might cause
            # plugin warnings displayed before that moment to disappear, this sleep
            # hopefully waits to display the first notification until prompt is
            # done. Hopefully thee won't be that many plugins displaying this
            # warning, so the accumulated wait time should not escalate too much...
            [ -n "$tpt_plugin_name" ] && sleep 2

            # Since this is normally run via tmux.conf TMUX_PANE is not available
            _current_pane="$($TMUX_BIN display -p '#{pane_id}')"
            _pty="$($TMUX_BIN display-message -p -t "$_current_pane" "#{pane_tty}")"

            _formatted="$(printf "%s" "$tpt_missing_dependencies" |
                sed 's/ /\n  /g' | sed 's/|/ or /g')"
            printf '\nFailed dependency for %s\n  %s\n' \
                "$_failed_dep_text_label" "$_formatted" \
                >"$_pty"
        fi
        return 1
    fi
    return 0
}

#---------------------------------------------------------------
#
#   tmux version related support functions
#
#---------------------------------------------------------------

tpt_retrieve_running_tmux_vers() {
    #
    # If the variables defining the currently used tmux version needs to
    # be accessed before the first call to tmux_vers_ok this can be called.
    #
    # Only assign if it hasn't already been done
    [ -n "$tpt_current_vers" ] && return

    tpt_current_vers="$($TMUX_BIN -V | cut -d' ' -f2)"
    tpt_current_vers_i="$(tpt_digits_from_string "$tpt_current_vers")"
    tpt_current_vers_suffix="$(tpt_tmux_vers_suffix "$tpt_current_vers")"
    tpt_log_it "Current version: $tpt_current_vers"

}

# Extracts all numeric digits from a string, ignoring other characters.
# Example inputs and outputs:
#   "tmux 1.9" => "19"
#   "1.9a"     => "19"
tpt_digits_from_string() {
    # the first sed removes -rc suffixes, to avoid anny numerical rc like -rc1 from
    # being included in the int extraction
    _i="$(echo "$1" | sed 's/-rc[0-9]*//' | tr -cd '0-9')" # Use 'tr' to keep only digits
    echo "$_i"
}

# Extracts any alphabetic suffix from the end of a version string.
# If no suffix exists, returns an empty string.
# Example inputs and outputs:
#   "3.2"  => ""
#   "3.2a" => "a"
tpt_tmux_vers_suffix() {
    echo "$1" | sed 's/.*[0-9]\([a-zA-Z]*\)$/\1/'
}

#---------------------------------------------------------------
#
#   Dependency check related support functions
#
#---------------------------------------------------------------

tpt_add_missing_dependeny() {
    tpt_log_it "      tpt_add_missing_dependeny($1)"
    tpt_fail_count=$((tpt_fail_count + 1))
    _s="$tpt_missing_dependencies"
    if [ -z "$tpt_missing_dependencies" ]; then
        tpt_missing_dependencies="$1"
    else
        tpt_missing_dependencies="$tpt_missing_dependencies $1"
    fi
    tpt_log_it "dependencies before[$_s] after[$tpt_missing_dependencies]"
}

tpt_verify_dependencies() {
    #
    #  Returns true if all the dependencies could be found
    # notation: "curl" "fzf|sk"
    #
    tpt_log_it "tpt_verify_dependencies($1)"
    tpt_missing_dependencies=""
    tpt_fail_count=0
    # shellcheck disable=SC2068 # in this case we want to split the param
    for _dep_group in $@; do
	# a _dep_group is one space separated item
        tpt_log_it " dep_group: >$_dep_group<"
        for _dep in $(echo "$_dep_group" | tr "|" ' '); do
	    # _dep is a | separated item, or the entire group if no | present
            tpt_log_it "  _dep: >$_dep<"
            if command -v "$_dep" >/dev/null 2>&1; then
                continue 2
            fi
        done
        tpt_add_missing_dependeny "$_dep_group"
    done
    # Equivalent to 'return' with a boolean result
    [ -z "$tpt_missing_dependencies" ]
}


set_popup_size_based_on_window_size() {
    #
    #  Defines:
    #    _win_height - height of window (minus status bar)
    #    _popup_h    - height in % for popup
    #
    _win_height="$($TMUX_BIN display -p "#{window_height}")"
    _height_adjusted=$((_win_height - tpt_fail_count))

    if [ "$_height_adjusted" -ge 20 ]; then
	_popup_h="50%"
    elif [ "$_height_adjusted" -ge 16 ]; then
	_popup_h="60%"
    elif [ "$_height_adjusted" -ge 14 ]; then
	_popup_h="70%"
    elif [ "$_height_adjusted" -ge 11 ]; then
	_popup_h="80%"
    elif [ "$_height_adjusted" -ge 10 ]; then
	_popup_h="90%"
    else
	_popup_h="100%"
    fi

    # Debug adds heights to label to help calculations
    # _failed_dep_popup_label="$_failed_dep_popup_label $_popup_h $_win_height $_height_adjusted "
}

#---------------------------------------------------------------
#
#   Other
#
#---------------------------------------------------------------

tpt_log_it() {
    #
    # If you want to integrate this log feature with your own logging
    # add this in your code after souring this file:
    #
    # tpt_log_it() {
    #     log_it "$@" # call your own logging here
    # }

    [ "$tpt_debug_mode" = "1" ] && {
        echo "><> $1" >/dev/stderr
    }
}

tpt_define_plugin_env() {
    #
    # Attempts to figure out some env related settings based on full path
    # to script calling this
    #
    [ -n "$tpt_plugin_name" ] && return # no need to be done more than once

    _caller="$(realpath "$0")"
    # tpt_log_it "trying to extract plugin name & folder from [$_caller]"

    # Assume plugin name is folder name following ../plugins/
    tpt_plugin_name="$(echo "$_caller" | grep plugins | sed 's#plugins/# #' |
        cut -d' ' -f 2 | cut -d/ -f 1)"
    if [ -n "$tpt_plugin_name" ]; then
        _failed_dep_popup_label=" plugin: $tpt_plugin_name "
	_failed_dep_popup_line_1="Failed dependencies"
        _failed_dep_text_label="plugin: $tpt_plugin_name"
        tpt_d_plugin="$(echo "$_caller" |
            sed "s#$tpt_plugin_name#$tpt_plugin_name\|#" | cut -d'|' -f1)"
    else
        # As a fallback, use full path of script that called this, to at least
        # give some hint
        _failed_dep_popup_label=" Failed dependencies "
	_failed_dep_popup_line_1="$_caller"
        _failed_dep_text_label="$_caller"
        tpt_d_plugin=""
    fi
}

tpt_display_env() {
    tpt_log_it "tpt_display_env()"
    tpt_log_it "tpt_plugin_name: $tpt_plugin_name"
    tpt_log_it "_failed_dep_popup_label:  [$_failed_dep_popup_label]"
    tpt_log_it "_failed_dep_popup_line_1: [$_failed_dep_popup_line_1]"
    tpt_log_it "_failed_dep_text_label:   [$_failed_dep_text_label]"
    tpt_log_it "_caller: $_caller"
    tpt_log_it "Dependencies: [$_dependencies]"
    tpt_log_it "      Failed: [$tpt_missing_dependencies]"
    tpt_log_it "tpt_d_plugin: $tpt_d_plugin"
    tpt_log_it
}

tpt_parse_cmd_line() {
    tpt_log_it "tpt_parse_cmd_line()"
    case "$1" in
        dependency-check)
            shift
            tpt_dependency_check "$@"
            ;;
        self-test) # Use this as a basic self-test
            shift
            tpt_tests "$@"
            ;;
	env)
	    shift
	    tpt_debug_mode=1
	    tpt_define_plugin_env
	    tpt_display_env
	    ;;
        *)
            echo "Valid params:"
            echo
            echo "dependency-check 'space separated string of dependencies'"
            echo "  If tmux >= 3.2 a popup will be used to display failed dependencies"
            echo "  For older tmux versions and if called from outside tmux, It will be printed."
            echo
	    echo "env"
	    echo "  Display environment picked up"
	    echo
            echo "self-test [skip-notifications]"
            echo "  This will demonstrate both tools:"
            echo "    tmux_vers_ok - to check if a given feature is available"
            echo "    tpt_dependency_check - to check if a tool is installed"
            echo "      skip-notifications - lets the caller present failed dependencies"
            echo "        Only returning false. Failed dependencies are set in the variable"
            echo "        tpt_missing_dependencies"
            echo
            ;;
    esac
}

#---------------------------------------------------------------
#
#   Self tests
#
#---------------------------------------------------------------

tpt_test_version() {
    v_test="$1"
    # echo "><> tmux_vers_ok($v_test)" >/dev/stderr

    if tmux_vers_ok "$v_test"; then
        printf '%s\ton %s\t- is ok\n' "$v_test" "$tpt_current_vers"
    else
        printf '%s\ton %s\t- FAIL\n' "$v_test" "$tpt_current_vers"
    fi
}

tpt_test_dependency() {
    dependency="$1"

    # echo "><> tpt_test_dependency($dependency)"
    tpt_dependency_check "$dependency" && echo "Dependencies verified: $dependency"
}

tpt_tests() {
    tpt_define_plugin_env

    echo "plugin folder detected: $tpt_d_plugin"
    # shellcheck disable=SC2154
    echo "plugin name detected: $tpt_plugin_name"
    echo

    echo "Display resulut for tmux_vers_ok vs current tmux - $tpt_current_vers"
    tpt_test_version 3.6a
    tpt_test_version 3.6
    tpt_test_version 3.5c
    tpt_test_version 3.5b
    tpt_test_version 3.5a
    tpt_test_version 3.5
    tpt_test_version 3.4
    tpt_test_version 3.3a
    tpt_test_version 3.3
    tpt_test_version 3.2a
    tpt_test_version 3.2
    tpt_test_version 3.1c
    tpt_test_version 3.1b
    tpt_test_version 3.1a
    tpt_test_version 3.1
    tpt_test_version 3.0a
    tpt_test_version 3.0
    tpt_test_version 2.9a
    tpt_test_version 2.9
    tpt_test_version 2.8
    tpt_test_version 2.7
    tpt_test_version 2.6
    tpt_test_version 2.5
    tpt_test_version 2.4
    tpt_test_version 2.3
    tpt_test_version 2.2
    tpt_test_version 2.1
    tpt_test_version 2.0
    echo

    #
    # to avoid getting tmux notifications of failed dependencies
    # run this as: tmux-plugin-tools.sh test-plugin-tools skip-notifications
    #
    tst_dependencies="less|more foo_a|foo_b foo_c ls"
    tpt_dependency_check "$tst_dependencies" "$1" || {
        echo "Dependencies tested: $tst_dependencies"
        echo "Dependency failures: $tpt_missing_dependencies"
    }
    exit 0
}

#===============================================================
#
#   Main
#
#===============================================================

# Only set this if undefined
[ -z "$TMUX_BIN" ] && TMUX_BIN="tmux"

# Hint that caller handles notifications about failed dependencies
_surpress_notification="skip-notifications"

#
# Call this to get early access to info about current tmux:
#   tpt_current_vers         - full name of available tmux version
#   tpt_current_vers_i       - int part of version
#   tpt_current_vers_suffix  - version suffix
#
# This will be done on fist call to tmux_vers_ok(), so not needed in
# normal usage
#
# tpt_retrieve_running_tmux_vers

#
# Call this to get early access to some best guesses for:
#   tpt_plugin_name
#   tpt_d_plugin    - the plugin folder
#
# This will be done in tpt_dependency_check(), so not needed in normal usage,
#  unless there is a need for early definition those variables
#
# tpt_define_plugin_env

# Enable for testing / debugging
tpt_debug_mode=0

[ -n "$1" ] && tpt_parse_cmd_line "$@"
