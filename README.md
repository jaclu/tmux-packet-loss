# tmux-packet-loss

Displays % packet loss to selected host

## Operation

Only appears if losses are at or above threshold level. Convenient way to see if there are connectivity issues.

This plugin runs a background process using repeated runs of ping to evaluate % package loss. On modern tmux versions this background process is terminated when tmux exits, see Tmux Compatibility for more details about versions and limitations.

## Dependencies

`tmux 1.9` - will shutdown background process for tmux 2.4 or higher.<br>
`sqlite3`

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

| Code           | Action                                                        |
| -------------- | ------------------------------------------------------------- |
| #{packet_loss} | Displays packet loss % if at or above @packet-loss_level_disp |

## Variables

To disable a setting, set it to " ", spaces will be trimmed and thus nothing will end up being printed, if you set it to "" it will be ignored and the default value will be used.

| Variable                  | Default       | Purpose                                                             |
| ------------------------- | ------------- | ------------------------------------------------------------------- |
| @packet-loss-ping_host    | 8.8.4.4       | What host to ping                                                   |
| @packet-loss-ping_count   | 10            | This many pings per statistics update.                              |
|                           |               |
| @packet-loss-history_size | 100           | How many ping results should be kept, for calculating average loss. |
|                           |               |
| @packet-loss_level_disp   | 0.1           | Display loss if this or higher level                                |
| @packet-loss_level_alert  | 2.0           | Color loss with color_alert                                         |
| @packet-loss_level_crit   | 8.0           | Color loss with color_crit                                          |
|                           |               |
| @packet-loss_color_alert  | yellow        | Use this color if loss is at or above @packet-loss_level_alert      |
| @packet-loss_color_crit   | red           | Use this color if loss is at or above @packet-loss_level_crit       |
| @packet-loss_color_bg     | black         | bg color when alert/crit colors are used in display                 |
|                           |               |
| @packet-loss_prefix       | " pkt loss: " | Prefix for status when displayed                                    |
| @packet-loss_suffix       | " "           | Suffix for status when displayed                                    |

## My config and resulting outputs

```
set -g @packet-loss-ping_count "5"
set -g @packet-loss_level_alert "1.7"
set -g @packet-loss_color_alert "colour181"
set -g @packet-loss_prefix "|"
set -g @packet-loss_suffix "| "

# Partial statusbar config, takes no place when under threshold
# @packet-loss-suffix ensures spacing to date when something is displayed
...#{battery_smart} #{packet_loss}%a %h-%d %H:%M ...
```

| Display                                                                                                            | Status              |
| ------------------------------------------------------------------------------------------------------------------ | ------------------- |
| ![no_loss](https://user-images.githubusercontent.com/5046648/159600959-23efe878-e28c-4988-86df-b43875701f6a.png)   | under threshold     |
| ![lvl_low](https://user-images.githubusercontent.com/5046648/159604267-3345f827-3541-49f7-aec7-6f0091e59a5f.png)   | low loss level      |
| ![lvl_alert](https://user-images.githubusercontent.com/5046648/159602048-90346c8c-396a-4f0b-be26-152ef13c806f.png) | alert loss level    |
| ![lvl_crit](https://user-images.githubusercontent.com/5046648/159601876-9f097499-3fb9-4c53-8490-759665ff555f.png)  | critical loss level |

## Contributing

Contributions are welcome, and they are greatly appreciated! Every little bit helps, and credit will always be given.

The best way to send feedback is to file an issue at https://github.com/jaclu/tmux-packet-loss/issues

##### License

[MIT](LICENSE.md)
