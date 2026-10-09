# gtklock on Sway

The installer configures gtklock as the Sway session lock screen when the
package is available from the enabled repositories. It keeps `swaylock`
installed and uses it as a fallback. gtklock is optional so systems without a
package do not lose the existing lock behavior.

## What gets configured

- `Super + Ctrl + L`, `Super + Ctrl + Shift + L`, and `Ctrl + Alt + L` call
  `~/.local/bin/lock-screen.sh`.
- Sway locks after 30 minutes idle and runs the same lock helper before sleep.
  This also covers suspend requests made by Sway's power menu and suspend key.
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

Log into a Sway session, then run `~/.local/bin/lock-screen.sh` or use a Sway
lock shortcut. Test suspend and wake after confirming the manual lock works. The session must be
Sway (or another compatible wlroots compositor); gtklock does not replace
GNOME Shell's lock screen or GDM's pre-login screen. GNOME continues to use its
own lock behavior. Reboot and shutdown screens are controlled by the boot and
display-manager themes, not gtklock.

If gtklock is unavailable or fails to install, the helper uses swaylock. The
fallback still uses the selected wallpaper, but it does not provide gtklock's
clock/date appearance. The installer does not change lid-close policy or the
configured power actions.
