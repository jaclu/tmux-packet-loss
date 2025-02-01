# FileDescription

- `all_data.sh` - can clear the DB and display all data or averages
- `ctrl_monitor.sh` - starts/stops the monitor
  if missing or obsolete. Also updates the triggers on each run
- `display_losses.sh` - Called from the status line, gathers current stats
- `monitor_packet_loss.sh` - Monitors the network link, gathering ping packet
  losses, and if so configures shuts down when no clients are connected.
- `pidfile_handler.sh` - Used to handle pid-files by the other scripts
- `prepare_db.sh` - called by`monitor_packet_loss.sh` to create the DB
- `show_settings.sh` - Can be called from the command line to inspect current
  settings
- `test_data.sh` - Used to feed test data into the DB
- `tmux-plugin-tools.sh` - Provide version & dependency checks
- `utils.sh` - Common stuff

All files can be run from the command-line
