# Qt apps pick palette + fonts from ~/.config/qt6ct (Catppuccin Mocha).
# Set before sway starts so every app inherits it; qs-session copies it into
# the systemd user environment for services (gpg-agent -> pinentry-qt).
export QT_QPA_PLATFORMTHEME=qt6ct

if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]]; then
  exec sway
fi
