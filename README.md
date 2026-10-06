# omarchy-sms

An SMS inbox for [Omarchy](https://omarchy.org/), for any modem driven by
ModemManager.

- **Bar icon:** an envelope `󰇮` with the number of unread messages.
- **Popup:** messages, newest first, with sender and time, plus **copy** and **delete** buttons. Opening the popup marks everything as read.
- **Sending:** **New message** (`󰏫`) in the header and **Reply** (`󰑚`) on messages from phone numbers. The message goes through ModemManager over D-Bus (`Messaging.Create` + `Sms.Send`), and a copy appears in the list as outgoing (`→`).
- **Background service (`omarchy-sms-store`):** listens to ModemManager over D-Bus, saves every received SMS to `~/.local/share/omarchy-sms/messages/<id>.json`, and shows a desktop notification. It waits until multipart messages are fully assembled and picks up messages that arrived while it wasn't running. It only reads from ModemManager and never deletes, so it needs no extra privileges.

ModemManager itself keeps SMS only in memory for modems without SIM/modem
storage (for example XMM7360/L850-GL with the
[xmm7360-lte](https://github.com/sbtasm-cmd/xmm7360-lte) fix), so they'd be
lost on its restart. The service is what makes them persistent.

## Install

```sh
omarchy plugin add https://github.com/sbtasm-cmd/omarchy-sms.git --enable
~/.config/omarchy/plugins/xmm7360.sms/bin/install-service
```

`install-service` links `systemd/omarchy-sms-store.service` into
`~/.config/systemd/user/`, then enables and starts it. No root is needed.

## Command line

```sh
~/.config/omarchy/plugins/xmm7360.sms/bin/sms list          # JSON, newest first
~/.config/omarchy/plugins/xmm7360.sms/bin/sms read --all
~/.config/omarchy/plugins/xmm7360.sms/bin/sms delete <id>
~/.config/omarchy/plugins/xmm7360.sms/bin/sms send +380XXXXXXXXX 'text'
journalctl --user -u omarchy-sms-store                      # service log
```

## Requirements

- ModemManager with SMS support for your modem (`mmcli -m any --messaging-status`).
- Python 3 with PyGObject (`python-gobject`), `notify-send` (libnotify), and `wl-copy`.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `5` | How often the widget rereads the message store |
| `hideWhenEmpty` | `false` | Hide the icon when there are no messages |

## License

GPL-2.0-or-later
