# tmux-packet-loss

Warns if there are packet losses

## Status

testing, works, but not documented yet

## Dependencies

`tmux 1.9` or higher

Sqlite3

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
