# Tmux-Packet-Loss

Tmux-Packet-Loss is a plugin for Tmux that displays the percentage of packet
loss on your connection. In reactive mode, it calculates loss using multiple
rolling averages over recent checks and reports the highest value, making
recent spikes visible while allowing them to decay over time. A simple rolling
average mode can be selected via configuration.

## Recent changes

- `@packet-loss-weighted_average` renamed to `@packet-loss-reactive` after
  clarifying that the approach is not a weighted average.
  The old variable is still supported for now, but triggers a warning advising migration.
- Added support for no network connection for all supported platforms - reported as 101
- Now uses both "journal_mode = WAL" and sqlite3 -cmd '.timeout 200' to avoid DB collisions
- Converted all scripts to POSIX, no more bash dependencies. This cuts down a lot
  on startup times, `scripts/display-losses.sh` is 3-4 times faster!
- Losses are displayed, but no stats are saved for the first 45 seconds.
  This avoids getting initial errors before the network is re-established saved
  into the history during a laptop resume.

## Screenshots

Partial status bar configuration: `#{battery_smart} #{packet_loss}%a %h-%d %H:%M`

Plugin output takes no space when under @packet-loss-level_disp level.

### Loss levels

The `~4` displays last 30 min average loss rate.

| Display                                                                                                     | With hist avg                                                                                                 | Status                |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | --------------------- |
| ![no_loss](https://github.com/jaclu/tmux-packet-loss/assets/5046648/91f94685-c931-425e-bc4a-20c0246959a4)   |                                                                                                               | under threshold       |
| ![lvl_low](https://github.com/jaclu/tmux-packet-loss/assets/5046648/78fd85b6-fdd3-4609-9903-9d15c0913ab2)   | ![lvl_low_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/95c91b03-f562-4790-8e62-1b7a343f90c1)   | low level losses      |
| ![lvl_alert](https://github.com/jaclu/tmux-packet-loss/assets/5046648/7213af06-6e81-41f1-84d8-2c978beff668) | ![lvl_alert_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/63539008-fd0c-45bf-8f95-7b6e9312dd0c) | alert level losses    |
| ![lvl_crit](https://github.com/jaclu/tmux-packet-loss/assets/5046648/7ea54245-d571-45e9-8b04-b100b6d791db)  | ![lvl_crit_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/fcc9e663-4b08-4c13-a6e9-9d7b92d3e3ef)  | critical level losses |

### Trends

If `@packet-loss-display_trend` is yes, change since the previous check is indicated
with a prefix character

| Display                                                                                                  | Status     |
| -------------------------------------------------------------------------------------------------------- | ---------- |
| ![incr](https://github.com/jaclu/tmux-packet-loss/assets/5046648/6b1650f0-fc83-4876-9ebe-30d6fe95898f)   | Increasing |
| ![stable](https://github.com/jaclu/tmux-packet-loss/assets/5046648/78fd85b6-fdd3-4609-9903-9d15c0913ab2) | Stable     |
| ![decr](https://github.com/jaclu/tmux-packet-loss/assets/5046648/a61e21dd-e7e3-4840-9d58-153644ca1717)   | Decreasing |

## Operation

The plugin runs a background process that periodically pings a host to measure packet loss.
By default, it computes loss from multiple rolling averages over recent samples
and reports the maximum value, making recent spikes more visible
while allowing them to decay over time.

### Background monitor

The monitor runs continuously. By default, it stops when no tmux clients are
connected and restarts when one reconnects. Set `@packet-loss-run_disconnected`
to `yes` to keep it running always. It exits when tmux shuts down.

### ping issues

Error codes (displayed as loss > 100%) indicate what went wrong:

| Code | Meaning                                                                                   |
| ---- | ----------------------------------------------------------------------------------------- |
| 101  | No network connection.                                                                    |
| 102  | Could not find loss % in ping output (usually temporary).                                 |
| 103  | Loss value outside 0–100% range (usually temporary).                                      |
| 104  | Ping returned an unrecognized error.                                                      |
| 201  | Could not parse ping output. Please file an issue with `ping -c 5 8.8.4.4` output and OS. |

## Dependencies

- `tmux 1.9+`
- `sqlite3`

## Verified Environments

- Linux
- macOS
- Windows Subsystem for Linux (WSL)
- iSH
- Termux

## Installation

### Installation with [Tmux Plugin Manager (tpm)](https://github.com/tmux-plugins/tpm) (recommended)

Add the plugin to the list of TPM plugins in `.tmux.conf`:

```tmux
set -g @plugin 'jaclu/tmux-packet-loss'
```

Hit `prefix + I` to fetch the plugin and source it. That's it!

### Manual Installation

Clone the repository:

```bash
git clone https://github.com/jaclu/tmux-packet-loss.git ~/clone/path
```

Add this line to the bottom of `.tmux.conf`:

```tmux
run-shell ~/clone/path/packet-loss.tmux
```

Reload the Tmux environment with `$ tmux source-file ~/.tmux.conf` - that's it!

## Supported Format Strings

| Code             | Action                                                                              |
| ---------------- | ----------------------------------------------------------------------------------- |
| `#{packet_loss}` | Displays packet loss if at or above `@packet-loss-level_disp` <br>Otherwise nothing |

## Configuration Variables

| Variable                      | Default   | Purpose                                                                                                                                                                    |
| ----------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| @packet-loss-ping_host        | 8.8.8.8   | The host to ping. Choosing a well-connected & replicated host like 8.8.8.8 or 1.1.1.1 gives a good idea of your general link quality.                                      |
| @packet-loss-ping_count       | 6         | Number of pings per statistics update.                                                                                                                                     |
| @packet-loss-history_size     | 7         | Number of results to keep. Lower values show current status better; use `@packet-loss-hist_avg_display` for longer-term trends.                                            |
|                               |           |                                                                                                                                                                            |
| @packet-loss-reactive         | yes       | Enables reactive mode: loss is computed from multiple rolling averages over recent samples and the highest value is used. If disabled, loss is the average of all samples. |
| @packet-loss-display_trend    | no        | Show trend indicator (`+` rising, `-` falling) if `yes`.                                                                                                                   |
| @packet-loss-hist_avg_display | no        | Show 30-min historical average alongside current loss if `yes`.                                                                                                            |
| @packet-loss-run_disconnected | no        | Monitor runs always if `yes`, stops when no clients connected if `no`.                                                                                                     |
| @packet-loss-level_disp       | 1         | Display loss if at or higher than this level.                                                                                                                              |
| @packet-loss-level_alert      | 18        | Color loss with `@packet-loss-color_alert` at or above this level. Tip: set one higher than single packet loss %.                                                          |
| @packet-loss-level_crit       | 40        | Color loss with `@packet-loss-color_crit` if at or above this level.                                                                                                       |
|                               |           |                                                                                                                                                                            |
| @packet-loss-hist_avg_minutes | 30        | Minutes to keep the historical average.                                                                                                                                    |
| @packet-loss-hist_separator   | '\~'      | Separator for current/historical losses.                                                                                                                                   |
|                               |           |                                                                                                                                                                            |
| @packet-loss-color_alert      | colour226 | Color for alert-level loss.                                                                                                                                                |
| @packet-loss-color_crit       | colour196 | Color for critical-level loss.                                                                                                                                             |
| @packet-loss-color_bg         | black     | Background color for colored loss display.                                                                                                                                 |
|                               |           |                                                                                                                                                                            |
| @packet-loss-prefix           | '\|'      | Prefix for status when displayed.                                                                                                                                          |
| @packet-loss-suffix           | '\|'      | Suffix for status when displayed.                                                                                                                                          |
|                               |           |                                                                                                                                                                            |
| @packet-loss-log_file         |           | If defined this file will be used for logging.                                                                                                                             |

## My config

```tmux
set -g @packet-loss-hist_avg_display  yes
set -g @packet-loss-run_disconnected  yes

# Single packet loss disappears from display in ~15s
set -g @packet-loss-level_disp   5

# Yellow background for alert/crit, so set alert color to blue instead
set -g @packet-loss-color_alert  colour21
set -g @packet-loss-color_bg     colour226

# Add spacer so plugin takes no space when there's no loss
set -g @packet-loss-suffix "| "
```

## Tuning for accuracy

**Ping count:** Higher counts give better granularity (e.g., 2 pings can only
show 0%, 50%, 100%) but take longer. Keep it short for real-time monitoring;
use `@packet-loss-hist_avg_display` for longer-term trends.

**Status interval:** Set tmux's `status-interval` one less than
`@packet-loss-ping_count` to sync updates (e.g., `status-interval = 5` if
`ping_count = 6`).

## Implementation details

**Clearing data:** Delete the data folder to reset the database and restart
the monitor—an easy way to clear history without touching SQL.

**Reactive mode:** When enabled (default), loss is computed from multiple
rolling averages over recent samples (1–7) plus the full-history average, and
the highest value is used. When disabled, loss is computed as the average of
all samples.

### Suggested Alert Levels

Recommended alert thresholds to avoid false alarms from a single lost packet:

| pings       | one higher than <br>a single loss % | history size <br>for approx 30s |
| ----------- | ----------------------------------- | ------------------------------- |
| 10          | 11                                  | 4 (28)  5 (37)                  |
| 9           | 12                                  | 5 (32)                          |
| 8           | 13                                  | 5 (28)  6 (36)                  |
| 7           | 15                                  | 6 (31)                          |
| 6 (default) | 18                                  | 7 (31)                          |
| 5           | 21                                  | 8 (29)                          |
| 4           | 26                                  | 11 (31)                         |
| 3           | 34                                  | 15 (30)                         |

### Database

There are three tables

| table   | Description                                                                              |
| ------- | ---------------------------------------------------------------------------------------- |
| t_loss  | Contains the current loss statuses                                                       |
| t_1_min | Keeps all samples from the last minute, to feed one-minute averages to the t_stats table |
| t_stats | Keeps one-minute averages for the last @packet-loss-hist_avg_minutes minutes             |

Each table contains two fields, time_stamp, and value. The time_stamp field is
used to purge old records.

### Simulating losses

Use the included test script to simulate packet loss:

```bash
./scripts/test_data.sh
```

Run without params for help. The monitor restarts automatically 2 minutes after the last run.

## Contributing

Contributions are welcome, and they're appreciated.
Every little bit helps, and credit is always given.

The best way to send feedback is to file an issue at tmux-packet-loss/issues

## License

[MIT](LICENSE)
