# Tmux-Packet-Loss

Tmux-Packet-Loss is a plugin for Tmux that displays the percentage of packet loss on your connection. It calculates the loss level as a weighted average by default, giving more emphasis to recent checks.

## Recent changes

- Losses are displayed, but no stats are saved for the first 30 seconds. This avoids getting initial errors saved into the history during a laptop resume before the network is re-established. 
- Fixed boolean parameter handling to allow for yes/no or true/false options.
- Renamed variables and defaults to match the Tmux option names.
- Refactored code into more task-isolated modules.

## Screenshots

Partial status bar configuration: `#{battery_smart} #{packet_loss}%a %h-%d %H:%M`

Plugin output takes no space when under @packet-loss-level_disp level.

### Loss levels

| Display | With hist avg | Status
| - | - | - |
| ![no_loss  ](https://github.com/jaclu/tmux-packet-loss/assets/5046648/91f94685-c931-425e-bc4a-20c0246959a4) |   | under threshold       |
| ![lvl_low  ](https://github.com/jaclu/tmux-packet-loss/assets/5046648/78fd85b6-fdd3-4609-9903-9d15c0913ab2) | ![lvl_low_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/95c91b03-f562-4790-8e62-1b7a343f90c1)   | low level losses      |
| ![lvl_alert](https://github.com/jaclu/tmux-packet-loss/assets/5046648/7213af06-6e81-41f1-84d8-2c978beff668) | ![lvl_alert_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/63539008-fd0c-45bf-8f95-7b6e9312dd0c) | alert level losses    |
| ![lvl_crit ](https://github.com/jaclu/tmux-packet-loss/assets/5046648/7ea54245-d571-45e9-8b04-b100b6d791db) | ![lvl_crit_h](https://github.com/jaclu/tmux-packet-loss/assets/5046648/fcc9e663-4b08-4c13-a6e9-9d7b92d3e3ef)  | critical level losses |

### Trends

If `@packet-loss-display_trend` is yes, change since the previous check is indicated with a prefix character

| Display | Status
| - | - |
|![incr  ](https://github.com/jaclu/tmux-packet-loss/assets/5046648/6b1650f0-fc83-4876-9ebe-30d6fe95898f) | Increasing |
|![stable](https://github.com/jaclu/tmux-packet-loss/assets/5046648/78fd85b6-fdd3-4609-9903-9d15c0913ab2) | Stable     |
|![decr  ](https://github.com/jaclu/tmux-packet-loss/assets/5046648/a61e21dd-e7e3-4840-9d58-153644ca1717) | Decreasing |

## Operation

This plugin runs a background process using repeated runs of ping to determine % package loss. The loss level is calculated as a weighted average of the stored data points by default, making the latest checks stand out.

### Termination on Tmux Exit

The background process terminates if the tmux main process is no longer running.

### ping issues

If the monitor fails to calculate loss, packet loss above 100% is reported. So far I have created one special case ping parser, for iSH running Debian 10.

| Result | Explanation                                                                                                     |
| ------ | --------------------------------------------------------------------------------------------------------------- |
| 101    | Failed to find % loss in ping output. Temporary issue. Some pings don't report loss % if there is no connection to the host. |
| 102    | loss reported was < 0 or > 100, odd but hopefully temporary |
| 201    | Could not parse output. This condition is unlikely to self-correct. If you file the output of `ping -c 5 8.8.4.4` as an Issue and also mention what Operating System this is and any other factors you think are relevant, I will try to fix it by including parsing of that output format. |

## Dependencies

Ensure you have the following dependencies installed:

- `tmux 1.9`
- `sqlite3`
- `bash`

## Verified Environments

Tmux-Packet-Loss has been tested and verified to work in the following environments:

- Linux
- MacOS
- iSH
- Windows Subsystem for Linux (WSL)

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

| Code           | Action                                             |
| -------------- | -------------------------------------------------- |
| `#{packet_loss}` | Displays average packet loss % if at or above `@packet-loss-level_disp` |

## Configuration Variables

| Variable                      | Default       | Purpose |
|-------------------------------|---------------|---------|
| @packet-loss-ping_host        | 8.8.4.4       | The host to ping. Choosing a well-connected & replicated host like 8.8.4.4 or 1.1.1.1 gives a good idea of your general link quality. |
| @packet-loss-ping_count       | 6             | Number of pings per statistics update. |
| @packet-loss-history_size     | 6             | Number of results to keep when displaying loss statistics.<br>Keeping this value low is recommended since it's more useful to see current status over long-term averages.<br>For a historical overview, use `@packet-loss-hist_avg_display`. |
|                               |               | |
| @packet-loss-weighted_average | yes           | yes - Use weighted average focusing on the latest data points.<br> no - Average over all data points. |
| @packet-loss-display_trend    | no            | yes - Display trend with `+` prefix for higher levels and `-` prefix for lower levels.<br>no - Do not indicate change since previous loss level. |
| @packet-loss-level_disp       | 1             | Display loss if at or higher than this level. |
| @packet-loss-level_alert      | 17            | Color loss with `color_alert` if at or above this level.<br>Suggestion: set it one higher than the percentage representing one loss in one update to avoid single packet loss triggering an alert initially. |
| @packet-loss-level_crit       | 40            | Color loss with `color_crit` if at or above this level. |
|                               |               | |
| @packet-loss-hist_avg_display | no            | yes - Show historical average when displaying current losses.<br>no - Do not show historical average. |
| @packet-loss-hist_avg_minutes | 30            | Minutes to keep the historical average. |
| @packet-loss-hist_separator   | '\~'          | Separator for current/historical losses. |
|                               |               | |
| @packet-loss-color_alert      | colour226     | Use this color if the loss is at or above `@packet-loss-level_alert`. |
| @packet-loss-color_crit       | colour196     | Use this color if the loss is at or above `@packet-loss-level_crit`. |
| @packet-loss-color_bg         | black         | Background color when alert/crit colors are used in the display. |
|                               |               | |
| @packet-loss-prefix           | '\|'          | Prefix for status when displayed. |
| @packet-loss-suffix           | '\|'          | Suffix for status when displayed. |

## My config

```tmux
set -g @packet-loss-display_trend     yes
set -g @packet-loss-hist_avg_display  yes

#
# In combination with weighted_average, ping_count and history_size,
# this makes a single ping loss disapear from being displayed in 15s
#
set -g @packet-loss-level_disp   5

set -g @packet-loss-color_alert  colour21
set -g @packet-loss-color_bg     colour226

```

## Balancing reporting

To obtain a clearer picture of the current situation, consider adjusting the ping count. A higher ping count results in more nuanced data per check. For instance, if only 2 packets are checked per round, the results may only be 0%, 50%, or 100%, lacking granularity. Increasing the ping count enhances the accuracy of each check.

However, be cautious not to exceed a certain limit, as a higher ping count prolongs the time taken for each test. This delay may render the reported data irrelevant to the current link status, particularly if your focus is on real-time monitoring.

For longer term averages it is better to use @packet-loss-hist_avg_display

Additionally, it's advisable to review and potentially adjust the `status-interval` setting to align with your reporting needs. Ensuring that the update rate for this plugin in the status bar remains relevant enhances the effectiveness of your monitoring system.

Given that ping is instantaneous, consider setting the `status-interval` to one lower than `@packet-loss-ping_count`. This adjustment synchronizes the sampling and reporting processes more effectively, providing timely and accurate updates.

## Nerdy stuff

If `@packet-loss-weighted_average` is set to yes (the default) losses
are displayed as the largest of:

- last value
- avg of last 2
- avg of last 3
- avg of last 4
- avg of last 5
- avg of last 6
- avg of last 7
- avg of all

If set to no, the average of all samples is always displayed.

### Suggested Alert Levels

Depending on the ping count, it is suggested to set alert,
so that a single lost packet wont show up as an alert.

| pings | one higher than a single loss % | history size for aprox 30s |
|-|-|-|
| 10 | 11 |  3=27 4=36 |
|  9 | 12 |  4=32 |
|  8 | 13 |  5=35 |
|  7 | 15 |  5=30 |
|  6 | 17 |  6=30 |
|  5 | 21 |  8=32 |
|  3 | 34 | 15=30 |

### Database

There are three tables

| table | Description |
| -|- |
| t_loss | Contains the current loss statuses |
| t_1_min   | Keeps all samples from the last minute, to feed one-minute averages to the t_stats table |
| t_stats  | Keeps one-minute averages for the last @packet-loss-hist_avg_minutes minutes |

Each table contains two fields, time_stamp, and value. The time_stamp field is only used to purge old data.

### Simulating losses

If you want to examine the plugin displaying losses you can pause the monitor and
feed the DB with fake losses like this:

```bash
./scripts/ctrl_monitor.sh stop
```

Then run this a suitable number of times, adjusting the loss level

```bash
sqlite3 data/packet_loss.sqlite "INSERT INTO t_loss (loss) VALUES (50)"
```

The monitor will be automatically restarted one minute after the last update.

## Contributing

Contributions are welcome, and they're appreciated.
Every little bit helps, and credit is always given.

The best way to send feedback is to file an issue at tmux-packet-loss/issues

#### License

[MIT](LICENSE)
