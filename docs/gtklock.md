# gtklock on Sway

The installer requires and verifies `gtklock` for the Sway lock screen. If the
package is unavailable or cannot be installed from the enabled repositories,
the package stage reports a required failure instead of silently configuring a
different lock screen. `swaylock` may remain installed for other user choices,
but this project's lock helper never launches it.

## What gets configured

- `Super + Ctrl + L`, `Super + Ctrl + Shift + L`, and `Ctrl + Alt + L` call
  `~/.local/bin/lock-screen.sh`.
- Sway locks after 30 minutes idle and runs the same lock helper before sleep.
  This also covers suspend requests made by Sway's power menu and suspend key.
- The helper first verifies that it is running inside an active Sway session.
  Outside Sway it exits without launching a locker. GTKlock is not registered
  with GNOME, GDM, GNOME autostart, or a global service.
- The helper uses the image currently passed to `swaybg`. If it cannot find
  that image, it tries the project's installed `IMG1.jpg` / `IMG2.jpg`, then
  the first supported image in `~/Pictures`.
- The first setup creates `~/.config/gtklock/config.ini` and `style.css` with
  Adwaita Dark, a 24-hour clock, a full date, and a transparent style. Existing
  gtklock files are preserved; edit them to customize the lock screen.

The lock helper, idle-hook manager, and defaults are
`sway/.local/bin/lock-screen.sh`, `sway/.local/bin/start-swayidle.sh`, and
`sway/.local/bin/setup-gtklock.sh`. Run setup manually as your user with:

```sh
~/.local/bin/setup-gtklock.sh
```

## Test and scope

Log into a Sway session, then use a Sway lock shortcut to test the helper.
Sway's existing `swayidle` process uses the same helper after 30 minutes and
before sleep; its one-hour suspend timeout is preserved. GTKlock does not
replace GNOME Shell's native lock screen or GDM's pre-login screen. The
installer does not change the selected display manager, GNOME settings,
lid-close policy, or configured power actions.
