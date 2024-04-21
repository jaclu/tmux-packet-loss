# FileDescription

- ctrl_monitor.sh - starts/stops the monitor
- db_prepare.sh - called by `monitor_packet_loss.sh` to create the DB
if missing or obsolete. Also updates the triggers on each run
- display_losses.sh - Called from the status line, gathers current stats
- monitor_packet_loss.sh - Monitors the network link, gathering ping packet
 losses
- no_sessions_shutdown.sh - Shuts down monitor if no tmux sessions remains,
called via tmux session-closed hook
- pidfile_handler.sh - Used to handle pid-files by the other scripts
- show_settings.sh - Can be called from the command line to inspect current
settings
- utils.sh - Common stuff
- vers_check.sh - Does version comparaes, able to handle tmux mixture of
numbers and letters

All files can be run from the command-line
