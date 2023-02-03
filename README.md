# Tmux-Packet-Loss

Displays % packet loss to the selected host, default is to use weighted
average, to give the last couple of checks greater emphasis.

## Recent changes

- Added @packet-loss_hist_separator to select separator, and alert/crit colors to hist average if it is high
- results are rounded to ints
- Added historical average
- Added @packet-loss_hook_idx in order to easily change it in case
    of collisions
- Updated Readme to match the current defaults
- If monitor isn't running, it's restarted by check_packet_loss.sh

## Screenshots

Partial status bar config, this plugins output takes no space when under
@packet-loss_level_disp

Be aware this uses my compact prefix & sufix!

... #{battery_smart}#{packet_loss}%a %h-%d %H:%M ...

| Display | With hist avg | Status
| - | - | - |
| ![no_loss](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png) | ![no_loss_h](https://user-images.githubusercontent.com/5046648/215356290-3155afac-c14f-4f92-9a9a-13752e396410.png)   | under threshold       |
| ![lvl_low](https://user-images.githubusercontent.com/5046648/215364078-e139daf0-d224-4275-afe2-6f3894420630.png) | ![lvl_low_h](https://user-images.githubusercontent.com/5046648/215363685-eaf8bc66-44f6-461b-83f1-0b3c16e76869.png)   | low level losses      |
| ![lvl_alert](https://user-images.githubusercontent.com/5046648/215363408-4b043df3-fcd3-46d7-a3fa-6c3698806955.png) | ![lvl_alert_h](https://user-images.githubusercontent.com/5046648/215363791-c1ca0731-57d5-4f34-a580-896b22fbf76b.png) | alert level losses    |
| ![lvl_crit](https://user-images.githubusercontent.com/5046648/215363311-0c925d11-c015-45df-8143-460d2f9d9ec8.png) | ![lvl_crit_h](https://user-images.githubusercontent.com/5046648/215363877-01509d06-f58e-442a-9ebf-06b80688dd7c.png)  | critical level losses |

## Operation

Appears if losses are at or above the threshold level.
A convenient way to see if there are connectivity issues.

If @packet-loss_hist_avg_display is 1, then when losses are displayed,
the historical average losses are also displayed.
How far back the historical average goes is set with @packet-loss_hist_avg_minutes

This plugin runs a background process using repeated runs of ping to
determine % package loss. Loss level is calculated as a weighted average
of the stored data points, making the latest checks stand out.
Past the decline point, the average of all samples is used.

On modern tmux versions, this background process is terminated when tmux
exits, see Tmux Compatibility for more details about versions and
limitations when it comes to shutting down this background process.

As the plugin is initialized, it will terminate any already running
background process, and start a new one.

Each time check_packet_loss.sh is run, if the monitor background process
is not running it is started, so should in all normal cases be self
healing.

If the monitor experiences errors, packet loss of 101% or higher are
reported.

Result | Explanation
-|-
101 | Failed to find % loss in ping output.  Temporary issue.<br /> Some pings don't report loss % if there is no connection to host.<br> They just report `ping: sendto: Host is unreachable`
201 | Could not parse output.  This condition is unlikely to self correct.<br /> If you file the output of `ping -c 5 8.8.4.4` as an Issue and also mention what Operating System this is and any other factors you think are relevant, I will try to fix it by including parsing of that output format.

## Dependencies

`tmux 1.9` `sqlite3`

## Tmux Compatibility

Version    | Notice
-|-
3.0 >=     | Background process is shut down when tmux exits using a session-closed hook with an array suffix.
2.4 - 2.9  | Will shut down background process, but since hooks doesn't support arrays, binding to session-closed might interfere with other stuff using the same hook.
1.9 - 2.3  | session-closed hook not available. If you want to kill the background monitoring process after tmux shutdown, you need to add `~/.tmux/plugins/tmux-packet-loss/packet-loss.tmux stop` to a script starting tmux. If you run tmux most of the time, you can just leave the process running.

## Verified to work in the following environments

Tested to make sure ps and ping parameters and output are interpreted correctly.

`MacOS`

`Linux`

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

Code           | Action
-|-
`#{packet_loss}` | Displays average packet loss % if at or above @packet-loss_level_disp

## Variables

Variable                      | Default       | Purpose
-|-|-
@packet-loss-ping_host        | 8.8.4.4       | What host to ping
@packet-loss-ping_count       | 6             | This many pings per statistics update.
@packet-loss-history_size     | 6             | How many results should be kept when calculating average loss.<br>I would recommend keeping it low since it will in most cases be more interesting to see current status over the long-term average. For long-term historical data it is probably better to use @packet-loss_hist_avg_display. 6 pings per check takes 5 secs so 6 here means 5 * 6 thus 30 seconds of ping history
||
@packet-loss_weighted_average | 1             | 1 = Use weighted average focusing on the latest data points<br> 0 = Average over all data points
@packet-loss_level_disp       | 1             | Display loss if this or higher level
@packet-loss_level_alert      | 18            | Color loss with color_alert
@packet-loss_level_crit       | 40            | Color loss with color_crit
||
@packet-loss_hist_avg_display | 0             | 1 = Also show historical average when current losses are displayed
@packet-loss_hist_avg_minutes | 30            | Minutes to keep historical average
@packet-loss_hist_separator   | ~             | Separator current/historical losses. Be aware that if you set it to a special char, you need to prefix it with backslash!
||
@packet-loss_color_alert      | yellow        | Use this color if loss is at or above @packet-loss_level_alert
@packet-loss_color_crit       | red           | Use this color if loss is at or above @packet-loss_level_crit
@packet-loss_color_bg         | black         | bg color when alert/crit colors are used in display
||
@packet-loss_prefix           | " pkt loss: " | Prefix for status when displayed
@packet-loss_suffix           | " "           | Suffix for status when displayed
||
@packet-loss_hook_idx         | 41            | Index for session-closed hook, only needs changing if it collides with other usages of session-closed using this index

## My config

I keep a slightly larger history.
Since I do 6 pings per run, one lost is 16.67%.
Alert level is set so that a single packet lost is not displayed as an
alert, and I filter our low loss levels entirely.
I display the historical average.
I use more compact prefix & suffix settings.

```tmux
set -g @packet-loss-history_size 7
set -g @packet-loss_level_alert 18
set -g @packet-loss_level_disp 4
set -g @packet-loss_hist_avg_display 1
set -g @packet-loss_prefix |
set -g @packet-loss_suffix |

```

## Balancing it

There is no point in getting updates more often than you update your
status bar. By using a higher ping count you also get a better statistical
analysis of the situation. If you only check 2 packets per round,
the only results would be 0%, 50% or 100% The higher the ping count,
the more nuanced the result will be. But, over a certain limit,
the time for each test will delay reporting until it's not representative
of the current link status, assuming you are focusing on that.

Since ping is close to instantaneous, to match reporting with
status bar updates, ping count is recommended to be set to one higher.
If they're the same, reporting drift over time,
and you generate updates that you never see in the first place.
Not that big of a deal, but by setting ping count to one higher,
they more or less match in update frequency,
and you get one more data point per update.

| status-interval | @packet-loss-ping_count |
| --------------- | ----------------------- |
| 5               | 6                       |
| 10              | 11                      |
| 15              | 16                      |
| ...             | ...                     |

You are recommended to also consider changing status-interval to keep
the update rate for this plugin relevant to your reporting needs.

```tmux
set -g status-interval 10
```

## Nerdy stuff

All timestamps use generic time ie in most cases UTC, since DB times are
not displayed, and this saves tons of typing, not having to cast
everything to localtime eveywhere.

If @packet-loss_weighted_average is set to 1 (the default) losses
are displayed as the largest of:

1. last value
1. avg of last 2
1. avg of last 3
1. avg of last 4
1. avg of last 5
1. avg of last 6
1. avg of last 7
1. avg of all

You can inspect the DB to get all timestamps & losses by running:

```bash
sqlite3 ~/.tmux/plugins/tmux-packet-loss/data/packet_loss.sqlite 'select * from packet_loss Order By Rowid asc'
```

You can inspect the DB to get the timestamp for the oldest kept record
by running:

```bash
sqlite3 ~/.tmux/plugins/tmux-packet-loss/data/packet_loss.sqlite 'select * from packet_loss limit 1'
```

## Contributing

Contributions are welcome, and they're appreciated.
Every little bit helps, and a credit is always be given.

The best way to send feedback is to file an issue at https://github.com/jaclu/tmux-packet-loss/issues

### License

[MIT](LICENSE.md)
