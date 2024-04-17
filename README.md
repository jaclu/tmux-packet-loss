# Tmux-Packet-Loss

Tmux-Packet-Loss is a plugin for Tmux that displays the percentage of packet loss on your connection. It calculates the loss level as a weighted average by default, giving more emphasis to recent checks.

## Recent changes

- Fixed boolean parameter handling to allow for yes/no or true/false options.
- Renamed variables and defaults to match the Tmux option names.
- Refactored code into more task-isolated modules.

## Screenshots

Note: The screenshots use compact prefix and suffix settings. Partial status bar configuration: `#{battery_smart}#{packet_loss}%a %h-%d %H:%M`

Plugin output takes no space when under @packet-loss-level_disp level.

### Loss levels

| Display | With hist avg | Status                 |
| ------- | ------------- | ---------------------- |
| ![no_loss  ](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png) | ![no_loss_h](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png)   | under threshold        |
| ![lvl_low  ](https://user-images.githubusercontent.com/5046648/215364078-e139daf0-d224-4275-afe2-6f3894420630.png) | ![lvl_low_h](https://user-images.githubusercontent.com/5046648/215363685-eaf8bc66-44f6-461b-83f1-0b3c16e76869.png)   | low level losses       |
| ![level_alert](https://user-images.githubusercontent.com/5046648/215363408-4b043df3-fcd3-46d7-a3fa-6c3698806955.png) | ![level_alert_h](https://user-images.githubusercontent.com/5046648/215363791-c1ca0731-57d5-4f34-a580-896b22fbf76b.png) | alert level losses     |
| ![level_crit ](https://user-images.githubusercontent.com/5046648/215363311-0c925d11-c015-45df-8143-460d2f9d9ec8.png) | ![level_crit_h](https://user-images.githubusercontent.com/5046648/215363877-01509d06-f58e-442a-9ebf-06b80688dd7c.png)  | critical level losses  |

### Trends

If `@packet-loss-display_trend` is set to 1, changes since the previous check are indicated with a prefix character.

| Display | Status       |
| ------- | ------------ |
| ![incr  ](https://user-images.githubusercontent.com/5046648/226140494-1715b5fa-61fe-4583-a9d4-d0c94c5ff63d.png) | Increasing   |
| ![stable](https://user-images.githubusercontent.com/5046648/226140512-fdd824bc-fcd0-4d5e-b960-eb5ec043e190.png) | Stable       |
| ![decr  ](https://user-images.githubusercontent.com/5046648/226140473-94032422-c028-4ffd-96ef-da8aade23460.png) | Decreasing   |

## Operation

This plugin runs a background process using repeated runs of ping to determine % package loss. The loss level is calculated as a weighted average of the stored data points by default, making the latest checks stand out.

### Termination on Tmux Exit

On modern Tmux versions, the background process is terminated when Tmux exits. See "Tmux Compatibility" for more details about versions and limitations regarding shutting down this background process.

### ping issues

If the monitor experiences errors, packet loss above 100% is reported.

| Result | Explanation                                                                                                     |
| ------ | --------------------------------------------------------------------------------------------------------------- |
| 101    | Failed to find % loss in ping output. Temporary issue. Some pings don't report loss % if there is no connection to the host. |
| 201    | Could not parse output. This condition is unlikely to self-correct. If you file the output of `ping -c 5 8.8.4.4` as an Issue and also mention what Operating System this is and any other factors you think are relevant, I will try to fix it by including parsing of that output format. |

## Dependencies

Ensure you have the following dependencies installed:

- `tmux 1.9`
- `sqlite3`

## Tmux Compatibility

| Version    | Notice                                                                                               |
| ---------- | ---------------------------------------------------------------------------------------------------- |
| 3.0 >=     | The background process is shut down when Tmux exits using a session-closed hook with an array suffix. |
| 2.4 - 2.9  | Will shut down the background process, but since hooks don't support arrays, binding to session-closed might interfere with other stuff using the same hook. |
| 1.9 - 2.3  | session-closed hook not available. If you want to kill the background monitoring process after Tmux shutdown, you need to add something like `~/.tmux/plugins/tmux-packet-loss/scripts/ctrl_monitor.sh stop` to a script starting Tmux. If you run Tmux most of the time, you can just leave the process running. |

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
| \`#{packet_loss}\` | Displays average packet loss % if at or above \`@packet-loss-level_disp\` |

## Configuration Variables

| Variable                      | Default       | Purpose |
|-------------------------------|---------------|---------|
| @packet-loss-ping_host        | 8.8.4.4       | The host to ping. Choosing a well-connected host like 8.8.4.4 gives a good idea of your general link quality. |
| @packet-loss-ping_count       | 6             | Number of pings per statistics update. |
| @packet-loss-history_size     | 6             | Number of results to keep when calculating average loss.<br>Keeping this value low is recommended since it's more useful to see current status over long-term averages.<br>For a historical overview, use `@packet-loss-hist_avg_display`. |
|                               |               | |
| @packet-loss-weighted_average | yes           | Whether to use weighted average focusing on the latest data points (`yes`) or average over all data points (`no`). |
| @packet-loss-display_trend    | no            | Display trend with `+` prefix for higher levels and `-` prefix for lower levels (`yes`). |
| @packet-loss-level_disp       | 1             | Display loss if at or higher than this level. |
| @packet-loss-level_alert      | 17            | Color loss with `color_alert` if at or above this level.<br>Suggestion: set it one higher than the percentage representing one loss in one update to avoid single packet loss triggering an alert initially. |
| @packet-loss-level_crit       | 40            | Color loss with `color_crit` if at or above this level. |
|                               |               | |
| @packet-loss-hist_avg_display | no            | Show historical average when displaying current losses (`yes`). |
| @packet-loss-hist_avg_minutes | 30            | Minutes to keep the historical average. |
| @packet-loss-hist_separator   | '\~'          | Separator for current/historical losses. |
|                               |               | |
| @packet-loss-color_alert      | colour226     | Use this color if the loss is at or above `@packet-loss-level_alert`. |
| @packet-loss-color_crit       | colour196     | Use this color if the loss is at or above `@packet-loss-level_crit`. |
| @packet-loss-color_bg         | black         | Background color when alert/crit colors are used in the display. |
|                               |               | |
| @packet-loss-prefix           | ' pkt loss: ' | Prefix for status when displayed. |
| @packet-loss-suffix           | ' '           | Suffix for status when displayed. |
|                               |               | |
| @packet-loss-hook_idx         | 41            | Index for session-closed hook. Only change if it collides with other usages of session-closed using this index. Check with `tmux show-hooks -g \| grep session-closed`.<br>If you do not want to use session-closed hook - set this to -1 |

## My config

```tmux
set -g @packet-loss-display_trend     yes
set -g @packet-loss-hist_avg_display  yes

set -g @packet-loss-color_alert colour21
set -g @packet-loss-color_bg    colour226

set -g @packet-loss-prefix '|'
set -g @packet-loss-suffix '|'
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

Depending on the ping count, it is suggested to have alert one higher, so that a single lost packet wont show up as an alert

| pings | one higher than a single loss |
|-|-|
| 6 | 17 |

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

The monitor will be automatically restarted one minute after the last update

## Contributing

Contributions are welcome, and they're appreciated.
Every little bit helps, and credit is always given.

The best way to send feedback is to file an issue at tmux-packet-loss/issues

#### License

[MIT](LICENSE)
