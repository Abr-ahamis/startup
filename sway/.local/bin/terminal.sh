#!/bin/bash

gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false

PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")

gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/pro>
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/pro>
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/pro>
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/pro>

systemctl --user daemon-reload

systemctl --user start battery-monitor.service

