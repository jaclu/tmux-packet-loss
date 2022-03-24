# tmux-packet-loss

Displays % packet loss to selected host

## Operation

Only appears if losses are at or above threshold level. Convenient way to see if there are connectivity issues.

This plugin runs a background process using repeated runs of ping to evaluate % package loss. Loss level is calculated as the average of the stored data points.

On modern tmux versions this background process is terminated when tmux exits, see Tmux Compatibility for more details about versions and limitations.

## Dependencies

`tmux 1.9`

`sqlite3`

## Verified to work in the following envrionments

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
| 3.0 <=    | Background process is shut down when tmux exits using session-closed hook with an array suffix.                                                                                                                     |
| 2.4 - 2.9 | Will shut down background process, but since hooks doesn't support arrays, binding to session-closed might interfere with other stuff using the same hook.                                                          |
| 1.9 - 2.3 | session-closed hook not available. If you want to kill of the background monitoring process after tmux shutdown, you need to add `~/.tmux/plugins/tmux-packet-loss/packet-loss.tmux stop` to a script starting tmux |

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
| @packet-loss-history_size | 10            | How many results should be kept<br>when calculating average loss.<br>I would recomend to keep it low, since it will<br>in most cases be more interesting to see <br>current status over long-term average. |
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

# Partial statusbar config, takes no place when under threshold
# @packet-loss-suffix ensures spacing to date when something is displayed
...#{battery_smart} #{packet_loss}%a %h-%d %H:%M ...
```

| Display                                                                                                            | Status                |
| ------------------------------------------------------------------------------------------------------------------ | --------------------- |
| ![no_loss](https://user-images.githubusercontent.com/5046648/159600959-23efe878-e28c-4988-86df-b43875701f6a.png)   | under threshold       |
| ![lvl_low](https://user-images.githubusercontent.com/5046648/159604267-3345f827-3541-49f7-aec7-6f0091e59a5f.png)   | low level losses      |
| ![lvl_alert](https://user-images.githubusercontent.com/5046648/159602048-90346c8c-396a-4f0b-be26-152ef13c806f.png) | alert level losses    |
| ![lvl_crit](https://user-images.githubusercontent.com/5046648/159601876-9f097499-3fb9-4c53-8490-759665ff555f.png)  | critical level losses |

## Nerdy stuff

When deciding on how long history you want for loss statistics, the two params of importance are:

-   @packet-loss-ping_count - Since normally ping is almost instantaneous if this is set to 10 it in practical terms means you will get an average loss saved every 9 seconds if the host is responding. It will be longer if there are any dropped packets or other timeouts.
-   @packet-loss-history_size - how many samples are kept

So multiplying (ping_count - 1) with history_size should give an aproximate length in seconds for the time-span the average is calculated over.

You can check the DB to get the timestamp for oldest kept record by doing:

```
sqlite3 ~/.tmux/plugins/tmux-packet-loss/scripts/packet_loss.sqlite 'select * from packet_loss limit 1'
```

## Contributing

Contributions are welcome, and they are greatly appreciated! Every little bit helps, and credit will always be given.

The best way to send feedback is to file an issue at https://github.com/jaclu/tmux-packet-loss/issues

##### License

[MIT](LICENSE.md)
