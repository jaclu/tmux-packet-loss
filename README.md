# tmux-packet-loss

Displays % packet loss to selected host

## Status

operational, but not fully documented yet

## Operation

This plugin runs a background process using repeated runs of ping to evaluate % package loss. On modern tmux versions this background process is terminated when tmux exits, see Tmux Compatibility for more details about versions and limitations.

## Dependencies

`tmux 1.9` - will shutdown background process for tmux 2.4 or higher.<br>
`sqlite3`

## Tmux Compatibility

| Version   | Notice                                                                                                                                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 3.0 >=    | Background process is shut down when tmux exits using session-closed hook with an array suffix.                                                                                                                   |
| 2.4 - 2.9 | Will shut down background process, but since hooks doesn't support arrays, binding to session-closed might interfere with other stuff using the same hook.                                                        |
| 2.4 <     | session-closed hook not available. If you want to kill of the background monitoring process after tmux shutdown, you need to add `.tmux/plugins/tmux-packet-loss/packet-loss.tmux stop` to a script starting tmux |

## Variables that can be set

To disable a setting, set it to " ", spaces will be trimmed and thus nothing will end up being printed, if you set it to "" it will be ignored and the default value will be used.

| Variable                 | Default       | Purpose                               |
| ------------------------ | ------------- | ------------------------------------- |
| @packet-loss-ping_host   | 8.8.4.4       | What host to ping                     |
| @packet-loss-ping_count  | 10            | this many pings per statistics update |
|                          |               |
| @packet-loss_level_disp  | 0.1           | Display loss if this or higher level  |
| @packet-loss_level_alert | 2.0           |
| @packet-loss_level_crit  | 8.0           | If % loss equals or is higher         |
|                          |               |
| @packet-loss_color_alert | yellow        |
| @packet-loss_color_crit  | red           |
| @packet-loss_color_bg    | black         |
|                          |               |
| @packet-loss_prefix      | " pkt loss: " | Prefix for the status                 |
| @packet-loss_suffix      | " "           | Suffix for the status                 |
