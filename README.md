# Tmux-Packet-Loss

Displays % packet loss to the selected host, the default is to use weighted
average, giving more current checks greater emphasis.

## Recent changes

- Fixed boolean param handling to also allow for yes/no true/false
- Renamed variables and defaults to match the tmux option names
- Refactored code into more task isolated modules

## Screenshots

Be aware this uses my compact prefix & suffix settings! Partial status bar config `#{battery_smart}#{packet_loss}%a %h-%d %H:%M`

Plugin output takes no space when under @packet-loss-level_disp level



### Loss levels

| Display | With hist avg | Status|
| - | - | - |
| ![no_loss  ](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png) | ![no_loss_h](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png)   | under threshold |
| ![lvl_low  ](https://user-images.githubusercontent.com/5046648/215364078-e139daf0-d224-4275-afe2-6f3894420630.png) | ![lvl_low_h](https://user-images.githubusercontent.com/5046648/215363685-eaf8bc66-44f6-461b-83f1-0b3c16e76869.png)   | low level losses |
| ![level_alert](https://user-images.githubusercontent.com/5046648/215363408-4b043df3-fcd3-46d7-a3fa-6c3698806955.png) | ![level_alert_h](https://user-images.githubusercontent.com/5046648/215363791-c1ca0731-57d5-4f34-a580-896b22fbf76b.png) | alert level losses |
| ![level_crit ](https://user-images.githubusercontent.com/5046648/215363311-0c925d11-c015-45df-8143-460d2f9d9ec8.png) | ![level_crit_h](https://user-images.githubusercontent.com/5046648/215363877-01509d06-f58e-442a-9ebf-06b80688dd7c.png)  | critical level losses |

### Trends

If @packet-loss-display_trend is 1, change since the previous check is indicated with a prefix character

| Display | Status |
| - | - |
|![incr  ](https://user-images.githubusercontent.com/5046648/226140494-1715b5fa-61fe-4583-a9d4-d0c94c5ff63d.png) | Increasing |
|![stable](https://user-images.githubusercontent.com/5046648/226140512-fdd824bc-fcd0-4d5e-b960-eb5ec043e190.png) | Stable     |
|![decr  ](https://user-images.githubusercontent.com/5046648/226140473-94032422-c028-4ffd-96ef-da8aade23460.png) | Decreasing |

## Operation

This plugin runs a background process using repeated runs of ping to
determine % package loss. The loss level is by default calculated as a weighted average
of the stored data points, making the latest checks stand out.

On modern tmux versions, this background process is terminated when tmux
exits, see Tmux Compatibility for more details about versions and
limitations when it comes to shutting down this background process.

As the plugin is initialized, it will terminate any already running
background process, and start a new one.

Each time packet_loss.sh is run, if the DB is missing or 
the monitor background process hasn't been updated for a minute, 
the monitor is restarted, So an accidental stop of the monitor 
should in all normal cases be  self-healing.

If the monitor experiences errors, packet loss of 101% or higher are
reported.

| Result | Explanation |
| -|- |
| 101 | Failed to find % loss in ping output. Temporary issue.  Some pings don't report loss % if there is no connection to the host. They just report `ping: sendto: Host is unreachable` |
| 201 | Could not parse output. This condition is unlikely to self-correct.  If you file the output of `ping -c 5 8.8.4.4` as an Issue and also mention what Operating System this is and any other factors you think are relevant, I will try to fix it by including parsing of that output format. |

## Dependencies

`tmux 1.9` `sqlite3`

## Tmux Compatibility

| Version    | Notice |
|-|-|
| 3.0 >=     | The Background process is shut down when tmux exits using a session-closed hook with an array suffix. |
| 2.4 - 2.9  | Will shut down the background process, but since hooks don't support arrays, binding to session-closed might interfere with other stuff using the same hook. |
| 1.9 - 2.3  | session-closed hook not available. If you want to kill the background monitoring process after tmux shutdown, you need to add something like `~/.tmux/plugins/tmux-packet-loss/packet-loss.tmux stop` to a script starting tmux. If you run tmux most of the time, you can just leave the process running. |

## Verified to work in the following environments

Tested to make sure ps and ping parameters and output are interpreted correctly.

`Linux`

`MacOS`

`iSH`

`Windows Subsystem for Linux (WSL)`

## Installation

### Installation with [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to the list of TPM plugins in `.tmux.conf`:

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

Reload TMUX environment with `$ tmux source-file ~/.tmux.conf` - that's it!

## Supported Format Strings

| Code           | Action |
|-|-|
| `#{packet_loss}` | Displays average packet loss % if at or above @packet-loss-level_disp |

## Variables

| Variable                      | Default       | Purpose |
|-|-|-|
| @packet-loss-ping_host        | 8.8.4.4       | What host to ping |
| @packet-loss-ping_count       | 6             | This many pings per statistics update. |
| @packet-loss-history_size     | 6             | How many results should be kept when calculating average loss<br> 6 pings per check take 5 seconds so 6 here means 5 * 6 thus 30 seconds of loss history<br> I would recommend keeping it low since it will in most cases be more interesting to see current status over the long-term average.<br> For a longer-term historical overview, it is probably better to use `@packet-loss-hist_avg_display` |
||||
| @packet-loss-weighted_average | yes             | yes = Use weighted average focusing on the latest data points<br> no = Average over all data points |
| @packet-loss-display_trend    | no            | yes = Display trend with + prefix if the level is higher than last displayed and - prefix if lower<br> no = Do not display trend |
| @packet-loss-level_disp       | 1             | Display loss if this or higher level |
| @packet-loss-level_alert      | 18            | Color loss with color_alert if at or above this level.<br> Suggestion: set this to one higher than the % that is one loss in one update, this way, a single packet loss never triggers an alert, even initially. |
| @packet-loss-level_crit       | 40            | Color loss with color_crit if at or above this level |
||||
| @packet-loss-hist_avg_display | no            | yes = Also show historical average when current losses are displayed<br> no - No historical average is displayed |
| @packet-loss-hist_avg_minutes | 30            | Minutes to keep historical average |
| @packet-loss-hist_separator   | '\~'           | Separator current/historical losses. |
||||
| @packet-loss-color_alert      | colour226     | (bright yellow) Use this color if the loss is at or above @packet-loss-level_alert |
| @packet-loss-color_crit       | colour196     | (bright red) Use this color if the loss is at or above @packet-loss-level_crit |
| @packet-loss-color_bg         | black         | bg color when alert/crit colors are used in display |
||||
| @packet-loss-prefix           | ' pkt loss: ' | Prefix for status when displayed |
| @packet-loss-suffix           | ' '           | Suffix for status when displayed |
||||
| @packet-loss-hook_idx         | 41            | Index for session-closed hook, only needs changing if it collides with other usages of session-closed using this index, check with `tmux show-hooks -g \| grep session-closed` |

## My config

```tmux
set -g @packet-loss-display_trend     yes

set -g @packet-loss-color_alert colour21
set -g @packet-loss-color_bg    colour226

set -g @packet-loss-prefix '|'
set -g @packet-loss-suffix '|'
```

## Content in data folder

If missing this folder will be re-created and the database will be created in this location

- db_restarted.log - timestamps for each time `scripts/packet_loss.sh` decided to restart `scripts/monitor_packet_loss.sh`
- monitor.pid - pid for currently running `scripts/monitor_packet_loss.sh`
- packet_loss.sqlite - sqlite3 db for loss statistics

## Balancing it

By using a higher ping count you get a clearer picture of the current situation.
If you only check 2 packets per round, the only results would be 0%, 50%
or 100%. The higher the ping count, the more nuanced the result will be per check.
But over a certain limit, the time taken for each test will delay reporting
until it's not representative of the current link status, assuming you
are focusing on that.

You are recommended to also consider changing status-interval to ensure that
the update rate for this plugin in the status bar is relevant to your reporting needs.

Since ping is instantaneous it can be set to one lower than
`@packet-loss-ping_count`. 
Then sampling and reporting would be more or less in sync.

```tmux
set -g status-interval 5
```

## Nerdy stuff

All timestamps in the DB use generic time i.e. in most cases UTC.
Not having to bother with timezones simplifies the code, since DB times
are not displayed.

If @packet-loss-weighted_average is set to yes (the default) losses
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

There are three tables in the DB
| table | Description |
| -|- |
| t_loss | Contains the current loss statuses |
| t_1_min   | Keeps all samples from the last minute, to feed one-minute averages to the t_stats table |
| t_stats  | Keeps one-minute averages for the last @packet-loss-hist_avg_minutes minutes |

Each table contains two fields, time_stamp, and value. The time_stamp field is only used to purge old data.

## Contributing

Contributions are welcome, and they're appreciated.
Every little bit helps, and credit is always given.

The best way to send feedback is to file an issue at [tmux-packet-loss/issues](https://github.com/jaclu/tmux-packet-loss/issues)

### License

[MIT](LICENSE.md)
