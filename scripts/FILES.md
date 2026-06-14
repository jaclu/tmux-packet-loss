# FileDescription

- `all-data.sh` - Display averags or all data. Can also clear the DB.
- `ctrl-monitor.sh` - starts/stops the monitor
  if missing or obsolete. Also updates the triggers on each run
- `display-losses.sh` - Called from the status line, gathers current stats
- `monitor-packet-loss.sh` - Monitors the network link, gathering ping packet
  losses, and if so configures shuts down when no clients are connected.
  Not normally run directly, started in the background by `ctrl-monitor.sh`
- `pidfile-handler.sh` - Used to handle pid-files by the other scripts
- `prepare-db.sh` - called by`monitor-packet-loss.sh` to create the DB
- `show-settings.sh` - Can be called from the command line to inspect current
  settings
- `test-data.sh` - Used to feed test data into the DB
- `tmux-plugin-tools.sh` - Provide version & dependency checks
- `utils.sh` - Common stuff

All files can be run from the command-line
