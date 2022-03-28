# tmux-packet-loss

Displays % packet loss to the selected host

## Operation

Only appears if losses are at or above the threshold level. A convenient way to see if there are connectivity issues.

This plugin runs a background process using repeated runs of ping to evaluate % package loss. Loss level is calculated as a weighted average of the stored data points, making the latest few checks stand out. Past the decline point, the average of all samples is used.

On modern tmux versions, this background process is terminated when tmux exits, see Tmux Compatibility for more details about versions and limitations when it comes to shutting down this background process.

## Dependencies

`tmux 1.9`

`sqlite3`

## Verified to work in the following environments

Tested to make sure ps and ping parameters are interpreted correctly

`MacOS`
`Linux`
`iSH`
`Windows Subsystem for Linux (WSL)`

## Install

### Installation with [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to the list of TPM plugins in `.tmux.conf`:

    set -g @plugin 'jaclu/tmux-packet-loss'

Hit `prefix + I` to fetch the plugin and source it. That's it!

### Manual Installation

Clone the repository:

    $ git clone https://github.com/jaclu/tmux-packet-loss.git ~/clone/path

Add this line to the bottom of `.tmux.conf`:

    run-shell ~/clone/path/packet-loss.tmux

Reload TMUX environment with `$ tmux source-file ~/.tmux.conf`, and that's it.

## Tmux Compatibility

| Version   | Notice                                                                                                                                                                                                              |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 3.0 <=    | Background process is shut down when tmux exits using a session-closed hook with an array suffix.                                                                                                                     |
| 2.4 - 2.9 | Will shut down background process, but since hooks don't support arrays, binding to session-closed might interfere with other stuff using the same hook.                                                          |
| 1.9 - 2.3 | session-closed hook not available. If you want to kill the background monitoring process after tmux shutdown, you need to add `~/.tmux/plugins/tmux-packet-loss/packet-loss.tmux stop` to a script starting tmux |

## Supported Format Strings

| Code           | Action                                                                |
| -------------- | --------------------------------------------------------------------- |
| #{packet_loss} | Displays average packet loss % if at or above @packet-loss_level_disp |

## Variables

| Variable                  | Default       | Purpose                                                                                                                                                                                                     |
| ------------------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| @packet-loss-ping_host    | 8.8.4.4       | What host to ping                                                                                                                                                                                           |
| @packet-loss-ping_count   | 6             | This many pings per statistics update.                                                                                                                                                                      |
|                           |               |
| @packet-loss-history_size | 6             | How many results should be kept<br>when calculating average loss.<br>I would recommend keeping it low since it will<br>in most cases be more interesting to see <br>current status over the long-term average. |
|                           |               |
| @packet-loss_level_disp   | 0.1           | Display loss if this or higher level                                                                                                                                                                        |
| @packet-loss_level_alert  | 2.0           | Color loss with color_alert                                                                                                                                                                                 |
| @packet-loss_level_crit   | 8.0           | Color loss with color_crit                                                                                                                                                                                  |
|                           |               |
| @packet-loss_color_alert  | yellow        | Use this color if loss is at or above<br>@packet-loss_level_alert                                                                                                                                           |
| @packet-loss_color_crit   | red           | Use this color if loss is at or above<br>@packet-loss_level_crit                                                                                                                                            |
| @packet-loss_color_bg     | black         | bg color when alert/crit colors<br>are used in display                                                                                                                                                      |
|                           |               |
| @packet-loss_prefix       | " pkt loss: " | Prefix for status when displayed                                                                                                                                                                            |
| @packet-loss_suffix       | " "           | Suffix for status when displayed                                                                                                                                                                            |

## My config and sample outputs

```
set -g @packet-loss-ping_count "6"
set -g @packet-loss-history_size "10"
set -g @packet-loss_level_alert "1.7"
set -g @packet-loss_color_alert "colour181"
set -g @packet-loss_prefix "|"
set -g @packet-loss_suffix "| "

# Partial status bar config, this plugin takes no space when under @packet-loss_level_disp
# @packet-loss-suffix ensures spacing to date when something is displayed
...#{battery_smart} #{packet_loss}%a %h-%d %H:%M ...
```

| Display                                                                                                            | Status                |
| ------------------------------------------------------------------------------------------------------------------ | --------------------- |
| ![no_loss](https://user-images.githubusercontent.com/5046648/159600959-23efe878-e28c-4988-86df-b43875701f6a.png)   | under threshold       |
| ![lvl_low](https://user-images.githubusercontent.com/5046648/159604267-3345f827-3541-49f7-aec7-6f0091e59a5f.png)   | low level losses      |
| ![lvl_alert](https://user-images.githubusercontent.com/5046648/159602048-90346c8c-396a-4f0b-be26-152ef13c806f.png) | alert level losses    |
| ![lvl_crit](https://user-images.githubusercontent.com/5046648/159601876-9f097499-3fb9-4c53-8490-759665ff555f.png)  | critical level losses |

## Sample settings

### Quick turnaround

History of 30 seconds. Focuses on the current state. Due to the weighting of results, a given loss report will quickly decrease as it gets further back in history. High alert & crit levels increase the likelihood the warning will shrink below the alert levels as it ages. Further focusing attention on the current situation.

```
set -g @packet-loss-ping_count "6"
set -g @packet-loss-history_size "6"
set -g @packet-loss_level_alert "20"
set -g @packet-loss_color_crit "45"
```

### 5 minutes history gives a better understanding of average link quality

History of 5 minutes, will give you a better understanding of packet loss over time, but since it can not indicate when the last loss happened, it does not give much information about the current state of affairs. The weighted results will still make the latest few checks stand out, but once it passes this decline, the loss will remain the same until it is eventually pushed off the list of stored results.

```
set -g @packet-loss-ping_count "11"
set -g @packet-loss-history_size "30"
```

## Balancing it

There is no point in getting updates more often than you update your status bar. By using a higher ping count you also get a better statistical analysis of the situation. If you only check 2 packets per round, the only results would be 0%, 50% or 100% The higher the ping count, the more nuanced the result will be. But, over a certain limit, the time for each test will delay reporting until it is not representative of the current link status, assuming you are focusing on that.

Since ping is normally close to instantaneous, to match reporting with status bar updates, ping count is recommended to be set to one higher. If they are the same, reporting will quickly drift over time, and you will generate updates that you will never see in the first place. Not that big of a deal, but by setting ping count to one higher, they will more or less match in update frequency, and you will get one more data point per update!

| status-interval | @packet-loss-ping_count |
| --------------- | ----------------------- |
| 5               | 6                       |
| 10              | 11                      |
| 15              | 16                      |
| ...             | ...                     |

You are recommended to also consider changing status-interval to keep the update rate for this plugin relevant to your reporting needs.

```
set -g status-interval 10
```

## Nerdy Stuff

To give loss a declining history weighting, it is rounded to one decimal and displayed as the largest of:

1. last value
1. avg of last 2
1. avg of last 3
1. avg of last 4
1. avg of last 5
1. avg of last 6
1. avg of last 7
1. avg of all

It can be changed in scripts/check_packet_loss.sh around line 40

```
select round(
  max(
      (select loss from packet_loss Order By Rowid desc limit 1),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 2)),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 3)),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 4)),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 5)),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 6)),
      (select avg(loss) from(select loss from packet_loss Order By Rowid desc limit 7)),
      (select avg(loss) from packet_loss)
     )
  ,1)
```

You can check the DB to get the timestamp for the oldest kept record by running:

```
sqlite3 ~/.tmux/plugins/tmux-packet-loss/data/packet_loss.sqlite 'select * from packet_loss limit 1'
```

## Contributing

Contributions are welcome, and they are greatly appreciated! Every little bit helps, and a credit will always be given.

The best way to send feedback is to file an issue at https://github.com/jaclu/tmux-packet-loss/issues

##### License

[MIT](LICENSE.md)
